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
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignments_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/presentation/firebase_assignments_screen.dart';
import 'package:om_sai_ram/shared/widgets/utc_schedule_date_field.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_groups_test.dart' as groups_test;
import 'group_home_overrides.dart';

const own = (uid: 'a', groupId: 'g', memberUid: 'a', week: 1);
const other = (uid: 'a', groupId: 'g', memberUid: 'public-uid-b', week: 1);
Map<String, dynamic> assignmentData(
    {FirebaseAssignmentsScope scope = own,
    int chapter = 16,
    FirebaseReadingStatus status = FirebaseReadingStatus.notStarted}) {
  final unit = FirebaseChapterUnit.fromChapter(chapter);
  return {
    'groupId': scope.groupId,
    'userId': scope.memberUid,
    'weekNumber': scope.week,
    'unitKey': unit.key,
    'chapterStart': unit.start,
    'chapterEnd': unit.end,
    'scheduledDate': null,
    'createdBy': 'a',
    'createdAt': Timestamp.fromDate(groups_test.now),
    'status': status.key,
    'progressUpdatedAt': Timestamp.fromDate(groups_test.now)
  };
}

class FakeAssignments implements FirebaseAssignmentsGateway {
  final transitions = <FirebaseAssignment>[];
  final transitionDrafts = <({bool archived, DateTime? date, String? target})>[];
  final versions = <(FirebaseAssignmentsScope, String, int), Map<String, dynamic>>{};
  @override
    Future<FirebaseAssignment> version(FirebaseAssignmentsScope scope, FirebaseChapterUnit unit, int revision) async =>
      FirebaseAssignment.parse(scope, unit.key, versions[(scope, unit.key, revision)]);
  @override
  Future<void> transition(FirebaseAssignmentsScope scope, FirebaseAssignment baseline,
      {required bool archived, required DateTime? scheduledDate, String? reassignTo}) async {
    transitions.add(baseline);
    transitionDrafts.add((archived: archived, date: scheduledDate, target: reassignTo));
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    final rows = saved.putIfAbsent(scope, () => {baseline.unit.key: assignmentData(scope: scope)});
    versions[(scope, baseline.unit.key, baseline.revision)] = Map.of(rows[baseline.unit.key]!);
    rows[baseline.unit.key] = {...rows[baseline.unit.key]!, 'archived': archived, 'revision': baseline.revision + 1,
      'changedBy': scope.uid, 'changedAt': Timestamp.fromDate(groups_test.now),
      if (!archived) 'status': 'not_started', if (!archived) 'scheduledDate': scheduledDate == null ? null : Timestamp.fromDate(scheduledDate)};
  }
  final reads = <FirebaseAssignmentsScope>[];
  final creates =
      <({FirebaseAssignmentsScope scope, String unit, DateTime? date})>[];
  final updates = <FirebaseReadingStatus>[];
  final saved = <FirebaseAssignmentsScope, Map<String, Map<String, dynamic>>>{};
  FirebaseGroupRole role = FirebaseGroupRole.admin;
  Object? error, writeError;
  FirebaseAssignmentsResult? tampered;
  final gates =
      <FirebaseAssignmentsScope, Completer<FirebaseAssignmentsResult>>{};
  Completer<void>? writeGate;
  FirebaseAssignmentsResult result(FirebaseAssignmentsScope scope) {
    final rows = saved[scope] ?? {'16-17': assignmentData(scope: scope)};
    return FirebaseAssignmentsResult(
        groups_test.detailFor(role).group,
        FirebaseMembership(scope.uid, role, groups_test.now),
        FirebaseMembership(
            scope.memberUid, FirebaseGroupRole.member, groups_test.now),
        rows.entries.map((entry) =>
            FirebaseAssignment.parse(scope, entry.key, entry.value)));
  }

  @override
  Future<FirebaseAssignmentsResult> read(FirebaseAssignmentsScope scope) async {
    reads.add(scope);
    if (error != null) throw error!;
    if (gates[scope] != null) return gates[scope]!.future;
    return tampered ?? result(scope);
  }

