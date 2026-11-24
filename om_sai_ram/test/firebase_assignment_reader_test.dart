import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/providers/language_provider.dart';
import 'package:om_sai_ram/core/providers/reader_settings_provider.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_resume.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignment_resume_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_assignments/presentation/firebase_assignment_reader_screen.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignment_reader_provider.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/reader/data/chapter_model.dart';
import 'package:om_sai_ram/features/reader/data/content_repository.dart';
import 'package:om_sai_ram/features/audio/data/audio_data.dart';
import 'package:om_sai_ram/features/audio/providers/chapter_audio_provider.dart';
import 'package:om_sai_ram/features/audio/presentation/satcharitra_audio_screen.dart';
import 'firebase_assignments_test.dart' as assignments_test;
import 'firebase_auth_mode_test.dart' as auth_test;
import 'firebase_bundled_reading_test.dart' as media_test;

const own = assignments_test.own;
const selection = (language: 'en', unitKey: '16-17');
const fixture = Chapter(
    id: 16,
    number: 16,
    chapterLabel: '16-17',
    title: 'Local fixture',
    content: 'Selectable local text');

class ControlledContent extends ContentRepository {
  int calls = 0;
  bool missing = false;
  final gates = <String, Completer<Chapter?>>{};
  ControlledContent() : super.bundledOnly();
  @override
  Future<Chapter?> getAssignmentChapter(int chapterNumber,
      {String language = 'en'}) async {
    calls++;
    if (gates[language] != null) return gates[language]!.future;
    return missing ? null : fixture;
  }
}

class EmptyContent extends ContentRepository {
  EmptyContent() : super.bundledOnly();
  @override
  Future<List<Chapter>> getChapters({String language = 'en'}) async => [];
}

class ControlledResumePreferences extends Fake implements SharedPreferences {
  final data = <String, String>{};
  int writes = 0;
  bool acknowledge = true;
  Completer<void>? writeGate;
  @override
  String? getString(String key) => data[key];
  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (acknowledge) data[key] = value;
    return acknowledge;
  }
  @override
  Future<bool> remove(String key) async {
    writes++;
    if (writeGate != null) await writeGate!.future;
    if (acknowledge) data.remove(key);
    return acknowledge;
  }
}

