import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firebase_chat_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firestore_highlights_gateway.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firebase_moderation_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firestore_moderation_gateway.dart';
import 'package:om_sai_ram/features/firebase_moderation/providers/firebase_moderation_provider.dart';
import 'package:om_sai_ram/features/firebase_moderation/presentation/firebase_moderation_screen.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_groups_test.dart' as groups;
import 'firebase_highlights_test.dart' as highlights;
import 'firebase_moderation_test.dart' as messages;
import 'firestore_highlights_gateway_test.dart' as highlight_data;
import 'firestore_moderation_gateway_test.dart' as data;
import 'package:om_sai_ram/features/firebase_highlights/data/firebase_highlight_models.dart';

const kind = FirebaseModerationTargetKind.highlights;
const binding = (uid: 'a', groupId: 'g', messageId: 'id0');
FirebaseModerationPage fixture({bool absent = false, bool audited = false,
    String status = 'open', FirebaseModerationBinding scope = binding}) => FirebaseModerationPage(scope, null,
  audited ? FirebaseMessageModerationRecord.parse(scope.messageId,
    {...data.markerData(), 'targetId': scope.messageId, 'targetKind': 'highlights'}, kind: kind) : null,
  [FirebaseModerationReport.parse('r', data.reportData(status: status))], kind: kind,
  target: absent ? null : FirebaseModerationHighlight(FirebaseHighlight.parse(scope.groupId, scope.messageId,
    highlight_data.highlightData(chapter: 52, paragraph: 2147483647))));

