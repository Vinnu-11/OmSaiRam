import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, getDocFromServer, getDocsFromServer,
    setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp, query, limit,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole, listMyGroups, listMembers } from '../src/groups.mjs';
import { leaveGroup, removeMember } from '../src/membership-lifecycle.mjs';
import { setMemberDisplay, listMemberDisplays } from '../src/member-display.mjs';
import { createInvitation, joinWithInvitation } from '../src/invitations.mjs';
import { assignmentReference, createAssignment, listAssignments, updateReadingProgress } from '../src/assignments.mjs';
import { sendMessage, getMessage, listMessages } from '../src/chat.mjs';
import { createHighlight, getHighlight, listHighlights } from '../src/highlights.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();
const member = (db, uid = 'reader', group = groupId) => doc(db, 'groups', group, 'members', uid);
const index = (db, uid = 'reader', group = groupId) => doc(db, 'users', uid, 'groups', group);
const profile = (db, uid = 'reader', group = groupId) => doc(db, 'groups', group, 'memberProfiles', uid);
const marker = (db, uid = 'reader', group = groupId) => doc(db, 'groups', group, 'departures', uid);
const markerData = (actor = 'owner', uid = 'reader', overrides = {}) => ({
    userId: uid, removedBy: actor, removedAt: serverTimestamp(),
    reason: actor === uid ? 'left' : 'removed', ...overrides,
});

// Raw SDK writes intentionally bypass helper validation. Each omitted component
// must fail atomically; assertions inspect actual server state, not local cache.
function rawBatch(db, actor = 'owner', uid = 'reader', {
    deletes = ['member', 'index', 'profile'], data = markerData(actor, uid),
    mark = true, group = groupId,
} = {}) {
    const batch = writeBatch(db);
    if (mark) batch.set(marker(db, uid, group), data);
    if (deletes.includes('member')) batch.delete(member(db, uid, group));
    if (deletes.includes('index')) batch.delete(index(db, uid, group));
    if (deletes.includes('profile')) batch.delete(profile(db, uid, group));
    return batch;
}

async function state(uid = 'reader', group = groupId) {
    let result;
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        const snapshots = await Promise.all([member(db, uid, group), index(db, uid, group),
        profile(db, uid, group), marker(db, uid, group)].map(getDocFromServer));
        result = snapshots.map(snapshot => snapshot.exists() ? snapshot.data() : null);
    });
    return result;
}

async function denied(batch, uid = 'reader', group = groupId) {
    const before = await state(uid, group);
    await assertFails(batch.commit());
    assert.deepEqual(await state(uid, group), before);
}

async function departed(uid, actor, reason) {
    const [membership, discovery, display, departure] = await state(uid);
    assert.equal(membership, null);
    assert.equal(discovery, null);
    assert.equal(display, null);
    assert.deepEqual(Object.keys(departure).sort(), ['reason', 'removedAt', 'removedBy', 'userId']);
    assert.equal(departure.userId, uid);
    assert.equal(departure.removedBy, actor);
    assert.equal(departure.reason, reason);
    assert.ok(departure.removedAt instanceof Timestamp);
    return departure;
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
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Membership lifecycle' });
    for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('member leaves without shared display: three-write transaction succeeds within rule budget', async () => {
    assert.equal(await assertSucceeds(leaveGroup(dbFor('reader'), groupId, 'reader')), 'reader');
    await departed('reader', 'reader', 'left');
});

test('member leaves with shared display: full four-write transaction succeeds within rule budget', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Shared alias');
    await assertSucceeds(leaveGroup(dbFor('reader'), groupId, 'reader'));
    await departed('reader', 'reader', 'left');
});

test('lead may leave themselves with shared display', async () => {
    await setMemberDisplay(dbFor('lead'), groupId, 'lead', 'Lead alias');
    await assertSucceeds(leaveGroup(dbFor('lead'), groupId, 'lead'));
    await departed('lead', 'lead', 'left');
});

test('admin removes ordinary member and shared display without reading their private index', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Shared alias');
    await assertFails(getDocFromServer(index(dbFor('owner'))));
    await assertSucceeds(removeMember(dbFor('owner'), groupId, 'owner', 'reader'));
    await departed('reader', 'owner', 'removed');
});

