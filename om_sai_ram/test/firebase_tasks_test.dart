// SDK-shaped doubles verify calls and failure handling, NOT actual SDK/rules.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:om_sai_ram/core/providers/language_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_resume.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignment_resume_provider.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firebase_task_models.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firestore_tasks_gateway.dart';
import 'package:om_sai_ram/features/firebase_tasks/providers/firebase_tasks_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/presentation/firebase_tasks_screen.dart';
import 'firebase_assignments_test.dart' as a;
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_groups_test.dart' as g;
import 'firestore_assignments_gateway_test.dart' as sdk;

const indexPath = 'users/a/groups';
const rowsPath = 'groups/g/readingWeeks/1/members/a/assignments';
const binding = (uid: 'a', options: defaultTaskOptions);

class TasksDb extends sdk.SdkDb {
  final queries =
      <({String path, int limit, Object field, List<Object?>? after})>[];
  final queryCache = <String>{}, queryPendingPaths = <String>{};
  @override
  CollectionReference<sdk.Data> collection(String path) =>
      TasksCollection(this, path);
}

class TasksCollection extends sdk.SdkCollection {
  TasksCollection(TasksDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) =>
      TasksDocument(db as TasksDb, '${this.path}/$path');
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) {
    expect(descending, isFalse);
    return TasksQuery(db as TasksDb, path, field);
  }
}

class TasksDocument extends sdk.SdkDocument {
  TasksDocument(TasksDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String collectionPath) =>
      TasksCollection(db as TasksDb, '$path/$collectionPath');
}

class TasksQuery extends Fake implements Query<sdk.Data> {
  final TasksDb db;
  final String path;
  final Object field;
  final int rowLimit;
  final List<Object?>? after;
  TasksQuery(this.db, this.path, this.field, {this.rowLimit = 0, this.after});
  @override
  Query<sdk.Data> limit(int limit) {
    return TasksQuery(db, path, field, rowLimit: limit, after: after);
  }

  @override
  Query<sdk.Data> startAfter(Iterable<Object?> values) {
    return TasksQuery(db, path, field,
        rowLimit: rowLimit, after: values.toList());
  }

  @override
  Future<QuerySnapshot<sdk.Data>> get([GetOptions? options]) async {
    db.queries.add((path: path, limit: rowLimit, field: field, after: after));
    db.sources.add(options?.source);
    if (db.gates[path] != null) await db.gates[path]!.future;
    if (db.errors[path] != null) throw db.errors[path]!;
    final entries = db.documents.entries
        .where((entry) =>
            entry.key.startsWith('$path/') &&
            !entry.key.substring(path.length + 1).contains('/') &&
            (after == null ||
                entry.key.split('/').last.compareTo(after!.single as String) >
                    0))
        .toList()
      ..sort((x, y) => x.key.compareTo(y.key));
    return sdk.QueryResult(
        entries
            .take(rowLimit)
            .map((entry) => sdk.QueryDocument(
                entry.key.split('/').last, entry.value, db.metadata(entry.key)))
            .toList(),
        sdk.Metadata(
            isFromCache: db.queryCache.contains(path),
            hasPendingWrites: db.queryPendingPaths.contains(path)));
  }
}

FirebaseTaskPage fixture(
    {String uid = 'a',
    String id = 'g',
    int week = 1,
    FirebaseTaskOptions options = defaultTaskOptions,
    bool empty = false,
    FirebaseTaskSummary? summary}) {
  final group =
      FirebaseGroup.parse(id, {...g.groupData(), 'currentWeek': week});
  return FirebaseTaskPage(
      uid,
      [
        FirebaseTaskGroup(group, [
          for (final selected in taskWeeks(group, options))
            FirebaseTaskWeek(
                selected,
                empty
                    ? []
                    : [
                        FirebaseAssignment.parse(
                            (
                              uid: uid,
                              groupId: id,
                              memberUid: uid,
                              week: selected
                            ),
                            '16-17',
                            a.assignmentData(scope: (
                              uid: uid,
                              groupId: id,
                              memberUid: uid,
                              week: selected
                            )))
                      ],
                summary: summary)
        ])
      ],
      hasMore: options.pageSize == 1,
      cursor: options.pageSize == 1 ? id : null);
}

