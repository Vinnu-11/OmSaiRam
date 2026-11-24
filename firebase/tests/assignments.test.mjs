import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
    writeBatch, serverTimestamp, Timestamp, query, limit,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole } from '../src/groups.mjs';
import { createInvitation } from '../src/invitations.mjs';
import { canonicalUnit, CHAPTER_UNITS } from '../src/chapter-units.mjs';
import {
    assignmentReference, createAssignment, getAssignment, listAssignments, updateReadingProgress,
} from '../src/assignments.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const anonymous = () => environment.unauthenticatedContext().firestore();
const options = (overrides = {}) => ({ groupId, userId: 'reader', weekNumber: 1, chapterNumber: 16, ...overrides });
const create = (db = dbFor('owner'), uid = 'owner', overrides = {}) => createAssignment(db, uid, options(overrides));
const ref = (db = dbFor('owner'), userId = 'reader', week = '1', unit = '16-17', group = groupId) =>
    doc(db, 'groups', group, 'readingWeeks', week, 'members', userId, 'assignments', unit);
const data = (overrides = {}) => ({
    groupId, userId: 'reader', weekNumber: 1, ...canonicalUnit(16), scheduledDate: null,
    createdBy: 'owner', createdAt: serverTimestamp(),
    status: 'not_started', progressUpdatedAt: serverTimestamp(), ...overrides,
});

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
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Manual Assignments' });
    for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('catalogue has exactly 48 immutable canonical units and all 53 chapters map correctly', () => {
    assert.equal(CHAPTER_UNITS.length, 48);
    assert.equal(new Set(CHAPTER_UNITS.map(unit => unit.unitKey)).size, 48);
    assert.ok(Object.isFrozen(CHAPTER_UNITS));
    for (let chapter = 1; chapter <= 53; chapter++) {
        const unit = canonicalUnit(chapter);
        assert.ok(CHAPTER_UNITS.some(entry => entry.unitKey === unit.unitKey));
        assert.ok(unit.chapterStart <= chapter && unit.chapterEnd >= chapter);
        assert.ok(Object.isFrozen(unit));
    }
    for (const [first, last] of [[16, 17], [18, 19], [43, 44], [51, 53]]) {
        assert.deepEqual(canonicalUnit(first), { unitKey: `${first}-${last}`, chapterStart: first, chapterEnd: last });
        for (let chapter = first; chapter <= last; chapter++) assert.deepEqual(canonicalUnit(chapter), canonicalUnit(first));
    }
    assert.equal(canonicalUnit(50).unitKey, '50');
});

test('admin manually creates a canonical assignment with embedded initial progress and server times', async () => {
    assert.equal(await assertSucceeds(create()), '16-17');
    const assignment = await getAssignment(dbFor('reader'), groupId, 'reader', 1, 17);
    assert.equal(assignment.userId, 'reader');
    assert.equal(assignment.createdBy, 'owner');
    assert.equal(assignment.chapterStart, 16);
    assert.equal(assignment.chapterEnd, 17);
    assert.equal(assignment.status, 'not_started');
    assert.equal(assignment.scheduledDate, null);
    assert.ok(assignment.createdAt instanceof Timestamp);
    assert.ok(assignment.progressUpdatedAt.isEqual(assignment.createdAt));
    assert.equal((await getDoc(doc(dbFor('owner'), 'groups', groupId))).data().currentWeek, 1);
});

test('lead may assign current members, including themselves; admins may self-assign', async () => {
    await assertSucceeds(create(dbFor('lead'), 'lead'));
    await assertSucceeds(create(dbFor('lead'), 'lead', { userId: 'lead' }));
    await assertSucceeds(create(dbFor('owner'), 'owner', { userId: 'owner' }));
});

test('all 48 canonical units pass rules in a single same-member batch within access-call budget', async () => {
    const db = dbFor('owner');
    const batch = writeBatch(db);
    for (const unit of CHAPTER_UNITS) batch.set(ref(db, 'reader', '1', unit.unitKey), data(unit));
    await assertSucceeds(batch.commit());
    const assignments = await listAssignments(dbFor('other'), groupId, 'reader', 1);
    assert.equal(assignments.length, 48);
    assert.deepEqual(new Set(assignments.map(item => item.unitKey)), new Set(CHAPTER_UNITS.map(unit => unit.unitKey)));
    assert.deepEqual(await listAssignments(db, groupId, 'reader', 1, assignments.at(-1).id), []);
});

