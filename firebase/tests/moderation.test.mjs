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
import { createInvitation } from '../src/invitations.mjs';
import { removeMember } from '../src/membership-lifecycle.mjs';
import {
    reportContent, getReport, listReports, resolveReport, removeContent, listModerationRecords,
} from '../src/moderation.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();
const item = (db, kind, id = 'target', group = groupId) => doc(db, 'groups', group, kind, id);
const reportRef = (db, kind, uid = 'reader', id = 'target', group = groupId) =>
    doc(item(db, kind, id, group), 'reports', uid);
const marker = (db, kind, id = 'target', group = groupId) =>
    doc(db, 'groups', group, 'moderationRecords', kind, 'items', id);
const itemData = (kind, senderUid = 'reader') => ({
    senderUid, text: 'Original content — must not be copied', createdAt: serverTimestamp(),
    ...(kind === 'highlights' ? { chapterNumber: 17, paragraphIndex: 0, quote: 'Original quote' } : {}),
});
const reportData = (overrides = {}) => ({
    reporterUid: 'reader', reason: 'spam', details: '', createdAt: serverTimestamp(),
    status: 'open', resolvedBy: null, resolvedAt: null, ...overrides,
});
const markerData = (kind, overrides = {}) => ({
    targetKind: kind, targetId: 'target', authorUid: 'reader', moderatedBy: 'owner',
    moderatedAt: serverTimestamp(), reason: 'spam', ...overrides,
});

function removalBatch(db, kind, { data = markerData(kind), mark = true, remove = true,
    id = 'target', group = groupId, markerKind = kind, markerId = id, markerGroup = group } = {}) {
    const batch = writeBatch(db);
    if (mark) batch.set(marker(db, markerKind, markerId, markerGroup), data);
    if (remove) batch.delete(item(db, kind, id, group));
    return batch;
}

async function state(kind, id = 'target', group = groupId) {
    let result;
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        result = await Promise.all([item(db, kind, id, group), marker(db, kind, id, group),
        reportRef(db, kind, 'reader', id, group)].map(async reference => {
            const snapshot = await getDocFromServer(reference);
            return snapshot.exists() ? snapshot.data() : null;
        }));
    });
    return result;
}

async function deniedRemoval(batch, kind) {
    const original = await state(kind);
    await assertFails(batch.commit());
    assert.deepEqual(await state(kind), original);
}

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
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Moderation' });
    for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
    for (const kind of ['messages', 'highlights']) await setDoc(item(dbFor('reader'), kind), itemData(kind));
});
after(async () => { await environment?.cleanup(); });

