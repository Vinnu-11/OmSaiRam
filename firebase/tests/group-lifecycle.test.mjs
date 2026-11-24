import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
    doc, collection, query, limit, getDocFromServer, getDocsFromServer, setDoc,
    updateDoc, deleteDoc, writeBatch, serverTimestamp, Timestamp
} from 'firebase/firestore';
import { localConfig } from '../scripts/local-config.mjs';
import { createGroup, addMember, setMemberRole } from '../src/groups.mjs';
import { DEFAULT_GROUP_REMINDER_SCHEDULE, saveGroupReminderSchedule } from '../src/group-reminders.mjs';
import { transitionAssignment, updateReadingProgress } from '../src/assignments.mjs';
import { removeMember, restoreMember, leaveGroup } from '../src/membership-lifecycle.mjs';

const config = localConfig();
let environment, groupId, owner, lead, member, outsider, token;
const connections = new Map();
const db = uid => {
    if (!connections.has(uid)) connections.set(uid,
        uid ? environment.authenticatedContext(uid).firestore() : environment.unauthenticatedContext().firestore());
    return connections.get(uid);
};
const group = connection => doc(connection, 'groups', groupId);
const change = (archived, revision, actor = owner) => ({
    archived, lifecycleRevision: revision,
    lifecycleChangedBy: actor, lifecycleChangedAt: serverTimestamp(), updatedAt: serverTimestamp()
});
const message = uid => ({ senderUid: uid, text: 'Archive QA', createdAt: serverTimestamp() });
const assignment = () => ({
    groupId, userId: member, weekNumber: 1, unitKey: '1', chapterStart: 1,
    chapterEnd: 1, scheduledDate: null, createdBy: owner, createdAt: serverTimestamp(), status: 'not_started', progressUpdatedAt: serverTimestamp()
});
before(async () => {
    environment = await initializeTestEnvironment({
        projectId: config.projectId,
        firestore: { ...config.firestore, rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') }
    });
});
beforeEach(async () => {
    [owner, lead, member, outsider] = ['owner', 'lead', 'member', 'outsider'].map(role => `archive-qa-${randomUUID()}-${role}`);
    for (const uid of [owner, lead, member, outsider]) await setDoc(doc(db(uid), 'users', uid), {
        displayName: 'Archive QA', createdAt: serverTimestamp(), updatedAt: serverTimestamp()
    });
    groupId = await createGroup(db(owner), owner, { name: 'Archive QA' });
    await addMember(db(owner), groupId, lead); await addMember(db(owner), groupId, member);
    await setMemberRole(db(owner), groupId, lead, 'group_lead');
    await setDoc(doc(db(owner), 'groups', groupId, 'messages', 'retained'), message(owner));
    await setDoc(doc(db(owner), 'groups', groupId, 'readingWeeks', '1', 'members', member, 'assignments', '1'), assignment());
    await saveGroupReminderSchedule(db(owner), groupId, owner, DEFAULT_GROUP_REMINDER_SCHEDULE);
    token = randomUUID().replaceAll('-', '') + randomUUID().replaceAll('-', '');
    await setDoc(doc(db(owner), 'groupInvites', token), {
        groupId, createdBy: owner, createdAt: serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + 3600000), active: true
    });
});
after(async () => { await environment?.cleanup(); });

