import {
    collection, doc, getDocFromServer, getDocsFromServer,
    query, orderBy, documentId, limit, startAfter,
} from 'firebase/firestore';

export const DISCOVERY_LIMITS = Object.freeze({ groups: 10, weeks: 3 });

function segment(value, name) {
    if (typeof value !== 'string' || !value || value.includes('/')
        || value === '.' || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error(`${name} must be a valid single Firestore path segment.`);
    }
    return value;
}

function integer(value, name, maximum) {
    if (!Number.isSafeInteger(value) || value < 1 || value > maximum) {
        throw new Error(`${name} must be an integer from 1 to ${maximum}.`);
    }
    return value;
}

function summarize(assignments) {
    const summary = { total: assignments.length, notStarted: 0, inProgress: 0, completed: 0 };
    for (const assignment of assignments) {
        switch (assignment.status) {
            case 'not_started': summary.notStarted++; break;
            case 'in_progress': summary.inProgress++; break;
            case 'completed': summary.completed++; break;
            default: throw new Error('Assignment discovery integrity error: invalid reading status.');
        }
    }
    return summary;
}

/** Local reference client; no writes, roster/private-profile reads or arbitrary
 * group input. UID validation is NOT authorization: rules require the caller's
 * own users/{uid}/groups index, even for admins who can directly read others'
 * assignments. Every read is server-only; permission/offline failures reject the
 * whole call, never return partial results or fall back to downloaded cache.
 *
 * Sequential reads bound concurrency but are NOT an atomic multi-read snapshot.
 * Revocation after an already completed read cannot retract downloaded data;
 * there is no erasure guarantee. A new request rechecks current server access.
 * Summaries cover only this UID and each selected week, not group/all-time totals.
 *
 * At most 10*3*48 assignment documents + 10 index + 10 metadata documents are
 * returned by reads. This is NOT a billing cap: rule-dependent document reads
 * may add charges, and empty queries have minimum charges (not one read/query).
 * Cursors follow index IDs, including empty groups. A full final page returns a
 * conservative continuation cursor and may require one additional empty page.
 */
export async function discoverMyAssignments(db, uid, {
    pageSize = 5, afterGroupId = null, weeksAhead = 1, weekNumber = null,
} = {}) {
    segment(uid, 'UID');
    integer(pageSize, 'Page size', DISCOVERY_LIMITS.groups);
    integer(weeksAhead, 'Weeks ahead', DISCOVERY_LIMITS.weeks);
    if (weekNumber !== null) integer(weekNumber, 'Week number', 10000);
    const constraints = [orderBy(documentId(), 'asc'), limit(pageSize)];
    if (afterGroupId !== null) constraints.push(startAfter(segment(afterGroupId, 'Cursor ID')));
    const index = await getDocsFromServer(query(collection(db, 'users', uid, 'groups'), ...constraints));
    const groups = [];
    for (const entry of index.docs) {
        const groupId = entry.id;
        const snapshot = await getDocFromServer(doc(db, 'groups', groupId));
        if (!snapshot.exists()) {
            throw new Error(`Assignment discovery integrity/unavailable error: group ${groupId} does not exist.`);
        }
        const { name, currentWeek } = snapshot.data();
        integer(currentWeek, 'Group current week', 10000);
        const startWeek = weekNumber ?? currentWeek;
        const weeks = [];
        for (let offset = 0; offset < weeksAhead && startWeek + offset <= 10000; offset++) {
            const selectedWeek = startWeek + offset;
            const result = await getDocsFromServer(query(collection(db, 'groups', groupId,
                'readingWeeks', String(selectedWeek), 'members', uid, 'assignments'),
                orderBy(documentId(), 'asc'), limit(48)));
            const assignments = result.docs.map(item => ({ ...item.data(), id: item.id }));
            weeks.push({ weekNumber: selectedWeek, assignments, summary: summarize(assignments) });
        }
        groups.push({ groupId, name, currentWeek, weeks });
    }
    return {
        groups,
        nextAfterGroupId: index.size === pageSize ? index.docs.at(-1).id : null,
    };
}