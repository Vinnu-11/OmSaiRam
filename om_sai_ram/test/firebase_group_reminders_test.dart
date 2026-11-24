import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:flutter/services.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_reminders/presentation/firebase_group_reminders_screen.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_group_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firestore_group_reminders_gateway.dart';
import 'package:om_sai_ram/features/firebase_reminders/providers/firebase_group_reminders_provider.dart';

Map<String, dynamic> scheduleData() => {
      ...FirebaseGroupReminderDraft.defaults.toData(),
      'groupId': 'g',
      'revision': 1,
      'createdBy': 'admin',
      'updatedBy': 'lead',
      'createdAt': Timestamp(100, 1),
      'updatedAt': Timestamp(101, 2)
    };

class GroupReminderFake implements FirebaseGroupRemindersGateway {
  String uid = 'a', groupId = 'g';
  FirebaseGroupRole role = FirebaseGroupRole.admin;
  FirebaseGroupReminderRecord? record;
  Object? readError, writeError;
  Completer<void>? readGate, writeGate;
  int reads = 0, writes = 0;
  bool missingAfterSave = false;
  @override
  Future<FirebaseGroupReminderSnapshot> read(String groupId) async {
    reads++;
    await readGate?.future;
    if (readError != null) throw readError!;
    return FirebaseGroupReminderSnapshot(uid, this.groupId, role, record);
  }

