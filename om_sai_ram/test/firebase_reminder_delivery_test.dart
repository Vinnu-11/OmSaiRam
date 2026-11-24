import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_planner.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_delivery.dart';

class NotificationDriverFake implements FirebaseNotificationDriver {
  bool granted = true;
  bool failCancel = false;
  int permissionCalls = 0, schedules = 0;
  int? failAt;
  Completer<void>? gate;
  final pending = <int>{}, cancelled = <int>[];
  @override
  Future<bool> requestPermission() async {
    permissionCalls++;
    return granted;
  }

  @override
  Future<bool> permissionGranted() async => granted;
  @override
  Future<List<int>> pendingIds() async => pending.toList();
  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('Cancel failed.');
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<void> schedule(FirebaseReminderItem item) async {
    schedules++;
    if (gate != null) await gate!.future;
    if (schedules == failAt) throw StateError('Plugin write failure.');
    pending.add(item.id);
  }
}

class NotificationJournalFake implements FirebaseNotificationJournal {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Disk full.');
    this.value = value;
  }
}

void main() {
  tz_data.initializeTimeZones();
  late String? uid;
  late NotificationDriverFake driver;
  late NotificationJournalFake journal;
  late FirebaseReminderDelivery delivery;
  FirebaseReminderPlan plan([String account = 'a']) => planFirebaseReminders(
      uid: account,
      preferences: FirebaseReminderPreferences.defaults
          .copyWith(dailyVerseEnabled: true),
      weeks: [],
      nowUtc: DateTime.utc(2026, 10, 19),
      location: tz.getLocation('Asia/Kolkata'));
  setUp(() {
    uid = 'a';
    driver = NotificationDriverFake();
    journal = NotificationJournalFake();
    delivery = FirebaseReminderDelivery(driver, journal, () => uid);
  });
  test(
      'permission is explicit, owned queue is journaled and unrelated legacy IDs survive',
      () async {
    driver.pending.addAll([1001, 42]);
    await delivery.apply('a', plan(), requestPermission: true);
    expect(driver.permissionCalls, 1);
    expect(driver.pending.length, 9);
    expect((jsonDecode(journal.value!) as Map)['ids'],
        plan().items.map((item) => item.id).toList());
    await delivery.apply('a', plan(), requestPermission: false);
    expect(driver.permissionCalls, 1);
    await delivery.invalidate();
    expect(driver.pending, {1001, 42});
    expect((jsonDecode(journal.value!) as Map)['ids'], isEmpty);
  });
  test('permission denied cancels stale owned notifications without scheduling',
      () async {
    driver.granted = false;
    driver.pending.add(0x40000001);
    await expectLater(
        delivery.apply('a', plan(), requestPermission: true), throwsStateError);
    expect(driver.schedules, 0);
    expect(driver.pending, isEmpty);
  });
  test(
      'partial plugin failure cancels all new IDs and never loses the recovery journal',
      () async {
    driver.failAt = 3;
    await expectLater(
        delivery.apply('a', plan(), requestPermission: true), throwsStateError);
    expect(driver.pending, isEmpty);
    expect((jsonDecode(journal.value!) as Map)['ids'], isEmpty);
  });
  test(
      'startup invalidation recovers a crash and corrupted journal via reserved pending range',
      () async {
    driver.pending.addAll([1001, 0x40000001]);
    journal.value = '{bad';
    await delivery.invalidate();
    expect(driver.pending, {1001});
  });
  test('journal failure prevents any plugin scheduling', () async {
    journal.fail = true;
    await expectLater(
        delivery.apply('a', plan(), requestPermission: true), throwsStateError);
    expect(driver.schedules, 0);
  });
  test('account mismatch rejects queue before requesting permission', () async {
    await expectLater(delivery.apply('a', plan('b'), requestPermission: true),
        throwsFormatException);
    expect(driver.permissionCalls, 0);
    expect(driver.schedules, 0);
  });
  test(
      'logout during plugin await serially cancels the just-scheduled old-account notification',
      () async {
    driver.gate = Completer<void>();
    final pending = expectLater(
        delivery.apply('a', plan(), requestPermission: true), throwsStateError);
    for (var index = 0; index < 20; index++) {
      await Future<void>.delayed(Duration.zero);
    }
    uid = null;
    final cleanup = delivery.invalidate();
    driver.gate!.complete();
    await pending;
    await cleanup;
    expect(driver.pending, isEmpty);
  });
  test('queued former-session work cannot run after invalidation', () async {
    final cleanup = delivery.invalidate();
    uid = 'b';
    final pending = expectLater(
        delivery.apply('a', plan(), requestPermission: true), throwsStateError);
    await cleanup;
    await pending;
    expect(driver.permissionCalls, 0);
    await delivery.apply('b', plan('b'), requestPermission: true);
    expect(driver.pending.length, 7);
  });
}
