import {
    collection, doc, getDocFromServer, getDocsFromServer, runTransaction,
    serverTimestamp, query, orderBy, documentId, limit, startAfter,
} from 'firebase/firestore';

function segment(value, name) {
    if (typeof value !== 'string' || !value || value.includes('/')
        || value === '.' || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error(`${name} must be a valid single Firestore path segment.`);
    }
    return value;
}

function profiles(db, groupId) {
    return collection(db, 'groups', segment(groupId, 'Group ID'), 'memberProfiles');
}

/** Opt-in, group-visible display only: may differ from the private user profile.
 * No private-profile reads/copies, email, avatar, roles or identity verification.
 * Names are not unique or authenticated identities; render as untrusted text.
 * Caller UID is checked by rules against auth and current group membership.
 * Missing profiles should be shown by consumers as an unnamed member/UID.
 * Reference JS only, not Flutter integration or an automatic roster backfill.
 */
export async function setMemberDisplay(db, groupId, uid, displayName) {
    if (typeof displayName !== 'string' || displayName.length < 1
        || displayName.length > 100 || !displayName.trim()) {
        throw new Error('Display name must be nonblank and at most 100 characters.');
    }
    const reference = doc(profiles(db, groupId), segment(uid, 'Member UID'));
    await runTransaction(db, async transaction => {
        const existing = await transaction.get(reference);
        transaction.set(reference, {
            displayName,
            createdAt: existing.exists() ? existing.data().createdAt : serverTimestamp(),
            updatedAt: serverTimestamp(),
        });
    });
    return reference.id;
}

export async function getMemberDisplay(db, groupId, uid) {
    const snapshot = await getDocFromServer(doc(profiles(db, groupId), segment(uid, 'Member UID')));
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}

/** Only explicitly published displays, not the membership roster. Server-only
 * reads enforce current access; rules cannot erase already downloaded names.
 * Future privileged removal must coordinate stale display cleanup as well.
 */
export async function listMemberDisplays(db, groupId, afterId = null) {
    const constraints = [orderBy(documentId()), limit(50)];
    if (afterId !== null) constraints.push(startAfter(segment(afterId, 'Cursor ID')));
    const snapshot = await getDocsFromServer(query(profiles(db, groupId), ...constraints));
    return snapshot.docs.map(entry => ({ id: entry.id, ...entry.data() }));
}