import { doc, runTransaction, serverTimestamp } from 'firebase/firestore';

function segment(value) {
    if (typeof value !== 'string' || !value || value.includes('/')
        || value === '.' || value === '..' || /^__.*__$/.test(value)
        || new TextEncoder().encode(value).length > 1500) {
        throw new Error('IDs must be valid single Firestore path segments.');
    }
    return value;
}

/** Local reference only. Retention policy, NOT account deletion or
 * data erasure: assignments/status/messages/highlights remain unchanged and
 * readable by remaining members. Previously downloaded data cannot be erased.
 * Rejoining requires explicit admin restoration with immutable before-images
 * and a fresh joinedAt boundary. Old assignment progress stays history-only.
 * Historical cascade deletion needs a trusted worker, not this client helper.
 *
 * One target per transaction, up to 5 writes with history/display, no chunking.
 * Group, actor, target and optional display reads precede every write and are
 * revalidated on transaction retry. Never read another user's private index:
 * its known-path delete is authorized ONLY by the coordinated departure rules.
 * Missing/inconsistent membership-index pairs fail closed at commit. Supplied
 * actor UID is untrusted: rules independently bind removedBy to auth and use
 * prewrite memberships/roles. No postwrite role grants departure authority.
 */
async function depart(db, groupId, actorUid, targetUid, reason) {
    [groupId, actorUid, targetUid].forEach(segment);
    const groupRef = doc(db, 'groups', groupId);
    const actorRef = doc(db, 'groups', groupId, 'members', actorUid);
    const memberRef = doc(db, 'groups', groupId, 'members', targetUid);
    const profileRef = doc(db, 'groups', groupId, 'memberProfiles', targetUid);
    const indexRef = doc(db, 'users', targetUid, 'groups', groupId);
    const departureRef = doc(db, 'groups', groupId, 'departures', targetUid);
    await runTransaction(db, async transaction => {
        const group = await transaction.get(groupRef);
        const actor = await transaction.get(actorRef);
        const member = actorUid === targetUid ? actor : await transaction.get(memberRef);
        if (!group.exists() || !actor.exists() || !member.exists()) {
            throw new Error('Group, actor and target must be current members.');
        }
        if ((group.data().ownerUid ?? group.data().createdBy) === targetUid) throw new Error('The group owner cannot depart.');
        if (reason === 'left') {
            if (actorUid !== targetUid || !['member', 'group_lead'].includes(member.data().role)) {
                throw new Error('Only nonadmin members may leave themselves.');
            }
        } else if (actorUid === targetUid || !(actor.data().role === 'admin'
            || (actor.data().role === 'group_lead' && member.data().role === 'member'))) {
            throw new Error('Only admins or leads removing ordinary members may remove others.');
        }
        const profile = await transaction.get(profileRef);
        const departure = await transaction.get(departureRef);
        const previous = departure.exists() ? departure.data() : null;
        const revision = previous?.revision ?? 0;
        if (previous && (previous.restored !== true || !Number.isSafeInteger(revision) || revision >= 2147483647)) {
            throw new Error('Membership lifecycle changed. Reload before departure.');
        }
        const history = previous ? doc(departureRef, 'versions', String(revision)) : null;
        if (history && (await transaction.get(history)).exists()) throw new Error('Membership version already retained.');
        if (history) transaction.set(history, previous);
        transaction.set(departureRef, {
            userId: targetUid, removedBy: actorUid, removedAt: serverTimestamp(), reason,
            ...(previous ? { restored: false, revision: revision + 1, changedBy: actorUid, changedAt: serverTimestamp() } : {}),
        });
        transaction.delete(memberRef);
        transaction.delete(indexRef);
        if (profile.exists()) transaction.delete(profileRef);
    });
    return targetUid;
}

export async function leaveGroup(db, groupId, uid) {
    return depart(db, groupId, uid, uid, 'left');
}

/** Admin: any noncreator. Lead: ordinary member only. No self-removal API. */
export async function removeMember(db, groupId, actorUid, targetUid) {
    return depart(db, groupId, actorUid, targetUid, 'removed');
}

export async function restoreMember(db, groupId, actorUid, targetUid, expectedRevision) {
    [groupId, actorUid, targetUid].forEach(segment);
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0 || expectedRevision >= 2147483647) throw new Error('Confirmed membership version required.');
    const root = doc(db, 'groups', groupId), member = doc(root, 'members', targetUid);
    const departure = doc(root, 'departures', targetUid), history = doc(departure, 'versions', String(expectedRevision));
    await runTransaction(db, async transaction => {
        const group = await transaction.get(root), actor = await transaction.get(doc(root, 'members', actorUid));
        if (!group.exists() || group.data().archived === true || !actor.exists() || actor.data().role !== 'admin') {
            throw new Error('An active group and current admin are required.');
        }
        const current = await transaction.get(member), marker = await transaction.get(departure);
        if (current.exists() || !marker.exists()) throw new Error('A departed member is required.');
        const previous = marker.data();
        if ((previous.revision ?? 0) !== expectedRevision || (previous.restored ?? false)) throw new Error('Membership version changed. Reload before restoring.');
        if ((await transaction.get(history)).exists()) throw new Error('Membership version already retained.');
        transaction.set(history, previous);
        transaction.update(departure, { restored: true, revision: expectedRevision + 1, changedBy: actorUid, changedAt: serverTimestamp() });
        transaction.set(member, { userId: targetUid, role: 'member', joinedAt: serverTimestamp() });
        transaction.set(doc(db, 'users', targetUid, 'groups', groupId), { groupId, joinedAt: serverTimestamp() });
    });
}