class FakeTasks implements FirebaseTasksGateway {
  final calls = <({FirebaseTaskOptions options, String? cursor})>[];
  Object? error;
  Completer<FirebaseTaskPage>? gate;
  FirebaseTaskPage? response;
  @override
  Future<FirebaseTaskPage> read(
      {FirebaseTaskOptions options = defaultTaskOptions,
      String? cursor}) async {
    calls.add((options: options, cursor: cursor));
    if (error != null) throw error!;
    if (gate != null) return gate!.future;
    return response ??
        fixture(options: options, id: cursor == null ? 'g' : 'h');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TasksDb db;
  late sdk.SdkAuth auth;
  late FirestoreTasksGateway gateway;
  void addGroup(String id, int week) {
    db.documents['$indexPath/$id'] = {
      'groupId': id,
      'joinedAt': Timestamp.fromDate(g.now)
    };
    db.documents['groups/$id'] = {...g.groupData(), 'currentWeek': week};
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = TasksDb();
    auth = sdk.SdkAuth();
    gateway = FirestoreTasksGateway(auth, db);
    db.documents['users/a'] = {
      'displayName': 'Private',
      'createdAt': Timestamp.fromDate(g.now),
      'updatedAt': Timestamp.fromDate(g.now)
    };
    addGroup('g', 1);
    db.documents['$rowsPath/16-17'] = a.assignmentData();
  });