  @override
  Future<void> save(FirebaseGroupReminderSnapshot baseline,
      FirebaseGroupReminderDraft draft) async {
    writes++;
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    if (!missingAfterSave) {
      record = FirebaseGroupReminderRecord.parse(groupId, {
        ...scheduleData(),
        ...draft.toData(),
        'revision': (record?.revision ?? 0) + 1,
        'updatedBy': uid
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<GroupReminderFake> mount(WidgetTester tester,
      {GroupReminderFake? gateway}) async {
    final auth = authentication.FakeGateway()..profile = 'Private';
    final source = gateway ?? GroupReminderFake();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupRemindersGatewayProvider.overrideWithValue(source),
      apiClientProvider.overrideWith((ref) => throw StateError('No legacy API'))
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: FirebaseGroupRemindersScreen(groupId: 'g'))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await auth.changes.close();
    });
    return source;
  }

  testWidgets(
      'missing group schedule is unsaved, explicit confirmation cancel/save controls writes',
      (tester) async {
    final gateway = await mount(tester);
    expect(find.text(groupReminderDisclosure), findsOneWidget);
    expect(find.byKey(const Key('group-reminders-missing')), findsOneWidget);
    expect(gateway.writes, 0);
    await tester.scrollUntilVisible(
        find.byKey(const Key('group-reminders-save')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-reminders-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Expected revision: 0'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.writes, 0);
    await tester.tap(find.byKey(const Key('group-reminders-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm save'));
    await tester.pumpAndSettle();
    expect(gateway.writes, 1);
    expect(
        find.text('Schedule saved and reloaded from server.'), findsOneWidget);
  });
  testWidgets('member sees read-only schedule and no editor or save action',
      (tester) async {
    final gateway = GroupReminderFake()
      ..role = FirebaseGroupRole.member
      ..record = FirebaseGroupReminderRecord.parse('g', scheduleData());
    await mount(tester, gateway: gateway);
    expect(find.textContaining('Read-only.'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.byKey(const Key('group-reminders-save')), findsNothing);
    expect(gateway.writes, 0);
  });
  testWidgets(
      'signout while save confirmation is open cannot dispatch a schedule write',
      (tester) async {
    final gateway = await mount(tester);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(FirebaseGroupRemindersScreen)));
    await tester.scrollUntilVisible(
        find.byKey(const Key('group-reminders-save')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-reminders-save')));
    await tester.pumpAndSettle();
    (container.read(firebaseAuthGatewayProvider) as authentication.FakeGateway)
        .emit(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm save'));
    await tester.pumpAndSettle();
    expect(gateway.writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'protected group reminder deep link redirects logged-out session before gateway access',
      (tester) async {
    final auth = authentication.FakeGateway();
    final gateway = GroupReminderFake();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupRemindersGatewayProvider.overrideWithValue(gateway),
      apiClientProvider.overrideWith((ref) => throw StateError('No legacy API'))
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(null);
    await tester.pump();
    final router = container.read(routerProvider)
      ..go('/groups/g/reminder-schedule');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(gateway.reads, 0);
    expect(gateway.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await auth.changes.close();
  });
  testWidgets(
      'storage editor never invokes notification plugin permissions or scheduling',
      (tester) async {
    final calls = <String>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await mount(tester);
    // Firebase is the default on Android, so the device layer may initialize
    // the plugin; the editor must still never request permission or schedule.
    expect(calls.where((method) => method != 'initialize'), isEmpty);
  });
  testWidgets(
      'native time picker edits only draft; invalid weekday order cannot be saved',
      (tester) async {
    final gateway = await mount(tester);
    await tester.tap(find.byKey(const Key('group-reminders-initial-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(gateway.writes, 0);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monday').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-reminders-validation')), findsNothing);
    expect(find.text('Deadline: Monday 22:00'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<int>).first, -150);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tuesday').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-reminders-validation')), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('group-reminders-save')), 150);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('group-reminders-save')))
            .onPressed,
        isNull);
  });
  testWidgets(
      '320px double-sized text fits schedule editor and scrollable confirmation',
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
    await tester.scrollUntilVisible(
        find.byKey(const Key('group-reminders-save')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-reminders-save')));
    await tester.pumpAndSettle();
    expect(find.text('Save group reminder schedule?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  const scope = (uid: 'a', groupId: 'g');
  test(
      'controller missing read never writes; explicit save acknowledges and reloads',
      () async {
    final gateway = GroupReminderFake();
    final controller =
        FirebaseGroupRemindersController(scope, () => gateway, () => true);
    expect(await controller.save(), false);
    await controller.load();
    expect(controller.state.canEdit, true);
    expect(controller.state.snapshot!.record, isNull);
    expect(gateway.writes, 0);
    expect(await controller.save(), true);
    expect(controller.state.acknowledged, true);
    expect(gateway.reads, 2);
    expect(gateway.writes, 1);
    controller.dispose();
  });
  test('member read-only and role loss on server reload disable editing',
      () async {
    final gateway = GroupReminderFake()..role = FirebaseGroupRole.member;
    final controller =
        FirebaseGroupRemindersController(scope, () => gateway, () => true);
    await controller.load();
    expect(controller.state.canEdit, false);
    expect(await controller.save(), false);
    gateway.role = FirebaseGroupRole.groupLead;
    await controller.load();
    expect(controller.state.canEdit, true);
    gateway.role = FirebaseGroupRole.member;
    await controller.load();
    expect(controller.state.canEdit, false);
    expect(gateway.writes, 0);
    controller.dispose();
  });
  test(
      'uncertain/conflict save blocks writes and retains draft through verification for explicit restore',
      () async {
    final gateway = GroupReminderFake()
      ..writeError = const FormatException('Schedule changed.');
    final controller =
        FirebaseGroupRemindersController(scope, () => gateway, () => true);
    await controller.load();
    final draft = controller.state.draft!.copyWith(initialHour: 10);
    controller.edit(draft);
    expect(await controller.save(), false);
    expect(controller.state.verifyBeforeSave, true);
    expect(controller.state.retainedDraft, same(draft));
    expect(await controller.save(), false);
    expect(gateway.writes, 1);
    gateway.writeError = null;
    await controller.load();
    expect(controller.state.retainedDraft, same(draft));
    expect(controller.state.draft!.initialHour, 9);
    controller.restoreDraft();
    expect(controller.state.draft!.initialHour, 10);
    expect(await controller.save(), true);
    expect(gateway.writes, 2);
    controller.dispose();
  });
  test(
      'restore after account change clears rather than exposing retained old-account draft',
      () async {
    var current = true;
    final gateway = GroupReminderFake()..writeError = StateError('offline');
    final controller =
        FirebaseGroupRemindersController(scope, () => gateway, () => current);
    await controller.load();
    controller.edit(controller.state.draft!.copyWith(initialHour: 10));
    await controller.save();
    gateway.writeError = null;
    await controller.load();
    expect(controller.state.retainedDraft, isNotNull);
    current = false;
    controller.restoreDraft();
    expect(controller.state.draft, isNull);
    expect(controller.state.retainedDraft, isNull);
    controller.dispose();
  });
  test('acknowledged write and failed reload never offer a blind write retry',
      () async {
    final gateway = GroupReminderFake();
    final controller =
        FirebaseGroupRemindersController(scope, () => gateway, () => true);
    await controller.load();
    gateway.readError = StateError('offline');
    expect(await controller.save(), true);
    expect(controller.state.acknowledged, true);
    expect(controller.state.error, contains('saved; server reload failed'));
    expect(await controller.save(), false);
    expect(gateway.writes, 1);
    gateway.readError = null;
    await controller.load();
    expect(controller.state.canEdit, true);
    controller.dispose();
  });
  for (final stage in ['load', 'write', 'reload']) {
    for (final dispose in [false, true]) {
      test(
          'late $stage after ${dispose ? 'dispose' : 'account change'} is discarded',
          () async {
        var current = true;
        final gateway = GroupReminderFake();
        final controller = FirebaseGroupRemindersController(
            scope, () => gateway, () => current);
        await controller.load();
        final gate = Completer<void>();
        if (stage == 'write') {
          gateway.writeGate = gate;
        } else {
          gateway.readGate = gate;
        }
        final pending = stage == 'load' ? controller.load() : controller.save();
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          controller.dispose();
        } else {
          current = false;
        }
        gate.complete();
        await pending;
        if (!dispose) {
          expect(controller.state.snapshot, isNull);
          expect(controller.state.draft, isNull);
          expect(controller.state.acknowledged, false);
          controller.dispose();
        }
      });
    }
  }
  test('wrong response UID/group and missing ACK record fail closed', () async {
    for (final field in ['uid', 'group', 'missing']) {
      final gateway = GroupReminderFake();
      final controller =
          FirebaseGroupRemindersController(scope, () => gateway, () => true);
      await controller.load();
      if (field == 'uid') gateway.uid = 'b';
      if (field == 'group') gateway.groupId = 'other';
      if (field == 'missing') gateway.missingAfterSave = true;
      await controller.save();
      expect(controller.state.canEdit, false);
      expect(controller.state.snapshot, isNull);
      controller.dispose();
    }
  });
  test(
      'weekly schedule stores intent and exact India timezone without date inference',
      () {
    final draft = FirebaseGroupReminderDraft.parse(
        FirebaseGroupReminderDraft.defaults.toData());
    expect(draft.initialLabel, 'Monday 09:00');
    expect(draft.deadlineLabel, 'Sunday 22:00');
    expect(draft.toData()['timezone'], 'Asia/Kolkata');
    expect(draft.copyWith(escalationEnabled: false).escalationEnabled, false);
    expect(draft.toData(), hasLength(8));
  });
  for (final field in FirebaseGroupReminderDraft.fields) {
    test('schedule rejects missing $field', () {
      final data = FirebaseGroupReminderDraft.defaults.toData()..remove(field);
      expect(
          () => FirebaseGroupReminderDraft.parse(data), throwsFormatException);
    });
  }
  test('exact schedule schema rejects extras and invalid scalar types/bounds',
      () {
    final original = FirebaseGroupReminderDraft.defaults.toData();
    expect(
        () => FirebaseGroupReminderDraft.parse({...original, 'fcmToken': 'no'}),
        throwsFormatException);
    for (final field in [
      'initialDay',
      'initialHour',
      'initialMinute',
      'deadlineDay',
      'deadlineHour',
      'deadlineMinute'
    ]) {
      final maximum = field.endsWith('Day')
          ? 6
          : field.endsWith('Hour')
              ? 23
              : 59;
      for (final value in [-1, maximum + 1, 0.5, '0', false, null]) {
        expect(
            () => FirebaseGroupReminderDraft.parse({...original, field: value}),
            throwsFormatException);
      }
    }
    for (final value in ['true', 1, null]) {
      expect(
          () => FirebaseGroupReminderDraft.parse(
              {...original, 'escalationEnabled': value}),
          throwsFormatException);
    }
    for (final value in ['UTC', 'Asia/Calcutta', null]) {
      expect(
          () => FirebaseGroupReminderDraft.parse(
              {...original, 'timezone': value}),
          throwsFormatException);
    }
  });
  test('deadline must follow start within the same Monday-based week', () {
    final original = FirebaseGroupReminderDraft.defaults.toData();
    for (final minute in [0, 1]) {
      expect(
          () => FirebaseGroupReminderDraft.parse({
                ...original,
                'initialMinute': minute,
                'deadlineDay': 0,
                'deadlineHour': 9,
                'deadlineMinute': 0
              }),
          throwsFormatException);
    }
    expect(
        FirebaseGroupReminderDraft.parse({
          ...original,
          'deadlineDay': 0,
          'deadlineHour': 9,
          'deadlineMinute': 1
        }).deadlineMinute,
        1);
  });
  test(
      'record validates scope, exact fields, revision, actor paths and precise timestamps',
      () {
    final record = FirebaseGroupReminderRecord.parse('g', scheduleData());
    expect(record.createdAt, Timestamp(100, 1));
    expect(record.updatedAt, Timestamp(101, 2));
    for (final change in [
      {'groupId': 'other'},
      {'revision': 0},
      {'revision': 1.0},
      {'revision': 2147483648},
      {'createdBy': 'a/b'},
      {'updatedBy': ''},
      {'createdAt': 'now'},
      {'updatedAt': null},
      {'updatedAt': Timestamp(99, 0)},
      {'extra': true}
    ]) {
      expect(
          () => FirebaseGroupReminderRecord.parse(
              'g', {...scheduleData(), ...change}),
          throwsA(anything));
    }
    for (final field in scheduleData().keys) {
      final data = scheduleData()..remove(field);
      expect(() => FirebaseGroupReminderRecord.parse('g', data),
          throwsA(anything));
    }
  });
}