test('same unit is independently assignable to another member, week or group; week 10000 is valid', async () => {
    await create();
    await assertSucceeds(create(dbFor('owner'), 'owner', { userId: 'other' }));
    await assertSucceeds(create(dbFor('owner'), 'owner', { weekNumber: 10000 }));
    const otherGroup = await createGroup(dbFor('owner'), 'owner', { name: 'Another Group' });
    await addMember(dbFor('owner'), otherGroup, 'reader');
    await assertSucceeds(create(dbFor('owner'), 'owner', { groupId: otherGroup }));
});

test('scheduled date is explicit Date instant or null, not a generated Monday or client clock timestamp', async () => {
    const date = new Date('2026-10-15T18:30:00.000Z');
    await create(dbFor('owner'), 'owner', { scheduledDate: date });
    assert.equal((await getDoc(ref())).data().scheduledDate.toMillis(), date.getTime());
    await assertSucceeds(setDoc(ref(dbFor('owner'), 'reader', '2'), data({ weekNumber: 2, scheduledDate: Timestamp.fromMillis(0) })));
    for (const scheduledDate of ['2026-10-13', 0, {}, false]) {
        await assertFails(setDoc(ref(dbFor('owner'), 'reader', '3'), data({ weekNumber: 3, scheduledDate })));
    }
    for (const scheduledDate of [new Date('invalid'), '2026-10-13', Timestamp.now(), 0]) {
        await assert.rejects(create(dbFor('owner'), 'owner', { scheduledDate }), /Scheduled date/);
    }
});

test('client input validation rejects invalid week/chapter numbers and path injection', async () => {
    for (const weekNumber of [0, -1, 10001, 1.5, '1', NaN, Infinity, null, true]) {
        await assert.rejects(create(dbFor('owner'), 'owner', { weekNumber }), /Week number/);
    }
    for (const chapterNumber of [0, -1, 54, 16.5, '16', NaN, Infinity, null, true]) {
        assert.throws(() => canonicalUnit(chapterNumber), /Chapter number/);
    }
    for (const value of ['', 'reader/extra', '.', '..', '__reserved__', 'x'.repeat(1501)]) {
        await assert.rejects(create(dbFor('owner'), 'owner', { userId: value }), /path segment/);
        await assert.rejects(create(dbFor('owner'), 'owner', { groupId: value }), /path segment/);
    }
    await assert.rejects(create(dbFor('owner'), ''), /path segment/);
});

test('server rejects invalid numeric weeks and noncanonical week keys even bypassing helpers', async () => {
    for (const weekNumber of [0, -1, 10001, 1.5, '1', NaN, Infinity, null, true]) {
        await assertFails(setDoc(ref(), data({ weekNumber })));
    }
    for (const week of ['01', '+1', '1.0', '1e0', '10001', 'arbitrary-token']) {
        await assertFails(setDoc(ref(dbFor('owner'), 'reader', week), data()));
    }
    await assertFails(setDoc(ref(), data({ weekNumber: 2 })));
});

test('server rejects invalid numeric ranges and every inner chapter as a separate unit', async () => {
    for (const chapterStart of [0, -1, 54, 16.5, '16', NaN, Infinity, null, true, 17, 19, 44, 52, 53]) {
        await assertFails(setDoc(ref(), data({ chapterStart })));
    }
    for (const chapterEnd of [16, 18, 54, 17.5, '17', NaN, Infinity, null, true]) {
        await assertFails(setDoc(ref(), data({ chapterEnd })));
    }
    for (const chapter of [17, 19, 44, 52, 53]) {
        const unitKey = String(chapter);
        await assertFails(setDoc(ref(dbFor('owner'), 'reader', '1', unitKey), data({
            unitKey, chapterStart: chapter, chapterEnd: chapter,
        })));
    }
    for (const [chapterStart, chapterEnd, unitKey] of [[1, 2, '1-2'], [16, 16, '16'], [51, 52, '51-52']]) {
        await assertFails(setDoc(ref(dbFor('owner'), 'reader', '1', unitKey), data({ chapterStart, chapterEnd, unitKey })));
    }
});

test('canonical unit cannot be duplicated through forged alternate document keys', async () => {
    await create();
    for (const unit of ['16', '17', '016-017', '16_17', '16-17-copy', 'random', '16–17']) {
        await assertFails(setDoc(ref(dbFor('owner'), 'reader', '1', unit), data()));
        await assertFails(setDoc(ref(dbFor('owner'), 'reader', '1', unit), data({ unitKey: unit })));
    }
    await assertFails(setDoc(ref(), data({ unitKey: '18-19' })));
    assert.equal((await listAssignments(dbFor('owner'), groupId, 'reader', 1)).length, 1);
});

