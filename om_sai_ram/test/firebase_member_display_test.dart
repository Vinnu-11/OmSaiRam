import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/data/auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/presentation/firebase_groups_screen.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firebase_member_display_models.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'package:om_sai_ram/features/firebase_member_display/providers/firebase_member_display_provider.dart';
import 'package:om_sai_ram/features/firebase_member_display/presentation/firebase_member_display_screen.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_membership_test.dart' as membership;
import 'group_home_overrides.dart';

const binding = (uid: 'a', groupId: 'g');
final instant = Timestamp(1700000000, 123456789);
FirebaseMemberDisplay name(String uid, [String text = 'Same name', String group = 'g']) =>
  FirebaseMemberDisplay.parse(group, uid, {'displayName': text, 'createdAt': instant, 'updatedAt': instant});
class FakeDisplays implements FirebaseMemberDisplayGateway {
  final reads = <String?>[], writes = <String>[];
  String uid = 'a';
  FirebaseMemberDisplay? own;
  List<FirebaseMemberDisplay> rows = [name('b'), name('c')];
  Object? readError, writeError;
  Completer<void>? readGate, writeGate;
  FirebaseMemberDisplayPage? overridePage;
  @override
  Future<List<FirebaseMemberDisplay>> readMembers(String groupId, List<String> memberUids) async {
    reads.add(null);
    if (readGate != null) await readGate!.future;
    if (readError != null) throw readError!;
    return rows.where((row) => memberUids.contains(row.uid)).toList();
  }
  @override
  Future<FirebaseMemberDisplayPage> read(String groupId, {int pageSize = 20, String? after}) async {
    reads.add(after);
    if (readGate != null) await readGate!.future;
    if (readError != null) throw readError!;
    return overridePage ?? FirebaseMemberDisplayPage((uid: uid, groupId: groupId),
      after == null ? rows : const [], own: own, after: after, pageSize: pageSize);
  }
  @override
  Future<void> publish(String groupId, String displayName) async {
    writes.add(displayName);
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    own = name(uid, displayName, groupId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('publish needs verified page, trims explicit draft and ACK blocks repeat', () async {
    final g = FakeDisplays(); final c = FirebaseMemberDisplayController(binding, () => g, () => true);
    expect(await c.publish('Name'), isFalse); expect(g.writes, isEmpty);
    await c.load(); expect(await c.publish('  Public  '), isTrue);
    expect(g.writes, ['Public']); expect(c.state.acknowledged, isTrue);
    expect(await c.publish('Repeat'), isFalse);
    await c.load(); expect(c.state.acknowledged, isFalse);
    expect(await c.publish('Changed'), isTrue); c.dispose();
  });
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code load clears published results before await and fails closed', () async {
      final g = FakeDisplays(); final c = FirebaseMemberDisplayController(binding, () => g, () => true);
      await c.load(); g.readGate = Completer(); g.readError = FirebaseException(plugin: 'cloud_firestore', code: code);
      final request = c.load(); expect(c.state.page, isNull); expect(c.state.busy, isTrue);
      g.readGate!.complete(); await request;
      expect(c.state.page, isNull); expect(c.state.error, isNotNull); expect(c.state.verifyBeforeRetry, isTrue);
      expect(await c.publish('Name'), isFalse); c.dispose();
    });
    test('$code write failure no false ACK/repeated write until verified', () async {
      final g = FakeDisplays()..writeError = FirebaseException(plugin: 'cloud_firestore', code: code);
      final c = FirebaseMemberDisplayController(binding, () => g, () => true); await c.load();
      expect(await c.publish('Name'), isFalse); expect(c.state.acknowledged, isFalse); expect(c.state.page, isNull);
      expect(await c.publish('Name'), isFalse); expect(g.writes.length, 1);
      g.writeError = null; await c.load(); expect(await c.publish('Changed'), isTrue); c.dispose();
    });
  }
  test('ACK reload failure preserved through failed manual refresh, never repeat', () async {
    final g = FakeDisplays(); final c = FirebaseMemberDisplayController(binding, () => g, () => true);
    await c.load(); g.readError = StateError('offline');
    expect(await c.publish('Name'), isTrue); expect(c.state.acknowledged, isTrue);
    expect(c.state.error, contains('acknowledged')); expect(c.state.page, isNull);
    await c.load(); expect(c.state.acknowledged, isTrue);
    expect(await c.publish('Name'), isFalse); expect(g.writes.length, 1);
    g.readError = null; await c.load(); expect(c.state.acknowledged, isFalse); c.dispose();
  });
  test('pagination replacement full final page empty then manual retry same cursor', () async {
    final g = FakeDisplays()..rows = [for (var i = 0; i < 20; i++) name('b${i.toString().padLeft(2, '0')}')];
    final c = FirebaseMemberDisplayController(binding, () => g, () => true);
    await c.load(); expect(c.state.page!.hasMore, isTrue);
    final cursor = c.state.page!.cursor;
    g.readError = StateError('offline'); await c.load(after: cursor); expect(c.state.page, isNull);
    g.readError = null; await c.load(retry: true);
    expect(g.reads, [null, cursor, cursor]); expect(c.state.page!.names, isEmpty);
    expect(c.state.page!.hasMore, isFalse); expect(g.reads.length, 3); c.dispose();
  });
  for (final operation in ['load', 'publish']) {
    for (final end in ['account', 'dispose']) {
      for (final failure in [false, true]) {
        test('$operation delayed $end ${failure ? 'failure' : 'success'} clears/discards', () async {
          var current = true; final g = FakeDisplays();
          final c = FirebaseMemberDisplayController(binding, () => g, () => current);
          await c.load();
          if (operation == 'load') { g.readGate = Completer(); if (failure) g.readError = StateError('old'); }
          else { g.writeGate = Completer(); if (failure) g.writeError = StateError('old'); }
          final request = operation == 'load' ? c.load() : c.publish('Name');
          expect(c.state.page, isNull);
          if (operation == 'publish') expect(await c.publish('Repeat'), isFalse);
          if (end == 'account') { current = false; } else { c.dispose(); }
          (operation == 'load' ? g.readGate : g.writeGate)!.complete(); await request;
          if (end == 'account') { expect(c.state.page, isNull); expect(c.state.error, isNull); expect(c.state.busy, isFalse); c.dispose(); }
        });
      }
    }
  }
  for (final mismatch in ['uid', 'group', 'size', 'cursor']) {
    test('controller rejects $mismatch response scope', () async {
      final g = FakeDisplays()..overridePage = FirebaseMemberDisplayPage(
        (uid: mismatch == 'uid' ? 'other' : 'a', groupId: mismatch == 'group' ? 'h' : 'g'), [],
        pageSize: mismatch == 'size' ? 50 : 20, after: mismatch == 'cursor' ? 'z' : null);
      final c = FirebaseMemberDisplayController(binding, () => g, () => true);
      await c.load(); expect(c.state.page, isNull); expect(c.state.error, contains('scope')); c.dispose();
    });
  }
  test('unready provider never constructs new SDK', () async {
    final auth = authentication.FakeGateway()..readGate = Completer();
    final container = ProviderContainer(overrides: [firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseMemberDisplayGatewayProvider.overrideWith((ref) => throw StateError('No SDK'))]);
    container.listen(firebaseSessionProvider, (_, __) {}); auth.emit(const FirebaseIdentity('a', null));
    await Future<void>.delayed(Duration.zero);
    container.listen(firebaseMemberDisplayProvider(binding), (_, __) {});
    final c = container.read(firebaseMemberDisplayProvider(binding).notifier);
    await c.load(); expect(await c.publish('Name'), isFalse); expect(c.state.page, isNull);
    container.dispose(); auth.readGate!.complete('Private'); await auth.changes.close();
  });

  Future<({ProviderContainer container, authentication.FakeGateway auth, FakeDisplays gateway})> mount(
      WidgetTester tester, {FakeDisplays? gateway, bool routed = false, bool ready = true,
      String groupId = 'g', bool groupScreen = false, FirebaseGroupRole role = FirebaseGroupRole.member}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = 'PRIVATE NAME';
    if (!ready) auth.readGate = Completer();
    final g = gateway ?? FakeDisplays();
    final groups = membership.MembershipGroups()..role = role;
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth), firebaseMemberDisplayGatewayProvider.overrideWithValue(g),
      firebaseGroupsGatewayProvider.overrideWithValue(groups), ...groupHomeOverrides(names: false),
      authRepositoryProvider.overrideWith((ref) => throw StateError('No legacy auth')),
      apiClientProvider.overrideWith((ref) => throw StateError('No legacy API')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {}); auth.emit(const FirebaseIdentity('a', 'PRIVATE EMAIL'));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: routed
      ? MaterialApp.router(routerConfig: container.read(routerProvider))
      : MaterialApp(home: groupScreen ? const FirebaseGroupsScreen(groupId: 'g') : FirebaseMemberDisplayScreen(groupId: groupId))));
    if (routed) container.read(routerProvider).go('/groups/${Uri.encodeComponent(groupId)}/member-names');
    if (g.readGate != null || !ready) { await tester.pump(); }
    else { await tester.pumpAndSettle(); }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink()); container.dispose();
      if (auth.readGate != null && !auth.readGate!.isCompleted) auth.readGate!.complete('Private');
      if (g.readGate != null && !g.readGate!.isCompleted) g.readGate!.complete();
      if (g.writeGate != null && !g.writeGate!.isCompleted) g.writeGate!.complete();
      await auth.changes.close();
    });
    return (container: container, auth: auth, gateway: g);
  }
  Future<void> open(WidgetTester tester, [String value = ' Explicit public ']) async {
    await tester.enterText(find.byType(TextFormField), value);
    await tester.ensureVisible(find.text('Publish / change name'));
    await tester.tap(find.text('Publish / change name')); await tester.pumpAndSettle();
  }
  testWidgets('blank initial form never reads/copies private displayName/email', (tester) async {
    final f = await mount(tester);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, '');
    expect(find.textContaining('PRIVATE NAME'), findsNothing); expect(find.textContaining('PRIVATE EMAIL'), findsNothing);
    expect(f.gateway.writes, isEmpty);
  });
  testWidgets('own published name read separately populates form even absent from page', (tester) async {
    await mount(tester, gateway: FakeDisplays()..own = name('a', 'My published'));
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, 'My published');
    expect(find.byKey(const ValueKey('name-a')), findsNothing);
    expect(find.text('Your current published name: My published'), findsOneWidget);
  });
  testWidgets('nonunique untrusted literal names rendered alongside UIDs', (tester) async {
    await mount(tester, gateway: FakeDisplays()..rows = [name('b', '<b>Same</b>'), name('c', '<b>Same</b>')]);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('name-c')), 300,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    expect(find.text('<b>Same</b>'), findsNWidgets(2)); expect(find.text('UID: b'), findsOneWidget); expect(find.text('UID: c'), findsOneWidget);
  });
  testWidgets('disclosure confirmation cancel does not publish', (tester) async {
    final f = await mount(tester); await open(tester);
    expect(find.byType(FirebaseMemberDisplayDialog), findsOneWidget);
    expect(find.text(memberDisplayDisclosure), findsNWidgets(2));
    expect(find.text('Name: Explicit public'), findsOneWidget); expect(find.text('UID: a'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(f.gateway.writes, isEmpty);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, ' Explicit public ');
  });
  testWidgets('confirm publish trim ACK blocks button double tap while pending', (tester) async {
    final f = await mount(tester, gateway: FakeDisplays()..writeGate = Completer());
    await open(tester); await tester.tap(find.text('Publish name')); await tester.pump();
    expect(f.gateway.writes, ['Explicit public']);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Publish / change name')).onPressed, isNull);
    f.gateway.writeGate!.complete(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('name-ack')), findsOneWidget); expect(f.gateway.writes.length, 1);
  });
  testWidgets('ACK reload error UI not failed publish and manual refresh recovers', (tester) async {
    final f = await mount(tester); await open(tester); f.gateway.readError = StateError('offline');
    await tester.tap(find.text('Publish name')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('name-ack')), findsOneWidget); expect(find.textContaining('Do not repeat the write'), findsOneWidget);
    expect(find.byKey(const ValueKey('name-b')), findsNothing); expect(f.gateway.writes.length, 1);
    f.gateway.readError = null; await tester.ensureVisible(find.text('Refresh names'));
    await tester.tap(find.text('Refresh names')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('name-ack')), findsNothing); expect(f.gateway.writes.length, 1);
  });
  for (final end in ['switch', 'logout']) {
    testWidgets('$end during dialog destroys captured draft and cancels publish', (tester) async {
      final f = await mount(tester); await open(tester, 'Old draft');
      f.gateway.uid = 'new'; f.auth.emit(end == 'logout' ? null : const FirebaseIdentity('new', null));
      await tester.pumpAndSettle();
      expect(find.byType(FirebaseMemberDisplayDialog), findsNothing); expect(find.textContaining('Old draft'), findsNothing);
      expect(f.gateway.writes, isEmpty);
      if (end == 'switch') expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, '');
    });
    testWidgets('$end delayed response never restores old names/form', (tester) async {
      final g = FakeDisplays()..readGate = Completer(); final f = await mount(tester, gateway: g);
      f.auth.emit(end == 'logout' ? null : const FirebaseIdentity('new', null));
      g.uid = 'new'; g.rows = []; g.readGate!.complete(); await tester.pumpAndSettle();
      expect(find.text('Same name'), findsNothing); expect(find.textContaining('PRIVATE'), findsNothing);
    });
  }
  testWidgets('blank publish denied without dialog or clearing/unpublish action', (tester) async {
    final f = await mount(tester); await open(tester, '   ');
    expect(find.byType(FirebaseMemberDisplayDialog), findsNothing); expect(f.gateway.writes, isEmpty);
    expect(find.text('Enter a nonblank name of 1–100 characters.'), findsOneWidget);
    expect(find.text('Unpublish'), findsNothing); expect(find.text('Delete name'), findsNothing);
  });
  testWidgets('page server failure clears rows before awaiting then shows retry no loop', (tester) async {
    final f = await mount(tester); f.gateway.readGate = Completer(); f.gateway.readError = const FormatException('Malformed names');
    await tester.tap(find.text('Refresh names')); await tester.pump();
    expect(find.byKey(const ValueKey('name-b')), findsNothing);
    f.gateway.readGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Malformed names'), findsOneWidget); expect(f.gateway.reads.length, 2);
  });
  testWidgets('full page next is replacement empty terminal, own retained', (tester) async {
    final f = await mount(tester, gateway: FakeDisplays()..own = name('a', 'Own')
      ..rows = [for (var i = 0; i < 20; i++) name('b${i.toString().padLeft(2, '0')}')]);
    final scrollable = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Next names page'), 400, scrollable: scrollable);
    await tester.tap(find.text('Next names page')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('No published names on this page.'), -400, scrollable: scrollable);
    expect(find.text('No published names on this page.'), findsOneWidget);
    expect(find.text('Next names page'), findsNothing); expect(f.gateway.reads, [null, 'b19']);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, 'Own');
  });
  for (final bad in ['x/y', '__reserved__', '.', 'é' * 751]) {
    testWidgets('malformed screen path length ${bad.length} no gateway', (tester) async {
      final f = await mount(tester, groupId: bad); expect(find.text('Invalid group path.'), findsOneWidget);
      expect(f.gateway.reads, isEmpty);
    });
  }
  testWidgets('ready Firebase routed directory isolates legacy', (tester) async {
    final f = await mount(tester, routed: true);
    expect(find.text('Group display names'), findsOneWidget); expect(f.gateway.reads.length, 1);
  });
  testWidgets('unready routed deep link redirects no names gateway', (tester) async {
    final f = await mount(tester, routed: true, ready: false);
    expect(find.byType(FirebaseMemberDisplayScreen), findsNothing); expect(f.gateway.reads, isEmpty);
  });
  for (final role in FirebaseGroupRole.values) {
    testWidgets('all-role ${role.name} members page links to shared name and reads names with roster', (tester) async {
      final f = await mount(tester, groupScreen: true, role: role);
      await tester.scrollUntilVisible(find.text('Change the name others see'), 300);
      expect(find.text('Change the name others see'), findsOneWidget); expect(f.gateway.reads, isNotEmpty);
      expect(find.textContaining('PRIVATE'), findsNothing);
    });
  }
}