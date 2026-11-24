import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, getDocFromServer, getDocsFromServer,
    setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp,
    query, limit, disableNetwork, enableNetwork,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember } from '../src/groups.mjs';
import { createAssignment, assignmentReference, updateReadingProgress } from '../src/assignments.mjs';
import { CHAPTER_UNITS } from '../src/chapter-units.mjs';
import { removeMember, leaveGroup } from '../src/membership-lifecycle.mjs';
import { DISCOVERY_LIMITS, discoverMyAssignments } from '../src/assignment-discovery.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const discover = (options) => discoverMyAssignments(dbFor('reader'), 'reader', options);
const assign = (overrides = {}) => createAssignment(dbFor('owner'), 'owner', {
    groupId, userId: 'reader', weekNumber: 1, chapterNumber: 16, ...overrides,
});
const emptySummary = { total: 0, notStarted: 0, inProgress: 0, completed: 0 };
const permissionDenied = error => error.code === 'permission-denied';

// Privileged fixtures model scale/corruption that normal clients cannot create.
// These bypasses exist only inside the emulator tests, never the discovery API.
async function fixtureGroup(db, id, currentWeek = 1, uid = 'reader') {
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', id), {
        name: `Fixture ${id}`, description: '', mode: 'chapter_wise', createdBy: 'owner',
        chaptersPerWeek: 2, startChapter: 1, currentWeek,
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'groups', id, 'members', uid), {
        userId: uid, role: 'member', joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'users', uid, 'groups', id), { groupId: id, joinedAt: serverTimestamp() });
    await batch.commit();
}

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
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Discovery' });
    for (const uid of ['reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
});
after(async () => { await environment?.cleanup(); });

test('discovery limits are the frozen public contract', () => {
    assert.deepEqual(DISCOVERY_LIMITS, { groups: 10, weeks: 3 });
    assert.ok(Object.isFrozen(DISCOVERY_LIMITS));
    assert.throws(() => { DISCOVERY_LIMITS.groups = 50; }, TypeError);
});

test('multiple groups discover only own assignments, not other assignees or unindexed groups', async () => {
    const second = await createGroup(dbFor('owner'), 'owner', { name: 'Second' });
    await addMember(dbFor('owner'), second, 'reader');
    const hidden = await createGroup(dbFor('owner'), 'owner', { name: 'Owner only' });
    await assign();
    await assign({ userId: 'other', chapterNumber: 18 });
    await assign({ groupId: second, chapterNumber: 43 });
    await assign({ groupId: hidden, userId: 'owner' });
    const result = await discover();
    assert.deepEqual(result.groups.map(group => group.groupId), [groupId, second].sort());
    assert.equal(result.nextAfterGroupId, null);
    for (const group of result.groups) {
        assert.equal(group.currentWeek, 1);
        assert.equal(group.weeks.length, 1);
        assert.equal(group.weeks[0].assignments.length, 1);
        assert.equal(group.weeks[0].assignments[0].userId, 'reader');
        assert.ok(group.weeks[0].assignments[0].createdAt instanceof Timestamp);
        assert.deepEqual(group.weeks[0].summary, { total: 1, notStarted: 1, inProgress: 0, completed: 0 });
    }
    assert.equal(result.groups.find(group => group.groupId === second).name, 'Second');
});

test('default starts at each group currentWeek; future windows and explicit history are per week', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(doc(context.firestore(), 'groups', groupId), { currentWeek: 4 });
        await fixtureGroup(context.firestore(), 'different-week', 7);
    });
    for (const weekNumber of [1, 4, 5, 6]) await assign({ weekNumber });
    const current = await discover();
    assert.deepEqual(current.groups.find(group => group.groupId === groupId).weeks.map(week => week.weekNumber), [4]);
    assert.deepEqual(current.groups.find(group => group.groupId === 'different-week').weeks.map(week => week.weekNumber), [7]);
    const future = await discover({ weeksAhead: 3 });
    assert.deepEqual(future.groups.find(group => group.groupId === groupId).weeks.map(week => week.weekNumber), [4, 5, 6]);
    assert.deepEqual(future.groups.find(group => group.groupId === 'different-week').weeks.map(week => week.weekNumber), [7, 8, 9]);
    const history = await discover({ weekNumber: 1, weeksAhead: 2 });
    for (const group of history.groups) assert.deepEqual(group.weeks.map(week => week.weekNumber), [1, 2]);
    const historical = history.groups.find(group => group.groupId === groupId);
    assert.equal(historical.currentWeek, 4);
    assert.equal(historical.weeks[0].summary.total, 1);
    assert.deepEqual(historical.weeks[1].summary, emptySummary);
});