class FakeKindModeration extends messages.FakeModeration {
  final kinds = <FirebaseModerationTargetKind>[];
  @override
  Future<FirebaseModerationPage> read(String groupId, String messageId,
      {int pageSize = 20, String? after, FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) async {
    kinds.add(kind);
    if (kind == FirebaseModerationTargetKind.messages) return super.read(groupId, messageId, pageSize: pageSize, after: after);
    reads.add(after);
    if (actualRole != FirebaseGroupRole.admin) throw const FormatException('Current group admin membership required.');
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    return response ?? fixture(scope: (uid: 'a', groupId: groupId, messageId: messageId));
  }
  @override
  Future<void> remove(String groupId, String messageId, FirebaseReportReason reason,
      {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) async {
    kinds.add(kind);
    if (actualRole != FirebaseGroupRole.admin) throw const FormatException('Current group admin membership required.');
    removals.add(reason);
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    response = fixture(absent: true, audited: true, scope: (uid: 'a', groupId: groupId, messageId: messageId));
    onRemove?.call();
  }
  @override
  Future<void> resolve(String groupId, String messageId, String reporterUid, FirebaseReportStatus status,
      {FirebaseModerationTargetKind kind = FirebaseModerationTargetKind.messages}) async {
    kinds.add(kind);
    if (actualRole != FirebaseGroupRole.admin) throw const FormatException('Current group admin membership required.');
    resolutions.add((reporter: reporterUid, status: status));
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    response = fixture(status: status.name, scope: (uid: 'a', groupId: groupId, messageId: messageId));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in ['resolve', 'remove']) {
    test('highlight $operation ACK refresh failure stays acknowledged no repeat', () async {
      final gateway = FakeKindModeration()..readError = StateError('offline');
      final controller = FirebaseModerationController(gateway, binding, () => true, kind: kind);
      await (operation == 'remove' ? controller.remove(FirebaseReportReason.other)
        : controller.resolve('r', FirebaseReportStatus.dismissed));
      expect(controller.state.acknowledged, isTrue); expect(controller.state.page, isNull);
      expect(controller.state.error, contains('Write acknowledged; server refresh unavailable'));
      gateway.readError = null; await controller.refresh();
      expect(gateway.kinds.every((k) => k == kind), isTrue);
      expect(gateway.removals.length + gateway.resolutions.length, 1); controller.dispose();
    });
    test('highlight $operation ambiguous write blocks retry until verified', () async {
      final gateway = FakeKindModeration()..writeError = StateError('transport');
      final controller = FirebaseModerationController(gateway, binding, () => true, kind: kind);
      Future<void> write() => operation == 'remove' ? controller.remove(FirebaseReportReason.other)
        : controller.resolve('r', FirebaseReportStatus.resolved);
      await write(); await write();
      expect(controller.state.verifyBeforeRetry, isTrue);
      expect(gateway.removals.length + gateway.resolutions.length, 1);
      await controller.refresh(head: true); expect(controller.state.verifyBeforeRetry, isFalse); controller.dispose();
    });
  }
  test('highlight controller rejects message page same binding and ID', () async {
    final gateway = FakeKindModeration()..response = messages.fixture(scope: binding);
    final controller = FirebaseModerationController(gateway, binding, () => true, kind: kind);
    await controller.refresh(); expect(controller.state.page, isNull); expect(controller.state.error, isNotNull);
    controller.dispose();
  });
  for (final operation in ['read', 'resolve', 'remove']) {
    test('highlight $operation delayed session/disposal discards old payload', () async {
      for (final dispose in [false, true]) {
        var current = true;
        final gateway = FakeKindModeration()..readGate = Completer()..writeGate = Completer();
        final controller = FirebaseModerationController(gateway, binding, () => current, kind: kind);
        final pending = switch (operation) {
          'read' => controller.refresh(), 'resolve' => controller.resolve('r', FirebaseReportStatus.resolved),
          _ => controller.remove(FirebaseReportReason.other),
        };
        current = false; if (dispose) controller.dispose();
        gateway.readGate!.complete(fixture()); gateway.writeGate!.complete(); await pending;
        if (!dispose) { expect(controller.state.page, isNull); expect(controller.state.busy, isFalse); controller.dispose(); }
        if (operation != 'read') expect(gateway.reads, isEmpty);
      }
    });
  }

  Future<({ProviderContainer container, authentication.FakeGateway auth,
      FakeKindModeration gateway, highlights.FakeHighlights highlights})> mount(WidgetTester tester,
      {FakeKindModeration? fake, bool ready = true, String id = 'id0', String groupId = 'g',
      bool routed = true, bool feed = false}) async {
    tester.view.physicalSize = const Size(1100, 1800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = ready ? 'Private name' : null;
    final gateway = fake ?? FakeKindModeration(); final feedGateway = highlights.FakeHighlights();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseModerationGatewayProvider.overrideWithValue(gateway),
      firebaseHighlightsGatewayProvider.overrideWithValue(feedGateway),
      firebaseGroupsGatewayProvider.overrideWithValue(groups.FakeGroups()),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth initialized')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API initialized')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', 'private@example.com')); await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: routed ? MaterialApp.router(routerConfig: container.read(routerProvider))
        : MaterialApp(home: FirebaseModerationScreen(groupId: groupId, messageId: id, kind: kind))));
    if (routed) {
      container.read(routerProvider).go(feed ? '/groups/g/highlights'
        : '/groups/${Uri.encodeComponent(groupId)}/highlights/${Uri.encodeComponent(id)}/moderation');
    }
    if (gateway.readGate != null) {
      await tester.pump(); await tester.pump(const Duration(milliseconds: 100));
    } else {
      await tester.pumpAndSettle();
    }
    addTearDown(() async { await tester.pumpWidget(const SizedBox()); container.dispose(); await auth.changes.close(); });
    return (container: container, auth: auth, gateway: gateway, highlights: feedGateway);
  }
  for (final role in FirebaseGroupRole.values) {
    testWidgets('actual moderation role ${role.name} controls highlight entry not group/private role', (tester) async {
      final env = await mount(tester, feed: true, fake: FakeKindModeration()..actualRole = role);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Moderate'), role == FirebaseGroupRole.admin ? findsOneWidget : findsNothing);
      expect(find.text('Private name'), findsNothing); expect(find.text('private@example.com'), findsNothing);
      expect(env.gateway.roles, 1); expect(env.gateway.reads, isEmpty);
    });
  }
  for (final role in [FirebaseGroupRole.member, FirebaseGroupRole.groupLead]) {
    testWidgets('highlight direct route ${role.name} no private reads/actions', (tester) async {
      final env = await mount(tester, fake: FakeKindModeration()..actualRole = role);
      expect(find.textContaining('admin membership required'), findsOneWidget);
      expect(find.text('Remove highlight'), findsNothing); expect(find.text('Resolve'), findsNothing);
      expect(env.gateway.reads, isEmpty);
    });
  }
  testWidgets('typed highlight preview all original fields labelled unverified and no message label', (tester) async {
    await mount(tester);
    expect(find.text('Highlight moderation'), findsOneWidget);
    expect(find.textContaining('Original chapter 52 • Paragraph index 2147483647'), findsOneWidget);
    expect(find.text('Quote:   Original quote  '), findsOneWidget); expect(find.text('Comment: Reflection'), findsOneWidget);
    expect(find.text('Sender UID: public-uid'), findsOneWidget);
    expect(find.text('User-supplied, unverified quote, anchor and comment.'), findsOneWidget);
    expect(find.text('Remove message'), findsNothing);
  });
  testWidgets('highlight confirmation cancel then reason selected correct kind marker and retained reports', (tester) async {
    final env = await mount(tester);
    await tester.tap(find.text('Remove highlight')); await tester.pumpAndSettle();
    expect(find.text('Confirm highlight removal'), findsOneWidget);
    expect(find.textContaining('The highlight ID stays reserved'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(env.gateway.removals, isEmpty);
    await tester.tap(find.text('Remove highlight')); await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<FirebaseReportReason>)); await tester.pumpAndSettle();
    await tester.tap(find.text('harassment').last); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm removal')); await tester.pumpAndSettle();
    expect(env.gateway.removals, [FirebaseReportReason.harassment]);
    expect(env.gateway.kinds.every((k) => k == kind), isTrue);
    expect(find.text('Removed/unavailable'), findsOneWidget);
    expect(find.textContaining('Target kind: highlights'), findsOneWidget); expect(find.text('Resolve'), findsOneWidget);
  });
  testWidgets('deleted target still shows retained report and marker resolve does not force remove', (tester) async {
    final env = await mount(tester, fake: FakeKindModeration()..response = fixture(absent: true, audited: true));
    expect(find.text('Remove highlight'), findsNothing); expect(find.text('Reporter UID: r'), findsOneWidget);
    await tester.tap(find.text('Dismiss')); await tester.pumpAndSettle();
    expect(env.gateway.resolutions.single.status, FirebaseReportStatus.dismissed); expect(env.gateway.removals, isEmpty);
  });
  testWidgets('admin navigation pop refreshes newest highlights removes deleted item', (tester) async {
    final env = await mount(tester, feed: true);
    env.gateway.onRemove = () => env.highlights.response = FirebaseHighlightsPage('a', 'g', []);
    await tester.tap(find.text('Moderate')); await tester.pumpAndSettle();
    expect(find.text('Highlight moderation'), findsOneWidget);
    expect(env.container.read(routerProvider).routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/groups/g/highlights/id0/moderation');
    await tester.tap(find.text('Remove highlight')); await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm removal')); await tester.pumpAndSettle();
    env.container.read(routerProvider).pop(); await tester.pumpAndSettle();
    expect(env.highlights.reads.length, 2); expect(env.highlights.reads.last, isNull);
    expect(find.text('Confirmed reflection'), findsNothing); expect(find.text('No highlights on this page.'), findsOneWidget);
  });
  testWidgets('role provider revocation immediately clears old moderation page and dialog actions', (tester) async {
    final env = await mount(tester);
    await tester.tap(find.text('Remove highlight')); await tester.pumpAndSettle();
    env.gateway.actualRole = FirebaseGroupRole.member;
    env.container.invalidate(firebaseModerationRoleProvider((uid: 'a', groupId: 'g'))); await tester.pumpAndSettle();
    expect(find.text('Comment: Reflection'), findsNothing); expect(find.text('Reporter UID: r'), findsNothing);
    expect(find.text('Confirm removal'), findsNothing); expect(env.gateway.removals, isEmpty);
  });
  testWidgets('highlight ACK read failure clears data and never claims failed write', (tester) async {
    final env = await mount(tester); env.gateway.readError = StateError('offline');
    await tester.tap(find.text('Resolve')); await tester.pumpAndSettle();
    expect(find.text('Moderation write acknowledged.'), findsOneWidget);
    expect(find.textContaining('Write acknowledged; server refresh unavailable'), findsOneWidget);
    expect(find.text('Comment: Reflection'), findsNothing); expect(env.gateway.resolutions.length, 1);
    env.gateway.readError = null;
    await tester.tap(find.text('Refresh first page')); await tester.pumpAndSettle();
    expect(find.text('Moderation write acknowledged.'), findsOneWidget);
    expect(env.gateway.resolutions.length, 1);
  });
  testWidgets('same ID separate kind providers never collide', (tester) async {
    final env = await mount(tester);
    const highlightBinding = (scope: binding, kind: kind);
    const messageBinding = (scope: binding, kind: FirebaseModerationTargetKind.messages);
    final sub = env.container.listen(firebaseTargetModerationProvider(messageBinding), (_, __) {});
    await tester.pumpAndSettle();
    final highlightController = env.container.read(firebaseTargetModerationProvider(highlightBinding).notifier);
    final messageController = env.container.read(firebaseTargetModerationProvider(messageBinding).notifier);
    expect(identical(highlightController, messageController), isFalse);
    await messageController.refresh(head: true); await tester.pumpAndSettle();
    expect(env.container.read(firebaseTargetModerationProvider(messageBinding)).page, isNotNull,
      reason: env.container.read(firebaseTargetModerationProvider(messageBinding)).error);
    expect(env.container.read(firebaseTargetModerationProvider(highlightBinding)).page!.target, isA<FirebaseModerationHighlight>());
    expect(env.container.read(firebaseTargetModerationProvider(messageBinding)).page!.target, isA<FirebaseModerationMessage>());
    sub.close();
  });
  for (final invalid in ['', '..', 'a/b', '__reserved__']) {
    testWidgets('invalid direct highlight route $invalid no SDK/role reads', (tester) async {
      final env = await mount(tester, id: invalid, routed: false);
      expect(find.text('Invalid moderation route.'), findsOneWidget); expect(env.gateway.reads, isEmpty); expect(env.gateway.roles, 0);
    });
  }
  testWidgets('highlight group guard pending profile and logout no legacy initialization', (tester) async {
    final env = await mount(tester, ready: false);
    expect(env.container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
    expect(env.gateway.reads, isEmpty);
  });
  testWidgets('logout deep highlight moderation discards loaded reports and target', (tester) async {
    final env = await mount(tester); env.auth.emit(null); await tester.pumpAndSettle();
    expect(env.container.read(routerProvider).routeInformationProvider.value.uri.path, '/');
    expect(find.text('Reporter UID: r'), findsNothing); expect(find.text('Comment: Reflection'), findsNothing);
  });
  testWidgets('delayed actual role after logout cannot expose highlight admin link', (tester) async {
    final gateway = FakeKindModeration()..roleGate = Completer();
    final env = await mount(tester, fake: gateway, feed: true);
    env.auth.emit(null); await tester.pumpAndSettle();
    gateway.roleGate!.complete(FirebaseGroupRole.admin); await tester.pumpAndSettle();
    expect(find.text('Moderate'), findsNothing); expect(gateway.reads, isEmpty);
  });
  testWidgets('delayed highlight reports after role revocation are discarded', (tester) async {
    final gateway = FakeKindModeration()..readGate = Completer();
    final env = await mount(tester, fake: gateway);
    gateway.actualRole = FirebaseGroupRole.member;
    env.container.invalidate(firebaseModerationRoleProvider((uid: 'a', groupId: 'g')));
    await tester.pumpAndSettle(); gateway.readGate!.complete(fixture()); await tester.pumpAndSettle();
    expect(find.text('Reporter UID: r'), findsNothing); expect(find.text('Comment: Reflection'), findsNothing);
    expect(find.text('Remove highlight'), findsNothing);
  });
}