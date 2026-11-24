import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, getDocFromServer, getDocsFromServer,
    setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp, query, limit,
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole } from '../src/groups.mjs';
import { DEFAULT_REMINDER_SETTINGS, setReminderSettings, getReminderSettings } from '../src/reminder-settings.mjs';

const settings = localConfig();
let environment;
let groupId;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const ref = (db = dbFor('reader'), uid = 'reader') => doc(db, 'users', uid, 'settings', 'reminders');
const data = (overrides = {}) => ({ ...DEFAULT_REMINDER_SETTINGS, updatedAt: serverTimestamp(), ...overrides });

before(async () => {
    environment = await initializeTestEnvironment({
        projectId: settings.projectId,
        firestore: { ...settings.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    });
});
beforeEach(async () => {
    await environment.clearFirestore();
    for (const uid of ['owner', 'lead', 'reader', 'outsider']) {
        await setDoc(doc(dbFor(uid), 'users', uid), {
            displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        });
    }
    groupId = await createGroup(dbFor('owner'), 'owner', { name: 'Preferences' });
    for (const uid of ['lead', 'reader']) await addMember(dbFor('owner'), groupId, uid);
    await setMemberRole(dbFor('owner'), groupId, 'lead', 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('missing settings remain null without auto-create; explicit defaults are off at 09:00 India time', async () => {
    assert.deepEqual(DEFAULT_REMINDER_SETTINGS, {
        readingReminderEnabled: false, dailyVerseEnabled: false,
        reminderHour: 9, reminderMinute: 0, timezone: 'Asia/Kolkata',
    });
    assert.ok(Object.isFrozen(DEFAULT_REMINDER_SETTINGS));
    assert.equal(await getReminderSettings(dbFor('reader'), 'reader'), null);
    assert.equal((await getDocFromServer(ref())).exists(), false);
    await assertSucceeds(setReminderSettings(dbFor('reader'), 'reader'));
    const saved = await getReminderSettings(dbFor('reader'), 'reader');
    assert.deepEqual(Object.keys(saved).sort(), [...Object.keys(DEFAULT_REMINDER_SETTINGS), 'updatedAt'].sort());
    assert.ok(saved.updatedAt instanceof Timestamp);
    const { updatedAt, ...preferences } = saved;
    assert.deepEqual(preferences, DEFAULT_REMINDER_SETTINGS);
});

test('owner can create and replace preferences and toggle both directions without group membership', async () => {
    const db = dbFor('outsider');
    await assertSucceeds(setReminderSettings(db, 'outsider', {
        ...DEFAULT_REMINDER_SETTINGS, readingReminderEnabled: true, dailyVerseEnabled: true,
        reminderHour: 23, reminderMinute: 59,
    }));
    assert.equal((await getReminderSettings(db, 'outsider')).dailyVerseEnabled, true);
    await assertSucceeds(setReminderSettings(db, 'outsider', {
        ...DEFAULT_REMINDER_SETTINGS, reminderHour: 0, reminderMinute: 0,
    }));
    const saved = await getReminderSettings(db, 'outsider');
    assert.equal(saved.readingReminderEnabled, false);
    assert.equal(saved.dailyVerseEnabled, false);
    assert.equal(saved.reminderHour, 0);
});

test('nonowners including group admin/lead and forged claims cannot read, create or update', async () => {
    for (const uid of ['owner', 'lead', 'outsider']) {
        await assertFails(setReminderSettings(dbFor(uid), 'reader'));
    }
    await setReminderSettings(dbFor('reader'), 'reader');
    for (const db of [dbFor('owner'), dbFor('lead'), dbFor('outsider'),
    dbFor('outsider', { admin: true, userId: 'reader', role: 'admin' }), environment.unauthenticatedContext().firestore()]) {
        await assertFails(getReminderSettings(db, 'reader'));
        await assertFails(setDoc(ref(db), data()));
        await assertFails(updateDoc(ref(db), { dailyVerseEnabled: true, updatedAt: serverTimestamp() }));
        await assertFails(deleteDoc(ref(db)));
    }
});

test('unauthenticated create is denied; owner cannot enumerate settings and may delete only their own', async () => {
    await assertFails(setDoc(ref(environment.unauthenticatedContext().firestore()), data()));
    await setReminderSettings(dbFor('reader'), 'reader');
    await assertFails(getDocsFromServer(query(collection(dbFor('reader'), 'users', 'reader', 'settings'), limit(50))));
    await assertFails(getDocsFromServer(query(collectionGroup(dbFor('reader'), 'settings'), limit(50))));
    // Account deletion removes private preferences; nobody else can.
    await assertSucceeds(deleteDoc(ref()));
    assert.equal(await getReminderSettings(dbFor('reader'), 'reader'), null);
});

test('exact schema rejects every missing field and permissions, identity, tokens or schedule extras on create/update', async () => {
    for (const key of Object.keys(data())) {
        const incomplete = data();
        delete incomplete[key];
        await assertFails(setDoc(ref(), incomplete));
    }
    const extras = [{ uid: 'reader' }, { userId: 'reader' }, { role: 'admin' }, { groupId },
    { fcmToken: 'secret' }, { createdAt: serverTimestamp() }, { deadlineHour: 22 },
    { escalationEnabled: true }, { email: 'private' }];
    for (const extra of extras) await assertFails(setDoc(ref(), data(extra)));
    await setReminderSettings(dbFor('reader'), 'reader');
    for (const key of Object.keys(data())) {
        const incomplete = data();
        delete incomplete[key];
        await assertFails(setDoc(ref(), incomplete));
    }
    for (const extra of extras) await assertFails(setDoc(ref(), data(extra)));
});

test('booleans reject strings, numbers, null and containers on create and update', async () => {
    for (const key of ['readingReminderEnabled', 'dailyVerseEnabled']) {
        for (const value of ['true', 'false', 0, 1, null, {}, []]) {
            await assertFails(setDoc(ref(), data({ [key]: value })));
        }
    }
    await setReminderSettings(dbFor('reader'), 'reader');
    for (const key of ['readingReminderEnabled', 'dailyVerseEnabled']) {
        await assertFails(updateDoc(ref(), { [key]: 1, updatedAt: serverTimestamp() }));
    }
});

test('hour/minute require bounded integers; fractional, wrong-type and overflow values fail', async () => {
    for (const [key, maximum] of [['reminderHour', 23], ['reminderMinute', 59]]) {
        for (const value of [-1, maximum + 1, 0.5, '0', null, false, {}, []]) {
            await assertFails(setDoc(ref(), data({ [key]: value })));
        }
    }
    await setReminderSettings(dbFor('reader'), 'reader');
    await assertFails(updateDoc(ref(), { reminderHour: 24, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(), { reminderMinute: 60, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref(), { reminderHour: 0, reminderMinute: 0, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref(), { reminderHour: 23, reminderMinute: 59, updatedAt: serverTimestamp() }));
});

test('only Asia/Kolkata is accepted, including on update; no broad timezone support', async () => {
    for (const timezone of ['UTC', 'Asia/Calcutta', 'America/New_York', '', ' Asia/Kolkata ', null, 1, {}]) {
        await assertFails(setDoc(ref(), data({ timezone })));
    }
    await setReminderSettings(dbFor('reader'), 'reader');
    await assertFails(updateDoc(ref(), { timezone: 'UTC', updatedAt: serverTimestamp() }));
});

test('updatedAt requires server time on create and update; stale or client-clock timestamps fail', async () => {
    for (const updatedAt of [Timestamp.fromMillis(0), Timestamp.fromMillis(4102444800000), null, 'now', 1]) {
        await assertFails(setDoc(ref(), data({ updatedAt })));
    }
    await setReminderSettings(dbFor('reader'), 'reader');
    const original = await getReminderSettings(dbFor('reader'), 'reader');
    await assertFails(updateDoc(ref(), { readingReminderEnabled: true }));
    await assertFails(setDoc(ref(), { ...original, dailyVerseEnabled: true }));
    await assertFails(updateDoc(ref(), { updatedAt: Timestamp.fromMillis(0) }));
    await assertSucceeds(updateDoc(ref(), { readingReminderEnabled: true, updatedAt: serverTimestamp() }));
    assert.ok((await getReminderSettings(dbFor('reader'), 'reader')).updatedAt.toMillis() >= original.updatedAt.toMillis());
});

test('preferences grant no group, membership, parent profile or nested settings privileges', async () => {
    const db = dbFor('outsider');
    await setReminderSettings(db, 'outsider', { ...DEFAULT_REMINDER_SETTINGS, readingReminderEnabled: true });
    await assertFails(getDocFromServer(doc(db, 'groups', groupId)));
    await assertFails(setDoc(doc(db, 'groups', groupId, 'members', 'outsider'), {
        userId: 'outsider', role: 'admin', joinedAt: serverTimestamp(),
    }));
    await assertFails(getDocFromServer(doc(db, 'users', 'reader')));
    for (const path of [`groups/${groupId}/settings/reminders`, 'users/outsider/settings/other',
        'users/outsider/settings/reminders/members/outsider', 'settings/reminders', 'users/outsider/reminders/prefs']) {
        await assertFails(setDoc(doc(db, path), data()));
        await assertFails(getDocFromServer(doc(db, path)));
    }
});

test('personal settings do not require a profile and never modify existing private profile data', async () => {
    const original = (await getDocFromServer(doc(dbFor('reader'), 'users', 'reader'))).data();
    await setReminderSettings(dbFor('reader'), 'reader');
    assert.deepEqual((await getDocFromServer(doc(dbFor('reader'), 'users', 'reader'))).data(), original);
    await assertSucceeds(setReminderSettings(dbFor('profileless'), 'profileless'));
    assert.equal((await getDocFromServer(doc(dbFor('profileless'), 'users', 'profileless'))).exists(), false);
    assert.ok(await getReminderSettings(dbFor('profileless'), 'profileless'));
});

test('helpers reject malformed schemas, booleans, bounds, timezone and UID path injection', async () => {
    const db = dbFor('reader');
    for (const value of [null, 1, [], {}, { ...DEFAULT_REMINDER_SETTINGS, extra: true },
        { readingReminderEnabled: true }]) {
        await assert.rejects(setReminderSettings(db, 'reader', value), /exactly/);
    }
    for (const key of Object.keys(DEFAULT_REMINDER_SETTINGS)) {
        const incomplete = { ...DEFAULT_REMINDER_SETTINGS };
        delete incomplete[key];
        await assert.rejects(setReminderSettings(db, 'reader', incomplete), /exactly/);
    }
    for (const key of ['readingReminderEnabled', 'dailyVerseEnabled']) {
        await assert.rejects(setReminderSettings(db, 'reader', { ...DEFAULT_REMINDER_SETTINGS, [key]: 1 }), /booleans/);
    }
    for (const [key, value] of [['reminderHour', -1], ['reminderHour', 24], ['reminderHour', 1.5],
    ['reminderMinute', -1], ['reminderMinute', 60], ['reminderMinute', '0']]) {
        await assert.rejects(setReminderSettings(db, 'reader', { ...DEFAULT_REMINDER_SETTINGS, [key]: value }), /integers/);
    }
    await assert.rejects(setReminderSettings(db, 'reader', { ...DEFAULT_REMINDER_SETTINGS, timezone: 'UTC' }), /Asia\/Kolkata/);
    for (const uid of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501)]) {
        await assert.rejects(setReminderSettings(db, uid), /path segment/);
        await assert.rejects(getReminderSettings(db, uid), /path segment/);
    }
});