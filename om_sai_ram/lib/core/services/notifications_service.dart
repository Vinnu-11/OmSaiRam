// Om Sai Ram
// Notifications service — daily verse reminder using local notifications.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    await _plugin.periodicallyShowWithDuration(
      _kDailyVerseNotifId,
      'Om Sai Ram 🙏',
      verse,
      const Duration(hours: 24),
      const NotificationDetails(android: android, iOS: ios),
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
}
