import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
    writeBatch, serverTimestamp,
    query, limit,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, listMyGroups, getGroup, listMembers, addMember, setMemberRole, updateGroup } from '../src/groups.mjs';

const settings = localConfig();
let environment;
const dbFor = uid => environment.authenticatedContext(uid).firestore();
const groupData = () => ({
    name: 'Local Parayana', description: '', mode: 'chapter_wise', createdBy: 'owner',
    chaptersPerWeek: 2, startChapter: 1, currentWeek: 1,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});
before(async () => {
    environment = await initializeTestEnvironment({
        projectId: settings.projectId,
        firestore: { ...settings.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    });
});
beforeEach(async () => {
    await environment.clearFirestore();
    for (const uid of ['owner', 'reader', 'outsider']) {
        await setDoc(doc(dbFor(uid), 'users', uid), {
            displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        });
    }
});
after(async () => { await environment?.cleanup(); });
const create = () => createGroup(dbFor('owner'), 'owner', { name: 'Local Parayana' });

test('group creation atomically creates owner admin membership and discovery index', async () => {
    const id = await assertSucceeds(create());
    const group = await getGroup(dbFor('owner'), id);
    assert.equal(group.createdBy, 'owner');
    assert.equal(group.currentWeek, 1);
    assert.equal(group.chaptersPerWeek, 2);
    assert.equal((await listMembers(dbFor('owner'), id))[0].role, 'admin');
    assert.equal((await listMyGroups(dbFor('owner'), 'owner'))[0].id, id);
});

test('group cannot be created without membership and index in the same batch', async () => {
    const db = dbFor('owner');
    await assertFails(setDoc(doc(db, 'groups/incomplete'), groupData()));
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/incomplete'), groupData());
    batch.set(doc(db, 'groups/incomplete/members/owner'), { userId: 'owner', role: 'admin', joinedAt: serverTimestamp() });
    await assertFails(batch.commit());
});

test('creator identity cannot be forged and a profile is required', async () => {
    await assertFails(createGroup(dbFor('owner'), 'reader', { name: 'Forged' }));
    await assertFails(createGroup(dbFor('no-profile'), 'no-profile', { name: 'Missing profile' }));
    await assertFails(createGroup(environment.unauthenticatedContext().firestore(), 'owner', { name: 'Anonymous' }));
});

test('invalid group fields are rejected by rules', async () => {
    for (const options of [
        { name: '' }, { name: '   ' }, { name: 'x'.repeat(101) },
        { name: 'Test', description: 'x'.repeat(1001) }, { name: 'Test', mode: 'invalid' },
        { name: 'Test', chaptersPerWeek: 0 }, { name: 'Test', chaptersPerWeek: 54 },
        { name: 'Test', chaptersPerWeek: 1.5 }, { name: 'Test', startChapter: 54 },
    ]) await assertFails(createGroup(dbFor('owner'), 'owner', options));
});

test('only members read a group and roster; global enumeration is denied', async () => {
    const id = await create();
    await assertFails(getGroup(dbFor('outsider'), id));
    await assertFails(listMembers(dbFor('outsider'), id));
    await assertFails(getDocs(collection(dbFor('owner'), 'groups')));
    await assertFails(getGroup(environment.unauthenticatedContext().firestore(), id));
});

test('admin adds an existing user with atomic membership and discovery', async () => {
    const id = await create();
    await assertSucceeds(addMember(dbFor('owner'), id, 'reader'));
    assert.equal((await listMyGroups(dbFor('reader'), 'reader'))[0].id, id);
    assert.equal((await listMembers(dbFor('reader'), id)).length, 2);
    await assertFails(getDoc(doc(dbFor('reader'), 'users/owner')));
    await assertFails(listMyGroups(dbFor('owner'), 'reader'));
});

test('outsiders cannot self-join or forge a discovery index', async () => {
    const id = await create();
    await assertFails(addMember(dbFor('outsider'), id, 'outsider'));
    await assertFails(setDoc(doc(dbFor('outsider'), 'users/outsider/groups', id), {
        groupId: id, joinedAt: serverTimestamp(),
    }));
});

test('membership cannot be orphaned or added for a missing profile', async () => {
    const id = await create();
    await assertFails(setDoc(doc(dbFor('owner'), 'groups', id, 'members/reader'), {
        userId: 'reader', role: 'member', joinedAt: serverTimestamp(),
    }));
    await assertFails(addMember(dbFor('owner'), id, 'missing-profile'));
    await assertFails(addMember(dbFor('owner'), 'missing-group', 'reader'));
});

test('duplicate membership is rejected and cannot reset roles or timestamps', async () => {
    const id = await create();
    await addMember(dbFor('owner'), id, 'reader');
    await setMemberRole(dbFor('owner'), id, 'reader', 'group_lead');
    await assertFails(addMember(dbFor('owner'), id, 'reader'));
    assert.equal((await getDoc(doc(dbFor('owner'), 'groups', id, 'members/reader'))).data().role, 'group_lead');
});

test('admin can promote/demote a lead, but cannot create more admins or demote the creator', async () => {
    const id = await create();
    await addMember(dbFor('owner'), id, 'reader');
    await assertSucceeds(setMemberRole(dbFor('owner'), id, 'reader', 'group_lead'));
    await assertSucceeds(setMemberRole(dbFor('owner'), id, 'reader', 'member'));
    await assertFails(setMemberRole(dbFor('owner'), id, 'reader', 'admin'));
    await assertFails(setMemberRole(dbFor('owner'), id, 'owner', 'member'));
});

test('members and leads cannot mutate roles, group settings or memberships', async () => {
    const id = await create();
    await addMember(dbFor('owner'), id, 'reader');
    for (const role of ['member', 'group_lead']) {
        if (role === 'group_lead') await setMemberRole(dbFor('owner'), id, 'reader', role);
        await assertFails(setMemberRole(dbFor('reader'), id, 'reader', 'admin'));
        await assertFails(updateGroup(dbFor('reader'), id, { name: 'Hijacked' }));
        await assertFails(addMember(dbFor('reader'), id, 'outsider'));
    }
});

test('admin settings update preserves identity/mode and denies week jumps or mixed advancement', async () => {
    const id = await create();
    await assertSucceeds(updateGroup(dbFor('owner'), id, { name: 'Updated', chaptersPerWeek: 3 }));
    for (const changes of [
        { createdBy: 'reader' }, { createdAt: serverTimestamp() }, { mode: 'saptah' },
        { currentWeek: 3 }, { currentWeek: 2, startChapter: 2 },
        { inviteCode: 'ABC123' }, { memberCount: 100 }, { chaptersPerWeek: 0 },
    ]) await assertFails(updateGroup(dbFor('owner'), id, changes));
});

test('membership identity, joinedAt and extra fields are immutable', async () => {
    const id = await create();
    await addMember(dbFor('owner'), id, 'reader');
    const reference = doc(dbFor('owner'), 'groups', id, 'members/reader');
    for (const changes of [{ userId: 'outsider' }, { joinedAt: serverTimestamp() }, { isAdmin: true }]) {
        await assertFails(updateDoc(reference, changes));
    }
});

test('group deletion and uncoordinated membership/discovery deletes remain denied', async () => {
    const id = await create();
    await addMember(dbFor('owner'), id, 'reader');
    for (const path of [`groups/${id}`, `groups/${id}/members/reader`, `users/reader/groups/${id}`]) {
        await assertFails(deleteDoc(doc(dbFor('owner'), path)));
    }
});

test('admin cannot bootstrap another member as privileged in a forged batch', async () => {
    const id = await create();
    const db = dbFor('owner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', id, 'members/reader'), { userId: 'reader', role: 'admin', joinedAt: serverTimestamp() });
    batch.set(doc(db, 'users/reader/groups', id), { groupId: id, joinedAt: serverTimestamp() });
    await assertFails(batch.commit());
});