for (const kind of ['messages', 'highlights']) {
    test(`${kind}: ID-reservation lookup permits 17 atomic creates but rejects 18 without partial writes`, async () => {
        const db = dbFor('reader');
        // Three shared reads (member, group before/after archive state) plus one unique
        // tombstone check per item exhaust the real 20-access-call atomic-write budget.
        const accepted = writeBatch(db);
        for (let index = 0; index < 17; index++) accepted.set(item(db, kind, `safe-${index}`), itemData(kind));
        await assertSucceeds(accepted.commit());
        const rejected = writeBatch(db);
        for (let index = 0; index < 18; index++) rejected.set(item(db, kind, `over-${index}`), itemData(kind));
        await assertFails(rejected.commit());
        for (let index = 0; index < 18; index++) assert.equal((await getDocFromServer(item(db, kind, `over-${index}`))).exists(), false);
    });

    test(`${kind}: all member roles report once with exact schema and all four reasons`, async () => {
        for (const [index, uid] of ['owner', 'lead', 'reader', 'other'].entries()) {
            const reason = ['spam', 'harassment', 'inappropriate', 'other'][index];
            const details = uid === 'reader' ? 'x'.repeat(1000) : '';
            assert.equal(await reportContent(dbFor(uid), groupId, kind, 'target', uid, { reason, details }), uid);
            const found = await getReport(dbFor(uid), groupId, kind, 'target', uid);
            assert.deepEqual(Object.keys(found).sort(),
                ['createdAt', 'details', 'id', 'reason', 'reporterUid', 'resolvedAt', 'resolvedBy', 'status']);
            assert.equal(found.reason, reason);
            assert.equal(found.details, details);
            assert.equal(found.reporterUid, uid);
            assert.equal(found.status, 'open');
            assert.equal(found.resolvedBy, null);
            assert.equal(found.resolvedAt, null);
            assert.ok(found.createdAt instanceof Timestamp);
            await assertFails(reportContent(dbFor(uid), groupId, kind, 'target', uid, { reason }));
        }
        assert.equal((await listReports(dbFor('owner'), groupId, kind, 'target')).length, 4);
        assert.equal(await getReport(dbFor('reader'), groupId, kind, 'missing', 'reader'), null);
    });

    test(`${kind}: missing target and same-batch new target cannot be reported`, async () => {
        const db = dbFor('reader');
        await assertFails(setDoc(reportRef(db, kind, 'reader', 'missing'), reportData()));
        const batch = writeBatch(db);
        batch.set(item(db, kind, 'new'), itemData(kind));
        batch.set(reportRef(db, kind, 'reader', 'new'), reportData());
        await assertFails(batch.commit());
        assert.equal((await getDocFromServer(item(db, kind, 'new'))).exists(), false);
    });

    test(`${kind}: report identity is self-authenticated regardless of role or forged claims`, async () => {
        for (const uid of ['owner', 'lead', 'other', 'outsider']) {
            await assertFails(setDoc(reportRef(dbFor(uid), kind), reportData()));
        }
        for (const db of [anonymous(), dbFor('outsider', { admin: true, role: 'admin', groupId }),
        dbFor('reader', { reporterUid: 'other' })]) {
            await assertFails(setDoc(reportRef(db, kind, 'other'), reportData({ reporterUid: 'other' })));
        }
        await assertFails(setDoc(reportRef(dbFor('reader'), kind), reportData({ reporterUid: 'other' })));
    });

    test(`${kind}: report exact fields reject omissions, content, identity and permission copies`, async () => {
        for (const key of Object.keys(reportData())) {
            const incomplete = reportData(); delete incomplete[key];
            await assertFails(setDoc(reportRef(dbFor('reader'), kind), incomplete));
        }
        for (const extra of [{ text: 'copy' }, { quote: 'copy' }, { senderUid: 'reader' },
        { displayName: 'private' }, { groupId }, { role: 'admin' }, { targetId: 'target' }]) {
            await assertFails(setDoc(reportRef(dbFor('reader'), kind), reportData(extra)));
        }
    });

    test(`${kind}: raw report value bounds and server creation time are enforced`, async () => {
        for (const overrides of [
            ...['SPAM', '', null, 1, {}, 'blocked'].map(reason => ({ reason })),
            ...['x'.repeat(1001), null, 1, true, {}, []].map(details => ({ details })),
            ...[Timestamp.fromMillis(0), Timestamp.fromMillis(4102444800000), null, 'now'].map(createdAt => ({ createdAt })),
            { status: 'resolved' }, { status: 'dismissed' }, { status: null },
            { resolvedBy: 'owner' }, { resolvedAt: serverTimestamp() },
        ]) await assertFails(setDoc(reportRef(dbFor('reader'), kind), reportData(overrides)));
    });

    test(`${kind}: only reporter or current admin gets reports; only admin lists even own reports`, async () => {
        await setDoc(reportRef(dbFor('reader'), kind), reportData());
        await assertSucceeds(getReport(dbFor('reader'), groupId, kind, 'target', 'reader'));
        await assertSucceeds(getReport(dbFor('owner'), groupId, kind, 'target', 'reader'));
        for (const db of [dbFor('lead'), dbFor('other'), dbFor('outsider'), anonymous(),
        dbFor('outsider', { admin: true, role: 'admin', groupId })]) {
            await assertFails(getReport(db, groupId, kind, 'target', 'reader'));
            await assertFails(listReports(db, groupId, kind, 'target'));
        }
        await assertFails(listReports(dbFor('reader'), groupId, kind, 'target'));
        const db = dbFor('reader');
        await assertFails(getDocsFromServer(query(collection(item(db, kind), 'reports'), limit(1))));
    });

    test(`${kind}: admin one-way resolution and dismissal preserve identity without deleting target`, async () => {
        for (const [uid, status] of [['reader', 'resolved'], ['other', 'dismissed']]) {
            await reportContent(dbFor(uid), groupId, kind, 'target', uid, { reason: 'other', details: 'Not trimmed  ' });
            const original = await getReport(dbFor(uid), groupId, kind, 'target', uid);
            await assertSucceeds(resolveReport(dbFor('owner'), groupId, kind, 'target', uid, 'owner', status));
            const resolved = await getReport(dbFor(uid), groupId, kind, 'target', uid);
            assert.equal(resolved.status, status);
            assert.equal(resolved.resolvedBy, 'owner');
            assert.ok(resolved.resolvedAt instanceof Timestamp);
            for (const field of ['reporterUid', 'reason', 'details', 'createdAt']) assert.deepEqual(resolved[field], original[field]);
            for (const next of ['open', 'resolved', 'dismissed']) {
                await assertFails(updateDoc(reportRef(dbFor('owner'), kind, uid), {
                    status: next, resolvedBy: 'owner', resolvedAt: serverTimestamp(),
                }));
            }
        }
        assert.ok((await state(kind))[0]);
        assert.equal((await state(kind))[1], null);
    });

    test(`${kind}: resolution rejects nonadmins, actor/time forgery, missing fields and identity edits`, async () => {
        await setDoc(reportRef(dbFor('reader'), kind), reportData());
        for (const uid of ['reader', 'lead', 'other', 'outsider']) {
            await assertFails(resolveReport(dbFor(uid), groupId, kind, 'target', 'reader', uid, 'resolved'));
        }
        await assertFails(resolveReport(anonymous(), groupId, kind, 'target', 'reader', 'owner', 'resolved'));
        const change = { status: 'resolved', resolvedBy: 'owner', resolvedAt: serverTimestamp() };
        for (const overrides of [{ resolvedBy: 'reader' }, { resolvedBy: null },
        { resolvedAt: Timestamp.fromMillis(0) }, { resolvedAt: null }, { resolvedAt: 'now' },
        { status: 'open' }, { status: 'hidden' }, { reason: 'other' }, { details: 'Edited' },
        { reporterUid: 'other' }, { createdAt: serverTimestamp() }, { text: 'copy' }]) {
            await assertFails(updateDoc(reportRef(dbFor('owner'), kind), { ...change, ...overrides }));
        }
        for (const key of Object.keys(change)) {
            const incomplete = { ...change }; delete incomplete[key];
            await assertFails(updateDoc(reportRef(dbFor('owner'), kind), incomplete));
        }
        assert.equal((await getReport(dbFor('reader'), groupId, kind, 'target', 'reader')).status, 'open');
    });

    test(`${kind}: reports can never be client-deleted or overwritten by reporter or admin`, async () => {
        await setDoc(reportRef(dbFor('reader'), kind), reportData());
        for (const uid of ['reader', 'owner', 'lead', 'other']) {
            await assertFails(deleteDoc(reportRef(dbFor(uid), kind)));
            await assertFails(setDoc(reportRef(dbFor(uid), kind), reportData()));
        }
    });

    test(`${kind}: admin atomic removal stores exact minimal immutable author audit without a report`, async () => {
        const original = (await state(kind))[0];
        assert.equal(await assertSucceeds(removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'inappropriate')), 'target');
        const [target, audit, report] = await state(kind);
        assert.equal(target, null);
        assert.equal(report, null);
        assert.deepEqual(Object.keys(audit).sort(), ['authorUid', 'moderatedAt', 'moderatedBy', 'reason', 'targetId', 'targetKind']);
        assert.equal(audit.authorUid, original.senderUid);
        assert.equal(audit.targetKind, kind);
        assert.equal(audit.targetId, 'target');
        assert.equal(audit.moderatedBy, 'owner');
        assert.equal(audit.reason, 'inappropriate');
        assert.ok(audit.moderatedAt instanceof Timestamp);
        assert.deepEqual((await listModerationRecords(dbFor('owner'), groupId, kind))[0], { id: 'target', ...audit });
    });

    test(`${kind}: admin may remove own creator-authored content and any member role's content`, async () => {
        for (const uid of ['owner', 'lead', 'reader', 'other']) {
            await setDoc(item(dbFor(uid), kind, uid), itemData(kind, uid));
            await assertSucceeds(removeContent(dbFor('owner'), groupId, kind, uid, 'owner', 'other'));
            assert.equal((await state(kind, uid))[1].authorUid, uid);
        }
    });

    test(`${kind}: marker-only, delete-only and missing prewrite target fail atomically`, async () => {
        await deniedRemoval(removalBatch(dbFor('owner'), kind, { remove: false }), kind);
        await deniedRemoval(removalBatch(dbFor('owner'), kind, { mark: false }), kind);
        await assertFails(deleteDoc(item(dbFor('owner'), kind)));
        await assertFails(setDoc(marker(dbFor('owner'), kind, 'missing'), markerData(kind, { targetId: 'missing' })));
        await assertFails(removalBatch(dbFor('owner'), kind, { id: 'missing', data: markerData(kind, { targetId: 'missing' }) }).commit());
        const db = dbFor('owner');
        const batch = writeBatch(db);
        batch.set(item(db, kind, 'new'), itemData(kind, 'owner'));
        batch.set(marker(db, kind, 'new'), markerData(kind, { targetId: 'new', authorUid: 'owner' }));
        await assertFails(batch.commit());
    });

    test(`${kind}: tombstone exact schema rejects omissions and every copied-content/identity extra`, async () => {
        for (const key of Object.keys(markerData(kind))) {
            const incomplete = markerData(kind); delete incomplete[key];
            await deniedRemoval(removalBatch(dbFor('owner'), kind, { data: incomplete }), kind);
        }
        for (const extra of [{ text: 'copy' }, { quote: 'copy' }, { details: 'copy' },
        { displayName: 'private' }, { email: 'private' }, { role: 'admin' }, { groupId }, { reportCount: 1 }]) {
            await deniedRemoval(removalBatch(dbFor('owner'), kind, { data: markerData(kind, extra) }), kind);
        }
    });

    test(`${kind}: immutable target/author, moderator, reason and server-time forgery denied`, async () => {
        for (const overrides of [{ targetKind: kind === 'messages' ? 'highlights' : 'messages' },
        { targetKind: 'chat' }, { targetId: 'other' }, { targetId: null },
        { authorUid: 'owner' }, { authorUid: null }, { authorUid: 1 },
        { moderatedBy: 'reader' }, { moderatedBy: null },
        { moderatedAt: Timestamp.fromMillis(0) }, { moderatedAt: Timestamp.fromMillis(4102444800000) },
        { moderatedAt: null }, { moderatedAt: 'now' }, { reason: 'delete' }, { reason: null }, { reason: 1 }]) {
            await deniedRemoval(removalBatch(dbFor('owner'), kind, { data: markerData(kind, overrides) }), kind);
        }
    });

    test(`${kind}: lead, author, members, outsiders, anonymous and claims cannot moderate`, async () => {
        for (const [db, actor] of [[dbFor('lead'), 'lead'], [dbFor('reader'), 'reader'],
        [dbFor('other'), 'other'], [dbFor('outsider'), 'outsider'], [anonymous(), 'owner'],
        [dbFor('reader', { admin: true, role: 'admin', groupId }), 'reader']]) {
            await deniedRemoval(removalBatch(db, kind, { data: markerData(kind, { moderatedBy: actor }) }), kind);
            await assertFails(removeContent(db, groupId, kind, 'target', actor, 'spam'));
        }
        await assertFails(removeContent(dbFor('owner'), groupId, kind, 'target', 'reader', 'spam'));
    });

    test(`${kind}: marker cannot authorize another kind, item ID or group`, async () => {
        const anotherGroup = await createGroup(dbFor('owner'), 'owner', { name: 'Second owned group' });
        await setDoc(item(dbFor('owner'), kind, 'target', anotherGroup), itemData(kind, 'owner'));
        for (const options of [
            { markerKind: kind === 'messages' ? 'highlights' : 'messages' },
            { markerId: 'other', data: markerData(kind, { targetId: 'other' }) },
            { markerGroup: anotherGroup },
        ]) await deniedRemoval(removalBatch(dbFor('owner'), kind, options), kind);
        assert.ok((await state(kind, 'target', anotherGroup))[0]);
        assert.equal((await state(kind, 'target', anotherGroup))[1], null);
    });

    test(`${kind}: audit get/list is admin-only, immutable and duplicate removal fails`, async () => {
        await removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'spam');
        const original = await state(kind);
        await assertSucceeds(getDocFromServer(marker(dbFor('owner'), kind)));
        for (const db of [dbFor('reader'), dbFor('lead'), dbFor('other'), dbFor('outsider'), anonymous()]) {
            await assertFails(getDocFromServer(marker(db, kind)));
            await assertFails(listModerationRecords(db, groupId, kind));
        }
        for (const db of [dbFor('owner'), dbFor('reader')]) {
            await assertFails(updateDoc(marker(db, kind), { reason: 'other' }));
            await assertFails(deleteDoc(marker(db, kind)));
            await assertFails(setDoc(marker(db, kind), markerData(kind)));
        }
        await assert.rejects(removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'spam'), /already been moderated/);
        await assertFails(removalBatch(dbFor('owner'), kind).commit());
        assert.deepEqual(await state(kind), original);
    });

    test(`${kind}: tombstone reserves deleted ID against author/admin recreation and replay`, async () => {
        await removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'spam');
        for (const uid of ['reader', 'owner', 'lead']) {
            await assertFails(setDoc(item(dbFor(uid), kind), itemData(kind, uid)));
        }
        await environment.withSecurityRulesDisabled(async context => {
            await setDoc(item(context.firestore(), kind), itemData(kind));
        });
        await assertFails(deleteDoc(item(dbFor('owner'), kind)));
        await assertFails(removalBatch(dbFor('owner'), kind).commit());
        await assert.rejects(removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'spam'), /already been moderated/);
    });

    test(`${kind}: retained reports readable/resolvable under absent parent, no new report after removal`, async () => {
        await reportContent(dbFor('reader'), groupId, kind, 'target', 'reader', { reason: 'harassment', details: 'Evidence description' });
        const original = (await state(kind))[2];
        await removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'harassment');
        assert.deepEqual((await state(kind))[2], original);
        assert.equal((await getReport(dbFor('reader'), groupId, kind, 'target', 'reader')).details, 'Evidence description');
        assert.equal((await listReports(dbFor('owner'), groupId, kind, 'target')).length, 1);
        await assertFails(getReport(dbFor('other'), groupId, kind, 'target', 'reader'));
        await assertFails(reportContent(dbFor('other'), groupId, kind, 'target', 'other', { reason: 'spam' }));
        await assertSucceeds(resolveReport(dbFor('owner'), groupId, kind, 'target', 'reader', 'owner', 'resolved'));
        await assertFails(deleteDoc(reportRef(dbFor('owner'), kind)));
    });

    test(`${kind}: current membership revocation shields retained reports and audits on next server read`, async () => {
        const readerDb = dbFor('reader');
        const ownerDb = dbFor('owner');
        await reportContent(readerDb, groupId, kind, 'target', 'reader', { reason: 'spam' });
        await removeContent(ownerDb, groupId, kind, 'target', 'owner', 'spam');
        await getReport(readerDb, groupId, kind, 'target', 'reader');
        await listModerationRecords(ownerDb, groupId, kind);
        await removeMember(ownerDb, groupId, 'owner', 'reader');
        await assertFails(getReport(readerDb, groupId, kind, 'target', 'reader'));
        await assertFails(reportContent(readerDb, groupId, kind, 'target', 'reader', { reason: 'spam' }));
        await assertSucceeds(getReport(ownerDb, groupId, kind, 'target', 'reader'));
        await environment.withSecurityRulesDisabled(async context => {
            await deleteDoc(doc(context.firestore(), 'groups', groupId, 'members', 'owner'));
        });
        await assertFails(getReport(ownerDb, groupId, kind, 'target', 'reader'));
        await assertFails(listReports(ownerDb, groupId, kind, 'target'));
        await assertFails(getDocFromServer(marker(ownerDb, kind)));
        await assertFails(listModerationRecords(ownerDb, groupId, kind));
        await assertFails(resolveReport(ownerDb, groupId, kind, 'target', 'reader', 'owner', 'resolved'));
    });

    test(`${kind}: unrelated group admin/invitation bearer cannot report, read or moderate here`, async () => {
        const unrelated = await createGroup(dbFor('outsider'), 'outsider', { name: 'Unrelated' });
        await setDoc(item(dbFor('outsider'), kind, 'target', unrelated), itemData(kind, 'outsider'));
        await reportContent(dbFor('reader'), groupId, kind, 'target', 'reader', { reason: 'spam' });
        await createInvitation(dbFor('owner'), groupId, 'owner');
        await assertFails(getReport(dbFor('outsider'), groupId, kind, 'target', 'reader'));
        await assertFails(reportContent(dbFor('outsider'), groupId, kind, 'target', 'outsider', { reason: 'spam' }));
        await assertFails(removeContent(dbFor('outsider'), groupId, kind, 'target', 'outsider', 'spam'));
        await assertFails(listModerationRecords(dbFor('outsider'), groupId, kind));
        await assertFails(removeContent(dbFor('owner'), unrelated, kind, 'target', 'owner', 'spam'));
    });

    test(`${kind}: same-batch privilege promotion cannot bootstrap moderation or resolution`, async () => {
        await reportContent(dbFor('reader'), groupId, kind, 'target', 'reader', { reason: 'spam' });
        const db = dbFor('lead');
        const batch = removalBatch(db, kind, { data: markerData(kind, { moderatedBy: 'lead' }) });
        batch.update(doc(db, 'groups', groupId, 'members', 'lead'), { role: 'admin' });
        await deniedRemoval(batch, kind);
        const resolve = writeBatch(db);
        resolve.update(doc(db, 'groups', groupId, 'members', 'lead'), { role: 'admin' });
        resolve.update(reportRef(db, kind), { status: 'resolved', resolvedBy: 'lead', resolvedAt: serverTimestamp() });
        await assertFails(resolve.commit());
    });

    test(`${kind}: concurrent moderation transactions yield exactly one immutable removal`, async () => {
        await environment.withSecurityRulesDisabled(async context => {
            await updateDoc(doc(context.firestore(), 'groups', groupId, 'members', 'other'), { role: 'admin' });
        });
        const results = await Promise.allSettled(['owner', 'other'].map(uid =>
            removeContent(dbFor(uid), groupId, kind, 'target', uid, 'spam')));
        assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
        assert.equal(results.filter(result => result.status === 'rejected').length, 1);
        const [target, audit] = await state(kind);
        assert.equal(target, null);
        assert.ok(['owner', 'other'].includes(audit.moderatedBy));
        assert.equal((await listModerationRecords(dbFor('owner'), groupId, kind)).length, 1);
    });

    test(`${kind}: duplicate report and resolution races each permit only one winner`, async () => {
        const reports = await Promise.allSettled(Array.from({ length: 2 }, () =>
            reportContent(dbFor('reader'), groupId, kind, 'target', 'reader', { reason: 'other' })));
        assert.equal(reports.filter(result => result.status === 'fulfilled').length, 1);
        const resolutions = await Promise.allSettled(['resolved', 'dismissed'].map(status =>
            resolveReport(dbFor('owner'), groupId, kind, 'target', 'reader', 'owner', status)));
        assert.equal(resolutions.filter(result => result.status === 'fulfilled').length, 1);
        assert.ok(['resolved', 'dismissed'].includes((await getReport(dbFor('reader'), groupId, kind, 'target', 'reader')).status));
    });

    test(`${kind}: reporting/removal race permits only a retained prewrite report or denial`, async () => {
        const results = await Promise.allSettled([
            reportContent(dbFor('reader'), groupId, kind, 'target', 'reader', { reason: 'spam' }),
            removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'spam'),
        ]);
        assert.equal(results[1].status, 'fulfilled');
        const [target, audit, report] = await state(kind);
        assert.equal(target, null);
        assert.ok(audit);
        assert.equal(report !== null, results[0].status === 'fulfilled');
        await assertFails(reportContent(dbFor('other'), groupId, kind, 'target', 'other', { reason: 'spam' }));
    });

    test(`${kind}: admin query bounds reject unbounded, 51, cross-group and collection-group discovery`, async () => {
        await reportContent(dbFor('reader'), groupId, kind, 'target', 'reader', { reason: 'spam' });
        await removeContent(dbFor('owner'), groupId, kind, 'target', 'owner', 'spam');
        const db = dbFor('owner');
        for (const reference of [collection(item(db, kind), 'reports'),
        collection(db, 'groups', groupId, 'moderationRecords', kind, 'items')]) {
            await assertSucceeds(getDocsFromServer(query(reference, limit(50))));
            await assertFails(getDocsFromServer(reference));
            await assertFails(getDocsFromServer(query(reference, limit(51))));
        }
        for (const name of ['reports', 'items']) {
            await assertFails(getDocsFromServer(query(collectionGroup(db, name), limit(50))));
        }
        await assertFails(getDocsFromServer(query(collection(db, 'groups', 'missing', 'moderationRecords', kind, 'items'), limit(50))));
    });

    test(`${kind}: stable document-ID lists paginate 57 reports and audits without new indexes`, async () => {
        const ids = Array.from({ length: 57 }, (_, index) => `id-${String(index).padStart(3, '0')}`);
        // Privileged fixture only for scale; authorization/create contracts are
        // tested above with real clients. No fabricated clock bypass in helpers.
        await environment.withSecurityRulesDisabled(async context => {
            const db = context.firestore();
            const batch = writeBatch(db);
            for (const id of ids) {
                batch.set(reportRef(db, kind, id), reportData({ reporterUid: id }));
                batch.set(marker(db, kind, id), markerData(kind, { targetId: id }));
            }
            await batch.commit();
        });
        for (const list of [options => listReports(dbFor('owner'), groupId, kind, 'target', options),
        options => listModerationRecords(dbFor('owner'), groupId, kind, options)]) {
            const first = await list();
            assert.equal(first.length, 50);
            const second = await list({ after: first.at(-1).id });
            assert.equal(second.length, 7);
            assert.deepEqual([...first, ...second].map(entry => entry.id), ids);
            assert.deepEqual(await list({ after: second.at(-1).id }), []);
            assert.deepEqual((await list({ pageSize: 1 })).map(entry => entry.id), [ids[0]]);
        }
    });
}

