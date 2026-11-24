import { doc, runTransaction, serverTimestamp, Timestamp } from 'firebase/firestore';
import { CHAPTER_UNITS, canonicalUnit } from './chapter-units.mjs';
import { assignmentReference } from './assignments.mjs';

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const SETTINGS_KEYS = ['mode', 'chaptersPerWeek', 'startChapter', 'currentWeek'];
export const SCHEDULE_LIMITS = Object.freeze({
    members: 50, weeks: 12, slots: 4096,
    atomicWrites: 48, atomicMembers: 12
});
export const SCHEDULE_MODES = Object.freeze([
    'independent', 'rotating_window', 'dense_window', 'synchronized',
]);
export const REMAINDER_MODES = Object.freeze(['manual', 'truncate', 'cycle', 'extend_last', 'round_robin']);

function segment(value) {
    if (typeof value !== 'string' || !value || value.includes('/') || value === '.'
        || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error('IDs must be valid single Firestore path segments.');
    }
    return value;
}

function integer(value, low, high, name) {
    if (!Number.isSafeInteger(value) || value < low || value > high) {
        throw new Error(`${name} must be an integer from ${low} to ${high}.`);
    }
    return value;
}

function fields(value, allowed, required, name) {
    if (!value || typeof value !== 'object' || Array.isArray(value)
        || Object.keys(value).some(key => !allowed.includes(key))
        || required.some(key => !Object.hasOwn(value, key))) {
        throw new Error(`Invalid ${name} fields.`);
    }
}

function validateSettings(settings) {
    fields(settings, SETTINGS_KEYS, SETTINGS_KEYS, 'settings');
    // Saptah is a group label only (legacy parity): both modes share this weekly
    // scheduling. There is no separate seven-day algorithm.
    if (!['chapter_wise', 'saptah'].includes(settings.mode)) throw new Error('Unsupported group mode.');
    integer(settings.chaptersPerWeek, 1, 48, 'Units per member per week');
    canonicalUnit(settings.startChapter);
    integer(settings.currentWeek, 1, 10000, 'Current week');
}

/** Deterministic, pure reference preview, NOT a trusted background job.
 * Settings are explicit snapshots of the four group scheduling fields. Plan:
 * { memberUids, weeksAhead, scheduleMode, remainderMode, startChapter?, firstWeekDate? }.
 * weeksAhead INCLUDES currentWeek, unlike backend suggestion's extra-weeks count.
 * Member order is supplied explicitly (no hidden join-order fetch/sort); a
 * selected subset is allowed, not a claim that the complete roster is covered.
 * Dates are explicit Date instants or null; subsequent weeks add exactly seven
 * UTC days. No implicit clock/Monday, local-calendar/DST or reminder semantics.
 * Backend modes researched: all four SCHEDULE_MODES; remainder manual/truncate/
 * cycle/extend_last/round_robin. The backend's extend_last/round_robin branches
 * were unreachable, so they are defined here instead: for the independent mode
 * only, when fewer units than one full week (members x width) remain after the
 * plan, they are added to the FINAL planned week so the book finishes there.
 * extend_last gives them all to the last member; round_robin deals them one
 * each to members in order. Past the book end both behave like truncate.
 * manual and truncate both omit overflow and report EVERY unfilled slot;
 * manual means review is needed, not imaginary out-of-book assignments.
 */