test('bootstrap rejects a nonadmin creator even with all documents supplied', async () => {
    const db = dbFor('owner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/forged'), groupData());
    batch.set(doc(db, 'groups/forged/members/owner'), { userId: 'owner', role: 'member', joinedAt: serverTimestamp() });
    batch.set(doc(db, 'users/owner/groups/forged'), { groupId: 'forged', joinedAt: serverTimestamp() });
    await assertFails(batch.commit());
});

test('malformed discovery indexes reject the whole membership batch', async () => {
    const id = await create();
    const db = dbFor('owner');
    for (const data of [
        { groupId: id },
        { groupId: id, joinedAt: serverTimestamp(), role: 'admin' },
        { groupId: 'wrong-group', joinedAt: serverTimestamp() },
    ]) {
        const batch = writeBatch(db);
        batch.set(doc(db, 'groups', id, 'members/reader'), { userId: 'reader', role: 'member', joinedAt: serverTimestamp() });
        batch.set(doc(db, 'users/reader/groups', id), data);
        await assertFails(batch.commit());
    }
});

test('list queries must be bounded and document-ID cursors do not repeat rows', async () => {
    const id = await create();
    const db = dbFor('owner');
    await addMember(db, id, 'reader');
    await assertFails(getDocs(collection(db, 'groups', id, 'members')));
    await assertFails(getDocs(query(collection(db, 'groups', id, 'members'), limit(51))));
    await assertFails(getDocs(collection(db, 'users/owner/groups')));
    const members = await listMembers(db, id);
    assert.equal(members.length, 2);
    assert.deepEqual(await listMembers(db, id, members.at(-1).id), []);
    assert.deepEqual(await listMyGroups(db, 'owner', id), []);
});