  for (final options in [
    (pageSize: 0, weeksAhead: 1, weekNumber: null),
    (pageSize: 11, weeksAhead: 1, weekNumber: null),
    (pageSize: 5, weeksAhead: 0, weekNumber: null),
    (pageSize: 5, weeksAhead: 4, weekNumber: null),
    (pageSize: 5, weeksAhead: 1, weekNumber: 0),
    (pageSize: 5, weeksAhead: 1, weekNumber: 10001),
  ]) {
    test('invalid options $options reject before database/gateway construction',
        () async {
      await expectLater(gateway.read(options: options), throwsFormatException);
      expect(db.reads, isEmpty);
      expect(db.queries, isEmpty);
      final container = ProviderContainer(overrides: [
        firebaseAuthGatewayProvider.overrideWithValue(auth_test.FakeGateway()),
        firebaseTasksGatewayProvider
            .overrideWith((ref) => throw StateError('Constructed')),
      ]);
      final scope = (uid: 'a', options: options);
      final sub = container.listen(firebaseTasksProvider(scope), (_, __) {});
      await container.read(firebaseTasksProvider(scope).notifier).refresh();
      expect(container.read(firebaseTasksProvider(scope)).page, isNull);
      sub.close();
      container.dispose();
    });
  }
  test('invalid cursor and signed-out SDK fail before reads', () async {
    await expectLater(gateway.read(cursor: 'a/b'), throwsFormatException);
    auth.currentUser = null;
    await expectLater(gateway.read(), throwsFormatException);
    expect(db.sources, isEmpty);
  });
  test(
      'direct own index and assignments only; all reads server with docID bounds',
      () async {
    db.documents['groups/g/readingWeeks/1/members/other/assignments/16-17'] =
        a.assignmentData(scope: a.other);
    final page = await gateway.read();
    expect(page.uid, 'a');
    expect(page.groups.single.weeks.single.assignments.single.userId, 'a');
    expect(db.reads, ['users/a', 'groups/g']);
    expect(db.queries.map((q) => (q.path, q.limit)),
        [(indexPath, 5), (rowsPath, 48)]);
    expect(db.queries.every((q) => q.field == FieldPath.documentId), isTrue);
    expect(db.sources.every((s) => s == Source.server), isTrue);
    expect(db.writes, isEmpty);
  });
  test('each group uses its own current week and retains safe empty groups',
      () async {
    addGroup('h', 7);
    final page = await gateway
        .read(options: (pageSize: 5, weeksAhead: 3, weekNumber: null));
    expect(
        page.groups
            .map((e) => e.weeks.map((w) => w.weekNumber).toList())
            .toList(),
        [
          [1, 2, 3],
          [7, 8, 9]
        ]);
    expect(page.groups.last.weeks.every((w) => w.summary.total == 0), isTrue);
  });
  test('explicit history selection replaces every group start week', () async {
    addGroup('h', 7);
    final page = await gateway
        .read(options: (pageSize: 5, weeksAhead: 2, weekNumber: 2));
    expect(
        page.groups
            .every((e) => e.weeks.map((w) => w.weekNumber).join(',') == '2,3'),
        isTrue);
    expect(page.groups.every((e) => e.weeks.every((w) => w.summary.total == 0)),
        isTrue);
  });
  test('10000 cap truncates selected weeks without overflow', () async {
    addGroup('g', 9999);
    final page = await gateway
        .read(options: (pageSize: 5, weeksAhead: 3, weekNumber: null));
    expect(page.groups.single.weeks.map((w) => w.weekNumber), [9999, 10000]);
    expect(
        (await gateway
                .read(options: (pageSize: 5, weeksAhead: 3, weekNumber: 10000)))
            .groups
            .single
            .weeks
            .length,
        1);
  });
  test('full empty group page carries last index cursor then empty final page',
      () async {
    db.documents.remove('$rowsPath/16-17');
    final first = await gateway
        .read(options: (pageSize: 1, weeksAhead: 1, weekNumber: null));
    expect(first.hasMore, isTrue);
    expect(first.cursor, 'g');
    expect(first.groups.single.weeks.single.assignments, isEmpty);
    final last = await gateway.read(
        options: (pageSize: 1, weeksAhead: 1, weekNumber: null),
        cursor: first.cursor);
    expect(last.groups, isEmpty);
    expect(last.hasMore, isFalse);
    expect(last.cursor, isNull);
    expect(db.queries.last.after, ['g']);
  });
  test(
      'maximum document fanout bounded to 1461 returned documents and sequential reads',
      () async {
    db.documents.clear();
    db.documents['users/a'] = {
      'displayName': 'Private',
      'createdAt': Timestamp.fromDate(g.now),
      'updatedAt': Timestamp.fromDate(g.now)
    };
    for (var i = 0; i < 11; i++) {
      final id = 'g${i.toString().padLeft(2, '0')}';
      addGroup(id, 1);
      for (var week = 1; week <= 3; week++) {
        for (final unit in FirebaseChapterUnit.all) {
          db.documents[
                  'groups/$id/readingWeeks/$week/members/a/assignments/${unit.key}'] =
              a.assignmentData(
                  scope: (uid: 'a', groupId: id, memberUid: 'a', week: week),
                  chapter: unit.start);
        }
      }
    }
    final page = await gateway
        .read(options: (pageSize: 10, weeksAhead: 3, weekNumber: null));
    expect(page.groups.length, 10);
    expect(db.reads.length, 11);
    expect(db.queries.length, 31);
    expect(
        page.groups.expand((e) => e.weeks).expand((w) => w.assignments).length,
        1440);
    expect(db.reads, isNot(contains('groups/g10')));
    expect(db.writes, isEmpty);
  });
  test(
      'summary enum counts canonical combined units once, not original chapter width',
      () async {
    for (final pair in [
      (1, FirebaseReadingStatus.inProgress),
      (53, FirebaseReadingStatus.completed)
    ]) {
      final unit = FirebaseChapterUnit.fromChapter(pair.$1);
      db.documents['$rowsPath/${unit.key}'] =
          a.assignmentData(chapter: pair.$1, status: pair.$2);
    }
    final week = (await gateway.read()).groups.single.weeks.single;
    expect(
        week.summary, (total: 3, notStarted: 1, inProgress: 1, completed: 1));
    expect(week.assignments.map((a) => a.unit.key), ['1', '16-17', '51-53']);
  });
  test(
      'task dashboard excludes archived and pre-rejoin work without losing discovery',
      () async {
    db.documents['$rowsPath/16-17']!.addAll({
      'archived': true,
      'revision': 1,
      'changedBy': 'a',
      'changedAt': Timestamp.fromDate(g.now)
    });
    var page = await gateway.read();
    expect(page.groups.single.weeks.single.assignments, isEmpty);
    db.documents['$rowsPath/16-17']!['archived'] = false;
    final created = db.documents['$rowsPath/16-17']!['createdAt'] as Timestamp;
    db.documents['$indexPath/g']!['joinedAt'] =
        Timestamp(created.seconds, created.nanoseconds + 1);
    page = await gateway.read();
    expect(page.groups.single.group.id, 'g');
    expect(page.groups.single.weeks.single.summary.total, 0);
    db.documents['$rowsPath/16-17']!['createdAt'] =
        Timestamp(created.seconds + 1, created.nanoseconds);
    page = await gateway.read();
    expect(page.groups.single.weeks.single.assignments.length, 1);
  });
  for (final path in [
    'users/a',
    '$indexPath/g',
    'groups/g',
    '$rowsPath/16-17'
  ]) {
    test('cached or pending document $path rejects whole page', () async {
      db.cached.add(path);
      await expectLater(gateway.read(), throwsStateError);
      db.cached.clear();
      db.pending.add(path);
      await expectLater(gateway.read(), throwsStateError);
    });
  }
  for (final path in [indexPath, rowsPath]) {
    test('cached or pending query $path rejects whole page', () async {
      db.queryCache.add(path);
      await expectLater(gateway.read(), throwsStateError);
      db.queryCache.clear();
      db.queryPendingPaths.add(path);
      await expectLater(gateway.read(), throwsStateError);
    });
  }
  for (final boundary in ['users/a', indexPath, 'groups/g', rowsPath]) {
    test('SDK account change during $boundary aborts delayed success',
        () async {
      db.gates[boundary] = Completer();
      final request = gateway.read();
      final expected = expectLater(request, throwsStateError);
      for (var n = 0; n < 12; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      auth.currentUser = sdk.SdkUser('b');
      db.gates[boundary]!.complete();
      await expected;
      expect(db.writes, isEmpty);
    });
  }
  for (final path in [
    'users/a',
    '$indexPath/g',
    'groups/g',
    '$rowsPath/16-17'
  ]) {
    test('malformed $path fails entire page including earlier valid groups',
        () async {
      addGroup('a-first', 1);
      db.documents[path]!['unexpected'] = true;
      await expectLater(gateway.read(), throwsFormatException);
    });
  }
  test('stale index missing group and invalid current week/status all reject',
      () async {
    db.documents.remove('groups/g');
    await expectLater(gateway.read(), throwsFormatException);
    addGroup('g', 10001);
    await expectLater(gateway.read(), throwsFormatException);
    addGroup('g', 1);
    db.documents['$rowsPath/16-17']!['status'] = 'unknown';
    await expectLater(gateway.read(), throwsFormatException);
  });
  for (final code in ['permission-denied', 'unavailable']) {
    test(
        '$code on later group rejects without partial/cache fallback then retries',
        () async {
      addGroup('h', 1);
      db.errors['groups/h'] =
          FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.read(), throwsA(isA<FirebaseException>()));
      db.errors.clear();
      expect((await gateway.read()).groups.length, 2);
    });
  }

