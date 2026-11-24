import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase/app';
import {
    getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signInWithCredential,
    linkWithCredential, signOut, GoogleAuthProvider, OAuthProvider,
} from 'firebase/auth';
import {
    getFirestore, connectFirestoreEmulator, doc, getDocFromServer, setDoc, serverTimestamp,
} from 'firebase/firestore';
import { localConfig, requireEmulators, firebaseOptions } from '../scripts/local-config.mjs';

// Auth-emulator credentials only: unsigned test ID tokens and emulator SMS codes.
// Not real Google/Apple consent, SMS delivery or production provider settings.
const settings = localConfig();
const authUrl = `http://${settings.auth.host}:${settings.auth.port}`;
const apps = [];
function client() {
    const app = initializeApp(firebaseOptions, `providers-${randomUUID()}`);
    apps.push(app);
    const auth = getAuth(app);
    connectAuthEmulator(auth, authUrl, { disableWarnings: true });
    const db = getFirestore(app);
    connectFirestoreEmulator(db, settings.firestore.host, settings.firestore.port);
    return { auth, db };
}
const unique = () => randomUUID().replaceAll('-', '');
const google = (sub, email) => GoogleAuthProvider.credential(JSON.stringify({ sub, email, email_verified: true }));
const apple = (sub, email) => new OAuthProvider('apple.com').credential({ idToken: JSON.stringify({ sub, email }) });
const phoneNumber = () => `+1555${String(Math.floor(Math.random() * 1e7)).padStart(7, '0')}`;
async function identity(method, body) {
    const response = await fetch(`${authUrl}/identitytoolkit.googleapis.com/v1/accounts:${method}?key=${firebaseOptions.apiKey}`, {
        method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
}
async function smsChallenge(number) {
    const sent = await identity('sendVerificationCode', { phoneNumber: number });
    assert.equal(sent.status, 200);
    const { sessionInfo } = sent.body;
    const codes = await (await fetch(`${authUrl}/emulator/v1/projects/${settings.projectId}/verificationCodes`)).json();
    const { code } = codes.verificationCodes.findLast(entry => entry.sessionInfo === sessionInfo);
    return { sessionInfo, code };
}
// The Node SDK build has no PhoneAuthProvider.credential; this is its REST call.
const phoneSignIn = (challenge, idToken) => identity('signInWithPhoneNumber', { ...challenge, ...(idToken ? { idToken } : {}) });
const providers = user => user.providerData.map(info => info.providerId).sort();
const profile = () => ({ displayName: 'Provider QA', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });

test.before(() => requireEmulators(settings));
test.after(() => Promise.all(apps.map(app => deleteApp(app))));

test('Google and Apple credentials open stable, separate UIDs with owner-only profiles', async () => {
    const { auth, db } = client(), other = client();
    const sub = unique();
    const first = (await signInWithCredential(auth, google(sub, `${sub}@example.test`))).user;
    assert.deepEqual(providers(first), ['google.com']);
    await setDoc(doc(db, 'users', first.uid), profile());
    await signOut(auth);
    assert.equal((await signInWithCredential(auth, google(sub, `${sub}@example.test`))).user.uid, first.uid);
    const appleUser = (await signInWithCredential(other.auth, apple(unique(), `${unique()}@example.test`))).user;
    assert.deepEqual(providers(appleUser), ['apple.com']);
    assert.notEqual(appleUser.uid, first.uid);
    await assert.rejects(getDocFromServer(doc(other.db, 'users', first.uid)), /permission/i);
    await assert.rejects(setDoc(doc(other.db, 'users', first.uid), profile()), /permission/i);
    assert.equal((await getDocFromServer(doc(db, 'users', first.uid))).data().displayName, 'Provider QA');
});

test('explicit linking keeps the UID; a credential owned by another account is never merged', async () => {
    const owner = client(), intruder = client();
    const credential = () => google(sub, `${sub}@example.test`), sub = unique();
    const user = (await createUserWithEmailAndPassword(owner.auth, `${unique()}@example.test`, 'LocalDemo123!')).user;
    const linked = (await linkWithCredential(user, credential())).user;
    assert.equal(linked.uid, user.uid);
    assert.deepEqual(providers(linked), ['google.com', 'password']);
    const second = (await createUserWithEmailAndPassword(intruder.auth, `${unique()}@example.test`, 'LocalDemo123!')).user;
    await assert.rejects(linkWithCredential(second, credential()), /credential-already-in-use/);
    assert.deepEqual(providers(intruder.auth.currentUser), ['password']);
    await signOut(intruder.auth);
    assert.equal((await signInWithCredential(intruder.auth, credential())).user.uid, user.uid);
});

test('an Apple sign-in with an email owned by a password account is refused, not merged', async () => {
    const owner = client(), other = client();
    const email = `${unique()}@example.test`;
    const user = (await createUserWithEmailAndPassword(owner.auth, email, 'LocalDemo123!')).user;
    await assert.rejects(signInWithCredential(other.auth, apple(unique(), email)), /account-exists-with-different-credential/);
    assert.equal(other.auth.currentUser, null);
    assert.deepEqual(providers(user), ['password']);
});

test('a Google sign-in with a password account\'s email never creates a second account for that email', async () => {
    const owner = client(), other = client();
    const email = `${unique()}@example.test`;
    const user = (await createUserWithEmailAndPassword(owner.auth, email, 'LocalDemo123!')).user;
    // Firebase treats Google as proof of email ownership: it either opens the
    // existing account or refuses. It must never yield a different UID.
    const outcome = await signInWithCredential(other.auth, google(unique(), email)).then(
        result => result.user.uid, error => error.code);
    assert.ok(outcome === user.uid || outcome === 'auth/account-exists-with-different-credential', outcome);
});

test('phone codes sign in, reject wrong codes and link without changing the UID', async () => {
    const owner = client(), intruder = client();
    const number = phoneNumber();
    const wrong = await smsChallenge(number);
    const refused = await phoneSignIn({ ...wrong, code: wrong.code === '000000' ? '111111' : '000000' });
    assert.equal(refused.status, 400);
    assert.match(refused.body.error.message, /INVALID_CODE/);
    const created = await phoneSignIn(await smsChallenge(number));
    assert.equal(created.status, 200);
    assert.equal(created.body.phoneNumber, number);
    assert.equal((await phoneSignIn(await smsChallenge(number))).body.localId, created.body.localId);

    const linkNumber = phoneNumber();
    const user = (await createUserWithEmailAndPassword(owner.auth, `${unique()}@example.test`, 'LocalDemo123!')).user;
    const linked = await phoneSignIn(await smsChallenge(linkNumber), await user.getIdToken());
    assert.equal(linked.status, 200);
    assert.equal(linked.body.localId, user.uid);
    await user.reload();
    assert.deepEqual(providers(owner.auth.currentUser), ['password', 'phone']);
    const second = (await createUserWithEmailAndPassword(intruder.auth, `${unique()}@example.test`, 'LocalDemo123!')).user;
    const reuse = await phoneSignIn(await smsChallenge(linkNumber), await second.getIdToken());
    assert.notEqual(reuse.body.localId, second.uid);
    await second.reload();
    assert.deepEqual(providers(intruder.auth.currentUser), ['password']);
    assert.equal((await phoneSignIn(await smsChallenge(linkNumber))).body.localId, user.uid);
});