test('combined units count once, retain chapter ranges and follow document-ID order', async () => {
    for (const chapterNumber of [53, 44, 19, 17, 2, 10]) await assign({ chapterNumber });
    const week = (await discover()).groups[0].weeks[0];
    assert.deepEqual(week.assignments.map(item => item.id), ['10', '16-17', '18-19', '2', '43-44', '51-53']);
    assert.deepEqual(week.assignments.filter(item => item.id.includes('-')).map(item => [item.chapterStart, item.chapterEnd]),
        [[16, 17], [18, 19], [43, 44], [51, 53]]);
    assert.deepEqual(week.summary, { total: 6, notStarted: 6, inProgress: 0, completed: 0 });
});

test('status counters refresh from server and exclude other weeks and members', async () => {
    for (const chapterNumber of [1, 16, 51]) await assign({ chapterNumber });
    await assign({ weekNumber: 2 });
    await assign({ userId: 'other' });
    const db = dbFor('reader');
    await updateReadingProgress(db, groupId, 'reader', 1, 16, 'in_progress');
    await updateReadingProgress(db, groupId, 'reader', 1, 53, 'completed');
    const first = await discoverMyAssignments(db, 'reader');
    assert.deepEqual(first.groups[0].weeks[0].summary, { total: 3, notStarted: 1, inProgress: 1, completed: 1 });
    await updateReadingProgress(db, groupId, 'reader', 1, 17, 'completed');
    const refreshed = await discoverMyAssignments(db, 'reader');
    assert.deepEqual(refreshed.groups[0].weeks[0].summary, { total: 3, notStarted: 1, inProgress: 0, completed: 2 });
    assert.equal(first.groups[0].weeks[0].summary.inProgress, 1);
});

test('empty groups stay in results and full final pages conservatively continue by index ID', async () => {
    const first = await discover({ pageSize: 1 });
    assert.equal(first.groups[0].groupId, groupId);
    assert.deepEqual(first.groups[0].weeks[0], { weekNumber: 1, assignments: [], summary: emptySummary });
    assert.equal(first.nextAfterGroupId, groupId);
    assert.deepEqual(await discover({ pageSize: 1, afterGroupId: first.nextAfterGroupId }), { groups: [], nextAfterGroupId: null });
});

test('pagination across more than ten indexed groups has no duplicates or omissions', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        for (let i = 0; i < 12; i++) await fixtureGroup(context.firestore(), `page-${String(i).padStart(2, '0')}`);
    });
    const first = await discover({ pageSize: 10 });
    const second = await discover({ pageSize: 10, afterGroupId: first.nextAfterGroupId });
    assert.equal(first.groups.length, 10);
    assert.equal(first.nextAfterGroupId, first.groups.at(-1).groupId);
    assert.equal(second.groups.length, 3);
    assert.equal(second.nextAfterGroupId, null);
    const ids = [...first.groups, ...second.groups].map(group => group.groupId);
    assert.deepEqual(ids, [groupId, ...Array.from({ length: 12 }, (_, i) => `page-${String(i).padStart(2, '0')}`)].sort());
    assert.equal(new Set(ids).size, 13);
});