test('nonmembers and unauthenticated clients cannot create, read or update assignments', async () => {
    await create();
    for (const db of [dbFor('outsider'), anonymous()]) {
        await assertFails(setDoc(ref(db, 'reader', '2'), data({ weekNumber: 2 })));
        await assertFails(getDoc(ref(db)));
        await assertFails(listAssignments(db, groupId, 'reader', 1));
        await assertFails(updateReadingProgress(db, groupId, 'reader', 1, 16, 'completed'));
    }
});

test('ordinary member cannot assign to themselves or another member', async () => {
    for (const userId of ['reader', 'other']) {
        await assertFails(create(dbFor('reader'), 'reader', { userId }));
        await assertFails(setDoc(ref(dbFor('reader'), userId), data({ userId, createdBy: 'reader' })));
    }
});

test('UID fields and path scope cannot be spoofed, including creator UID and auth claims', async () => {
    for (const override of [{ userId: 'other' }, { groupId: 'other' }, { createdBy: 'reader' }]) {
        await assertFails(setDoc(ref(), data(override)));
    }
    await assertFails(create(dbFor('lead'), 'owner'));
    await assertFails(create(dbFor('reader', { admin: true, role: 'admin', groupId }), 'reader'));
    await assertFails(create(dbFor('outsider', { admin: true, role: 'group_lead' }), 'outsider'));
    await create();
    await assertFails(updateReadingProgress(dbFor('other', { userId: 'reader', admin: true }), groupId, 'reader', 1, 16, 'completed'));
});

test('assignment requires an existing group and current target membership, not just a profile or invite', async () => {
    for (const userId of ['outsider', 'missing-user']) {
        await assertFails(setDoc(ref(dbFor('owner'), userId), data({ userId })));
    }
    await assertFails(setDoc(ref(dbFor('owner'), 'reader', '1', '16-17', 'missing-group'), data({ groupId: 'missing-group' })));
    const token = await createInvitation(dbFor('owner'), groupId, 'owner');
    await assertFails(setDoc(ref(dbFor('owner'), 'outsider'), data({ userId: 'outsider', inviteToken: token })));
});

test('reads are group-member scoped and lists must be bounded; global and parent enumeration denied', async () => {
    await create();
    for (const uid of ['owner', 'lead', 'reader', 'other']) {
        await assertSucceeds(getDoc(ref(dbFor(uid))));
        assert.equal((await listAssignments(dbFor(uid), groupId, 'reader', 1)).length, 1);
    }
    const db = dbFor('owner');
    const assignments = collection(db, 'groups', groupId, 'readingWeeks', '1', 'members', 'reader', 'assignments');
    await assertFails(getDocs(assignments));
    await assertFails(getDocs(query(assignments, limit(49))));
    await assertSucceeds(getDocs(query(assignments, limit(1))));
    await assertFails(getDocs(query(collectionGroup(db, 'assignments'), limit(48))));
    await assertFails(getDocs(query(collection(db, 'groups', groupId, 'readingWeeks'), limit(48))));
    await assertFails(getDocs(query(collection(db, 'groups', groupId, 'readingWeeks', '1', 'members'), limit(48))));
    await assertFails(setDoc(doc(db, 'groups', groupId, 'readingWeeks', '1'), { weekNumber: 1 }));
    assert.equal(await getAssignment(db, groupId, 'reader', 1, 1), null);
});

test('only assignee updates progress; all three statuses and backwards transitions are supported', async () => {
    await create();
    const before = (await getDoc(ref())).data();
    for (const status of ['in_progress', 'completed', 'not_started']) {
        await assertSucceeds(updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 17, status));
        const after = (await getDoc(ref())).data();
        assert.equal(after.status, status);
        assert.ok(after.progressUpdatedAt.toMillis() >= before.progressUpdatedAt.toMillis());
        const { status: previousStatus, progressUpdatedAt: previousTime, ...immutableBefore } = before;
        const { status: nextStatus, progressUpdatedAt: nextTime, ...immutableAfter } = after;
        assert.deepEqual(immutableAfter, immutableBefore);
    }
    for (const uid of ['owner', 'lead', 'other']) {
        await assertFails(updateReadingProgress(dbFor(uid), groupId, 'reader', 1, 16, 'completed'));
    }
});

