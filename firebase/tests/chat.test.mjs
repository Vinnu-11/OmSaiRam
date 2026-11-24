import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, getDocFromServer, getDocsFromServer,
    setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, query, limit,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole } from '../src/groups.mjs';
import { createInvitation, joinWithInvitation } from '../src/invitations.mjs';
import { sendMessage, getMessage, listMessages } from '../src/chat.mjs';
import { setMemberDisplay, getMemberDisplay } from '../src/member-display.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();
const ref = (db = dbFor('reader'), id = 'raw', group = groupId) => doc(db, 'groups', group, 'messages', id);
const data = (overrides = {}) => ({ senderUid: 'reader', text: 'Om Sai Ram', createdAt: serverTimestamp(), ...overrides });

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
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Group Chat' });
    for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('all current member roles send auto-ID messages with only sender, text and server time', async () => {
    const ids = [];
    for (const uid of ['owner', 'lead', 'reader', 'other']) {
        const id = await assertSucceeds(sendMessage(dbFor(uid), groupId, uid, 'Om Sai Ram\nTogether'));
        assert.match(id, /^[A-Za-z0-9]{20}$/);
        ids.push(id);
        const message = await getMessage(dbFor('other'), groupId, id);
        assert.deepEqual(Object.keys(message).sort(), ['createdAt', 'id', 'senderUid', 'text']);
        assert.equal(message.senderUid, uid);
        assert.equal(message.text, 'Om Sai Ram\nTogether');
        assert.ok(message.createdAt instanceof Timestamp);
    }
    assert.equal(new Set(ids).size, 4);
    assert.equal((await listMessages(dbFor('reader'), groupId)).length, 4);
    assert.equal(await getMessage(dbFor('reader'), groupId, 'missing'), null);
});

test('chat resolves opt-in shared names separately, never exposes private profiles or identity snapshots', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Group Alias');
    const id = await sendMessage(dbFor('reader'), groupId, 'reader', 'Reading completed');
    const message = await getMessage(dbFor('other'), groupId, id);
    assert.equal((await getMemberDisplay(dbFor('other'), groupId, message.senderUid)).displayName, 'Group Alias');
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'New Alias');
    assert.equal((await getMemberDisplay(dbFor('other'), groupId, message.senderUid)).displayName, 'New Alias');
    assert.deepEqual(await getMessage(dbFor('other'), groupId, id), message);
    await assertFails(getDocFromServer(doc(dbFor('other'), 'users', 'reader')));
    assert.equal((await getDocFromServer(doc(dbFor('reader'), 'users', 'reader'))).data().displayName, 'Private reader');
});

test('invitation possession grants no chat access until membership has committed', async () => {
    const id = await sendMessage(dbFor('reader'), groupId, 'reader', 'Welcome');
    const token = await createInvitation(dbFor('owner'), groupId, 'owner');
    const outsider = dbFor('outsider');
    await assertFails(getMessage(outsider, groupId, id));
    await assertFails(sendMessage(outsider, groupId, 'outsider', 'Not joined'));
    await joinWithInvitation(outsider, 'outsider', token);
    await assertSucceeds(getMessage(outsider, groupId, id));
    await assertSucceeds(sendMessage(outsider, groupId, 'outsider', 'Joined'));
});

test('nonmembers and unauthenticated clients cannot read, list or send even with forged claims', async () => {
    const id = await sendMessage(dbFor('reader'), groupId, 'reader', 'Members only');
    for (const db of [dbFor('outsider'), dbFor('outsider', { admin: true, role: 'admin', groupId }), anonymous()]) {
        await assertFails(getMessage(db, groupId, id));
        await assertFails(listMessages(db, groupId));
        await assertFails(setDoc(ref(db), data({ senderUid: 'outsider' })));
    }
});

test('sender spoofing fails in helpers and raw writes regardless of group role or claims', async () => {
    for (const uid of ['owner', 'lead', 'other']) {
        await assertFails(sendMessage(dbFor(uid), groupId, 'reader', 'Forged'));
        await assertFails(setDoc(ref(dbFor(uid)), data()));
    }
    await assertFails(setDoc(ref(dbFor('other', { senderUid: 'reader', userId: 'reader' })), data()));
    for (const senderUid of [null, 1, true, '', { uid: 'reader' }]) {
        await assertFails(setDoc(ref(), data({ senderUid })));
    }
});

test('raw message schema rejects every missing field and private identity, invite and highlight extras', async () => {
    for (const key of Object.keys(data())) {
        const incomplete = data();
        delete incomplete[key];
        await assertFails(setDoc(ref(), incomplete));
    }
    for (const extra of [
        { displayName: 'Reader' }, { senderName: 'Reader' }, { email: 'private@example.test' },
        { phone: 'private' }, { avatarUrl: 'private' }, { identity: { name: 'Reader' } },
        { inviteToken: 'a'.repeat(64) }, { token: 'secret' }, { type: 'highlight' },
        { type: 'message' }, { unitKey: '16-17' }, { groupId }, { updatedAt: serverTimestamp() },
    ]) await assertFails(setDoc(ref(), data(extra)));
});

