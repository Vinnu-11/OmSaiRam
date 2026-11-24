import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, getDocFromServer, setDoc, updateDoc, deleteDoc, deleteField,
    writeBatch, serverTimestamp, Timestamp,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember } from '../src/groups.mjs';
import { createInvitation, joinWithInvitation } from '../src/invitations.mjs';
import { removeMember, restoreMember } from '../src/membership-lifecycle.mjs';
import { isAccountDeactivated, listOwnedGroups, setAccountDeactivated, deleteAccountData } from '../src/account-lifecycle.mjs';

// Non-clearing: unique IDs per test, existing emulator fixtures stay untouched.
const config = localConfig();
let environment, groupId, owner, member, outsider;
const connections = new Map();
const db = uid => {
    if (!connections.has(uid)) connections.set(uid,
        uid ? environment.authenticatedContext(uid).firestore() : environment.unauthenticatedContext().firestore());
    return connections.get(uid);
};
const account = (connection, uid) => doc(connection, 'users', uid);
const deactivate = () => ({ deactivatedAt: serverTimestamp(), updatedAt: serverTimestamp() });
const restore = () => ({ deactivatedAt: deleteField(), updatedAt: serverTimestamp() });
const profile = () => ({ displayName: 'Account QA', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
function handover(from, to, revision = 1) {
    const connection = db(from), batch = writeBatch(connection);
    batch.update(doc(connection, 'groups', groupId), {
        ownerUid: to, ownershipRevision: revision, ownershipChangedBy: from,
        ownershipChangedAt: serverTimestamp(), updatedAt: serverTimestamp()
    });
    batch.update(doc(connection, 'groups', groupId, 'members', from), { role: 'group_lead' });
    batch.update(doc(connection, 'groups', groupId, 'members', to), { role: 'admin' });
    batch.set(doc(connection, 'groups', groupId, 'ownershipChanges', String(revision)), {
        groupId, fromOwner: from, toOwner: to, revision, changedBy: from, changedAt: serverTimestamp()
    });
    return batch.commit();
}

before(async () => {
    environment = await initializeTestEnvironment({
        projectId: config.projectId,
        firestore: { ...config.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    });
});
beforeEach(async () => {
    [owner, member, outsider] = ['owner', 'member', 'outsider'].map(role => `account-qa-${randomUUID()}-${role}`);
    for (const uid of [owner, member, outsider]) await setDoc(doc(db(uid), 'users', uid), profile());
    groupId = await createGroup(db(owner), owner, { name: 'Account QA' });
    await addMember(db(owner), groupId, member);
});
after(async () => { await environment?.cleanup(); });

test('deactivate and restore are idempotent and retain the profile, membership and history', async () => {
    const original = (await getDocFromServer(account(db(member), member))).data();
    assert.equal(await isAccountDeactivated(db(member), member), false);
    assert.equal(await setAccountDeactivated(db(member), member, false), false);
    assert.equal(await setAccountDeactivated(db(member), member, true), true);
    assert.equal(await setAccountDeactivated(db(member), member, true), false);
    assert.equal(await isAccountDeactivated(db(member), member), true);
    const marked = (await getDocFromServer(account(db(member), member))).data();
    assert.deepEqual(Object.keys(marked).sort(), ['createdAt', 'deactivatedAt', 'displayName', 'updatedAt']);
    assert.ok(marked.deactivatedAt instanceof Timestamp);
    assert.ok(marked.createdAt.isEqual(original.createdAt));
    // Soft state only: private name, membership and discovery index all remain.
    assert.equal(marked.displayName, 'Account QA');
    assert.equal((await getDocFromServer(doc(db(owner), 'groups', groupId, 'members', member))).data().role, 'member');
    assert.equal((await getDocFromServer(doc(db(member), 'users', member, 'groups', groupId))).exists(), true);
    assert.equal(await setAccountDeactivated(db(member), member, false), true);
    // An active profile is always exactly the three original fields again.
    const restored = (await getDocFromServer(account(db(member), member))).data();
    assert.deepEqual(Object.keys(restored).sort(), ['createdAt', 'displayName', 'updatedAt']);
    assert.ok(restored.createdAt.isEqual(original.createdAt));
    assert.equal(await setAccountDeactivated(db(member), member, true), true);
    assert.equal(await isAccountDeactivated(db(member), member), true);
});

test('deactivation is blocked while a group is owned and allowed after an explicit handover', async () => {
    assert.deepEqual(await listOwnedGroups(db(owner), owner), [groupId]);
    await assert.rejects(setAccountDeactivated(db(owner), owner, true), /Transfer ownership of 1 group/);
    assert.equal(await isAccountDeactivated(db(owner), owner), false);
    await handover(owner, member);
    assert.deepEqual(await listOwnedGroups(db(owner), owner), []);
    assert.deepEqual(await listOwnedGroups(db(member), member), [groupId]);
    assert.equal(await setAccountDeactivated(db(owner), owner, true), true);
    await assert.rejects(setAccountDeactivated(db(member), member, true), /Transfer ownership/);
});

test('ownership cannot be handed to a deactivated account until it is restored', async () => {
    await setAccountDeactivated(db(member), member, true);
    await assertFails(handover(owner, member));
    assert.equal((await getDocFromServer(doc(db(owner), 'groups', groupId))).data().ownerUid, undefined);
    await setAccountDeactivated(db(member), member, false);
    await assertSucceeds(handover(owner, member));
});

test('deactivated accounts cannot create or join groups, be added or restored, or edit the private profile', async () => {
    const token = await createInvitation(db(owner), groupId, owner);
    await setAccountDeactivated(db(outsider), outsider, true);
    await assertFails(createGroup(db(outsider), outsider, { name: 'Denied' }));
    await assertFails(addMember(db(owner), groupId, outsider));
    await assertFails(joinWithInvitation(db(outsider), outsider, token));
    await assertFails(updateDoc(doc(db(outsider), 'users', outsider), { displayName: 'Denied', updatedAt: serverTimestamp() }));
    await removeMember(db(owner), groupId, owner, member);
    await setAccountDeactivated(db(member), member, true);
    await assertFails(restoreMember(db(owner), groupId, owner, member, 0));
    await setAccountDeactivated(db(member), member, false);
    await assertSucceeds(restoreMember(db(owner), groupId, owner, member, 0));
    await setAccountDeactivated(db(outsider), outsider, false);
    await assertSucceeds(updateDoc(doc(db(outsider), 'users', outsider), { displayName: 'Restored', updatedAt: serverTimestamp() }));
    await assertSucceeds(joinWithInvitation(db(outsider), outsider, token));
});

test('only the account owner can deactivate or restore; the profile is never deleted or listed', async () => {
    for (const uid of [owner, outsider, null]) {
        await assertFails(getDocFromServer(account(db(uid), member)));
        await assertFails(updateDoc(account(db(uid), member), deactivate()));
    }
    const forged = environment.authenticatedContext(owner, { admin: true }).firestore();
    await assertFails(updateDoc(account(forged, member), deactivate()));
    await setAccountDeactivated(db(member), member, true);
    for (const uid of [owner, outsider, null]) await assertFails(updateDoc(account(db(uid), member), restore()));
    for (const uid of [owner, outsider, null]) await assertFails(deleteDoc(account(db(uid), member)));
    const ghost = `account-qa-${randomUUID()}-ghost`;
    await assertFails(setDoc(account(db(ghost), ghost), { ...profile(), deactivatedAt: serverTimestamp() }));
    await assertFails(updateDoc(account(db(ghost), ghost), deactivate()));
});

test('raw writes cannot forge the marker time, rename while toggling, repeat or add fields', async () => {
    const reference = account(db(member), member);
    for (const invalid of [{ ...deactivate(), deactivatedAt: Timestamp.fromMillis(0) }, { ...deactivate(), deactivatedAt: true },
    { ...deactivate(), displayName: 'Renamed' }, { ...deactivate(), createdAt: serverTimestamp() },
    { ...deactivate(), extra: true }, { deactivatedAt: serverTimestamp() },
    { ...deactivate(), updatedAt: Timestamp.fromMillis(0) }]) {
        await assertFails(updateDoc(reference, invalid));
    }
    await assertSucceeds(updateDoc(reference, deactivate()));
    for (const invalid of [deactivate(), { displayName: 'Renamed', updatedAt: serverTimestamp() },
    { ...restore(), displayName: 'Renamed' }, { ...restore(), extra: true }, { deactivatedAt: deleteField() },
    { ...restore(), updatedAt: Timestamp.fromMillis(0) }, { ...restore(), createdAt: serverTimestamp() }]) {
        await assertFails(updateDoc(reference, invalid));
    }
    await assertSucceeds(updateDoc(reference, restore()));
    assert.deepEqual(Object.keys((await getDocFromServer(reference)).data()).sort(), ['createdAt', 'displayName', 'updatedAt']);
    await assertSucceeds(updateDoc(reference, { displayName: 'Renamed', updatedAt: serverTimestamp() }));
});

test('account data deletion leaves groups, removes private data and keeps content under the anonymous UID', async () => {
    const message = doc(db(member), 'groups', groupId, 'messages', `kept-${randomUUID()}`);
    await setDoc(message, { senderUid: member, text: 'Retained content', createdAt: serverTimestamp() });
    await setDoc(doc(db(member), 'groups', groupId, 'memberProfiles', member), profile());
    const settings = doc(db(member), 'users', member, 'settings', 'reminders');
    await setDoc(settings, {
        readingReminderEnabled: true, dailyVerseEnabled: false, reminderHour: 9,
        reminderMinute: 0, timezone: 'Asia/Kolkata', updatedAt: serverTimestamp()
    });
    assert.deepEqual(await deleteAccountData(db(member), member), []);
    for (const reference of [account(db(member), member), settings, doc(db(member), 'users', member, 'groups', groupId)]) {
        assert.equal((await getDocFromServer(reference)).exists(), false);
    }
    for (const path of ['members', 'memberProfiles']) {
        assert.equal((await getDocFromServer(doc(db(owner), 'groups', groupId, path, member))).exists(), false);
    }
    const marker = (await getDocFromServer(doc(db(owner), 'groups', groupId, 'departures', member))).data();
    assert.equal(marker.reason, 'left');
    const kept = (await getDocFromServer(doc(db(owner), 'groups', groupId, 'messages', message.id))).data();
    assert.deepEqual([kept.senderUid, kept.text], [member, 'Retained content']);
    // A repeat after a partial failure finds nothing left and still succeeds.
    assert.deepEqual(await deleteAccountData(db(member), member), []);
    await assertFails(getDocFromServer(doc(db(member), 'groups', groupId)));
});

test('account data deletion is blocked for owners and reports archived memberships it cannot leave', async () => {
    await assert.rejects(deleteAccountData(db(owner), owner), /Transfer ownership of 1 group/);
    assert.equal((await getDocFromServer(account(db(owner), owner))).exists(), true);
    await updateDoc(doc(db(owner), 'groups', groupId), {
        archived: true, lifecycleRevision: 1,
        lifecycleChangedBy: owner, lifecycleChangedAt: serverTimestamp(), updatedAt: serverTimestamp()
    });
    assert.deepEqual(await deleteAccountData(db(member), member), [groupId]);
    assert.equal((await getDocFromServer(account(db(member), member))).exists(), false);
    assert.equal((await getDocFromServer(doc(db(owner), 'groups', groupId, 'members', member))).exists(), true);
});
