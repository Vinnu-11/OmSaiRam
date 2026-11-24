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
import 'package:om_sai_ram/features/firebase_chat/data/firestore_chat_gateway.dart';
import 'package:om_sai_ram/features/firebase_chat/presentation/firebase_chat_screen.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firebase_moderation_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firestore_moderation_gateway.dart';
import 'package:om_sai_ram/features/firebase_moderation/providers/firebase_moderation_provider.dart';
import 'package:om_sai_ram/features/firebase_moderation/presentation/firebase_moderation_screen.dart';
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_chat_test.dart' as chat;
import 'firebase_groups_test.dart' as groups;
import 'firestore_chat_gateway_test.dart' as sdk;
import 'firestore_moderation_gateway_test.dart' as data;

const binding = (uid: 'a', groupId: 'g', messageId: 'z');
FirebaseModerationPage fixture(
        {FirebaseModerationBinding scope = binding,
        bool absent = false,
        bool audited = false,
        int count = 1,
        String status = 'open',
        String prefix = 'r'}) =>
    FirebaseModerationPage(
        scope,
        absent
            ? null
            : FirebaseChatMessage.parse(
                scope.groupId, scope.messageId, sdk.messageData()),
        audited
            ? FirebaseMessageModerationRecord.parse(scope.messageId,
                {...data.markerData(), 'targetId': scope.messageId})
            : null,
        [
          for (var i = 0; i < count; i++)
            FirebaseModerationReport.parse(
                '$prefix${i.toString().padLeft(2, '0')}',
                data.reportData(
                    uid: '$prefix${i.toString().padLeft(2, '0')}',
                    status: status))
        ]);

class FakeModeration implements FirebaseModerationGateway {
  FirebaseGroupRole actualRole = FirebaseGroupRole.admin;
  final reads = <String?>[];
  final resolutions = <({String reporter, FirebaseReportStatus status})>[];
  final removals = <FirebaseReportReason>[];
  int roles = 0;
  Completer<FirebaseGroupRole>? roleGate;
  Completer<FirebaseModerationPage>? readGate;
  Completer<void>? writeGate;
  Object? readError, writeError, roleError;
  FirebaseModerationPage? response;
  void Function()? onRemove;
  @override
  Future<FirebaseGroupRole> role(String groupId) async {
    roles++;
    if (roleError != null) throw roleError!;
    if (roleGate != null) return roleGate!.future;
    return actualRole;
  }

  void _admin() {
    if (actualRole != FirebaseGroupRole.admin)
      throw const FormatException('Current group admin membership required.');
  }

  @override
  Future<FirebaseModerationPage> read(String groupId, String messageId,
      {int pageSize = 20,
      String? after,
      FirebaseModerationTargetKind kind =
          FirebaseModerationTargetKind.messages}) async {
    expect(pageSize, 20);
    reads.add(after);
    _admin();
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    return response ??
        fixture(scope: (uid: 'a', groupId: groupId, messageId: messageId));
  }

  @override
  Future<void> resolve(String groupId, String messageId, String reporterUid,
      FirebaseReportStatus status,
      {FirebaseModerationTargetKind kind =
          FirebaseModerationTargetKind.messages}) async {
    _admin();
    resolutions.add((reporter: reporterUid, status: status));
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    response = fixture(status: status.name);
  }

