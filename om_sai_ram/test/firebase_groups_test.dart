import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/presentation/firebase_groups_screen.dart';
import 'package:om_sai_ram/features/firebase_groups/presentation/group_home_screen.dart';
import 'package:om_sai_ram/features/firebase_groups/presentation/group_list_screens.dart';
import 'package:om_sai_ram/features/firebase_groups/providers/firebase_groups_provider.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_member_display_test.dart' as names;

final now = DateTime.utc(2026, 10, 13);
final validToken = 'ab' * 32;
Map<String, dynamic> groupData() => {
  'name': 'Reading circle', 'description': 'Public group description',
  'mode': 'chapter_wise', 'createdBy': 'a', 'chaptersPerWeek': 2,
  'startChapter': 1, 'currentWeek': 1,
  'createdAt': Timestamp.fromDate(now), 'updatedAt': Timestamp.fromDate(now),
};
FirebaseGroupDetail detailFor(FirebaseGroupRole role) => FirebaseGroupDetail(
  FirebaseGroup.parse('g', groupData()), FirebaseMembership('a', role, now),
  FirebasePage([FirebaseMembership('a', role, now),
    FirebaseMembership('public-uid-b', FirebaseGroupRole.member, now)],
    cursor: 'public-uid-b', hasMore: false));

