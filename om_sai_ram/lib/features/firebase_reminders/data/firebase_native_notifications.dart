import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import 'firebase_reminder_delivery.dart';
import 'firebase_reminder_planner.dart';

class FirebaseAndroidNotificationDriver implements FirebaseNotificationDriver {
  final FlutterLocalNotificationsPlugin plugin;
  final tz.Location location;
  bool _initialized = false;
  FirebaseAndroidNotificationDriver(this.plugin, this.location);
  Future<void> _init() async {
    if (_initialized) return;
    await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    return await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;
  }

  @override
  Future<bool> permissionGranted() async {
    await _init();
    return await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled() ??
        false;
  }

  @override
  Future<List<int>> pendingIds() async {
    await _init();
    return (await plugin.pendingNotificationRequests())
        .map((item) => item.id)
        .toList();
  }

  @override
  Future<void> cancel(int id) async {
    await _init();
    await plugin.cancel(id);
  }

  @override
  Future<void> schedule(FirebaseReminderItem item) async {
    await _init();
    await plugin.zonedSchedule(
        item.id,
        item.title,
        item.body,
        tz.TZDateTime.from(item.fireAtUtc, location),
        const NotificationDetails(
            android: AndroidNotificationDetails(
                'firebase_reading_v1', 'Firebase reminders',
                channelDescription: 'Opt-in reading and daily verse reminders',
                importance: Importance.defaultImportance)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime);
  }
}

class SharedFirebaseNotificationJournal implements FirebaseNotificationJournal {
  static const key = 'firebase_notification_journal_v1';
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Notification journal write failed.');
    }
  }
}

class FirebaseReminderRegistration {
  final String groupId;
  final int week;
  final DateTime mondayUtc;
  FirebaseReminderRegistration(this.groupId, this.week, this.mondayUtc) {
    assignmentSegment(groupId);
    assignmentWeek(week);
    if (!mondayUtc.isUtc) {
      throw const FormatException('UTC week anchor required.');
    }
  }
  Map<String, dynamic> toData() => {
        'groupId': groupId,
        'week': week,
        'mondayUtc': mondayUtc.toIso8601String()
      };
  static FirebaseReminderRegistration parse(dynamic value) {
    if (value is! Map ||
        value.length != 3 ||
        value['groupId'] is! String ||
        value['week'] is! int ||
        value['mondayUtc'] is! String) {
      throw const FormatException('Invalid device week registration.');
    }
    return FirebaseReminderRegistration(
        value['groupId'], value['week'], DateTime.parse(value['mondayUtc']));
  }
}

abstract class FirebaseReminderDeviceStore {
  Future<String?> enabledUid();
  Future<void> setEnabledUid(String? uid);
  Future<List<FirebaseReminderRegistration>> registrations(String uid);
  Future<void> saveRegistrations(
      String uid, List<FirebaseReminderRegistration> values);
}

class SharedFirebaseReminderDeviceStore implements FirebaseReminderDeviceStore {
  static const _enabled = 'firebase_notifications_device_uid_v1';
  String _key(String uid) =>
      'firebase_notification_weeks_v1_${Uri.encodeComponent(assignmentSegment(uid))}';
  @override
  Future<String?> enabledUid() async =>
      (await SharedPreferences.getInstance()).getString(_enabled);
  @override
  Future<void> setEnabledUid(String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = uid == null
        ? await prefs.remove(_enabled)
        : await prefs.setString(_enabled, assignmentSegment(uid));
    if (!saved) throw StateError('Device opt-in write failed.');
  }

  @override
  Future<List<FirebaseReminderRegistration>> registrations(String uid) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(uid));
    if (raw == null) return [];
    final list = jsonDecode(raw);
    if (list is! List || list.length > 8) {
      throw const FormatException('Invalid device reminder registrations.');
    }
    final result = list.map(FirebaseReminderRegistration.parse).toList();
    if (result
            .map((item) => jsonEncode([item.groupId, item.week]))
            .toSet()
            .length !=
        result.length) {
      throw const FormatException('Duplicate device weeks.');
    }
    return result;
  }

  @override
  Future<void> saveRegistrations(
      String uid, List<FirebaseReminderRegistration> values) async {
    if (values.length > 8) {
      throw const FormatException('At most eight device weeks.');
    }
    if (!await (await SharedPreferences.getInstance()).setString(
        _key(uid), jsonEncode(values.map((item) => item.toData()).toList()))) {
      throw StateError('Device registrations write failed.');
    }
  }
}
