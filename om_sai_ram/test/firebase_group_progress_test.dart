import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_group_progress/data/firebase_group_progress.dart';
import 'package:om_sai_ram/features/firebase_group_progress/providers/firebase_group_progress_provider.dart';
import 'firebase_groups_test.dart' as groups;
import 'firebase_member_display_test.dart' as names;
import 'firebase_assignments_test.dart' as assignments;
import 'firebase_auth_mode_test.dart' as authentication;

const binding = (uid: 'a', groupId: 'g', week: 3);

class ProgressGroups extends Fake implements FirebaseGroupsGateway {
  final requests = <({int size, String? cursor})>[];
  List<FirebaseMembership> members = [
    groups.detailFor(FirebaseGroupRole.member).self
  ];
  bool more = false;
  @override
  Future<FirebaseGroupDetail> detail(String groupId,
      {int pageSize = 20, String? cursor}) async {
    requests.add((size: pageSize, cursor: cursor));
    final base = groups.detailFor(FirebaseGroupRole.member);
    return FirebaseGroupDetail(
        base.group,
        base.self,
        FirebasePage(members,
            cursor: members.isEmpty ? cursor : members.last.uid,
            hasMore: more));
  }
}

class ProgressAssignments extends Fake implements FirebaseAssignmentsGateway {
  final requests = <FirebaseAssignmentsScope>[];
  Object? error;
  Completer<void>? gate;
  @override
  Future<FirebaseAssignmentsResult> read(FirebaseAssignmentsScope scope) async {
    requests.add(scope);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    final detail = groups.detailFor(FirebaseGroupRole.member);
    final member = FirebaseMembership(
        scope.memberUid, FirebaseGroupRole.member, detail.self.joinedAt);
    return FirebaseAssignmentsResult(detail.group, detail.self, member, [
      FirebaseAssignment.parse(
          scope, '1', assignments.assignmentData(scope: scope, chapter: 1))
    ]);
  }
}

