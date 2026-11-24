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

function highlights(db, groupId) {
    return collection(db, 'groups', segment(groupId, 'Group ID'), 'highlights');
}

/** Local reference JS; use an emulator-configured db.
 * Intentional SQL schema difference: original chapterNumber (1..53), not a
 * language-specific chapter_id or canonical assignment unit. quote/text map
 * to highlighted_text/comment; paragraphIndex preserves the paragraph anchor.
 * No identity snapshot; rules authenticate senderUid independently.
 * RELEASE GATE: moderation/reporting and retention/removal must be reviewed
 * before production. No client edit/delete API, including for authors/admins.
 * Quote existence and paragraph accuracy are not verified against book content.
 */
export async function createHighlight(db, groupId, senderUid, {
    chapterNumber, paragraphIndex = 0, quote, text,
}) {
    segment(senderUid, 'Sender UID');
    if (!Number.isSafeInteger(chapterNumber) || chapterNumber < 1 || chapterNumber > 53) {
        throw new Error('Chapter number must be an integer from 1 to 53.');
    }
    if (!Number.isSafeInteger(paragraphIndex) || paragraphIndex < 0 || paragraphIndex > 2147483647) {
        throw new Error('Paragraph index must be an integer from 0 to 2147483647.');
    }
    for (const [name, value, maximum] of [['Quote', quote, 500], ['Text', text, 2000]]) {
        if (typeof value !== 'string' || !value.trim() || value.length > maximum) {
            throw new Error(`${name} must be nonblank and at most ${maximum} characters.`);
        }
    }
    const reference = doc(highlights(db, groupId));
    await setDoc(reference, { senderUid, chapterNumber, paragraphIndex, quote, text, createdAt: serverTimestamp() });
    return reference.id;
}

/** Server-only reads recheck membership; downloaded data cannot be erased. */
export async function getHighlight(db, groupId, highlightId) {
    const snapshot = await getDocFromServer(doc(highlights(db, groupId), segment(highlightId, 'Highlight ID')));
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}

/** Timestamp + descending ID cursor preserves ties and sub-millisecond time.
 * Pass the last entry as after. Pages are not a frozen snapshot; fetch a new
 * head for newly created entries. No collection-group discovery or filtering.
 */
export async function listHighlights(db, groupId, { pageSize = 50, after = null } = {}) {
    if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 50) {
        throw new Error('Page size must be an integer from 1 to 50.');
    }
    const constraints = [orderBy('createdAt', 'desc'), orderBy(documentId(), 'desc'), limit(pageSize)];
    if (after !== null) {
        if (!(after.createdAt instanceof Timestamp)) throw new Error('Cursor createdAt must be a Timestamp.');
        constraints.push(startAfter(after.createdAt, segment(after.id, 'Cursor ID')));
    }
    const snapshot = await getDocsFromServer(query(highlights(db, groupId), ...constraints));
    return snapshot.docs.map(entry => ({ id: entry.id, ...entry.data() }));
}