test('progress updates cannot create missing assignments or independent relational progress documents', async () => {
    await assertFails(updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 16, 'completed'));
    await create();
    const db = dbFor('reader');
    for (const path of [
        'progress/forged', 'assignments/forged', `groups/${groupId}/progress/forged`,
        `${ref(db).path}/progress/forged`,
    ]) {
        await assertFails(setDoc(doc(db, path), { status: 'completed' }));
        await assertFails(getDoc(doc(db, path)));
    }
});

test('progress enum and server timestamp are enforced independently of client helper', async () => {
    await create();
    const reference = ref(dbFor('reader'));
    for (const status of ['done', '', 1, null, true]) {
        await assertFails(updateDoc(reference, { status, progressUpdatedAt: serverTimestamp() }));
        await assert.rejects(updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 16, status), /Invalid reading status/);
    }
    await assertFails(updateDoc(reference, { status: 'completed', progressUpdatedAt: Timestamp.fromMillis(0) }));
    await assertFails(updateDoc(reference, { status: 'completed' }));
});

test('every assignment field is immutable even to the assignee and privileged creator', async () => {
    await create();
    for (const uid of ['reader', 'owner', 'lead']) {
        for (const changes of [
            { groupId: 'other' }, { userId: 'other' }, { weekNumber: 2 }, { unitKey: '18-19' },
            { chapterStart: 18, chapterEnd: 19 }, { scheduledDate: Timestamp.now() },
            { createdBy: 'reader' }, { createdAt: Timestamp.fromMillis(0) },
            { role: 'admin' }, { isAdmin: true }, { completedBy: 'reader' },
        ]) await assertFails(updateDoc(ref(dbFor(uid)), { ...changes, progressUpdatedAt: serverTimestamp() }));
    }
});

test('creation rejects extra/missing fields, initial progress forgery and client timestamps', async () => {
    for (const override of [
        { status: 'completed' }, { status: 'in_progress' }, { createdAt: Timestamp.fromMillis(0) },
        { progressUpdatedAt: Timestamp.fromMillis(0) }, { role: 'admin' }, { language: 'mr' },
        { chapterId: 123 }, { token: 'forged' },
    ]) await assertFails(setDoc(ref(), data(override)));
    for (const key of Object.keys(data())) {
        const incomplete = data();
        delete incomplete[key];
        await assertFails(setDoc(ref(), incomplete));
    }
});

test('assignment deletion and reassignment are denied to every actor', async () => {
    await create();
    for (const db of [dbFor('owner'), dbFor('lead'), dbFor('reader'), dbFor('outsider'), anonymous()]) {
        await assertFails(deleteDoc(ref(db)));
    }
    const db = dbFor('owner');
    const batch = writeBatch(db);
    batch.delete(ref(db));
    batch.set(ref(db, 'other'), data({ userId: 'other' }));
    await assertFails(batch.commit());
    assert.equal((await getDoc(ref())).data().userId, 'reader');
    assert.equal((await getDoc(ref(db, 'other'))).exists(), false);
});

test('duplicate chapter aliases and raw overwrites cannot reset existing assignments or progress', async () => {
    await create();
    await updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 16, 'completed');
    await assert.rejects(create(dbFor('owner'), 'owner', { chapterNumber: 17 }), /already exists/);
    await assertFails(setDoc(ref(), data()));
    assert.equal((await getDoc(ref())).data().status, 'completed');
    await create(dbFor('owner'), 'owner', { userId: 'owner', chapterNumber: 53 });
    await assert.rejects(create(dbFor('owner'), 'owner', { userId: 'owner', chapterNumber: 52 }), /already exists/);
    await assertFails(setDoc(ref(dbFor('owner'), 'owner', '1', '51-53'), data({ userId: 'owner', ...canonicalUnit(51) })));
});

