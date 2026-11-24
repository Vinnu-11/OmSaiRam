import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/providers/language_provider.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_reader_highlight_selection.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_assignments/presentation/firebase_assignment_reader_screen.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignment_reader_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignments_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_reader_share_provider.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firebase_highlight_models.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firestore_highlights_gateway.dart';
import 'package:om_sai_ram/features/firebase_highlights/providers/firebase_highlights_provider.dart';
import 'package:om_sai_ram/features/reader/data/chapter_model.dart';
import 'package:om_sai_ram/features/reader/data/content_repository.dart';
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_assignments_test.dart' as assignments_test;
import 'firebase_highlights_test.dart' as highlights_test;
import 'firestore_highlights_gateway_test.dart' as highlights_sdk;
import 'firestore_assignments_gateway_test.dart' as assignments_sdk;

const scope = assignments_test.own;
const contentKey = (language: 'en', unitKey: '16-17');
const shareKey = (scope: scope, unitKey: '16-17');
const source = Chapter(id: 16, number: 16, chapterLabel: '16-17',
    title: 'Share fixture', content: '  Exact 😀 quote  \nnext paragraph');

class ShareContent extends ContentRepository {
  Chapter chapter;
  ShareContent([this.chapter = source]) : super.bundledOnly();
  @override
  Future<Chapter?> getAssignmentChapter(int chapterNumber, {String language = 'en'}) async => chapter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final unit = FirebaseChapterUnit.fromChapter(16);
  FirebaseReaderHighlightSelection capture(Chapter chapter, int start, int end) =>
      FirebaseReaderHighlightSelection.capture(chapter, 'en', unit, start, end);