export function previewSchedule(settings, plan) {
    validateSettings(settings);
    const required = ['memberUids', 'weeksAhead', 'scheduleMode', 'remainderMode'];
    fields(plan, [...required, 'startChapter', 'firstWeekDate'], required, 'plan');
    if (!SCHEDULE_MODES.includes(plan.scheduleMode)) throw new Error('Unsupported schedule mode.');
    if (!REMAINDER_MODES.includes(plan.remainderMode)) throw new Error('Unsupported remainder mode.');
    const finishing = ['extend_last', 'round_robin'].includes(plan.remainderMode);
    if (finishing && plan.scheduleMode !== 'independent') {
        throw new Error('extend_last and round_robin require the independent schedule mode.');
    }
    if (!Array.isArray(plan.memberUids) || plan.memberUids.length < 1
        || plan.memberUids.length > SCHEDULE_LIMITS.members) throw new Error('Member count must be 1..50.');
    // Array.from visits sparse holes too: malformed arrays cannot skip validation.
    const members = Array.from(plan.memberUids, segment);
    if (new Set(members).size !== members.length) throw new Error('Duplicate member UID.');
    const weeks = integer(plan.weeksAhead, 1, SCHEDULE_LIMITS.weeks, 'Weeks ahead');
    if (settings.currentWeek + weeks - 1 > 10000) throw new Error('Week range exceeds 10000.');
    const width = settings.chaptersPerWeek;
    const requestedCount = members.length * weeks * width;
    if (requestedCount > SCHEDULE_LIMITS.slots) throw new Error('Preview exceeds 4096 requested slots.');
    const start = canonicalUnit(Object.hasOwn(plan, 'startChapter') ? plan.startChapter : settings.startChapter);
    const base = CHAPTER_UNITS.findIndex(unit => unit.unitKey === start.unitKey);
    const date = Object.hasOwn(plan, 'firstWeekDate') ? plan.firstWeekDate : null;
    if (date !== null && (!(date instanceof Date) || !Number.isFinite(date.getTime()))) {
        throw new Error('First week date must be a valid Date or null.');
    }
    // Validate Firestore's timestamp range, including the FINAL week, before loops.
    if (date !== null) {
        Timestamp.fromMillis(date.getTime());
        Timestamp.fromMillis(date.getTime() + (weeks - 1) * WEEK_MS);
    }
    const assignments = [];
    const unfilled = [];
    for (let k = 0; k < weeks; k++) {
        const weekNumber = settings.currentWeek + k;
        for (let i = 0; i < members.length; i++) {
            const offset = plan.scheduleMode === 'independent' ? (k * members.length + i) * width
                : plan.scheduleMode === 'rotating_window' ? (k + i) * width
                    : plan.scheduleMode === 'dense_window' ? k * width + i : k * width;
            for (let slot = 0; slot < width; slot++) {
                const position = base + offset + slot;
                if (position >= 48 && plan.remainderMode !== 'cycle') {
                    unfilled.push({ userId: members[i], weekNumber, slot, unitPosition: position + 1 });
                } else {
                    assignments.push({
                        userId: members[i], weekNumber,
                        ...CHAPTER_UNITS[position % 48],
                        scheduledDate: date === null ? null : new Date(date.getTime() + k * WEEK_MS)
                    });
                }
            }
        }
    }
    // Independent plans consume contiguous units, so the leftover is one number.
    const extraCount = 48 - base - requestedCount;
    const finishes = finishing && extraCount > 0 && extraCount < members.length * width;
    for (let extra = 0; finishes && extra < extraCount; extra++) {
        assignments.push({
            userId: members[plan.remainderMode === 'extend_last' ? members.length - 1 : extra % members.length],
            weekNumber: settings.currentWeek + weeks - 1,
            ...CHAPTER_UNITS[base + requestedCount + extra],
            scheduledDate: date === null ? null : new Date(date.getTime() + (weeks - 1) * WEEK_MS)
        });
    }
    return {
        assignments, requestedCount, extraCount: finishes ? extraCount : 0,
        unfilledCount: unfilled.length, unfilled,
        reviewRequired: plan.remainderMode === 'manual' && unfilled.length > 0
    };
}

/** Validated hints { position, chapterStart }, in canonical UNIT positions.
 * Unlike the backend first-two subtraction, divide by the actual position gap,
 * infer position-zero's base, and require ALL hints to agree. Inner chapters
 * normalize to their canonical unit. Only synchronized/window patterns are
 * identifiable from one week's hints; independent vs rotating is ambiguous.
 * Nonintegral, negative, custom, duplicate or inconsistent hints are rejected.
 * Returned plan is reviewable and can be passed explicitly to commitSchedule.
 */
export function suggestSchedule(settings, plan, hints) {
    previewSchedule(settings, plan); // Bounded input validation before hint traversal.
    if (!Array.isArray(hints) || hints.length < 2 || hints.length > plan.memberUids.length) {
        throw new Error('Provide 2..member-count hints.');
    }
    const ordered = Array.from(hints, hint => {
        fields(hint, ['position', 'chapterStart'], ['position', 'chapterStart'], 'hint');
        const position = integer(hint.position, 0, plan.memberUids.length - 1, 'Hint position');
        const unit = canonicalUnit(hint.chapterStart);
        return { position, index: CHAPTER_UNITS.findIndex(entry => entry.unitKey === unit.unitKey) };
    }).sort((a, b) => a.position - b.position);
    if (new Set(ordered.map(hint => hint.position)).size !== ordered.length) throw new Error('Duplicate hint position.');
    const step = (ordered[1].index - ordered[0].index) / (ordered[1].position - ordered[0].position);
    const base = ordered[0].index - ordered[0].position * step;
    if (!Number.isSafeInteger(step) || step < 0 || !Number.isSafeInteger(base) || base < 0 || base >= 48
        || ordered.some(hint => hint.index !== base + hint.position * step)) {
        throw new Error('Hints must define a consistent nonnegative integral unit pattern.');
    }
    const mode = step === 0 ? 'synchronized'
        : step === settings.chaptersPerWeek ? 'rotating_window' : step === 1 ? 'dense_window' : null;
    if (mode === null) throw new Error('Custom hint steps are not supported.');
    const suggestedPlan = {
        ...plan, memberUids: [...plan.memberUids], scheduleMode: mode,
        startChapter: CHAPTER_UNITS[base].chapterStart
    };
    return {
        detectedMode: mode, detectedStep: step, plan: suggestedPlan,
        preview: previewSchedule(settings, suggestedPlan)
    };
}

