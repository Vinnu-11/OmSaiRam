import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
    writeBatch, serverTimestamp, Timestamp,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, getGroup, listMembers, listMyGroups, addMember, setMemberRole } from '../src/groups.mjs';
import { generateInviteToken, createInvitation, revokeInvitation, joinWithInvitation } from '../src/invitations.mjs';

const settings = localConfig();
let environment;
const dbFor = uid => environment.authenticatedContext(uid).firestore();
let groupId;
before(async () => {
    environment = await initializeTestEnvironment({
        projectId: settings.projectId,
        firestore: { ...settings.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    });
});
beforeEach(async () => {
    await environment.clearFirestore();
    for (const uid of ['owner', 'reader', 'other', 'outsider']) {
        await setDoc(doc(dbFor(uid), 'users', uid), {
            displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        });
    }
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Invitation Test' });
});
after(async () => { await environment?.cleanup(); });
const create = () => createInvitation(dbFor('owner'), groupId, 'owner');

async function forgedJoin(db, uid, token, { group = groupId, role = 'member', index = true, membership = true } = {}) {
    const batch = writeBatch(db);
    if (membership) batch.set(doc(db, 'groups', group, 'members', uid), {
        userId: uid, role, joinedAt: serverTimestamp(),
    });
    if (index) batch.set(doc(db, 'users', uid, 'groups', group), {
        groupId: group, joinedAt: serverTimestamp(), inviteToken: token,
    });
    return batch.commit();
}

test('admin creates a random expiring invitation and reader joins atomically', async () => {
    const token = await assertSucceeds(create());
    assert.match(token, /^[a-f0-9]{64}$/);
    assert.equal(await assertSucceeds(joinWithInvitation(dbFor('reader'), 'reader', token)), groupId);
    assert.equal((await getGroup(dbFor('reader'), groupId)).createdBy, 'owner');
    assert.equal((await listMyGroups(dbFor('reader'), 'reader'))[0].id, groupId);
    const reader = (await listMembers(dbFor('owner'), groupId)).find(member => member.userId === 'reader');
    assert.equal(reader.role, 'member');
    assert.equal(Object.hasOwn(reader, 'inviteToken'), false);
    await assertFails(getDoc(doc(dbFor('owner'), 'users/reader/groups', groupId)));
});

test('tokens are distinct and revocable independently', async () => {
    const first = await create();
    const second = await create();
    assert.notEqual(first, second);
    await revokeInvitation(dbFor('owner'), first);
    await assert.rejects(joinWithInvitation(dbFor('reader'), 'reader', first));
    await assertSucceeds(joinWithInvitation(dbFor('reader'), 'reader', second));
});

test('revocation prevents new joins but does not remove existing members', async () => {
    const token = await create();
    await joinWithInvitation(dbFor('reader'), 'reader', token);
    await revokeInvitation(dbFor('owner'), token);
    await assertSucceeds(getGroup(dbFor('reader'), groupId));
    await assertFails(forgedJoin(dbFor('other'), 'other', token));
});

test('a token supports multiple members until expiry or revocation', async () => {
    const token = await create();
    await assertSucceeds(joinWithInvitation(dbFor('reader'), 'reader', token));
    await assertSucceeds(joinWithInvitation(dbFor('other'), 'other', token));
    assert.equal((await listMembers(dbFor('owner'), groupId)).length, 3);
});

test('outsiders and members cannot create or revoke invitations; leads invite and revoke only their own', async () => {
    const token = await create();
    await addMember(dbFor('owner'), groupId, 'reader');
    for (const uid of ['outsider', 'reader']) {
        await assertFails(createInvitation(dbFor(uid), groupId, uid));
        await assertFails(revokeInvitation(dbFor(uid), token));
    }
    await setMemberRole(dbFor('owner'), groupId, 'reader', 'group_lead');
    const leadCode = await assertSucceeds(createInvitation(dbFor('reader'), groupId, 'reader', { code: true }));
    await assertFails(revokeInvitation(dbFor('reader'), token));
    await assertSucceeds(revokeInvitation(dbFor('reader'), leadCode));
    const second = await createInvitation(dbFor('reader'), groupId, 'reader', { code: true });
    await assertSucceeds(revokeInvitation(dbFor('owner'), second));
    await setMemberRole(dbFor('owner'), groupId, 'reader', 'member');
    await assertFails(createInvitation(dbFor('reader'), groupId, 'reader', { code: true }));
});

test('8-character codes join like long tokens; other short shapes are refused', async () => {
    const code = await assertSucceeds(createInvitation(dbFor('owner'), groupId, 'owner', { code: true }));
    assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
    assert.equal(await assertSucceeds(joinWithInvitation(dbFor('reader'), 'reader', code)), groupId);
    for (const bad of ['ABCDEFG1', 'ABCDEFGO', 'abcdefgh', 'ABCDEFG', 'ABCDEFGHJ']) {
        await assertFails(getDoc(doc(dbFor('other'), 'groupInvites', bad)));
        await assertFails(setDoc(doc(dbFor('owner'), 'groupInvites', bad), {
            groupId, createdBy: 'owner', createdAt: serverTimestamp(),
            expiresAt: Timestamp.fromMillis(Date.now() + 60000), active: true,
        }));
    }
});

test('invitation lookup requires authentication and cannot be enumerated', async () => {
    const token = await create();
    await assertSucceeds(getDoc(doc(dbFor('outsider'), 'groupInvites', token)));
    await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'groupInvites', token)));
    await assertFails(getDocs(collection(dbFor('owner'), 'groupInvites')));
});

