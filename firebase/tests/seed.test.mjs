import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { getFirestore, connectFirestoreEmulator, doc, getDoc } from 'firebase/firestore';
import { localConfig, firebaseOptions } from '../scripts/local-config.mjs';

test('seeding twice preserves fixture identities and creation timestamps', async () => {
    const settings = localConfig();
    const script = fileURLToPath(new URL('../scripts/seed.mjs', import.meta.url));
    const app = initializeApp(firebaseOptions, 'seed-verification');
    try {
        const auth = getAuth(app);
        connectAuthEmulator(auth, `http://${settings.auth.host}:${settings.auth.port}`, { disableWarnings: true });
        const db = getFirestore(app);
        connectFirestoreEmulator(db, settings.firestore.host, settings.firestore.port);
        const snapshots = [];
        for (let round = 0; round < 2; round++) {
            execFileSync(process.execPath, [script], { stdio: 'pipe', timeout: 20000 });
            const records = [];
            for (const email of ['reader.one@example.test', 'reader.two@example.test']) {
                const { user } = await signInWithEmailAndPassword(auth, email, 'LocalDemo123!');
                const snapshot = await getDoc(doc(db, 'users', user.uid));
                assert.ok(snapshot.exists());
                records.push({ uid: user.uid, createdAt: snapshot.data().createdAt.toMillis() });
                await signOut(auth);
            }
            snapshots.push(records);
        }
        assert.deepEqual(snapshots[0], snapshots[1]);
        assert.notEqual(snapshots[0][0].uid, snapshots[0][1].uid);
    } finally {
        await deleteApp(app);
    }
});