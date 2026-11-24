import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, getDocFromServer, getDocsFromServer, setDoc,
    updateDoc, deleteDoc, serverTimestamp, Timestamp, query, limit, writeBatch,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole } from '../src/groups.mjs';
import { setMemberDisplay, getMemberDisplay, listMemberDisplays } from '../src/member-display.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();
const ref = (db = dbFor('reader'), uid = 'reader', group = groupId) => doc(db, 'groups', group, 'memberProfiles', uid);
const data = (overrides = {}) => ({ displayName: 'Shared Alias', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...overrides });

before(async () => {
    environment = await initializeTestEnvironment({
        projectId: settings.projectId,
        firestore: { ...settings.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    });
});
beforeEach(async () => {
    await environment.clearFirestore();
    for (const uid of ['owner', 'lead', 'reader', 'other', 'outsider']) {
        await setDoc(doc(dbFor(uid), 'users', uid), {
            displayName: `Private ${uid}`, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        });
    }
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Shared Member Display' });
    for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('member opts into a shared name independently of private profile; memberships remain minimal', async () => {
    assert.equal(await getMemberDisplay(dbFor('other'), groupId, 'reader'), null);
    assert.deepEqual(await listMemberDisplays(dbFor('other'), groupId), []);
    assert.equal(await assertSucceeds(setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Public Alias')), 'reader');
    const display = await getMemberDisplay(dbFor('other'), groupId, 'reader');
    assert.equal(display.displayName, 'Public Alias');
    assert.deepEqual(Object.keys(display).sort(), ['createdAt', 'displayName', 'id', 'updatedAt']);
    assert.ok(display.createdAt instanceof Timestamp);
    assert.ok(display.createdAt.isEqual(display.updatedAt));
    const membership = (await getDocFromServer(doc(dbFor('other'), 'groups', groupId, 'members', 'reader'))).data();
    assert.deepEqual(Object.keys(membership).sort(), ['joinedAt', 'role', 'userId']);
    assert.equal((await getDocFromServer(doc(dbFor('reader'), 'users', 'reader'))).data().displayName, 'Private reader');
    await assertFails(getDocFromServer(doc(dbFor('other'), 'users', 'reader')));
});

test('all roles publish and update only themselves, retaining immutable createdAt and server updatedAt', async () => {
    for (const uid of ['owner', 'lead', 'reader', 'other']) {
        const db = dbFor(uid);
        await setMemberDisplay(db, groupId, uid, 'First');
        const before = await getMemberDisplay(db, groupId, uid);
        await assertSucceeds(setMemberDisplay(db, groupId, uid, 'Second'));
        const after = await getMemberDisplay(db, groupId, uid);
        assert.equal(after.displayName, 'Second');
        assert.ok(after.createdAt.isEqual(before.createdAt));
        assert.ok(after.updatedAt.toMillis() >= before.updatedAt.toMillis());
    }
    assert.equal((await listMemberDisplays(dbFor('reader'), groupId)).length, 4);
});

test('admins, leads and other members cannot create or update another member display', async () => {
    for (const uid of ['owner', 'lead', 'other']) {
        await assertFails(setMemberDisplay(dbFor(uid), groupId, 'reader', 'Impersonated'));
        await assertFails(setDoc(ref(dbFor(uid)), data()));
    }
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Self');
    for (const uid of ['owner', 'lead', 'other']) {
        await assertFails(setMemberDisplay(dbFor(uid), groupId, 'reader', 'Edited'));
        await assertFails(updateDoc(ref(dbFor(uid)), { displayName: 'Edited', updatedAt: serverTimestamp() }));
    }
    await assertFails(setDoc(ref(dbFor('other', { userId: 'reader', admin: true })), data()));
});

test('nonmembers and unauthenticated callers cannot create, get, list or update shared displays', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Self');
    for (const db of [dbFor('outsider'), dbFor('outsider', { admin: true, groupId }), anonymous()]) {
        await assertFails(getMemberDisplay(db, groupId, 'reader'));
        await assertFails(listMemberDisplays(db, groupId));
        await assertFails(setDoc(ref(db, 'outsider'), data()));
        await assertFails(updateDoc(ref(db), { displayName: 'Edited', updatedAt: serverTimestamp() }));
    }
});

test('raw display schema rejects missing fields and all private identity/permission/token extras', async () => {
    for (const key of Object.keys(data())) {
        const incomplete = data();
        delete incomplete[key];
        await assertFails(setDoc(ref(), incomplete));
    }
    for (const extra of [
        { email: 'private@example.test' }, { phoneNumber: 'private' }, { avatarUrl: 'private' },
        { identity: { email: 'private' } }, { userId: 'reader' }, { role: 'admin' },
        { groupId }, { inviteToken: 'a'.repeat(64) }, { isAdmin: true },
    ]) await assertFails(setDoc(ref(), data(extra)));
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Self');
    await assertFails(updateDoc(ref(), { email: 'private@example.test', updatedAt: serverTimestamp() }));
});

test('display names are nonblank strings of length 1..100, including nonblank multiline names', async () => {
    for (const displayName of ['', ' ', '\t\r\n', '\n \n', 'x'.repeat(101), null, 1, true, [], {}]) {
        await assertFails(setDoc(ref(), data({ displayName })));
        await assert.rejects(setMemberDisplay(dbFor('reader'), groupId, 'reader', displayName), /Display name/);
    }
    for (const displayName of ['x', 'x'.repeat(100), '\nSai\n', 'సాయి', 'साई राम']) {
        await setMemberDisplay(dbFor('reader'), groupId, 'reader', displayName);
        assert.equal((await getMemberDisplay(dbFor('other'), groupId, 'reader')).displayName, displayName);
    }
    await assertFails(updateDoc(ref(), { displayName: 'x'.repeat(101), updatedAt: serverTimestamp() }));
});

test('display timestamps enforce server creation/update and immutable createdAt even for self', async () => {
    for (const changes of [
        { createdAt: Timestamp.fromMillis(0) }, { createdAt: null },
        { updatedAt: Timestamp.fromMillis(0) }, { updatedAt: null },
    ]) await assertFails(setDoc(ref(), data(changes)));
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Self');
    const original = (await getDocFromServer(ref())).data();
    await assertFails(updateDoc(ref(), { displayName: 'Changed' }));
    await assertFails(updateDoc(ref(), { updatedAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(ref(), { createdAt: Timestamp.fromMillis(0), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(ref(), data({ createdAt: Timestamp.fromMillis(0) })));
    await assertSucceeds(updateDoc(ref(), { displayName: 'Own edit', updatedAt: serverTimestamp() }));
    assert.ok((await getDocFromServer(ref())).data().createdAt.isEqual(original.createdAt));
});

test('display listing is bounded to 50; collection-group enumeration and uncoordinated deletes are denied', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Self');
    const db = dbFor('other');
    const profiles = collection(db, 'groups', groupId, 'memberProfiles');
    await assertSucceeds(getDocsFromServer(query(profiles, limit(50))));
    await assertFails(getDocsFromServer(profiles));
    await assertFails(getDocsFromServer(query(profiles, limit(51))));
    await assertFails(getDocsFromServer(query(collectionGroup(db, 'memberProfiles'), limit(50))));
    for (const db of [dbFor('reader'), dbFor('owner'), dbFor('lead'), dbFor('outsider'), anonymous()]) {
        await assertFails(deleteDoc(ref(db)));
    }
});

test('shared-display document-ID pagination lists only opted-in names without gaps', async () => {
    // Privileged fixture simulates a larger roster without weakening client ownership.
    const ids = Array.from({ length: 53 }, (_, index) => `member-${String(index).padStart(3, '0')}`);
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        const batch = writeBatch(db);
        for (const uid of ids) {
            batch.set(doc(db, 'groups', groupId, 'members', uid), {
                userId: uid, role: 'member', joinedAt: serverTimestamp(),
            });
            batch.set(ref(db, uid), data({ displayName: uid }));
        }
        await batch.commit();
    });
    const first = await listMemberDisplays(dbFor('reader'), groupId);
    assert.equal(first.length, 50);
    const second = await listMemberDisplays(dbFor('reader'), groupId, first.at(-1).id);
    assert.equal(second.length, 3);
    assert.deepEqual([...first, ...second].map(entry => entry.id), ids);
    assert.deepEqual(await listMemberDisplays(dbFor('reader'), groupId, second.at(-1).id), []);
});

test('same member may choose different names in different groups; unrelated group access is denied', async () => {
    const another = await createGroup(dbFor('owner'), 'owner', { name: 'Other Group' });
    await addMember(dbFor('owner'), another, 'reader');
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'First Alias');
    await setMemberDisplay(dbFor('reader'), another, 'reader', 'Second Alias');
    assert.equal((await getMemberDisplay(dbFor('owner'), groupId, 'reader')).displayName, 'First Alias');
    assert.equal((await getMemberDisplay(dbFor('owner'), another, 'reader')).displayName, 'Second Alias');
    await assertFails(getMemberDisplay(dbFor('other'), another, 'reader'));
    await assertFails(listMemberDisplays(dbFor('other'), another));
    await assertFails(setMemberDisplay(dbFor('other'), another, 'other', 'Not a member'));
    await assertFails(setMemberDisplay(dbFor('reader'), 'missing-group', 'reader', 'Missing'));
});

test('membership removal revokes same-client reads and self-updates despite private profile and index', async () => {
    const db = dbFor('reader');
    await setMemberDisplay(db, groupId, 'reader', 'Before');
    await getMemberDisplay(db, groupId, 'reader');
    await listMemberDisplays(db, groupId);
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId, 'members', 'reader'));
    });
    assert.ok((await getDocFromServer(doc(db, 'users', 'reader'))).exists());
    assert.ok((await getDocFromServer(doc(db, 'users', 'reader', 'groups', groupId))).exists());
    await assertFails(getMemberDisplay(db, groupId, 'reader'));
    await assertFails(listMemberDisplays(db, groupId));
    await assertFails(setMemberDisplay(db, groupId, 'reader', 'After'));
    await assertFails(updateDoc(ref(db), { displayName: 'After', updatedAt: serverTimestamp() }));
    // Remaining members can read stale displays until future privileged coordinated cleanup.
    assert.equal((await getMemberDisplay(dbFor('other'), groupId, 'reader')).displayName, 'Before');
});

