import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/firebase_bootstrap.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firebase_chat_models.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firestore_chat_gateway.dart';
import 'package:om_sai_ram/features/firebase_chat/providers/firebase_chat_provider.dart';
import 'package:om_sai_ram/features/firebase_chat/presentation/firebase_chat_screen.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firestore_tasks_gateway.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firestore_moderation_gateway.dart';
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_groups_test.dart' as groups;
import 'firestore_chat_gateway_test.dart' as sdk;
import 'group_home_overrides.dart';

const binding = (uid: 'a', groupId: 'g');
FirebaseChatPage fixture({String uid = 'a', String groupId = 'g', int count = 1,
    int seconds = 1700000000, String text = 'Confirmed message'}) => FirebaseChatPage(uid, groupId, [
  for (var i = 0; i < count; i++) FirebaseChatMessage.parse(groupId, 'id$i',
    sdk.messageData(time: Timestamp(seconds - i, 123456789), text: text))
]);
class FakeChat implements FirebaseChatGateway {
  final reads = <FirebaseChatCursor?>[];
  final sends = <String>[];
  final reports = <({String groupId, String id, FirebaseReportReason reason, String details})>[];
  Completer<FirebaseChatPage>? readGate;
  Completer<void>? sendGate, reportGate;
  Object? readError, sendError, reportError;
  FirebaseChatPage? response;
  @override
  Future<FirebaseChatPage> read(String groupId, {int pageSize = 20, FirebaseChatCursor? after}) async {
    expect(pageSize, 20);
    reads.add(after);
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    return response ?? fixture(groupId: groupId, seconds: after == null ? 1700000000 : after.createdAt.seconds - 1);
  }
  @override
  Future<void> send(String groupId, String text) async {
    sends.add(text);
    if (sendGate != null) await sendGate!.future;
    if (sendError != null) throw sendError!;
  }
  @override
  Future<void> report(String groupId, String messageId, FirebaseReportReason reason, String details) async {
    reports.add((groupId: groupId, id: messageId, reason: reason, details: details));
    if (reportGate != null) await reportGate!.future;
    if (reportError != null) throw reportError!;
  }
}

