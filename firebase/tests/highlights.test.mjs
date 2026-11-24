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
import { createHighlight, getHighlight, listHighlights } from '../src/highlights.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();
const ref = (db = dbFor('reader'), id = 'raw', group = groupId) => doc(db, 'groups', group, 'highlights', id);
const data = (overrides = {}) => ({
    senderUid: 'reader', chapterNumber: 17, paragraphIndex: 0,
    quote: 'Selected verse', text: 'Reflection', createdAt: serverTimestamp(), ...overrides,
});
const input = (overrides = {}) => ({ chapterNumber: 17, quote: 'Selected verse', text: 'Reflection', ...overrides });

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
            displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        });
    }
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Highlights' });
    for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('all member roles create exact auto-ID highlights with server timestamps and original chapter anchors', async () => {
    const ids = [];
    for (const uid of ['owner', 'lead', 'reader', 'other']) {
        const id = await assertSucceeds(createHighlight(dbFor(uid), groupId, uid, input()));
        ids.push(id);
        assert.match(id, /^[A-Za-z0-9]{20}$/);
        const found = await getHighlight(dbFor('other'), groupId, id);
        assert.deepEqual(Object.keys(found).sort(), ['chapterNumber', 'createdAt', 'id', 'paragraphIndex', 'quote', 'senderUid', 'text']);
        assert.equal(found.senderUid, uid);
        assert.equal(found.chapterNumber, 17);
        assert.equal(found.paragraphIndex, 0);
        assert.ok(found.createdAt instanceof Timestamp);
    }
    assert.equal(new Set(ids).size, 4);
    assert.equal((await listHighlights(dbFor('reader'), groupId)).length, 4);
    assert.equal(await getHighlight(dbFor('reader'), groupId, 'missing'), null);
});

test('all 53 original chapters including combined-unit inner chapters stay distinct', async () => {
    const db = dbFor('reader');
    // Keep every creation under real client rules; per-ID tombstone checks
    // bound atomic content creates to 17, so this chapter fixture uses batches.
    for (let start = 1; start <= 53; start += 17) {
        const batch = writeBatch(db);
        for (let chapterNumber = start; chapterNumber <= Math.min(start + 16, 53); chapterNumber++) {
            batch.set(ref(db, `chapter-${chapterNumber}`), data({ chapterNumber }));
        }
        await assertSucceeds(batch.commit());
    }
    for (const chapterNumber of [1, 16, 17, 18, 19, 43, 44, 51, 52, 53]) {
        assert.equal((await getHighlight(db, groupId, `chapter-${chapterNumber}`)).chapterNumber, chapterNumber);
    }
});

test('nonmembers and anonymous clients cannot read/list/create despite forged group claims', async () => {
    await setDoc(ref(), data());
    for (const db of [dbFor('outsider'), dbFor('outsider', { admin: true, role: 'admin', groupId }), anonymous()]) {
        await assertFails(getHighlight(db, groupId, 'raw'));
        await assertFails(listHighlights(db, groupId));
        await assertFails(setDoc(ref(db, 'new'), data({ senderUid: 'outsider' })));
    }
});

test('sender spoofing fails for every other member role and wrong types', async () => {
    for (const uid of ['owner', 'lead', 'other']) {
        await assertFails(createHighlight(dbFor(uid), groupId, 'reader', input()));
        await assertFails(setDoc(ref(dbFor(uid)), data()));
    }
    for (const senderUid of [null, 1, true, '', {}, 'other']) await assertFails(setDoc(ref(), data({ senderUid })));
});

test('schema rejects each missing field and all identity, unit, role or schedule extras', async () => {
    for (const key of Object.keys(data())) {
        const incomplete = data();
        delete incomplete[key];
        await assertFails(setDoc(ref(), incomplete));
    }
    for (const extra of [
        { unitKey: '16-17' }, { chapterStart: 16 }, { chapterEnd: 17 }, { chapterId: 999 },
        { groupId }, { userId: 'reader' }, { displayName: 'Reader' }, { email: 'private' },
        { role: 'admin' }, { inviteToken: 'a'.repeat(64) }, { updatedAt: serverTimestamp() },
        { readingReminderEnabled: true },
    ]) await assertFails(setDoc(ref(), data(extra)));
});

test('chapter and paragraph integer bounds reject aliases, fractions and wrong types', async () => {
    for (const chapterNumber of [0, 54, -1, 16.5, '17', '16-17', null, true, {}]) {
        await assertFails(setDoc(ref(), data({ chapterNumber })));
    }
    for (const paragraphIndex of [-1, 0.5, 2147483648, '0', null, false, {}]) {
        await assertFails(setDoc(ref(), data({ paragraphIndex })));
    }
    await assertSucceeds(setDoc(ref(), data({ chapterNumber: 53, paragraphIndex: 2147483647 })));
});