class FakeGroups implements FirebaseGroupsGateway {
  Object? error;
  FirebaseGroupRole role = FirebaseGroupRole.admin;
  Completer<FirebasePage<FirebaseGroupEntry>>? listGate;
  Completer<FirebaseGroupDetail>? detailGate;
  FirebasePage<FirebaseGroupEntry>? page;
  final cursors = <String?>[];
  int creates = 0, joins = 0, issues = 0, revokes = 0;
  FirebaseGroupDraft? draft;
  String? joinedToken;
  void check() { if (error != null) throw error!; }
  @override
  Future<FirebasePage<FirebaseGroupEntry>> listGroups({int pageSize = 20, String? cursor}) async {
    cursors.add(cursor); check();
    if (listGate != null) return listGate!.future;
    return page ?? FirebasePage([FirebaseGroupEntry(detailFor(role).group,
      detailFor(role).self)], cursor: 'g', hasMore: false);
  }
  @override
  Future<FirebaseGroupDetail> detail(String groupId, {int pageSize = 20, String? cursor}) async {
    cursors.add(cursor); check();
    if (detailGate != null) return detailGate!.future;
    return detailFor(role);
  }
  @override
  Future<String> create(FirebaseGroupDraft value) async {
    creates++; draft = value; check(); return 'g';
  }
  @override
  Future<String> join(String token) async {
    joins++; joinedToken = token; check(); return 'g';
  }
  @override
  Future<FirebaseGroupInvite> issueInvite(String groupId,
      {Duration lifetime = const Duration(hours: 24)}) async {
    issues++; check();
    return FirebaseGroupInvite(validToken, groupId, 'a', now,
      now.add(lifetime), true);
  }
  @override
  Future<void> revokeInvite(String token) async { revokes++; check(); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('strict models and validation', () {
    test('creation trims and retains chapter-wise defaults', () {
      final draft = FirebaseGroupDraft(' Circle ', ' Description ');
      expect(draft.name, 'Circle'); expect(draft.description, 'Description');
      expect(draft.chaptersPerWeek, 2); expect(draft.startChapter, 1);
      expect(draft.mode, 'chapter_wise');
      expect(FirebaseGroupDraft('x', '', mode: 'saptah').mode, 'saptah');
      for (final mode in ['', 'Saptah', 'daily']) {
        expect(() => FirebaseGroupDraft('x', '', mode: mode), throwsFormatException);
      }
    });
    test('creation rejects invalid name description width and start', () {
      for (final action in <void Function()>[
        () => FirebaseGroupDraft(' ', ''),
        () => FirebaseGroupDraft('x' * 101, ''),
        () => FirebaseGroupDraft('x', 'x' * 1001),
        () => FirebaseGroupDraft('x', '', chaptersPerWeek: 49),
        () => FirebaseGroupDraft('x', '', chaptersPerWeek: 0),
        () => FirebaseGroupDraft('x', '', startChapter: 54),
        () => FirebaseGroupDraft('x', '', startChapter: 0),
      ]) { expect(action, throwsFormatException); }
      expect(FirebaseGroupDraft('x', '', chaptersPerWeek: 48, startChapter: 53).startChapter, 53);
    });
    test('group parser retains timestamps metadata and rejects coercion', () {
      final group = FirebaseGroup.parse('g', groupData());
      expect(group.createdAt, now); expect(group.currentWeek, 1);
      for (final bad in [
        {...groupData(), 'currentWeek': '1'},
        {...groupData(), 'updatedAt': now},
        {...groupData(), 'email': 'private@example.com'},
        {...groupData(), 'mode': 'other'},
        {...groupData()}..remove('description'),
      ]) { expect(() => FirebaseGroup.parse('g', bad), throwsFormatException); }
      expect(() => FirebaseGroup.parse('g', null), throwsFormatException);
    });
    test('membership uses actual role and enforces UID and strict private-free shape', () {
      final raw = {'userId': 'a', 'role': 'group_lead', 'joinedAt': Timestamp.fromDate(now)};
      expect(FirebaseMembership.parse('a', raw).role, FirebaseGroupRole.groupLead);
      expect(() => FirebaseMembership.parse('b', raw), throwsFormatException);
      expect(() => FirebaseMembership.parse('a', {...raw, 'email': 'private'}), throwsFormatException);
      expect(() => FirebaseMembership.parse('a', {...raw, 'role': 'owner'}), throwsFormatException);
    });
    test('index rejects mismatched ID invalid token and unconfirmed date', () {
      final raw = {'groupId': 'g', 'joinedAt': Timestamp.fromDate(now)};
      expect(FirebaseGroupIndex.parse('g', raw).groupId, 'g');
      expect(() => FirebaseGroupIndex.parse('other', raw), throwsFormatException);
      expect(() => FirebaseGroupIndex.parse('g', {...raw, 'inviteToken': 'bad'}), throwsFormatException);
      expect(() => FirebaseGroupIndex.parse('g', {...raw, 'joinedAt': null}), throwsFormatException);
    });
    test('paging bounds 1 to 50 and empty continuation preserves index cursor', () {
      expect(boundedPageSize(1), 1); expect(boundedPageSize(50), 50);
      expect(() => boundedPageSize(0), throwsFormatException);
      expect(() => boundedPageSize(51), throwsFormatException);
      final page = FirebasePage<FirebaseGroupEntry>([], cursor: 'last-index', hasMore: false);
      expect(page.cursor, 'last-index'); expect(page.items, isEmpty);
      expect(() => FirebasePage([], hasMore: true), throwsFormatException);
      expect(() => documentId('g/member'), throwsFormatException);
    });
    test('token validation forbids uppercase whitespace and other lengths', () {
      expect(inviteToken(validToken), validToken);
      for (final token in ['AB' * 32, 'ab' * 31, 'ab' * 33, ' $validToken', 'z' * 64, 'ABCDEFGI', 'abcdefgh', 'ABCD-EFG']) {
        expect(() => inviteToken(token), throwsFormatException);
      }
      expect(inviteToken('ABCD2345'), 'ABCD2345');
    });
    test('invite text finds code in typed code, link or shared message', () {
      expect(inviteFromText('abcd-efgh'), 'ABCDEFGH');
      expect(inviteFromText(' abcd efgh '), 'ABCDEFGH');
      expect(inviteFromText('https://app.example/#/groups/join?code=ABCDEFGH'), 'ABCDEFGH');
      expect(inviteFromText('Join "Reading circle" on Om Sai Sannidhi.\nCode: WXYZ-2345\nValid until 5 pm'), 'WXYZ2345');
      expect(inviteFromText(validToken), validToken);
      for (final bad in ['', 'invalid', 'ABCD-EFG', 'IIII-OOOO']) {
        expect(() => inviteFromText(bad), throwsFormatException);
      }
      expect(displayInvite('ABCDEFGH'), 'ABCD-EFGH'); expect(displayInvite(validToken), validToken);
    });
    test('invite parser enforces boolean and Timestamp expiry metadata', () {
      final raw = {'groupId': 'g', 'createdBy': 'a', 'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))), 'active': true};
      expect(FirebaseGroupInvite.parse(validToken, raw).expiresAt, now.add(const Duration(hours: 24)));
      for (final bad in [{...raw, 'active': 1}, {...raw, 'expiresAt': now},
        {...raw, 'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 8)))},
        {...raw, 'createdAt': null}]) {
        expect(() => FirebaseGroupInvite.parse(validToken, bad), throwsFormatException);
      }
    });
    test('local expiry and revocation UX checks reject unusable invites', () {
      expect(() => FirebaseGroupInvite(validToken, 'g', 'a', now, now, true).requireUsable(now), throwsFormatException);
      expect(() => FirebaseGroupInvite(validToken, 'g', 'a', now,
        now.add(const Duration(days: 1)), false).requireUsable(now), throwsFormatException);
    });
  });

  group('UID-bound provider operations', () {
    late auth_test.FakeGateway auth;
    late FakeGroups groups;
    late ProviderContainer container;
    const scope = (uid: 'a', groupId: null);
    setUp(() async {
      auth = auth_test.FakeGateway()..profile = 'Private name';
      groups = FakeGroups();
      container = ProviderContainer(overrides: [
        firebaseAuthGatewayProvider.overrideWithValue(auth),
        firebaseGroupsGatewayProvider.overrideWithValue(groups),
      ]);
      container.listen(firebaseSessionProvider, (_, __) {});
      auth.emit(const FirebaseIdentity('a', 'private@example.com'));
      await Future<void>.delayed(Duration.zero);
      container.listen(firebaseGroupsProvider(scope), (_, __) {});
    });
    tearDown(() async { container.dispose(); await auth.changes.close(); });
    test('creation invalid input never reaches gateway and valid defaults pass', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      expect(await controller.create('', '', 2, 1), isNull); expect(groups.creates, 0);
      expect(container.read(firebaseGroupsProvider(scope)).error, isNotNull);
      expect(await controller.create(' Group ', '', 2, 1), 'g');
      expect(groups.draft!.name, 'Group'); expect(groups.draft!.mode, 'chapter_wise');
      expect(await controller.create('Saptah', '', 2, 1, mode: 'saptah'), 'g');
      expect(groups.draft!.mode, 'saptah');
      expect(await controller.create('Bad', '', 2, 1, mode: 'daily'), isNull); expect(groups.creates, 2);
    });
    test('request failure clears previous page; explicit retry succeeds', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      await controller.refresh(); expect(controller.state.groups, isNotNull);
      groups.error = StateError('secret details');
      await controller.refresh(); expect(controller.state.groups, isNull);
      expect(controller.state.error, isNot(contains('secret details')));
      groups.error = null; await controller.refresh(); expect(controller.state.groups, isNotNull);
    });
    test('refresh clears displayed data before awaited server response', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      await controller.refresh(); groups.listGate = Completer();
      final request = controller.refresh();
      expect(controller.state.busy, isTrue); expect(controller.state.groups, isNull);
      groups.listGate!.complete(FirebasePage([], cursor: 'g', hasMore: false));
      await request; expect(controller.state.groups!.cursor, 'g');
    });
    test('empty paginated response preserves cursor and next request uses index cursor', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      groups.page = FirebasePage([], cursor: 'last-index', hasMore: true);
      await controller.refresh();
      await controller.refresh(cursor: controller.state.groups!.cursor);
      expect(groups.cursors, [null, 'last-index']);
    });
    test('join validates format before gateway, trims UI input and surfaces expiry error', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      expect(await controller.join('invalid'), isNull); expect(groups.joins, 0);
      groups.error = const FormatException('This invite is expired or revoked.');
      expect(await controller.join(' $validToken '), isNull);
      expect(groups.joinedToken, validToken); expect(controller.state.error, contains('expired'));
      groups.error = null; expect(await controller.join(validToken), 'g');
    });
    test('duplicate join conflict is visible, not treated as success', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      groups.error = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      expect(await controller.join(validToken), isNull);
      expect(controller.state.error, contains('already be in this group'));
    });
    test('logout during delayed read discards old result and clears provider', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      groups.listGate = Completer(); final pending = controller.refresh();
      auth.emit(null); await Future<void>.delayed(Duration.zero);
      expect(container.read(firebaseGroupsProvider(scope)).groups, isNull);
      groups.listGate!.complete(FirebasePage([FirebaseGroupEntry(detailFor(groups.role).group,
        detailFor(groups.role).self)], hasMore: false));
      await pending;
      expect(container.read(firebaseGroupsProvider(scope)).groups, isNull);
    });
    test('account switch discards delayed result and old UID cannot request data', () async {
      final controller = container.read(firebaseGroupsProvider(scope).notifier);
      groups.listGate = Completer(); final pending = controller.refresh();
      auth.emit(const FirebaseIdentity('b', 'new@example.com'));
      await Future<void>.delayed(Duration.zero);
      groups.listGate!.complete(FirebasePage([], cursor: 'old', hasMore: false));
      await pending;
      final old = container.read(firebaseGroupsProvider(scope).notifier);
      await old.refresh(); expect(old.state.groups, isNull); expect(groups.cursors.length, 1);
    });
    test('pending private profile makes groups gateway inaccessible', () async {
      auth.profile = null; auth.emit(const FirebaseIdentity('b', 'new@example.com'));
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(firebaseGroupsProvider((uid: 'b', groupId: null)).notifier);
      await controller.refresh(); expect(groups.cursors, isEmpty);
      expect(controller.state.groups, isNull);
    });
    for (final role in FirebaseGroupRole.values) {
      test('actual ${role.name} role controls issuance, not createdBy', () async {
        groups.role = role;
        const detailScope = (uid: 'a', groupId: 'g');
        container.listen(firebaseGroupsProvider(detailScope), (_, __) {});
        final controller = container.read(firebaseGroupsProvider(detailScope).notifier);
        await controller.refresh(); await controller.issue();
        expect(groups.issues, isGroupLeader(role) ? 1 : 0);
        expect(controller.state.issued != null, isGroupLeader(role));
      });
    }
    test('permission failure clears group roster and issued token; retry reads fresh', () async {
      const detailScope = (uid: 'a', groupId: 'g');
      container.listen(firebaseGroupsProvider(detailScope), (_, __) {});
      final controller = container.read(firebaseGroupsProvider(detailScope).notifier);
      await controller.refresh(); await controller.issue(); expect(controller.state.issued, isNotNull);
      groups.error = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      await controller.refresh(); expect(controller.state.detail, isNull); expect(controller.state.issued, isNull);
      groups.error = null; await controller.refresh(); expect(controller.state.detail, isNotNull);
      expect(controller.state.issued, isNull);
    });
    test('revocation removes bearer token and rereads server roster', () async {
      const detailScope = (uid: 'a', groupId: 'g');
      container.listen(firebaseGroupsProvider(detailScope), (_, __) {});
      final controller = container.read(firebaseGroupsProvider(detailScope).notifier);
      await controller.refresh(); await controller.issue(); await controller.revoke();
      expect(groups.revokes, 1); expect(controller.state.issued, isNull);
      expect(controller.state.detail, isNotNull); expect(groups.cursors.length, 2);
    });
  });

  Future<(auth_test.FakeGateway, FakeGroups, ProviderContainer)> mount(WidgetTester tester, Widget screen,
      {FirebaseGroupRole role = FirebaseGroupRole.admin, void Function(FakeGroups)? setup}) async {
    final auth = auth_test.FakeGateway()..profile = 'Private name';
    final groups = FakeGroups()..role = role;
    setup?.call(groups);
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(groups),
      firebaseMemberDisplayGatewayProvider.overrideWithValue(
        names.FakeDisplays()..rows = [names.name('public-uid-b', 'Lakshmi')]),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(home: screen)));
    auth.emit(const FirebaseIdentity('a', 'private@example.com'));
    await tester.pumpAndSettle();
    addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink());
      container.dispose(); await auth.changes.close(); });
    return (auth, groups, container);
  }
  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key))); await tester.pumpAndSettle();
  }
  testWidgets('group list shows cards with week and role, plus start and join', (tester) async {
    await mount(tester, const FirebaseGroupListScreen());
    expect(find.text('Start a new group'), findsOneWidget); expect(find.text('Join a group'), findsOneWidget);
    expect(find.text('Reading circle'), findsOneWidget);
    expect(find.textContaining('Week 1'), findsOneWidget);
  });
  testWidgets('empty group list explains how to begin', (tester) async {
    await mount(tester, const FirebaseGroupListScreen(),
      setup: (groups) => groups.page = FirebasePage([], hasMore: false));
    expect(find.textContaining('You are not in a group yet'), findsOneWidget);
  });
  testWidgets('create form validates before requests and sends the Saptah kind', (tester) async {
    final (_, groups, _) = await mount(tester, const FirebaseCreateGroupScreen());
    await tapKey(tester, 'create-submit');
    expect(groups.creates, 0); expect(find.text('Please enter a group name.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('create-name')), 'Saptah circle');
    await tapKey(tester, 'create-mode-saptah');
    groups.error = StateError('offline'); // The request is captured; no navigation follows.
    await tapKey(tester, 'create-submit');
    expect(groups.draft!.mode, 'saptah'); expect(groups.draft!.name, 'Saptah circle');
    expect(find.byKey(const Key('groups-error')), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing); expect(tester.takeException(), isNull);
  });
  testWidgets('join accepts a pasted invite message and rejects a bad code first', (tester) async {
    final (_, groups, _) = await mount(tester, const FirebaseJoinGroupScreen(initialCode: 'nope'));
    await tapKey(tester, 'join-submit');
    expect(groups.joins, 0); expect(find.text('Enter the 8-letter invite code.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('join-code')), 'Join "Reading circle".\nCode: wxyz-2345');
    groups.error = StateError('offline');
    await tapKey(tester, 'join-submit');
    expect(groups.joinedToken, 'WXYZ2345'); expect(find.byKey(const Key('groups-error')), findsOneWidget);
  });
  for (final role in FirebaseGroupRole.values) {
    testWidgets('members show shared names, never account IDs, and ${role.name} controls', (tester) async {
      await mount(tester, const FirebaseGroupsScreen(groupId: 'g'), role: role);
      expect(find.text('Lakshmi'), findsOneWidget); expect(find.text('You'), findsOneWidget);
      expect(find.text('public-uid-b'), findsNothing);
      expect(find.text('private@example.com'), findsNothing); expect(find.text('Private name'), findsNothing);
      expect(find.byKey(const Key('add-member')), role == FirebaseGroupRole.admin ? findsOneWidget : findsNothing);
      // This fixture's actor is the creator even when its role is changed.
      expect(detailFor(role).group.createdBy, 'a');
      expect(find.text('Leave group'), findsNothing);
    });
  }
  testWidgets('members disappear immediately during refresh and on logout', (tester) async {
    final (auth, groups, _) = await mount(tester, const FirebaseGroupsScreen(groupId: 'g'));
    expect(find.text('Lakshmi'), findsOneWidget);
    groups.detailGate = Completer();
    await tester.tap(find.text('Refresh')); await tester.pump();
    expect(find.text('Lakshmi'), findsNothing);
    auth.emit(null); await tester.pumpAndSettle();
    groups.detailGate!.complete(detailFor(FirebaseGroupRole.admin)); await tester.pumpAndSettle();
    expect(find.text('Please sign in to use groups.'), findsOneWidget);
    expect(find.text('Reading circle'), findsNothing); expect(tester.takeException(), isNull);
  });
  testWidgets('account switch with delayed detail cannot surface old group data', (tester) async {
    final (auth, groups, _) = await mount(tester, const FirebaseGroupsScreen(groupId: 'g'));
    groups.detailGate = Completer();
    await tester.tap(find.text('Refresh')); await tester.pump();
    auth.profile = null; auth.emit(const FirebaseIdentity('b', 'new@example.com'));
    await tester.pumpAndSettle();
    groups.detailGate!.complete(detailFor(FirebaseGroupRole.admin)); await tester.pumpAndSettle();
    expect(find.text('Reading circle'), findsNothing); expect(find.text('Lakshmi'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('guarded routes deny pending profile and logout, ready My groups works', (tester) async {
    final auth = auth_test.FakeGateway(); final groups = FakeGroups();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(groups),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth accessed')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API accessed')),
    ]);
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp.router(routerConfig: router)));
    auth.emit(const FirebaseIdentity('a', 'private@example.com')); await tester.pumpAndSettle();
    for (final path in ['/groups', '/groups/g', '/groups/g/members']) {
      router.go(path); await tester.pumpAndSettle();
      expect(find.byType(FirebaseGroupListScreen), findsNothing);
      expect(find.byType(FirebaseGroupHomeScreen), findsNothing);
      expect(find.byType(FirebaseGroupsScreen), findsNothing);
    }
    router.go('/'); await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-groups')), findsNothing); expect(groups.cursors, isEmpty);
    auth.profile = 'Private'; await container.read(firebaseSessionProvider.notifier).reloadProfile();
    await tester.pumpAndSettle();
    expect(container.read(firebaseSessionProvider).ready, isTrue);
    router.go('/'); await tester.pumpAndSettle();
    final tile = find.byKey(const Key('home-groups'));
    await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(tile); await tester.pumpAndSettle();
    expect(find.byType(FirebaseGroupListScreen), findsOneWidget);
    auth.emit(null); await tester.pumpAndSettle();
    expect(find.byType(FirebaseGroupListScreen), findsNothing); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); container.dispose(); await auth.changes.close();
  });
}