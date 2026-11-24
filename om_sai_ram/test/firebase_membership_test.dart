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
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignments_provider.dart';
import 'package:om_sai_ram/features/firebase_chat/providers/firebase_chat_provider.dart';
import 'package:om_sai_ram/features/firebase_highlights/providers/firebase_highlights_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/providers/firebase_tasks_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firebase_task_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/providers/firebase_moderation_provider.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firebase_moderation_models.dart';
import 'package:om_sai_ram/features/firebase_membership/data/firebase_membership_models.dart';
import 'package:om_sai_ram/features/firebase_membership/data/firestore_membership_gateway.dart';
import 'package:om_sai_ram/features/firebase_membership/providers/firebase_membership_provider.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_groups_test.dart' as groups;
import 'firebase_assignments_test.dart' as assignments;
import 'group_home_overrides.dart';

const binding = (uid: 'a', groupId: 'g');
class FakeMembership implements FirebaseMembershipGateway {
  final restorations = <FirebaseDeparture>[];
  @override
  Future<FirebaseDeparture> departure(String groupId, String targetUid) async {
    if (error != null) throw error!;
    return FirebaseDeparture.parse(groupId, targetUid, {'userId': targetUid, 'removedBy': 'a',
      'removedAt': Timestamp.fromDate(groups.now), 'reason': 'removed'});
  }
  @override
  Future<void> restore(FirebaseDeparture baseline) async {
    restorations.add(baseline);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    onWrite?.call();
  }
  final calls = <({String group, String target, FirebaseDepartureReason reason})>[];
  Completer<void>? gate;
  Object? error;
  void Function()? onWrite;
  Future<void> write(String group, String target, FirebaseDepartureReason reason) async {
    calls.add((group: group, target: target, reason: reason));
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    onWrite?.call();
  }
  @override
  Future<void> leave(String groupId) => write(groupId, 'a', FirebaseDepartureReason.left);
  @override
  Future<void> remove(String groupId, String targetUid) => write(groupId, targetUid, FirebaseDepartureReason.removed);
}
class MembershipGroups extends groups.FakeGroups {
  String creator = 'creator';
  Map<String, dynamic> groupOverrides = {};
  final removed = <String>{};
  bool paged = false;
  FirebaseGroupRole targetRole = FirebaseGroupRole.member;
  @override
  Future<FirebaseGroupDetail> detail(String groupId, {int pageSize = 20, String? cursor}) async {
    cursors.add(cursor); check();
    if (detailGate != null) return detailGate!.future;
    return FirebaseGroupDetail(FirebaseGroup.parse('g', {...groups.groupData(), 'createdBy': creator, ...groupOverrides}),
      FirebaseMembership('a', role, groups.now), FirebasePage([
        if (cursor == null) FirebaseMembership('a', role, groups.now),
        if (!removed.contains('b') && (!paged || cursor != null)) FirebaseMembership('b', targetRole, groups.now),
      ], cursor: cursor == null ? 'a' : 'b', hasMore: paged && cursor == null));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final reason in FirebaseDepartureReason.values) {
    test('${reason.name} clears first ACK remains separate from reload', () async {
      final gateway = FakeMembership();
      var cleared = 0, invalidated = 0, reloaded = 0;
      final controller = FirebaseMembershipController(() => gateway, binding, () => true,
        () => cleared++, () => invalidated++, () async { reloaded++; return 'offline'; });
      expect(await controller.depart(reason == FirebaseDepartureReason.left ? 'a' : 'b', reason), isTrue);
      expect(cleared, 1); expect(invalidated, 1); expect(reloaded, reason == FirebaseDepartureReason.left ? 0 : 1);
      expect(controller.state.acknowledged, isTrue);
      expect(controller.state.error, reason == FirebaseDepartureReason.left ? isNull : contains('acknowledged'));
      await controller.depart(reason == FirebaseDepartureReason.left ? 'a' : 'b', reason);
      expect(gateway.calls.length, 1); controller.dispose();
    });
    test('${reason.name} delayed write double request rejected and logout discards ACK', () async {
      var current = true; var invalidated = 0;
      final gateway = FakeMembership()..gate = Completer();
      final controller = FirebaseMembershipController(() => gateway, binding, () => current,
        () {}, () => invalidated++, () async => null);
      final target = reason == FirebaseDepartureReason.left ? 'a' : 'b';
      final request = controller.depart(target, reason);
      expect(controller.state.busy, isTrue);
      expect(await controller.depart(target, reason), isFalse);
      current = false; gateway.gate!.complete(); expect(await request, isFalse);
      expect(gateway.calls.length, 1); expect(invalidated, 0);
      expect(controller.state.acknowledged, isFalse); expect(controller.state.busy, isFalse); controller.dispose();
    });
  }
  test('ambiguous error never retries automatically or on repeated confirm before refresh', () async {
    final gateway = FakeMembership()..error = StateError('transport');
    final controller = FirebaseMembershipController(() => gateway, binding, () => true, () {}, () {}, () async => null);
    await controller.depart('b', FirebaseDepartureReason.removed);
    await controller.depart('b', FirebaseDepartureReason.removed);
    expect(gateway.calls.length, 1); expect(controller.state.verifyBeforeRetry, isTrue);
    expect(controller.state.acknowledged, isFalse);
    controller.verifiedRefresh(); gateway.error = null;
    expect(await controller.depart('b', FirebaseDepartureReason.removed), isTrue); controller.dispose();
  });
  test('disposed delayed write cannot invalidate old data or reload', () async {
    final gateway = FakeMembership()..gate = Completer();
    final controller = FirebaseMembershipController(() => gateway, binding, () => true,
      () {}, () => fail('invalidated'), () async { fail('reloaded'); });
    final request = controller.depart('b', FirebaseDepartureReason.removed);
    controller.dispose(); gateway.gate!.complete(); expect(await request, isFalse);
  });