test('quote and text reject blanks, oversized values and nonstrings independently', async () => {
    for (const [key, maximum] of [['quote', 500], ['text', 2000]]) {
        for (const value of ['', ' ', '\t\r\n', '\n \n', 'x'.repeat(maximum + 1), null, 1, true, [], {}]) {
            await assertFails(setDoc(ref(), data({ [key]: value })));
        }
    }
});

test('text and quote support exact bounds and multiline nonblank content without trimming', async () => {
    for (const [quote, text] of [['x', 'y'], ['x'.repeat(500), 'y'.repeat(2000)], ['\n साई\n', '\n Sai\t'], ['ఓం', 'राम']]) {
        const id = await createHighlight(dbFor('reader'), groupId, 'reader', input({ quote, text }));
        const found = await getHighlight(dbFor('other'), groupId, id);
        assert.equal(found.quote, quote);
        assert.equal(found.text, text);
    }
});

test('createdAt must be server time, not null, client epoch, future or wrong type', async () => {
    for (const createdAt of [Timestamp.fromMillis(0), Timestamp.fromMillis(4102444800000), null, 'now', 1, true]) {
        await assertFails(setDoc(ref(), data({ createdAt })));
    }
});

test('author, admin, lead and every other actor cannot edit, overwrite or uncoordinated delete highlights', async () => {
    await setDoc(ref(), data());
    const original = (await getDocFromServer(ref())).data();
    for (const db of [dbFor('reader'), dbFor('owner'), dbFor('lead'), dbFor('other'), dbFor('outsider'), anonymous()]) {
        for (const change of [{ text: 'Edited' }, { quote: 'Edited' }, { chapterNumber: 18 },
        { paragraphIndex: 1 }, { senderUid: 'owner' }, { createdAt: serverTimestamp() }, { hidden: true }]) {
            await assertFails(updateDoc(ref(db), change));
        }
        await assertFails(setDoc(ref(db), data()));
        await assertFails(deleteDoc(ref(db)));
    }
    assert.deepEqual((await getDocFromServer(ref())).data(), original);
});

test('bounded lists allow 50 only and deny collection-group, legacy and nested privilege paths', async () => {
    await setDoc(ref(), data());
    const db = dbFor('reader');
    const highlights = collection(db, 'groups', groupId, 'highlights');
    await assertSucceeds(getDocsFromServer(query(highlights, limit(50))));
    await assertFails(getDocsFromServer(highlights));
    await assertFails(getDocsFromServer(query(highlights, limit(51))));
    await assertFails(getDocsFromServer(query(collectionGroup(db, 'highlights'), limit(50))));
    for (const path of ['highlights/legacy', `groups/${groupId}/highlights/raw/settings/reminders`,
        `groups/${groupId}/highlights/raw/members/reader`, `groups/${groupId}/settings/reminders`]) {
        await assertFails(setDoc(doc(db, path), data()));
        await assertFails(getDocFromServer(doc(db, path)));
    }
});

test('real same-batch timestamp ties paginate 57 highlights exactly once using descending doc IDs', async () => {
    const db = dbFor('reader');
    const ids = Array.from({ length: 57 }, (_, index) => `tie-${String(index).padStart(3, '0')}`);
    // Preserve real same-commit timestamp ties in a privileged fixture only;
    // client-create access budgets are tested separately. Reads use real rules.
    await environment.withSecurityRulesDisabled(async context => {
        const fixtureDb = context.firestore();
        const batch = writeBatch(fixtureDb);
        for (const id of ids) batch.set(ref(fixtureDb, id), data());
        await assertSucceeds(batch.commit());
    });
    const first = await listHighlights(db, groupId);
    assert.equal(first.length, 50);
    assert.ok(first.every(item => item.createdAt.isEqual(first[0].createdAt)));
    const second = await listHighlights(db, groupId, { after: first.at(-1) });
    assert.equal(second.length, 7);
    assert.deepEqual([...first, ...second].map(item => item.id), ids.toReversed());
    assert.equal(new Set([...first, ...second].map(item => item.id)).size, 57);
    assert.deepEqual(await listHighlights(db, groupId, { after: second.at(-1) }), []);
});