test('maximum window returns at most ten groups, three weeks and 48 units per week', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        await deleteDoc(doc(db, 'users', 'reader', 'groups', groupId));
        for (let i = 0; i < 10; i++) {
            const id = `maximum-${i}`;
            await fixtureGroup(db, id);
            const batch = writeBatch(db);
            for (const weekNumber of [1, 2, 3]) {
                for (const unit of CHAPTER_UNITS) {
                    batch.set(doc(db, 'groups', id, 'readingWeeks', String(weekNumber), 'members', 'reader', 'assignments', unit.unitKey), {
                        groupId: id, userId: 'reader', weekNumber, ...unit, scheduledDate: null,
                        createdBy: 'owner', createdAt: serverTimestamp(),
                        status: 'not_started', progressUpdatedAt: serverTimestamp(),
                    });
                }
            }
            await batch.commit();
        }
    });
    const result = await discover({ pageSize: 10, weeksAhead: 3 });
    assert.equal(result.groups.length, 10);
    let total = 0;
    for (const group of result.groups) {
        assert.equal(group.weeks.length, 3);
        for (const week of group.weeks) {
            assert.equal(week.assignments.length, 48);
            assert.equal(week.summary.total, 48);
            total += week.assignments.length;
        }
    }
    assert.equal(total, 10 * 3 * 48);
});

test('week 10000 boundary truncates both current and explicit windows instead of overflowing', async () => {
    await environment.withSecurityRulesDisabled(async context => {
        await updateDoc(doc(context.firestore(), 'groups', groupId), { currentWeek: 10000 });
    });
    await assign({ weekNumber: 10000 });
    assert.deepEqual((await discover({ weeksAhead: 3 })).groups[0].weeks.map(week => week.weekNumber), [10000]);
    const weeks = (await discover({ weekNumber: 9999, weeksAhead: 3 })).groups[0].weeks;
    assert.deepEqual(weeks.map(week => week.weekNumber), [9999, 10000]);
    assert.deepEqual(weeks[0].summary, emptySummary);
    assert.equal(weeks[1].summary.total, 1);
    assert.deepEqual((await discover({ weekNumber: 10000, weeksAhead: 3 })).groups[0].weeks.map(week => week.weekNumber), [10000]);
});

test('invalid numeric options are rejected before any database access', async () => {
    for (const [key, maximum, label] of [['pageSize', 10, 'Page size'], ['weeksAhead', 3, 'Weeks ahead'], ['weekNumber', 10000, 'Week number']]) {
        const values = [0, -1, maximum + 1, 1.5, '1', NaN, Infinity, true, Number.MAX_SAFE_INTEGER];
        if (key !== 'weekNumber') values.push(null);
        for (const value of values) await assert.rejects(discoverMyAssignments(null, 'reader', { [key]: value }), new RegExp(label));
    }
});

test('UID and cursor reject path injection, dot/reserved IDs and UTF-8 overflow before reads', async () => {
    const invalid = ['', 'reader/extra', '.', '..', '__reserved__', 'x'.repeat(1501), 'é'.repeat(751), '😀'.repeat(376), null, 123, {}, false];
    for (const value of invalid) {
        await assert.rejects(discoverMyAssignments(null, value), /UID.*path segment/);
        if (value !== null) await assert.rejects(discoverMyAssignments(null, 'reader', { afterGroupId: value }), /Cursor ID.*path segment/);
    }
});

test('single-segment Unicode and exact 1500 UTF-8 byte IDs remain valid', async () => {
    const uid = 'é'.repeat(750);
    const id = '界'.repeat(500);
    await environment.withSecurityRulesDisabled(context => fixtureGroup(context.firestore(), id, 1, uid));
    const result = await discoverMyAssignments(dbFor(uid), uid, { pageSize: 1 });
    assert.equal(result.groups[0].groupId, id);
    assert.equal(result.nextAfterGroupId, id);
    assert.deepEqual(await discoverMyAssignments(dbFor(uid), uid, { afterGroupId: id }), { groups: [], nextAfterGroupId: null });
});

