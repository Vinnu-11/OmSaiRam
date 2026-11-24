import {
    doc, getDoc, setDoc, updateDoc, writeBatch, serverTimestamp, Timestamp,
} from 'firebase/firestore';

const DAY = 24 * 60 * 60 * 1000;
const TOKEN_PATTERN = /^([a-f0-9]{64}|[A-HJ-NP-Z2-9]{8})$/;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function validateToken(token) {
    if (typeof token !== 'string' || !TOKEN_PATTERN.test(token)) {
        throw new Error('An invitation token must be 64 lowercase hexadecimal characters or an 8-character code.');
    }
}

/** 8 characters people can type; 32 symbols, so 40 bits. CSPRNG only. */
export function generateInviteCode() {
    const bytes = globalThis.crypto.getRandomValues(new Uint8Array(8));
    return Array.from(bytes, byte => CODE_ALPHABET[byte % 32]).join('');
}

export function generateInviteToken() {
    // 256 bits, CSPRNG only. No Math.random fallback.
    const bytes = globalThis.crypto.getRandomValues(new Uint8Array(32));
    return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

export async function createInvitation(db, groupId, uid, { lifetimeMs = DAY, code = false } = {}) {
    if (!Number.isSafeInteger(lifetimeMs) || lifetimeMs <= 0 || lifetimeMs > 7 * DAY) {
        throw new Error('Invitation lifetime must be positive and at most seven days.');
    }
    const token = code ? generateInviteCode() : generateInviteToken();
    await setDoc(doc(db, 'groupInvites', token), {
        groupId,
        createdBy: uid,
        createdAt: serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + lifetimeMs),
        active: true,
    });
    // Caller can display/share the token. Never log bearer tokens automatically.
    return token;
}

export async function revokeInvitation(db, token) {
    validateToken(token);
    await updateDoc(doc(db, 'groupInvites', token), { active: false });
}

export async function joinWithInvitation(db, uid, token) {
    validateToken(token);
    const snapshot = await getDoc(doc(db, 'groupInvites', token));
    if (!snapshot.exists()) throw new Error('Invitation unavailable.');
    const invite = snapshot.data();
    if (!invite.active || invite.expiresAt.toMillis() <= Date.now()) {
        throw new Error('Invitation unavailable.');
    }
    // Client checks aid UX only: rules independently validate the post-write
    // invitation and server time at commit, including expiry/revocation races.
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups', invite.groupId, 'members', uid), {
        userId: uid, role: 'member', joinedAt: serverTimestamp(),
    });
    batch.set(doc(db, 'users', uid, 'groups', invite.groupId), {
        groupId: invite.groupId, joinedAt: serverTimestamp(), inviteToken: token,
    });
    await batch.commit();
    return invite.groupId;
}