test('raw message text rejects blank, whitespace-only, oversized and wrong-type values', async () => {
    for (const text of ['', ' ', '\t\r\n', '\n \n', 'x'.repeat(2001), null, 1, true, [], {}]) {
        await assertFails(setDoc(ref(), data({ text })));
    }
});

test('text boundaries and multiline nonblank messages are supported without hidden trimming', async () => {
    for (const text of ['x', 'x'.repeat(2000), '\n  Sai\n\t', 'साई राम', 'ఓం సాయి రామ్']) {
        const id = await sendMessage(dbFor('reader'), groupId, 'reader', text);
        assert.equal((await getMessage(dbFor('reader'), groupId, id)).text, text);
    }
    await assertSucceeds(setDoc(ref(), data({ text: '\nSai\n' })));
});

test('message createdAt must be server time, not client time, null or forged future time', async () => {
    for (const createdAt of [Timestamp.fromMillis(0), Timestamp.fromMillis(4102444800000), null, 'now', 1]) {
        await assertFails(setDoc(ref(), data({ createdAt })));
    }
});

test('every actor including sender, admin and lead is denied message edits, overwrites and uncoordinated deletes', async () => {
    await setDoc(ref(), data());
    const original = (await getDocFromServer(ref())).data();
    for (const db of [dbFor('reader'), dbFor('owner'), dbFor('lead'), dbFor('other'), dbFor('outsider'), anonymous()]) {
        for (const change of [{ text: 'Edited' }, { senderUid: 'other' }, { createdAt: serverTimestamp() }, { hidden: true }]) {
            await assertFails(updateDoc(ref(db), change));
        }
        await assertFails(setDoc(ref(db), data({ senderUid: 'owner' })));
        await assertFails(deleteDoc(ref(db)));
    }
    assert.deepEqual((await getDocFromServer(ref())).data(), original);
});

test('lists require a limit of at most 50 and cannot discover cross-group or legacy chat', async () => {
    await setDoc(ref(), data());
    const db = dbFor('reader');
    const messages = collection(db, 'groups', groupId, 'messages');
    await assertSucceeds(getDocsFromServer(query(messages, limit(50))));
    await assertFails(getDocsFromServer(messages));
    await assertFails(getDocsFromServer(query(messages, limit(51))));
    await assertFails(getDocsFromServer(query(collectionGroup(db, 'messages'), limit(50))));
    for (const path of ['messages/legacy', 'chat/legacy', `groups/${groupId}/chat/legacy`]) {
        await assertFails(setDoc(doc(db, path), data()));
        await assertFails(getDocFromServer(doc(db, path)));
    }
});

test('pagination covers more than 50 same-batch tied timestamps exactly once in descending ID order', async () => {
    const db = dbFor('reader');
    const ids = Array.from({ length: 57 }, (_, index) => `tie-${String(index).padStart(3, '0')}`);
    // Fixture-only bypass preserves real same-commit timestamp ties. Client
    // creates now perform per-ID tombstone checks (18-item atomic budget),
    // independently covered by moderation tests. All reads remain unprivileged.
    await environment.withSecurityRulesDisabled(async context => {
        const fixtureDb = context.firestore();
        const batch = writeBatch(fixtureDb);
        for (const id of ids) batch.set(ref(fixtureDb, id), data());
        await assertSucceeds(batch.commit());
    });
    const first = await listMessages(db, groupId);
    assert.equal(first.length, 50);
    assert.ok(first.every(entry => entry.createdAt.isEqual(first[0].createdAt)));
    const last = first.at(-1);
    const second = await listMessages(db, groupId, { after: { createdAt: last.createdAt, id: last.id } });
    assert.equal(second.length, 7);
    assert.deepEqual([...first, ...second].map(entry => entry.id), ids.toReversed());
    assert.equal(new Set([...first, ...second].map(entry => entry.id)).size, 57);
    assert.deepEqual(await listMessages(db, groupId, { after: second.at(-1) }), []);
});

test('cursor retains sub-millisecond precision and orders mixed times before descending tied IDs', async () => {
    const entries = [
        // Firestore persists microseconds, rounding away finer nanoseconds.
        ['older-z', new Timestamp(100, 1000)], ['newer-a', new Timestamp(100, 2000)],
        ['newer-z', new Timestamp(100, 2000)], ['oldest', new Timestamp(99, 999999000)],
    ];
    // Privileged fixture creates precisely known times, never a client timestamp bypass.
    await environment.withSecurityRulesDisabled(async context => {
        const batch = writeBatch(context.firestore());
        for (const [id, createdAt] of entries) batch.set(ref(context.firestore(), id), data({ createdAt }));
        await batch.commit();
    });
    const found = [];
    let after = null;
    for (; ;) {
        const page = await listMessages(dbFor('other'), groupId, { pageSize: 1, after });
        if (!page.length) break;
        found.push(page[0].id);
        after = { createdAt: page[0].createdAt, id: page[0].id };
    }
    assert.deepEqual(found, ['newer-z', 'newer-a', 'older-z', 'oldest']);
});