  @override
  Future<void> create(FirebaseAssignmentsScope scope, FirebaseChapterUnit unit,
      {required DateTime? scheduledDate}) async {
    creates.add((scope: scope, unit: unit.key, date: scheduledDate));
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    final rows =
        saved.putIfAbsent(scope, () => {'16-17': assignmentData(scope: scope)});
    if (rows.containsKey(unit.key)) {
      throw const FormatException('Assignment already exists.');
    }
    rows[unit.key] = {...assignmentData(scope: scope, chapter: unit.start),
      'scheduledDate': scheduledDate == null ? null : Timestamp.fromDate(scheduledDate)};
  }

  @override
  Future<void> updateStatus(FirebaseAssignmentsScope scope,
      FirebaseChapterUnit unit, FirebaseReadingStatus status) async {
    updates.add(status);
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    saved.putIfAbsent(
            scope, () => {'16-17': assignmentData(scope: scope)})[unit.key] =
        assignmentData(scope: scope, chapter: unit.start, status: status);
  }
}

class PagedGroups extends groups_test.FakeGroups {
  @override
  Future<FirebaseGroupDetail> detail(String groupId,
      {int pageSize = 20, String? cursor}) async {
    cursors.add(cursor);
    check();
    if (detailGate != null) return detailGate!.future;
    final detail = groups_test.detailFor(role);
    final group = FirebaseGroup.parse(
        'g', {...groups_test.groupData(), 'currentWeek': 7});
    return FirebaseGroupDetail(
        group,
        detail.self,
        FirebasePage([
          FirebaseMembership(cursor == null ? 'public-uid-b' : 'page-two',
              FirebaseGroupRole.member, groups_test.now)
        ],
            cursor: cursor == null ? 'public-uid-b' : 'page-two',
            hasMore: cursor == null));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('canonical units and strict assignment models', () {
    test('catalogue has exactly 48 unique original-number units', () {
      expect(FirebaseChapterUnit.all.length, 48);
      expect(
          FirebaseChapterUnit.all.map((unit) => unit.key).toSet().length, 48);
      expect(FirebaseChapterUnit.all.last.key, '51-53');
      expect(
          FirebaseChapterUnit.all
              .where((unit) => [17, 19, 44, 52, 53].contains(unit.start)),
          isEmpty);
    });
    for (final alias in {
      17: '16-17',
      19: '18-19',
      44: '43-44',
      52: '51-53',
      53: '51-53'
    }.entries) {
      test('inner alias ${alias.key} normalizes to ${alias.value}', () {
        expect(FirebaseChapterUnit.fromChapter(alias.key).key, alias.value);
      });
    }
    test('invalid original numbers and week bounds are rejected', () {
      for (final value in [-1, 0, 54, 1000]) {
        expect(() => FirebaseChapterUnit.fromChapter(value),
            throwsFormatException);
      }
      expect(assignmentWeek(1), 1);
      expect(assignmentWeek(10000), 10000);
      expect(() => assignmentWeek(0), throwsFormatException);
      expect(() => assignmentWeek(10001), throwsFormatException);
    });
    test('path segments reject slash reserved names and excessive UTF8 bytes',
        () {
      for (final value in ['', '.', '..', 'a/b', '__bad__', 'é' * 751]) {
        expect(() => assignmentSegment(value), throwsFormatException);
      }
    });
    test('exact eleven fields permit null date and retain UTC timestamps', () {
      expect(assignmentData().length, 11);
      final row = FirebaseAssignment.parse(own, '16-17', assignmentData());
      expect(row.scheduledDate, isNull);
      expect(row.createdAt, groups_test.now);
      expect(row.progressUpdatedAt, groups_test.now);
      expect(row.status, FirebaseReadingStatus.notStarted);
      expect(
          () => FirebaseAssignment.parse(
              own, '16-17', {...assignmentData(), 'legacyId': 99}),
          throwsFormatException);
      expect(
          () => FirebaseAssignment.parse(
              own, '16-17', assignmentData()..remove('scheduledDate')),
          throwsFormatException);
      expect(() => FirebaseAssignment.parse(own, '16-17', null),
          throwsFormatException);
    });
    test('timestamp types reject strings DateTime and pending server values',
        () {
      for (final key in ['createdAt', 'progressUpdatedAt', 'scheduledDate']) {
        for (final value in [
          '2026-10-14',
          groups_test.now,
          FieldValue.serverTimestamp()
        ]) {
          expect(
              () => FirebaseAssignment.parse(
                  own, '16-17', {...assignmentData(), key: value}),
              throwsFormatException);
        }
      }
      final row = FirebaseAssignment.parse(own, '16-17', {
        ...assignmentData(),
        'scheduledDate': Timestamp.fromDate(groups_test.now)
      });
      expect(row.scheduledDate, groups_test.now);
    });
    test('all statuses parse exactly and reject unsupported values', () {
      for (final status in FirebaseReadingStatus.values) {
        expect(
            FirebaseAssignment.parse(
                    own, '16-17', assignmentData(status: status))
                .status,
            status);
      }
      for (final value in ['done', 'COMPLETED', 1, null]) {
        expect(
            () => FirebaseAssignment.parse(
                own, '16-17', {...assignmentData(), 'status': value}),
            throwsFormatException);
      }
    });
    test('group member week unit and chapter tampering is rejected', () {
      for (final change in <Map<String, dynamic>>[
        {'groupId': 'x'},
        {'userId': 'b'},
        {'weekNumber': 2},
        {'weekNumber': '1'},
        {'chapterStart': 17},
        {'chapterStart': 52},
        {'chapterEnd': 16},
        {'chapterEnd': 17.0},
        {'unitKey': '17'},
        {'createdBy': 'a/b'},
      ]) {
        expect(
            () => FirebaseAssignment.parse(
                own, '16-17', {...assignmentData(), ...change}),
            throwsFormatException);
      }
      expect(() => FirebaseAssignment.parse(own, '17', assignmentData()),
          throwsFormatException);
    });
  });

  group('scoped controller and readiness', () {
    late auth_test.FakeGateway auth;
    late FakeAssignments assignments;
    late ProviderContainer container;
    FirebaseAssignmentsController controller(
        [FirebaseAssignmentsScope scope = own]) {
      container.listen(firebaseAssignmentsProvider(scope), (_, __) {});
      return container.read(firebaseAssignmentsProvider(scope).notifier);
    }

    setUp(() async {
      auth = auth_test.FakeGateway()..profile = 'Private';
      assignments = FakeAssignments();
      container = ProviderContainer(overrides: [
        firebaseAuthGatewayProvider.overrideWithValue(auth),
        firebaseAssignmentsGatewayProvider.overrideWithValue(assignments),
      ]);
      container.listen(firebaseSessionProvider, (_, __) {});
      auth.emit(const FirebaseIdentity('a', 'private@example.com'));
      await Future<void>.delayed(Duration.zero);
    });
    tearDown(() async {
      container.dispose();
      await auth.changes.close();
    });
    test('clears results before refresh and rejects concurrent requests',
        () async {
      final c = controller();
      await c.refresh();
      assignments.gates[own] = Completer();
      final pending = c.refresh();
      expect(c.state.busy, isTrue);
      expect(c.state.result, isNull);
      await c.refresh();
      expect(assignments.reads.length, 2);
      assignments.gates[own]!.complete(assignments.result(own));
      await pending;
      expect(c.state.busy, isFalse);
      expect(c.state.result, isNotNull);
    });
    test('permission error clears everything and retry reloads', () async {
      final c = controller();
      await c.refresh();
      assignments.error = FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
      await c.refresh();
      expect(c.state.result, isNull);
      expect(c.state.error, contains('Access denied'));
      assignments.error = null;
      await c.refresh();
      expect(c.state.result, isNotNull);
    });
    test('network errors do not expose internal details or sticky busy',
        () async {
      final c = controller();
      assignments.error = StateError('secret');
      await c.refresh();
      expect(c.state.error, isNot(contains('secret')));
      expect(c.state.busy, isFalse);
      assignments.error = null;
      await c.refresh();
      expect(c.state.result, isNotNull);
    });
    test('SDK UID mismatch without stream event refuses access', () async {
      auth.currentUser = const FirebaseIdentity('b', null);
      final c = controller();
      await c.refresh();
      expect(assignments.reads, isEmpty);
    });
    test('SDK UID drift during read discards result and resets busy', () async {
      final c = controller();
      assignments.gates[own] = Completer();
      final pending = c.refresh();
      auth.currentUser = const FirebaseIdentity('b', null);
      assignments.gates[own]!.complete(assignments.result(own));
      await pending;
      expect(c.state.result, isNull);
      expect(c.state.busy, isFalse);
    });
    test('profile-unready session never obtains assignments dependency',
        () async {
      auth.profile = null;
      auth.emit(const FirebaseIdentity('b', null));
      await Future<void>.delayed(Duration.zero);
      final c = controller((uid: 'b', groupId: 'g', memberUid: 'b', week: 1));
      await c.refresh();
      expect(assignments.reads, isEmpty);
    });
    for (final identity in <FirebaseIdentity?>[
      null,
      const FirebaseIdentity('b', null)
    ]) {
      test(
          '${identity == null ? 'logout' : 'account switch'} discards delayed result',
          () async {
        final c = controller();
        assignments.gates[own] = Completer();
        final pending = c.refresh();
        auth.emit(identity);
        await Future<void>.delayed(Duration.zero);
        assignments.gates[own]!.complete(assignments.result(own));
        await pending;
        expect(container.read(firebaseAssignmentsProvider(own)).result, isNull);
      });
    }
    test('disposed old week cannot populate new selected week', () async {
      var active = true;
      final old = FirebaseAssignmentsController(assignments, own, () => active);
      assignments.gates[own] = Completer();
      final pending = old.refresh();
      active = false;
      old.dispose();
      const next = (uid: 'a', groupId: 'g', memberUid: 'a', week: 2);
      final fresh = controller(next);
      await fresh.refresh();
      assignments.gates[own]!.complete(assignments.result(own));
      await pending;
      expect(fresh.state.result!.assignments.single.weekNumber, 2);
    });
    test('disposed old member cannot populate new selected member', () async {
      final old = FirebaseAssignmentsController(assignments, own, () => true);
      assignments.gates[own] = Completer();
      final pending = old.refresh();
      old.dispose();
      final fresh = controller(other);
      await fresh.refresh();
      assignments.gates[own]!.complete(assignments.result(own));
      await pending;
      expect(fresh.state.result!.assignments.single.userId, 'public-uid-b');
    });
    test('response scope tampering and duplicate rows fail closed', () async {
      final c = controller();
      assignments.tampered = assignments.result(other);
      await c.refresh();
      expect(c.state.result, isNull);
      expect(c.state.error, contains('scope mismatch'));
      final result = assignments.result(own);
      assignments.tampered = FirebaseAssignmentsResult(
          result.group,
          result.self,
          result.member,
          [result.assignments.single, result.assignments.single]);
      await c.refresh();
      expect(c.state.result, isNull);
    });
    for (final role in FirebaseGroupRole.values) {
      test('actual ${role.name} role controls manual creation even if creator',
          () async {
        assignments.role = role;
        final c = controller();
        await c.refresh();
        await c.create(FirebaseChapterUnit.fromChapter(1));
        expect(assignments.creates.length,
            role == FirebaseGroupRole.member ? 0 : 1);
        if (role != FirebaseGroupRole.member) {
          expect(assignments.creates.single.date, isNull);
          expect(assignments.reads.length, 2);
        }
      });
    }
    test('duplicate creation is an error with no overwrite or fake success',
        () async {
      final c = controller();
      await c.refresh();
      await c.create(FirebaseChapterUnit.fromChapter(17));
      expect(c.state.result, isNull);
      expect(c.state.error, contains('already exists'));
      expect(assignments.reads.length, 1);
      await c.refresh();
      expect(c.state.result, isNotNull);
    });
    test('dated creation ACK survives failed reloads and blocks repeat until verified', () async {
      final c = controller(); await c.refresh();
      final date = DateTime.utc(2026, 11, 1, 18, 30);
      assignments.writeGate = Completer();
      final request = c.create(FirebaseChapterUnit.fromChapter(1), scheduledDate: date);
      assignments.error = StateError('offline'); assignments.writeGate!.complete(); await request;
      expect(assignments.creates.single.date, date);
      expect(c.state.acknowledged, isTrue); expect(c.state.verifyBeforeRetry, isFalse);
      expect(c.state.error, contains('write acknowledged'));
      await c.refresh(); expect(c.state.acknowledged, isTrue);
      await c.create(FirebaseChapterUnit.fromChapter(2)); expect(assignments.creates.length, 1);
      assignments.error = null; await c.refresh(); expect(c.state.acknowledged, isFalse);
      await c.create(FirebaseChapterUnit.fromChapter(2), scheduledDate: null);
      expect(assignments.creates.length, 2); expect(assignments.creates.last.date, isNull);
    });
    test('uncertain dated creation preserves verification guard across failed refresh', () async {
      final c = controller(); await c.refresh(); assignments.writeError = StateError('unknown');
      await c.create(FirebaseChapterUnit.fromChapter(1), scheduledDate: DateTime.utc(2026, 10, 15));
      expect(c.state.acknowledged, isFalse); expect(c.state.verifyBeforeRetry, isTrue);
      assignments.error = StateError('offline'); await c.refresh(); expect(c.state.verifyBeforeRetry, isTrue);
      await c.create(FirebaseChapterUnit.fromChapter(1)); expect(assignments.creates.length, 1);
      assignments.error = null; assignments.writeError = null; await c.refresh();
      expect(c.state.verifyBeforeRetry, isFalse);
      await c.create(FirebaseChapterUnit.fromChapter(1)); expect(assignments.creates.length, 2);
    });
    test('write clears rows; reload failure is not reported as success',
        () async {
      final c = controller();
      await c.refresh();
      assignments.writeGate = Completer();
      final pending = c.create(FirebaseChapterUnit.fromChapter(1));
      expect(c.state.result, isNull);
      expect(c.state.busy, isTrue);
      await c.create(FirebaseChapterUnit.fromChapter(2));
      expect(assignments.creates.length, 1);
      assignments.error = StateError('offline');
      assignments.writeGate!.complete();
      await pending;
      expect(c.state.result, isNull);
      expect(c.state.error, isNotNull);
      expect(c.state.busy, isFalse);
      assignments.error = null;
      await c.refresh();
      expect(c.state.result!.assignments.length, 2);
    });
    test('only own assignee can write progress even when admin', () async {
      final c = controller(other);
      await c.refresh();
      await c.updateStatus(
          FirebaseChapterUnit.fromChapter(16), FirebaseReadingStatus.completed);
      expect(assignments.updates, isEmpty);
    });
    test('own status transitions both directions reload server', () async {
      final c = controller();
      await c.refresh();
      for (final status in [
        FirebaseReadingStatus.completed,
        FirebaseReadingStatus.inProgress,
        FirebaseReadingStatus.notStarted
      ]) {
        await c.updateStatus(FirebaseChapterUnit.fromChapter(16), status);
        expect(c.state.result!.assignments.single.status, status);
      }
      expect(assignments.reads.length, 4);
    });
    test('failed status write clears rows and is retryable via refresh',
        () async {
      final c = controller();
      await c.refresh();
      assignments.writeError = StateError('offline');
      await c.updateStatus(
          FirebaseChapterUnit.fromChapter(16), FirebaseReadingStatus.completed);
      expect(c.state.result, isNull);
      expect(c.state.error, isNotNull);
      assignments.writeError = null;
      await c.refresh();
      expect(c.state.result!.assignments.single.status,
          FirebaseReadingStatus.notStarted);
    });
    test('account switch during write prevents postwrite read', () async {
      final c = controller();
      await c.refresh();
      assignments.writeGate = Completer();
      final pending = c.create(FirebaseChapterUnit.fromChapter(1));
      auth.emit(const FirebaseIdentity('b', null));
      await Future<void>.delayed(Duration.zero);
      assignments.writeGate!.complete();
      await pending;
      expect(assignments.reads.length, 1);
      expect(container.read(firebaseAssignmentsProvider(own)).result, isNull);
    });
  });

  Future<
          (
            auth_test.FakeGateway,
            FakeAssignments,
            PagedGroups,
            ProviderContainer
          )>
      mount(WidgetTester tester,
          {FirebaseGroupRole role = FirebaseGroupRole.admin}) async {
    final auth = auth_test.FakeGateway()..profile = 'Private';
    final assignments = FakeAssignments()..role = role;
    final groups = PagedGroups()..role = role;
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseAssignmentsGatewayProvider.overrideWithValue(assignments),
      firebaseGroupsGatewayProvider.overrideWithValue(groups),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child:
            const MaterialApp(home: FirebaseAssignmentsScreen(groupId: 'g'))));
    auth.emit(const FirebaseIdentity('a', 'private@example.com'));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await auth.changes.close();
    });
    return (auth, assignments, groups, container);
  }

  Future<void> selectOther(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('public-uid-b • member').last);
    await tester.pumpAndSettle();
  }

  Future<void> assignmentAction(WidgetTester tester, String label) async {
    final menu = find.byKey(const ValueKey('assignment-actions-16-17'));
    await tester.scrollUntilVisible(menu, 240, scrollable: find.byType(Scrollable).first); await tester.pumpAndSettle();
    await tester.tap(menu); await tester.pumpAndSettle(); await tester.tap(find.text(label).last); await tester.pumpAndSettle();
  }
  Future<void> reloadAssignments(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Reload assignments')); await tester.pumpAndSettle();
    await tester.tap(find.text('Reload assignments')); await tester.pumpAndSettle();
  }
  testWidgets('archive cancel is write-free; confirmation locks status and retained version is readable', (tester) async {
    final (_, assignments, _, _) = await mount(tester);
    await assignmentAction(tester, 'Archive');
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(assignments.transitions, isEmpty);
    await assignmentAction(tester, 'Archive');
    await tester.tap(find.byKey(const Key('confirm-assignment-lifecycle'))); await tester.pumpAndSettle();
    expect(assignments.transitions.single.unit.key, '16-17');
    await reloadAssignments(tester);
    await assignmentAction(tester, 'Retained versions');
    expect(find.textContaining('History only - no active progress is restored.'), findsOneWidget);
    await tester.tap(find.text('Close')); await tester.pumpAndSettle();
    final status = find.byType(DropdownButtonFormField<FirebaseReadingStatus>);
    await tester.scrollUntilVisible(status, 240, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<DropdownButtonFormField<FirebaseReadingStatus>>(status).onChanged, isNull);
    expect(assignments.updates, isEmpty);
  });
  testWidgets('fresh active version starts unscheduled without inheriting archived date', (tester) async {
    final (_, assignments, _, _) = await mount(tester);
    const scope = (uid: 'a', groupId: 'g', memberUid: 'a', week: 7);
    assignments.saved[scope] = {'16-17': {...assignmentData(scope: scope), 'archived': true, 'revision': 1,
      'changedBy': 'a', 'changedAt': Timestamp.fromDate(groups_test.now), 'scheduledDate': Timestamp.fromDate(groups_test.now)}};
    await reloadAssignments(tester); await assignmentAction(tester, 'Create fresh active version');
    expect(find.text('New work will be unscheduled.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-assignment-lifecycle'))); await tester.pumpAndSettle();
    expect(assignments.transitionDrafts.single.archived, false); expect(assignments.transitionDrafts.single.date, isNull);
    expect(assignments.result(scope).assignments.single.archived, false);
    expect(assignments.result(scope).assignments.single.scheduledDate, isNull);
  });
  testWidgets('reassignment validates different exact UID and keeps explicit new date', (tester) async {
    final (_, assignments, _, _) = await mount(tester);
    await assignmentAction(tester, 'Reassign');
    await tester.enterText(find.byKey(const Key('reassignment-target')), 'a');
    await tester.tap(find.byKey(const Key('confirm-assignment-lifecycle'))); await tester.pumpAndSettle();
    expect(assignments.transitions, isEmpty);
    await tester.enterText(find.byKey(const Key('reassignment-target')), 'public-uid-b');
    final date = DateTime.utc(2026, 11, 1);
    tester.widget<UtcScheduleDateField>(find.byKey(const Key('replacement-date'))).onChanged(date);
    await tester.pumpAndSettle(); await tester.tap(find.byKey(const Key('confirm-assignment-lifecycle'))); await tester.pumpAndSettle();
    expect(assignments.transitionDrafts.single, (archived: true, date: date, target: 'public-uid-b'));
  });
  testWidgets('account switch cancels lifecycle confirmation without typed-route errors or writes', (tester) async {
    final (auth, assignments, _, _) = await mount(tester);
    await assignmentAction(tester, 'Archive'); auth.emit(const FirebaseIdentity('other', null)); await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-assignment-lifecycle')), findsNothing);
    expect(assignments.transitions, isEmpty); expect(tester.takeException(), isNull);
  });
  testWidgets('assignment lifecycle confirmation fits narrow screen and large text', (tester) async {
    await mount(tester); await assignmentAction(tester, 'Reassign');
    tester.view.physicalSize = const Size(320, 900); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
  });

  testWidgets(
      'defaults own UID and server currentWeek with self absent from page',
      (tester) async {
    final (_, assignments, _, _) = await mount(tester);
    expect(assignments.reads.single.memberUid, 'a');
    expect(assignments.reads.single.week, 7);
    expect(find.text('a (you) • admin'), findsOneWidget);
    expect(
        find.text('Bundled assignment reader • explicit assignee completion'),
        findsOneWidget);
    expect(find.text('Private'), findsNothing);
    expect(find.text('private@example.com'), findsNothing);
    expect(
        find.text('Scheduled date (UTC)'),
        findsOneWidget);
  });
  for (final role in FirebaseGroupRole.values) {
    testWidgets('${role.name} sees manual create according to actual role',
        (tester) async {
      await mount(tester, role: role);
      expect(find.text('Assign unit'),
          role == FirebaseGroupRole.member ? findsNothing : findsOneWidget);
    });
  }
  testWidgets('manual date is reviewed exactly, cancel is write-free and confirmed date persists', (tester) async {
    tester.view.physicalSize = const Size(800, 1200); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final (_, assignments, _, _) = await mount(tester);
    final date = DateTime.utc(2026, 11, 1, 18, 30);
    tester.widget<UtcScheduleDateField>(find.byKey(const Key('manual-scheduled-date'))).onChanged(date);
    await tester.pumpAndSettle(); await tester.ensureVisible(find.text('Assign unit')); await tester.pumpAndSettle();
    await tester.tap(find.text('Assign unit')); await tester.pumpAndSettle();
    expect(find.textContaining('Scheduled (UTC): ${date.toIso8601String()}'), findsOneWidget);
    expect(find.textContaining('Member UID: a\nWeek: 7\nChapters: 1'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(assignments.creates, isEmpty);
    await tester.tap(find.text('Assign unit')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm assignment')); await tester.pumpAndSettle();
    expect(assignments.creates.single.date, date); expect(assignments.creates.single.scope.week, 7);
    expect(assignments.result(assignments.creates.single.scope).assignments.firstWhere((row) => row.unit.key == '1').scheduledDate, date);
    expect(find.byKey(const Key('assignment-create-ack')), findsOneWidget);
  });
  for (final change in ['logout', 'member', 'week']) {
    testWidgets('$change cancels manual confirmation without a stale write', (tester) async {
      tester.view.physicalSize = const Size(800, 1200); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final (auth, assignments, _, _) = await mount(tester);
      await tester.ensureVisible(find.text('Assign unit')); await tester.pumpAndSettle();
      await tester.tap(find.text('Assign unit')); await tester.pumpAndSettle();
      expect(find.text('Confirm assignment'), findsOneWidget);
      if (change == 'logout') {
        auth.emit(null);
      } else if (change == 'member') {
        tester.widget<DropdownButtonFormField<String>>(find.byKey(const ValueKey('a'))).onChanged!('public-uid-b');
      } else {
        tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text = '8';
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Select week')).onPressed!();
      }
      await tester.pumpAndSettle(); expect(find.text('Confirm assignment'), findsNothing);
      expect(assignments.creates, isEmpty);
    });
  }
  testWidgets('other member readable but no status control even for admin',
      (tester) async {
    final (_, assignments, _, _) = await mount(tester);
    await selectOther(tester);
    expect(assignments.reads.last.memberUid, 'public-uid-b');
    expect(find.byType(DropdownButtonFormField<FirebaseReadingStatus>),
        findsNothing);
    expect(find.text('Assign unit'), findsOneWidget);
  });
  testWidgets(
      'member pagination uses existing cursor and retains current self option',
      (tester) async {
    final (_, assignments, groups, _) = await mount(tester);
    await selectOther(tester);
    await tester.tap(find.text('Next members page'));
    await tester.pumpAndSettle();
    expect(groups.cursors, [null, 'public-uid-b']);
    expect(find.text('a (you) • admin'), findsOneWidget);
    expect(assignments.reads.last.memberUid, 'a');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('page-two • member'), findsWidgets);
    expect(find.text('public-uid-b • member'), findsNothing);
  });
  testWidgets('week validation prevents invalid requests and permits 10000',
      (tester) async {
    final (_, assignments, _, _) = await mount(tester);
    for (final value in ['0', '10001', 'abc']) {
      await tester.enterText(find.byType(TextFormField), value);
      await tester.tap(find.text('Select week'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1–10000.'), findsOneWidget);
      expect(assignments.reads.length, 1);
    }
    await tester.enterText(find.byType(TextFormField), '10000');
    await tester.tap(find.text('Select week'));
    await tester.pumpAndSettle();
    expect(assignments.reads.last.week, 10000);
  });
  testWidgets(
      'week change discards delayed old rows and does not resurrect them',
      (tester) async {
    final (_, assignments, _, container) = await mount(tester);
    final scope = assignments.reads.single;
    assignments.gates[scope] = Completer();
    final pending =
        container.read(firebaseAssignmentsProvider(scope).notifier).refresh();
    await tester.pump();
    expect(find.byKey(const ValueKey('assignment-16-17')), findsNothing);
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('Select week'));
    await tester.pumpAndSettle();
    expect(assignments.reads.last.week, 2);
    assignments.gates[scope]!.complete(assignments.result(scope));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Selected week: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('member change discards delayed previous selection',
      (tester) async {
    final (_, assignments, _, container) = await mount(tester);
    final scope = assignments.reads.single;
    assignments.gates[scope] = Completer();
    final pending =
        container.read(firebaseAssignmentsProvider(scope).notifier).refresh();
    await tester.pump();
    await selectOther(tester);
    assignments.gates[scope]!.complete(assignments.result(scope));
    await pending;
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<FirebaseReadingStatus>),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('account change hides old workspace and delayed result',
      (tester) async {
    final (auth, assignments, _, container) = await mount(tester);
    final scope = assignments.reads.single;
    assignments.gates[scope] = Completer();
    final pending =
        container.read(firebaseAssignmentsProvider(scope).notifier).refresh();
    await tester.pump();
    auth.profile = null;
    auth.emit(const FirebaseIdentity('b', null));
    await tester.pumpAndSettle();
    assignments.gates[scope]!.complete(assignments.result(scope));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Ready Firebase session required.'), findsOneWidget);
    expect(find.byKey(const ValueKey('assignment-16-17')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('error retry displays only a new successful response',
      (tester) async {
    final (_, assignments, _, _) =
        await mount(tester, role: FirebaseGroupRole.member);
    assignments.error =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await tester.tap(find.text('Reload assignments'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assignments-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('assignment-16-17')), findsNothing);
    assignments.error = null;
    await tester.tap(find.text('Reload assignments'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assignments-error')), findsNothing);
    expect(find.byKey(const ValueKey('assignment-16-17')), findsOneWidget);
  });
  testWidgets('guarded assignments route never accesses legacy auth or API',
      (tester) async {
    final auth = auth_test.FakeGateway();
    final assignments = FakeAssignments();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(PagedGroups()),
      firebaseAssignmentsGatewayProvider.overrideWithValue(assignments),
      ...groupHomeOverrides(assignments: false),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth accessed')),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API accessed')),
    ]);
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    auth.emit(const FirebaseIdentity('a', null));
    await tester.pumpAndSettle();
    router.go('/groups/g/assignments');
    await tester.pumpAndSettle();
    expect(find.byType(FirebaseAssignmentsScreen), findsNothing);
    expect(assignments.reads, isEmpty);
    auth.profile = 'Private';
    await container.read(firebaseSessionProvider.notifier).reloadProfile();
    router.go('/groups/g');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('group-my-schedule')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('group-my-schedule')));
    await tester.pumpAndSettle();
    expect(find.byType(FirebaseAssignmentsScreen), findsOneWidget);
    auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.byType(FirebaseAssignmentsScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await auth.changes.close();
  });
}
