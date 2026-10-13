// Om Sai Ram
// Notifications service — daily verse reminder + group reading reminders.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../../features/groups/data/assignment_model.dart';
import '../../features/groups/data/notification_schedule_model.dart';

const _kNotifEnabledKey = 'daily_notif_enabled';
const _kNotifHourKey = 'daily_notif_hour';
const _kNotifMinuteKey = 'daily_notif_minute';
const int _kDailyVerseNotifId = 1001;

// A small set of rotating daily verses.
const _verses = [
  'Sai Baba said: "Why do you fear when I am here?"',
  '"Have faith and patience. Then I shall be always with you wherever you are." — Sai Baba',
  '"Before we begin any task, we must first remember Sai Baba and seek His blessings."',
  '"I am the slave of my devotees. Wherever my devotees sing my praises, I am there." — Sai Baba',
  '"Look at Me, I will look at you." — Sai Baba',
  '"My treasury is full and I can give everyone what they want, but I have to see whether they deserve it." — Sai Baba',
  '"Do not be idle. Work, utter God\'s name and read the scriptures." — Sai Baba',
];

class NotificationsService {
  static final NotificationsService _instance = NotificationsService._();
  factory NotificationsService() => _instance;
  NotificationsService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotifEnabledKey) ?? false;
  }

  Future<({int hour, int minute})> getScheduledTime() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      hour: prefs.getInt(_kNotifHourKey) ?? 7,
      minute: prefs.getInt(_kNotifMinuteKey) ?? 0,
    );
  }

  Future<void> scheduleDailyVerse({required int hour, required int minute}) async {
    await init();
    await _plugin.cancel(_kDailyVerseNotifId);

    // Pick verse based on day-of-year so it rotates daily
    final dayOfYear = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    final verse = _verses[dayOfYear % _verses.length];

    const android = AndroidNotificationDetails(
      'daily_verse',
      'Daily Verse',
      channelDescription: 'A daily Sai Baba verse to inspire your day',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const ios = DarwinNotificationDetails();

    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, hour, minute);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      _kDailyVerseNotifId,
      'Om Sai Ram 🙏',
      verse,
      tz.TZDateTime.from(first, tz.local),
      const NotificationDetails(android: android, iOS: ios),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // ponytail: tz.local is UTC (no device tz lookup), so the time shifts 1h across DST changes.
      matchDateTimeComponents: DateTimeComponents.time,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabledKey, true);
    await prefs.setInt(_kNotifHourKey, hour);
    await prefs.setInt(_kNotifMinuteKey, minute);
  }

  Future<void> cancelDailyVerse() async {
    await init();
    await _plugin.cancel(_kDailyVerseNotifId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabledKey, false);
  }

  // ─── Group reading reminders ──────────────────────────────────────────────

  static const _kReadingChannel = 'reading_reminders';

  /// Notification details for reading reminders.
  static const _readingDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _kReadingChannel,
      'Reading Reminders',
      channelDescription: 'Reminders to complete your weekly Sai Satcharita reading',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  /// Compute a stable notification ID for a given assignment + slot index.
  ///
  /// Uses a bounded hash so IDs stay within the int32 range that
  /// flutter_local_notifications requires.
  int _notifId(String assignmentId, int slot) {
    // Keep in 0..999_999_9 range (7 digits), multiply by 10 for 7 slots per id.
    return (assignmentId.hashCode.abs() % 1000000) * 10 + slot;
  }

  /// Schedule all future reading reminders for [assignments] using [schedule].
  ///
  /// Call this whenever the user opens a group screen or after marking progress.
  /// Notifications for assignments that are already completed are skipped.
  /// Any previously scheduled notifications for these assignments are cancelled
  /// first so the set is always fresh.
  Future<void> scheduleGroupReadingNotifications({
    required List<Assignment> assignments,
    required GroupNotificationSchedule schedule,
  }) async {
    await init();

    for (final a in assignments) {
      // Always cancel stale notifications first.
      await cancelGroupNotificationsForAssignment(a.id);

      // Skip completed assignments.
      if (a.status == ReadingStatus.completed) continue;

      // Skip assignments with no scheduled date.
      if (a.scheduledDate == null) continue;

      final chapterLabel = 'Chapter ${a.displayChapterLabel}${a.chapterTitle == null ? '' : ' — ${a.chapterTitle}'}';
      final deadline = schedule.deadlineDateTime(a.scheduledDate!);
      final reminder = schedule.reminderDateTime(a.scheduledDate!);
      final now = DateTime.now();

      // Slot 0 — Initial reminder: "Time to start reading"
      if (reminder.isAfter(now)) {
        await _zonedSchedule(
          id: _notifId(a.id, 0),
          title: 'Om Sai Ram 🙏 — Time to Read',
          body: 'Your reading for this week: $chapterLabel. Baba is waiting! 📖',
          scheduledAt: reminder,
        );
      }

      if (!schedule.escalationEnabled) continue;

      // Escalation slots — only schedule those that are still in the future.
      final escalations = [
        (hours: 72, slot: 1, msg: '3 days left to read $chapterLabel ⏳'),
        (hours: 48, slot: 2, msg: '2 days left! Please start $chapterLabel 📖'),
        (hours: 24, slot: 3, msg: 'Only 1 day left to complete your reading 🙏'),
        (hours: 12, slot: 4, msg: '12 hours remaining — $chapterLabel awaits 🕐'),
        (hours: 6,  slot: 5, msg: 'Just 6 hours left. Don\'t miss this week\'s reading! ⏰'),
        (hours: 2,  slot: 6, msg: 'Final reminder: 2 hours to complete $chapterLabel 📿'),
      ];

      for (final e in escalations) {
        final fireAt = deadline.subtract(Duration(hours: e.hours));
        if (fireAt.isAfter(now)) {
          await _zonedSchedule(
            id: _notifId(a.id, e.slot),
            title: 'Om Sai Ram — Reading Deadline',
            body: e.msg,
            scheduledAt: fireAt,
          );
        }
      }
    }
  }

  /// Cancel all scheduled reading reminders for a single assignment.
  Future<void> cancelGroupNotificationsForAssignment(String assignmentId) async {
    await init();
    for (var slot = 0; slot < 7; slot++) {
      await _plugin.cancel(_notifId(assignmentId, slot));
    }
  }

  /// Cancel ALL group reading reminders (e.g. on logout); the daily verse is kept.
  Future<void> cancelAllGroupNotifications() async {
    await init();
    await _plugin.cancelAll();
    if (await isEnabled()) {
      final t = await getScheduledTime();
      await scheduleDailyVerse(hour: t.hour, minute: t.minute);
    }
  }

  /// Internal helper — schedule a one-shot notification using zonedSchedule.
  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    final tzDateTime = tz.TZDateTime.from(scheduledAt, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDateTime,
      _readingDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );
  }
}