test('new head messages do not duplicate or disturb an existing older-page cursor', async () => {
    const db = dbFor('reader');
    const batch = writeBatch(db);
    for (const id of ['a', 'b', 'c']) batch.set(ref(db, id), data());
    await batch.commit();
    const first = await listMessages(db, groupId, { pageSize: 2 });
    const newId = await sendMessage(db, groupId, 'reader', 'New head');
    assert.deepEqual((await listMessages(db, groupId, { after: first.at(-1) })).map(item => item.id), ['a']);
    assert.equal((await listMessages(db, groupId))[0].id, newId);
});

test('chat access is scoped to the chosen group and requires a surviving parent group', async () => {
    const otherGroup = await createGroup(dbFor('outsider'), 'outsider', { name: 'Unrelated' });
    await assertFails(sendMessage(dbFor('reader'), otherGroup, 'reader', 'Wrong group'));
    await assertFails(listMessages(dbFor('reader'), otherGroup));
    await assertFails(sendMessage(dbFor('reader'), 'missing-group', 'reader', 'Missing'));
    await setDoc(ref(), data());
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId));
    });
    await assertFails(getMessage(dbFor('reader'), groupId, 'raw'));
    await assertFails(listMessages(dbFor('reader'), groupId));
    await assertFails(sendMessage(dbFor('reader'), groupId, 'reader', 'Orphan'));
});

test('privileged membership removal revokes the same client next server reads and sends despite stale index', async () => {
    const db = dbFor('reader');
    const id = await sendMessage(db, groupId, 'reader', 'Before removal');
    await getMessage(db, groupId, id);
    await listMessages(db, groupId);
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId, 'members', 'reader'));
    });
    assert.ok((await getDocFromServer(doc(db, 'users', 'reader', 'groups', groupId))).exists());
    await assertFails(getMessage(db, groupId, id));
    await assertFails(listMessages(db, groupId));
    await assertFails(sendMessage(db, groupId, 'reader', 'After removal'));
    await assertFails(setDoc(ref(db, 'after-removal'), data()));
    await assertSucceeds(getMessage(dbFor('other'), groupId, id));
});

test('joining-and-posting cannot use a same-batch newly added membership', async () => {
    const db = dbFor('owner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', groupId, 'members', 'outsider'), {
        userId: 'outsider', role: 'member', joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'users', 'outsider', 'groups', groupId), { groupId, joinedAt: serverTimestamp() });
    batch.set(ref(db, 'joined'), data({ senderUid: 'outsider' }));
    await assertFails(batch.commit());
    assert.equal((await getDocFromServer(doc(db, 'groups', groupId, 'members', 'outsider'))).exists(), false);
    const token = await createInvitation(db, groupId, 'owner');
    const outsider = dbFor('outsider');
    const join = writeBatch(outsider);
    join.set(doc(outsider, 'groups', groupId, 'members', 'outsider'), {
        userId: 'outsider', role: 'member', joinedAt: serverTimestamp(),
    });
    join.set(doc(outsider, 'users', 'outsider', 'groups', groupId), { groupId, joinedAt: serverTimestamp(), inviteToken: token });
    join.set(ref(outsider, 'joined'), data({ senderUid: 'outsider' }));
    await assertFails(join.commit());
});

test('helper validation rejects invalid content, path injection, limits and incomplete cursors', async () => {
    const db = dbFor('reader');
    for (const text of ['', '\n\t ', 'x'.repeat(2001), null, 1, {}, []]) {
        await assert.rejects(sendMessage(db, groupId, 'reader', text), /Message text/);
    }
    for (const value of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501)]) {
        await assert.rejects(sendMessage(db, value, 'reader', 'Sai'), /path segment/);
        await assert.rejects(sendMessage(db, groupId, value, 'Sai'), /path segment/);
        await assert.rejects(getMessage(db, groupId, value), /path segment/);
        await assert.rejects(listMessages(db, groupId, { after: { createdAt: Timestamp.now(), id: value } }), /path segment/);
    }
    for (const pageSize of [0, 51, -1, 1.5, '1', null, NaN, Infinity]) {
        await assert.rejects(listMessages(db, groupId, { pageSize }), /Page size/);
    }
    for (const after of [{}, { id: 'raw' }, { id: 'raw', createdAt: new Date() }, { id: 'raw', createdAt: 1 }]) {
        await assert.rejects(listMessages(db, groupId, { after }), /Timestamp/);
    }
});