import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/presentation/firebase_groups_screen.dart';
import 'package:om_sai_ram/features/firebase_groups/providers/firebase_groups_provider.dart';
import 'package:om_sai_ram/features/firebase_group_admin/data/firebase_group_admin_models.dart';
import 'package:om_sai_ram/features/firebase_group_admin/data/firestore_group_admin_gateway.dart';
import 'package:om_sai_ram/features/firebase_group_admin/providers/firebase_group_admin_provider.dart';
import 'package:om_sai_ram/features/firebase_group_admin/presentation/firebase_group_settings_screen.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignments_provider.dart';
import 'package:om_sai_ram/features/firebase_chat/providers/firebase_chat_provider.dart';
import 'package:om_sai_ram/features/firebase_highlights/providers/firebase_highlights_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/providers/firebase_tasks_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firebase_task_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/providers/firebase_moderation_provider.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firebase_moderation_models.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_groups_test.dart' as groups;
import 'firebase_membership_test.dart' as membership;
import 'firebase_member_display_test.dart' as displays;
import 'group_home_overrides.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firestore_member_display_gateway.dart';

const binding = (uid: 'a', groupId: 'g');
class FakeAdmin implements FirebaseGroupAdminGateway {
  final membership.MembershipGroups groupsGateway;
  final saves = <({FirebaseGroupSettingsSnapshot baseline, FirebaseGroupSettingsDraft draft})>[];
  final roles = <({String group, String target, FirebaseGroupRole expected, FirebaseGroupRole next})>[];
  final adds = <({String group, String target})>[];
  final archives = <bool>[];
  final transfers = <String>[];
  @override
  Future<void> transferOwnership(FirebaseGroupSettingsSnapshot baseline, FirebaseMembership successor) async {
    transfers.add(successor.uid); await _write();
    raw.addAll({'ownerUid': successor.uid, 'ownershipRevision': baseline.group.ownershipRevision + 1,
      'ownershipChangedBy': 'a', 'ownershipChangedAt': Timestamp(1700000001, 123456789),
      'updatedAt': Timestamp(1700000001, 123456789)});
    groupsGateway.groupOverrides = Map.of(raw);
    groupsGateway.role = FirebaseGroupRole.groupLead; groupsGateway.targetRole = FirebaseGroupRole.admin;
  }
  int loads = 0;
  Map<String, dynamic> raw = groups.groupData();
  Completer<void>? loadGate, writeGate;
  Object? loadError, writeError;
  FakeAdmin(this.groupsGateway);
  @override
  Future<void> setArchived(FirebaseGroupSettingsSnapshot baseline, bool archived) async {
    archives.add(archived);
    await _write();
    raw.addAll({'archived': archived, 'lifecycleRevision': baseline.group.lifecycleRevision + 1,
      'lifecycleChangedBy': 'a', 'lifecycleChangedAt': Timestamp(1700000001, 123456789),
      'updatedAt': Timestamp(1700000001, 123456789)});
    groupsGateway.groupOverrides = Map.of(raw);
  }
  @override
  Future<FirebaseGroupSettingsSnapshot> load(String groupId) async {
    loads++;
    if (loadGate != null) await loadGate!.future;
    if (loadError != null) throw loadError!;
    if (groupsGateway.role != FirebaseGroupRole.admin) throw const FormatException('Only an actual group admin');
    return FirebaseGroupSettingsSnapshot.parse(groupId, raw);
  }
  Future<void> _write() async {
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
  }
  @override
  Future<void> addMember(String groupId, String targetUid) async {
    adds.add((group: groupId, target: targetUid));
    await _write();
  }
  @override
  Future<void> save(FirebaseGroupSettingsSnapshot baseline, FirebaseGroupSettingsDraft draft) async {
    saves.add((baseline: baseline, draft: draft));
    await _write();
    raw.addAll({'name': draft.name, 'description': draft.description,
      if (draft.chaptersPerWeek != null) 'chaptersPerWeek': draft.chaptersPerWeek,
      if (draft.startChapter != null) 'startChapter': draft.startChapter,
      'updatedAt': Timestamp(1700000001, 123456789)});
  }
  @override
  Future<void> changeRole(String groupId, String targetUid, FirebaseGroupRole expected, FirebaseGroupRole next) async {
    roles.add((group: groupId, target: targetUid, expected: expected, next: next));
    await _write();
    groupsGateway.targetRole = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final reloadError in [false, true]) {
    test('add member ACK and reload ${reloadError ? 'failure' : 'success'} cannot repeat before refresh', () async {
      final gateway = FakeAdmin(membership.MembershipGroups());
      final controller = FirebaseGroupAdminController(binding, () => gateway, () => true,
        () {}, () {}, () async => reloadError ? 'offline' : null);
      expect(await controller.addMember('new-uid'), isTrue);
      expect(controller.state.acknowledged, isTrue);
      expect(await controller.addMember('new-uid'), isFalse);
      expect(gateway.adds.single, (group: 'g', target: 'new-uid'));
      controller.dispose();
    });
  }
  test('uncertain add requires verification and discards account-switched result', () async {
    var current = true;
    final gateway = FakeAdmin(membership.MembershipGroups())..writeGate = Completer();
    final controller = FirebaseGroupAdminController(binding, () => gateway, () => current,
      () {}, () => fail('old invalidation'), () async => fail('old reload'));
    final request = controller.addMember('new-uid');
    expect(await controller.addMember('new-uid'), isFalse);
    current = false; gateway.writeGate!.complete();
    expect(await request, isFalse);
    expect(controller.state.acknowledged, isFalse);
    controller.dispose();
  });
  for (final settings in [false, true]) {
    test('${settings ? 'settings' : 'role'} clear before await ACK reload failure distinct and cannot repeat', () async {
      final gateway = FakeAdmin(membership.MembershipGroups());
      var cleared = 0, invalidated = 0, reloaded = 0;
      final c = FirebaseGroupAdminController(binding, () => gateway, () => true,
        () => cleared++, () => invalidated++, () async { reloaded++; return 'offline'; });
      final baseline = FirebaseGroupSettingsSnapshot.parse('g', gateway.raw);
      Future<bool> action() => settings ? c.save(baseline, FirebaseGroupSettingsDraft('Name', '', chaptersPerWeek: 2, startChapter: 1)) :
        c.changeRole('b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead);
      final request = action();
      expect(cleared, 1); expect(c.state.busy, isTrue);
      expect(await request, isTrue); expect(c.state.acknowledged, isTrue);
      expect(c.state.error, contains('acknowledged')); expect(invalidated, 1); expect(reloaded, 1);
      expect(await action(), isFalse); expect(gateway.saves.length + gateway.roles.length, 1);
      c.dispose();
    });
    for (final error in [const FormatException('stale'), StateError('transport')]) {
      test('${settings ? 'settings' : 'role'} $error failure requires manual verification no invalidation', () async {
        final gateway = FakeAdmin(membership.MembershipGroups())..writeError = error;
        final c = FirebaseGroupAdminController(binding, () => gateway, () => true,
          () {}, () => fail('invalidation on failure'), () async { fail('reload on failure'); });
        final baseline = FirebaseGroupSettingsSnapshot.parse('g', gateway.raw);
        Future<bool> action() => settings ? c.save(baseline, FirebaseGroupSettingsDraft('Name', '', chaptersPerWeek: 2, startChapter: 1)) :
          c.changeRole('b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead);
        expect(await action(), isFalse); expect(await action(), isFalse);
        expect(c.state.acknowledged, isFalse); expect(c.state.verifyBeforeRetry, isTrue);
        expect(gateway.saves.length + gateway.roles.length, 1); c.dispose();
      });
    }
    for (final end in ['logout', 'dispose']) {
      test('${settings ? 'settings' : 'role'} delayed $end discards result and blocks double tap', () async {
        var current = true;
        final gateway = FakeAdmin(membership.MembershipGroups())..writeGate = Completer();
        final c = FirebaseGroupAdminController(binding, () => gateway, () => current,
          () {}, () => fail('old invalidation'), () async { fail('old reload'); });
        final baseline = FirebaseGroupSettingsSnapshot.parse('g', gateway.raw);
        Future<bool> action() => settings ? c.save(baseline, FirebaseGroupSettingsDraft('Name', '', chaptersPerWeek: 2, startChapter: 1)) :
          c.changeRole('b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead);
        final request = action(); expect(await action(), isFalse);
        if (end == 'logout') { current = false; } else { c.dispose(); }
        gateway.writeGate!.complete(); expect(await request, isFalse);
        expect(gateway.saves.length + gateway.roles.length, 1);
        if (end == 'logout') { expect(c.state.acknowledged, isFalse); expect(c.state.busy, isFalse); c.dispose(); }
      });
    }
  }
  for (final failLoad in [false, true]) {
    test('pending load account switch discards ${failLoad ? 'error' : 'data'}', () async {
      var current = true;
      final gateway = FakeAdmin(membership.MembershipGroups())..loadGate = Completer();
      if (failLoad) gateway.loadError = StateError('old');
      final c = FirebaseGroupAdminController(binding, () => gateway, () => current, () {}, () {}, () async => null);
      final request = c.load(); current = false; gateway.loadGate!.complete(); await request;
      expect(c.state.snapshot, isNull); expect(c.state.error, isNull); expect(c.state.busy, isFalse); c.dispose();
    });
  }
  test('failed settings ACK followup load never permits automatic repeat', () async {
    final gateway = FakeAdmin(membership.MembershipGroups())..loadError = StateError('offline');
    final c = FirebaseGroupAdminController(binding, () => gateway, () => true, () {}, () {}, () async => null);
    final baseline = FirebaseGroupSettingsSnapshot.parse('g', gateway.raw);
    final draft = FirebaseGroupSettingsDraft('Name', '', chaptersPerWeek: 2, startChapter: 1);
    expect(await c.save(baseline, draft), isTrue); expect(c.state.acknowledged, isTrue);
    await c.load(); expect(c.state.acknowledged, isTrue);
    expect(await c.save(baseline, draft), isFalse); expect(gateway.saves.length, 1);
    gateway.loadError = null; await c.load(); expect(c.state.acknowledged, isFalse); c.dispose();
  });
  test('wrong group baseline controller refuses before SDK', () async {
    final gateway = FakeAdmin(membership.MembershipGroups());
    final c = FirebaseGroupAdminController(binding, () => gateway, () => true, () => fail('clear'), () {}, () async => null);
    expect(await c.save(FirebaseGroupSettingsSnapshot.parse('other', gateway.raw),
      FirebaseGroupSettingsDraft('Name', '', chaptersPerWeek: 2, startChapter: 1)), isFalse);
    expect(gateway.saves, isEmpty); c.dispose();
  });

  test('role ACK invalidates every permission/task family and refreshes roster head', () async {
    final auth = authentication.FakeGateway()..profile = 'Private';
    final groupGateway = membership.MembershipGroups(); final gateway = FakeAdmin(groupGateway);
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth), firebaseGroupsGatewayProvider.overrideWithValue(groupGateway),
      firebaseGroupAdminGatewayProvider.overrideWithValue(gateway),
      firebaseAssignmentsProvider.overrideWith((ref, scope) => FirebaseAssignmentsController(null, scope, () => false)),
      firebaseChatProvider.overrideWith((ref, scope) => FirebaseChatController(null, scope, () => false)),
      firebaseHighlightsProvider.overrideWith((ref, scope) => FirebaseHighlightsController(null, scope, () => false)),
      firebaseTasksProvider.overrideWith((ref, scope) => FirebaseTasksController(null, scope, () => false)),
      firebaseModerationProvider.overrideWith((ref, scope) => FirebaseModerationController(null, scope, () => false)),
      firebaseTargetModerationProvider.overrideWith((ref, target) => FirebaseModerationController(null, target.scope, () => false, kind: target.kind)),
      firebaseModerationRoleProvider.overrideWith((ref, scope) async => null),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null)); await Future<void>.delayed(Duration.zero);
    final providers = [
      firebaseAssignmentsProvider((uid: 'a', groupId: 'g', memberUid: 'b', week: 1)).notifier,
      firebaseAssignmentsProvider((uid: 'a', groupId: 'g', memberUid: 'a', week: 2)).notifier,
      firebaseChatProvider(binding).notifier, firebaseHighlightsProvider(binding).notifier,
      firebaseTasksProvider((uid: 'a', options: defaultTaskOptions)).notifier,
      firebaseModerationProvider((uid: 'a', groupId: 'g', messageId: 'z')).notifier,
      for (final kind in FirebaseModerationTargetKind.values)
        firebaseTargetModerationProvider((scope: (uid: 'a', groupId: 'g', messageId: 'z'), kind: kind)).notifier,
    ];
    for (final p in providers) { container.listen(p, (_, __) {}); }
    final before = [for (final p in providers) container.read(p)];
    container.listen(firebaseGroupAdminProvider(binding), (_, __) {});
    expect(await container.read(firebaseGroupAdminProvider(binding).notifier).changeRole('b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), isTrue);
    for (var i = 0; i < providers.length; i++) { expect(identical(before[i], container.read(providers[i])), isFalse); }
    expect(groupGateway.cursors.last, isNull);
    expect(container.read(firebaseGroupsProvider(binding)).detail!.members.items.last.role, FirebaseGroupRole.groupLead);
    container.dispose(); await auth.changes.close();
  });
  test('unready binding never instantiates admin or groups SDK dependencies', () async {
    final auth = authentication.FakeGateway()..readGate = Completer();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWith((ref) => throw StateError('SDK groups must not initialize')),
      firebaseGroupAdminGatewayProvider.overrideWith((ref) => throw StateError('SDK admin must not initialize')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null)); await Future<void>.delayed(Duration.zero);
    container.listen(firebaseGroupAdminProvider(binding), (_, __) {});
    final c = container.read(firebaseGroupAdminProvider(binding).notifier);
    await c.load(); expect(await c.changeRole('b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), isFalse);
    expect(c.state.snapshot, isNull);
    container.dispose(); auth.readGate!.complete('Private'); await auth.changes.close();
  });

  Future<({ProviderContainer container, authentication.FakeGateway auth, membership.MembershipGroups groups, FakeAdmin admin})>
      mount(WidgetTester tester, {FirebaseGroupRole role = FirebaseGroupRole.admin,
        FirebaseGroupRole target = FirebaseGroupRole.member, String creator = 'creator',
        bool settings = false, bool routed = false, bool pending = false,
        String groupId = 'g', String mode = 'chapter_wise', bool delayedLoad = false,
        displays.FakeDisplays? names}) async {
    tester.view.physicalSize = const Size(1200, 1600); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = 'Private name';
    if (pending) auth.readGate = Completer();
    final groupGateway = membership.MembershipGroups()..role = role..targetRole = target..creator = creator;
    final admin = FakeAdmin(groupGateway)..raw['mode'] = mode;
    if (delayedLoad) admin.loadGate = Completer();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(groupGateway),
      firebaseGroupAdminGatewayProvider.overrideWithValue(admin),
      if (names != null) firebaseMemberDisplayGatewayProvider.overrideWithValue(names),
      ...groupHomeOverrides(names: names == null),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth accessed')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API accessed')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', 'private@example.com')); await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: routed
      ? MaterialApp.router(routerConfig: container.read(routerProvider))
      : MaterialApp(home: settings ? FirebaseGroupSettingsScreen(groupId: groupId) : FirebaseGroupsScreen(groupId: groupId))));
    if (routed) container.read(routerProvider).go('/groups/${Uri.encodeComponent(groupId)}${settings ? '/settings' : ''}');
    if (delayedLoad || pending) { await tester.pump(); } else { await tester.pumpAndSettle(); }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox()); container.dispose();
      if (pending && !auth.readGate!.isCompleted) auth.readGate!.complete('Private');
      if (admin.loadGate != null && !admin.loadGate!.isCompleted) admin.loadGate!.complete();
      await auth.changes.close();
    });
    return (container: container, auth: auth, groups: groupGateway, admin: admin);
  }
  for (final role in FirebaseGroupRole.values) {
    for (final target in FirebaseGroupRole.values) {
      testWidgets('${role.name} actual role controls targeting ${target.name}', (tester) async {
        await mount(tester, role: role, target: target);
        expect(find.byKey(const Key('group-archive-action')), role == FirebaseGroupRole.admin ? findsOneWidget : findsNothing);
        expect(find.byKey(const Key('add-member')), role == FirebaseGroupRole.admin ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('change-role-b')), role == FirebaseGroupRole.admin && target != FirebaseGroupRole.admin ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('change-role-a')), findsNothing);
        expect(find.text('Private name'), findsNothing); expect(find.text('private@example.com'), findsNothing);
      });
    }
    testWidgets('direct settings route server enforces actual ${role.name} no legacy dependencies', (tester) async {
      final env = await mount(tester, role: role, settings: true, routed: true);
      expect(env.admin.loads, 1);
      expect(find.byKey(const Key('settings-name')), role == FirebaseGroupRole.admin ? findsOneWidget : findsNothing);
      if (role != FirebaseGroupRole.admin) expect(find.textContaining('Only an actual group admin'), findsOneWidget);
      expect(env.admin.saves, isEmpty);
    });
  }
  testWidgets('archive confirmation retains reads and restore is an explicit separate admin action', (tester) async {
    final fixture = await mount(tester);
    await tester.tap(find.byKey(const Key('group-archive-action'))); await tester.pumpAndSettle();
    expect(find.textContaining('Members can still see everything'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(fixture.admin.archives, isEmpty);
    await tester.tap(find.byKey(const Key('group-archive-action'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, close')); await tester.pumpAndSettle();
    expect(fixture.admin.archives, [true]);
    expect(find.byKey(const Key('group-archived')), findsOneWidget);
    expect(find.byKey(const Key('add-member')), findsNothing);
    expect(find.byKey(const ValueKey('change-role-b')), findsNothing);
    expect(find.byKey(const ValueKey('remove-member-b')), findsNothing);
    await tester.tap(find.text('Refresh')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-archive-action'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, reopen')); await tester.pumpAndSettle();
    expect(fixture.admin.archives, [true, false]);
    expect(find.byKey(const Key('group-archived')), findsNothing);
    expect(find.byKey(const Key('add-member')), findsOneWidget);
  });
  Future<void> openTransfer(WidgetTester tester) async {
    final action = find.byKey(const ValueKey('transfer-owner-b'));
    await tester.scrollUntilVisible(action, 220); await tester.pumpAndSettle();
    await tester.tap(action); await tester.pumpAndSettle();
  }
  testWidgets('ownership confirmation cancel is write-free; ACK replaces owner and removes outgoing admin controls', (tester) async {
    final env = await mount(tester, creator: 'a'); env.admin.raw['createdBy'] = 'a';
    await openTransfer(tester); expect(find.text('Hand over the group?'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(env.admin.transfers, isEmpty);
    await openTransfer(tester); await tester.tap(find.byKey(const Key('confirm-ownership-transfer'))); await tester.pumpAndSettle();
    expect(env.admin.transfers, ['b']);
    expect(find.byKey(const ValueKey('transfer-owner-b')), findsNothing);
    expect(find.byKey(const Key('group-archive-action')), findsNothing);
  });
  testWidgets('nonowner admin never sees ownership transfer controls', (tester) async {
    await mount(tester, creator: 'creator'); expect(find.byKey(const ValueKey('transfer-owner-b')), findsNothing);
  });
  testWidgets('account switch closes owner handover without dispatch', (tester) async {
    final env = await mount(tester, creator: 'a'); env.admin.raw['createdBy'] = 'a';
    await openTransfer(tester); env.auth.emit(const FirebaseIdentity('other', null)); await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-ownership-transfer')), findsNothing); expect(env.admin.transfers, isEmpty);
  });
  testWidgets('changed successor role closes handover and demands a fresh confirmation', (tester) async {
    final env = await mount(tester, creator: 'a'); env.admin.raw['createdBy'] = 'a';
    await openTransfer(tester); env.groups.targetRole = FirebaseGroupRole.groupLead;
    await env.container.read(firebaseGroupsProvider(binding).notifier).refresh(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-ownership-transfer')), findsNothing); expect(env.admin.transfers, isEmpty);
  });
  testWidgets('ownership confirmation and roster fit 320px double text', (tester) async {
    final env = await mount(tester, creator: 'a'); env.admin.raw['createdBy'] = 'a';
    await openTransfer(tester);
    tester.view.physicalSize = const Size(320, 900); tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
  });
  testWidgets('account change closes archive confirmation without writing', (tester) async {
    final fixture = await mount(tester);
    await tester.tap(find.byKey(const Key('group-archive-action'))); await tester.pumpAndSettle();
    fixture.auth.emit(const FirebaseIdentity('other', null)); await tester.pumpAndSettle();
    expect(find.text('Yes, close'), findsNothing);
    expect(fixture.admin.archives, isEmpty);
  });
  testWidgets('320px double-sized archive confirmation remains scrollable without overflow', (tester) async {
    await mount(tester);
    tester.view.physicalSize = const Size(320, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('group-archive-action')), 180); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-archive-action'))); await tester.pumpAndSettle();
    expect(find.text('Yes, close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('creator target role action protected even if member', (tester) async {
    await mount(tester, creator: 'b'); expect(find.byKey(const ValueKey('change-role-b')), findsNothing);
  });
  testWidgets('UID confirmation validates and cancels without writes then acknowledges one add', (tester) async {
    final fixture = await mount(tester);
    await tester.tap(find.byKey(const Key('add-member'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-member-uid')), 'x/y');
    await tester.tap(find.text('Confirm add member')); await tester.pumpAndSettle();
    expect(fixture.admin.adds, isEmpty);
    expect(find.text('Enter a valid Firebase UID.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('add-member-uid')), 'new-uid');
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(fixture.admin.adds, isEmpty);
    await tester.tap(find.byKey(const Key('add-member'))); await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('add-member-uid'))).controller!.text, '');
    await tester.enterText(find.byKey(const Key('add-member-uid')), ' new-uid ');
    await tester.tap(find.text('Confirm add member')); await tester.pumpAndSettle();
    expect(fixture.admin.adds.single, (group: 'g', target: 'new-uid'));
    expect(find.byKey(const Key('admin-ack')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('add-member'))).onPressed, isNull);
  });
  testWidgets('unconfirmed add disables blind retry until verified roster refresh', (tester) async {
    final fixture = await mount(tester);
    fixture.admin.writeError = StateError('unknown commit');
    await tester.tap(find.byKey(const Key('add-member'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-member-uid')), 'new-uid');
    await tester.tap(find.text('Confirm add member')); await tester.pumpAndSettle();
    expect(fixture.admin.adds.length, 1); expect(find.byKey(const Key('admin-ack')), findsNothing);
    expect(find.text('Not yet confirmed: account new-uid'), findsOneWidget);
    await tester.tap(find.text('Refresh')); await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('add-member'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('add-member'))); await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('add-member-uid'))).controller!.text, 'new-uid');
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
  });
  for (final end in ['logout', 'switch']) {
    testWidgets('$end cancels UID-bound add confirmation and destroys its draft', (tester) async {
      final fixture = await mount(tester);
      await tester.tap(find.byKey(const Key('add-member'))); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('add-member-uid')), 'old-target');
      fixture.auth.emit(end == 'logout' ? null : const FirebaseIdentity('new', null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-member-uid')), findsNothing);
      expect(fixture.admin.adds, isEmpty);
    });
  }
  testWidgets('shared names load with the roster and fall back to Member N on lookup failure', (tester) async {
    final names = displays.FakeDisplays()..rows = [displays.name('b', 'Optional public')];
    await mount(tester, names: names);
    expect(find.text('Optional public'), findsOneWidget); expect(find.text('b'), findsNothing);
    names.readError = StateError('offline');
    await tester.tap(find.text('Refresh')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('roster-names-error')), findsOneWidget);
    expect(find.textContaining('Optional public'), findsNothing);
    expect(find.text('Member 2'), findsOneWidget); expect(find.text('b'), findsNothing);
  });
  for (final target in [FirebaseGroupRole.member, FirebaseGroupRole.groupLead]) {
    testWidgets('${target.name} confirmation captures group UID expected role and ACK refreshed roster', (tester) async {
      final env = await mount(tester, target: target);
      await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
      expect(find.textContaining('Group: g\nTarget UID: b'), findsOneWidget);
      expect(find.textContaining('not guaranteed a push refresh'), findsOneWidget);
      await tester.tap(find.text('Confirm role change')); await tester.pumpAndSettle();
      expect(env.admin.roles.single, (group: 'g', target: 'b', expected: target,
        next: target == FirebaseGroupRole.member ? FirebaseGroupRole.groupLead : FirebaseGroupRole.member));
      expect(find.byKey(const Key('admin-ack')), findsOneWidget);
      final button = tester.widget<TextButton>(find.byKey(const ValueKey('change-role-b')));
      expect(button.onPressed, isNull);
      await tester.tap(find.text('Refresh')); await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('change-role-b'))).onPressed, isNotNull);
    });
  }
  testWidgets('cancel confirmation never writes', (tester) async {
    final env = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(env.admin.roles, isEmpty);
  });
  for (final replacement in [null, const FirebaseIdentity('new', null)]) {
    testWidgets('old account confirmation ${replacement?.uid ?? 'logout'} cannot execute on new session', (tester) async {
      final env = await mount(tester);
      await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
      env.auth.emit(replacement); await tester.pumpAndSettle();
      expect(find.text('Confirm role change'), findsNothing); expect(env.admin.roles, isEmpty);
      expect(find.byKey(const ValueKey('change-role-b')), findsNothing);
    });
  }
  testWidgets('session becomes pending while role dialog open removes confirmation', (tester) async {
    final env = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
    env.auth.readGate = Completer();
    final reload = env.container.read(firebaseSessionProvider.notifier).reloadProfile();
    await tester.pumpAndSettle();
    expect(find.text('Confirm role change'), findsNothing); expect(env.admin.roles, isEmpty);
    env.auth.readGate!.complete('Private'); await reload; await tester.pumpAndSettle();
  });
  testWidgets('pending role write hides old group and roster double tap guarded', (tester) async {
    final env = await mount(tester); env.admin.writeGate = Completer();
    await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm role change')); await tester.pump();
    expect(find.text('b'), findsNothing); expect(find.text('Reading circle'), findsNothing);
    expect(find.text('Group settings'), findsNothing); expect(env.admin.roles.length, 1);
    expect(await env.container.read(firebaseGroupAdminProvider(binding).notifier).changeRole('b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), isFalse);
    env.admin.writeGate!.complete(); await tester.pumpAndSettle();
  });
  testWidgets('role ACK reload failure shown distinctly no duplicate retry', (tester) async {
    final env = await mount(tester); env.groups.error = StateError('reload offline');
    await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm role change')); await tester.pumpAndSettle();
    expect(find.textContaining('Admin write acknowledged; server reload unavailable'), findsOneWidget);
    expect(find.text('b'), findsNothing); expect(env.admin.roles.length, 1);
  });
  testWidgets('manage screen settings button goes to isolated guarded settings route', (tester) async {
    final env = await mount(tester, routed: true);
    env.container.read(routerProvider).go('/groups/g/manage'); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('manage-settings'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-settings'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-name')), findsOneWidget);
    expect(find.textContaining('do not reschedule existing assignments'), findsOneWidget);
  });
  for (final pending in [false, true]) {
    testWidgets('settings ${pending ? 'pending' : 'logout'} clears forms and denies writes', (tester) async {
      final env = await mount(tester, settings: true);
      await tester.enterText(find.byKey(const Key('settings-name')), 'Unsaved secret');
      Future<void>? reload;
      if (pending) { env.auth.readGate = Completer(); reload = env.container.read(firebaseSessionProvider.notifier).reloadProfile(); }
      else { env.auth.emit(null); }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-name')), findsNothing); expect(find.text('Unsaved secret'), findsNothing);
      expect(env.admin.saves, isEmpty);
      if (pending) { env.auth.readGate!.complete('Private'); await reload; await tester.pumpAndSettle(); }
    });
  }
  testWidgets('pending direct route redirects and never loads SDK admin', (tester) async {
    final env = await mount(tester, settings: true, routed: true, pending: true);
    expect(env.admin.loads, 0); expect(find.byKey(const Key('settings-name')), findsNothing);
  });
  for (final path in ['.', '..', '__reserved__', 'a/b']) {
    testWidgets('invalid settings route $path denies before gateway', (tester) async {
      final env = await mount(tester, settings: true, routed: true, groupId: path);
      expect(env.admin.loads, 0); expect(find.byKey(const Key('settings-name')), findsNothing);
    });
  }
  for (final field in ['name', 'description', 'width', 'start']) {
    testWidgets('form strict $field validation before SDK', (tester) async {
      final env = await mount(tester, settings: true);
      await tester.enterText(find.byKey(Key('settings-$field')), switch (field) {
        'name' => ' ', 'description' => 'x' * 1001, 'width' => '49', _ => '54'});
      await tester.tap(find.text('Save settings')); await tester.pumpAndSettle();
      expect(env.admin.saves, isEmpty); expect(find.byKey(const Key('settings-name')), findsOneWidget);
    });
  }
  testWidgets('saptah label settings edit width and start like chapter-wise', (tester) async {
    final env = await mount(tester, settings: true, mode: 'saptah');
    expect(find.byKey(const Key('settings-width')), findsOneWidget);
    expect(find.textContaining('a label only'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('settings-name')), ' Saptah name ');
    await tester.tap(find.text('Save settings')); await tester.pumpAndSettle();
    expect(env.admin.saves.single.draft.chaptersPerWeek, isNotNull);
    expect(env.admin.saves.single.draft.name, 'Saptah name');
  });
  testWidgets('async rebuild never overwrites unsaved form, save retains exact raw baseline', (tester) async {
    final env = await mount(tester, settings: true);
    final original = env.admin.raw['updatedAt'];
    await tester.enterText(find.byKey(const Key('settings-name')), ' New manual name ');
    env.admin.raw['name'] = 'Background name';
    await env.container.read(firebaseGroupsProvider(binding).notifier).refresh(); await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('settings-name'))).controller!.text, ' New manual name ');
    await tester.tap(find.text('Save settings')); await tester.pumpAndSettle();
    expect(env.admin.saves.single.baseline.updatedAt, original);
    expect(env.admin.saves.single.draft.name, 'New manual name');
    expect(tester.widget<TextFormField>(find.byKey(const Key('settings-name'))).controller!.text, ' New manual name ');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save settings')).onPressed, isNull);
  });
  testWidgets('manual reload explicit discard rehydrates baseline before another save', (tester) async {
    final env = await mount(tester, settings: true);
    await tester.enterText(find.byKey(const Key('settings-name')), 'Uncommitted');
    env.admin.raw['name'] = 'New server name';
    env.admin.raw['updatedAt'] = Timestamp(1700000010, 987654321);
    await tester.tap(find.text('Reload settings (discards edits)')); await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('settings-name'))).controller!.text, 'New server name');
    await tester.tap(find.text('Save settings')); await tester.pumpAndSettle();
    expect(env.admin.saves.single.baseline.updatedAt.nanoseconds, 987654321);
  });
  testWidgets('failed save privately retains form, no automatic retry, explicit reload required', (tester) async {
    final env = await mount(tester, settings: true); env.admin.writeError = const FormatException('stale');
    await tester.enterText(find.byKey(const Key('settings-name')), 'Retained edit');
    final textController = tester.widget<TextFormField>(find.byKey(const Key('settings-name'))).controller!;
    await tester.tap(find.text('Save settings')); await tester.pumpAndSettle();
    expect(textController.text, 'Retained edit'); expect(find.text('Save settings'), findsNothing);
    expect(find.textContaining('No automatic retry'), findsOneWidget); expect(env.admin.saves.length, 1);
    env.admin.writeError = null;
    await tester.tap(find.text('Reload settings (discards edits)')); await tester.pumpAndSettle();
    await tester.tap(find.text('Save settings')); await tester.pumpAndSettle(); expect(env.admin.saves.length, 2);
  });
  testWidgets('settings acknowledged reload unavailable prevents form retry until manual server reload', (tester) async {
    final env = await mount(tester, settings: true); env.admin.loadError = StateError('offline');
    await tester.tap(find.text('Save settings')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-ack')), findsOneWidget);
    expect(find.textContaining('Do not repeat the write'), findsOneWidget); expect(find.text('Save settings'), findsNothing);
    await tester.tap(find.text('Reload settings (discards edits)')); await tester.pumpAndSettle();
    expect(env.admin.saves.length, 1); expect(find.text('Save settings'), findsNothing);
    env.admin.loadError = null;
    await tester.tap(find.text('Reload settings (discards edits)')); await tester.pumpAndSettle();
    expect(find.text('Save settings'), findsOneWidget);
  });
  testWidgets('delayed settings initial load logout cannot reveal old metadata', (tester) async {
    final env = await mount(tester, settings: true, delayedLoad: true);
    env.auth.emit(null); await tester.pump(); env.admin.loadGate!.complete(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-name')), findsNothing); expect(find.text('Reading circle'), findsNothing);
  });
  testWidgets('phone-width roster keeps UID role actions and settings usable without overflow', (tester) async {
    await mount(tester);
    tester.view.physicalSize = const Size(390, 844); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('change-role-b')), 120,
      scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
    expect(find.text('Member 2'), findsOneWidget); expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('change-role-b'))); await tester.pumpAndSettle();
    expect(find.text('Confirm role change'), findsOneWidget); expect(tester.takeException(), isNull);
  });
  testWidgets('delayed settings write new UID never shows old draft or ACK', (tester) async {
    final env = await mount(tester, settings: true); env.admin.writeGate = Completer();
    await tester.enterText(find.byKey(const Key('settings-name')), 'Old account edit');
    await tester.tap(find.text('Save settings')); await tester.pump();
    env.auth.emit(const FirebaseIdentity('new', null)); await tester.pump();
    env.admin.writeGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Old account edit'), findsNothing); expect(find.byKey(const Key('admin-ack')), findsNothing);
    expect(env.admin.saves.length, 1);
  });
}