test('concurrent admin/lead creates of chapter aliases produce exactly one canonical assignment', async () => {
    const results = await Promise.allSettled([
        create(dbFor('owner'), 'owner', { chapterNumber: 51 }),
        create(dbFor('lead'), 'lead', { chapterNumber: 52 }),
        create(dbFor('owner'), 'owner', { chapterNumber: 53 }),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    assert.equal(results.filter(result => result.status === 'rejected').length, 2);
    for (const result of results.filter(result => result.status === 'rejected')) {
        assert.match(result.reason.message, /already exists/);
    }
    const assignments = await listAssignments(dbFor('owner'), groupId, 'reader', 1);
    assert.equal(assignments.length, 1);
    assert.equal(assignments[0].id, '51-53');
});

test('concurrent raw SDK creates cannot bypass rule-enforced uniqueness', async () => {
    const results = await Promise.allSettled([
        setDoc(ref(dbFor('owner')), data()),
        setDoc(ref(dbFor('lead')), data({ createdBy: 'lead' })),
    ]);
    assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
    const rejected = results.find(result => result.status === 'rejected');
    assert.equal(rejected.reason.code, 'permission-denied');
    assert.equal((await listAssignments(dbFor('owner'), groupId, 'reader', 1)).length, 1);
});

test('concurrent valid progress writes retain one document and privilege tampering never succeeds', async () => {
    await create();
    const results = await Promise.allSettled([
        updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 16, 'in_progress'),
        updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 17, 'completed'),
        updateDoc(ref(dbFor('reader')), { userId: 'other', status: 'completed', progressUpdatedAt: serverTimestamp() }),
        updateReadingProgress(dbFor('owner'), groupId, 'reader', 1, 16, 'completed'),
    ]);
    assert.deepEqual(results.map(result => result.status), ['fulfilled', 'fulfilled', 'rejected', 'rejected']);
    const assignments = await listAssignments(dbFor('other'), groupId, 'reader', 1);
    assert.equal(assignments.length, 1);
    assert.equal(assignments[0].userId, 'reader');
    assert.ok(['in_progress', 'completed'].includes(assignments[0].status));
});

test('atomic self-promotion or joining cannot bootstrap assignment privileges or target membership', async () => {
    const readerDb = dbFor('reader');
    const promote = writeBatch(readerDb);
    promote.update(doc(readerDb, 'groups', groupId, 'members', 'reader'), { role: 'group_lead' });
    promote.set(ref(readerDb), data({ createdBy: 'reader' }));
    await assertFails(promote.commit());
    // Even a legitimate admin promotion does not grant pre-write assignment authority.
    const ownerDb = dbFor('owner');
    const promotion = writeBatch(ownerDb);
    promotion.update(doc(ownerDb, 'groups', groupId, 'members', 'reader'), { role: 'group_lead' });
    promotion.set(ref(ownerDb), data({ createdBy: 'reader' }));
    await assertFails(promotion.commit());
    const joinAndAssign = writeBatch(ownerDb);
    joinAndAssign.set(doc(ownerDb, 'groups', groupId, 'members', 'outsider'), {
        userId: 'outsider', role: 'member', joinedAt: serverTimestamp(),
    });
    joinAndAssign.set(doc(ownerDb, 'users', 'outsider', 'groups', groupId), { groupId, joinedAt: serverTimestamp() });
    joinAndAssign.set(ref(ownerDb, 'outsider'), data({ userId: 'outsider' }));
    await assertFails(joinAndAssign.commit());
    assert.equal((await getDoc(doc(ownerDb, 'groups', groupId, 'members', 'outsider'))).exists(), false);
});

test('revoked lead authority and removed membership/group are checked at the next request', async () => {
    await create();
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'member');
    await assertFails(setDoc(ref(dbFor('lead'), 'reader', '2'), data({ weekNumber: 2, createdBy: 'lead' })));
    // Privileged fixtures simulate future coordinated cleanup; no client delete escape.
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId, 'members', 'reader'));
    });
    await assertFails(updateReadingProgress(dbFor('reader'), groupId, 'reader', 1, 16, 'completed'));
    await assertFails(getDoc(ref(dbFor('reader'))));
    await assertFails(setDoc(ref(dbFor('owner'), 'reader', '2'), data({ weekNumber: 2 })));
    await environment.withSecurityRulesDisabled(async context => {
        await deleteDoc(doc(context.firestore(), 'groups', groupId));
    });
    await assertFails(getDoc(ref()));
    await assertFails(listAssignments(dbFor('owner'), groupId, 'reader', 1));
    await assertFails(setDoc(ref(dbFor('owner'), 'other'), data({ userId: 'other' })));
});

test('UIDs containing separators used by flat keys remain distinct in nested path contract', async () => {
    const uid = 'reader_1_16-17';
    await setDoc(doc(dbFor(uid), 'users', uid), {
        displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    await addMember(dbFor('owner'), groupId, uid);
    await create(dbFor('owner'), 'owner', { userId: uid, chapterNumber: 17 });
    assert.equal(assignmentReference(dbFor(uid), groupId, uid, 1, 17).path,
        `groups/${groupId}/readingWeeks/1/members/${uid}/assignments/16-17`);
    await assertSucceeds(updateReadingProgress(dbFor(uid), groupId, uid, 1, 17, 'completed'));
    await assertFails(updateReadingProgress(dbFor('reader'), groupId, uid, 1, 17, 'completed'));
});