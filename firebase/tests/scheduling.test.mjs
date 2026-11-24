import { readFileSync } from 'node:fs';
import { describe, before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, writeBatch, serverTimestamp, Timestamp } from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { CHAPTER_UNITS, canonicalUnit } from '../src/chapter-units.mjs';
import { createGroup, addMember, setMemberRole, updateGroup } from '../src/groups.mjs';
import { assignmentReference, createAssignment, listAssignments, updateReadingProgress } from '../src/assignments.mjs';
import {
    previewSchedule, suggestSchedule, commitSchedule, advanceWeek, SCHEDULE_LIMITS,
    SCHEDULE_MODES, REMAINDER_MODES
} from '../src/scheduling.mjs';

const snapshot = (overrides = {}) => ({
    mode: 'chapter_wise', chaptersPerWeek: 2,
    startChapter: 1, currentWeek: 1, ...overrides
});
const plan = (overrides = {}) => ({
    memberUids: ['reader', 'other'], weeksAhead: 2,
    scheduleMode: 'independent', remainderMode: 'truncate', ...overrides
});
const unitKeys = preview => preview.assignments.map(entry => entry.unitKey);

describe('pure scheduling preview and hints', () => {
    const offsets = {
        independent: [0, 2, 4, 6, 8, 10],
        rotating_window: [0, 2, 4, 2, 4, 6],
        dense_window: [0, 1, 2, 2, 3, 4],
        synchronized: [0, 0, 0, 2, 2, 2],
    };
    for (const mode of SCHEDULE_MODES) {
        test(`${mode} uses canonical unit offsets, explicit member order and weeks`, () => {
            const result = previewSchedule(snapshot({ currentWeek: 7, startChapter: 17 }),
                plan({ memberUids: ['other', 'reader', 'owner'], scheduleMode: mode }));
            const base = CHAPTER_UNITS.findIndex(unit => unit.chapterStart === 16);
            assert.equal(result.requestedCount, 12);
            assert.equal(result.unfilledCount, 0);
            assert.equal(result.reviewRequired, false);
            const expected = offsets[mode].flatMap((offset, index) => [0, 1].map(slot => ({
                userId: ['other', 'reader', 'owner'][index % 3], weekNumber: 7 + Math.floor(index / 3),
                ...CHAPTER_UNITS[base + offset + slot], scheduledDate: null,
            })));
            assert.deepEqual(result.assignments, expected);
        });
    }

    test('all 48 canonical units appear exactly once, not 53 separate chapters', () => {
        const result = previewSchedule(snapshot({ chaptersPerWeek: 48 }), plan({ memberUids: ['reader'], weeksAhead: 1 }));
        assert.deepEqual(unitKeys(result), CHAPTER_UNITS.map(unit => unit.unitKey));
        assert.equal(result.assignments.length, 48);
        for (const key of ['16-17', '18-19', '43-44', '51-53']) assert.ok(unitKeys(result).includes(key));
        for (const key of ['17', '19', '44', '52', '53']) assert.ok(!unitKeys(result).includes(key));
    });

    for (const remainderMode of REMAINDER_MODES) {
        test(`${remainderMode} reports exact end-of-book counts and unfilled positions`, () => {
            const result = previewSchedule(snapshot({ startChapter: 50 }), plan({ remainderMode }));
            assert.equal(result.requestedCount, 8);
            if (remainderMode === 'cycle') {
                assert.deepEqual(unitKeys(result), ['50', '51-53', '1', '2', '3', '4', '5', '6']);
                assert.equal(result.unfilledCount, 0);
                assert.deepEqual(result.unfilled, []);
            } else {
                assert.deepEqual(unitKeys(result), ['50', '51-53']);
                assert.equal(result.unfilledCount, 6);
                assert.deepEqual(result.unfilled, [
                    { userId: 'other', weekNumber: 1, slot: 0, unitPosition: 49 },
                    { userId: 'other', weekNumber: 1, slot: 1, unitPosition: 50 },
                    { userId: 'reader', weekNumber: 2, slot: 0, unitPosition: 51 },
                    { userId: 'reader', weekNumber: 2, slot: 1, unitPosition: 52 },
                    { userId: 'other', weekNumber: 2, slot: 0, unitPosition: 53 },
                    { userId: 'other', weekNumber: 2, slot: 1, unitPosition: 54 },
                ]);
            }
            assert.equal(result.reviewRequired, remainderMode === 'manual');
            assert.equal(result.assignments.length + result.unfilledCount, result.requestedCount);
        });
    }

    test('every mode/remainder combination has canonical unique member/week/unit paths', () => {
        for (const scheduleMode of SCHEDULE_MODES) for (const remainderMode of REMAINDER_MODES) {
            // Finishing remainders are defined for the independent mode only.
            if (scheduleMode !== 'independent' && ['extend_last', 'round_robin'].includes(remainderMode)) continue;
            const result = previewSchedule(snapshot({ chaptersPerWeek: 48, startChapter: 53 }),
                plan({ scheduleMode, remainderMode, weeksAhead: 3 }));
            const keys = result.assignments.map(entry => `${entry.userId}/${entry.weekNumber}/${entry.unitKey}`);
            assert.equal(new Set(keys).size, keys.length);
            assert.equal(keys.length + result.unfilled.length, 288);
            for (const entry of result.assignments) assert.deepEqual(canonicalUnit(entry.chapterStart), {
                unitKey: entry.unitKey, chapterStart: entry.chapterStart, chapterEnd: entry.chapterEnd,
            });
        }
    });

    test('unknown remainder/schedule/group modes and widths above 48 are rejected', () => {
        for (const remainderMode of ['extend', 'roundrobin', '', null]) {
            assert.throws(() => previewSchedule(snapshot(), plan({ remainderMode })), /Unsupported remainder/);
        }
        assert.throws(() => previewSchedule(snapshot({ mode: 'daily' }), plan()), /Unsupported group mode/);
        for (const chaptersPerWeek of [0, 49, 53, 1.5, '2', NaN, Infinity]) {
            assert.throws(() => previewSchedule(snapshot({ chaptersPerWeek }), plan()), /integer/);
        }
        assert.throws(() => previewSchedule(snapshot(), plan({ scheduleMode: 'custom' })), /Unsupported schedule/);
    });

    test('Saptah is a label only: the same weekly plan as a chapter-wise group', () => {
        for (const scheduleMode of SCHEDULE_MODES) {
            const saptah = previewSchedule(snapshot({ mode: 'saptah' }), plan({ scheduleMode }));
            assert.deepEqual(saptah, previewSchedule(snapshot(), plan({ scheduleMode })));
        }
    });

    test('extend_last and round_robin finish the book in the last planned week', () => {
        const members = ['a', 'b', 'c', 'd'];
        const base = { memberUids: members, weeksAhead: 5 };
        // 4 x 2 x 5 = 40 units; 8 remain, which is NOT less than a full week of 8: nothing is added.
        for (const remainderMode of ['extend_last', 'round_robin']) {
            const result = previewSchedule(snapshot(), plan({ ...base, remainderMode }));
            assert.equal(result.assignments.length, 40);
            assert.equal(result.extraCount, 0);
        }
        // Width 3: 4 x 3 x 3 = 36 units; 12 remain = a full week: nothing added. Four weeks cover all 48.
        assert.equal(previewSchedule(snapshot({ chaptersPerWeek: 3 }), plan({ ...base, weeksAhead: 4, remainderMode: 'extend_last' })).extraCount, 0);
        // Start at chapter 4 (position 3): 45 units remain, 40 planned, 5 extras in week 5.
        const date = new Date('2026-12-07T00:00:00Z');
        const extend = previewSchedule(snapshot({ startChapter: 4, currentWeek: 3 }),
            plan({ ...base, remainderMode: 'extend_last', firstWeekDate: date }));
        const dealt = previewSchedule(snapshot({ startChapter: 4, currentWeek: 3 }),
            plan({ ...base, remainderMode: 'round_robin', firstWeekDate: date }));
        const truncated = previewSchedule(snapshot({ startChapter: 4, currentWeek: 3 }),
            plan({ ...base, remainderMode: 'truncate', firstWeekDate: date }));
        assert.equal(truncated.extraCount, 0);
        assert.equal(truncated.assignments.length, 40);
        for (const result of [extend, dealt]) {
            assert.equal(result.extraCount, 5);
            assert.equal(result.requestedCount, 40);
            assert.equal(result.unfilledCount, 0);
            assert.deepEqual(result.assignments.slice(0, 40), truncated.assignments);
            const extras = result.assignments.slice(40);
            assert.deepEqual(extras.map(entry => entry.unitKey), CHAPTER_UNITS.slice(43).map(unit => unit.unitKey));
            for (const entry of extras) {
                assert.equal(entry.weekNumber, 7);
                assert.equal(entry.scheduledDate.toISOString(), '2027-01-04T00:00:00.000Z');
            }
            // Every unit from the start to the end of the book appears exactly once.
            assert.deepEqual(unitKeys(result), CHAPTER_UNITS.slice(3).map(unit => unit.unitKey));
        }
        assert.deepEqual(extend.assignments.slice(40).map(entry => entry.userId), ['d', 'd', 'd', 'd', 'd']);
        assert.deepEqual(dealt.assignments.slice(40).map(entry => entry.userId), ['a', 'b', 'c', 'd', 'a']);
    });

    test('finishing modes need the independent mode and truncate past the book end', () => {
        for (const remainderMode of ['extend_last', 'round_robin']) {
            for (const scheduleMode of SCHEDULE_MODES.filter(mode => mode !== 'independent')) {
                assert.throws(() => previewSchedule(snapshot(), plan({ scheduleMode, remainderMode })), /independent/);
            }
            const past = previewSchedule(snapshot({ startChapter: 50 }), plan({ remainderMode }));
            assert.deepEqual(past, { ...previewSchedule(snapshot({ startChapter: 50 }), plan()), reviewRequired: false });
        }
    });

    test('settings and plans reject missing/extra fields, invalid canonical starts and weeks', () => {
        for (const key of Object.keys(snapshot())) {
            const incomplete = snapshot(); delete incomplete[key];
            assert.throws(() => previewSchedule(incomplete, plan()), /settings fields/);
        }
        for (const key of Object.keys(plan())) {
            const incomplete = plan(); delete incomplete[key];
            assert.throws(() => previewSchedule(snapshot(), incomplete), /plan fields/);
        }
        assert.throws(() => previewSchedule(snapshot({ isAdmin: true }), plan()), /settings fields/);
        assert.throws(() => previewSchedule(snapshot(), plan({ arbitrary: true })), /plan fields/);
        for (const startChapter of [0, 54, 1.5, '1', null]) {
            assert.throws(() => previewSchedule(snapshot({ startChapter }), plan()), /Chapter number/);
            assert.throws(() => previewSchedule(snapshot(), plan({ startChapter })), /Chapter number/);
        }
        for (const currentWeek of [0, 10001, 1.5, '1', null]) {
            assert.throws(() => previewSchedule(snapshot({ currentWeek }), plan()), /Current week/);
        }
        for (const weeksAhead of [0, 13, 1.5, '1', null]) {
            assert.throws(() => previewSchedule(snapshot(), plan({ weeksAhead })), /Weeks ahead/);
        }
        assert.throws(() => previewSchedule(snapshot({ currentWeek: 10000 }), plan()), /exceeds 10000/);
        assert.equal(previewSchedule(snapshot({ currentWeek: 10000 }), plan({ weeksAhead: 1 })).assignments[0].weekNumber, 10000);
    });

    test('member IDs reject duplicates, sparse holes, path injection and excessive counts', () => {
        for (const memberUids of [[], null, ['reader', 'reader'], new Array(2),
        ...['', '.', '..', '__reserved__', 'a/b', 'é'.repeat(751), null, 1].map(uid => [uid]),
        Array.from({ length: 51 }, (_, i) => `u${i}`)]) {
            assert.throws(() => previewSchedule(snapshot(), plan({ memberUids })));
        }
        assert.equal(previewSchedule(snapshot({ chaptersPerWeek: 1 }), plan({
            memberUids: Array.from({ length: 50 }, (_, i) => `u${i}`), weeksAhead: 12,
        })).requestedCount, 600);
        assert.throws(() => previewSchedule(snapshot({ chaptersPerWeek: 48 }), plan({
            memberUids: Array.from({ length: 50 }, (_, i) => `u${i}`), weeksAhead: 2,
        })), /4096/);
        assert.deepEqual(SCHEDULE_LIMITS, { members: 50, weeks: 12, slots: 4096, atomicWrites: 48, atomicMembers: 12 });
    });

    test('dates are explicit immutable UTC instants with seven-day offsets and timestamp bounds', () => {
        const date = new Date('2026-10-31T18:30:00Z');
        const settings = Object.freeze(snapshot());
        const input = Object.freeze(plan({ memberUids: Object.freeze(['reader']), firstWeekDate: date }));
        const first = previewSchedule(settings, input);
        assert.deepEqual(first, previewSchedule(settings, input));
        assert.equal(first.assignments[2].scheduledDate.toISOString(), '2026-11-07T18:30:00.000Z');
        first.assignments[0].scheduledDate.setTime(0);
        assert.equal(date.toISOString(), '2026-10-31T18:30:00.000Z');
        assert.equal(first.assignments[1].scheduledDate.getTime(), date.getTime());
        for (const firstWeekDate of [new Date('invalid'), '2026-10-13', 0, Timestamp.now(), undefined]) {
            assert.throws(() => previewSchedule(snapshot(), plan({ firstWeekDate })), /valid Date/);
        }
        for (const firstWeekDate of [new Date('0000-12-31T00:00:00Z'), new Date('9999-12-31T00:00:00Z')]) {
            assert.throws(() => previewSchedule(snapshot(), plan({ firstWeekDate })));
        }
        assert.equal(previewSchedule(snapshot(), plan({ firstWeekDate: null })).assignments[0].scheduledDate, null);
    });

    test('hints use actual position gaps, infer position-zero base and canonicalize inner chapters', () => {
        const result = suggestSchedule(snapshot(), plan({ memberUids: ['a', 'b', 'c', 'd'] }), [
            { position: 3, chapterStart: 23 }, { position: 1, chapterStart: 19 },
        ]);
        assert.equal(result.detectedMode, 'rotating_window');
        assert.equal(result.detectedStep, 2);
        assert.equal(result.plan.startChapter, 15);
        assert.deepEqual(unitKeys(result.preview).slice(0, 8), ['15', '16-17', '18-19', '20', '21', '22', '23', '24']);
    });

    test('synchronized, rotating and dense hints agree across every supplied position', () => {
        for (const [step, mode] of [[0, 'synchronized'], [1, 'dense_window'], [2, 'rotating_window']]) {
            const input = plan({ memberUids: ['a', 'b', 'c', 'd'] });
            const result = suggestSchedule(snapshot(), input,
                [3, 0, 2].map(position => ({ position, chapterStart: CHAPTER_UNITS[4 + position * step].chapterStart })));
            assert.equal(result.detectedMode, mode);
            assert.equal(result.plan.startChapter, 5);
            assert.equal(input.scheduleMode, 'independent');
            assert.notEqual(result.plan.memberUids, input.memberUids);
            assert.deepEqual(result.preview, previewSchedule(snapshot(), result.plan));
        }
    });

    test('hints reject inconsistent, duplicate, custom, negative, fractional and negative-base patterns', () => {
        const input = plan({ memberUids: ['a', 'b', 'c', 'd'] });
        for (const hints of [
            [{ position: 0, chapterStart: 1 }, { position: 1, chapterStart: 3 }, { position: 3, chapterStart: 8 }],
            [{ position: 1, chapterStart: 2 }, { position: 1, chapterStart: 2 }],
            [{ position: 0, chapterStart: 1 }, { position: 1, chapterStart: 4 }],
            [{ position: 0, chapterStart: 4 }, { position: 1, chapterStart: 1 }],
            [{ position: 0, chapterStart: 1 }, { position: 2, chapterStart: 2 }],
            [{ position: 2, chapterStart: 1 }, { position: 3, chapterStart: 3 }],
        ]) assert.throws(() => suggestSchedule(snapshot(), input, hints));
    });

    test('hint schema, count, sparse holes and positions are strictly validated', () => {
        const valid = { position: 0, chapterStart: 1 };
        for (const hints of [null, [], [valid], new Array(2), Array(3).fill(valid),
            [valid, { position: 1 }], [valid, { position: 1, chapterStart: 2, custom: true }],
            ...[-1, 2, 0.5, '1'].map(position => [valid, { position, chapterStart: 2 }]),
            [valid, { position: 1, chapterStart: 54 }]]) {
            assert.throws(() => suggestSchedule(snapshot(), plan(), hints));
        }
    });
});

