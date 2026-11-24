import {
    collection, doc, setDoc, updateDoc, getDocFromServer, getDocsFromServer,
    runTransaction, serverTimestamp, query, orderBy, documentId, limit, startAfter,
} from 'firebase/firestore';

function segment(value, name) {
    if (typeof value !== 'string' || !value || value.includes('/')
        || value === '.' || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error(`${name} must be a valid single Firestore path segment.`);
    }
    return value;
}

function kindValue(kind) {
    if (!['messages', 'highlights'].includes(kind)) throw new Error('Kind must be messages or highlights.');
    return kind;
}

function reasonValue(reason) {
    if (!['spam', 'harassment', 'inappropriate', 'other'].includes(reason)) {
        throw new Error('Reason must be spam, harassment, inappropriate or other.');
    }
    return reason;
}

function target(db, groupId, kind, itemId) {
    return doc(db, 'groups', segment(groupId, 'Group ID'), kindValue(kind), segment(itemId, 'Item ID'));
}

function records(db, groupId, kind) {
    return collection(db, 'groups', segment(groupId, 'Group ID'), 'moderationRecords', kindValue(kind), 'items');
}

function report(db, groupId, kind, itemId, reporterUid) {
    return doc(target(db, groupId, kind, itemId), 'reports', segment(reporterUid, 'Reporter UID'));
}

/** Local reference clients only. Actor arguments are untrusted; rules bind
 * authority to prewrite membership, never claims or helper validation.
 * One report per reporter/item; resubmission is denied, not an overwrite.
 */
export async function reportContent(db, groupId, kind, itemId, reporterUid, { reason, details = '' }) {
    const reference = report(db, groupId, kind, itemId, reporterUid);
    reasonValue(reason);
    if (typeof details !== 'string' || details.length > 1000) {
        throw new Error('Details must be a string of at most 1000 characters.');
    }
    await setDoc(reference, {
        reporterUid, reason, details, createdAt: serverTimestamp(),
        status: 'open', resolvedBy: null, resolvedAt: null,
    });
    return reference.id;
}

/** Server reads recheck access, including after removal. Downloaded data cannot
 * be remotely erased. Reports are retained beneath deleted item documents.
 */
export async function getReport(db, groupId, kind, itemId, reporterUid) {
    const snapshot = await getDocFromServer(report(db, groupId, kind, itemId, reporterUid));
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}

async function boundedList(reference, { pageSize = 50, after = null } = {}) {
    if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 50) {
        throw new Error('Page size must be an integer from 1 to 50.');
    }
    // Single document-ID ordering needs no additional composite index. Cursor
    // is the previous entry's id, not a time; pages are not frozen snapshots.
    const constraints = [orderBy(documentId(), 'asc'), limit(pageSize)];
    if (after !== null) constraints.push(startAfter(segment(after, 'Cursor ID')));
    const snapshot = await getDocsFromServer(query(reference, ...constraints));
    return snapshot.docs.map(entry => ({ id: entry.id, ...entry.data() }));
}

export async function listReports(db, groupId, kind, itemId, options) {
    return boundedList(collection(target(db, groupId, kind, itemId), 'reports'), options);
}

/** One-way resolution; deliberately does not delete or hide the target. */
export async function resolveReport(db, groupId, kind, itemId, reporterUid, moderatedBy, status) {
    const reference = report(db, groupId, kind, itemId, reporterUid);
    segment(moderatedBy, 'Moderator UID');
    if (!['resolved', 'dismissed'].includes(status)) throw new Error('Status must be resolved or dismissed.');
    await updateDoc(reference, { status, resolvedBy: moderatedBy, resolvedAt: serverTimestamp() });
    return reference.id;
}

/** Atomic hard removal, with no copied text/quote or report requirement. Reads
 * both target and immutable marker before writes so retries reject duplicates.
 * IDs remain reserved indefinitely until privileged cleanup; reports remain.
 */
export async function removeContent(db, groupId, kind, itemId, moderatedBy, reason) {
    const reference = target(db, groupId, kind, itemId);
    const marker = doc(records(db, groupId, kind), itemId);
    segment(moderatedBy, 'Moderator UID');
    reasonValue(reason);
    return runTransaction(db, async transaction => {
        const item = await transaction.get(reference);
        const audit = await transaction.get(marker);
        if (audit.exists()) throw new Error('Content has already been moderated.');
        if (!item.exists()) throw new Error('Content does not exist.');
        transaction.set(marker, {
            targetKind: kind, targetId: itemId, authorUid: item.data().senderUid,
            moderatedBy, moderatedAt: serverTimestamp(), reason,
        });
        transaction.delete(reference);
        return itemId;
    });
}

export async function listModerationRecords(db, groupId, kind, options) {
    return boundedList(records(db, groupId, kind), options);
}