test('orphaned memberships do not grant shared-display access after parent group removal', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Before');
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId));
    });
    await assertFails(getMemberDisplay(dbFor('reader'), groupId, 'reader'));
    await assertFails(listMemberDisplays(dbFor('reader'), groupId));
    await assertFails(setMemberDisplay(dbFor('reader'), groupId, 'reader', 'After'));
    await assertFails(setDoc(ref(dbFor('other'), 'other'), data()));
});

test('concurrent self-display transactions preserve one createdAt and cannot impersonate another user', async () => {
    const db = dbFor('reader');
    await setMemberDisplay(db, groupId, 'reader', 'Initial');
    const createdAt = (await getMemberDisplay(db, groupId, 'reader')).createdAt;
    const results = await Promise.allSettled([
        setMemberDisplay(db, groupId, 'reader', 'First'),
        setMemberDisplay(db, groupId, 'reader', 'Second'),
        setMemberDisplay(dbFor('other'), groupId, 'reader', 'Forged'),
    ]);
    assert.deepEqual(results.map(result => result.status), ['fulfilled', 'fulfilled', 'rejected']);
    const display = await getMemberDisplay(db, groupId, 'reader');
    assert.ok(['First', 'Second'].includes(display.displayName));
    assert.ok(display.createdAt.isEqual(createdAt));
    assert.equal((await listMemberDisplays(db, groupId)).length, 1);
});

test('member display helpers reject invalid group, member and cursor path segments', async () => {
    const db = dbFor('reader');
    for (const value of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501)]) {
        await assert.rejects(setMemberDisplay(db, value, 'reader', 'Sai'), /path segment/);
        await assert.rejects(setMemberDisplay(db, groupId, value, 'Sai'), /path segment/);
        await assert.rejects(getMemberDisplay(db, value, 'reader'), /path segment/);
        await assert.rejects(getMemberDisplay(db, groupId, value), /path segment/);
        await assert.rejects(listMemberDisplays(db, groupId, value), /path segment/);
    }
});