test('admin removes lead with shared display within full transaction rule budget', async () => {
    await setMemberDisplay(dbFor('lead'), groupId, 'lead', 'Lead alias');
    await assertSucceeds(removeMember(dbFor('owner'), groupId, 'owner', 'lead'));
    await departed('lead', 'owner', 'removed');
});

test('lead removes ordinary member with shared display but still cannot read private index', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Shared alias');
    await assertFails(getDocFromServer(index(dbFor('lead'))));
    await assertSucceeds(removeMember(dbFor('lead'), groupId, 'lead', 'reader'));
    await departed('reader', 'lead', 'removed');
});

test('raw coordinated batch succeeds when optional profile is absent and omitted', async () => {
    await assertSucceeds(rawBatch(dbFor('reader'), 'reader', 'reader', { deletes: ['member', 'index'] }).commit());
    await departed('reader', 'reader', 'left');
});

test('raw coordinated batch succeeds with optional absent-profile delete', async () => {
    await assertSucceeds(rawBatch(dbFor('owner')).commit());
    await departed('reader', 'owner', 'removed');
});

for (const deletes of [[], ['member'], ['index'], ['profile'],
['member', 'index'], ['member', 'profile'], ['index', 'profile']]) {
    test(`partial departure [${deletes.join(',') || 'marker only'}] is denied without any partial writes`, async () => {
        await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Keep until atomic departure');
        await denied(rawBatch(dbFor('owner'), 'owner', 'reader', { deletes }));
    });
}

test('missing tombstone denies combined deletes and every standalone delete, including owner index delete', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Keep');
    for (const uid of ['owner', 'reader']) {
        const db = dbFor(uid);
        await denied(rawBatch(db, uid, 'reader', { mark: false }));
        for (const reference of [member(db), index(db), profile(db)]) await assertFails(deleteDoc(reference));
    }
});

test('tombstone exact schema rejects missing fields and private identity, token or permissions copies', async () => {
    for (const key of Object.keys(markerData())) {
        const data = markerData(); delete data[key];
        await denied(rawBatch(dbFor('owner'), 'owner', 'reader', { data }));
    }
    for (const extra of [{ displayName: 'Private reader' }, { email: 'private' },
    { inviteToken: 'a'.repeat(64) }, { role: 'admin' }, { groupId }, { token: 'secret' }]) {
        await denied(rawBatch(dbFor('owner'), 'owner', 'reader', { data: markerData('owner', 'reader', extra) }));
    }
});

test('tombstone actor, target, reason and server time cannot be forged', async () => {
    for (const overrides of [{ userId: 'other' }, { removedBy: 'reader' }, { removedBy: null },
    { removedAt: Timestamp.fromMillis(0) }, { removedAt: Timestamp.fromMillis(4102444800000) },
    { removedAt: null }, { removedAt: 'now' }, { reason: 'left' }, { reason: 'deleted' }, { reason: null }]) {
        await denied(rawBatch(dbFor('owner'), 'owner', 'reader', { data: markerData('owner', 'reader', overrides) }));
    }
    await denied(rawBatch(dbFor('reader'), 'reader', 'reader', { data: markerData('reader', 'reader', { reason: 'removed' }) }));
});

test('ordinary members, outsiders, anonymous and forged claims cannot remove another member', async () => {
    for (const [db, actor] of [[dbFor('other'), 'other'], [dbFor('outsider'), 'outsider'],
    [dbFor('outsider', { admin: true, role: 'admin', userId: 'owner', groupId }), 'outsider'],
    [anonymous(), 'owner']]) {
        await denied(rawBatch(db, actor));
        await assert.rejects(removeMember(db, groupId, actor, 'reader'));
    }
});

test('helper actor spoofing cannot borrow owner or lead authority', async () => {
    for (const uid of ['other', 'lead', 'outsider']) {
        await assert.rejects(removeMember(dbFor(uid), groupId, 'owner', 'reader'));
    }
    await assertFails(leaveGroup(dbFor('other'), groupId, 'reader'));
    assert.ok((await state())[0]);
});