test('anonymous, outsiders, admins and forged claims cannot discover someone else UID', async () => {
    await assign();
    for (const db of [environment.unauthenticatedContext().firestore(), dbFor('outsider'), dbFor('owner'),
    dbFor('other', { userId: 'reader', admin: true, role: 'admin' }),
    dbFor('outsider', { admin: true, role: 'group_lead' })]) {
        await assert.rejects(discoverMyAssignments(db, 'reader'), permissionDenied);
    }
    // An outsider's own empty owner index is legal, not a global group query.
    assert.deepEqual(await discoverMyAssignments(dbFor('outsider'), 'outsider'), { groups: [], nextAfterGroupId: null });
});

test('direct reads of other assignments remain member-readable but discovery needs the owned index', async () => {
    await assign();
    const db = dbFor('other');
    assert.equal((await getDocFromServer(assignmentReference(db, groupId, 'reader', 1, 16))).data().userId, 'reader');
    await assert.rejects(discoverMyAssignments(db, 'reader'), permissionDenied);
    assert.deepEqual((await discoverMyAssignments(db, 'other')).groups[0].weeks[0].summary, emptySummary);
});

test('new discovery after removal omits revoked group while historical assignment remains', async () => {
    await assign();
    const db = dbFor('reader');
    const before = await discoverMyAssignments(db, 'reader');
    await removeMember(dbFor('owner'), groupId, 'owner', 'reader');
    assert.deepEqual(await discoverMyAssignments(db, 'reader'), { groups: [], nextAfterGroupId: null });
    await assert.rejects(getDocFromServer(assignmentReference(db, groupId, 'reader', 1, 16)), permissionDenied);
    assert.equal((await getDocFromServer(assignmentReference(dbFor('other'), groupId, 'reader', 1, 16))).data().status, 'not_started');
    assert.equal(before.groups[0].weeks[0].assignments.length, 1); // No erasure of completed reads.
});

test('leaving also removes discovery on a fresh request without deleting history', async () => {
    await assign();
    await leaveGroup(dbFor('reader'), groupId, 'reader');
    assert.deepEqual(await discover(), { groups: [], nextAfterGroupId: null });
    assert.ok((await getDocFromServer(assignmentReference(dbFor('owner'), groupId, 'reader', 1, 16))).exists());
});

test('stale index fails the whole page on permission denial rather than skipping or returning partial data', async () => {
    await assign();
    const staleId = 'zzzz-stale';
    assert.ok(groupId < staleId);
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        await fixtureGroup(db, staleId);
        await deleteDoc(doc(db, 'groups', staleId, 'members', 'reader'));
    });
    await assert.rejects(discover(), permissionDenied);
});

test('missing group parent with surviving membership rejects with explicit integrity/unavailable error', async () => {
    await assign();
    await environment.withSecurityRulesDisabled(async context => {
        const db = context.firestore();
        await fixtureGroup(db, 'zzzz-missing');
        await deleteDoc(doc(db, 'groups', 'zzzz-missing'));
    });
    await assert.rejects(discover(), /integrity\/unavailable error: group zzzz-missing does not exist/);
});

test('discovery works without private profiles or any shared roster display documents', async () => {
    await assign();
    await environment.withSecurityRulesDisabled(async context => {
        for (const uid of ['owner', 'reader', 'other']) await deleteDoc(doc(context.firestore(), 'users', uid));
    });
    assert.equal((await discover()).groups[0].weeks[0].summary.total, 1);
});

test('server-only discovery rejects offline even after successful reads populated the cache', async () => {
    await assign();
    const db = dbFor('reader');
    assert.equal((await discoverMyAssignments(db, 'reader')).groups[0].weeks[0].summary.total, 1);
    await disableNetwork(db);
    try {
        await assert.rejects(discoverMyAssignments(db, 'reader'), error => error.code === 'unavailable');
    } finally {
        await enableNetwork(db);
    }
});

test('collection-group and global group discovery remain denied without rule expansion', async () => {
    await assign();
    const db = dbFor('owner');
    await assert.rejects(getDocsFromServer(query(collectionGroup(db, 'assignments'), limit(48))), permissionDenied);
    await assert.rejects(getDocsFromServer(query(collection(db, 'groups'), limit(10))), permissionDenied);
    await assert.rejects(getDocsFromServer(query(collection(db, 'users', 'owner', 'groups'), limit(51))), permissionDenied);
});