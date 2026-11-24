import {
    collection, doc, setDoc, getDocFromServer, getDocsFromServer, serverTimestamp,
    Timestamp, query, orderBy, documentId, limit, startAfter,
} from 'firebase/firestore';

function segment(value, name) {
    if (typeof value !== 'string' || !value || value.includes('/')
        || value === '.' || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error(`${name} must be a valid single Firestore path segment.`);
    }
    return value;
}

function messages(db, groupId) {
    return collection(db, 'groups', segment(groupId, 'Group ID'), 'messages');
}

/** Reference JS only; supply an emulator-configured db for local use.
 * senderUid is untrusted input: rules bind it to auth and current membership.
 * No private identity snapshots, invite tokens, highlights or client clock time.
 * Auto-ID allocation is a helper convention, not an authorization boundary.
 * RELEASE GATE: moderation/reporting and coordinated retention/removal are
 * required before production chat. There is intentionally no edit/delete API.
 */
export async function sendMessage(db, groupId, senderUid, text) {
    segment(senderUid, 'Sender UID');
    if (typeof text !== 'string' || text.length < 1 || text.length > 2000 || !text.trim()) {
        throw new Error('Message text must be nonblank and at most 2000 characters.');
    }
    const reference = doc(messages(db, groupId));
    await setDoc(reference, { senderUid, text, createdAt: serverTimestamp() });
    return reference.id;
}

/** Server reads deliberately avoid presenting cached data after revocation.
 * Previously downloaded data cannot be remotely erased by security rules.
 */
export async function getMessage(db, groupId, messageId) {
    const snapshot = await getDocFromServer(doc(messages(db, groupId), segment(messageId, 'Message ID')));
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}

/** Newest first, with descending document ID as the deterministic tie-breaker.
 * Pass { createdAt: last.createdAt, id: last.id } as after, never just a time.
 * Preserve Timestamp nanoseconds; do not round the cursor to Date/milliseconds.
 * Pages are not a frozen snapshot: newly added messages appear on a fresh head
 * fetch, not by restarting an older-page cursor. No collection-group discovery.
 */
export async function listMessages(db, groupId, { pageSize = 50, after = null } = {}) {
    if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 50) {
        throw new Error('Page size must be an integer from 1 to 50.');
    }
    const constraints = [orderBy('createdAt', 'desc'), orderBy(documentId(), 'desc'), limit(pageSize)];
    if (after !== null) {
        if (!(after.createdAt instanceof Timestamp)) throw new Error('Cursor createdAt must be a Timestamp.');
        constraints.push(startAfter(after.createdAt, segment(after.id, 'Cursor ID')));
    }
    const snapshot = await getDocsFromServer(query(messages(db, groupId), ...constraints));
    return snapshot.docs.map(entry => ({ id: entry.id, ...entry.data() }));
}