  test('exact UTF16 selection preserves spaces/newlines and supplementary character', () {
    final selected = capture(source, 0, 18);
    expect(selected.quote, source.content.substring(0, 18));
    expect(selected.quote, contains('😀'));
    expect(selected.requestedLanguage, 'en');
    expect(selected.languages, ['en']);
    expect(selected.chapters, [16, 17]);
    expect(() => selected.chapters.add(18), throwsUnsupportedError);
    expect(() => selected.draft(null, '0', 'Comment'), throwsFormatException);
    expect(() => selected.draft(18, '0', 'Comment'), throwsFormatException);
    expect(selected.draft(17, '2147483647', ' Comment ').text, ' Comment ');
    expect(selected.draft(17, '0', 'Comment').paragraphIndex, 0);
  });
  test('invalid, whitespace, overlength and split-surrogate offsets never truncate', () {
    for (final range in [(-1, 1), (0, 0), (4, 2), (0, 1000), (0, 2), (8, 9), (9, 10)]) {
      expect(() => capture(source, range.$1, range.$2), throwsFormatException, reason: '$range');
    }
    final long = Chapter(id: 16, number: 16, title: 'Long', content: '😀' * 250 + 'x');
    expect(capture(long, 0, 500).quote.length, 500);
    expect(() => capture(long, 0, 501), throwsFormatException);
    final selected = capture(source, 2, 7);
    for (final paragraph in ['', '-1', '+1', '1.0', '1e0', ' 1', '2147483648', '9' * 100]) {
      expect(() => selected.draft(16, paragraph, 'Comment'), throwsFormatException);
    }
    for (final comment in [' ', 'x' * 2001]) {
      expect(() => selected.draft(16, '0', comment), throwsFormatException);
    }
    expect(selected.draft(16, '0', 'x' * 2000).text.length, 2000);
  });
  test('real assembled Marathi selection exposes chapter source but never paragraph precision', () async {
    final repo = ContentRepository.bundledOnly();
    final chapter = (await repo.getAssignmentChapter(16, language: 'mr'))!;
    expect(chapter.sourceSegments.length, 2);
    final segment = chapter.sourceSegments.last;
    final selected = capture(chapter, segment.start, segment.start + 8);
    expect(selected.chapters, [17]);
    expect(selected.languages, ['mr']);
    expect(() => selected.draft(16, '0', 'Comment'), throwsFormatException);
    expect(() => selected.draft(17, '', 'Comment'), throwsFormatException);
    expect(selected.quote, chapter.content.substring(segment.start, segment.start + 8));
  });
  test('real merged English originals stay explicit and chapter50 uses actual Marathi', () async {
    final repo = ContentRepository.bundledOnly();
    final merged = (await repo.getAssignmentChapter(16))!;
    expect(capture(merged, 0, 10).chapters, [16, 17]);
    final fallback = (await repo.getAssignmentChapter(50))!;
    final selected = FirebaseReaderHighlightSelection.capture(fallback, 'en',
        FirebaseChapterUnit.fromChapter(50), 0, 10);
    expect(selected.languages, ['mr']);
    expect(selected.chapters, [50]);
    expect(selected.requestedLanguage, 'en');
    expect(selected.quote, fallback.content.substring(0, 10));
  });
  test('per-segment mixed fallback language is not the assembled first language', () {
    const mixed = Chapter(id: 16, number: 16, title: 'Mixed', content: 'English\n\nमराठी',
        sourceSegments: [ChapterSourceSegment(0, 7, 16, 16, 'en'),
          ChapterSourceSegment(9, 14, 17, 17, 'mr')]);
    final selected = capture(mixed, 9, 14);
    expect(selected.chapters, [17]); expect(selected.languages, ['mr']);
    // A separator without source provenance is not an original anchor.
    expect(() => capture(mixed, 0, 14), throwsFormatException);
    expect(() => capture(mixed, 7, 9), throwsFormatException);
  });
  test('reader selection draft uses actual SDK self membership and strict six-field write only', () async {
    final db = highlights_sdk.HighlightsDb();
    highlights_sdk.seed(db);
    final auth = assignments_sdk.SdkAuth();
    final gateway = FirestoreHighlightsGateway(auth, db);
    const chapter = Chapter(id: 16, number: 16, title: 'Fallback',
        content: 'मराठी quote', language: 'mr',
        sourceSegments: [ChapterSourceSegment(0, 11, 17, 17, 'mr')]);
    final selected = capture(chapter, 0, 5);
    await gateway.send('g', selected.draft(17, '2147483647', ' Comment '));
    final body = db.writes.single.data;
    expect(body.keys.toSet(), {'senderUid', 'chapterNumber', 'paragraphIndex', 'quote', 'text', 'createdAt'});
    expect(body['senderUid'], 'a'); expect(body['quote'], chapter.content.substring(0, 5));
    expect(body['chapterNumber'], 17); expect(body['paragraphIndex'], 2147483647);
    db.documents.remove('groups/g/members/a');
    await expectLater(gateway.send('g', selected.draft(17, '0', 'Comment')), throwsFormatException);
    expect(db.allocations, 1); expect(db.writes.length, 1);
  });