  for (final poison in [
    'uid',
    'summary',
    'week',
    'cursor',
    'other-row',
    'duplicate'
  ]) {
    test('controller rejects injected $poison response', () async {
      final fake = FakeTasks();
      final normal = fixture();
      fake.response = switch (poison) {
        'uid' => fixture(uid: 'b'),
        'summary' => fixture(
            summary: (total: 4, notStarted: 4, inProgress: 0, completed: 0)),
        'week' => FirebaseTaskPage(
            'a',
            [
              FirebaseTaskGroup(normal.groups.single.group,
                  fixture(week: 2).groups.single.weeks)
            ],
            hasMore: false),
        'cursor' =>
          FirebaseTaskPage('a', normal.groups, hasMore: true, cursor: 'g'),
        'other-row' => FirebaseTaskPage(
            'a',
            [
              FirebaseTaskGroup(normal.groups.single.group, [
                FirebaseTaskWeek(
                    1, fixture(uid: 'b').groups.single.weeks.single.assignments)
              ])
            ],
            hasMore: false),
        _ => FirebaseTaskPage(
            'a',
            [
              FirebaseTaskGroup(normal.groups.single.group, [
                FirebaseTaskWeek(1, [
                  ...normal.groups.single.weeks.single.assignments,
                  ...normal.groups.single.weeks.single.assignments
                ])
              ])
            ],
            hasMore: false),
      };
      final controller = FirebaseTasksController(fake, binding, () => true);
      await controller.refresh();
      expect(controller.state.page, isNull);
      expect(controller.state.error, isNotNull);
      controller.dispose();
    });
  }
  test(
      'controller clears old page/error before await and retries failed next cursor without skipping',
      () async {
    final fake = FakeTasks();
    final controller = FirebaseTasksController(fake, binding, () => true);
    await controller.refresh();
    expect(controller.state.page, isNotNull);
    fake.error = StateError('offline');
    await controller.refresh(cursor: 'g');
    expect(controller.state.page, isNull);
    expect(controller.state.error, isNotNull);
    fake.error = null;
    fake.gate = Completer();
    final retry = controller.refresh();
    expect(controller.state.page, isNull);
    expect(controller.state.error, isNull);
    expect(controller.state.busy, isTrue);
    fake.gate!.complete(fixture(id: 'h'));
    await retry;
    expect(fake.calls.map((c) => c.cursor), [null, 'g', 'g']);
    fake.gate = null;
    await controller.refresh(restart: true);
    expect(fake.calls.last.cursor, isNull);
    controller.dispose();
  });
  test('disposed or changed-account controller never accepts delayed response',
      () async {
    var current = true;
    final fake = FakeTasks()..gate = Completer();
    final controller = FirebaseTasksController(fake, binding, () => current);
    final request = controller.refresh();
    current = false;
    fake.gate!.complete(fixture());
    await request;
    expect(controller.state.page, isNull);
    expect(controller.state.busy, isFalse);
    current = true;
    fake.gate = Completer();
    final later = controller.refresh();
    controller.dispose();
    fake.gate!.complete(fixture());
    await later;
  });

