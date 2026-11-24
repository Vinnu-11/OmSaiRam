import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_group_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/presentation/firebase_device_reminder_controls.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_assignments_test.dart' as assignments;
import 'firebase_group_reminders_test.dart' as groups;
import 'firebase_groups_test.dart' as group_models;
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_native_notifications.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_delivery.dart';
import 'package:om_sai_ram/features/firebase_reminders/providers/firebase_device_reminders_provider.dart';
import 'firebase_reminder_delivery_test.dart' as delivery_test;

class DeviceStoreFake implements FirebaseReminderDeviceStore {
  String? enabled;
  final weeks = <String, List<FirebaseReminderRegistration>>{};
  @override
  Future<String?> enabledUid() async => enabled;
  @override
  Future<void> setEnabledUid(String? uid) async {
    enabled = uid;
  }

  @override
  Future<List<FirebaseReminderRegistration>> registrations(String uid) async =>
      List.of(weeks[uid] ?? []);
  @override
  Future<void> saveRegistrations(
      String uid, List<FirebaseReminderRegistration> values) async {
    weeks[uid] = List.of(values);
  }
}

void main() {
  tz_data.initializeTimeZones();
  late String? uid;
  late delivery_test.NotificationDriverFake driver;
  late DeviceStoreFake store;
  late FirebaseDeviceRemindersController controller;
  late FirebaseReminderRecord? record;
  Completer<void>? gate;
  var reads = 0;
  late Future<FirebaseGroupReminderSnapshot> Function(String) scheduleReader;
  late Future<FirebaseAssignmentsResult> Function(FirebaseAssignmentsScope)
      assignmentReader;
  FirebaseDeviceRemindersController createController() =>
      FirebaseDeviceRemindersController(
          supported: true,
          delivery: FirebaseReminderDelivery(
              driver, delivery_test.NotificationJournalFake(), () => uid),
          store: store,
          currentUid: () => uid,
          readPreferences: () async {
            reads++;
            if (gate != null) await gate!.future;
            return record;
          },
          readSchedule: (group) => scheduleReader(group),
          readAssignments: (scope) => assignmentReader(scope),
          location: tz.getLocation('Asia/Kolkata'),
          clock: () => DateTime.utc(2026, 10, 19));
  setUp(() {
    uid = 'a';
    driver = delivery_test.NotificationDriverFake();
    store = DeviceStoreFake();
    reads = 0;
    gate = null;
    record = FirebaseReminderRecord.parse('a', {
      ...FirebaseReminderPreferences.defaults
          .copyWith(dailyVerseEnabled: true)
          .toData(),
      'updatedAt': Timestamp(100, 1)
    });
    scheduleReader = (_) async => throw StateError('No reading preference');
    assignmentReader = (_) async => throw StateError('No reading preference');
    controller = createController();
  });
  tearDown(() {
    if (controller.mounted) controller.dispose();
  });
  Future<ProviderContainer> mount(WidgetTester tester) async {
    await tester.runAsync(() async {
      controller.dispose();
      await controller.delivery.invalidate();
    });
    controller = createController();
    final auth = authentication.FakeGateway()..profile = 'Private';
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseDeviceRemindersProvider.overrideWith((ref) => controller)
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: FirebaseDeviceReminderControls(uid: 'a'))))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await auth.changes.close();
    });
    return container;
  }

  testWidgets(
      'device controls do not prompt on load or cancel; explicit confirmation enables queued verses',
      (tester) async {
    final container = await mount(tester);
    expect(driver.permissionCalls, 0);
    expect(container.read(firebaseSessionProvider).ready, true);
    await tester
        .ensureVisible(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(driver.permissionCalls, 0);
    await tester.tap(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable on device'));
    await tester.pumpAndSettle();
    expect(controller.state.error, isNull);
    expect(reads, 1);
    expect(driver.permissionCalls, 1);
    expect(driver.pending.length, 7);
  });
  testWidgets(
      'signout during device permission confirmation cannot dispatch the old account queue',
      (tester) async {
    final container = await mount(tester);
    await tester
        .ensureVisible(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    uid = null;
    (container.read(firebaseAuthGatewayProvider) as authentication.FakeGateway)
        .emit(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable on device'));
    await tester.pumpAndSettle();
    expect(driver.permissionCalls, 0);
  });
  testWidgets(
      '320px double-sized device controls and confirmation have no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await mount(tester);
    await tester
        .ensureVisible(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-reminders-enable')));
    await tester.pumpAndSettle();
    expect(find.text('Enable reminders on this device?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
      'opening/reloading device preferences never requests permission or reads Firestore until opted in',
      () async {
    await controller.sessionChanged('a');
    await controller.refresh();
    expect(reads, 0);
    expect(driver.permissionCalls, 0);
    await controller.enable();
    expect(driver.permissionCalls, 1);
    expect(driver.pending.length, 7);
    expect(controller.state.enabled, true);
    await controller.refresh();
    expect(driver.permissionCalls, 1);
    expect(driver.pending.length, 7);
  });
  test(
      'disabled saved preferences cancel queue and device opt-in without prompting',
      () async {
    await controller.enable();
    record = FirebaseReminderRecord.parse('a', {
      ...FirebaseReminderPreferences.defaults.toData(),
      'updatedAt': Timestamp(101, 1)
    });
    await controller.refresh();
    expect(driver.pending, isEmpty);
    expect(store.enabled, isNull);
    expect(controller.state.enabled, false);
  });
  test('missing or unverified server preferences never enable delivery',
      () async {
    record = null;
    await controller.enable();
    expect(driver.pending, isEmpty);
    expect(driver.permissionCalls, 0);
    expect(controller.state.error, isNotNull);
  });
  test('revoked OS permission pauses rather than prompting on refresh',
      () async {
    await controller.enable();
    driver.granted = false;
    await controller.refresh();
    expect(controller.state.enabled, false);
    expect(driver.pending, isEmpty);
    expect(driver.permissionCalls, 1);
  });
  test(
      'failed cancellation is disclosed as unverified and explicit disable can recover',
      () async {
    await controller.enable();
    driver.failCancel = true;
    record = null;
    await controller.refresh();
    expect(controller.state.error,
        contains('Could not verify device cancellation'));
    expect(driver.pending, isNotEmpty);
    driver.failCancel = false;
    await controller.disable();
    expect(driver.pending, isEmpty);
    expect(controller.state.error, isNull);
  });
  test(
      'logout and account switch cancel owned queue and require explicit new-account opt-in',
      () async {
    await controller.enable();
    uid = null;
    await controller.sessionChanged(null, signedOut: true);
    expect(driver.pending, isEmpty);
    expect(store.enabled, isNull);
    uid = 'b';
    await controller.sessionChanged('b');
    expect(reads, 1);
    expect(controller.state.enabled, false);
  });
  test('direct account switch drops the former account device opt-in',
      () async {
    await controller.enable();
    uid = 'b';
    await controller.sessionChanged('b');
    expect(store.enabled, isNull);
    expect(driver.pending, isEmpty);
    uid = 'a';
    await controller.sessionChanged('a');
    expect(driver.pending, isEmpty);
    expect(controller.state.enabled, false);
  });
  test(
      'late server preference response after account change never schedules old-account reminders',
      () async {
    gate = Completer<void>();
    final pending = controller.enable();
    for (var index = 0; index < 12; index++) {
      await Future<void>.delayed(Duration.zero);
    }
    uid = 'b';
    final changed = controller.sessionChanged('b');
    gate!.complete();
    await pending;
    await changed;
    expect(driver.schedules, 0);
    expect(driver.permissionCalls, 0);
    expect(store.enabled, isNull);
  });
  test(
      'registration requires a genuine confirmed India Monday and remains per-account',
      () async {
    await controller.register(
        FirebaseReminderRegistration('g', 1, DateTime.utc(2026, 10, 19)));
    expect(controller.state.error, isNotNull);
    expect(store.weeks, isEmpty);
    await controller.register(FirebaseReminderRegistration(
        'g', 1, DateTime.utc(2026, 10, 18, 18, 30)));
    expect(store.weeks['a']!.length, 1);
    expect(driver.permissionCalls, 0);
    uid = 'b';
    await controller.sessionChanged('b');
    expect(controller.state.registrations, isEmpty);
  });
  test('account state clears synchronously before asynchronous plugin cleanup',
      () async {
    await controller.register(FirebaseReminderRegistration(
        'private-group', 1, DateTime.utc(2026, 10, 18, 18, 30)));
    expect(controller.state.registrations, isNotEmpty);
    uid = 'b';
    final pending = controller.sessionChanged('b');
    expect(controller.state.registrations, isEmpty);
    await pending;
  });
  test(
      'own reading reminders reconcile completion and pause on membership read failure',
      () async {
    final source = assignments.FakeAssignments();
    final anchor = DateTime.utc(2026, 10, 18, 18, 30);
    source.saved[assignments.own] = {
      '16-17': {
        ...assignments.assignmentData(),
        'scheduledDate':
            Timestamp.fromDate(anchor.add(const Duration(hours: 12)))
      }
    };
    final schedule = groups.GroupReminderFake()
      ..record = FirebaseGroupReminderRecord.parse('g', groups.scheduleData());
    scheduleReader = schedule.read;
    assignmentReader = source.read;
    record = FirebaseReminderRecord.parse('a', {
      ...FirebaseReminderPreferences.defaults
          .copyWith(readingReminderEnabled: true)
          .toData(),
      'updatedAt': Timestamp(100, 1)
    });
    await controller.register(FirebaseReminderRegistration('g', 1, anchor));
    await controller.enable();
    expect(driver.pending.length, 7);
    source.saved[assignments.own]!['16-17']!['status'] = 'completed';
    await controller.refresh();
    expect(driver.pending, isEmpty);
    source.saved[assignments.own]!['16-17']!['status'] = 'in_progress';
    await controller.refresh();
    expect(driver.pending.length, 7);
    final active = source.result(assignments.own);
    source.saved[assignments.own]!['16-17']!.addAll({'archived': true, 'revision': 1,
      'changedBy': 'a', 'changedAt': Timestamp.fromDate(group_models.now)});
    await controller.refresh(); expect(driver.pending, isEmpty);
    source.saved[assignments.own]!['16-17']!.addAll({'archived': false, 'revision': 2});
    await controller.refresh(); expect(driver.pending.length, 7);
    final created = active.assignments.single.createdToken;
    source.tampered = FirebaseAssignmentsResult(active.group, active.self,
      FirebaseMembership.parse('a', {'userId': 'a', 'role': 'member', 'joinedAt': Timestamp(created.seconds, created.nanoseconds + 1)}), active.assignments);
    await controller.refresh(); expect(driver.pending, isEmpty);
    source.tampered = null;
    await controller.refresh(); expect(driver.pending.length, 7);
    source.tampered = FirebaseAssignmentsResult(
      FirebaseGroup.parse('g', {...group_models.groupData(), 'archived': true,
        'lifecycleRevision': 1, 'lifecycleChangedBy': 'a', 'lifecycleChangedAt': group_models.groupData()['updatedAt']}),
      active.self, active.member, active.assignments);
    await controller.refresh();
    expect(driver.pending, isEmpty);
    expect(controller.state.enabled, true);
    expect(controller.state.error, isNull);
    source.tampered = null;
    await controller.refresh();
    expect(driver.pending.length, 7);
    schedule.readError = StateError('departed');
    await controller.refresh();
    expect(driver.pending, isEmpty);
    expect(controller.state.enabled, false);
  });
}