test('timestamp cursor preserves microseconds and mixed-time order with tied descending IDs', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        const batch = writeBatch(context.firestore());
        for (const [id, createdAt] of [
            ['older-z', new Timestamp(100, 1000)], ['newer-a', new Timestamp(100, 2000)],
            ['newer-z', new Timestamp(100, 2000)], ['oldest', new Timestamp(99, 999999000)],
        ]) batch.set(ref(context.firestore(), id), data({ createdAt }));
        await batch.commit();
    });
    const found = [];
    let after = null;
    for (; ;) {
        const page = await listHighlights(dbFor('other'), groupId, { pageSize: 1, after });
        if (!page.length) break;
        found.push(page[0].id);
        after = page[0];
    }
    assert.deepEqual(found, ['newer-z', 'newer-a', 'older-z', 'oldest']);
});

test('new head insertion does not restart or duplicate an existing older cursor', async () => {
    const db = dbFor('reader');
    const batch = writeBatch(db);
    for (const id of ['a', 'b', 'c']) batch.set(ref(db, id), data());
    await batch.commit();
    const first = await listHighlights(db, groupId, { pageSize: 2 });
    const id = await createHighlight(db, groupId, 'reader', input());
    assert.deepEqual((await listHighlights(db, groupId, { after: first.at(-1) })).map(item => item.id), ['a']);
    assert.equal((await listHighlights(db, groupId))[0].id, id);
});

test('group scope, missing parents and removed membership revoke next server access', async () => {
    const db = dbFor('reader');
    const id = await createHighlight(db, groupId, 'reader', input());
    await getHighlight(db, groupId, id);
    await listHighlights(db, groupId);
    const unrelated = await createGroup(dbFor('outsider'), 'outsider', { name: 'Other' });
    await assertFails(createHighlight(db, unrelated, 'reader', input()));
    await assertFails(listHighlights(db, unrelated));
    await assertFails(createHighlight(db, 'missing', 'reader', input()));
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId, 'members', 'reader'));
    });
    assert.ok((await getDocFromServer(doc(db, 'users', 'reader', 'groups', groupId))).exists());
    await assertFails(getHighlight(db, groupId, id));
    await assertFails(listHighlights(db, groupId));
    await assertFails(createHighlight(db, groupId, 'reader', input()));
    await assertSucceeds(getHighlight(dbFor('other'), groupId, id));
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId));
    });
    await assertFails(getHighlight(dbFor('other'), groupId, id));
    await assertFails(listHighlights(dbFor('other'), groupId));
    await assertFails(createHighlight(dbFor('other'), groupId, 'other', input()));
});

test('invitation gives no highlight access before committed membership; atomic join-and-post fails', async () => {
    const token = await createInvitation(dbFor('owner'), groupId, 'owner');
    const db = dbFor('outsider');
    await assertFails(listHighlights(db, groupId));
    await assertFails(createHighlight(db, groupId, 'outsider', input()));
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', groupId, 'members', 'outsider'), {
        userId: 'outsider', role: 'member', joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'users', 'outsider', 'groups', groupId), { groupId, joinedAt: serverTimestamp(), inviteToken: token });
    batch.set(ref(db), data({ senderUid: 'outsider' }));
    await assertFails(batch.commit());
    await joinWithInvitation(db, 'outsider', token);
    await assertSucceeds(createHighlight(db, groupId, 'outsider', input()));
});

test('helpers reject invalid content, chapter/paragraph bounds, path injection, pages and cursors', async () => {
    const db = dbFor('reader');
    for (const [key, maximum] of [['quote', 500], ['text', 2000]]) {
        for (const value of ['', '\n\t ', 'x'.repeat(maximum + 1), null, 1, {}, []]) {
            await assert.rejects(createHighlight(db, groupId, 'reader', input({ [key]: value })), /nonblank/);
        }
    }
    for (const chapterNumber of [0, 54, 1.5, '17', null]) {
        await assert.rejects(createHighlight(db, groupId, 'reader', input({ chapterNumber })), /Chapter number/);
    }
    for (const paragraphIndex of [-1, 2147483648, 1.5, '0', null]) {
        await assert.rejects(createHighlight(db, groupId, 'reader', input({ paragraphIndex })), /Paragraph index/);
    }
    for (const value of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501)]) {
        await assert.rejects(createHighlight(db, value, 'reader', input()), /path segment/);
        await assert.rejects(createHighlight(db, groupId, value, input()), /path segment/);
        await assert.rejects(getHighlight(db, groupId, value), /path segment/);
        await assert.rejects(listHighlights(db, groupId, { after: { createdAt: Timestamp.now(), id: value } }), /path segment/);
    }
    for (const pageSize of [0, 51, -1, 1.5, '1', null, NaN, Infinity]) {
        await assert.rejects(listHighlights(db, groupId, { pageSize }), /Page size/);
    }
    for (const after of [{}, { id: 'raw' }, { id: 'raw', createdAt: new Date() }]) {
        await assert.rejects(listHighlights(db, groupId, { after }), /Timestamp/);
    }
});