test('leads cannot remove another lead or admin, including noncreator privileged targets', async () => {
    await setMemberRole(dbFor('owner'), groupId, 'other', 'group_lead');
    for (const uid of ['other', 'owner']) {
        await denied(rawBatch(dbFor('lead'), 'lead', uid), uid);
        await assert.rejects(removeMember(dbFor('lead'), groupId, 'lead', uid));
    }
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(member(context.firestore(), 'other'), { role: 'admin' });
    });
    await denied(rawBatch(dbFor('lead'), 'lead', 'other'), 'other');
});

test('creator is immune to self-leave and removal even if privileged fixture demotes creator', async () => {
    await assert.rejects(leaveGroup(dbFor('owner'), groupId, 'owner'), /owner/);
    await denied(rawBatch(dbFor('owner'), 'owner', 'owner'), 'owner');
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        await updateDoc(member(db, 'owner'), { role: 'member' });
        await updateDoc(member(db, 'other'), { role: 'admin' });
    });
    await denied(rawBatch(dbFor('other'), 'other', 'owner'), 'owner');
    await denied(rawBatch(dbFor('lead'), 'lead', 'owner'), 'owner');
    await assert.rejects(leaveGroup(dbFor('owner'), groupId, 'owner'), /owner/);
});

test('noncreator admin cannot self-leave or label self-removal as removed; another admin may remove them', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(member(context.firestore(), 'other'), { role: 'admin' });
    });
    await assert.rejects(leaveGroup(dbFor('other'), groupId, 'other'), /nonadmin/);
    await assert.rejects(removeMember(dbFor('other'), groupId, 'other', 'other'), /remove others/);
    for (const reason of ['left', 'removed']) {
        await denied(rawBatch(dbFor('other'), 'other', 'other', { data: markerData('other', 'other', { reason }) }), 'other');
    }
    await assertSucceeds(removeMember(dbFor('owner'), groupId, 'owner', 'other'));
    await departed('other', 'owner', 'removed');
});

test('marker creation requires both prewrite member and index; inconsistent fixtures fail closed', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(index(context.firestore()));
    });
    await denied(rawBatch(dbFor('owner')));
    await assertFails(removeMember(dbFor('owner'), groupId, 'owner', 'reader'));
    await denied(rawBatch(dbFor('owner'), 'owner', 'outsider'), 'outsider');
    await denied(rawBatch(dbFor('outsider'), 'outsider', 'outsider'), 'outsider');
});

test('missing or deleted parent group cannot authorize departures through orphaned memberships', async () => {
    await denied(rawBatch(dbFor('owner'), 'owner', 'reader', { group: 'missing' }), 'reader', 'missing');
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId));
    });
    await denied(rawBatch(dbFor('owner')));
});

test('actual group discovery and roster/display lists update after removal; unrelated group stays visible', async () => {
    const db = dbFor('reader');
    const otherGroup = await createGroup(dbFor('owner'), 'owner', { name: 'Unrelated' });
    await addMember(dbFor('owner'), otherGroup, 'reader');
    await setMemberDisplay(db, groupId, 'reader', 'Reader');
    assert.equal((await listMyGroups(db, 'reader')).length, 2);
    assert.ok((await listMembers(dbFor('other'), groupId)).some(row => row.id === 'reader'));
    await removeMember(dbFor('owner'), groupId, 'owner', 'reader');
    assert.deepEqual((await listMyGroups(db, 'reader')).map(row => row.id), [otherGroup]);
    assert.equal((await listMembers(dbFor('other'), groupId)).some(row => row.id === 'reader'), false);
    assert.deepEqual(await listMemberDisplays(dbFor('other'), groupId), []);
    assert.ok((await state('reader', otherGroup))[0]);
    assert.ok((await getDocFromServer(doc(db, 'users', 'reader'))).exists());
    await assertFails(getDocFromServer(doc(db, 'groups', groupId)));
    await assertFails(listMembers(db, groupId));
    await assertFails(listMemberDisplays(db, groupId));
});

