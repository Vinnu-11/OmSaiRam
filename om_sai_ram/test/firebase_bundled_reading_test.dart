import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/providers/language_provider.dart';
import 'package:om_sai_ram/core/providers/reader_settings_provider.dart';
import 'package:om_sai_ram/core/providers/reading_progress_provider.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/audio/presentation/audio_hub_screen.dart';
import 'package:om_sai_ram/features/audio/presentation/aarti_screen.dart';
import 'package:om_sai_ram/features/audio/presentation/satcharitra_audio_screen.dart';
import 'package:om_sai_ram/features/audio/data/audio_data.dart';
import 'package:om_sai_ram/features/audio/providers/chapter_audio_provider.dart';
import 'package:om_sai_ram/features/faq/presentation/faq_screen.dart';
import 'package:om_sai_ram/features/info/presentation/daily_programme_screen.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_home/presentation/firebase_home_screen.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_reading/data/bundled_reading.dart';
import 'package:om_sai_ram/features/firebase_reading/providers/bundled_reading_provider.dart';
import 'package:om_sai_ram/features/firebase_reading/presentation/bundled_reading_screen.dart';
import 'package:om_sai_ram/features/reader/data/chapter_model.dart';
import 'package:om_sai_ram/features/reader/data/content_repository.dart';
import 'package:om_sai_ram/shared/widgets/baba_image.dart';
import 'firebase_auth_mode_test.dart' as auth_test;

Chapter entry(
        {int number = 16,
        String? label = '16-17',
        String language = 'en',
        String content = 'Bundled selectable text',
        int id = 900,
        String title = 'Local title'}) =>
    Chapter(
        id: id,
        number: number,
        chapterLabel: label,
        language: language,
        content: content,
        title: title,
        heading: 'Original heading');

class FailingBookmarkProgress extends ReadingProgressNotifier {
  @override
  Future<void> toggleBookmark(int chapterNumber) async {
    throw StateError('Storage unavailable');
  }
}

class FailingResumeProgress extends ReadingProgressNotifier {
  @override
  Future<void> saveResumePosition(int chapterNumber, double position) async {
    throw StateError('Storage unavailable');
  }
}

class ControlledAudio extends ChapterAudioNotifier {
  final played = <AudioTrack>[];
  bool fail = false;
  Duration? sought;
  void setAudio(ChapterAudioState value) => state = value;
  @override
  Future<void> toggleAudio(AudioTrack track) async {
    played.add(track);
    state = ChapterAudioState(
        track: track,
        status: fail
            ? ChapterAudioStatus.error
            : state.status == ChapterAudioStatus.playing
                ? ChapterAudioStatus.paused
                : ChapterAudioStatus.playing,
        total: const Duration(minutes: 5));
  }

  @override
  Future<void> stop() async => state = const ChapterAudioState();
  @override
  Future<void> seek(Duration position) async {
    sought = position;
    state = state.copyWith(position: position);
  }
}

class LocalContent extends ContentRepository {
  LocalContent() : super.bundledOnly();
  bool missing = false;
  int calls = 0, assignmentCalls = 0;
  final cleared = <String?>[];
  final gates = <String, Completer<Chapter?>>{};
  @override
  Future<List<Chapter>> getChapters({String language = 'en'}) async {
    calls++;
    return missing ? [] : [entry(language: language)];
  }

  @override
  Future<Chapter?> getChapter(int chapterNumber,
      {String language = 'en'}) async {
    calls++;
    if (gates.containsKey(language)) return gates[language]!.future;
    return missing
        ? null
        : entry(number: chapterNumber, label: null, language: language);
  }

  @override
  Future<Chapter?> getAssignmentChapter(int chapterNumber,
      {String language = 'en'}) async {
    assignmentCalls++;
    throw StateError('Assignment assembly forbidden');
  }

  @override
  void clearCache([String? language]) {
    cleared.add(language);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
      () => SharedPreferences.setMockInitialValues({'reader_language': 'en'}));