class UnobservedCompletion extends assignments_test.FakeAssignments {
  @override
  Future<void> updateStatus(FirebaseAssignmentsScope scope,
      FirebaseChapterUnit unit, FirebaseReadingStatus status) async {
    updates.add(status); // Simulate a concurrent reset before server reload.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  FirebaseAssignmentResume saved({FirebaseAssignmentsScope scope = own, String unit = '16-17',
      String language = 'en', double position = .5}) => FirebaseAssignmentResume(
    scope: scope, unitKey: unit, language: language, position: position);
  test('resume roundtrip preserves full identity, exact route and bounded position', () {
    final value = FirebaseAssignmentResume.decode(saved().encode(), 'a');
    expect(value.matches(own, '16-17', 'en'), isTrue);
    expect(value.matches(assignments_test.other, '16-17', 'en'), isFalse);
    expect(value.matches(own, '16-17', 'mr'), isFalse);
    expect(value.location, '/groups/g/assignments/read/a/1/16-17');
    expect(value.position, .5);
    expect(() => FirebaseAssignmentResume.decode(saved().encode(), 'other'), throwsFormatException);
  });
  for (final position in [-.1, 1.1, double.nan, double.infinity]) {
    test('resume rejects invalid position $position', () => expect(() => saved(position: position), throwsFormatException));
  }
  for (final raw in ['{}', '[]', 'invalid', jsonEncode({'extra': 'private'})]) {
    test('resume malformed storage $raw exposes no pointer and can be cleared', () async {
      final prefs = ControlledResumePreferences()..data[firebaseAssignmentResumeKey('a')] = raw;
      final controller = FirebaseAssignmentResumeController('a', () async => prefs, () => true);
      await controller.ready; expect(controller.state.value, isNull); expect(controller.state.error, isNotNull);
      expect(await controller.clear(), isTrue); expect(prefs.data, isEmpty); controller.dispose();
    });
  }
  test('resume save/clear require acknowledged storage and preserve the preceding pointer on failure', () async {
    final prefs = ControlledResumePreferences();
    final controller = FirebaseAssignmentResumeController('a', () async => prefs, () => true);
    await controller.ready; expect(await controller.save(saved()), isTrue);
    prefs.acknowledge = false;
    expect(await controller.save(saved(position: .8)), isFalse); expect(controller.state.value!.position, .5);
    expect(await controller.clear(), isFalse); expect(controller.state.value!.position, .5);
    prefs.acknowledge = true; expect(await controller.clear(), isTrue); expect(controller.state.value, isNull);
    controller.dispose();
  });
  test('resume pending write never claims success after account replacement or allows double writes', () async {
    var current = true; final prefs = ControlledResumePreferences()..writeGate = Completer();
    final controller = FirebaseAssignmentResumeController('a', () async => prefs, () => current);
    await controller.ready; final request = controller.save(saved()); await Future<void>.delayed(Duration.zero);
    expect(controller.state.value, isNull); expect(await controller.save(saved(position: .8)), isFalse);
    current = false; prefs.writeGate!.complete(); expect(await request, isFalse);
    expect(controller.state.value, isNull); expect(prefs.writes, 1); controller.dispose();
  });
  test('resume survives restart without changing standalone chapter storage', () async {
    final prefs = await SharedPreferences.getInstance(); await prefs.setInt('resume_chapter', 53);
    final first = FirebaseAssignmentResumeController('a', () async => prefs, () => true);
    expect(await first.save(saved()), isTrue); first.dispose();
    final next = FirebaseAssignmentResumeController('a', () async => prefs, () => true);
    await next.ready; expect(next.state.value!.matches(own, '16-17', 'en'), isTrue);
    expect(prefs.getInt('resume_chapter'), 53); next.dispose();
  });
  for (final change in <Map<String, dynamic>>[
    {'version': 1.0}, {'version': 2}, {'week': 1.0}, {'week': 10001},
    {'language': 'unknown'}, {'unitKey': '17'}, {'groupId': 'a/b'},
    {'position': '0.5'}, {'position': -1}, {'privateText': 'not allowed'},
  ]) {
    test('resume rejects malformed metadata $change', () {
      final data = jsonDecode(saved().encode()) as Map<String, dynamic>;
      data.addAll(change);
      expect(() => FirebaseAssignmentResume.decode(jsonEncode(data), 'a'), throwsFormatException);
    });
  }

  for (final bad in ['0', '01', '1e0', '+1', '1.0', '10001']) {
    test('route rejects noncanonical week $bad', () {
      expect(() => parseFirebaseReaderRoute('g', 'a', bad, '16-17'),
          throwsFormatException);
    });
  }
  for (final bad in ['17', '52', '16', '51', '01', '16–17']) {
    test('route rejects noncanonical unit $bad', () {
      expect(() => parseFirebaseReaderRoute('g', 'a', '1', bad),
          throwsFormatException);
    });
  }
  test('route accepts exactly all 48 keys at both week bounds', () {
    for (final unit in FirebaseChapterUnit.all) {
      for (final week in ['1', '10000']) {
        expect(parseFirebaseReaderRoute('g', 'other', week, unit.key).unit,
            same(unit));
      }
    }
    for (final segment in ['', '..', 'a/b', '__bad__']) {
      expect(() => parseFirebaseReaderRoute(segment, 'a', '1', '1'),
          throwsFormatException);
      expect(() => parseFirebaseReaderRoute('g', segment, '1', '1'),
          throwsFormatException);
    }
  });
  test('bundled provider constructs and assembles without legacy API/provider',
      () async {
    final container = ProviderContainer(overrides: [
      apiClientProvider
          .overrideWith((ref) => throw StateError('API constructed')),
      contentRepositoryProvider.overrideWith(
          (ref) => throw StateError('Legacy repository constructed')),
    ]);
    final subscription = container.listen(
        firebaseAssignmentContentProvider(selection), (_, __) {});
    final chapter = await container
        .read(firebaseAssignmentContentProvider(selection).future);
    expect(chapter.content, isNotEmpty);
    expect(chapter.language, 'en');
    subscription.close();
    container.dispose();
  });
  for (final start in [16, 51]) {
    test('real Marathi $start originals assembled in order exactly once',
        () async {
      final repo = ContentRepository.bundledOnly();
      final unit = FirebaseChapterUnit.fromChapter(start);
      final chapter = (await repo.getAssignmentChapter(start, language: 'mr'))!;
      final parts = [
        for (var n = start; n <= unit.end; n++)
          (await repo.getChapter(n, language: 'mr'))!
      ];
      expect(chapter.chapterLabel, unit.key);
      expect(chapter.language, 'mr');
      expect(
          chapter.content,
          parts
              .map((part) =>
                  '${part.heading ?? 'Chapter ${part.number}'}\n\n${part.content}')
              .join('\n\n'));
    });
    test('real English $start merged translation is not duplicated', () async {
      final repo = ContentRepository.bundledOnly();
      final original = (await repo.getChapter(start))!;
      final combined = (await repo.getAssignmentChapter(start))!;
      expect(combined.content, original.content);
    });
  }
  test('real English chapter 50 falls back to Marathi original', () async {
    final repo = ContentRepository.bundledOnly();
    final chapter = (await repo.getAssignmentChapter(50))!;
    expect(chapter.language, 'mr');
    expect(
        chapter.content, (await repo.getChapter(50, language: 'mr'))!.content);
  });
  test(
      'all canonical units load from real bundles in every supported reader language',
      () async {
    final repo = ContentRepository.bundledOnly();
    for (final language in AppLanguage.available) {
      for (final unit in FirebaseChapterUnit.all) {
        final chapter = await repo.getAssignmentChapter(unit.start,
            language: language.code);
        expect(chapter, isNotNull, reason: '${language.code}/${unit.key}');
        expect(chapter!.content.trim(), isNotEmpty,
            reason: '${language.code}/${unit.key}');
      }
    }
  });
  test('unknown asset language uses canonical Marathi fallback', () async {
    final repo = ContentRepository.bundledOnly();
    expect((await repo.getAssignmentChapter(16, language: 'missing'))!.language,
        'mr');
  });
  test(
      'missing bundled originals produce explicit provider failure rather than success',
      () async {
    final container = ProviderContainer(overrides: [
      bundledContentRepositoryProvider.overrideWith((ref) => EmptyContent())
    ]);
    final sub = container.listen(
        firebaseAssignmentContentProvider(selection), (_, __) {});
    await expectLater(
        container.read(firebaseAssignmentContentProvider(selection).future),
        throwsFormatException);
    sub.close();
    container.dispose();
  });

  Future<
          (
            auth_test.FakeGateway,
            assignments_test.FakeAssignments,
            ProviderContainer
          )>
      mount(WidgetTester tester,
          {String member = 'a',
          String week = '1',
          String unit = '16-17',
          ContentRepository? content,
          assignments_test.FakeAssignments? gateway,
          media_test.ControlledAudio? audio,
          bool ready = true,
          Future<SharedPreferences> Function()? preferences,
          bool routed = false}) async {
    final auth = auth_test.FakeGateway()..profile = ready ? 'Private' : null;
    final assignments = gateway ?? assignments_test.FakeAssignments();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(auth_test.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseAssignmentsGatewayProvider.overrideWithValue(assignments),
      if (audio != null) chapterAudioProvider.overrideWith((ref) => audio),
      if (preferences != null) firebaseAssignmentResumePreferencesProvider.overrideWithValue(preferences),
      firebaseGroupsGatewayProvider
          .overrideWithValue(assignments_test.PagedGroups()),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API accessed')),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth accessed')),
      contentRepositoryProvider
          .overrideWith((ref) => throw StateError('Legacy content accessed')),
      if (content != null)
        bundledContentRepositoryProvider.overrideWith((ref) => content),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(const FirebaseIdentity('a', null));
    await tester.pump();
    final router = routed ? container.read(routerProvider) : null;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: routed
            ? MaterialApp.router(routerConfig: router)
            : MaterialApp(
                home: FirebaseAssignmentReaderScreen(
                    groupId: 'g',
                    memberUid: member,
                    week: week,
                    unitKey: unit))));
    if (routed) router!.go('/groups/g/assignments/read/$member/$week/$unit');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await auth.changes.close();
    });
    return (auth, assignments, container);
  }

  Future<void> tapComplete(WidgetTester tester) async {
    final button = find.byKey(const Key('reader-complete'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('assignment bookmarks persist separate combined originals without server progress or streaks', (tester) async {
    final (_, assignments, _) = await mount(tester, content: ControlledContent());
    await tester.pumpAndSettle();
    for (final number in [16, 17]) {
      final button = find.byKey(ValueKey('assignment-bookmark-$number'));
      await tester.ensureVisible(button); await tester.pumpAndSettle();
      await tester.tap(button); await tester.pumpAndSettle();
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('bookmarks'), ['16', '17']);
    expect(prefs.getStringList('completed_chapters'), isNull);
    expect(prefs.getStringList('streak_dates'), isNull);
    expect(assignments.updates, isEmpty);
  });

  testWidgets('assignment explicit save stores exact scope without progress and restores after reload', (tester) async {
    final content = ControlledContent();
    content.gates['en'] = Completer<Chapter?>()..complete(Chapter(id: 16, number: 16,
      title: 'Long text', content: List.filled(180, 'Original chapter reading content.').join('\n')));
    final (_, assignments, container) = await mount(tester, content: content);
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.controller!.offset, 0);
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent * .6);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-save-position'))); await tester.pumpAndSettle();
    final savedValue = container.read(firebaseAssignmentResumeProvider('a')).value!;
    expect(savedValue.matches(own, '16-17', 'en'), isTrue); expect(savedValue.position, closeTo(.6, .01));
    list.controller!.jumpTo(0); await tester.pumpAndSettle();
    await tester.tap(find.text('Reload assignment access')); await tester.pumpAndSettle();
    expect(list.controller!.offset / list.controller!.position.maxScrollExtent, closeTo(.6, .01));
    expect(assignments.updates, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('streak_dates'), isNull); expect(prefs.getInt('resume_chapter'), isNull);
  });

  for (final wrong in [
    saved(scope: (uid: 'a', groupId: 'different', memberUid: 'a', week: 1)),
    saved(scope: (uid: 'a', groupId: 'g', memberUid: 'other', week: 1)),
    saved(scope: (uid: 'a', groupId: 'g', memberUid: 'a', week: 2)),
    saved(unit: '18-19'), saved(language: 'mr'),
    saved(scope: (uid: 'b', groupId: 'g', memberUid: 'a', week: 1)),
  ]) {
    testWidgets('resume does not restore mismatched assignment ${wrong.encode()}', (tester) async {
      SharedPreferences.setMockInitialValues({firebaseAssignmentResumeKey('a'): wrong.encode()});
      await mount(tester, content: ControlledContent()); await tester.pumpAndSettle();
      expect(tester.widget<ListView>(find.byType(ListView).first).controller!.offset, 0);
    });
  }
  testWidgets('resume waits for authorized content, but a denied assignment never loads or restores content', (tester) async {
    SharedPreferences.setMockInitialValues({firebaseAssignmentResumeKey('a'): saved().encode()});
    final content = ControlledContent()..gates['en'] = Completer<Chapter?>();
    final (_, assignments, _) = await mount(tester, content: content);
    expect(find.byKey(const Key('assignment-save-position')), findsNothing);
    content.gates['en']!.complete(Chapter(id: 16, number: 16, title: 'Delayed chapter',
      content: List.filled(160, 'Delayed original chapter text').join('\n')));
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(find.byType(ListView).first).controller!;
    expect(scroll.offset / scroll.position.maxScrollExtent, closeTo(.5, .01));
    assignments.saved[own] = {}; scroll.jumpTo(0); await tester.pumpAndSettle();
    await tester.tap(find.text('Reload assignment access')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-content')), findsNothing);
    expect(find.byKey(const Key('assignment-save-position')), findsNothing);
    expect(scroll.offset, 0); expect(content.calls, 1); expect(assignments.updates, isEmpty);
  });
  testWidgets('delayed resume load after logout is discarded with no restore or success', (tester) async {
    final gate = Completer<SharedPreferences>();
    final prefs = ControlledResumePreferences()..data[firebaseAssignmentResumeKey('a')] = saved().encode();
    final (auth, assignments, _) = await mount(tester, content: ControlledContent(), preferences: () => gate.future);
    auth.emit(null); await tester.pump(); gate.complete(prefs); await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-content')), findsNothing);
    expect(find.byKey(const Key('assignment-save-position')), findsNothing);
    expect(assignments.updates, isEmpty); expect(tester.takeException(), isNull);
  });
  testWidgets('delayed resume restore rejects language and content generation changes', (tester) async {
    final gate = Completer<SharedPreferences>();
    final prefs = ControlledResumePreferences()..data[firebaseAssignmentResumeKey('a')] = saved().encode();
    final content = ControlledContent();
    final (_, _, container) = await mount(tester, content: content, preferences: () => gate.future);
    await container.read(languageProvider.notifier).setReaderLanguage(AppLanguage.marathi);
    await tester.pumpAndSettle(); gate.complete(prefs); await tester.pumpAndSettle();
    expect(tester.widget<ListView>(find.byType(ListView).first).controller!.offset, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed assignment position write has no success or completion', (tester) async {
    final prefs = ControlledResumePreferences()..acknowledge = false;
    final (_, assignments, container) = await mount(tester, content: ControlledContent(), preferences: () async => prefs);
    await tester.pumpAndSettle(); await tester.tap(find.byKey(const Key('assignment-save-position')));
    await tester.pumpAndSettle(); expect(container.read(firebaseAssignmentResumeProvider('a')).value, isNull);
    expect(find.text('Assignment reading position saved.'), findsNothing);
    expect(find.byKey(const Key('assignment-resume-error')), findsOneWidget);
    expect(assignments.updates, isEmpty);
  });
  testWidgets('account replacement during save never overwrites or displays new account pointer', (tester) async {
    final prefs = ControlledResumePreferences()..writeGate = Completer();
    final second = saved(scope: (uid: 'b', groupId: 'g', memberUid: 'a', week: 1), position: .2);
    prefs.data[firebaseAssignmentResumeKey('b')] = second.encode();
    final content = ControlledContent();
    content.gates['en'] = Completer<Chapter?>()..complete(Chapter(id: 16, number: 16,
      title: 'Account switch text', content: List.filled(120, 'Original chapter account switch').join('\n')));
    final (auth, assignments, container) = await mount(tester, content: content, preferences: () async => prefs);
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(find.byType(ListView).first).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent * .6); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignment-save-position'))); await tester.pump();
    auth.emit(const FirebaseIdentity('b', null)); await tester.pumpAndSettle();
    prefs.writeGate!.complete(); await tester.pumpAndSettle();
    final current = container.read(firebaseAssignmentResumeProvider('b')).value!;
    expect(current.scope.uid, 'b'); expect(current.position, .2);
    expect(prefs.data[firebaseAssignmentResumeKey('b')], second.encode());
    expect(find.text('Assignment reading position saved.'), findsNothing);
    final nextScroll = tester.widget<ListView>(find.byType(ListView).first).controller!;
    expect(nextScroll.offset / nextScroll.position.maxScrollExtent, closeTo(.2, .01));
    expect(assignments.updates, isEmpty); expect(tester.takeException(), isNull);
  });
  testWidgets('combined bookmarks and save controls fit narrow large-text reader', (tester) async {
    tester.view.physicalSize = const Size(360, 760); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final (_, _, container) = await mount(tester, content: ControlledContent());
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
      home: const FirebaseAssignmentReaderScreen(groupId: 'g', memberUid: 'a', week: '1', unitKey: '16-17'))));
    await tester.pumpAndSettle(); expect(find.byKey(const ValueKey('assignment-bookmark-17')), findsOneWidget);
  });

  testWidgets('invalid link does not read assignments or load content',
      (tester) async {
    final content = ControlledContent();
    final (_, assignments, _) =
        await mount(tester, unit: '17', content: content);
    expect(find.text('Invalid assignment reader link.'), findsOneWidget);
    expect(assignments.reads, isEmpty);
    expect(content.calls, 0);
  });
  testWidgets('pending profile cannot read assignments or content',
      (tester) async {
    final content = ControlledContent();
    final (_, assignments, _) =
        await mount(tester, ready: false, content: content);
    expect(find.text('Ready Firebase session required.'), findsOneWidget);
    expect(assignments.reads, isEmpty);
    expect(content.calls, 0);
  });
  testWidgets('absent assignment denies content and completion',
      (tester) async {
    final content = ControlledContent();
    final gateway = assignments_test.FakeAssignments()..saved[own] = {};
    await mount(tester, gateway: gateway, content: content);
    expect(find.textContaining('This assignment is not available'),
        findsOneWidget);
    expect(content.calls, 0);
    expect(find.byKey(const Key('reader-complete')), findsNothing);
    expect(find.byType(ReaderAudioControls), findsNothing);
  });
  testWidgets(
      'other member uses active SDK UID and preserves URL member/week read only',
      (tester) async {
    final (_, assignments, _) = await mount(tester,
        member: 'public-uid-b', week: '10000', content: ControlledContent());
    expect(assignments.reads.single,
        (uid: 'a', groupId: 'g', memberUid: 'public-uid-b', week: 10000));
    expect(find.byKey(const Key('reader-content')), findsOneWidget);
    expect(find.byKey(const Key('reader-complete')), findsNothing);
    expect(assignments.updates, isEmpty);
  });
  testWidgets('combined Marathi assignment audio preserves originals without progress writes', (tester) async {
    SharedPreferences.setMockInitialValues({'reader_language': 'mr'});
    final content = ControlledContent();
    content.gates['mr'] = Completer<Chapter?>()..complete(const Chapter(
      id: 16, number: 16, chapterLabel: '16-17', language: 'mr',
      title: 'Marathi combined originals', content: 'Original sixteen and seventeen'));
    final audio = media_test.ControlledAudio();
    final (_, assignments, _) = await mount(tester, content: content, audio: audio);
    await tester.pumpAndSettle();
    for (final number in [16, 17]) {
      final track = audioTrackForChapter('mr', number)!;
      final button = find.byKey(ValueKey('reader-audio-${track.fileName}'));
      expect(button, findsOneWidget);
      await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(button); await tester.pumpAndSettle();
      await tester.tap(button); await tester.pumpAndSettle();
      expect(audio.played.last.fileName, track.fileName);
    }
    expect(assignments.updates, isEmpty);
    expect(Firebase.apps, isEmpty);
  });
  testWidgets('opening and scrolling never write progress', (tester) async {
    final (_, assignments, _) =
        await mount(tester, content: ControlledContent());
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(assignments.updates, isEmpty);
    expect(find.byType(SelectableText), findsOneWidget);
  });
  testWidgets('explicit completion requires reload-observed completed status',
      (tester) async {
    final (_, assignments, _) =
        await mount(tester, content: ControlledContent());
    await tapComplete(tester);
    expect(assignments.updates, [FirebaseReadingStatus.completed]);
    expect(assignments.reads.length,
        3); // entry, prewrite access, postwrite reload
    expect(find.byKey(const Key('reader-completion-success')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reader-complete')))
            .onPressed,
        isNull);
  });
  testWidgets(
      'already completed initial assignment is disabled without success claim',
      (tester) async {
    final gateway = assignments_test.FakeAssignments()
      ..saved[own] = {
        '16-17': assignments_test.assignmentData(
            status: FirebaseReadingStatus.completed)
      };
    await mount(tester, gateway: gateway, content: ControlledContent());
    expect(find.text('Already completed'), findsOneWidget);
    expect(find.byKey(const Key('reader-completion-success')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reader-complete')))
            .onPressed,
        isNull);
    expect(gateway.updates, isEmpty);
  });
  testWidgets('unobserved completion is never reported as success',
      (tester) async {
    final gateway = UnobservedCompletion();
    await mount(tester, gateway: gateway, content: ControlledContent());
    await tapComplete(tester);
    expect(gateway.updates.length, 1);
    expect(find.byKey(const Key('reader-completion-success')), findsNothing);
    expect(find.text('Status: Not started'), findsOneWidget);
  });
  testWidgets('double tap while status write pending writes once',
      (tester) async {
    final gateway = assignments_test.FakeAssignments()
      ..writeGate = Completer<void>();
    await mount(tester, gateway: gateway, content: ControlledContent());
    await tapComplete(tester);
    expect(find.byKey(const Key('reader-complete')), findsNothing);
    expect(gateway.updates.length, 1);
    gateway.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(gateway.updates.length, 1);
    expect(find.byKey(const Key('reader-completion-success')), findsOneWidget);
  });
  for (final failure in ['permission-denied', 'unavailable']) {
    testWidgets('$failure access error blocks local content and permits retry',
        (tester) async {
      final content = ControlledContent();
      final gateway = assignments_test.FakeAssignments()
        ..error = FirebaseException(plugin: 'cloud_firestore', code: failure);
      await mount(tester, gateway: gateway, content: content);
      expect(content.calls, 0);
      expect(find.byKey(const Key('reader-access-error')), findsOneWidget);
      expect(find.byKey(const Key('reader-complete')), findsNothing);
      gateway.error = null;
      await tester.tap(find.text('Reload assignment access'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-content')), findsOneWidget);
    });
    testWidgets(
        '$failure status error clears content and controls without false success',
        (tester) async {
      final gateway = assignments_test.FakeAssignments()
        ..writeError =
            FirebaseException(plugin: 'cloud_firestore', code: failure);
      await mount(tester, gateway: gateway, content: ControlledContent());
      await tapComplete(tester);
      expect(find.byKey(const Key('reader-access-error')), findsOneWidget);
      expect(find.byKey(const Key('reader-content')), findsNothing);
      expect(find.byKey(const Key('reader-complete')), findsNothing);
      expect(find.byKey(const Key('reader-completion-success')), findsNothing);
    });
  }
  testWidgets('assignment removed before completion cannot write',
      (tester) async {
    final (_, gateway, _) = await mount(tester, content: ControlledContent());
    gateway.saved[own] = {};
    await tapComplete(tester);
    expect(gateway.updates, isEmpty);
    expect(find.byKey(const Key('reader-content')), findsNothing);
  });
  testWidgets('postwrite reload offline cannot claim completion',
      (tester) async {
    final gateway = assignments_test.FakeAssignments()
      ..writeGate = Completer<void>();
    await mount(tester, gateway: gateway, content: ControlledContent());
    await tapComplete(tester);
    gateway.error = StateError('offline');
    gateway.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-content')), findsNothing);
    expect(find.byKey(const Key('reader-completion-success')), findsNothing);
  });
  testWidgets('missing local content is an explicit error with working retry',
      (tester) async {
    final content = ControlledContent()..missing = true;
    await mount(tester, content: content);
    expect(find.byKey(const Key('reader-content-error')), findsOneWidget);
    expect(find.byKey(const Key('reader-complete')), findsNothing);
    content.missing = false;
    await tester.tap(find.text('Retry content'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-content')), findsOneWidget);
  });
  testWidgets('real asset fallback language is labeled for chapter 50',
      (tester) async {
    final gateway = assignments_test.FakeAssignments()
      ..saved[own] = {'50': assignments_test.assignmentData(chapter: 50)};
    await mount(tester, gateway: gateway, unit: '50');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('Fallback content: Marathi (mr)'), findsOneWidget);
    expect(find.byKey(const Key('reader-content')), findsOneWidget);
  });
  for (final next in <FirebaseIdentity?>[
    null,
    const FirebaseIdentity('b', null)
  ]) {
    testWidgets(
        '${next == null ? 'logout' : 'account switch'} discards delayed content',
        (tester) async {
      final content = ControlledContent()..gates['en'] = Completer<Chapter?>();
      final (auth, _, _) = await mount(tester, content: content);
      auth.profile = null;
      auth.emit(next);
      await tester.pump();
      content.gates['en']!.complete(fixture);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-content')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '${next == null ? 'logout' : 'account switch'} discards delayed status',
        (tester) async {
      final gateway = assignments_test.FakeAssignments()
        ..writeGate = Completer<void>();
      final (auth, _, _) =
          await mount(tester, gateway: gateway, content: ControlledContent());
      await tapComplete(tester);
      auth.emit(next);
      await tester.pump();
      gateway.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-completion-success')), findsNothing);
      expect(gateway.reads.where((scope) => scope.uid == 'a').length, 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('SDK drift without session event cannot complete',
      (tester) async {
    final (auth, gateway, _) =
        await mount(tester, content: ControlledContent());
    auth.currentUser = const FirebaseIdentity('b', null);
    await tapComplete(tester);
    expect(gateway.updates, isEmpty);
    expect(find.byKey(const Key('reader-completion-success')), findsNothing);
  });
  testWidgets(
      'language change discards late content and shares installation preferences',
      (tester) async {
    final content = ControlledContent()..gates['en'] = Completer<Chapter?>();
    final (_, _, container) = await mount(tester, content: content);
    await container
        .read(languageProvider.notifier)
        .setReaderLanguage(AppLanguage.marathi);
    await tester.pumpAndSettle();
    content.gates['en']!.complete(
        const Chapter(id: 1, number: 1, title: 'Old', content: 'Late English'));
    await tester.pumpAndSettle();
    expect(find.text('Late English'), findsNothing);
    expect(find.byKey(const Key('reader-content')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('reader_language'),
        'mr');
  });
  testWidgets('font size safely reuses clamped reader preferences',
      (tester) async {
    final (_, _, container) = await mount(tester, content: ControlledContent());
    await container.read(readerSettingsProvider.notifier).setFontSize(1000);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('reader-content')))
            .style!
            .fontSize,
        maxFontSize);
  });
  testWidgets('guarded nested reader redirects on pending session and logout',
      (tester) async {
    final (auth, gateway, container) = await mount(tester,
        ready: false, routed: true, content: ControlledContent());
    expect(find.byType(FirebaseAssignmentReaderScreen), findsNothing);
    expect(gateway.reads, isEmpty);
    auth.profile = 'Private';
    await container.read(firebaseSessionProvider.notifier).reloadProfile();
    container.read(routerProvider).go('/groups/g/assignments/read/a/1/16-17');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-content')), findsOneWidget);
    auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.byType(FirebaseAssignmentReaderScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('row navigation back refreshes exact member/week scope',
      (tester) async {
    final (_, gateway, container) =
        await mount(tester, routed: true, content: ControlledContent());
    final router = container.read(routerProvider);
    router.go('/groups/g/assignments');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Read assignment').hitTestable(), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read assignment').hitTestable());
    await tester.pumpAndSettle();
    expect(gateway.reads.last.week, 7);
    await tapComplete(tester);
    final before = gateway.reads.length;
    await tester.tap(find.byTooltip('Back to assignments'));
    await tester.pumpAndSettle();
    expect(gateway.reads.length, before + 1);
    expect(
        gateway.reads.last, (uid: 'a', groupId: 'g', memberUid: 'a', week: 7));
    expect(find.text('Status: Completed'), findsOneWidget);
  });
}