class UnusedAssignments extends Fake implements FirebaseAssignmentsGateway {}
class UnusedTasks extends Fake implements FirebaseTasksGateway {}
class UnusedModeration extends Fake implements FirebaseModerationGateway {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bundle stores injected chat service without default SDK initialization', () {
    final chat = FakeChat();
    final bundle = FirebaseServiceBundle(auth_test.FakeGateway(), groups.FakeGroups(),
      UnusedAssignments(), UnusedTasks(), chat, UnusedModeration());
    expect(identical(bundle.chat, chat), isTrue);
  });
  for (final poison in ['uid', 'group', 'duplicate', 'order', 'too-many', 'after']) {
    test('controller rejects injected $poison page without partial data', () async {
      final chat = FakeChat();
      final row = fixture().messages.single;
      chat.response = switch (poison) {
        'uid' => fixture(uid: 'b'), 'group' => fixture(groupId: 'other'),
        'duplicate' => FirebaseChatPage('a', 'g', [row, row]),
        'order' => FirebaseChatPage('a', 'g', fixture(count: 2).messages.reversed),
        'too-many' => fixture(count: 21), _ => fixture()
      };
      final controller = FirebaseChatController(chat, binding, () => true);
      await controller.refresh(after: poison == 'after' ? row.cursor : null);
      expect(controller.state.page, isNull); expect(controller.state.error, isNotNull);
      controller.dispose();
    });
  }
  test('replacement older pages preserve failed cursor retry and refresh HEAD', () async {
    final chat = FakeChat()..response = fixture(count: 20);
    final controller = FirebaseChatController(chat, binding, () => true);
    await controller.refresh();
    final cursor = controller.state.page!.cursor;
    chat.response = null; chat.readError = StateError('private transport details');
    await controller.refresh(after: cursor);
    expect(controller.state.page, isNull); expect(controller.state.error, isNot(contains('private transport')));
    chat.readError = null; chat.readGate = Completer();
    final retry = controller.refresh();
    expect(controller.state.busy, isTrue); expect(controller.state.page, isNull);
    chat.readGate!.complete(fixture(seconds: cursor!.createdAt.seconds - 1)); await retry;
    expect(identical(chat.reads.last, cursor), isTrue);
    chat.readGate = null; await controller.refresh(head: true);
    expect(chat.reads.last, isNull); expect(controller.state.page!.messages.length, 1);
    controller.dispose();
  });
  test('send clears older history before await then refreshes HEAD only after write ACK', () async {
    final chat = FakeChat(); final controller = FirebaseChatController(chat, binding, () => true);
    await controller.refresh(after: FirebaseChatCursor(Timestamp(1800000000, 1), 'z'));
    chat.sendGate = Completer(); final sent = controller.send('original');
    expect(controller.state.page, isNull); expect(controller.state.busy, isTrue);
    expect(chat.reads.length, 1);
    chat.sendGate!.complete(); expect(await sent, FirebaseChatDelivery.acknowledged);
    expect(chat.reads.last, isNull); expect(chat.sends, ['original']);
    controller.dispose();
  });
  test('write ACK with failed read is not falsely failed delivery', () async {
    final chat = FakeChat()..readError = StateError('offline');
    final controller = FirebaseChatController(chat, binding, () => true);
    expect(await controller.send('text'), FirebaseChatDelivery.acknowledged);
    expect(controller.state.delivery, FirebaseChatDelivery.acknowledged);
    expect(controller.state.error, contains('write acknowledged'));
    expect(controller.state.page, isNull); controller.dispose();
  });
  test('ambiguous write keeps verification barrier, no automatic resend, head verification removes barrier', () async {
    final chat = FakeChat()..sendError = const FirebaseChatDeliveryUncertain();
    final controller = FirebaseChatController(chat, binding, () => true);
    expect(await controller.send('text'), FirebaseChatDelivery.uncertain);
    expect(controller.state.error, chatUncertainMessage);
    expect(await controller.send('text'), FirebaseChatDelivery.notAttempted);
    expect(chat.sends.length, 1); expect(chat.reads, isEmpty);
    chat.readError = StateError('offline'); await controller.refresh(head: true);
    expect(controller.state.verifyBeforeRetry, isTrue);
    chat.readError = null; await controller.refresh(head: true);
    expect(controller.state.verifyBeforeRetry, isFalse); expect(chat.sends.length, 1);
    controller.dispose();
  });
  test('non-head page cannot clear ambiguous delivery verification barrier', () async {
    final chat = FakeChat()..sendError = const FirebaseChatDeliveryUncertain();
    final controller = FirebaseChatController(chat, binding, () => true);
    await controller.send('text');
    await controller.refresh(after: FirebaseChatCursor(Timestamp(1800000000, 0), 'z'));
    expect(controller.state.verifyBeforeRetry, isTrue); controller.dispose();
  });
  test('prewrite validation returns notAttempted and does not call gateway', () async {
    final chat = FakeChat(); final controller = FirebaseChatController(chat, binding, () => true);
    expect(await controller.send('  '), FirebaseChatDelivery.notAttempted);
    expect(chat.sends, isEmpty); expect(controller.state.error, contains('nonblank'));
    controller.dispose();
  });
  for (final operation in ['read', 'send', 'report']) {
    test('$operation delayed UID change and disposal cannot publish old result', () async {
      var current = true;
      final chat = FakeChat()..readGate = Completer()..sendGate = Completer()..reportGate = Completer();
      final controller = FirebaseChatController(chat, binding, () => current);
      Future<Object?> run() => switch (operation) {
        'read' => controller.refresh(), 'send' => controller.send('text'),
        _ => controller.report('id0', FirebaseReportReason.spam, '')
      };
      final request = run(); current = false;
      chat.readGate!.complete(fixture()); chat.sendGate!.complete(); chat.reportGate!.complete();
      await request; expect(controller.state.page, isNull); expect(controller.state.busy, isFalse);
      controller.dispose();
      current = true; chat.readGate = Completer(); chat.sendGate = Completer(); chat.reportGate = Completer();
      final disposed = FirebaseChatController(chat, binding, () => current);
      final lateRequest = operation == 'read' ? disposed.refresh() : operation == 'send'
          ? disposed.send('text') : disposed.report('id0', FirebaseReportReason.spam, '');
      disposed.dispose(); chat.readGate!.complete(fixture()); chat.sendGate!.complete(); chat.reportGate!.complete();
      await lateRequest;
    });
  }
  test('report validation duplicate and no ACK keep generic accurate errors', () async {
    final chat = FakeChat(); final controller = FirebaseChatController(chat, binding, () => true);
    expect(await controller.report('id0', FirebaseReportReason.other, 'x' * 1001), isNotNull);
    expect(chat.reports, isEmpty);
    chat.reportError = const FormatException('You have already reported this message.');
    expect(await controller.report('id0', FirebaseReportReason.spam, ''), contains('already'));
    chat.reportError = StateError('private error');
    expect(await controller.report('id0', FirebaseReportReason.spam, ''), contains('confirmation unavailable'));
    chat.reportError = null;
    expect(await controller.report('id0', FirebaseReportReason.spam, ''), isNull);
    controller.dispose();
  });

  Future<(auth_test.FakeGateway, FakeChat, ProviderContainer)> mount(WidgetTester tester,
      {FakeChat? chat, bool ready = true, String groupId = 'g', bool routed = false,
        FirebaseGroupRole role = FirebaseGroupRole.member}) async {
    tester.view.physicalSize = const Size(1100, 1500); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = auth_test.FakeGateway()..profile = ready ? 'Private name' : null;
    final fake = chat ?? FakeChat();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseChatGatewayProvider.overrideWithValue(fake),
      firebaseGroupsGatewayProvider.overrideWithValue(groups.FakeGroups()..role = role),
      ...groupHomeOverrides(),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth initialized')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API initialized')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', 'private@example.com')); await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: routed ? MaterialApp.router(routerConfig: container.read(routerProvider))
          : MaterialApp(home: FirebaseChatScreen(groupId: groupId))));
    if (routed) container.read(routerProvider).go('/groups/${Uri.encodeComponent(groupId)}/chat');
    await tester.pumpAndSettle();
    addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); container.dispose(); await auth.changes.close(); });
    return (auth, fake, container);
  }
  testWidgets('pending profile direct and guarded URL have no reads or legacy initialization', (tester) async {
    final (_, chat, container) = await mount(tester, ready: false, routed: true);
    expect(container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
    expect(chat.reads, isEmpty); expect(find.text('Group chat'), findsNothing);
  });
  testWidgets('archived chat displays history with disabled composer and report controls', (tester) async {
    final response = fixture();
    final fake = FakeChat()..response = FirebaseChatPage('a', 'g', response.messages, archived: true);
    await mount(tester, chat: fake);
    expect(find.text('Archived • Read-only'), findsOneWidget);
    expect(find.text('Confirmed message'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-draft'))).enabled, false);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Report')).onPressed, isNull);
    expect(fake.sends, isEmpty); expect(fake.reports, isEmpty);
  });
  for (final id in ['__reserved__', 'a/b', '..', 'é' * 751]) {
    testWidgets('invalid group $id screen validates before injected gateway', (tester) async {
      final (_, chat, _) = await mount(tester, groupId: id);
      expect(find.text('Invalid group ID.'), findsOneWidget); expect(chat.reads, isEmpty);
    });
  }
  test('invalid provider binding never constructs even injected SDK gateway', () async {
    final auth = auth_test.FakeGateway();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseChatGatewayProvider.overrideWith((ref) => throw StateError('Constructed invalid SDK gateway'))
    ]);
    const invalid = (uid: 'a', groupId: '__reserved__');
    final sub = container.listen(firebaseChatProvider(invalid), (_, __) {});
    await container.read(firebaseChatProvider(invalid).notifier).refresh();
    expect(container.read(firebaseChatProvider(invalid)).page, isNull);
    sub.close(); container.dispose(); await auth.changes.close();
  });
  for (final role in FirebaseGroupRole.values) {
    testWidgets('${role.name} detail Chat action navigates guarded Firebase chat only', (tester) async {
      final (_, chat, container) = await mount(tester, routed: true, role: role);
      container.read(routerProvider).go('/groups/g'); await tester.pumpAndSettle();
      final action = find.byKey(const Key('group-chat'));
      await tester.ensureVisible(action); await tester.pumpAndSettle();
      await tester.tap(action); await tester.pumpAndSettle();
      expect(container.read(routerProvider).routeInformationProvider.value.uri.path, '/groups/g/chat');
      expect(find.text('A member'), findsOneWidget); expect(find.textContaining('public-uid'), findsNothing); expect(chat.reads.length, 2);
      expect(find.text('Private name'), findsNothing); expect(find.text('private@example.com'), findsNothing);
    });
  }
  testWidgets('manual bounded older replacement retry and head refresh controls', (tester) async {
    final fake = FakeChat()..response = fixture(count: 20);
    final (_, chat, _) = await mount(tester, chat: fake);
    await tester.tap(find.text('Older messages')); await tester.pumpAndSettle();
    // An invalid injected repeat of head is rejected rather than accumulated.
    expect(find.text('Confirmed message'), findsNothing); expect(find.byKey(const Key('chat-error')), findsOneWidget);
    final oldCursor = chat.reads.last;
    chat.response = fixture(seconds: oldCursor!.createdAt.seconds - 1, text: 'Older only');
    await tester.tap(find.text('Retry page')); await tester.pumpAndSettle();
    expect(find.text('Older only'), findsOneWidget); expect(identical(chat.reads.last, oldCursor), isTrue);
    chat.response = fixture(text: 'Newest only'); await tester.tap(find.text('Refresh newest')); await tester.pumpAndSettle();
    expect(find.text('Newest only'), findsOneWidget); expect(find.text('Older only'), findsNothing);
    expect(chat.reads.last, isNull);
  });
  testWidgets('empty page no older action and no background polling', (tester) async {
    final (_, chat, _) = await mount(tester, chat: FakeChat()..response = fixture(count: 0));
    expect(find.text('No messages on this page.'), findsOneWidget); expect(find.text('Older messages'), findsNothing);
    await tester.pump(const Duration(minutes: 5)); expect(chat.reads.length, 1);
  });
  testWidgets('send no optimism clears draft only on ACK even if history refresh fails', (tester) async {
    final (auth, chat, _) = await mount(tester);
    await tester.enterText(find.byKey(const Key('chat-draft')), 'Unsent draft');
    chat.sendGate = Completer(); chat.readError = StateError('offline');
    await tester.tap(find.text('Send')); await tester.pump();
    expect(find.text('Confirmed message'), findsNothing); expect(find.text('You'), findsNothing); expect(find.text('A member'), findsNothing);
    expect(chat.reads.length, 1);
    chat.sendGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Message sent.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-draft'))).controller!.text, isEmpty);
    expect(find.textContaining('history refresh unavailable'), findsOneWidget);
    expect(auth.currentUser!.uid, 'a');
  });
  testWidgets('uncertain delivery retains draft and disables send until explicit head verification', (tester) async {
    final (_, chat, _) = await mount(tester);
    chat.sendError = const FirebaseChatDeliveryUncertain();
    await tester.enterText(find.byKey(const Key('chat-draft')), 'Maybe delivered');
    await tester.tap(find.text('Send')); await tester.pumpAndSettle();
    expect(find.text(chatUncertainMessage), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('chat-draft'))).controller!.text, 'Maybe delivered');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);
    expect(chat.sends.length, 1);
    await tester.tap(find.text('Refresh newest')); await tester.pumpAndSettle();
    expect(chat.sends.length, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNotNull);
  });
  testWidgets('report reasons details and confirmation only after transaction ACK', (tester) async {
    final (_, chat, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<FirebaseReportReason>)); await tester.pumpAndSettle();
    await tester.tap(find.text('other').last); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('report-details')), 'My details');
    chat.reportGate = Completer(); await tester.tap(find.text('Submit report')); await tester.pump();
    expect(find.text('Report submitted.'), findsNothing);
    expect(chat.reports.single, (groupId: 'g', id: 'id0', reason: FirebaseReportReason.other, details: 'My details'));
    chat.reportGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Report submitted.'), findsOneWidget);
    expect(find.textContaining('does not hide or remove'), findsOneWidget);
  });
  testWidgets('duplicate report surfaces rejection without fake success or overwrite', (tester) async {
    final (_, chat, _) = await mount(tester);
    chat.reportError = const FormatException('You have already reported this message.');
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    await tester.tap(find.text('Submit report')); await tester.pumpAndSettle();
    expect(find.text('Report submitted.'), findsNothing);
    expect(find.text('You have already reported this message.'), findsWidgets);
    expect(chat.reports.length, 1);
  });
  testWidgets('old report dialog UID bound clears form cannot submit as new account', (tester) async {
    final (auth, chat, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('report-details')), 'Old private draft');
    auth.emit(const FirebaseIdentity('b', null)); await tester.pumpAndSettle();
    expect(find.text('Report closed: account changed.'), findsOneWidget);
    expect(find.text('Submit report'), findsNothing); expect(find.text('Old private draft'), findsNothing);
    expect(chat.reports, isEmpty);
  });
  testWidgets('account switch during report acknowledgement does not show stale confirmation', (tester) async {
    final (auth, chat, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    chat.reportGate = Completer(); await tester.tap(find.text('Submit report')); await tester.pump();
    auth.emit(null); await tester.pump(); chat.reportGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Report submitted.'), findsNothing); expect(find.text('Report closed: account changed.'), findsOneWidget);
  });
  testWidgets('logout during delayed refresh removes history and drafts; late results discarded', (tester) async {
    final (auth, chat, _) = await mount(tester);
    await tester.enterText(find.byKey(const Key('chat-draft')), 'Old draft');
    chat.readGate = Completer(); await tester.tap(find.text('Refresh newest')); await tester.pump();
    expect(find.text('Confirmed message'), findsNothing);
    auth.emit(null); await tester.pump(); chat.readGate!.complete(fixture()); await tester.pumpAndSettle();
    expect(find.text('Ready Firebase session required.'), findsOneWidget);
    expect(find.text('Confirmed message'), findsNothing); expect(find.text('Old draft'), findsNothing);
  });
  testWidgets('widget disposal during send cannot clear new account draft or set disposed state', (tester) async {
    final (_, chat, _) = await mount(tester);
    chat.sendGate = Completer(); await tester.enterText(find.byKey(const Key('chat-draft')), 'Draft');
    await tester.tap(find.text('Send')); await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
    chat.sendGate!.complete(); await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    expect(chat.reads.length, 1);
  });
  testWidgets('ready deep URL logout redirects without legacy restoration', (tester) async {
    final (auth, _, container) = await mount(tester, routed: true);
    expect(find.text('Group chat'), findsOneWidget);
    auth.emit(null); await tester.pumpAndSettle();
    expect(container.read(routerProvider).routeInformationProvider.value.uri.path, '/');
    expect(find.text('Group chat'), findsNothing);
  });
}