  Future<(auth_test.FakeGateway, FakeTasks, ProviderContainer)> mount(
      WidgetTester tester,
      {bool ready = true,
      bool routed = false,
      FakeTasks? fake}) async {
    final authGateway = auth_test.FakeGateway()
      ..profile = ready ? 'Private' : null;
    final tasks = fake ?? FakeTasks();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(authGateway),
      firebaseTasksGatewayProvider.overrideWithValue(tasks),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API constructed')),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth constructed')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    authGateway.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: routed
            ? MaterialApp.router(routerConfig: container.read(routerProvider))
            : const MaterialApp(home: FirebaseTasksScreen())));
    if (routed) container.read(routerProvider).go('/tasks');
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await authGateway.changes.close();
    });
    return (authGateway, tasks, container);
  }

  testWidgets(
      'pending profile direct screen and deep URL never construct legacy or tasks reads',
      (tester) async {
    final (_, tasks, container) =
        await mount(tester, ready: false, routed: true);
    expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        '/');
    expect(tasks.calls, isEmpty);
    expect(find.text('My reading tasks'), findsNothing);
  });
  testWidgets(
      'saved assignment clear affects only current account pointer, including invalid storage',
      (tester) async {
    final other = FirebaseAssignmentResume(
        scope: (uid: 'b', groupId: 'g', memberUid: 'b', week: 4),
        unitKey: '51-53',
        language: 'mr',
        position: .3);
    SharedPreferences.setMockInitialValues({
      firebaseAssignmentResumeKey('a'): 'broken',
      firebaseAssignmentResumeKey('b'): other.encode()
    });
    await mount(tester);
    expect(find.byKey(const Key('tasks-resume-error')), findsOneWidget);
    expect(find.byKey(const Key('tasks-continue-saved')), findsNothing);
    await tester.tap(find.byKey(const Key('tasks-clear-saved')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(firebaseAssignmentResumeKey('a')), isNull);
    expect(prefs.getString(firebaseAssignmentResumeKey('b')), other.encode());
  });

  testWidgets(
      'saved assignment continue preserves exact scope and saved language then reloads tasks',
      (tester) async {
    final saved = FirebaseAssignmentResume(
        scope: (uid: 'a', groupId: 'g #', memberUid: 'a +', week: 7),
        unitKey: '51-53',
        language: 'mr',
        position: .3);
    SharedPreferences.setMockInitialValues(
        {firebaseAssignmentResumeKey('a'): saved.encode()});
    final authGateway = auth_test.FakeGateway()..profile = 'Private';
    final tasks = FakeTasks();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(authGateway),
      firebaseTasksGatewayProvider.overrideWithValue(tasks)
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    authGateway.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    String? captured;
    final router = GoRouter(initialLocation: '/tasks', routes: [
      GoRoute(path: '/tasks', builder: (_, __) => const FirebaseTasksScreen()),
      GoRoute(
          path: '/groups/:id/assignments/read/:uid/:week/:unit',
          builder: (context, state) {
            captured = state.uri.toString();
            return Scaffold(
                body: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Saved reader back')));
          }),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tasks-continue-saved')));
    await tester.pumpAndSettle();
    expect(captured, '/groups/g%20%23/assignments/read/a%20%2B/7/51-53');
    expect(
        container.read(languageProvider).readerLanguage, AppLanguage.marathi);
    await tester.tap(find.text('Saved reader back'));
    await tester.pumpAndSettle();
    expect(tasks.calls.length, 2);
    expect(
        container.read(firebaseAssignmentResumeProvider('a')).value!.position,
        .3);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    await authGateway.changes.close();
  });
  testWidgets('ready auth entry and tasks route preserve Firebase boundary',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final (_, tasks, container) = await mount(tester, routed: true);
    expect(tasks.calls.length, 1);
    expect(find.text('Original chapters 16-17'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-tasks')), findsNothing);
    container.read(routerProvider).go('/tasks');
    await tester.pumpAndSettle();
    expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/tasks');
  });
  testWidgets(
      'week option change keys new provider and clears previous selected summaries',
      (tester) async {
    final (_, tasks, _) = await mount(tester);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    expect(tasks.calls.last.options.weeksAhead, 3);
    expect(find.textContaining('Week 3 • Your tasks: 1'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '10000');
    await tester.tap(find.text('Apply week selection'));
    await tester.pumpAndSettle();
    expect(tasks.calls.last.options.weekNumber, 10000);
    expect(find.textContaining('Week 10000 • Your tasks: 1'), findsOneWidget);
    expect(find.textContaining('Week 1 • Your tasks'), findsNothing);
  });
  testWidgets(
      'invalid explicit week has no reads and safe empty group remains visible',
      (tester) async {
    final (_, tasks, _) =
        await mount(tester, fake: FakeTasks()..response = fixture(empty: true));
    expect(find.text('No assignments for you in this week.'), findsOneWidget);
    expect(find.text('Read'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '10001');
    await tester.tap(find.text('Apply week selection'));
    await tester.pumpAndSettle();
    expect(tasks.calls.length, 1);
    expect(find.text('Enter a week from 1–10000.'), findsOneWidget);
  });
  testWidgets(
      'logout during delayed read hides page and discards old account result',
      (tester) async {
    final tasks = FakeTasks();
    final (authGateway, _, _) = await mount(tester, fake: tasks);
    tasks.gate = Completer();
    await tester.tap(find.text('Refresh / retry page'));
    await tester.pump();
    expect(find.text('Original chapters 16-17'), findsNothing);
    authGateway.emit(null);
    await tester.pump();
    tasks.gate!.complete(fixture());
    await tester.pumpAndSettle();
    expect(find.text('Original chapters 16-17'), findsNothing);
    expect(find.text('Ready Firebase session required.'), findsOneWidget);
  });
  testWidgets(
      'provider options disposal drops delayed old selection even while new selection succeeds',
      (tester) async {
    final (_, tasks, container) = await mount(tester);
    final oldGate = Completer<FirebaseTaskPage>();
    tasks.gate = oldGate;
    final old = container.read(firebaseTasksProvider(binding).notifier);
    final delayed = old.refresh();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    const newBinding =
        (uid: 'a', options: (pageSize: 5, weeksAhead: 2, weekNumber: null));
    tasks.gate = null;
    final subscription =
        container.listen(firebaseTasksProvider(newBinding), (_, __) {});
    await container.read(firebaseTasksProvider(newBinding).notifier).refresh();
    expect(
        container
            .read(firebaseTasksProvider(newBinding))
            .page!
            .groups
            .single
            .weeks
            .length,
        2);
    oldGate.complete(fixture());
    await delayed;
    expect(
        container
            .read(firebaseTasksProvider(newBinding))
            .page!
            .groups
            .single
            .weeks
            .length,
        2);
    subscription.close();
  });
  testWidgets(
      'reader encoded own scope link push then pop reloads same options/page',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authGateway = auth_test.FakeGateway()..profile = 'Private';
    final tasks = FakeTasks();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(authGateway),
      firebaseTasksGatewayProvider.overrideWithValue(tasks)
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    authGateway.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    String? captured;
    final router = GoRouter(initialLocation: '/tasks', routes: [
      GoRoute(path: '/tasks', builder: (_, __) => const FirebaseTasksScreen()),
      GoRoute(
          path: '/groups/:id/assignments/read/:uid/:week/:unit',
          builder: (context, state) {
            captured = state.uri.path;
            return Scaffold(
                body: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Reader back')));
          })
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '7');
    await tester.tap(find.text('Apply week selection'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Read'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(captured, '/groups/g/assignments/read/a/7/16-17');
    await tester.tap(find.text('Reader back'));
    await tester.pumpAndSettle();
    expect(tasks.calls.map((c) => c.options.weekNumber), [null, 7, 7]);
    expect(tasks.calls.last.cursor, isNull);
    const scope = (uid: 'a', groupId: 'g #', memberUid: 'a +', week: 10000);
    final row = FirebaseAssignment.parse(
        scope, '51-53', a.assignmentData(scope: scope, chapter: 53));
    expect(taskReaderLocation(row),
        '/groups/g%20%23/assignments/read/a%20%2B/10000/51-53');
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    await authGateway.changes.close();
  });
}
