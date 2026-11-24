import { doc, getDocFromServer, runTransaction, serverTimestamp, Timestamp } from 'firebase/firestore';

export const DEFAULT_GROUP_REMINDER_SCHEDULE = Object.freeze({
    initialDay: 0, initialHour: 9,
    initialMinute: 0, deadlineDay: 6, deadlineHour: 22, deadlineMinute: 0,
    escalationEnabled: true, timezone: 'Asia/Kolkata'
});
const fields = Object.keys(DEFAULT_GROUP_REMINDER_SCHEDULE);
const audit = ['groupId', 'revision', 'createdBy', 'createdAt', 'updatedBy', 'updatedAt'];
function segment(value) {
    if (typeof value !== 'string' || !value || value.includes('/') || value === '.' || value === '..'
        || /^__.*__$/.test(value) || new TextEncoder().encode(value).length > 1500) throw new Error('Invalid schedule path segment.');
    return value;
}
function exact(value, keys) {
    if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length !== keys.length
        || !keys.every(key => Object.hasOwn(value, key))) throw new Error('Exact schedule fields required.');
}
export function validateGroupReminderSchedule(value) {
    exact(value, fields);
    for (const [key, maximum] of [['initialDay', 6], ['deadlineDay', 6], ['initialHour', 23],
    ['deadlineHour', 23], ['initialMinute', 59], ['deadlineMinute', 59]]) {
        if (!Number.isSafeInteger(value[key]) || value[key] < 0 || value[key] > maximum) throw new Error('Invalid schedule integer bounds.');
    }
    if (typeof value.escalationEnabled !== 'boolean' || value.timezone !== 'Asia/Kolkata'
        || value.deadlineDay * 1440 + value.deadlineHour * 60 + value.deadlineMinute
        <= value.initialDay * 1440 + value.initialHour * 60 + value.initialMinute) throw new Error('Invalid timezone, toggle or schedule order.');
    return Object.freeze({ ...value });
}
function record(groupId, data) {
    exact(data, [...fields, ...audit]);
    if (data.groupId !== groupId || !Number.isSafeInteger(data.revision) || data.revision < 1 || data.revision > 2147483647
        || !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp)
        || data.createdAt.valueOf() > data.updatedAt.valueOf()) throw new Error('Invalid schedule record.');
    segment(data.createdBy); segment(data.updatedBy);
    validateGroupReminderSchedule(Object.fromEntries(fields.map(key => [key, data[key]])));
    return Object.freeze({ ...data });
}
function confirmed(snapshot, path) {
    if (snapshot.ref.path !== path || snapshot.metadata.fromCache || snapshot.metadata.hasPendingWrites) throw new Error('Confirmed server schedule required.');
}
export async function getGroupReminderSchedule(db, groupId) {
    segment(groupId);
    const reference = doc(db, 'groups', groupId, 'settings', 'notificationSchedule');
    const snapshot = await getDocFromServer(reference);
    confirmed(snapshot, reference.path);
    return snapshot.exists() ? record(groupId, snapshot.data()) : null;
}
export async function saveGroupReminderSchedule(db, groupId, uid, schedule, expectedRevision = 0) {
    segment(groupId); segment(uid);
    const draft = validateGroupReminderSchedule(schedule);
    if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0 || expectedRevision >= 2147483647) throw new Error('Invalid expected schedule revision.');
    const group = doc(db, 'groups', groupId);
    const member = doc(db, 'groups', groupId, 'members', uid);
    const reference = doc(db, 'groups', groupId, 'settings', 'notificationSchedule');
    await runTransaction(db, async transaction => {
        const groupDoc = await transaction.get(group), actor = await transaction.get(member), saved = await transaction.get(reference);
        for (const [snapshot, path] of [[groupDoc, group.path], [actor, member.path], [saved, reference.path]]) confirmed(snapshot, path);
        if (!groupDoc.exists() || !actor.exists() || actor.data().userId !== uid
            || !['admin', 'group_lead'].includes(actor.data().role)) throw new Error('Actual admin or lead membership required.');
        const current = saved.exists() ? record(groupId, saved.data()) : null;
        if ((current?.revision ?? 0) !== expectedRevision) throw new Error('Schedule changed. Reload before saving.');
        const time = serverTimestamp();
        transaction.set(reference, {
            ...draft, groupId, revision: expectedRevision + 1,
            createdBy: current?.createdBy ?? uid, createdAt: current?.createdAt ?? time, updatedBy: uid, updatedAt: time
        });
    });
}