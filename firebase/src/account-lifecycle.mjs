import {
    collection, doc, getDocFromServer, getDocsFromServer, runTransaction, serverTimestamp, deleteField,
    query, orderBy, documentId, limit, startAfter, writeBatch,
} from 'firebase/firestore';
import { leaveGroup } from './membership-lifecycle.mjs';

const PAGE = 50, MAX_GROUPS = 500;

/** True while the private profile carries the `deactivatedAt` marker. */
export async function isAccountDeactivated(db, uid) {
    const snapshot = await getDocFromServer(doc(db, 'users', uid));
    if (!snapshot.exists()) throw new Error('Private profile required.');
    return 'deactivatedAt' in snapshot.data();
}

/** The caller's groups, found through the caller's own private index.
 * Rules cannot enumerate groups, so ownership preconditions are client-enforced
 * and not atomic with later writes; rules only deny transfers to deactivated users.
 */
async function scanGroups(db, uid) {
    const groups = [];
    let after = null;
    for (; ;) {
        const constraints = [orderBy(documentId()), limit(PAGE)];
        if (after !== null) constraints.push(startAfter(after));
        const index = await getDocsFromServer(query(collection(db, 'users', uid, 'groups'), ...constraints));
        for (const entry of index.docs) {
            const group = await getDocFromServer(doc(db, 'groups', entry.id));
            if (!group.exists()) throw new Error('Group index is inconsistent. Reload and retry.');
            groups.push({
                id: entry.id, archived: group.data().archived === true,
                owned: (group.data().ownerUid ?? group.data().createdBy) === uid,
            });
        }
        if (index.size < PAGE) return groups;
        if (groups.length >= MAX_GROUPS) throw new Error('Too many groups to verify ownership. Leave some groups first.');
        after = index.docs.at(-1).id;
    }
}

export async function listOwnedGroups(db, uid) {
    return (await scanGroups(db, uid)).filter(group => group.owned).map(group => group.id);
}

/** Permanent removal of the caller's private data; the caller deletes the Auth
 * user afterwards. The account leaves every writable group (departure markers
 * and earlier messages, highlights, progress and reports stay under the UID,
 * without a name). Archived groups are read-only, so those memberships remain
 * and their IDs are returned. Blocked while the account owns a group.
 */
export async function deleteAccountData(db, uid) {
    const groups = await scanGroups(db, uid);
    const owned = groups.filter(group => group.owned).length;
    if (owned) throw new Error(`Transfer ownership of ${owned} group(s) before deleting the account.`);
    const retained = [];
    for (const group of groups) {
        if (group.archived) retained.push(group.id);
        else await leaveGroup(db, group.id, uid);
    }
    const batch = writeBatch(db);
    batch.delete(doc(db, 'users', uid, 'settings', 'reminders'));
    batch.delete(doc(db, 'users', uid));
    await batch.commit();
    return retained;
}

/** Soft, self-reversible deactivation: NOT Firebase Auth deletion or data
 * erasure. Memberships, history and the Auth account are retained. Deactivation
 * adds `deactivatedAt` to the private profile and restoration removes it, so an
 * active profile always has exactly its three fields. Returns whether a write
 * happened; an already-matching state is left untouched.
 */
export async function setAccountDeactivated(db, uid, deactivated) {
    if (deactivated) {
        const owned = await listOwnedGroups(db, uid);
        if (owned.length) throw new Error(`Transfer ownership of ${owned.length} group(s) before deactivating.`);
    }
    const profile = doc(db, 'users', uid);
    return runTransaction(db, async transaction => {
        const snapshot = await transaction.get(profile);
        if (!snapshot.exists()) throw new Error('Private profile required.');
        if (('deactivatedAt' in snapshot.data()) === deactivated) return false;
        transaction.update(profile, {
            deactivatedAt: deactivated ? serverTimestamp() : deleteField(), updatedAt: serverTimestamp(),
        });
        return true;
    });
}