  @override
  Future<void> remove(
      String groupId, String messageId, FirebaseReportReason reason,
      {FirebaseModerationTargetKind kind =
          FirebaseModerationTargetKind.messages}) async {
    _admin();
    removals.add(reason);
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    response = fixture(
        scope: (uid: 'a', groupId: groupId, messageId: messageId),
        absent: true,
        audited: true);
    onRemove?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'replacement pagination clears data and retries same reporter cursor then head',
      () async {
    final gateway = FakeModeration()..response = fixture(count: 20);
    final controller =
        FirebaseModerationController(gateway, binding, () => true);
    await controller.refresh();
    final cursor = controller.state.page!.cursor;
    gateway.readError = StateError('offline');
    await controller.refresh(after: cursor);
    expect(controller.state.page, isNull);
    expect(controller.state.error, isNotNull);
    gateway.readError = null;
    gateway.response = fixture(prefix: 's');
    await controller.refresh();
    expect(gateway.reads.last, cursor);
    expect(controller.state.page!.reports.length, 1);
    await controller.refresh(head: true);
    expect(gateway.reads.last, isNull);
    controller.dispose();
  });
  for (final poison in [
    'uid',
    'group',
    'message',
    'duplicate',
    'order',
    'too-many',
    'cursor'
  ]) {
    test('controller discards malformed injected $poison page entirely',
        () async {
      final gateway = FakeModeration();
      final page = fixture(count: 2);
      gateway.response = switch (poison) {
        'uid' => fixture(scope: (uid: 'b', groupId: 'g', messageId: 'z')),
        'group' => fixture(scope: (uid: 'a', groupId: 'other', messageId: 'z')),
        'message' =>
          fixture(scope: (uid: 'a', groupId: 'g', messageId: 'other')),
        'duplicate' => FirebaseModerationPage(
            binding, null, null, [page.reports.first, page.reports.first]),
        'order' =>
          FirebaseModerationPage(binding, null, null, page.reports.reversed),
        'too-many' => fixture(count: 21),
        _ => fixture(),
      };
      final controller =
          FirebaseModerationController(gateway, binding, () => true);
      await controller.refresh(after: poison == 'cursor' ? 'z' : null);
      expect(controller.state.page, isNull);
      expect(controller.state.error, isNotNull);
      controller.dispose();
    });
  }
  for (final operation in ['resolve', 'remove']) {
    test('$operation no optimistic success ACK then server reload only',
        () async {
      final gateway = FakeModeration()..writeGate = Completer();
      final controller =
          FirebaseModerationController(gateway, binding, () => true);
      await controller.refresh();
      final request = operation == 'remove'
          ? controller.remove(FirebaseReportReason.spam)
          : controller.resolve('r00', FirebaseReportStatus.resolved);
      expect(controller.state.page, isNull);
      expect(controller.state.acknowledged, isFalse);
      expect(gateway.reads.length, 1);
      gateway.writeGate!.complete();
      await request;
      expect(controller.state.acknowledged, isTrue);
      expect(controller.state.page, isNotNull);
      expect(gateway.reads, [null, null]);
      controller.dispose();
    });
    test('$operation ACK refresh failure distinguished no auto repeat',
        () async {
      final gateway = FakeModeration()..readError = StateError('offline');
      final controller =
          FirebaseModerationController(gateway, binding, () => true);
      await (operation == 'remove'
          ? controller.remove(FirebaseReportReason.other)
          : controller.resolve('r00', FirebaseReportStatus.dismissed));
      expect(controller.state.acknowledged, isTrue);
      expect(controller.state.page, isNull);
      expect(controller.state.error,
          contains('Write acknowledged; server refresh unavailable'));
      expect(gateway.removals.length + gateway.resolutions.length, 1);
      gateway.readError = null;
      await controller.refresh();
      expect(controller.state.acknowledged, isTrue);
      expect(gateway.removals.length + gateway.resolutions.length, 1);
      controller.dispose();
    });
  }
  test('ambiguous write blocks retry until explicit server verification',
      () async {
    final gateway = FakeModeration()..writeError = StateError('transport');
    final controller =
        FirebaseModerationController(gateway, binding, () => true);
    await controller.remove(FirebaseReportReason.spam);
    await controller.remove(FirebaseReportReason.spam);
    expect(gateway.removals.length, 1);
    expect(controller.state.acknowledged, isFalse);
    expect(controller.state.verifyBeforeRetry, isTrue);
    gateway.readError = StateError('offline');
    await controller.refresh();
    expect(controller.state.verifyBeforeRetry, isTrue);
    gateway.readError = null;
    await controller.refresh(head: true);
    expect(controller.state.verifyBeforeRetry, isFalse);
    expect(gateway.removals.length, 1);
    controller.dispose();
  });
  for (final operation in ['read', 'resolve', 'remove']) {
    test('$operation delayed UID switch and disposal discard old responses',
        () async {
      for (final dispose in [false, true]) {
        var current = true;
        final gateway = FakeModeration()
          ..readGate = Completer()
          ..writeGate = Completer();
        final controller =
            FirebaseModerationController(gateway, binding, () => current);
        final request = switch (operation) {
          'read' => controller.refresh(),
          'resolve' => controller.resolve('r00', FirebaseReportStatus.resolved),
          _ => controller.remove(FirebaseReportReason.other),
        };
        current = false;
        if (dispose) controller.dispose();
        gateway.readGate!.complete(fixture());
        gateway.writeGate!.complete();
        await request;
        if (!dispose) {
          expect(controller.state.page, isNull);
          expect(controller.state.busy, isFalse);
          controller.dispose();
        }
        if (operation != 'read') expect(gateway.reads, isEmpty);
      }
    });
  }
  test('role revocation clears previously loaded page on action and refresh',
      () async {
    final gateway = FakeModeration();
    final controller =
        FirebaseModerationController(gateway, binding, () => true);
    await controller.refresh();
    gateway.actualRole = FirebaseGroupRole.member;
    await controller.resolve('r00', FirebaseReportStatus.resolved);
    expect(controller.state.page, isNull);
    expect(controller.state.error, contains('admin'));
    expect(controller.state.acknowledged, isFalse);
    expect(gateway.resolutions, isEmpty);
    await controller.refresh();
    expect(controller.state.page, isNull);
    controller.dispose();
  });

