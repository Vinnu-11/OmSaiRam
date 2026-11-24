import { doc, setDoc, getDocFromServer, serverTimestamp } from 'firebase/firestore';

// Backend reading schedule defaults to 09:00. Daily verse currently defaults
// off (with a separate 07:00 device time). This personal contract has ONE time,
// not two schedules: use 09:00 and conservative opt-in toggles for both.
export const DEFAULT_REMINDER_SETTINGS = Object.freeze({
    readingReminderEnabled: false,
    dailyVerseEnabled: false,
    reminderHour: 9,
    reminderMinute: 0,
    timezone: 'Asia/Kolkata',
});

function reference(db, uid) {
    if (typeof uid !== 'string' || !uid || uid.includes('/')
        || uid === '.' || uid === '..' || /^__.*__$/.test(uid)
        || new TextEncoder().encode(uid).length > 1500) {
        throw new Error('Owner UID must be a valid single Firestore path segment.');
    }
    return doc(db, 'users', uid, 'settings', 'reminders');
}

/** Local reference preferences only. Full replacement avoids stale fields;
 * partial/unknown fields are rejected, never silently defaulted on updates.
 * No scheduler, FCM, device tokens, group deadlines or delivery permissions.
 * India-first timezone allowlist only; no general timezone support claimed.
 * Rules verify uid against authentication, not group role or client input.
 */
export async function setReminderSettings(db, uid, settings = DEFAULT_REMINDER_SETTINGS) {
    const ref = reference(db, uid);
    const keys = Object.keys(DEFAULT_REMINDER_SETTINGS);
    if (!settings || typeof settings !== 'object' || Array.isArray(settings)
        || Object.keys(settings).length !== keys.length
        || !keys.every(key => Object.hasOwn(settings, key))) {
        throw new Error('Reminder settings must contain exactly the five preference fields.');
    }
    const { readingReminderEnabled, dailyVerseEnabled, reminderHour, reminderMinute, timezone } = settings;
    if (typeof readingReminderEnabled !== 'boolean' || typeof dailyVerseEnabled !== 'boolean') {
        throw new Error('Reminder toggles must be booleans.');
    }
    if (!Number.isSafeInteger(reminderHour) || reminderHour < 0 || reminderHour > 23
        || !Number.isSafeInteger(reminderMinute) || reminderMinute < 0 || reminderMinute > 59) {
        throw new Error('Reminder hour/minute must be integers in 0..23/0..59.');
    }
    if (timezone !== 'Asia/Kolkata') throw new Error('Only Asia/Kolkata is supported initially.');
    await setDoc(ref, { ...settings, updatedAt: serverTimestamp() });
}

/** Missing preferences remain null; reading does not write or enable defaults.
 * Server-only access avoids treating cached preferences as an authorization.
 */
export async function getReminderSettings(db, uid) {
    const snapshot = await getDocFromServer(reference(db, uid));
    return snapshot.exists() ? snapshot.data() : null;
}