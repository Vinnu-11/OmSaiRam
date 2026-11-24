import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/core/services/firebase_bootstrap.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firebase_highlight_models.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firestore_highlights_gateway.dart';
import 'package:om_sai_ram/features/firebase_highlights/providers/firebase_highlights_provider.dart';
import 'package:om_sai_ram/features/firebase_highlights/presentation/firebase_highlights_screen.dart';
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_groups_test.dart' as groups;
import 'group_home_overrides.dart';
import 'firebase_chat_test.dart' as services;
import 'firestore_highlights_gateway_test.dart' as sdk;

const binding = (uid: 'a', groupId: 'g');
FirebaseHighlightsPage fixture({String uid = 'a', String groupId = 'g', int count = 1,
    int seconds = 1700000000, String text = 'Confirmed reflection'}) => FirebaseHighlightsPage(uid, groupId, [
  for (var i = 0; i < count; i++) FirebaseHighlight.parse(groupId, 'id$i',
    sdk.highlightData(time: Timestamp(seconds - i, 123456789), text: text))
]);
class FakeHighlights implements FirebaseHighlightsGateway {
  final reads = <FirebaseHighlightCursor?>[];
  final sends = <({String groupId, FirebaseHighlightDraft draft})>[];
  final reports = <({String groupId, String id, FirebaseHighlightReportReason reason, String details})>[];
  Completer<FirebaseHighlightsPage>? readGate;
  Completer<void>? sendGate, reportGate;
  Object? readError, sendError, reportError;
  FirebaseHighlightsPage? response;
  @override
  Future<FirebaseHighlightsPage> read(String groupId, {int pageSize = 20, FirebaseHighlightCursor? after}) async {
    expect(pageSize, 20); reads.add(after);
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    return response ?? fixture(groupId: groupId, seconds: after == null ? 1700000000 : after.createdAt.seconds - 1);
  }
  @override
  Future<void> send(String groupId, FirebaseHighlightDraft draft) async {
    sends.add((groupId: groupId, draft: draft));
    if (sendGate != null) await sendGate!.future;
    if (sendError != null) throw sendError!;
  }
  @override
  Future<void> report(String groupId, String highlightId, FirebaseHighlightReportReason reason, String details) async {
    reports.add((groupId: groupId, id: highlightId, reason: reason, details: details));
    if (reportGate != null) await reportGate!.future;
    if (reportError != null) throw reportError!;
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('named bundle preserves injected highlights and existing six-service constructor', () {
    final highlights = FakeHighlights();
    final bundle = FirebaseServiceBundle(auth_test.FakeGateway(), groups.FakeGroups(),
      services.UnusedAssignments(), services.UnusedTasks(), services.FakeChat(),
      services.UnusedModeration(), highlights: highlights);
    expect(identical(bundle.highlights, highlights), isTrue);
  });
  test('bootstrap other mode rejected before any default Firebase SDK initialization', () async {
    await expectLater(bootstrapFirebase(auth_test.config(mode: 'fastapi')), throwsStateError);
  });
  for (final poison in ['uid', 'group', 'row-group', 'duplicate', 'order', 'too-many', 'after']) {
    test('controller rejects injected $poison page entirely', () async {
      final fake = FakeHighlights(); final row = fixture().highlights.single;
      fake.response = switch (poison) {
        'uid' => fixture(uid: 'b'), 'group' => fixture(groupId: 'other'),
        'row-group' => FirebaseHighlightsPage('a', 'g', fixture(groupId: 'other').highlights),
        'duplicate' => FirebaseHighlightsPage('a', 'g', [row, row]),
        'order' => FirebaseHighlightsPage('a', 'g', fixture(count: 2).highlights.reversed),
        'too-many' => fixture(count: 21), _ => fixture()
      };
      final controller = FirebaseHighlightsController(fake, binding, () => true);
      await controller.refresh(after: poison == 'after' ? row.cursor : null);
      expect(controller.state.page, isNull); expect(controller.state.error, isNotNull);
      controller.dispose();
    });
  }
  test('older page replacement retry same original cursor and explicit head reset', () async {
    final fake = FakeHighlights()..response = fixture(count: 20);
    final controller = FirebaseHighlightsController(fake, binding, () => true);
    await controller.refresh(); final cursor = controller.state.page!.cursor;
    fake.response = null; fake.readError = StateError('private failure');
    await controller.refresh(after: cursor);
    expect(controller.state.page, isNull); expect(controller.state.error, isNot(contains('private failure')));
    fake.readError = null; fake.readGate = Completer(); final pending = controller.refresh();
    expect(controller.state.page, isNull); expect(controller.state.busy, isTrue);
    fake.readGate!.complete(fixture(seconds: cursor!.createdAt.seconds - 1)); await pending;
    expect(identical(fake.reads.last, cursor), isTrue);
    fake.readGate = null; await controller.refresh(head: true);
    expect(fake.reads.last, isNull); expect(controller.state.page!.highlights.length, 1);
    controller.dispose();
  });
  test('send no optimistic record reloads head only after ACK', () async {
    final fake = FakeHighlights(); final controller = FirebaseHighlightsController(fake, binding, () => true);
    await controller.refresh(); fake.sendGate = Completer();
    final sent = controller.send(52, 2147483647, '  Quote  ', ' Comment ');
    expect(controller.state.page, isNull); expect(fake.reads.length, 1);
    expect(fake.sends.single.draft.chapterNumber, 52);
    expect(fake.sends.single.draft.paragraphIndex, 2147483647);
    expect(fake.sends.single.draft.quote, '  Quote  ');
    fake.sendGate!.complete(); expect(await sent, FirebaseHighlightDelivery.acknowledged);
    expect(fake.reads.last, isNull); controller.dispose();
  });
  test('ACK with failed reload stays acknowledged not uncertain', () async {
    final fake = FakeHighlights()..readError = StateError('offline');
    final controller = FirebaseHighlightsController(fake, binding, () => true);
    expect(await controller.send(17, 0, 'q', 't'), FirebaseHighlightDelivery.acknowledged);
    expect(controller.state.error, contains('write acknowledged; head refresh unavailable'));
    expect(controller.state.verifyBeforeRetry, isFalse); expect(controller.state.page, isNull);
    controller.dispose();
  });
  test('uncertainty blocks resend until successful head, not failed or older read', () async {
    final fake = FakeHighlights()..sendError = const FirebaseHighlightDeliveryUncertain();
    final controller = FirebaseHighlightsController(fake, binding, () => true);
    expect(await controller.send(17, 0, 'q', 't'), FirebaseHighlightDelivery.uncertain);
    expect(controller.state.error, highlightUncertainMessage);
    expect(await controller.send(17, 0, 'q', 't'), FirebaseHighlightDelivery.notAttempted);
    expect(fake.sends.length, 1); expect(fake.reads, isEmpty);
    fake.readError = StateError('offline'); await controller.refresh(head: true);
    expect(controller.state.verifyBeforeRetry, isTrue);
    fake.readError = null;
    await controller.refresh(after: FirebaseHighlightCursor(Timestamp(1800000000, 0), 'z'));
    expect(controller.state.verifyBeforeRetry, isTrue);
    await controller.refresh(head: true); expect(controller.state.verifyBeforeRetry, isFalse);
    expect(fake.sends.length, 1); controller.dispose();
  });
  for (final bad in [(0, 0, 'q', 't'), (54, 0, 'q', 't'), (17, -1, 'q', 't'),
      (17, 2147483648, 'q', 't'), (17, 0, ' ', 't'), (17, 0, 'q', ' ')]) {
    test('controller invalid manual input $bad never calls send gateway', () async {
      final fake = FakeHighlights(); final controller = FirebaseHighlightsController(fake, binding, () => true);
      expect(await controller.send(bad.$1, bad.$2, bad.$3, bad.$4), FirebaseHighlightDelivery.notAttempted);
      expect(fake.sends, isEmpty); expect(controller.state.error, isNotNull); controller.dispose();
    });
  }
  for (final operation in ['read', 'send', 'report']) {
    test('$operation delayed scope change and disposal suppress old publication', () async {
      var current = true;
      final fake = FakeHighlights()..readGate = Completer()..sendGate = Completer()..reportGate = Completer();
      final controller = FirebaseHighlightsController(fake, binding, () => current);
      Future<Object?> run(FirebaseHighlightsController c) => switch (operation) {
        'read' => c.refresh(), 'send' => c.send(17, 0, 'q', 't'),
        _ => c.report('id0', FirebaseHighlightReportReason.spam, '')
      };
      final pending = run(controller); current = false;
      fake.readGate!.complete(fixture()); fake.sendGate!.complete(); fake.reportGate!.complete();
      await pending; expect(controller.state.page, isNull); expect(controller.state.busy, isFalse);
      controller.dispose(); current = true;
      fake.readGate = Completer(); fake.sendGate = Completer(); fake.reportGate = Completer();
      final disposed = FirebaseHighlightsController(fake, binding, () => current);
      final late = run(disposed); disposed.dispose();
      fake.readGate!.complete(fixture()); fake.sendGate!.complete(); fake.reportGate!.complete(); await late;
    });
  }
  test('report clears displayed data errors and validates before gateway with accurate ACK', () async {
    final fake = FakeHighlights(); final controller = FirebaseHighlightsController(fake, binding, () => true);
    await controller.refresh();
    expect(await controller.report('id0', FirebaseHighlightReportReason.other, 'x' * 1001), isNotNull);
    expect(fake.reports, isEmpty); expect(controller.state.page, isNull);
    fake.reportError = const FormatException('You have already reported this highlight.');
    expect(await controller.report('id0', FirebaseHighlightReportReason.spam, ''), contains('already'));
    fake.reportError = StateError('private failure');
    expect(await controller.report('id0', FirebaseHighlightReportReason.spam, ''), contains('confirmation unavailable'));
    fake.reportError = null;
    expect(await controller.report('id0', FirebaseHighlightReportReason.spam, ''), isNull); controller.dispose();
  });
  test('busy operations do not issue concurrent sends reports or polling reads', () async {
    final fake = FakeHighlights()..readGate = Completer();
    final controller = FirebaseHighlightsController(fake, binding, () => true);
    final read = controller.refresh(); await controller.refresh();
    expect(await controller.send(17, 0, 'q', 't'), FirebaseHighlightDelivery.notAttempted);
    expect(await controller.report('id0', FirebaseHighlightReportReason.spam, ''), isNotNull);
    expect(fake.reads.length, 1); expect(fake.sends, isEmpty); expect(fake.reports, isEmpty);
    fake.readGate!.complete(fixture()); await read; controller.dispose();
  });

  Future<(auth_test.FakeGateway, FakeHighlights, ProviderContainer)> mount(WidgetTester tester,
      {FakeHighlights? highlights, bool ready = true, String groupId = 'g', bool routed = false,
      FirebaseGroupRole role = FirebaseGroupRole.member}) async {
    tester.view.physicalSize = const Size(1100, 1800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = auth_test.FakeGateway()..profile = ready ? 'Private name' : null;
    final fake = highlights ?? FakeHighlights();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseHighlightsGatewayProvider.overrideWithValue(fake),
      firebaseGroupsGatewayProvider.overrideWithValue(groups.FakeGroups()..role = role),
      ...groupHomeOverrides(),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth initialized')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API initialized')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', 'private@example.com')); await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: routed ? MaterialApp.router(routerConfig: container.read(routerProvider))
        : MaterialApp(home: FirebaseHighlightsScreen(groupId: groupId))));
    if (routed) container.read(routerProvider).go('/groups/${Uri.encodeComponent(groupId)}/highlights');
    await tester.pumpAndSettle();
    addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink());
      container.dispose(); await auth.changes.close(); });
    return (auth, fake, container);
  }
  Future<void> enterDraft(WidgetTester tester, {String chapter = '52', String paragraph = '2147483647'}) async {
    for (final entry in {'highlight-chapter': chapter, 'highlight-paragraph': paragraph,
      'highlight-quote': '  Manual quote  ', 'highlight-comment': 'My reflection'}.entries) {
      await tester.ensureVisible(find.byKey(Key(entry.key)));
      await tester.enterText(find.byKey(Key(entry.key)), entry.value);
    }
    await tester.ensureVisible(find.text('Share highlight')); await tester.pumpAndSettle();
  }
  testWidgets('pending profile direct screen denies reads', (tester) async {
    final (_, fake, _) = await mount(tester, ready: false);
    expect(find.text('Ready Firebase session required.'), findsOneWidget); expect(fake.reads, isEmpty);
  });
  testWidgets('guarded deep route pending profile denied without legacy SDK construction', (tester) async {
    final (_, fake, container) = await mount(tester, ready: false, routed: true);
    expect(container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
    expect(fake.reads, isEmpty); expect(find.byType(FirebaseHighlightsScreen), findsNothing);
  });
  for (final id in ['__reserved__', 'a/b', '..', 'é' * 751]) {
    testWidgets('invalid group $id blocks injected gateway', (tester) async {
      final (_, fake, _) = await mount(tester, groupId: id);
      expect(find.text('Invalid group ID.'), findsOneWidget); expect(fake.reads, isEmpty);
    });
  }
  test('invalid provider binding constructs no SDK gateway', () async {
    final auth = auth_test.FakeGateway();
    final container = ProviderContainer(overrides: [
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseHighlightsGatewayProvider.overrideWith((ref) => throw StateError('Unexpected gateway'))
    ]);
    const invalid = (uid: 'a', groupId: '__reserved__');
    final sub = container.listen(firebaseHighlightsProvider(invalid), (_, __) {});
    await container.read(firebaseHighlightsProvider(invalid).notifier).refresh();
    expect(container.read(firebaseHighlightsProvider(invalid)).page, isNull);
    sub.close(); container.dispose(); await auth.changes.close();
  });
  for (final role in FirebaseGroupRole.values) {
    testWidgets('${role.name} group detail Highlights link only guarded slice and no moderation controls', (tester) async {
      final (_, fake, container) = await mount(tester, routed: true, role: role);
      container.read(routerProvider).go('/groups/g'); await tester.pumpAndSettle();
      final action = find.byKey(const Key('group-quotes'));
      await tester.ensureVisible(action); await tester.pumpAndSettle();
      await tester.tap(action); await tester.pumpAndSettle();
      expect(container.read(routerProvider).routeInformationProvider.value.uri.path, '/groups/g/highlights');
      expect(find.text('A member'), findsOneWidget); expect(find.textContaining('public-uid'), findsNothing); expect(fake.reads.length, 2);
      expect(find.text('Private name'), findsNothing); expect(find.text('private@example.com'), findsNothing);
      expect(find.text('Moderate'), findsNothing); expect(find.text('Remove'), findsNothing);
      expect(find.textContaining('The admin can remove quotes.'), findsOneWidget);
      expect(find.textContaining('not checked against the book'), findsOneWidget);
    });
  }
  testWidgets('manual originals 52 and explicit paragraph preserve draft independent of reader', (tester) async {
    final (_, fake, _) = await mount(tester);
    await enterDraft(tester); await tester.tap(find.text('Share highlight')); await tester.pumpAndSettle();
    final sent = fake.sends.single;
    expect(sent.groupId, 'g'); expect(sent.draft.chapterNumber, 52);
    expect(sent.draft.paragraphIndex, 2147483647); expect(sent.draft.quote, '  Manual quote  ');
    expect(sent.draft.text, 'My reflection');
    expect(tester.widget<TextFormField>(find.byKey(const Key('highlight-quote'))).controller!.text, isEmpty);
  });
  testWidgets('manual blank fields validated before gateway with no fabricated paragraph default', (tester) async {
    final (_, fake, _) = await mount(tester);
    await tester.ensureVisible(find.text('Share highlight')); await tester.tap(find.text('Share highlight'));
    await tester.pumpAndSettle(); expect(fake.sends, isEmpty);
    expect(find.text('Enter an integer from 1 to 53.'), findsOneWidget);
    expect(find.text('Enter an integer from 0 to 2147483647.'), findsOneWidget);
    expect(find.text('Quote must be nonblank and at most 500 characters.'), findsOneWidget);
    expect(find.text('Comment must be nonblank and at most 2000 characters.'), findsOneWidget);
  });
  for (final inputs in [('17.0', '0'), ('54', '0'), ('17', '-1'), ('17', '2147483648')]) {
    testWidgets('manual numeric UX rejects $inputs', (tester) async {
      final (_, fake, _) = await mount(tester);
      await enterDraft(tester, chapter: inputs.$1, paragraph: inputs.$2);
      await tester.tap(find.text('Share highlight')); await tester.pumpAndSettle(); expect(fake.sends, isEmpty);
      expect(find.textContaining('Enter an integer from'), findsOneWidget);
    });
  }
  testWidgets('older replacement invalid page retry same cursor then head only', (tester) async {
    final fake = FakeHighlights()..response = fixture(count: 20);
    await mount(tester, highlights: fake);
    await tester.tap(find.text('Older highlights')); await tester.pumpAndSettle();
    expect(find.text('Confirmed reflection'), findsNothing); expect(find.byKey(const Key('highlights-error')), findsOneWidget);
    final cursor = fake.reads.last!;
    fake.response = fixture(seconds: cursor.createdAt.seconds - 1, text: 'Older only');
    await tester.tap(find.text('Retry page')); await tester.pumpAndSettle();
    expect(find.text('Older only'), findsOneWidget); expect(identical(fake.reads.last, cursor), isTrue);
    fake.response = fixture(text: 'Newest only');
    await tester.tap(find.text('Refresh newest')); await tester.pumpAndSettle();
    expect(find.text('Newest only'), findsOneWidget); expect(find.text('Older only'), findsNothing); expect(fake.reads.last, isNull);
  });
  testWidgets('empty page no older and no background polling', (tester) async {
    final (_, fake, _) = await mount(tester, highlights: FakeHighlights()..response = fixture(count: 0));
    expect(find.text('No highlights on this page.'), findsOneWidget); expect(find.text('Older highlights'), findsNothing);
    await tester.pump(const Duration(minutes: 5)); expect(fake.reads.length, 1);
  });
  testWidgets('send ACK reload failure clears draft without optimism or false failure', (tester) async {
    final (_, fake, _) = await mount(tester); await enterDraft(tester);
    fake.sendGate = Completer(); fake.readError = StateError('offline');
    await tester.tap(find.text('Share highlight')); await tester.pump();
    expect(find.text('Confirmed reflection'), findsNothing); expect(find.text('You'), findsNothing); expect(find.text('A member'), findsNothing);
    expect(fake.reads.length, 1); fake.sendGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Highlight write acknowledged.'), findsOneWidget);
    expect(find.textContaining('head refresh unavailable'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const Key('highlight-comment'))).controller!.text, isEmpty);
  });
  testWidgets('uncertain send retains all manual inputs and requires explicit successful head refresh', (tester) async {
    final (_, fake, _) = await mount(tester); await enterDraft(tester);
    fake.sendError = const FirebaseHighlightDeliveryUncertain();
    await tester.tap(find.text('Share highlight')); await tester.pumpAndSettle();
    expect(find.text(highlightUncertainMessage), findsOneWidget);
    for (final entry in {'highlight-chapter': '52', 'highlight-paragraph': '2147483647',
      'highlight-quote': '  Manual quote  ', 'highlight-comment': 'My reflection'}.entries) {
      expect(tester.widget<TextFormField>(find.byKey(Key(entry.key))).controller!.text, entry.value);
    }
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Share highlight')).onPressed, isNull);
    await tester.ensureVisible(find.text('Refresh newest')); await tester.tap(find.text('Refresh newest')); await tester.pumpAndSettle();
    expect(fake.sends.length, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Share highlight')).onPressed, isNotNull);
  });
  testWidgets('permission failure clears cards immediately retry can recover', (tester) async {
    final (_, fake, _) = await mount(tester);
    fake.readError = StateError('private auth details');
    await tester.tap(find.text('Refresh newest')); await tester.pumpAndSettle();
    expect(find.text('Confirmed reflection'), findsNothing); expect(find.textContaining('private auth details'), findsNothing);
    expect(find.byKey(const Key('highlights-error')), findsOneWidget);
    fake.readError = null; await tester.tap(find.text('Retry page')); await tester.pumpAndSettle();
    expect(find.text('Confirmed reflection'), findsOneWidget); expect(find.byKey(const Key('highlights-error')), findsNothing);
  });
  testWidgets('member report enum and details confirms only after transaction ACK', (tester) async {
    final (_, fake, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<FirebaseHighlightReportReason>)); await tester.pumpAndSettle();
    await tester.tap(find.text('other').last); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('highlight-report-details')), 'My details');
    fake.reportGate = Completer(); await tester.tap(find.text('Submit report')); await tester.pump();
    expect(find.text('Report submitted.'), findsNothing);
    expect(fake.reports.single, (groupId: 'g', id: 'id0', reason: FirebaseHighlightReportReason.other, details: 'My details'));
    fake.reportGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Report submitted.'), findsOneWidget);
    expect(find.textContaining('does not hide or remove the highlight'), findsOneWidget);
  });
  for (final error in [const FormatException('You have already reported this highlight.'),
      const FormatException('Highlight unavailable. Refresh newest highlights.'), StateError('private failure')]) {
    testWidgets('report $error never displays false success and clears cards', (tester) async {
      final (_, fake, _) = await mount(tester); fake.reportError = error;
      await tester.tap(find.text('Report')); await tester.pumpAndSettle();
      await tester.tap(find.text('Submit report')); await tester.pumpAndSettle();
      expect(find.text('Report submitted.'), findsNothing); expect(find.text('Confirmed reflection'), findsNothing);
      expect(find.textContaining('private failure'), findsNothing);
      expect(find.byKey(const Key('highlights-error')), findsOneWidget);
    });
  }
  testWidgets('old UID report dialog wipes fields reason and cannot submit as new UID', (tester) async {
    final (auth, fake, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('highlight-report-details')), 'Old private draft');
    auth.emit(const FirebaseIdentity('b', null)); await tester.pumpAndSettle();
    expect(find.text('Report closed: account changed.'), findsOneWidget);
    expect(find.text('Submit report'), findsNothing); expect(find.text('Old private draft'), findsNothing);
    expect(fake.reports, isEmpty);
  });
  testWidgets('account switch during report ACK suppresses stale success', (tester) async {
    final (auth, fake, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    fake.reportGate = Completer(); await tester.tap(find.text('Submit report')); await tester.pump();
    auth.emit(null); await tester.pump(); fake.reportGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Report submitted.'), findsNothing); expect(find.text('Report closed: account changed.'), findsOneWidget);
  });
  testWidgets('close dialog while report pending cannot update disposed form', (tester) async {
    final (_, fake, _) = await mount(tester);
    await tester.tap(find.text('Report')); await tester.pumpAndSettle();
    fake.reportGate = Completer(); await tester.tap(find.text('Submit report')); await tester.pump();
    await tester.tap(find.text('Close')); await tester.pump(const Duration(milliseconds: 300));
    fake.reportGate!.complete(); await tester.pumpAndSettle(); expect(tester.takeException(), isNull);
    expect(find.text('Report submitted.'), findsNothing);
  });
  testWidgets('logout delayed refresh clears page all drafts and suppresses late results', (tester) async {
    final (auth, fake, _) = await mount(tester); await enterDraft(tester);
    fake.readGate = Completer(); await tester.ensureVisible(find.text('Refresh newest'));
    await tester.tap(find.text('Refresh newest')); await tester.pump();
    auth.emit(null); await tester.pump(); fake.readGate!.complete(fixture()); await tester.pumpAndSettle();
    expect(find.text('Ready Firebase session required.'), findsOneWidget);
    expect(find.text('Confirmed reflection'), findsNothing); expect(find.text('My reflection'), findsNothing);
  });
  testWidgets('dispose delayed send cannot reread head or modify disposed draft', (tester) async {
    final (_, fake, _) = await mount(tester); await enterDraft(tester);
    fake.sendGate = Completer(); await tester.tap(find.text('Share highlight')); await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pumpAndSettle();
    fake.sendGate!.complete(); await tester.pumpAndSettle();
    expect(fake.reads.length, 1); expect(tester.takeException(), isNull);
  });
  testWidgets('ready deep highlights URL redirects on logout no legacy restoration', (tester) async {
    final (auth, _, container) = await mount(tester, routed: true);
    expect(find.text('Shared quotes'), findsOneWidget);
    auth.emit(null); await tester.pumpAndSettle();
    expect(container.read(routerProvider).routeInformationProvider.value.uri.path, '/');
    expect(find.text('Shared quotes'), findsNothing);
  });
  testWidgets('UID-bound provider autoDispose recreates clean controller after navigation', (tester) async {
    final (_, fake, container) = await mount(tester, routed: true); await enterDraft(tester);
    fake.sendError = const FirebaseHighlightDeliveryUncertain();
    await tester.tap(find.text('Share highlight')); await tester.pumpAndSettle();
    expect(container.read(firebaseHighlightsProvider(binding)).verifyBeforeRetry, isTrue);
    container.read(routerProvider).go('/groups/g'); await tester.pumpAndSettle();
    container.read(routerProvider).go('/groups/g/highlights'); await tester.pumpAndSettle();
    expect(container.read(firebaseHighlightsProvider(binding)).verifyBeforeRetry, isFalse);
    expect(container.read(firebaseHighlightsProvider(binding)).error, isNull);
    expect(tester.widget<TextFormField>(find.byKey(const Key('highlight-comment'))).controller!.text, isEmpty);
  });
}