  Future<(auth_test.FakeGateway, assignments_test.FakeAssignments,
      highlights_test.FakeHighlights, ProviderContainer)> mount(WidgetTester tester,
      {String member = 'a', ShareContent? content,
      assignments_test.FakeAssignments? assignments,
      highlights_test.FakeHighlights? highlights}) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = auth_test.FakeGateway()..profile = 'Private';
    final assignmentGateway = assignments ?? assignments_test.FakeAssignments();
    final highlightGateway = highlights ?? highlights_test.FakeHighlights();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseAssignmentsGatewayProvider.overrideWithValue(assignmentGateway),
      firebaseHighlightsGatewayProvider.overrideWithValue(highlightGateway),
      bundledContentRepositoryProvider.overrideWith((ref) => content ?? ShareContent()),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API accessed')),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth accessed')),
      contentRepositoryProvider.overrideWith((ref) => throw StateError('Legacy repository accessed')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp(home: FirebaseAssignmentReaderScreen(groupId: 'g',
            memberUid: member, week: '1', unitKey: '16-17'))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose(); await auth.changes.close();
    });
    return (auth, assignmentGateway, highlightGateway, container);
  }
  Future<void> select(WidgetTester tester, {int start = 0, int end = 18}) async {
    tester.widget<SelectableText>(find.byKey(const Key('reader-content')))
        .onSelectionChanged!(TextSelection(baseOffset: start, extentOffset: end),
            SelectionChangedCause.drag);
    await tester.pump();
  }
  Future<void> open(WidgetTester tester) async {
    await select(tester);
    await tester.ensureVisible(find.byKey(const Key('reader-share-selected')));
    await tester.tap(find.byKey(const Key('reader-share-selected')));
    await tester.pumpAndSettle();
  }
  Future<void> fill(WidgetTester tester, {String paragraph = '0', String comment = ' My reflection '}) async {
    await tester.tap(find.byKey(const Key('reader-share-chapter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original chapter 17').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reader-share-paragraph')), paragraph);
    await tester.enterText(find.byKey(const Key('reader-share-comment')), comment);
  }
  Future<void> confirm(WidgetTester tester, {bool settle = true}) async {
    await tester.tap(find.byKey(const Key('reader-share-confirm')));
    if (settle) { await tester.pumpAndSettle(); } else { await tester.pump(); }
  }

  testWidgets('only a valid selection enables explicit share; open/select/scroll/cancel never write', (tester) async {
    final (_, assignments, highlights, _) = await mount(tester);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reader-share-selected'))).onPressed, isNull);
    await select(tester, end: 2);
    expect(find.byKey(const Key('reader-selection-error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reader-share-selected'))).onPressed, isNull);
    await open(tester);
    expect(assignments.reads.length, 2);
    expect(find.text('Review group highlight'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('reader-share-quote'))).data, source.content.substring(0, 18));
    expect(tester.widget<DropdownButtonFormField<int>>(find.byKey(const Key('reader-share-chapter'))).initialValue, isNull);
    expect(tester.widget<TextField>(find.byKey(const Key('reader-share-paragraph'))).controller!.text, isEmpty);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(highlights.sends, isEmpty); expect(highlights.reads, isEmpty);
    expect(assignments.updates, isEmpty);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reader-share-selected'))).onPressed, isNull);
  });
  testWidgets('review requires explicit chapter/paragraph/nonblank bounded comment; quote cannot be edited', (tester) async {
    final (_, assignments, highlights, _) = await mount(tester);
    await open(tester); await confirm(tester);
    expect(find.textContaining('Choose an original chapter'), findsOneWidget);
    await fill(tester, paragraph: ''); await confirm(tester);
    expect(find.textContaining('Enter a paragraph index'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reader-share-paragraph')), '2147483648');
    await confirm(tester);
    expect(find.textContaining('Paragraph index must be'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reader-share-paragraph')), '0');
    await tester.enterText(find.byKey(const Key('reader-share-comment')), ' ');
    await confirm(tester);
    expect(find.textContaining('Comment must be nonblank'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reader-share-comment')), 'x' * 2001);
    await confirm(tester);
    expect(highlights.sends, isEmpty); expect(assignments.reads.length, 2);
    expect(assignments.updates, isEmpty);
    expect(find.byKey(const Key('reader-share-quote')), findsOneWidget);
  });
  testWidgets('viewer of another member can share exact quote under own group membership, never progress', (tester) async {
    final (_, assignments, highlights, _) = await mount(tester, member: 'public-uid-b');
    await open(tester); await fill(tester, paragraph: '2147483647'); await confirm(tester);
    final sent = highlights.sends.single;
    expect(sent.groupId, 'g'); expect(sent.draft.chapterNumber, 17);
    expect(sent.draft.paragraphIndex, 2147483647);
    expect(sent.draft.quote, source.content.substring(0, 18));
    expect(sent.draft.text, ' My reflection ');
    expect(assignments.reads.length, 3);
    expect(assignments.reads.every((s) => s.uid == 'a' && s.memberUid == 'public-uid-b'), isTrue);
    expect(assignments.updates, isEmpty);
    expect(find.text('Highlight write acknowledged.'), findsOneWidget);
    expect(find.byKey(const Key('reader-share-confirm')), findsNothing);
  });
  testWidgets('selected source language displayed instead of requested or assembled language', (tester) async {
    const fallback = Chapter(id: 16, number: 16, title: 'Fallback',
        content: '  Exact 😀 quote  \nnext paragraph', language: 'mr',
        sourceSegments: [ChapterSourceSegment(0, 32, 16, 17, 'mr')]);
    await mount(tester, content: ShareContent(fallback));
    await open(tester);
    expect(find.text('Requested language: en. Selected source language: mr.'), findsOneWidget);
    expect(find.textContaining('Unverified anchor:'), findsOneWidget);
  });
  for (final stage in ['before review', 'before write']) {
    testWidgets('removed assignment $stage prevents any send', (tester) async {
      final (_, assignments, highlights, _) = await mount(tester);
      if (stage == 'before write') { await open(tester); await fill(tester); }
      assignments.saved[scope] = {};
      if (stage == 'before review') { await open(tester); } else { await confirm(tester); }
      expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
      expect(find.textContaining('Fresh assignment access denied'), findsOneWidget);
      expect(find.byKey(const Key('reader-content')), findsNothing);
    });
    testWidgets('revoked permission $stage prevents any send', (tester) async {
      final (_, assignments, highlights, _) = await mount(tester);
      if (stage == 'before write') { await open(tester); await fill(tester); }
      assignments.error = StateError('revoked');
      if (stage == 'before review') { await open(tester); } else { await confirm(tester); }
      expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
      expect(find.textContaining('Fresh assignment access denied'), findsOneWidget);
    });
  }
  testWidgets('ACK survives failed head reload and assignment invalidation without resend', (tester) async {
    final highlights = highlights_test.FakeHighlights()..sendGate = Completer<void>()
        ..readError = StateError('offline');
    final (_, assignments, _, container) = await mount(tester, highlights: highlights);
    // An already-live manual controller must be invalidated, not used as our draft state.
    final sub = container.listen(firebaseHighlightsProvider(highlights_test.binding), (_, __) {});
    final original = container.read(firebaseHighlightsProvider(highlights_test.binding).notifier);
    await open(tester); await fill(tester); await confirm(tester, settle: false);
    assignments.saved[scope] = {};
    await container.read(firebaseAssignmentsProvider(scope).notifier).refresh();
    await tester.pump();
    highlights.sendGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Highlight write acknowledged.'), findsOneWidget);
    expect(find.textContaining('head refresh unavailable'), findsOneWidget);
    expect(find.byKey(const Key('reader-share-confirm')), findsNothing);
    expect(identical(original, container.read(firebaseHighlightsProvider(highlights_test.binding).notifier)), isFalse);
    expect(highlights.sends.length, 1); expect(assignments.updates, isEmpty);
    sub.close();
  });
  testWidgets('uncertain delivery blocks reopen and failed verification; explicit server head unlocks with warning', (tester) async {
    final highlights = highlights_test.FakeHighlights()..sendError = const FirebaseHighlightDeliveryUncertain();
    final (_, _, _, container) = await mount(tester, highlights: highlights);
    await open(tester); await fill(tester); await confirm(tester);
    expect(container.read(firebaseReaderShareProvider(shareKey)).verifyBeforeRetry, isTrue);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reader-share-confirm'))).onPressed, isNull);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    // Dispose and reopen the reader while retaining the application container.
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: const MaterialApp(home: SizedBox())));
    await tester.pumpAndSettle();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: const MaterialApp(home: FirebaseAssignmentReaderScreen(
            groupId: 'g', memberUid: 'a', week: '1', unitKey: '16-17'))));
    await tester.pumpAndSettle(); await open(tester);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reader-share-confirm'))).onPressed, isNull);
    highlights.readError = StateError('offline');
    await tester.tap(find.text('Verify newest server highlights')); await tester.pumpAndSettle();
    expect(container.read(firebaseReaderShareProvider(shareKey)).verifyBeforeRetry, isTrue);
    highlights.readError = null;
    await tester.tap(find.text('Verify newest server highlights')); await tester.pumpAndSettle();
    expect(find.textContaining('NOT proof of non-delivery'), findsOneWidget);
    expect(find.textContaining('Confirmed reflection'), findsOneWidget);
    expect(container.read(firebaseReaderShareProvider(shareKey)).verifyBeforeRetry, isFalse);
    expect(highlights.sends.length, 1);
    expect(highlights.reads, [null, null]);
  });
  for (final change in ['selection', 'language', 'content retry', 'reload', 'account', 'SDK drift']) {
    testWidgets('$change invalidates an open review without leaking or sending stale quote', (tester) async {
      final (auth, assignments, highlights, container) = await mount(tester);
      await open(tester); await fill(tester);
      switch (change) {
        case 'selection': await select(tester, start: 2, end: 7);
        case 'language': await container.read(languageProvider.notifier).setReaderLanguage(AppLanguage.marathi);
        case 'content retry': container.invalidate(firebaseAssignmentContentProvider(contentKey));
        case 'reload':
          // Invoke the explicit underlying reload action while the overlay exists.
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reload assignment access')).onPressed!();
        case 'account': auth.emit(const FirebaseIdentity('b', null));
        case 'SDK drift':
          auth.currentUser = const FirebaseIdentity('b', null);
          // A stale UI must still check the SDK synchronously at confirmation.
          await confirm(tester);
      }
      await tester.pumpAndSettle();
      if (change != 'SDK drift') expect(find.text('Highlight review expired.'), findsOneWidget);
      expect(find.byKey(const Key('reader-share-quote')), findsNothing);
      expect(find.text(' My reflection '), findsNothing);
      expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final change in ['dispose', 'account', 'language', 'content']) {
    testWidgets('delayed prewrite fresh access followed by $change cannot send', (tester) async {
      final (auth, assignments, highlights, container) = await mount(tester);
      await open(tester); await fill(tester);
      assignments.gates[scope] = Completer<FirebaseAssignmentsResult>();
      await confirm(tester, settle: false);
      switch (change) {
        case 'dispose': await tester.pumpWidget(const SizedBox.shrink());
        case 'account': auth.emit(const FirebaseIdentity('b', null));
        case 'language': await container.read(languageProvider.notifier).setReaderLanguage(AppLanguage.marathi);
        case 'content': container.invalidate(firebaseAssignmentContentProvider(contentKey));
      }
      await tester.pump();
      assignments.gates[scope]!.complete(assignments.result(scope));
      await tester.pumpAndSettle();
      expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('route disposal during initial fresh access cannot open a delayed review', (tester) async {
    final (_, assignments, highlights, _) = await mount(tester);
    assignments.gates[scope] = Completer<FirebaseAssignmentsResult>();
    await select(tester);
    await tester.tap(find.byKey(const Key('reader-share-selected'))); await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pump();
    assignments.gates[scope]!.complete(assignments.result(scope));
    await tester.pumpAndSettle();
    expect(find.text('Review group highlight'), findsNothing);
    expect(highlights.sends, isEmpty); expect(tester.takeException(), isNull);
  });
  testWidgets('new reader member/week scope expires surviving old-route overlay', (tester) async {
    final (_, assignments, highlights, container) = await mount(tester);
    await open(tester); await fill(tester);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: const MaterialApp(home: FirebaseAssignmentReaderScreen(
            groupId: 'g', memberUid: 'public-uid-b', week: '2', unitKey: '16-17'))));
    await tester.pumpAndSettle();
    expect(find.text('Highlight review expired.'), findsOneWidget);
    expect(find.byKey(const Key('reader-share-quote')), findsNothing);
    expect(assignments.reads.last.memberUid, 'public-uid-b');
    expect(assignments.reads.last.week, 2);
    expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('UID roundtrip while initial fresh access waits cannot resurrect an old selection', (tester) async {
    final (auth, assignments, highlights, _) = await mount(tester);
    assignments.gates[scope] = Completer<FirebaseAssignmentsResult>();
    await select(tester);
    await tester.tap(find.byKey(const Key('reader-share-selected'))); await tester.pump();
    auth.emit(const FirebaseIdentity('b', null)); await tester.pump();
    auth.emit(const FirebaseIdentity('a', null)); await tester.pump();
    assignments.gates[scope]!.complete(assignments.result(scope));
    await tester.pumpAndSettle();
    expect(find.text('Review group highlight'), findsNothing);
    expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancel while prewrite access is pending prevents write after await', (tester) async {
    final (_, assignments, highlights, _) = await mount(tester);
    await open(tester); await fill(tester);
    assignments.gates[scope] = Completer<FirebaseAssignmentsResult>();
    await confirm(tester, settle: false);
    await tester.tap(find.text('Cancel')); await tester.pump(const Duration(milliseconds: 300));
    assignments.gates[scope]!.complete(assignments.result(scope));
    await tester.pumpAndSettle();
    expect(highlights.sends, isEmpty); expect(assignments.updates, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('uncertainty arriving after dialog close still blocks route reopen', (tester) async {
    final highlights = highlights_test.FakeHighlights()..sendGate = Completer<void>()
        ..sendError = const FirebaseHighlightDeliveryUncertain();
    final (_, _, _, container) = await mount(tester, highlights: highlights);
    await open(tester); await fill(tester); await confirm(tester, settle: false);
    await tester.tap(find.text('Cancel')); await tester.pump(const Duration(milliseconds: 300));
    highlights.sendGate!.complete(); await tester.pumpAndSettle();
    expect(container.read(firebaseReaderShareProvider(shareKey)).verifyBeforeRetry, isTrue);
    await open(tester);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reader-share-confirm'))).onPressed, isNull);
    expect(highlights.sends.length, 1); expect(highlights.reads, isEmpty);
  });
  test('reader guard independently scopes bindings and rejects poisoned verification pages', () async {
    final fake = highlights_test.FakeHighlights()..sendError = const FirebaseHighlightDeliveryUncertain();
    final controller = FirebaseReaderShareController(fake, highlights_test.binding, () {});
    final draft = FirebaseHighlightDraft(17, 0, 'Quote', 'Comment');
    expect(await controller.send(draft, current: () => true, freshAccess: () async {}), FirebaseHighlightDelivery.uncertain);
    fake.response = highlights_test.fixture(uid: 'b');
    expect(await controller.verifyHead(() => true), isNull);
    expect(controller.state.verifyBeforeRetry, isTrue);
    final other = FirebaseReaderShareController(fake, (uid: 'b', groupId: 'g'), () {});
    expect(other.state.verifyBeforeRetry, isFalse);
    expect(await controller.send(draft, current: () => true, freshAccess: () async {}), FirebaseHighlightDelivery.notAttempted);
    expect(fake.sends.length, 1);
    controller.dispose(); other.dispose();
  });
  test('guard distinguishes definite rejection, unknown write outcome and ACK when route disappears', () async {
    final fake = highlights_test.FakeHighlights()..sendError = const FormatException('Membership rejected.');
    var current = true, invalidations = 0;
    final controller = FirebaseReaderShareController(fake, highlights_test.binding, () => invalidations++);
    final draft = FirebaseHighlightDraft(17, 0, 'Quote', 'Comment');
    expect(await controller.send(draft, current: () => current, freshAccess: () async {}), FirebaseHighlightDelivery.notAttempted);
    expect(controller.state.verifyBeforeRetry, isFalse);
    fake.sendError = StateError('unknown commit');
    expect(await controller.send(draft, current: () => current, freshAccess: () async {}), FirebaseHighlightDelivery.uncertain);
    expect(controller.state.verifyBeforeRetry, isTrue);
    await controller.verifyHead(() => true);
    fake.sendError = null; fake.sendGate = Completer<void>();
    final sending = controller.send(draft, current: () => current, freshAccess: () async {});
    await Future<void>.delayed(Duration.zero);
    current = false; fake.sendGate!.complete();
    expect(await sending, FirebaseHighlightDelivery.acknowledged);
    expect(controller.state.delivery, FirebaseHighlightDelivery.acknowledged);
    expect(controller.state.busy, isFalse);
    expect(invalidations, 0); expect(fake.reads.length, 1);
    controller.dispose();
  });
  test('verification completion from stale account never unlocks guard or returns old head', () async {
    final fake = highlights_test.FakeHighlights()..sendError = const FirebaseHighlightDeliveryUncertain();
    final controller = FirebaseReaderShareController(fake, highlights_test.binding, () {});
    await controller.send(FirebaseHighlightDraft(17, 0, 'Quote', 'Comment'),
        current: () => true, freshAccess: () async {});
    var current = true;
    fake.readGate = Completer<FirebaseHighlightsPage>();
    final verification = controller.verifyHead(() => current);
    current = false; fake.readGate!.complete(highlights_test.fixture());
    expect(await verification, isNull);
    expect(controller.state.verifyBeforeRetry, isTrue);
    expect(controller.state.busy, isFalse);
    expect(fake.sends.length, 1); controller.dispose();
  });
}