function handover(connection, from, to, revision, patch = {}) {
    const batch = writeBatch(connection);
    batch.update(group(connection), { ownerUid: to, ownershipRevision: revision, ownershipChangedBy: from,
        ownershipChangedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...patch });
    batch.update(doc(connection, 'groups', groupId, 'members', from), { role: 'group_lead' });
    batch.update(doc(connection, 'groups', groupId, 'members', to), { role: 'admin' });
    batch.set(doc(connection, 'groups', groupId, 'ownershipChanges', String(revision)), {
        groupId, fromOwner: from, toOwner: to, revision, changedBy: from, changedAt: serverTimestamp() });
    return batch.commit();
}
test('ownership transfer preserves creator and history; only the successor remains protected', async () => {
    await handover(db(owner), owner, member, 1);
    assert.equal((await getDocFromServer(group(db(member)))).data().createdBy, owner);
    assert.equal((await getDocFromServer(group(db(member)))).data().ownerUid, member);
    assert.equal((await getDocFromServer(doc(db(owner), 'groups', groupId, 'members', owner))).data().role, 'group_lead');
    await assertFails(updateDoc(doc(db(member), 'groups', groupId, 'members', member), { role: 'member' }));
    await assert.rejects(removeMember(db(lead), groupId, lead, member), /owner/);
    await assertSucceeds(removeMember(db(member), groupId, member, owner));
    await handover(db(member), member, lead, 2);
    await assertFails(updateDoc(doc(db(lead), 'groups', groupId, 'ownershipChanges', '1'), { toOwner: lead }));
    await assertFails(deleteDoc(doc(db(lead), 'groups', groupId, 'ownershipChanges', '1')));
});
test('ownership transfer rejects raw partial, stale, spoofed, archived and nonowner changes', async () => {
    await assertFails(updateDoc(group(db(owner)), { ownerUid: member, ownershipRevision: 1,
        ownershipChangedBy: owner, ownershipChangedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(handover(db(lead), lead, member, 1));
    for (const patch of [{ ownershipChangedBy: lead }, { ownershipRevision: 2 }, { createdBy: member },
      { ownershipChangedAt: Timestamp.fromMillis(0) }, { archived: true }]) {
      await assertFails(handover(db(owner), owner, member, 1, patch));
    }
    await updateDoc(group(db(owner)), change(true, 1));
    await assertFails(handover(db(owner), owner, member, 1));
    await updateDoc(group(db(owner)), change(false, 2));
    await assertSucceeds(handover(db(owner), owner, member, 1));
    await assertFails(handover(db(owner), owner, lead, 2));
});
test('ownership handover requires all four documents and cannot rewrite membership join history', async () => {
        const omissions = ['actor', 'target', 'audit'];
        for (const omitted of omissions) {
            const connection = db(owner), batch = writeBatch(connection);
            batch.update(group(connection), { ownerUid: member, ownershipRevision: 1, ownershipChangedBy: owner,
                ownershipChangedAt: serverTimestamp(), updatedAt: serverTimestamp() });
            if (omitted !== 'actor') batch.update(doc(connection, 'groups', groupId, 'members', owner), { role: 'group_lead' });
            if (omitted !== 'target') batch.update(doc(connection, 'groups', groupId, 'members', member), { role: 'admin' });
            if (omitted !== 'audit') batch.set(doc(connection, 'groups', groupId, 'ownershipChanges', '1'), {
                groupId, fromOwner: owner, toOwner: member, revision: 1, changedBy: owner, changedAt: serverTimestamp() });
            await assertFails(batch.commit());
        }
        await assertFails(handover(db(owner), owner, outsider, 1));
        await handover(db(owner), owner, member, 1);
        await assertFails(updateDoc(doc(db(member), 'groups', groupId, 'members', owner), { joinedAt: serverTimestamp() }));
        await assertFails(getDocFromServer(doc(db(outsider), 'groups', groupId, 'ownershipChanges', '1')));
});

const work = (connection, uid = member) => doc(connection, 'groups', groupId, 'readingWeeks', '1', 'members', uid, 'assignments', '1');
const transition = async (archived, options = {}, actor = owner) => {
    const previous = (await getDocFromServer(work(db(actor)))).data();
    return transitionAssignment(db(actor), actor, {
        groupId, userId: member, weekNumber: 1, chapterNumber: 1,
        expectedRevision: previous.revision ?? 0, expectedProgressUpdatedAt: previous.progressUpdatedAt, archived, ...options
    });
};
test('restoration retains departure versions and fresh membership cannot reactivate old progress', async () => {
    await updateReadingProgress(db(member), groupId, member, 1, 1, 'completed');
    const original = (await getDocFromServer(work(db(owner)))).data();
    await removeMember(db(owner), groupId, owner, member);
    const marker = doc(db(owner), 'groups', groupId, 'departures', member);
    const before = (await getDocFromServer(marker)).data();
    await restoreMember(db(owner), groupId, owner, member, 0);
    assert.deepEqual((await getDocFromServer(doc(marker, 'versions', '0'))).data(), before);
    assert.deepEqual((await getDocFromServer(work(db(member)))).data(), original);
    await assertFails(updateReadingProgress(db(member), groupId, member, 1, 1, 'not_started'));
    await transition(true); await transition(false);
    await assertSucceeds(updateReadingProgress(db(member), groupId, member, 1, 1, 'in_progress'));
    await leaveGroup(db(member), groupId, member);
    assert.equal((await getDocFromServer(marker)).data().revision, 2);
    await restoreMember(db(owner), groupId, owner, member, 2);
    assert.equal((await getDocFromServer(marker)).data().revision, 3);
    assert.equal((await getDocFromServer(doc(marker, 'versions', '1'))).data().restored, true);
    await assertFails(updateReadingProgress(db(member), groupId, member, 1, 1, 'completed'));
    await assertFails(deleteDoc(doc(marker, 'versions', '0')));
});
test('restoration rejects nonadmin, stale versions, archive, invitation bypass and forged coordinated writes', async () => {
    await removeMember(db(owner), groupId, owner, member);
    await assert.rejects(restoreMember(db(lead), groupId, lead, member, 0), /admin/);
    await assert.rejects(restoreMember(db(owner), groupId, owner, member, 1), /changed/);
    await assertFails(addMember(db(owner), groupId, member));
    const connection = db(owner), marker = doc(connection, 'groups', groupId, 'departures', member);
    const previous = (await getDocFromServer(marker)).data();
    const restored = { restored: true, revision: 1, changedBy: owner, changedAt: serverTimestamp() };
    await assertFails(updateDoc(marker, restored));
    for (const patch of [{ role: 'admin' }, { joinedAt: Timestamp.fromMillis(0) }]) {
        const batch = writeBatch(connection);
        batch.set(doc(marker, 'versions', '0'), previous); batch.update(marker, restored);
        batch.set(doc(connection, 'groups', groupId, 'members', member), { userId: member, role: 'member', joinedAt: serverTimestamp(), ...patch });
        batch.set(doc(connection, 'users', member, 'groups', groupId), { groupId, joinedAt: serverTimestamp() });
        await assertFails(batch.commit());
    }
    await updateDoc(group(connection), change(true, 1));
    await assert.rejects(restoreMember(connection, groupId, owner, member, 0), /active group/);
    await updateDoc(group(connection), change(false, 2));
    await restoreMember(connection, groupId, owner, member, 0);
    await assert.rejects(restoreMember(connection, groupId, owner, member, 0), /departed/);
    await assertFails(updateDoc(doc(marker, 'versions', '0'), { reason: 'left' }));
});
test('assignment archive preserves immutable before-images; replacement resets progress and date', async () => {
    await updateReadingProgress(db(member), groupId, member, 1, 1, 'completed');
    const original = (await getDocFromServer(work(db(member)))).data();
    await transition(true);
    const archived = (await getDocFromServer(work(db(member)))).data();
    assert.equal(archived.archived, true); assert.equal(archived.status, 'completed'); assert.equal(archived.revision, 1);
    assert.deepEqual((await getDocFromServer(doc(work(db(member)), 'versions', '0'))).data(), original);
    await assertFails(updateReadingProgress(db(member), groupId, member, 1, 1, 'not_started'));
    await transition(false, { scheduledDate: new Date('2026-11-01T03:30:00Z') });
    const replacement = (await getDocFromServer(work(db(member)))).data();
    assert.equal(replacement.archived, false); assert.equal(replacement.status, 'not_started'); assert.equal(replacement.revision, 2);
    assert.equal(replacement.scheduledDate.toDate().toISOString(), '2026-11-01T03:30:00.000Z');
    assert.deepEqual((await getDocFromServer(doc(work(db(member)), 'versions', '1'))).data(), archived);
    await assertSucceeds(updateReadingProgress(db(member), groupId, member, 1, 1, 'in_progress'));
});
test('reassignment archives source and creates fresh work atomically; duplicate target rejects everything', async () => {
    await transition(true, { reassignTo: lead });
    assert.equal((await getDocFromServer(work(db(owner)))).data().archived, true);
    assert.equal((await getDocFromServer(work(db(lead), lead))).data().status, 'not_started');
    await transition(false);
    await assert.rejects(transition(true, { reassignTo: lead }), /already exists/);
    assert.equal((await getDocFromServer(work(db(owner)))).data().archived, false);
    assert.equal((await getDocFromServer(doc(work(db(owner)), 'versions', '2'))).exists(), false);
});
test('raw transition requires exact history and cannot forge archive progress or reuse history', async () => {
    const connection = db(owner), reference = work(connection);
    const original = (await getDocFromServer(reference)).data();
    const next = { archived: true, revision: 1, changedBy: owner, changedAt: serverTimestamp() };
    await assertFails(updateDoc(reference, next));
    for (const patch of [{ status: 'completed' }, { revision: 2 }, { changedBy: member }, { changedAt: Timestamp.fromMillis(0) }]) {
        const batch = writeBatch(connection);
        batch.set(doc(reference, 'versions', '0'), original); batch.update(reference, { ...next, ...patch });
        await assertFails(batch.commit());
    }
    const forged = writeBatch(connection);
    forged.set(doc(reference, 'versions', '0'), { ...original, status: 'completed' }); forged.update(reference, next);
    await assertFails(forged.commit());
    await assertFails(setDoc(doc(reference, 'versions', '0'), original));
    await transition(true);
    await assertFails(updateDoc(doc(reference, 'versions', '0'), { status: 'completed' }));
    await assertFails(deleteDoc(doc(reference, 'versions', '0')));
});
test('assignment version authority, stale progress and group archive cannot be bypassed', async () => {
    const original = (await getDocFromServer(work(db(owner)))).data();
    await assert.rejects(transition(true, {}, member), /scheduler/);
    await updateReadingProgress(db(member), groupId, member, 1, 1, 'in_progress');
    await assert.rejects(transition(true, { expectedProgressUpdatedAt: original.progressUpdatedAt }), /changed/);
    await updateDoc(group(db(owner)), change(true, 1));
    await assert.rejects(transition(true), /active group/);
    await updateDoc(group(db(owner)), change(false, 2));
    await transition(true, {}, lead);
    await assertFails(getDocFromServer(doc(work(db(outsider)), 'versions', '0')));
});

test('48 assignment writes across 12 target members stay within rules access limits', async () => {
    const connection = db(owner), targets = [owner, lead, member];
    while (targets.length < 12) {
        const uid = `archive-fanout-${randomUUID()}`;
        await setDoc(doc(db(uid), 'users', uid), { displayName: 'Fanout QA', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
        await addMember(connection, groupId, uid); targets.push(uid);
    }
    const commit = week => {
        const batch = writeBatch(connection);
        for (const uid of targets) for (let chapter = 1; chapter <= 4; chapter++) {
            batch.set(doc(connection, 'groups', groupId, 'readingWeeks', String(week), 'members', uid, 'assignments', String(chapter)),
                { ...assignment(), userId: uid, weekNumber: week, unitKey: String(chapter), chapterStart: chapter, chapterEnd: chapter });
        }
        return batch.commit();
    };
    await assertSucceeds(commit(2));
    await updateDoc(group(connection), change(true, 1));
    await assertFails(commit(3));
    await updateDoc(group(connection), change(false, 2));
    await assertSucceeds(commit(3));
});

test('moderation, reports, highlights, invites and personal boundaries survive archive/restore', async () => {
    const connection = db(owner);
    const pending = [];
    for (const kind of ['messages', 'highlights']) {
        const target = doc(connection, 'groups', groupId, kind, 'moderated');
        const content = kind === 'messages' ? message(owner) : { ...message(owner), chapterNumber: 16, paragraphIndex: 0, quote: 'Retained quote' };
        await setDoc(target, content);
        const report = doc(db(member), 'groups', groupId, kind, 'moderated', 'reports', member);
        const reportData = { reporterUid: member, reason: 'spam', details: '', createdAt: serverTimestamp(), status: 'open', resolvedBy: null, resolvedAt: null };
        await setDoc(report, reportData);
        pending.push(() => setDoc(doc(db(lead), 'groups', groupId, kind, 'moderated', 'reports', lead), { ...reportData, reporterUid: lead }));
        pending.push(() => updateDoc(doc(connection, 'groups', groupId, kind, 'moderated', 'reports', member),
            { status: 'resolved', resolvedBy: owner, resolvedAt: serverTimestamp() }));
        pending.push(() => setDoc(doc(db(member), 'groups', groupId, kind, 'new'), { ...content, senderUid: member }));
        pending.push(() => {
            const batch = writeBatch(connection);
            batch.set(doc(connection, 'groups', groupId, 'moderationRecords', kind, 'items', 'moderated'),
                { targetKind: kind, targetId: 'moderated', authorUid: owner, moderatedBy: owner, moderatedAt: serverTimestamp(), reason: 'spam' });
            batch.delete(target); return batch.commit();
        });
    }
    const display = doc(db(member), 'groups', groupId, 'memberProfiles', member);
    await setDoc(display, { displayName: 'Retained', createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
    pending.push(() => updateDoc(display, { displayName: 'Changed', updatedAt: serverTimestamp() }));
    const newToken = randomUUID().replaceAll('-', '') + randomUUID().replaceAll('-', '');
    pending.push(() => setDoc(doc(connection, 'groupInvites', newToken), {
        groupId, createdBy: owner,
        createdAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 3600000), active: true
    }));
    await updateDoc(group(connection), change(true, 1));
    for (const write of pending) await assertFails(write());
    await assertSucceeds(updateDoc(doc(db(member), 'users', member), { displayName: 'Still private', updatedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(db(member), 'users', member, 'settings', 'reminders'), {
        readingReminderEnabled: false, dailyVerseEnabled: true, reminderHour: 9, reminderMinute: 0,
        timezone: 'Asia/Kolkata', updatedAt: serverTimestamp()
    }));
    await assertSucceeds(getDocFromServer(display));
    await updateDoc(group(connection), change(false, 2));
    for (const write of pending) await assertSucceeds(write());
    await assertSucceeds(updateDoc(group(connection), { name: 'Restored name', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(group(connection), { currentWeek: 2, updatedAt: serverTimestamp() }));
});

test('group bootstrap cannot include lifecycle metadata; restored metadata cannot be removed', async () => {
    const connection = db(owner);
    const raw = (await getDocFromServer(group(connection))).data();
    const id = `archive-bootstrap-${randomUUID()}`;
    const batch = writeBatch(connection);
    batch.set(doc(connection, 'groups', id), { ...raw, ...change(true, 1), createdAt: serverTimestamp() });
    batch.set(doc(connection, 'groups', id, 'members', owner), { userId: owner, role: 'admin', joinedAt: serverTimestamp() });
    batch.set(doc(connection, 'users', owner, 'groups', id), { groupId: id, joinedAt: serverTimestamp() });
    await assertFails(batch.commit());
    await updateDoc(group(connection), change(true, 1));
    await updateDoc(group(connection), change(false, 2));
    await assertFails(setDoc(group(connection), { ...raw, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(group(connection), change(true, 3)));
});

test('legacy group archives/restores without erasure; existing members retain bounded read access', async () => {
    const original = (await getDocFromServer(group(db(owner)))).data();
    await assertSucceeds(updateDoc(group(db(owner)), change(true, 1)));
    for (const uid of [owner, lead, member]) {
        const snapshot = await assertSucceeds(getDocFromServer(group(db(uid))));
        assert.equal(snapshot.data().archived, true); assert.equal(snapshot.data().lifecycleRevision, 1);
        await assertSucceeds(getDocsFromServer(query(collection(db(uid), 'groups', groupId, 'messages'), limit(10))));
        await assertSucceeds(getDocFromServer(doc(db(uid), 'groups', groupId, 'readingWeeks', '1', 'members', member, 'assignments', '1')));
        await assertSucceeds(getDocFromServer(doc(db(uid), 'groups', groupId, 'settings', 'notificationSchedule')));
    }
    await assertSucceeds(updateDoc(group(db(owner)), change(false, 2)));
    const restored = (await getDocFromServer(group(db(member)))).data();
    assert.equal(restored.archived, false); assert.equal(restored.lifecycleRevision, 2);
    assert.ok(restored.createdAt.isEqual(original.createdAt)); assert.equal(restored.createdBy, original.createdBy);
    await assertSucceeds(setDoc(doc(db(member), 'groups', groupId, 'messages', 'after-restore'), message(member)));
});
test('only actual prewrite admins can transition; spoofed claims, leads, members and outsiders fail', async () => {
    for (const uid of [lead, member, outsider, null]) await assertFails(updateDoc(group(db(uid)), change(true, 1, uid)));
    const forged = environment.authenticatedContext(member, { admin: true, role: 'admin' }).firestore();
    await assertFails(updateDoc(group(forged), change(true, 1, member)));
    await updateDoc(group(db(owner)), change(true, 1));
    for (const uid of [lead, member, outsider, null]) await assertFails(updateDoc(group(db(uid)), change(false, 2, uid)));
    await assertFails(getDocFromServer(group(db(outsider)))); await assertFails(getDocFromServer(group(db(null))));
});
test('revision/timestamp/audit/schema guards reject bypasses and mixed identity/settings changes', async () => {
    const connection = db(owner);
    for (const invalid of [{ lifecycleRevision: 0 }, { lifecycleRevision: 2 }, { lifecycleRevision: 1.5 },
    { lifecycleRevision: 2147483648 }, { archived: 'true' }, { lifecycleChangedBy: member },
    { lifecycleChangedAt: Timestamp.fromMillis(0) }, { updatedAt: Timestamp.fromMillis(0) },
    { name: 'Mixed' }, { currentWeek: 2 }, { extra: true }]) await assertFails(updateDoc(group(connection), { ...change(true, 1), ...invalid }));
    for (const key of Object.keys(change(true, 1))) {
        const value = change(true, 1); delete value[key]; await assertFails(updateDoc(group(connection), value));
    }
    await updateDoc(group(connection), change(true, 1));
    await assertFails(updateDoc(group(connection), change(true, 2)));
    await assertFails(updateDoc(group(connection), change(false, 1)));
    await assertFails(deleteDoc(group(connection)));
});
test('archive/restore cannot be combined with any ordinary write, including same-document settings', async () => {
    const connection = db(owner);
    for (const archived of [true, false]) {
        const batch = writeBatch(connection);
        batch.update(group(connection), change(archived, archived ? 1 : 2));
        batch.set(doc(connection, 'groups', groupId, 'messages', 'mixed'), message(owner));
        await assertFails(batch.commit());
        if (archived) await updateDoc(group(connection), change(true, 1));
    }
    const batch = writeBatch(db(member));
    batch.update(doc(db(member), 'groups', groupId, 'members', member), { role: 'admin' });
    batch.update(group(db(member)), change(false, 2, member)); await assertFails(batch.commit());
});
test('archived group denies settings, content, progress, membership, invites and display mutations', async () => {
    await updateDoc(group(db(owner)), change(true, 1));
    await assertFails(updateDoc(group(db(owner)), { name: 'No', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(group(db(owner)), { currentWeek: 2, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db(member), 'groups', groupId, 'messages', 'new'), message(member)));
    await assertFails(updateDoc(doc(db(member), 'groups', groupId, 'readingWeeks', '1', 'members', member, 'assignments', '1'),
        { status: 'completed', progressUpdatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(db(owner), 'groups', groupId, 'readingWeeks', '1', 'members', member, 'assignments', '2'),
        { ...assignment(), unitKey: '2', chapterStart: 2, chapterEnd: 2 }));
    await assertFails(setDoc(doc(db(member), 'groups', groupId, 'memberProfiles', member),
        { displayName: 'No', createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(addMember(db(owner), groupId, outsider));
    await assertFails(setMemberRole(db(owner), groupId, member, 'group_lead'));
    await assertFails(updateDoc(doc(db(owner), 'groupInvites', token), { active: false }));
    await assertFails(saveGroupReminderSchedule(db(owner), groupId, owner, DEFAULT_GROUP_REMINDER_SCHEDULE, 1));
    const joined = writeBatch(db(outsider));
    joined.set(doc(db(outsider), 'groups', groupId, 'members', outsider), { userId: outsider, role: 'member', joinedAt: serverTimestamp() });
    joined.set(doc(db(outsider), 'users', outsider, 'groups', groupId), { groupId, joinedAt: serverTimestamp(), inviteToken: token });
    await assertFails(joined.commit());
    const departed = writeBatch(db(member));
    departed.set(doc(db(member), 'groups', groupId, 'departures', member), { userId: member, removedBy: member, removedAt: serverTimestamp(), reason: 'left' });
    departed.delete(doc(db(member), 'groups', groupId, 'members', member));
    departed.delete(doc(db(member), 'users', member, 'groups', groupId)); await assertFails(departed.commit());
});