void main() {
  test('bounded overview composes exact member/week reads and page-only counts',
      () async {
    final roster = ProgressGroups();
    final rows = ProgressAssignments();
    final display = names.FakeDisplays();
    final gateway =
        FirebaseGroupProgressGateway(roster, rows, display, () => true);
    final page = await gateway.read(binding);
    expect(roster.requests.single, (size: 10, cursor: null));
    expect(rows.requests.single,
        (uid: 'a', groupId: 'g', memberUid: 'a', week: 3));
    expect(page.summary.total, 1);
    expect(page.summary.notStarted, 1);
    expect(page.members.single.sharedName, isNull);
    final location = Uri.parse(groupProgressAssignmentsLocation(binding, 'a'));
    expect(location.path, '/groups/g/assignments');
    expect(location.queryParameters, {'member': 'a', 'week': '3'});
  });
  test('empty next page retains cursor and makes no names/assignment calls',
      () async {
    final roster = ProgressGroups()..members = [];
    final rows = ProgressAssignments();
    final display = names.FakeDisplays();
    final page =
        await FirebaseGroupProgressGateway(roster, rows, display, () => true)
            .read(binding, cursor: 'z');
    expect(page.detail.members.cursor, 'z');
    expect(page.summary.total, 0);
    expect(rows.requests, isEmpty);
    expect(display.reads, isEmpty);
  });
  test('invalid week rejects before any reads', () async {
    final roster = ProgressGroups();
    final gateway = FirebaseGroupProgressGateway(
        roster, ProgressAssignments(), names.FakeDisplays(), () => true);
    await expectLater(
        gateway.read((uid: 'a', groupId: 'g', week: 0)), throwsFormatException);
    expect(roster.requests, isEmpty);
  });
  test('assignment links encode group and UID once without losing week', () {
    final location = Uri.parse(groupProgressAssignmentsLocation(
        (uid: 'a', groupId: 'group % space', week: 10000), 'uid & space'));
    expect(location.pathSegments, ['groups', 'group % space', 'assignments']);
    expect(
        location.queryParameters, {'member': 'uid & space', 'week': '10000'});
  });
  test('over-limit and unordered rosters fail before names or assignments',
      () async {
    for (final uids in [
      List.generate(11, (index) => 'b${index.toString().padLeft(2, '0')}'),
      ['z', 'b'],
      ['b', 'b']
    ]) {
      final roster = ProgressGroups()
        ..members = [
          for (final uid in uids)
            FirebaseMembership(uid, FirebaseGroupRole.member, groups.now)
        ];
      final rows = ProgressAssignments();
      final display = names.FakeDisplays();
      await expectLater(
          FirebaseGroupProgressGateway(roster, rows, display, () => true)
              .read(binding),
          throwsFormatException);
      expect(rows.requests, isEmpty);
      expect(display.reads, isEmpty);
    }
  });
  test(
      'counts cover ten displayed members only and full page permits an empty terminal page',
      () async {
    final roster = ProgressGroups()
      ..more = true
      ..members = [
        for (var index = 0; index < 10; index++)
          FirebaseMembership('b0$index', FirebaseGroupRole.member, groups.now)
      ];
    final rows = ProgressAssignments();
    final display = names.FakeDisplays()..rows = [names.name('b01', 'Opt-in')];
    final gateway =
        FirebaseGroupProgressGateway(roster, rows, display, () => true);
    final page = await gateway.read(binding);
    expect(page.summary.total, 10);
    expect(page.members[1].sharedName!.displayName, 'Opt-in');
    expect(page.detail.members.cursor, 'b09');
    expect(rows.requests.length, 10);
    roster.more = false;
    roster.members = [];
    final terminal =
        await gateway.read(binding, cursor: page.detail.members.cursor);
    expect(terminal.members, isEmpty);
    expect(terminal.detail.members.hasMore, isFalse);
    expect(roster.requests.last.cursor, 'b09');
  });
  test(
      'failed refresh clears old page before await, no partial results and retry preserves cursor',
      () async {
    final roster = ProgressGroups();
    final rows = ProgressAssignments();
    final controller = FirebaseGroupProgressController(
        FirebaseGroupProgressGateway(
            roster, rows, names.FakeDisplays(), () => true),
        binding,
        () => true);
    await controller.refresh();
    expect(controller.state.page, isNotNull);
    roster.members = [
      FirebaseMembership('z', FirebaseGroupRole.member, groups.now)
    ];
    rows.error = StateError('offline');
    rows.gate = Completer();
    final request = controller.refresh(cursor: 'b');
    expect(controller.state.page, isNull);
    expect(controller.state.busy, isTrue);
    rows.gate!.complete();
    await request;
    expect(controller.state.page, isNull);
    expect(controller.state.error, isNotNull);
    rows.error = null;
    await controller.refresh();
    expect(roster.requests.last.cursor, 'b');
    await controller.refresh(restart: true);
    expect(roster.requests.last.cursor, isNull);
    controller.dispose();
  });
  test('shared-name failure discards entire overview before assignment reads',
      () async {
    final rows = ProgressAssignments();
    final display = names.FakeDisplays()..readError = StateError('denied');
    await expectLater(
        FirebaseGroupProgressGateway(
            ProgressGroups(), rows, display, () => true).read(binding),
        throwsStateError);
    expect(rows.requests, isEmpty);
  });
  test('account switch during assignment read suppresses old page and error',
      () async {
    var current = true;
    final rows = ProgressAssignments()..gate = Completer();
    final controller = FirebaseGroupProgressController(
        FirebaseGroupProgressGateway(
            ProgressGroups(), rows, names.FakeDisplays(), () => current),
        binding,
        () => current);
    final request = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    current = false;
    rows.gate!.complete();
    await request;
    expect(controller.state.page, isNull);
    expect(controller.state.error, isNull);
    expect(controller.state.busy, isFalse);
    controller.dispose();
  });

  Future<
      ({
        ProviderContainer container,
        authentication.FakeGateway auth,
        ProgressAssignments rows
      })> mount(WidgetTester tester, {String week = '3'}) async {
    final auth = authentication.FakeGateway()..profile = 'PRIVATE';
    final rows = ProgressAssignments();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(ProgressGroups()),
      firebaseAssignmentsGatewayProvider.overrideWithValue(rows),
      firebaseMemberDisplayGatewayProvider.overrideWithValue(
          names.FakeDisplays()..rows = [names.name('a', 'Shared name')]),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth accessed')),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API accessed')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            MaterialApp.router(routerConfig: container.read(routerProvider))));
    container.read(routerProvider).go('/groups/g/progress?week=$week');
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await auth.changes.close();
    });
    return (container: container, auth: auth, rows: rows);
  }

  testWidgets(
      'guarded route displays exact UID, opt-in name and selected-week assignment link',
      (tester) async {
    final fixture = await mount(tester);
    expect(find.text('Shared name'), findsWidgets);
    expect(find.text('UID: a'), findsNothing);
    expect(find.byKey(const Key('progress-page-totals')), findsOneWidget);
    expect(find.text('PRIVATE'), findsNothing);
    await tester.tap(find.byTooltip('Readings for Shared name, week 3'));
    await tester.pumpAndSettle();
    expect(fixture.rows.requests.last.week, 3);
    expect(fixture.rows.requests.last.memberUid, 'a');
  });
  testWidgets(
      'invalid deep-linked week does not read progress and logout clears protected page',
      (tester) async {
    final fixture = await mount(tester, week: 'bad');
    expect(fixture.rows.requests, isEmpty);
    expect(
        find.text('Select a valid group and week (1-10000).'), findsOneWidget);
    expect(find.byTooltip('Back to group'), findsOneWidget);
    fixture.auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.text('Reading this week'), findsNothing);
  });
  testWidgets(
      'week selection changes exact scope and invalid form makes no reads',
      (tester) async {
    final fixture = await mount(tester);
    final before = fixture.rows.requests.length;
    await tester.enterText(find.byKey(const Key('progress-week')), '0');
    await tester.tap(find.text('Show this week'));
    await tester.pumpAndSettle();
    expect(fixture.rows.requests.length, before);
    await tester.enterText(find.byKey(const Key('progress-week')), '7');
    await tester.tap(find.text('Show this week'));
    await tester.pumpAndSettle();
    expect(fixture.rows.requests.last.week, 7);
    expect(find.byTooltip('Readings for Shared name, week 7'), findsOneWidget);
  });
  testWidgets('overview remains usable at narrow width and large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await mount(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp.router(
            routerConfig: fixture.container.read(routerProvider),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('progress-member-a')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('progress-member-a')),
            matching: find.text('Shared name')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