test('moderation clients validate every path segment, kind, reason, status, details, page and cursor', async () => {
    const db = dbFor('owner');
    const valid = ['messages', 'target', 'reader'];
    for (const bad of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501), null, 1]) {
        for (const [group, kind, id, uid] of [[bad, ...valid], [groupId, 'messages', bad, 'reader'],
        [groupId, 'messages', 'target', bad]]) {
            await assert.rejects(reportContent(db, group, kind, id, uid, { reason: 'spam' }), /path segment/);
            await assert.rejects(getReport(db, group, kind, id, uid), /path segment/);
            await assert.rejects(resolveReport(db, group, kind, id, uid, 'owner', 'resolved'), /path segment/);
        }
        await assert.rejects(removeContent(db, groupId, 'messages', bad, 'owner', 'spam'), /path segment/);
        await assert.rejects(removeContent(db, groupId, 'messages', 'target', bad, 'spam'), /path segment/);
        await assert.rejects(resolveReport(db, groupId, 'messages', 'target', 'reader', bad, 'resolved'), /path segment/);
        await assert.rejects(listReports(db, bad, 'messages', 'target'), /path segment/);
        await assert.rejects(listReports(db, groupId, 'messages', bad), /path segment/);
        await assert.rejects(listModerationRecords(db, bad, 'messages'), /path segment/);
    }
    for (const kind of ['chat', 'message', '', 'messages/x', null, 1]) {
        for (const call of [
            () => reportContent(db, groupId, kind, 'target', 'reader', { reason: 'spam' }),
            () => getReport(db, groupId, kind, 'target', 'reader'),
            () => listReports(db, groupId, kind, 'target'),
            () => resolveReport(db, groupId, kind, 'target', 'reader', 'owner', 'resolved'),
            () => removeContent(db, groupId, kind, 'target', 'owner', 'spam'),
            () => listModerationRecords(db, groupId, kind),
        ]) await assert.rejects(call(), /Kind/);
    }
    for (const reason of ['', 'SPAM', 'delete', null, 1]) {
        await assert.rejects(reportContent(db, groupId, 'messages', 'target', 'owner', { reason }), /Reason/);
        await assert.rejects(removeContent(db, groupId, 'messages', 'target', 'owner', reason), /Reason/);
    }
    for (const details of ['x'.repeat(1001), null, 1, {}]) {
        await assert.rejects(reportContent(db, groupId, 'messages', 'target', 'owner', { reason: 'other', details }), /Details/);
    }
    for (const status of ['open', 'hidden', '', null, 1]) {
        await assert.rejects(resolveReport(db, groupId, 'messages', 'target', 'reader', 'owner', status), /Status/);
    }
    for (const pageSize of [0, 51, -1, 1.5, '1', null, NaN, Infinity]) {
        await assert.rejects(listReports(db, groupId, 'messages', 'target', { pageSize }), /Page size/);
        await assert.rejects(listModerationRecords(db, groupId, 'messages', { pageSize }), /Page size/);
    }
    for (const after of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501), {}, 1]) {
        await assert.rejects(listReports(db, groupId, 'messages', 'target', { after }), /path segment/);
        await assert.rejects(listModerationRecords(db, groupId, 'messages', { after }), /path segment/);
    }
});

test('unknown report/audit kinds and parent audit documents remain locked', async () => {
    const db = dbFor('owner');
    for (const kind of ['chat', 'members', 'readingWeeks']) {
        await assertFails(setDoc(reportRef(db, kind, 'owner'), reportData({ reporterUid: 'owner' })));
        await assertFails(getDocFromServer(reportRef(db, kind, 'owner')));
        await assertFails(setDoc(marker(db, kind), markerData(kind)));
        await assertFails(getDocFromServer(marker(db, kind)));
        await assertFails(getDocsFromServer(query(collection(db, 'groups', groupId, 'moderationRecords', kind, 'items'), limit(50))));
    }
    await assertFails(setDoc(doc(db, 'groups', groupId, 'moderationRecords', 'messages'), { privileged: true }));
    await assertFails(getDocFromServer(doc(db, 'groups', groupId, 'moderationRecords', 'messages')));
});