  for (final bad in [
    '',
    '0',
    '00',
    '01',
    '053',
    '54',
    '900',
    '-1',
    '+1',
    '1.0',
    '1e0',
    ' 1',
    '1 ',
    '16-17',
    '51-53',
    '1/2',
    '１',
    '1\n',
    '1 OR 1=1'
  ]) {
    test('reject original route "$bad" before repository construction',
        () async {
      expect(() => parseOriginalChapter(bad), throwsFormatException);
      final container = ProviderContainer(overrides: [
        bundledContentRepositoryProvider
            .overrideWith((ref) => throw StateError('Constructed')),
      ]);
      addTearDown(container.dispose);
      await expectLater(
          container.read(
              bundledReadingProvider((language: 'en', chapterNumber: bad))
                  .future),
          throwsFormatException);
    });
  }
  test('all original numbers canonical, including 17 and 52', () {
    for (var n = 1; n <= 53; n++) {
      expect(parseOriginalChapter('$n'), n);
    }
  });
  test('entry schema rejects invalid ranges, IDs, content and unknown source',
      () {
    for (final chapter in [
      entry(number: 0),
      entry(number: 54),
      entry(label: '16-54'),
      entry(label: '15-17'),
      entry(label: '16-15'),
      entry(label: '016-17'),
      entry(label: '16-17-18'),
      entry(id: -1),
      entry(content: '  '),
      entry(language: 'xx')
    ]) {
      expect(() => validateBundledEntry(chapter), throwsFormatException);
    }
    expect(() => validateBundledEntry(entry(), requested: 18),
        throwsFormatException);
    expect(validateBundledEntry(entry(id: 0, title: ''), requested: 17).number,
        16);
    expect(
        validateBundledEntry(entry(id: 900)).id, 900); // ID is not navigation.
  });
  test('search finds title heading range and inner original, no expanded rows',
      () {
    final rows = [entry(), entry(number: 51, label: '51-53', title: 'Finale')];
    for (final query in ['17', '16-17', 'local']) {
      expect(searchBundledCatalogue(rows, query), [rows.first]);
    }
    expect(searchBundledCatalogue(rows, 'heading'), rows);
    expect(searchBundledCatalogue(rows, '52'), [rows.last]);
    expect(searchBundledCatalogue(rows, ''), hasLength(2));
    expect(searchBundledCatalogue(rows, 'absent'), isEmpty);
  });
  test('unknown selection language rejects before repository construction',
      () async {
    final container = ProviderContainer(overrides: [
      bundledContentRepositoryProvider
          .overrideWith((ref) => throw StateError('Constructed')),
    ]);
    addTearDown(container.dispose);
    await expectLater(container.read(bundledCatalogueProvider('xx').future),
        throwsFormatException);
    await expectLater(
        container.read(
            bundledReadingProvider((language: 'xx', chapterNumber: '1'))
                .future),
        throwsFormatException);
  });
  test(
      'real assets preserve all translation rows, ranges and separate originals without API',
      () async {
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWith((ref) => throw StateError('API')),
      contentRepositoryProvider
          .overrideWith((ref) => throw StateError('Legacy content')),
      firebaseAuthGatewayProvider
          .overrideWith((ref) => throw StateError('Auth')),
    ]);
    addTearDown(container.dispose);
    for (final language in AppLanguage.values) {
      final rows =
          await container.read(bundledCatalogueProvider(language.code).future);
      expect(rows, hasLength(language == AppLanguage.marathi ? 53 : 47));
      expect(rows.map((e) => e.number).toSet().length, rows.length);
      for (var n = 1; n <= 53; n++) {
        final chapter = await container.read(bundledReadingProvider(
            (language: language.code, chapterNumber: '$n')).future);
        expect(chapter.covers(n), isTrue, reason: '${language.code}/$n');
        expect(chapter.content.trim(), isNotEmpty);
        expect(chapter.sourceSegments, isEmpty);
        if (language != AppLanguage.marathi && n == 50)
          expect(chapter.language, 'mr');
      }
    }
    final repo = ContentRepository.bundledOnly();
    for (final n in [16, 17, 51, 52, 53]) {
      final actual = await container.read(
          bundledReadingProvider((language: 'mr', chapterNumber: '$n')).future);
      expect(actual.number, n);
      expect(actual.lastNumber, n);
      expect(
          actual.content, (await repo.getChapter(n, language: 'mr'))!.content);
    }
    final last = await container.read(
        bundledReadingProvider((language: 'en', chapterNumber: '51')).future);
    expect(last.chapterLabel, '51-53');
    expect(last.content, (await repo.getChapter(51))!.content);
  });
  test('providers surface swallowed empty catalogue and null chapter',
      () async {
    final content = LocalContent()..missing = true;
    final container = ProviderContainer(overrides: [
      bundledContentRepositoryProvider.overrideWith((ref) => content)
    ]);
    addTearDown(container.dispose);
    await expectLater(container.read(bundledCatalogueProvider('en').future),
        throwsFormatException);
    await expectLater(
        container.read(
            bundledReadingProvider((language: 'en', chapterNumber: '1'))
                .future),
        throwsFormatException);
  });
  test('providers reject wrong coverage and unexpected fallback', () async {
    final content = LocalContent();
    final container = ProviderContainer(overrides: [
      bundledContentRepositoryProvider.overrideWith((ref) => content)
    ]);
    addTearDown(container.dispose);
    final gate = content.gates['en'] = Completer<Chapter?>();
    final future = container.read(
        bundledReadingProvider((language: 'en', chapterNumber: '17')).future);
    gate.complete(entry(number: 18, label: null));
    await expectLater(future, throwsFormatException);
    content.gates['en'] = Completer<Chapter?>()
      ..complete(entry(number: 1, label: null, language: 'fr'));
    await expectLater(
        container.read(
            bundledReadingProvider((language: 'en', chapterNumber: '1'))
                .future),
        throwsFormatException);
  });

  Future<ProviderContainer> mount(WidgetTester tester,
      {String? chapter = '16',
      ContentRepository? content,
      bool routed = false,
      bool poisonAuth = true,
      auth_test.FakeGateway? auth,
      ReadingProgressNotifier? progress,
      ControlledAudio? audio}) async {
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      apiClientProvider.overrideWith((ref) => throw StateError('API')),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth')),
      contentRepositoryProvider
          .overrideWith((ref) => throw StateError('Legacy content')),
      if (progress != null)
        readingProgressProvider.overrideWith((ref) => progress),
      if (audio != null) chapterAudioProvider.overrideWith((ref) => audio),
      firebaseAssignmentsGatewayProvider
          .overrideWith((ref) => throw StateError('Assignments')),
      firebaseGroupsGatewayProvider
          .overrideWith((ref) => throw StateError('Groups')),
      if (poisonAuth)
        firebaseAuthGatewayProvider
            .overrideWith((ref) => throw StateError('Auth/profile')),
      if (auth != null) firebaseAuthGatewayProvider.overrideWithValue(auth),
      if (content != null)
        bundledContentRepositoryProvider.overrideWith((ref) => content),
    ]);
    final router = routed ? container.read(routerProvider) : null;
    if (routed) router!.go(chapter == null ? '/reader' : '/reader/$chapter');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: routed
            ? MaterialApp.router(routerConfig: router)
            : MaterialApp(home: BundledReadingScreen(chapterNumber: chapter))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    return container;
  }

  test(
      'reader audio uses source languages, originals and deduplicated merged tracks',
      () {
    expect(audioTracksForChapters([('en', 16)]), isEmpty);
    final marathi = audioTracksForChapters([('mr', 16), ('mr', 17)]);
    expect(marathi, hasLength(2));
    expect(marathi.first.fileName, contains('ch16'));
    expect(marathi.last.fileName, contains('ch17'));
    final hindi = audioTracksForChapters([('hi', 16), ('hi', 17)]);
    expect(hindi, hasLength(1));
    expect(hindi.single.fileName, contains('ch16_17'));
    expect(audioTracksForChapters([('en', 50), ('mr', 50)]), hasLength(1));
  });
  testWidgets('public audio direct links never access Auth or legacy API',
      (tester) async {
    final container = await mount(tester,
        chapter: null, content: LocalContent(), routed: true);
    final router = container.read(routerProvider);
    router.go('/audio');
    await tester.pumpAndSettle();
    expect(find.byType(AudioHubScreen), findsOneWidget);
    router.go('/audio/aarti');
    await tester.pumpAndSettle();
    expect(find.byType(AartiScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back to audio'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/audio');
    router.go('/audio/satcharitra');
    await tester.pumpAndSettle();
    expect(find.byType(SatcharitaAudioScreen), findsOneWidget);
    expect(Firebase.apps, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'public info routes use Firebase-accurate copy with no Auth or API',
      (tester) async {
    final container = await mount(tester,
        chapter: null, content: LocalContent(), routed: true);
    final router = container.read(routerProvider);
    router.go('/daily-programme');
    await tester.pumpAndSettle();
    expect(find.byType(DailyProgrammeScreen), findsOneWidget);
    expect(find.text('Daily Schedule'), findsOneWidget);
    expect(tester.widget<BabaImage>(find.byType(BabaImage)).imageUrl,
        babaAtDwarakamaiPhotoUrl);
    final listen = find.byKey(const ValueKey('daily-aarti-listen-Bhupali'));
    await tester.scrollUntilVisible(listen, 200);
    await tester.ensureVisible(listen);
    await tester.pumpAndSettle();
    await tester.tap(listen);
    await tester.pumpAndSettle();
    expect(find.byType(AartiScreen), findsOneWidget);
    expect(tester.widget<BabaImage>(find.byType(BabaImage)).imageUrl,
        babaReadingPhotoUrl);
    router.go('/faq');
    await tester.pumpAndSettle();
    expect(find.byType(FaqScreen), findsOneWidget);
    final question = find.text('How do I create or join a group?');
    await tester.ensureVisible(question);
    await tester.tap(question);
    await tester.pumpAndSettle();
    expect(find.textContaining('long invitation token'), findsOneWidget);
    expect(find.textContaining('Weekly Saptah is a label'), findsOneWidget);
    expect(Firebase.apps, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'reader audio follows actual fallback and playback never saves progress',
      (tester) async {
    final audio = ControlledAudio();
    final content = LocalContent();
    content.gates['en'] = Completer<Chapter?>()
      ..complete(entry(number: 50, label: null, language: 'mr'));
    await mount(tester, chapter: '50', content: content, audio: audio);
    await tester.pumpAndSettle();
    final play = find.byKey(
        ValueKey('reader-audio-${audioTrackForChapter('mr', 50)!.fileName}'));
    await tester.scrollUntilVisible(play, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(
        audio.played.single.fileName, audioTrackForChapter('mr', 50)!.fileName);
    expect(find.byTooltip('Pause chapter audio'), findsOneWidget);
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(audio.state.status, ChapterAudioStatus.paused);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('completed_chapters'), isNull);
    expect(prefs.getInt('resume_chapter'), isNull);
    expect(prefs.getStringList('streak_dates'), isNull);
  });
  testWidgets(
      'audio controls handle loading errors seek and stop at narrow large-text width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final audio = ControlledAudio();
    final track = audioTrackForChapter('mr', 17)!;
    audio.setAudio(ChapterAudioState(
        track: track,
        status: ChapterAudioStatus.downloading,
        downloadProgress: 0.5));
    await tester.pumpWidget(ProviderScope(
        overrides: [chapterAudioProvider.overrideWith((ref) => audio)],
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: ReaderAudioControls(tracks: [track]))))));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(
                find.byKey(ValueKey('reader-audio-${track.fileName}')))
            .onPressed,
        isNull);
    audio.setAudio(
        ChapterAudioState(track: track, status: ChapterAudioStatus.error));
    await tester.pump();
    expect(
        find.text('Audio could not be played. Retry playback when connected.'),
        findsOneWidget);
    audio.setAudio(ChapterAudioState(
        track: track,
        status: ChapterAudioStatus.paused,
        total: const Duration(minutes: 5)));
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(60000);
    await tester.pump();
    expect(audio.sought, const Duration(minutes: 1));
    await tester.tap(find.byTooltip('Stop audio'));
    await tester.pump();
    expect(audio.state.status, ChapterAudioStatus.idle);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid deep link never obtains preferences content or Auth',
      (tester) async {
    final content = LocalContent();
    await mount(tester, chapter: '053', content: content, routed: true);
    expect(
        find.textContaining('Invalid original chapter link'), findsOneWidget);
    expect(content.calls, 0);
    expect(Firebase.apps, isEmpty);
  });
  testWidgets(
      'guest public routes do not construct SDK API profiles or write progress',
      (tester) async {
    var notificationCalls = 0;
    const notificationChannel =
        MethodChannel('dexterous.com/flutter/local_notifications');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
      notificationCalls++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null));
    final content = LocalContent();
    final container = await mount(tester, content: content, routed: true);
    expect(find.byKey(const Key('bundled-reader-content')), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    container.read(routerProvider).go('/reader');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalogue-16')), findsOneWidget);
    expect(content.assignmentCalls, 0);
    expect(notificationCalls, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('completed_chapters'), isNull);
    expect(prefs.getStringList('streak_dates'), isNull);
    expect(prefs.getInt('resume_chapter'), isNull);
    expect(Firebase.apps, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('resume saves wait for loading, persist and reject invalid positions',
      () async {
    SharedPreferences.setMockInitialValues({
      'bookmarks': ['2']
    });
    final progress = ReadingProgressNotifier();
    addTearDown(progress.dispose);
    await progress.saveResumePosition(17, 0.4);
    expect(progress.state.bookmarks, {2});
    final restored = ReadingProgressNotifier();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.resumeChapter, 17);
    expect(restored.state.resumePosition, 0.4);
    for (final position in [double.nan, double.infinity]) {
      await expectLater(
          progress.saveResumePosition(17, position), throwsArgumentError);
    }
    await progress.saveResumePosition(17, -0.1);
    expect(progress.state.resumePosition, 0);
    await progress.saveResumePosition(17, 1.1);
    expect(progress.state.resumePosition, 1);
  });
  testWidgets(
      'explicit save records requested original without completion or streak',
      (tester) async {
    final content = LocalContent();
    content.gates['en'] = Completer<Chapter?>()
      ..complete(entry(content: List.filled(200, 'Reading text').join('\n')));
    final container =
        await mount(tester, chapter: '17', content: content, routed: true);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-reading-position')));
    await tester.pumpAndSettle();
    expect(container.read(readingProgressProvider).resumeChapter, 17);
    expect(
        container.read(readingProgressProvider).resumePosition, greaterThan(0));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('completed_chapters'), isNull);
    expect(prefs.getStringList('streak_dates'), isNull);
    expect(Firebase.apps, isEmpty);
    container.read(routerProvider).go('/reader');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('continue-reading')));
    await tester.tap(find.byKey(const Key('continue-reading')));
    await tester.pumpAndSettle();
    expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/reader/17');
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, greaterThan(0));
  });
  testWidgets('restores saved relative scroll after content loads',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader_language': 'en',
      'resume_chapter': 17,
      'resume_position': 0.5
    });
    final content = LocalContent();
    final gate = content.gates['en'] = Completer<Chapter?>();
    await mount(tester, chapter: '17', content: content);
    gate.complete(entry(content: List.filled(200, 'Reading text').join('\n')));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(controller.offset,
        closeTo(controller.position.maxScrollExtent * 0.5, 1));
  });
  testWidgets(
      'other chapter never inherits saved scroll and old delayed content cannot restore',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader_language': 'en',
      'resume_chapter': 17,
      'resume_position': 0.5
    });
    final content = LocalContent();
    final gate = content.gates['en'] = Completer<Chapter?>();
    final container =
        await mount(tester, chapter: '17', content: content, routed: true);
    content.gates.remove('en');
    container.read(routerProvider).go('/reader/18');
    await tester.pumpAndSettle();
    gate.complete(
        entry(content: List.filled(200, 'Old chapter text').join('\n')));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 18'), findsOneWidget);
    expect(find.textContaining('Old chapter text'), findsNothing);
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(controller.offset, 0);
    expect(
        (await SharedPreferences.getInstance()).getInt('resume_chapter'), 17);
  });
  for (final position in [double.nan, -1.0, 2.0]) {
    testWidgets(
        'stored resume position $position is finite and bounded on restore',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_language': 'en',
        'resume_chapter': 17,
        'resume_position': position
      });
      final content = LocalContent();
      content.gates['en'] = Completer<Chapter?>()
        ..complete(entry(content: List.filled(200, 'Reading text').join('\n')));
      await mount(tester, chapter: '17', content: content);
      await tester.pumpAndSettle();
      final controller =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      expect(controller.offset.isFinite, isTrue);
      expect(controller.offset,
          inInclusiveRange(0, controller.position.maxScrollExtent));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed position save does not claim success', (tester) async {
    final progress = FailingResumeProgress();
    await progress.ready;
    await mount(tester, content: LocalContent(), progress: progress);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-reading-position')));
    await tester.pump();
    expect(find.text('Reading position could not be saved. Try again.'),
        findsOneWidget);
    expect(progress.state.resumeChapter, isNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('save-reading-position')))
            .onPressed,
        isNotNull);
  });
  testWidgets('invalid saved original has no continue entry', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader_language': 'en',
      'resume_chapter': 900,
      'resume_position': double.nan
    });
    await mount(tester, chapter: null, content: LocalContent());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('continue-reading')), findsNothing);
  });
  test(
      'bookmark toggle waits for storage load and preserves existing bookmarks',
      () async {
    SharedPreferences.setMockInitialValues({
      'bookmarks': ['2']
    });
    final notifier = ReadingProgressNotifier();
    addTearDown(notifier.dispose);
    await notifier.toggleBookmark(17);
    expect(notifier.state.bookmarks, {2, 17});
    final restored = ReadingProgressNotifier();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.bookmarks, {2, 17});
  });
  testWidgets(
      'guest bookmarks requested original and removes it without group writes',
      (tester) async {
    final container = await mount(tester,
        chapter: '17', content: LocalContent(), routed: true);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('bundled-bookmark-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(readingProgressProvider).bookmarks, {17});
    expect((await SharedPreferences.getInstance()).getStringList('bookmarks'),
        ['17']);
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(readingProgressProvider).bookmarks, isEmpty);
    expect(Firebase.apps, isEmpty);
  });
  testWidgets(
      'failed bookmark save stays unsaved and exposes a retryable error',
      (tester) async {
    final progress = FailingBookmarkProgress();
    await progress.ready;
    await mount(tester, content: LocalContent(), progress: progress);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('bundled-bookmark-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(
        find.text('Bookmark could not be saved. Try again.'), findsOneWidget);
    expect(progress.state.bookmarks, isEmpty);
    expect(tester.widget<IconButton>(toggle).onPressed, isNotNull);
    expect((await SharedPreferences.getInstance()).getStringList('bookmarks'),
        isNull);
  });
  testWidgets(
      'saved originals open exact routes and ignore invalid saved numbers',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader_language': 'en',
      'bookmarks': ['17', '2', '900', '0']
    });
    final container = await mount(tester,
        chapter: null, content: LocalContent(), routed: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bookmark-900')), findsNothing);
    expect(find.byKey(const ValueKey('bookmark-0')), findsNothing);
    final saved = find.byKey(const ValueKey('bookmark-17'));
    await tester.scrollUntilVisible(saved, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(saved);
    await tester.pumpAndSettle();
    expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/reader/17');
  });
  testWidgets(
      'merged text bookmark keeps requested original instead of entry start',
      (tester) async {
    final content = LocalContent();
    content.gates['en'] = Completer<Chapter?>()..complete(entry());
    final container = await mount(tester, chapter: '17', content: content);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('bundled-bookmark-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(readingProgressProvider).bookmarks, {17});
    expect(find.text('This section covers chapters 16-17.'), findsOneWidget);
  });
  testWidgets(
      'real fallback and merged range disclosed with requested original number',
      (tester) async {
    final content = ContentRepository.bundledOnly();
    await tester.runAsync(() async {
      await content.getChapters(language: 'en');
      await content.getChapters(language: 'mr');
    });
    final container =
        await mount(tester, chapter: '50', routed: true, content: content);
    await tester.pumpAndSettle();
    expect(find.text('Chapter 50'), findsOneWidget);
    expect(find.text('Text language: Marathi'), findsOneWidget);
    expect(find.textContaining('Showing it in Marathi'), findsOneWidget);
    container.read(routerProvider).go('/reader/51');
    await tester.pumpAndSettle();
    expect(find.text('This section covers chapters 51-53.'), findsOneWidget);
    expect(find.textContaining('same text again'), findsOneWidget);
  });
  testWidgets(
      'original next/previous never normalize merged ranges, endpoints disabled',
      (tester) async {
    final container = await mount(tester,
        chapter: '16', content: LocalContent(), routed: true);
    final router = container.read(routerProvider);
    await tester.ensureVisible(find.text('Next: chapter 17'));
    await tester.tap(find.text('Next: chapter 17'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reader/17');
    await tester.ensureVisible(find.text('Previous: chapter 16'));
    await tester.tap(find.text('Previous: chapter 16'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reader/16');
    for (final n in [1, 53]) {
      router.go('/reader/$n');
      await tester.pumpAndSettle();
      final label = n == 1 ? 'Start of book' : 'End of book';
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, label))
              .onPressed,
          isNull);
    }
  });
  testWidgets(
      'catalogue search keeps one merged row and missing chapter jump opens 50',
      (tester) async {
    final content = ContentRepository.bundledOnly();
    await tester.runAsync(() async {
      await content.getChapters(language: 'en');
      await content.getChapters(language: 'mr');
    });
    final container =
        await mount(tester, chapter: null, routed: true, content: content);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalogue-search')), '17');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalogue-16')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalogue-17')), findsNothing);
    await tester.enterText(
        find.byKey(const Key('original-chapter-jump')), '050');
    await tester.ensureVisible(find.text('Open chapter'));
    await tester.tap(find.text('Open chapter'));
    await tester.pump();
    expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/reader');
    await tester.enterText(
        find.byKey(const Key('original-chapter-jump')), '50');
    await tester.tap(find.text('Open chapter'));
    await tester.pumpAndSettle();
    expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/reader/50');
  });
  testWidgets(
      'delayed language changes never display old result; prefs are installation-wide',
      (tester) async {
    final content = LocalContent();
    final en = content.gates['en'] = Completer<Chapter?>();
    final mr = content.gates['mr'] = Completer<Chapter?>();
    final container = await mount(tester, content: content);
    await container
        .read(languageProvider.notifier)
        .setReaderLanguage(AppLanguage.marathi);
    await tester.pump();
    en.complete(entry(content: 'Stale English'));
    await tester.pump();
    expect(find.text('Stale English'), findsNothing);
    mr.complete(entry(language: 'mr', content: 'Current Marathi'));
    await tester.pumpAndSettle();
    expect(find.text('Current Marathi'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('reader_language'),
        'mr');
  });
  testWidgets(
      'catalogue language control preserves visible search and replaces original rows',
      (tester) async {
    final content = ContentRepository.bundledOnly();
    await tester.runAsync(() async {
      await content.getChapters(language: 'en');
      await content.getChapters(language: 'mr');
    });
    await mount(tester, chapter: null, content: content);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalogue-search')), '17');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalogue-16')), findsOneWidget);
    await tester
        .ensureVisible(find.byType(DropdownButtonFormField<AppLanguage>));
    await tester.tap(find.byType(DropdownButtonFormField<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('मराठी').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalogue-16')), findsNothing);
    expect(find.byKey(const ValueKey('catalogue-17')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('catalogue-search')))
            .controller!
            .text,
        '17');
  });
  testWidgets(
      'nonfinite stored font defaults safely and actual fallback determines direction',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'reader_language': 'sd', 'reader_font_size': double.nan});
    final content = LocalContent();
    content.gates['sd'] = Completer<Chapter?>()
      ..complete(entry(number: 16, label: null, language: 'mr'));
    await mount(tester, content: content);
    await tester.pumpAndSettle();
    final finder = find.byKey(const Key('bundled-reader-content'));
    expect(
        tester.widget<SelectableText>(finder).style!.fontSize, defaultFontSize);
    expect(Directionality.of(tester.element(finder)), TextDirection.ltr);
    expect(find.text('Text language: Marathi'), findsOneWidget);
  });
  for (final catalogue in [false, true]) {
    testWidgets(
        'local ${catalogue ? 'catalogue' : 'reader'} error explicit retry clears fallback cache',
        (tester) async {
      final content = LocalContent()..missing = true;
      await mount(tester, content: content, chapter: catalogue ? null : '16');
      await tester.pumpAndSettle();
      content.missing = false;
      await tester.scrollUntilVisible(find.text('Try again'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(content.cleared, ['en', 'mr']);
      expect(find.text('Try again'), findsNothing);
      expect(content.calls, 2);
    });
  }
  for (final lang in [AppLanguage.urdu, AppLanguage.sindhi]) {
    testWidgets(
        '${lang.code} actual source is RTL, clamped font and large-text narrow controls wrap',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      SharedPreferences.setMockInitialValues(
          {'reader_language': lang.code, 'reader_font_size': 200.0});
      final container = await mount(tester, content: LocalContent());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('bundled-reader-content')), 300,
          scrollable: find.byType(Scrollable).first);
      final text = tester.widget<SelectableText>(
          find.byKey(const Key('bundled-reader-content')));
      expect(text.style!.fontSize, maxFontSize);
      expect(
          Directionality.of(
              tester.element(find.byKey(const Key('bundled-reader-content')))),
          TextDirection.rtl);
      await container.read(readerSettingsProvider.notifier).setFontSize(18);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SelectableText>(
                  find.byKey(const Key('bundled-reader-content')))
              .style!
              .fontSize,
          18);
      expect(
          (await SharedPreferences.getInstance()).getDouble('reader_font_size'),
          18);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'auth transitions do not interrupt public reading; group guard unchanged',
      (tester) async {
    final auth = auth_test.FakeGateway()..profile = 'Member';
    addTearDown(auth.changes.close);
    final container = await mount(tester,
        routed: true, content: LocalContent(), poisonAuth: false, auth: auth);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('member', null));
    await tester.pumpAndSettle();
    final router = container.read(routerProvider);
    expect(router.routeInformationProvider.value.uri.path, '/reader/16');
    auth.emit(null);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reader/16');
    router.go('/groups/private/assignments');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(FirebaseHomeScreen), findsOneWidget);
    expect(auth.reads, 1); // Only the explicit session restoration above.
    expect(auth.writes, 0);
  });
}