test('self-leave makes listMyGroups empty, not a stale index causing permission errors', async () => {
    const db = dbFor('reader');
    assert.equal((await listMyGroups(db, 'reader')).length, 1);
    await leaveGroup(db, groupId, 'reader');
    assert.deepEqual(await listMyGroups(db, 'reader'), []);
});

test('valid departure cannot delete unrelated user/group indexes or private profiles', async () => {
    const otherGroup = await createGroup(dbFor('owner'), 'owner', { name: 'Unrelated' });
    await addMember(dbFor('owner'), otherGroup, 'reader');
    const db = dbFor('owner');
    for (const reference of [index(db, 'other'), index(db, 'reader', otherGroup), doc(db, 'users', 'reader')]) {
        const batch = rawBatch(db);
        batch.delete(reference);
        await denied(batch);
    }
    assert.ok((await state('reader', otherGroup))[1]);
    assert.ok((await state('other'))[1]);
});

for (const reason of ['left', 'removed']) {
    test(`${reason} tombstone blocks helper and raw invitation rejoin/admin-add without reviving membership`, async () => {
        const token = await createInvitation(dbFor('owner'), groupId, 'owner');
        if (reason === 'left') await leaveGroup(dbFor('reader'), groupId, 'reader');
        else await removeMember(dbFor('owner'), groupId, 'owner', 'reader');
        await assertFails(addMember(dbFor('owner'), groupId, 'reader'));
        await assertFails(joinWithInvitation(dbFor('reader'), 'reader', token));
        for (const [db, inviteToken] of [[dbFor('owner'), null], [dbFor('reader'), token]]) {
            const batch = writeBatch(db);
            batch.set(member(db), { userId: 'reader', role: 'member', joinedAt: serverTimestamp() });
            batch.set(index(db), { groupId, joinedAt: serverTimestamp(), ...(inviteToken ? { inviteToken } : {}) });
            await denied(batch);
        }
        await departed('reader', reason === 'left' ? 'reader' : 'owner', reason);
    });
}

test('member creation and discovery creation independently reject tombstones even with privileged counterpart fixture', async () => {
    await removeMember(dbFor('owner'), groupId, 'owner', 'reader');
    await environment.withSecurityRulesDisabled(async context => {
        await setDoc(index(context.firestore()), { groupId, joinedAt: serverTimestamp() });
    });
    await assertFails(setDoc(member(dbFor('owner')), { userId: 'reader', role: 'member', joinedAt: serverTimestamp() }));
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        await deleteDoc(index(db));
        await setDoc(member(db), { userId: 'reader', role: 'member', joinedAt: serverTimestamp() });
    });
    await assertFails(setDoc(index(dbFor('owner')), { groupId, joinedAt: serverTimestamp() }));
});

test('tombstones are immutable and cannot be deleted to bypass the rejoin block', async () => {
    await leaveGroup(dbFor('reader'), groupId, 'reader');
    const original = (await state())[3];
    for (const db of [dbFor('reader'), dbFor('owner'), dbFor('lead'), dbFor('outsider'), anonymous()]) {
        await assertFails(updateDoc(marker(db), { reason: 'removed' }));
        await assertFails(setDoc(marker(db), markerData('owner')));
        await assertFails(deleteDoc(marker(db)));
    }
    assert.deepEqual((await state())[3], original);
});

test('departure audit confidentiality: owner gets own after leaving, only admin gets others and bounded lists', async () => {
    await leaveGroup(dbFor('reader'), groupId, 'reader');
    await assertSucceeds(getDocFromServer(marker(dbFor('reader'))));
    await assertSucceeds(getDocFromServer(marker(dbFor('owner'))));
    for (const db of [dbFor('lead'), dbFor('other'), dbFor('outsider'),
    dbFor('outsider', { role: 'admin', admin: true }), anonymous()]) {
        await assertFails(getDocFromServer(marker(db)));
    }
    await assertFails(getDocFromServer(marker(dbFor('reader'), 'other')));
    const departures = db => collection(db, 'groups', groupId, 'departures');
    await assertSucceeds(getDocsFromServer(query(departures(dbFor('owner')), limit(50))));
    await assertFails(getDocsFromServer(departures(dbFor('owner'))));
    await assertFails(getDocsFromServer(query(departures(dbFor('owner')), limit(51))));
    for (const uid of ['reader', 'lead', 'other', 'outsider']) {
        await assertFails(getDocsFromServer(query(departures(dbFor(uid)), limit(50))));
    }
    await assertFails(getDocsFromServer(query(collectionGroup(dbFor('owner'), 'departures'), limit(50))));
});

