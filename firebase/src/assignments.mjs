import {
    collection, doc, getDoc, getDocs, runTransaction, updateDoc,
    serverTimestamp, Timestamp, query, orderBy, documentId, limit, startAfter,
} from 'firebase/firestore';
import { canonicalUnit } from './chapter-units.mjs';

function segment(value, name) {
    if (typeof value !== 'string' || !value || value.includes('/')
        || value === '.' || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error(`${name} must be a valid single Firestore path segment.`);
    }
    return value;
}

function assignmentsCollection(db, groupId, userId, weekNumber) {
    if (!Number.isSafeInteger(weekNumber) || weekNumber < 1 || weekNumber > 10000) {
        throw new Error('Week number must be an integer from 1 to 10000.');
    }
    return collection(db, 'groups', segment(groupId, 'Group ID'), 'readingWeeks',
        String(weekNumber), 'members', segment(userId, 'Assignee UID'), 'assignments');
}

/** One canonical document per group/member/week/unit; chapter aliases normalize. */
export function assignmentReference(db, groupId, userId, weekNumber, chapterNumber) {
    return doc(assignmentsCollection(db, groupId, userId, weekNumber), canonicalUnit(chapterNumber).unitKey);
}

/** Manual only. scheduledDate is a caller-supplied Date instant or null (default).
 * No default Monday, timezone inference, currentWeek advancement or auto-scheduling.
 * createdBy is an untrusted caller value: rules verify it against request.auth.uid.
 */
export async function createAssignment(db, createdBy, {
    groupId, userId, weekNumber = 1, chapterNumber, scheduledDate = null,
}) {
    segment(createdBy, 'Creator UID');
    if (scheduledDate !== null
        && (!(scheduledDate instanceof Date) || !Number.isFinite(scheduledDate.getTime()))) {
        throw new Error('Scheduled date must be a valid Date or null.');
    }
    const scheduledTimestamp = scheduledDate === null ? null : Timestamp.fromDate(scheduledDate);
    const reference = assignmentReference(db, groupId, userId, weekNumber, chapterNumber);
    const unit = canonicalUnit(chapterNumber);
    // Transaction provides explicit duplicate feedback, including admin self-assignments.
    // Rules independently deny changes to any existing assignment metadata.
    await runTransaction(db, async transaction => {
        if ((await transaction.get(reference)).exists()) throw new Error('Assignment already exists.');
        transaction.set(reference, {
            groupId, userId, weekNumber, ...unit, scheduledDate: scheduledTimestamp,
            createdBy, createdAt: serverTimestamp(),
            status: 'not_started', progressUpdatedAt: serverTimestamp(),
        });
    });
    return reference.id;
}

export async function getAssignment(db, groupId, userId, weekNumber, chapterNumber) {
    const snapshot = await getDoc(assignmentReference(db, groupId, userId, weekNumber, chapterNumber));
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}

/** Scoped roster reading: all group members may read another member's progress.
 * Limit 48 matches the entire canonical catalogue; cursors use document-ID order.
 * Collection-group queries and unbounded/global assignment discovery are not supported.
 */
export async function listAssignments(db, groupId, userId, weekNumber, afterId = null) {
    const constraints = [orderBy(documentId()), limit(48)];
    if (afterId !== null) constraints.push(startAfter(segment(afterId, 'Cursor')));
    const snapshot = await getDocs(query(
        assignmentsCollection(db, groupId, userId, weekNumber), ...constraints,
    ));
    return snapshot.docs.map(entry => ({ id: entry.id, ...entry.data() }));
}

/** Rules require the current assignee's authenticated identity and membership.
 * Status can move in either direction, matching the relational progress contract.
 * Concurrent valid progress changes are last-write-wins; no duplicate progress row.
 */
export async function updateReadingProgress(db, groupId, userId, weekNumber, chapterNumber, status) {
    if (!['not_started', 'in_progress', 'completed'].includes(status)) {
        throw new Error('Invalid reading status.');
    }
    await updateDoc(assignmentReference(db, groupId, userId, weekNumber, chapterNumber), {
        status, progressUpdatedAt: serverTimestamp(),
    });
}

export async function transitionAssignment(db, actorUid, {
    groupId, userId, weekNumber, chapterNumber, expectedRevision,
    expectedProgressUpdatedAt, archived, scheduledDate = null, reassignTo = null,
}) {
    segment(actorUid, 'Actor UID');
    if (typeof archived !== 'boolean' || !Number.isSafeInteger(expectedRevision)
        || expectedRevision < 0 || expectedRevision >= 2147483647
        || !(expectedProgressUpdatedAt instanceof Timestamp)) throw new Error('A confirmed assignment version is required.');
    if (scheduledDate !== null && (!(scheduledDate instanceof Date) || !Number.isFinite(scheduledDate.getTime()))) {
        throw new Error('Scheduled date must be an explicit Date or null.');
    }
    if (reassignTo !== null) {
        segment(reassignTo, 'New assignee UID');
        if (!archived || reassignTo === userId) throw new Error('Reassignment requires a different target UID.');
    }
    const reference = assignmentReference(db, groupId, userId, weekNumber, chapterNumber);
    await runTransaction(db, async transaction => {
        const group = await transaction.get(doc(db, 'groups', groupId));
        const actor = await transaction.get(doc(db, 'groups', groupId, 'members', actorUid));
        const snapshot = await transaction.get(reference);
        if (!group.exists() || group.data().archived === true || !actor.exists()
            || !['admin', 'group_lead'].includes(actor.data().role) || !snapshot.exists()) {
            throw new Error('An active group, scheduler and existing assignment are required.');
        }
        const previous = snapshot.data();
        if ((previous.revision ?? 0) !== expectedRevision || (previous.archived ?? false) === archived
            || !previous.progressUpdatedAt.isEqual(expectedProgressUpdatedAt)) throw new Error('Assignment changed. Reload before confirming.');
        const history = doc(reference, 'versions', String(expectedRevision));
        if ((await transaction.get(history)).exists()) throw new Error('Assignment version already retained.');
        const targetUid = reassignTo ?? userId;
        if (!archived || reassignTo !== null) {
            if (!(await transaction.get(doc(db, 'groups', groupId, 'members', targetUid))).exists()) throw new Error('Current target membership required.');
        }
        const target = reassignTo === null ? null : assignmentReference(db, groupId, reassignTo, weekNumber, chapterNumber);
        if (target !== null && (await transaction.get(target)).exists()) throw new Error('Target assignment already exists.');
        const fresh = {
            scheduledDate: scheduledDate === null ? null : Timestamp.fromDate(scheduledDate),
            createdBy: actorUid, createdAt: serverTimestamp(), status: 'not_started', progressUpdatedAt: serverTimestamp(),
        };
        transaction.set(history, previous);
        transaction.update(reference, {
            archived, revision: expectedRevision + 1,
            changedBy: actorUid, changedAt: serverTimestamp(), ...(!archived ? fresh : {})
        });
        if (target !== null) {
            transaction.set(target, { groupId, userId: reassignTo, weekNumber, ...canonicalUnit(chapterNumber), ...fresh });
        }
    });
}