describe('scheduling transactions and independent security rules', () => {
    let environment;
    let groupId;
    const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
    const anonymous = () => environment.unauthenticatedContext().firestore();
    const groupRef = (db = dbFor('owner')) => doc(db, 'groups', groupId);
    const oneWeek = (overrides = {}) => plan({ weeksAhead: 1, ...overrides });
    const commit = (db = dbFor('owner'), uid = 'owner', overrides = {}) => commitSchedule(db, uid, {
        groupId, settings: snapshot(), plan: oneWeek(), ...overrides,
    });
    const rows = (uid = 'reader', week = 1) => listAssignments(dbFor('owner'), groupId, uid, week);
    const rawAssignment = (uid = 'reader', chapter = 1, createdBy = 'owner') => ({
        groupId, userId: uid, weekNumber: 1, ...canonicalUnit(chapter), scheduledDate: null,
        createdBy, createdAt: serverTimestamp(), status: 'not_started', progressUpdatedAt: serverTimestamp(),
    });
    const patchWeek = (db, changes) => updateDoc(groupRef(db), { ...changes, updatedAt: serverTimestamp() });

    before(async () => {
        const config = localConfig();
        environment = await initializeTestEnvironment({
            projectId: config.projectId,
            firestore: { ...config.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') }
        });
    });
    beforeEach(async () => {
        await environment.clearFirestore();
        for (const uid of ['owner', 'lead', 'reader', 'other', 'outsider']) {
            await setDoc(doc(dbFor(uid), 'users', uid), {
                displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
            });
        }
        groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Scheduling' });
        for (const uid of ['lead', 'reader', 'other']) await addMember(dbFor('owner'), groupId, uid);
        await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
    });
    after(async () => { await environment?.cleanup(); });

    test('admin atomically commits canonical assignments, server times and explicit dates without advancing week', async () => {
        const firstWeekDate = new Date('2026-10-15T18:30:00Z');
        const result = await assertSucceeds(commit(undefined, undefined, {
            plan: plan({ startChapter: 17, firstWeekDate }),
        }));
        assert.equal(result.assignmentPaths.length, 8);
        for (const entry of result.assignments) {
            const reference = assignmentReference(dbFor('reader'), groupId, entry.userId, entry.weekNumber, entry.chapterStart);
            assert.ok(result.assignmentPaths.includes(reference.path));
            const stored = (await getDoc(reference)).data();
            assert.equal(stored.createdBy, 'owner');
            assert.equal(stored.status, 'not_started');
            assert.ok(stored.createdAt instanceof Timestamp);
            assert.ok(stored.createdAt.isEqual(stored.progressUpdatedAt));
            assert.equal(stored.scheduledDate.toMillis(), firstWeekDate.getTime() + (entry.weekNumber - 1) * 604800000);
        }
        assert.equal((await getDoc(groupRef())).data().currentWeek, 1);
    });

    test('lead commits for members and self; admin self-scheduling is allowed', async () => {
        await assertSucceeds(commit(dbFor('lead'), 'lead', { plan: oneWeek({ memberUids: ['lead', 'reader'] }) }));
        await assertSucceeds(commit(undefined, undefined, { plan: oneWeek({ memberUids: ['owner'] }) }));
        assert.equal((await rows('lead'))[0].createdBy, 'lead');
        assert.equal((await rows('owner'))[0].createdBy, 'owner');
    });

    test('member, outsider, unauthenticated and forged-claim actors cannot schedule', async () => {
        for (const [db, uid] of [[dbFor('reader'), 'reader'], [dbFor('outsider'), 'outsider'],
        [anonymous(), 'owner'], [dbFor('reader', { role: 'admin', admin: true, userId: 'owner' }), 'reader']]) {
            await assert.rejects(commit(db, uid));
        }
        assert.deepEqual(await rows(), []);
        assert.deepEqual(await rows('other'), []);
    });

    test('rules bind claimed creator to authenticated UID even when helper reads a real privileged membership', async () => {
        for (const [db, uid] of [[dbFor('reader'), 'owner'], [dbFor('lead'), 'owner'],
        [dbFor('reader', { userId: 'lead', role: 'group_lead' }), 'lead']]) {
            await assertFails(commit(db, uid));
        }
        assert.deepEqual(await rows(), []);
    });

    test('duplicate at the last planned path aborts the entire transaction and preserves progress', async () => {
        await createAssignment(dbFor('owner'), 'owner', { groupId, userId: 'other', chapterNumber: 4 });
        await updateReadingProgress(dbFor('other'), groupId, 'other', 1, 4, 'completed');
        await assert.rejects(commit(), /already exists/);
        assert.deepEqual(await rows(), []);
        const existing = await rows('other');
        assert.equal(existing.length, 1);
        assert.equal(existing[0].status, 'completed');
    });

    test('repeated commits reject rather than overwrite or silently skip existing paths', async () => {
        await commit();
        const before = await rows();
        await assert.rejects(commit(), /already exists/);
        assert.deepEqual(await rows(), before);
        assert.equal((await rows('other')).length, 2);
    });

    test('missing target membership aborts all writes, even with an existing private profile', async () => {
        for (const uid of ['outsider', 'missing-user']) {
            await assert.rejects(commit(undefined, undefined, {
                plan: oneWeek({ memberUids: ['reader', uid] }),
            }), /current group member/);
        }
        assert.deepEqual(await rows(), []);
    });

    test('invalid target/group/creator path segments reject before IO', async () => {
        for (const value of ['', '.', '..', '__reserved__', 'a/b', 'x'.repeat(1501)]) {
            await assert.rejects(commitSchedule(null, 'owner', { groupId: value, settings: snapshot(), plan: oneWeek() }), /path segments/);
            await assert.rejects(commitSchedule(null, value, { groupId, settings: snapshot(), plan: oneWeek() }), /path segments/);
            await assert.rejects(commitSchedule(null, 'owner', { groupId, settings: snapshot(), plan: oneWeek({ memberUids: [value] }) }), /path segments/);
        }
    });

    test('Saptah-labelled group commits the same weekly plan; extend_last extras pass rules atomically', async () => {
        const saptahId = await createGroup(dbFor('owner'), 'owner', { name: 'Saptah', mode: 'saptah' });
        await addMember(dbFor('owner'), saptahId, 'reader');
        const saved = await commitSchedule(dbFor('owner'), 'owner', {
            groupId: saptahId, settings: snapshot({ mode: 'saptah' }), plan: oneWeek({ memberUids: ['reader'] }),
        });
        assert.deepEqual(unitKeys(saved), ['1', '2']);
        assert.equal((await listAssignments(dbFor('reader'), saptahId, 'reader', 1)).length, 2);
        // From chapter 47 five units remain: four are planned and the last one is the extra.
        await updateGroup(dbFor('owner'), groupId, { startChapter: 47 });
        const result = await commit(undefined, undefined, {
            settings: snapshot({ startChapter: 47 }), plan: oneWeek({ remainderMode: 'extend_last' }),
        });
        assert.equal(result.extraCount, 1);
        assert.deepEqual((await rows('reader')).map(row => row.unitKey).sort(), ['47', '48']);
        assert.deepEqual((await rows('other')).map(row => row.unitKey).sort(), ['49', '50', '51-53']);
    });

    test('stale width, canonical start and current week snapshots reject the entire preview', async () => {
        for (const changes of [{ chaptersPerWeek: 3 }, { startChapter: 17 }]) {
            await updateGroup(dbFor('owner'), groupId, changes);
            await assert.rejects(commit(), /settings changed/);
            await updateGroup(dbFor('owner'), groupId, { chaptersPerWeek: 2, startChapter: 1 });
        }
        await advanceWeek(dbFor('owner'), groupId);
        await assert.rejects(commit(), /settings changed/);
        assert.deepEqual(await rows(), []);
        assert.deepEqual(await rows('other'), []);
    });

    test('actual Saptah group cannot accept a forged chapter-wise snapshot; missing group rejects', async () => {
        const saptahId = await createGroup(dbFor('owner'), 'owner', { name: 'Saptah', mode: 'saptah' });
        await assert.rejects(commit(undefined, undefined, { groupId: saptahId }), /settings changed/);
        await assert.rejects(commit(undefined, undefined, { groupId: 'missing-group' }));
    });

    test('revoked lead authority is revalidated at commit time', async () => {
        previewSchedule(snapshot(), oneWeek());
        await setMemberRole(dbFor('owner'), groupId, 'lead', 'member');
        await assert.rejects(commit(dbFor('lead'), 'lead'), /current admins and leads/);
        assert.deepEqual(await rows(), []);
    });

    test('48 writes to one member succeed and 49+ writes reject before IO without chunking', async () => {
        await updateGroup(dbFor('owner'), groupId, { chaptersPerWeek: 48 });
        const result = await assertSucceeds(commit(undefined, undefined, {
            settings: snapshot({ chaptersPerWeek: 48 }), plan: oneWeek({ memberUids: ['reader'] }),
        }));
        assert.equal(result.assignmentPaths.length, 48);
        assert.equal((await rows()).length, 48);
        // Exact off-by-one boundary: 7 members × 7 units = 49 writes.
        await assert.rejects(commitSchedule(null, 'owner', {
            groupId,
            settings: snapshot({ chaptersPerWeek: 7 }), plan: oneWeek({
                memberUids: Array.from({ length: 7 }, (_, i) => `u${i}`), remainderMode: 'cycle',
            })
        }), /1\.\.48/);
        await assert.rejects(commitSchedule(null, 'owner', {
            groupId,
            settings: snapshot({ chaptersPerWeek: 25 }), plan: oneWeek({ remainderMode: 'cycle' })
        }), /1\.\.48/);
        assert.deepEqual(await rows('other'), []);
    });

    test('12 distinct members and 48 writes succeed within rule-call budget; 13 targets reject before IO', async () => {
        const memberUids = ['owner', 'lead', 'reader', 'other'];
        for (let i = 0; i < 8; i++) {
            const uid = `target${i}`;
            await setDoc(doc(dbFor(uid), 'users', uid), {
                displayName: uid,
                createdAt: serverTimestamp(), updatedAt: serverTimestamp()
            });
            await addMember(dbFor('owner'), groupId, uid);
            memberUids.push(uid);
        }
        await updateGroup(dbFor('owner'), groupId, { chaptersPerWeek: 4 });
        const result = await assertSucceeds(commit(undefined, undefined, {
            settings: snapshot({ chaptersPerWeek: 4 }), plan: oneWeek({ memberUids }),
        }));
        assert.equal(result.assignmentPaths.length, 48);
        for (const uid of memberUids) assert.equal((await rows(uid)).length, 4);
        await assert.rejects(commitSchedule(null, 'owner', {
            groupId,
            settings: snapshot({ chaptersPerWeek: 1 }), plan: oneWeek({ memberUids: [...memberUids, 'outsider'] })
        }), /12 target/);
    });

    test('manual remainder commits only real units, returns review gaps and does not invent assignments', async () => {
        const result = await commit(undefined, undefined, {
            plan: oneWeek({ startChapter: 53, remainderMode: 'manual' }),
        });
        assert.equal(result.requestedCount, 4);
        assert.equal(result.unfilledCount, 3);
        assert.equal(result.reviewRequired, true);
        assert.deepEqual((await rows()).map(entry => entry.unitKey), ['51-53']);
        assert.deepEqual(await rows('other'), []);
    });

    test('caller mutation after invocation cannot change the settings snapshot, targets or dates', async () => {
        const settings = snapshot();
        const input = oneWeek({ firstWeekDate: new Date('2026-10-15T00:00:00Z') });
        const pending = commit(undefined, undefined, { settings, plan: input });
        settings.currentWeek = 9000;
        input.memberUids[0] = 'outsider';
        input.firstWeekDate.setTime(0);
        input.startChapter = 50;
        await assertSucceeds(pending);
        const stored = await rows();
        assert.equal(stored.length, 2);
        assert.equal(stored[0].scheduledDate.toDate().toISOString(), '2026-10-15T00:00:00.000Z');
        assert.equal(stored[0].weekNumber, 1);
    });

    test('concurrent overlapping schedules have one winner and no partial loser writes', async () => {
        const results = await Promise.allSettled([
            commit(undefined, undefined, { plan: oneWeek({ memberUids: ['reader', 'other'] }) }),
            commit(dbFor('lead'), 'lead', { plan: oneWeek({ memberUids: ['reader', 'lead'] }) }),
        ]);
        assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
        assert.match(results.find(result => result.status === 'rejected').reason.message, /already exists/);
        const winner = results[0].status === 'fulfilled' ? 'owner' : 'lead';
        assert.equal((await rows()).length, 2);
        for (const entry of await rows()) assert.equal(entry.createdBy, winner);
        assert.equal((await rows('other')).length, winner === 'owner' ? 2 : 0);
        assert.equal((await rows('lead')).length, winner === 'lead' ? 2 : 0);
    });

    test('concurrent manual and scheduled creates cannot duplicate or partially commit a losing schedule', async () => {
        const results = await Promise.allSettled([
            commit(),
            createAssignment(dbFor('lead'), 'lead', { groupId, userId: 'other', chapterNumber: 4 }),
        ]);
        assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
        assert.match(results.find(result => result.status === 'rejected').reason.message, /already exists/);
        const scheduleWon = results[0].status === 'fulfilled';
        assert.equal((await rows()).length, scheduleWon ? 2 : 0);
        assert.equal((await rows('other')).length, scheduleWon ? 2 : 1);
    });

    test('authorized raw manual assignments may differ from preview algorithms: rules certify authorization, not formulas', async () => {
        await assertSucceeds(setDoc(assignmentReference(dbFor('owner'), groupId, 'reader', 1, 43), rawAssignment('reader', 43)));
        assert.deepEqual((await rows()).map(entry => entry.unitKey), ['43-44']);
        assert.ok(!unitKeys(previewSchedule(snapshot(), oneWeek())).includes('43-44'));
    });

    test('admins and leads advance by exactly one; settings updates cannot jump or mix with advancement', async () => {
        assert.equal(await assertSucceeds(advanceWeek(dbFor('owner'), groupId)), 2);
        assert.equal(await assertSucceeds(advanceWeek(dbFor('lead'), groupId)), 3);
        await assertFails(updateGroup(dbFor('lead'), groupId, { name: 'Lead rename' }));
        await environment.withSecurityRulesDisabled(async context => {
            await updateDoc(groupRef(context.firestore()), { currentWeek: 2 });
        });
        for (const db of [dbFor('reader'), dbFor('outsider'), anonymous(),
        dbFor('reader', { role: 'admin', admin: true, userId: 'owner' })]) {
            await assertFails(advanceWeek(db, groupId));
        }
        await assertSucceeds(updateGroup(dbFor('owner'), groupId, { name: 'Updated', chaptersPerWeek: 3, startChapter: 17 }));
        for (const changes of [{ currentWeek: 4 }, { currentWeek: 1 }, { currentWeek: 0 },
        { currentWeek: 3, name: 'Mixed' }, { currentWeek: 3, chaptersPerWeek: 4 },
        { currentWeek: 3, startChapter: 2 }, { currentWeek: 3, mode: 'saptah' },
        { currentWeek: 3, createdBy: 'reader' }, { currentWeek: 2.5 }, { currentWeek: '3' }]) {
            await assertFails(patchWeek(dbFor('owner'), changes));
        }
        await assertFails(updateDoc(groupRef(), { currentWeek: 3, updatedAt: Timestamp.fromMillis(0) }));
        assert.equal((await getDoc(groupRef())).data().currentWeek, 2);
        await assertSucceeds(patchWeek(dbFor('owner'), { currentWeek: 3 }));
    });

    test('concurrent successful admin advances each contribute one increment without lost updates', async () => {
        const values = await Promise.all(Array.from({ length: 3 }, () => advanceWeek(dbFor('owner'), groupId)));
        assert.deepEqual(values.sort((a, b) => a - b), [2, 3, 4]);
        assert.equal((await getDoc(groupRef())).data().currentWeek, 4);
        assert.deepEqual(await rows(), []);
    });

    test('week 10000 boundary: concurrent attempts allow one final increment and deny all overflow', async () => {
        // Explicit boundary fixture only: avoid 9998 real transactions. Normal
        // group/profile/membership fixtures above all use authorized source APIs.
        await environment.withSecurityRulesDisabled(async context => {
            await updateDoc(groupRef(context.firestore()), { currentWeek: 9999 });
        });
        const results = await Promise.allSettled([
            advanceWeek(dbFor('owner'), groupId), advanceWeek(dbFor('owner'), groupId),
        ]);
        assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
        assert.equal(results.find(result => result.status === 'fulfilled').value, 10000);
        assert.match(results.find(result => result.status === 'rejected').reason.message, /beyond week 10000/);
        await assert.rejects(advanceWeek(dbFor('owner'), groupId), /beyond week 10000/);
        await assertFails(patchWeek(dbFor('owner'), { currentWeek: 10001 }));
        await assertFails(patchWeek(dbFor('owner'), { currentWeek: 9999 }));
        assert.equal((await getDoc(groupRef())).data().currentWeek, 10000);
    });

    test('forged membership/admin roles cannot bootstrap week advancement in a batch', async () => {
        for (const uid of ['reader', 'lead']) {
            const db = dbFor(uid);
            const batch = writeBatch(db);
            batch.update(doc(db, 'groups', groupId, 'members', uid), { role: 'admin' });
            batch.update(groupRef(db), { currentWeek: 2, updatedAt: serverTimestamp() });
            await assertFails(batch.commit());
        }
        const db = dbFor('outsider');
        const batch = writeBatch(db);
        batch.set(doc(db, 'groups', groupId, 'members', 'outsider'), {
            userId: 'outsider', role: 'admin', joinedAt: serverTimestamp(),
        });
        batch.set(doc(db, 'users', 'outsider', 'groups', groupId), { groupId, joinedAt: serverTimestamp() });
        batch.update(groupRef(db), { currentWeek: 2, updatedAt: serverTimestamp() });
        await assertFails(batch.commit());
        assert.equal((await getDoc(groupRef())).data().currentWeek, 1);
        assert.equal((await getDoc(doc(dbFor('owner'), 'groups', groupId, 'members', 'reader'))).data().role, 'member');
    });

    test('advanceWeek validates group paths and cannot create missing groups', async () => {
        await assert.rejects(advanceWeek(dbFor('owner'), 'missing-group'));
        for (const id of ['', '.', '..', '__reserved__', 'a/b']) {
            await assert.rejects(advanceWeek(null, id), /path segments/);
        }
    });
});