test('unknown, malformed and missing-group tokens do not authorize joins', async () => {
    await assert.rejects(joinWithInvitation(dbFor('reader'), 'reader', 'ABC123'));
    await assert.rejects(joinWithInvitation(dbFor('reader'), 'reader', generateInviteToken()));
    await assertFails(forgedJoin(dbFor('reader'), 'reader', generateInviteToken()));
    await assertFails(createInvitation(dbFor('owner'), 'missing', 'owner'));
});

test('expired tokens are rejected by server rules even with a forged batch', async () => {
    const token = await create();
    // Privileged test fixture only, simulating time passage without sleeps.
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(doc(context.firestore(), 'groupInvites', token), { expiresAt: Timestamp.fromMillis(0) });
    });
    await assert.rejects(joinWithInvitation(dbFor('reader'), 'reader', token));
    await assertFails(forgedJoin(dbFor('reader'), 'reader', token));
});

test('tokens cannot grant a privileged role, join for someone else or target another group', async () => {
    const token = await create();
    for (const role of ['admin', 'group_lead']) {
        await assertFails(forgedJoin(dbFor('reader'), 'reader', token, { role }));
    }
    await assertFails(forgedJoin(dbFor('reader'), 'other', token));
    const otherGroup = await createGroup(dbFor('owner'), 'owner', { name: 'Other Group' });
    await assertFails(forgedJoin(dbFor('reader'), 'reader', token, { group: otherGroup }));
});

test('joining needs an existing profile and both membership documents', async () => {
    const token = await create();
    await assertFails(forgedJoin(dbFor('no-profile'), 'no-profile', token));
    await assertFails(forgedJoin(dbFor('reader'), 'reader', token, { index: false }));
    await assertFails(forgedJoin(dbFor('reader'), 'reader', token, { membership: false }));
});

test('repeat joins and simultaneous duplicate joins cannot overwrite membership', async () => {
    const token = await create();
    const results = await Promise.allSettled([
        joinWithInvitation(dbFor('reader'), 'reader', token),
        joinWithInvitation(dbFor('reader'), 'reader', token),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    await setMemberRole(dbFor('owner'), groupId, 'reader', 'group_lead');
    await assertFails(forgedJoin(dbFor('reader'), 'reader', token));
    assert.equal((await getDoc(doc(dbFor('owner'), 'groups', groupId, 'members/reader'))).data().role, 'group_lead');
});

test('invitation scope, expiry and creator are immutable and revoked tokens cannot reactivate', async () => {
    const token = await create();
    const reference = doc(dbFor('owner'), 'groupInvites', token);
    for (const changes of [
        { groupId: 'other' }, { createdBy: 'reader' },
        { expiresAt: Timestamp.fromMillis(Date.now() + 1000) }, { extra: true },
    ]) await assertFails(updateDoc(reference, changes));
    await assertFails(deleteDoc(reference));
    await revokeInvitation(dbFor('owner'), token);
    await assertFails(updateDoc(reference, { active: true }));
});

test('invitation creation validates schema, expiry bounds and creator at server', async () => {
    const base = () => ({
        groupId, createdBy: 'owner', createdAt: serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + 60000), active: true,
    });
    const db = dbFor('owner');
    for (const override of [
        { createdBy: 'reader' }, { active: false }, { extra: true },
        { expiresAt: Timestamp.fromMillis(0) },
        { expiresAt: Timestamp.fromMillis(Date.now() + 8 * 86400000) },
    ]) await assertFails(setDoc(doc(db, 'groupInvites', generateInviteToken()), { ...base(), ...override }));
    await assertFails(setDoc(doc(db, 'groupInvites/ABC123'), base()));
    await assert.rejects(createInvitation(db, groupId, 'owner', { lifetimeMs: 8 * 86400000 }));
});

test('a join racing revocation follows commit order and never permits subsequent joins', async () => {
    const token = await create();
    const [join, revoke] = await Promise.allSettled([
        joinWithInvitation(dbFor('reader'), 'reader', token),
        revokeInvitation(dbFor('owner'), token),
    ]);
    assert.equal(revoke.status, 'fulfilled');
    const members = await listMembers(dbFor('owner'), groupId);
    assert.equal(members.some(member => member.userId === 'reader'), join.status === 'fulfilled');
    await assertFails(forgedJoin(dbFor('other'), 'other', token));
});

test('nonadmins cannot mutate invitation scope or timestamps', async () => {
    const token = await create();
    for (const changes of [
        { groupId: 'other' }, { createdBy: 'reader' },
        { expiresAt: Timestamp.fromMillis(Date.now() + 60000) },
    ]) await assertFails(updateDoc(doc(dbFor('outsider'), 'groupInvites', token), changes));
});