  test('ACK invalidates all session family variants without SDK deletion or reads', () async {
    final auth = authentication.FakeGateway()..profile = 'Private';
    final gateway = FakeMembership();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(MembershipGroups()),
      firebaseMembershipGatewayProvider.overrideWithValue(gateway),
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
      firebaseChatProvider(binding).notifier,
      firebaseHighlightsProvider(binding).notifier,
      firebaseTasksProvider((uid: 'a', options: defaultTaskOptions)).notifier,
      firebaseModerationProvider((uid: 'a', groupId: 'g', messageId: 'z')).notifier,
      for (final kind in FirebaseModerationTargetKind.values)
        firebaseTargetModerationProvider((scope: (uid: 'a', groupId: 'g', messageId: 'z'), kind: kind)).notifier,
    ];
    for (final provider in providers) { container.listen(provider, (_, __) {}); }
    final before = [for (final provider in providers) container.read(provider)];
    container.listen(firebaseMembershipProvider(binding), (_, __) {});
    expect(await container.read(firebaseMembershipProvider(binding).notifier).depart('a', FirebaseDepartureReason.left), isTrue);
    for (var i = 0; i < providers.length; i++) {
      expect(identical(before[i], container.read(providers[i])), isFalse);
    }
    expect(gateway.calls.length, 1);
    container.dispose(); await auth.changes.close();
  });

  test('clearing detail cancels old inflight roster generation', () async {
    final gateway = MembershipGroups()..detailGate = Completer();
    final controller = FirebaseGroupsController(gateway, binding, () => true);
    final request = controller.refresh(); controller.clearForDeparture();
    gateway.detailGate!.complete(groups.detailFor(FirebaseGroupRole.admin)); await request;
    expect(controller.state.detail, isNull); expect(controller.state.busy, isFalse); controller.dispose();
  });
  test('restoration ACK survives reload failure and prevents resend; old-group baseline is rejected', () async {
    final gateway = FakeMembership();
    final baseline = await gateway.departure('g', 'b');
    final controller = FirebaseMembershipController(() => gateway, binding, () => true, () {}, () {}, () async => 'offline');
    expect(await controller.restore(baseline), true);
    expect(controller.state.acknowledged, true); expect(controller.state.error, contains('Restoration write acknowledged'));
    expect(await controller.restore(baseline), false); expect(gateway.restorations.length, 1);
    controller.dispose();
    final wrong = FirebaseMembershipController(() => gateway, binding, () => true, () {}, () {}, () async => null);
    expect(await wrong.restore(await gateway.departure('other', 'b')), false);
    expect(gateway.restorations.length, 1); wrong.dispose();
  });
  test('account switch during restoration discards ACK and skips reload', () async {
    var current = true, reloads = 0;
    final gateway = FakeMembership()..gate = Completer();
    final baseline = await gateway.departure('g', 'b');
    final controller = FirebaseMembershipController(() => gateway, binding, () => current,
      () {}, () {}, () async { reloads++; return null; });
    final pending = controller.restore(baseline); current = false; gateway.gate!.complete();
    expect(await pending, false); expect(reloads, 0); expect(controller.state.acknowledged, false); controller.dispose();
  });

  Future<({ProviderContainer container, authentication.FakeGateway auth, MembershipGroups groups, FakeMembership membership})>
      mount(WidgetTester tester, {FirebaseGroupRole role = FirebaseGroupRole.admin,
        FirebaseGroupRole targetRole = FirebaseGroupRole.member, String creator = 'creator', bool routed = false, bool paged = false}) async {
    tester.view.physicalSize = const Size(1100, 1600); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = 'Private name';
    final groupGateway = MembershipGroups()..role = role..targetRole = targetRole..creator = creator..paged = paged;
    final membership = FakeMembership()..onWrite = () => groupGateway.removed.add('b');
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(groupGateway),
      firebaseMembershipGatewayProvider.overrideWithValue(membership),
      ...groupHomeOverrides(),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth accessed')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API accessed')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', 'private@example.com')); await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: routed ? MaterialApp.router(routerConfig: container.read(routerProvider)) :
        const MaterialApp(home: FirebaseGroupsScreen(groupId: 'g'))));
    if (routed) container.read(routerProvider).go('/groups/g/members');
    await tester.pumpAndSettle();
    addTearDown(() async { await tester.pumpWidget(const SizedBox()); container.dispose(); await auth.changes.close(); });
    return (container: container, auth: auth, groups: groupGateway, membership: membership);
  }
  for (final role in FirebaseGroupRole.values) {
    for (final targetRole in FirebaseGroupRole.values) {
      testWidgets('${role.name} detail controls targeting ${targetRole.name} actual roles privacy', (tester) async {
        await mount(tester, role: role, targetRole: targetRole);
        expect(find.text('Leave group'), role == FirebaseGroupRole.admin ? findsNothing : findsOneWidget);
        expect(find.byKey(const ValueKey('remove-member-b')), role == FirebaseGroupRole.admin ||
          (role == FirebaseGroupRole.groupLead && targetRole == FirebaseGroupRole.member) ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('remove-member-a')), findsNothing);
        expect(find.text('Private name'), findsNothing); expect(find.text('private@example.com'), findsNothing);
      });
    }
    testWidgets('creator ${role.name} cannot leave and creator target cannot be removed', (tester) async {
      final env = await mount(tester, role: role, creator: 'a');
      expect(find.text('Leave group'), findsNothing);
      env.groups.creator = 'b';
      await env.container.read(firebaseGroupsProvider(binding).notifier).refresh(); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('remove-member-b')), findsNothing);
    });
  }
  testWidgets('cancel explicit UID policy warning sends no request', (tester) async {
    final env = await mount(tester);
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    expect(find.textContaining('Target UID: b'), findsOneWidget);
    expect(find.textContaining('Only an admin can explicitly restore'), findsOneWidget);
    expect(find.textContaining('not account deletion or privacy erasure'), findsOneWidget);
    expect(find.textContaining('previously downloaded data is not erased'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(env.membership.calls, isEmpty);
  });
  Future<void> reviewRestore(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('restore-member'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-member'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('restore-member-uid')), 'b');
    await tester.tap(find.text('Review departure')); await tester.pumpAndSettle();
  }
  testWidgets('restoration review cancel is write-free; explicit confirmation ACK refreshes fresh member', (tester) async {
    final env = await mount(tester); env.groups.removed.add('b');
    env.membership.onWrite = () => env.groups.removed.remove('b');
    await reviewRestore(tester);
    expect(find.textContaining('Old assignments and progress remain history-only'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(env.membership.restorations, isEmpty);
    await reviewRestore(tester); await tester.tap(find.byKey(const Key('confirm-member-restoration'))); await tester.pumpAndSettle();
    expect(env.membership.restorations.single.uid, 'b'); expect(env.membership.restorations.single.revision, 0);
    expect(find.byKey(const Key('departure-ack')), findsOneWidget); expect(env.groups.removed, isEmpty);
  });
  testWidgets('restoration requires fresh review after target changes and cancels on account switch', (tester) async {
    final env = await mount(tester); await reviewRestore(tester);
    await tester.enterText(find.byKey(const Key('restore-member-uid')), 'c'); await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('confirm-member-restoration'))).onPressed, isNull);
    env.auth.emit(const FirebaseIdentity('other', null)); await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-member-restoration')), findsNothing); expect(env.membership.restorations, isEmpty);
  });
  testWidgets('restoration review closes when admin role is revoked', (tester) async {
    final env = await mount(tester); await reviewRestore(tester);
    env.groups.role = FirebaseGroupRole.member;
    await env.container.read(firebaseGroupsProvider(binding).notifier).refresh(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-member-restoration')), findsNothing); expect(env.membership.restorations, isEmpty);
  });
  testWidgets('restoration confirmation fits narrow screen at double text', (tester) async {
    await mount(tester); await reviewRestore(tester);
    tester.view.physicalSize = const Size(320, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
  });
  testWidgets('confirm removal ACK refreshes head removes row no extra write', (tester) async {
    final env = await mount(tester, paged: true);
    await tester.tap(find.text('Next members page')); await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pumpAndSettle();
    expect(env.membership.calls.single, (group: 'g', target: 'b', reason: FirebaseDepartureReason.removed));
    expect(env.groups.cursors, [null, 'a', null]);
    expect(find.byKey(const Key('departure-ack')), findsOneWidget);
    expect(find.text('Member 2'), findsNothing); expect(find.text('You'), findsOneWidget);
  });
  testWidgets('pending write clears roster and group; controls disable double confirm', (tester) async {
    final env = await mount(tester); env.membership.gate = Completer();
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pump();
    expect(find.text('b'), findsNothing); expect(find.text('Reading circle'), findsNothing);
    expect(find.text('Confirm departure'), findsNothing); expect(env.membership.calls.length, 1);
    final refresh = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Refresh'));
    expect(refresh.onPressed, isNull);
    env.membership.gate!.complete(); await tester.pumpAndSettle();
  });
  testWidgets('ACK with roster reload failure remains ACK no rollback/repeat or stale data', (tester) async {
    final env = await mount(tester);
    env.membership.onWrite = () => env.groups.error = StateError('offline');
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('departure-ack')), findsOneWidget);
    expect(find.textContaining('roster refresh unavailable'), findsOneWidget);
    expect(find.text('b'), findsNothing); expect(find.text('Reading circle'), findsNothing);
    env.groups.error = null;
    await tester.tap(find.text('Refresh')); await tester.pumpAndSettle();
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pumpAndSettle();
    expect(env.membership.calls.length, 1);
  });
  testWidgets('write error clears roster/group and never displays ACK', (tester) async {
    final env = await mount(tester); env.membership.error = StateError('denied');
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('departure-error')), findsOneWidget);
    expect(find.byKey(const Key('departure-ack')), findsNothing);
    expect(find.text('b'), findsNothing); expect(find.text('Reading circle'), findsNothing);
  });
  for (final logout in [true, false]) {
    testWidgets('old dialog ${logout ? 'logout' : 'new account'} never confirms new actor', (tester) async {
      final env = await mount(tester);
      await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
      env.auth.emit(logout ? null : const FirebaseIdentity('new', 'new@example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm departure'), findsNothing);
      expect(env.membership.calls, isEmpty);
      await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    });
  }
  testWidgets('role revoked while dialog open disables confirmation before gateway', (tester) async {
    final env = await mount(tester);
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    env.groups.role = FirebaseGroupRole.member;
    await env.container.read(firebaseGroupsProvider(binding).notifier).refresh(); await tester.pumpAndSettle();
    expect(find.text('Confirm departure'), findsNothing); expect(env.membership.calls, isEmpty);
  });
  testWidgets('self leave navigates My groups refreshes index not forbidden detail', (tester) async {
    final env = await mount(tester, role: FirebaseGroupRole.member, routed: true);
    await tester.tap(find.text('Leave group')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pumpAndSettle();
    expect(env.container.read(routerProvider).routeInformationProvider.value.uri.path, '/groups');
    expect(find.text('My reading groups'), findsOneWidget); expect(env.groups.cursors, [null, null]);
    expect(env.membership.calls.single.reason, FirebaseDepartureReason.left);
    expect(find.textContaining('You have left the group.'), findsOneWidget);
  });
  testWidgets('logout during pending confirmation action discards old UID state', (tester) async {
    final env = await mount(tester); env.membership.gate = Completer();
    await tester.tap(find.text('Remove member')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm departure')); await tester.pump();
    env.auth.emit(null); await tester.pumpAndSettle();
    env.membership.gate!.complete(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('departure-ack')), findsNothing); expect(env.groups.cursors, [null]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('existing assignment route drops removed roster selection on next server refresh', (tester) async {
    final auth = authentication.FakeGateway()..profile = 'Private';
    final groupGateway = MembershipGroups();
    final assignmentGateway = assignments.FakeAssignments();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(groupGateway),
      firebaseAssignmentsGatewayProvider.overrideWithValue(assignmentGateway),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth accessed')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API accessed')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null)); await tester.pump();
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    router.go('/groups/g/assignments?member=b&week=1'); await tester.pumpAndSettle();
    expect(assignmentGateway.reads.last.memberUid, 'b');
    groupGateway.removed.add('b');
    await tester.tap(find.text('Refresh roster')); await tester.pumpAndSettle();
    expect(assignmentGateway.reads.last.memberUid, 'a');
    expect(find.textContaining('Read-only progress.'), findsNothing);
    // This only proves a refreshed local roster clears the selected widget;
    // another client's departure is not a live push or historical erasure.
    await tester.pumpWidget(const SizedBox()); container.dispose(); await auth.changes.close();
  });
}