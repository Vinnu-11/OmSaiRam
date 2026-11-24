import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, collectionGroup, query, limit, getDocFromServer, getDocsFromServer,
    setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp, writeBatch
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole } from '../src/groups.mjs';
import {
    DEFAULT_GROUP_REMINDER_SCHEDULE as defaults, validateGroupReminderSchedule,
    getGroupReminderSchedule, saveGroupReminderSchedule
} from '../src/group-reminders.mjs';
const settings = localConfig();
let environment, groupId, owner, lead, member, outsider;
const dbFor = (uid, claims = {}) => environment.authenticatedContext(uid, claims).firestore();
const reference = (db, id = groupId) => doc(db, 'groups', id, 'settings', 'notificationSchedule');
const data = (uid = owner, changes = {}) => ({
    ...defaults, groupId, revision: 1,
    createdBy: uid, createdAt: serverTimestamp(), updatedBy: uid, updatedAt: serverTimestamp(), ...changes
});
before(async () => {
    environment = await initializeTestEnvironment({
        projectId: settings.projectId,
        firestore: { ...settings.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') }
    });
});
beforeEach(async () => {
    const prefix = `reminder-qa-${randomUUID()}`;
    [owner, lead, member, outsider] = ['owner', 'lead', 'member', 'outsider'].map(role => `${prefix}-${role}`);
    for (const uid of [owner, lead, member, outsider]) await setDoc(doc(dbFor(uid), 'users', uid), {
        displayName: 'Reminder QA', createdAt: serverTimestamp(), updatedAt: serverTimestamp()
    });
    groupId = await createGroup(dbFor(owner), owner, { name: 'Reminder QA' });
    for (const uid of [lead, member]) await addMember(dbFor(owner), groupId, uid);
    await setMemberRole(dbFor(owner), groupId, lead, 'group_lead');
});
after(async () => { await environment?.cleanup(); });

test('missing stays absent; members read and actual admin/lead create/update with immutable creation audit', async () => {
    assert.equal(await getGroupReminderSchedule(dbFor(member), groupId), null);
    await saveGroupReminderSchedule(dbFor(owner), groupId, owner, defaults);
    const first = await getGroupReminderSchedule(dbFor(member), groupId);
    assert.equal(first.revision, 1); assert.equal(first.timezone, 'Asia/Kolkata');
    assert.ok(first.createdAt instanceof Timestamp); assert.ok(Object.isFrozen(first));
    await saveGroupReminderSchedule(dbFor(lead), groupId, lead, { ...defaults, escalationEnabled: false }, 1);
    const second = await getGroupReminderSchedule(dbFor(member), groupId);
    assert.equal(second.revision, 2); assert.equal(second.createdBy, owner); assert.equal(second.updatedBy, lead);
    assert.ok(second.createdAt.isEqual(first.createdAt)); assert.equal(second.escalationEnabled, false);
});
test('nonmembers, anonymous and forged claims cannot read/write; members cannot write', async () => {
    for (const db of [dbFor(outsider), dbFor(outsider, { admin: true, role: 'admin' }), environment.unauthenticatedContext().firestore()]) {
        await assertFails(getGroupReminderSchedule(db, groupId)); await assertFails(setDoc(reference(db), data()));
    }
    await assertFails(setDoc(reference(dbFor(member, { admin: true })), data(member)));
    await assert.rejects(saveGroupReminderSchedule(dbFor(member), groupId, member, defaults), /membership/);
    await assertFails(saveGroupReminderSchedule(dbFor(member), groupId, owner, defaults));
});
test('every missing/extra field, raw numeric bounds and invalid types fail on create and update', async () => {
    const db = dbFor(owner);
    for (const key of Object.keys(data())) { const raw = data(); delete raw[key]; await assertFails(setDoc(reference(db), raw)); }
    for (const change of [{ fcmToken: 'no' }, { timezone: 'UTC' }, { escalationEnabled: 1 }, { revision: 2 },
    { groupId: 'other' }, { createdBy: member }, { updatedBy: lead }, { createdAt: Timestamp.fromMillis(0) }, { updatedAt: Timestamp.fromMillis(0) }]) {
        await assertFails(setDoc(reference(db), data(owner, change)));
    }
    for (const [field, maximum] of [['initialDay', 6], ['deadlineDay', 6], ['initialHour', 23],
    ['deadlineHour', 23], ['initialMinute', 59], ['deadlineMinute', 59]]) {
        for (const value of [-1, maximum + 1, 0.5, '0', null, false]) await assertFails(setDoc(reference(db), data(owner, { [field]: value })));
    }
    await saveGroupReminderSchedule(db, groupId, owner, defaults);
    const first = await getGroupReminderSchedule(db, groupId);
    for (const change of [{ revision: 1 }, { revision: 3 }, { revision: 2147483648 }, { createdBy: lead },
    { createdAt: serverTimestamp() }, { updatedBy: lead }, { updatedAt: Timestamp.fromMillis(0) },
    { timezone: 'UTC' }, { escalationEnabled: 'true' }, { initialMinute: 60 }, { fcmToken: 'no' }]) {
        await assertFails(setDoc(reference(db), { ...first, revision: 2, updatedAt: serverTimestamp(), ...change }));
    }
    await assertFails(updateDoc(reference(db), { revision: 2 }));
});
test('ordering, unknown paths, delete and collection/global enumeration fail closed', async () => {
    const db = dbFor(owner);
    for (const change of [{ deadlineDay: 0, deadlineHour: 9 }, { deadlineDay: 0, deadlineHour: 8 },
    { initialDay: 6, initialHour: 23, deadlineDay: 0 }]) await assertFails(setDoc(reference(db), data(owner, change)));
    await saveGroupReminderSchedule(db, groupId, owner, defaults);
    await assertFails(deleteDoc(reference(db)));
    await assertFails(getDocsFromServer(query(collection(db, 'groups', groupId, 'settings'), limit(10))));
    await assertFails(getDocsFromServer(query(collectionGroup(db, 'settings'), limit(10))));
    for (const path of [`groups/${groupId}/settings/reminders`, `groups/${groupId}/settings/other`,
    `groups/${groupId}/settings/notificationSchedule/nested/x`, 'settings/notificationSchedule']) {
        await assertFails(setDoc(doc(db, path), data())); await assertFails(getDocFromServer(doc(db, path)));
    }
    await assertFails(getDocFromServer(doc(db, 'users', member)));
});
test('stale create/update and demoted editor cannot overwrite current intent', async () => {
    const db = dbFor(owner);
    await saveGroupReminderSchedule(db, groupId, owner, defaults);
    await assert.rejects(saveGroupReminderSchedule(db, groupId, owner, defaults, 0), /changed/);
    await saveGroupReminderSchedule(dbFor(lead), groupId, lead, { ...defaults, initialHour: 10 }, 1);
    await assert.rejects(saveGroupReminderSchedule(db, groupId, owner, defaults, 1), /changed/);
    await setMemberRole(db, groupId, lead, 'member');
    await assert.rejects(saveGroupReminderSchedule(dbFor(lead), groupId, lead, defaults, 2), /membership/);
    assert.equal((await getGroupReminderSchedule(db, groupId)).initialHour, 10);
});
test('same-batch privilege bootstrap and orphan memberships grant no schedule access', async () => {
    const db = dbFor(member); const batch = writeBatch(db);
    batch.update(doc(db, 'groups', groupId, 'members', member), { role: 'group_lead' });
    batch.set(reference(db), data(member)); await assertFails(batch.commit());
    const orphan = `orphan-${randomUUID()}`;
    await environment.withSecurityRulesDisabled(async context => {
        await setDoc(doc(context.firestore(), 'groups', orphan, 'members', owner), { userId: owner, role: 'admin', joinedAt: Timestamp.now() });
    });
    await assertFails(getDocFromServer(reference(dbFor(owner), orphan)));
    await assertFails(setDoc(reference(dbFor(owner), orphan), data(owner, { groupId: orphan })));
});
test('departed member loses reads and writes while the schedule is retained', async () => {
    await saveGroupReminderSchedule(dbFor(owner), groupId, owner, defaults);
    const db = dbFor(member); const batch = writeBatch(db);
    batch.set(doc(db, 'groups', groupId, 'departures', member), { userId: member, removedBy: member, removedAt: serverTimestamp(), reason: 'left' });
    batch.delete(doc(db, 'groups', groupId, 'members', member)); batch.delete(doc(db, 'users', member, 'groups', groupId));
    await assertSucceeds(batch.commit()); await assertFails(getGroupReminderSchedule(db, groupId));
    await assertFails(setDoc(reference(db), data(member)));
    assert.equal((await getGroupReminderSchedule(dbFor(owner), groupId)).revision, 1);
});
test('helpers reject malformed inputs before reads and freeze caller drafts', async () => {
    for (const value of [null, [], {}, { ...defaults, extra: 1 }, { ...defaults, initialHour: 24 }, { ...defaults, timezone: 'UTC' }]) {
        assert.throws(() => validateGroupReminderSchedule(value));
    }
    const draft = validateGroupReminderSchedule(defaults); assert.ok(Object.isFrozen(draft));
    for (const bad of ['', 'x/y', '.', '..', '__reserved__', 'x'.repeat(1501)]) {
        await assert.rejects(getGroupReminderSchedule(dbFor(owner), bad), /segment/);
    }
    await assert.rejects(saveGroupReminderSchedule(dbFor(owner), groupId, owner, defaults, -1), /revision/);
});