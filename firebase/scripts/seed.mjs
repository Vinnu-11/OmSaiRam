import { initializeApp, deleteApp } from 'firebase/app';
import {
    getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
    signInWithEmailAndPassword, signOut,
} from 'firebase/auth';
import {
    getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc,
    updateDoc, serverTimestamp,
} from 'firebase/firestore';
import { localConfig, requireEmulators, firebaseOptions } from './local-config.mjs';

const settings = localConfig();
await requireEmulators(settings);
const app = initializeApp(firebaseOptions, 'local-seed');
const auth = getAuth(app);
connectAuthEmulator(auth, `http://${settings.auth.host}:${settings.auth.port}`, { disableWarnings: true });
const db = getFirestore(app);
connectFirestoreEmulator(db, settings.firestore.host, settings.firestore.port);

// Public, disposable emulator credentials only; never use in a real project.
const fixtures = [
    { email: 'reader.one@example.test', displayName: 'Local Reader One' },
    { email: 'reader.two@example.test', displayName: 'Local Reader Two' },
];
try {
    for (const fixture of fixtures) {
        let credential;
        try {
            credential = await createUserWithEmailAndPassword(auth, fixture.email, 'LocalDemo123!');
        } catch (error) {
            if (error.code !== 'auth/email-already-in-use') throw error;
            credential = await signInWithEmailAndPassword(auth, fixture.email, 'LocalDemo123!');
        }
        const reference = doc(db, 'users', credential.user.uid);
        if ((await getDoc(reference)).exists()) {
            await updateDoc(reference, { displayName: fixture.displayName, updatedAt: serverTimestamp() });
        } else {
            await setDoc(reference, {
                displayName: fixture.displayName,
                createdAt: serverTimestamp(),
                updatedAt: serverTimestamp(),
            });
        }
        console.log(`Seeded local profile: ${fixture.email}`);
        await signOut(auth);
    }
} finally {
    await deleteApp(app);
}