test('repeated helper/raw departures and stale-marker replay fail without partial writes', async () => {
    await removeMember(dbFor('owner'), groupId, 'owner', 'reader');
    const original = (await state())[3];
    await assert.rejects(removeMember(dbFor('owner'), groupId, 'owner', 'reader'), /current members/);
    await assert.rejects(leaveGroup(dbFor('reader'), groupId, 'reader'));
    await denied(rawBatch(dbFor('owner')));
    // Privileged inconsistent fixtures must not turn an old marker into fresh
    // delete authority; normal client membership recreation is already denied.
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        await setDoc(member(db), { userId: 'reader', role: 'member', joinedAt: serverTimestamp() });
        await setDoc(index(db), { groupId, joinedAt: serverTimestamp() });
    });
    await denied(rawBatch(dbFor('owner'), 'owner', 'reader', { mark: false }));
    assert.deepEqual((await state())[3], original);
});

test('concurrent admin removal and self-leave have exactly one winner and no partial state', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Concurrent');
    const results = await Promise.allSettled([
        leaveGroup(dbFor('reader'), groupId, 'reader'),
        removeMember(dbFor('owner'), groupId, 'owner', 'reader'),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.filter(result => result.status === 'rejected').length, 1);
    const left = results[0].status === 'fulfilled';
    await departed('reader', left ? 'reader' : 'owner', left ? 'left' : 'removed');
    assert.deepEqual(await listMyGroups(dbFor('reader'), 'reader'), []);
});

