import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase/app';
import {
    getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
    signInWithEmailAndPassword, signOut, deleteUser,
} from 'firebase/auth';
import { localConfig, requireEmulators, firebaseOptions } from '../scripts/local-config.mjs';

test('Auth emulator supports registration, logout, login and deletion', async () => {
    const settings = localConfig();
    await requireEmulators(settings);
    const app = initializeApp(firebaseOptions, `auth-smoke-${randomUUID()}`);
    try {
        const auth = getAuth(app);
        connectAuthEmulator(auth, `http://${settings.auth.host}:${settings.auth.port}`, { disableWarnings: true });
        const email = `smoke-${randomUUID()}@example.test`;
        const credential = await createUserWithEmailAndPassword(auth, email, 'LocalDemo123!');
        const uid = credential.user.uid;
        assert.ok(uid);
        await signOut(auth);
        assert.equal(auth.currentUser, null);
        await assert.rejects(signInWithEmailAndPassword(auth, email, 'WrongPassword!'));
        const signedIn = await signInWithEmailAndPassword(auth, email, 'LocalDemo123!');
        assert.equal(signedIn.user.uid, uid);
        await deleteUser(signedIn.user);
        assert.equal(auth.currentUser, null);
        await assert.rejects(signInWithEmailAndPassword(auth, email, 'LocalDemo123!'));
    } finally {
        await deleteApp(app);
    }
});