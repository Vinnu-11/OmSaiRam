import {
    collection, doc, getDoc, getDocs, writeBatch, updateDoc, serverTimestamp,
    query, orderBy, documentId, limit, startAfter,
} from 'firebase/firestore';

function page(reference, afterId) {
    const constraints = [orderBy(documentId()), limit(50)];
    if (afterId !== null) constraints.push(startAfter(afterId));
    return query(reference, ...constraints);
}

/** Firestore client contract, with authorization enforced by deployed rules.
 * Local tests use emulator-configured db instances. Flutter is not wired yet.
 */
export async function createGroup(db, uid, options) {
    if (!uid) throw new Error('An authenticated Firebase UID is required.');
    const reference = doc(collection(db, 'groups'));
    const batch = writeBatch(db);
    batch.set(reference, {
        name: options.name,
        description: options.description ?? '',
        mode: options.mode ?? 'chapter_wise',
        createdBy: uid,
        chaptersPerWeek: options.chaptersPerWeek ?? 2,
        startChapter: options.startChapter ?? 1,
        currentWeek: 1,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'groups', reference.id, 'members', uid), {
        userId: uid, role: 'admin', joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'users', uid, 'groups', reference.id), {
        groupId: reference.id, joinedAt: serverTimestamp(),
    });
    await batch.commit();
    return reference.id;
}

export async function listMyGroups(db, uid, afterId = null) {
    const index = await getDocs(page(collection(db, 'users', uid, 'groups'), afterId));
    const groups = await Promise.all(index.docs.map(entry => getDoc(doc(db, 'groups', entry.id))));
    return groups.filter(snapshot => snapshot.exists())
        .map(snapshot => ({ id: snapshot.id, ...snapshot.data() }));
}

export async function getGroup(db, groupId) {
    const snapshot = await getDoc(doc(db, 'groups', groupId));
    return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}

export async function listMembers(db, groupId, afterId = null) {
    const snapshot = await getDocs(page(collection(db, 'groups', groupId, 'members'), afterId));
    // No private profile/name/email copies; cross-user profiles remain private.
    return snapshot.docs.map(entry => ({ id: entry.id, ...entry.data() }));
}

export async function addMember(db, groupId, uid) {
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', groupId, 'members', uid), {
        userId: uid, role: 'member', joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'users', uid, 'groups', groupId), {
        groupId, joinedAt: serverTimestamp(),
    });
    await batch.commit();
}

export async function setMemberRole(db, groupId, uid, role) {
    await updateDoc(doc(db, 'groups', groupId, 'members', uid), { role });
}

export async function updateGroup(db, groupId, changes) {
    await updateDoc(doc(db, 'groups', groupId), { ...changes, updatedAt: serverTimestamp() });
}