test('concurrent raw coordinated removals have one winner and one canonical immutable marker', async () => {
    await setMemberDisplay(dbFor('reader'), groupId, 'reader', 'Concurrent');
    const results = await Promise.allSettled([
        rawBatch(dbFor('owner')).commit(), rawBatch(dbFor('lead'), 'lead').commit(),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.find(result => result.status === 'rejected').reason.code, 'permission-denied');
    await departed('reader', results[0].status === 'fulfilled' ? 'owner' : 'lead', 'removed');
});

test('retained completed assignments, messages and highlights are byte-for-byte unchanged and readable by remaining members', async () => {
    const db = dbFor('reader');
    await createAssignment(dbFor('owner'), 'owner', { groupId, userId: 'reader', chapterNumber: 17 });
    await updateReadingProgress(db, groupId, 'reader', 1, 17, 'completed');
    const messageId = await sendMessage(db, groupId, 'reader', 'Historical reading');
    const highlightId = await createHighlight(db, groupId, 'reader', {
        chapterNumber: 17, quote: 'Historical verse', text: 'Historical reflection',
    });
    const assignment = assignmentReference(db, groupId, 'reader', 1, 17);
    const references = [assignment, doc(db, 'groups', groupId, 'messages', messageId),
        doc(db, 'groups', groupId, 'highlights', highlightId)];
    const before = await Promise.all(references.map(async ref => (await getDocFromServer(ref)).data()));
    await setMemberDisplay(db, groupId, 'reader', 'Shared alias');
    await removeMember(dbFor('owner'), groupId, 'owner', 'reader');
    await environment.withSecurityRulesDisabled(async context => {
        const after = await Promise.all(references.map(async ref =>
            (await getDocFromServer(doc(context.firestore(), ref.path))).data()));
        assert.deepEqual(after, before);
    });
    assert.equal((await listAssignments(dbFor('other'), groupId, 'reader', 1))[0].status, 'completed');
    assert.equal((await getMessage(dbFor('other'), groupId, messageId)).text, before[1].text);
    assert.equal((await getHighlight(dbFor('other'), groupId, highlightId)).quote, before[2].quote);
    for (const ref of references) await assertFails(getDocFromServer(ref));
    await assertFails(listAssignments(db, groupId, 'reader', 1));
    await assertFails(listMessages(db, groupId));
    await assertFails(listHighlights(db, groupId));
    await assertFails(updateReadingProgress(db, groupId, 'reader', 1, 17, 'not_started'));
    await assertFails(sendMessage(db, groupId, 'reader', 'After departure'));
    await assertFails(createHighlight(db, groupId, 'reader', { chapterNumber: 1, quote: 'No', text: 'No' }));
    await assertFails(createAssignment(dbFor('owner'), 'owner', { groupId, userId: 'reader', chapterNumber: 1 }));
    await assertFails(setMemberDisplay(db, groupId, 'reader', 'After departure'));
});

test('departure cannot be combined with client historical cascade deletion', async () => {
    await createAssignment(dbFor('owner'), 'owner', { groupId, userId: 'reader', chapterNumber: 1 });
    const db = dbFor('owner');
    const batch = rawBatch(db);
    batch.delete(assignmentReference(db, groupId, 'reader', 1, 1));
    await denied(batch);
    assert.equal((await listAssignments(db, groupId, 'reader', 1)).length, 1);
});

test('prewrite authority rejects same-batch self-promotion; conflicting target demotion/delete cannot bypass rules', async () => {
    const db = dbFor('other');
    const promotion = rawBatch(db, 'other');
    promotion.update(member(db, 'other'), { role: 'group_lead' });
    await denied(promotion);
    await setMemberRole(dbFor('owner'), groupId, 'reader', 'group_lead');
    const leadDb = dbFor('lead');
    const demotion = rawBatch(leadDb, 'lead');
    demotion.update(member(leadDb), { role: 'member' });
    const beforeDemotion = await state();
    // The SDK/backend rejects duplicate delete-then-update operations before
    // rules evaluation. Do not misreport this as a rules authorization denial.
    await assert.rejects(demotion.commit(), { code: 'invalid-argument' });
    assert.deepEqual(await state(), beforeDemotion);
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(member(context.firestore(), 'other'), { role: 'admin' });
    });
    const self = rawBatch(db, 'other', 'other');
    self.update(member(db, 'other'), { role: 'member' });
    const beforeSelf = await state('other');
    await assert.rejects(self.commit(), { code: 'invalid-argument' });
    assert.deepEqual(await state('other'), beforeSelf);
});

test('prewrite admin authority, not a same-batch replacement role, governs authorized removal', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(member(context.firestore(), 'other'), { role: 'admin' });
    });
    const db = dbFor('other');
    const batch = rawBatch(db, 'other');
    batch.update(member(db, 'other'), { role: 'member' });
    await assertSucceeds(batch.commit());
    await departed('reader', 'other', 'removed');
    await denied(rawBatch(db, 'other', 'lead'), 'lead');
});

test('revoked actor cannot remove anyone on the next request, even with forged admin claims', async () => {
    await removeMember(dbFor('owner'), groupId, 'owner', 'lead');
    const db = dbFor('lead', { role: 'admin', admin: true });
    await denied(rawBatch(db, 'lead'));
    await assert.rejects(removeMember(db, groupId, 'lead', 'reader'));
});

test('helpers validate all path segments before IO and cannot bootstrap missing groups or targets', async () => {
    for (const value of ['', 'x/y', '.', '..', '__reserved__', 'é'.repeat(751), null, 1]) {
        await assert.rejects(leaveGroup(null, value, 'reader'), /path segments/);
        await assert.rejects(leaveGroup(null, 'group', value), /path segments/);
        await assert.rejects(removeMember(null, value, 'owner', 'reader'), /path segments/);
        await assert.rejects(removeMember(null, 'group', value, 'reader'), /path segments/);
        await assert.rejects(removeMember(null, 'group', 'owner', value), /path segments/);
    }
    await assert.rejects(removeMember(dbFor('owner'), 'missing', 'owner', 'reader'));
    await assert.rejects(removeMember(dbFor('owner'), groupId, 'owner', 'outsider'), /current members/);
});