  Future<
          ({
            ProviderContainer container,
            auth_test.FakeGateway auth,
            FakeModeration gateway,
            chat.FakeChat chat
          })>
      mount(WidgetTester tester,
          {FakeModeration? fake,
          bool routed = false,
          bool chatScreen = false,
          bool ready = true,
          String groupId = 'g',
          String messageId = 'z'}) async {
    final auth = auth_test.FakeGateway()
      ..profile = ready ? 'Private name' : null;
    final gateway = fake ?? FakeModeration();
    final chatGateway = chat.FakeChat();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseModerationGatewayProvider.overrideWithValue(gateway),
      firebaseChatGatewayProvider.overrideWithValue(chatGateway),
      firebaseGroupsGatewayProvider.overrideWithValue(groups.FakeGroups()),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth initialized')),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API initialized')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', 'private@example.com'));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: routed
            ? MaterialApp.router(routerConfig: container.read(routerProvider))
            : MaterialApp(
                home: chatScreen
                    ? FirebaseChatScreen(groupId: groupId)
                    : FirebaseModerationScreen(
                        groupId: groupId, messageId: messageId))));
    if (routed)
      container
          .read(routerProvider)
          .go(chatScreen ? '/groups/g/chat' : '/groups/g/moderation/z');
    if (gateway.readGate != null) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    } else {
      await tester.pumpAndSettle();
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await auth.changes.close();
    });
    return (
      container: container,
      auth: auth,
      gateway: gateway,
      chat: chatGateway
    );
  }

  for (final invalid in ['', 'a/b', '__reserved__']) {
    testWidgets('invalid message route $invalid no gateway calls',
        (tester) async {
      final env = await mount(tester, messageId: invalid);
      expect(find.text('Invalid moderation route.'), findsOneWidget);
      expect(env.gateway.reads, isEmpty);
    });
  }
  testWidgets('invalid group route no gateway calls', (tester) async {
    final env = await mount(tester, groupId: 'a/b');
    expect(env.gateway.reads, isEmpty);
  });
  testWidgets('unready session refuses screen without reads', (tester) async {
    final env = await mount(tester, ready: false);
    expect(find.text('Ready Firebase session required.'), findsOneWidget);
    expect(env.gateway.reads, isEmpty);
  });
  for (final role in [FirebaseGroupRole.member, FirebaseGroupRole.groupLead]) {
    testWidgets('$role deep route denied and no chat admin link',
        (tester) async {
        await mount(tester,
          fake: FakeModeration()..actualRole = role, routed: true);
      expect(find.textContaining('admin membership required'), findsOneWidget);
      expect(find.text('Resolve'), findsNothing);
      await tester.tap(find.byTooltip('Back to group chat'));
      await tester.pumpAndSettle();
      expect(find.text('Moderate'), findsNothing);
      expect(find.text('Report'), findsOneWidget);
    });
  }
  testWidgets(
      'removed/unavailable does not claim moderated without marker; retained reports resolve',
      (tester) async {
    final env = await mount(tester,
        fake: FakeModeration()..response = fixture(absent: true));
    expect(find.text('Removed/unavailable'), findsOneWidget);
    expect(find.textContaining('Confirmed removal:'), findsNothing);
    expect(find.text('Remove message'), findsNothing);
    expect(find.text('Resolve'), findsOneWidget);
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(
        env.gateway.resolutions.single.status, FirebaseReportStatus.resolved);
    expect(find.text('Moderation write acknowledged.'), findsOneWidget);
    expect(find.text('Resolve'), findsNothing);
  });
  testWidgets(
      'removal explicit confirmation reason selection cancel no write then atomic gateway action',
      (tester) async {
    final env = await mount(tester);
    await tester.tap(find.text('Remove message'));
    await tester.pumpAndSettle();
    expect(env.gateway.removals, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(env.gateway.removals, isEmpty);
    await tester.tap(find.text('Remove message'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byType(DropdownButtonFormField<FirebaseReportReason>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('harassment').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm removal'));
    await tester.pumpAndSettle();
    expect(env.gateway.removals, [FirebaseReportReason.harassment]);
    expect(find.text('Removed/unavailable'), findsOneWidget);
    expect(find.textContaining('Confirmed removal:'), findsOneWidget);
    expect(find.text('Remove message'), findsNothing);
    expect(find.text('Resolve'), findsOneWidget);
  });
  testWidgets('confirmation account switch cannot submit old removal',
      (tester) async {
    final env = await mount(tester);
    await tester.tap(find.text('Remove message'));
    await tester.pumpAndSettle();
    env.auth.emit(const FirebaseIdentity('b', 'other@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm removal'), findsNothing);
    expect(env.gateway.removals, isEmpty);
    expect(find.textContaining('account changed'), findsOneWidget);
  });
  testWidgets('UI ACK reload failure no false failed write or stale target',
      (tester) async {
    final env = await mount(tester);
    env.gateway.readError = StateError('offline');
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Moderation write acknowledged.'), findsOneWidget);
    expect(
        find.textContaining('Write acknowledged; server refresh unavailable'),
        findsOneWidget);
    expect(find.text('Original text'), findsNothing);
    expect(find.text('Resolve'), findsNothing);
    expect(env.gateway.resolutions.length, 1);
  });
  testWidgets('refresh revoke removes every downloaded report and action',
      (tester) async {
    final env = await mount(tester);
    env.gateway.actualRole = FirebaseGroupRole.member;
    await tester.tap(find.text('Refresh first page'));
    await tester.pumpAndSettle();
    expect(find.text('Reporter UID: r00'), findsNothing);
    expect(find.text('Original text'), findsNothing);
    expect(find.text('Remove message'), findsNothing);
    expect(find.textContaining('admin membership required'), findsOneWidget);
  });
  testWidgets(
      'report paging replaces only20 rows retry cursor and head manually',
      (tester) async {
    final env = await mount(tester,
        fake: FakeModeration()..response = fixture(count: 20));
    env.gateway.readError = StateError('offline');
    await tester.tap(find.text('Next reports page'));
    await tester.pumpAndSettle();
    expect(find.text('Reporter UID: r00'), findsNothing);
    expect(env.gateway.reads.last, 'r19');
    env.gateway.readError = null;
    env.gateway.response = fixture(prefix: 's');
    await tester.tap(find.text('Retry page'));
    await tester.pumpAndSettle();
    expect(env.gateway.reads.last, 'r19');
    expect(find.text('Reporter UID: s00'), findsOneWidget);
    expect(find.text('Next reports page'), findsNothing);
    await tester.tap(find.text('Refresh first page'));
    await tester.pumpAndSettle();
    expect(env.gateway.reads.last, isNull);
  });
  testWidgets(
      'admin per-message navigation returning chat reads HEAD and removes deleted card',
      (tester) async {
    final env = await mount(tester, routed: true, chatScreen: true);
    env.gateway.onRemove =
        () => env.chat.response = FirebaseChatPage('a', 'g', []);
    await tester.tap(find.text('Moderate'));
    await tester.pumpAndSettle();
    expect(find.text('Message moderation'), findsOneWidget);
    await tester.tap(find.text('Remove message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm removal'));
    await tester.pumpAndSettle();
    expect(env.gateway.removals.length, 1);
    env.container.read(routerProvider).pop();
    await tester.pumpAndSettle();
    expect(env.chat.reads.length, 2);
    expect(env.chat.reads.last, isNull);
    expect(find.text('Confirmed message'), findsNothing);
    expect(find.text('No messages on this page.'), findsOneWidget);
  });
  testWidgets(
      'guarded moderation route logout returns auth with no legacy initialization',
      (tester) async {
    final env = await mount(tester, routed: true);
    env.auth.emit(null);
    await tester.pumpAndSettle();
    expect(
        env.container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/');
    expect(find.text('Reporter UID: r00'), findsNothing);
  });
  testWidgets('delayed role read after logout does not reveal admin chat link',
      (tester) async {
    final gate = Completer<FirebaseGroupRole>();
    final env = await mount(tester,
        fake: FakeModeration()..roleGate = gate, chatScreen: true);
    env.auth.emit(null);
    await tester.pumpAndSettle();
    gate.complete(FirebaseGroupRole.admin);
    await tester.pumpAndSettle();
    expect(find.text('Moderate'), findsNothing);
  });
  testWidgets('delayed report read after UID change cannot publish old target',
      (tester) async {
    final gate = Completer<FirebaseModerationPage>();
    final env = await mount(tester, fake: FakeModeration()..readGate = gate);
    env.auth.emit(null);
    await tester.pumpAndSettle();
    gate.complete(fixture());
    await tester.pumpAndSettle();
    expect(find.text('Original text'), findsNothing);
    expect(find.text('Reporter UID: r00'), findsNothing);
  });
}
