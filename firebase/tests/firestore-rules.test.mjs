import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import {
    initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
    doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
    serverTimestamp, Timestamp,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';

const settings = localConfig();
let environment;
const profile = () => ({
    displayName: 'Local Reader', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
});
const ownDb = () => environment.authenticatedContext('reader-one').firestore();
before(async () => {
    environment = await initializeTestEnvironment({
        projectId: settings.projectId,
        firestore: {
            ...settings.firestore,
            rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
        },
    });
});
beforeEach(async () => { await environment.clearFirestore(); });
after(async () => { await environment?.cleanup(); });

test('owner can create, read and update their private profile', async () => {
    const reference = doc(ownDb(), 'users/reader-one');
    await assertSucceeds(setDoc(reference, profile()));
    await assertSucceeds(getDoc(reference));
    await assertSucceeds(updateDoc(reference, {
        displayName: 'Updated Reader', updatedAt: serverTimestamp(),
    }));
});

test('unauthenticated access is denied', async () => {
    const db = environment.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users/reader-one')));
    await assertFails(setDoc(doc(db, 'users/reader-one'), profile()));
});

test('another user cannot read or write a profile', async () => {
    await setDoc(doc(ownDb(), 'users/reader-one'), profile());
    const reference = doc(environment.authenticatedContext('reader-two').firestore(), 'users/reader-one');
    await assertFails(getDoc(reference));
    await assertFails(setDoc(reference, profile()));
    await assertFails(deleteDoc(reference));
});

test('users cannot enumerate profiles; only the owner may delete their own', async () => {
    const db = ownDb();
    const reference = doc(db, 'users/reader-one');
    await setDoc(reference, profile());
    await assertFails(getDocs(collection(db, 'users')));
    await assertSucceeds(deleteDoc(reference));
});

test('clients cannot introduce roles or private identity fields', async () => {
    const reference = doc(ownDb(), 'users/reader-one');
    await assertFails(setDoc(reference, { ...profile(), role: 'admin' }));
    await assertFails(setDoc(reference, { ...profile(), email: 'someone@example.test' }));
    await setDoc(reference, profile());
    await assertFails(updateDoc(reference, { isAdmin: true, updatedAt: serverTimestamp() }));
});

test('profile name must be a nonblank bounded string', async () => {
    const reference = doc(ownDb(), 'users/reader-one');
    for (const displayName of ['', '   ', 'x'.repeat(101), 42, null]) {
        await assertFails(setDoc(reference, { ...profile(), displayName }));
    }
});

test('required fields cannot be omitted', async () => {
    const reference = doc(ownDb(), 'users/reader-one');
    for (const key of ['displayName', 'createdAt', 'updatedAt']) {
        const data = profile();
        delete data[key];
        await assertFails(setDoc(reference, data));
    }
});

test('timestamps must be server-generated and creation time is immutable', async () => {
    const reference = doc(ownDb(), 'users/reader-one');
    await assertFails(setDoc(reference, { ...profile(), createdAt: Timestamp.fromMillis(0) }));
    await assertFails(setDoc(reference, { ...profile(), updatedAt: Timestamp.fromMillis(0) }));
    await setDoc(reference, profile());
    await assertFails(updateDoc(reference, {
        createdAt: Timestamp.fromMillis(0), updatedAt: serverTimestamp(),
    }));
});

test('unmigrated collections and nested documents deny all client access', async () => {
    const db = ownDb();
    for (const path of [
        'groups/example', 'groups/example/members/reader-one', 'assignments/example',
        'progress/example', 'messages/example', 'users/reader-one/private/example',
    ]) {
        await assertFails(getDoc(doc(db, path)));
        await assertFails(setDoc(doc(db, path), { value: 'blocked' }));
    }
});