/** All-or-nothing, create-only transaction. No skip-existing/idempotent overwrite
 * or hidden chunking. >48 writes OR >12 distinct targets is rejected before IO;
 * the latter reserves headroom in Firestore's 20 rule-document-call budget.
 * Larger previews need separate explicit user-reviewed plans; cross-plan atomicity
 * is NOT provided. Empty plans reject. All reads precede writes; a duplicate
 * anywhere aborts the whole plan, including races with manual assignments.
 * Settings/role/target reads revalidate on retries, protecting stale previews.
 * Rules independently authorize EVERY assignment using pre-write memberships,
 * creator auth, canonical path/unit/week and immutable metadata. Client previews,
 * hint detection, membership fields and claimed creator are NEVER authority.
 * Raw authorized manual writes remain allowed; rules do not certify formulas,
 * complete-roster coverage, dates or settings provenance as a trusted schedule.
 */
export async function commitSchedule(db, createdBy, { groupId, settings, plan }) {
    segment(groupId);
    segment(createdBy);
    // Copy validated inputs before awaiting: caller mutation cannot alter writes.
    const expected = { ...settings };
    const preview = previewSchedule(expected, plan);
    const targets = [...new Set(preview.assignments.map(entry => entry.userId))];
    if (preview.assignments.length < 1 || preview.assignments.length > SCHEDULE_LIMITS.atomicWrites
        || targets.length > SCHEDULE_LIMITS.atomicMembers) {
        throw new Error('Atomic plan requires 1..48 writes and at most 12 target members; no automatic chunking.');
    }
    const group = doc(db, 'groups', groupId);
    const references = preview.assignments.map(entry => assignmentReference(
        db, groupId, entry.userId, entry.weekNumber, entry.chapterStart,
    ));
    await runTransaction(db, async transaction => {
        const current = await transaction.get(group);
        if (!current.exists() || SETTINGS_KEYS.some(key => current.data()[key] !== expected[key])) {
            throw new Error('Group scheduling settings changed; preview again.');
        }
        const actor = await transaction.get(doc(db, 'groups', groupId, 'members', createdBy));
        if (!actor.exists() || !['admin', 'group_lead'].includes(actor.data().role)) {
            throw new Error('Only current admins and leads can schedule.');
        }
        for (const uid of targets) {
            if (!(await transaction.get(doc(db, 'groups', groupId, 'members', uid))).exists()) {
                throw new Error('Every assignee must be a current group member.');
            }
        }
        for (const reference of references) {
            if ((await transaction.get(reference)).exists()) throw new Error('Assignment already exists; entire plan rejected.');
        }
        preview.assignments.forEach((entry, index) => transaction.set(references[index], {
            ...entry, groupId, createdBy,
            scheduledDate: entry.scheduledDate === null ? null : Timestamp.fromDate(entry.scheduledDate),
            createdAt: serverTimestamp(), status: 'not_started', progressUpdatedAt: serverTimestamp(),
        }));
    });
    return { ...preview, assignmentPaths: references.map(reference => reference.path) };
}

/** Admin-only atomic +1, no arbitrary week argument, scheduling or skipped weeks.
 * Read/compare/write transaction retries against the current week, so concurrent
 * successful calls each contribute one increment. Rules enforce old+1 separately
 * from settings updates and reject mixed changes, forged roles and upper overflow.
 */
export async function advanceWeek(db, groupId) {
    const reference = doc(db, 'groups', segment(groupId));
    return runTransaction(db, async transaction => {
        const snapshot = await transaction.get(reference);
        if (!snapshot.exists()) throw new Error('Group not found.');
        const week = integer(snapshot.data().currentWeek, 1, 10000, 'Current week');
        if (week === 10000) throw new Error('Cannot advance beyond week 10000.');
        transaction.update(reference, { currentWeek: week + 1, updatedAt: serverTimestamp() });
        return week + 1;
    });
}