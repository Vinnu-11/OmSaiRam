import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/features/groups/data/assignment_model.dart';
import 'package:om_sai_ram/features/groups/data/assignments_repository.dart';
import 'package:om_sai_ram/features/groups/data/group_model.dart';
import 'package:om_sai_ram/features/groups/presentation/manual_assignment_sheet.dart';
import 'package:om_sai_ram/features/reader/data/chapter_model.dart';

Assignment _assignment(int chapterId, int number, String userId, int week) =>
    Assignment(id: '$userId-$week-$chapterId', groupId: 'group', userId: userId,
        chapterId: chapterId, chapterNumber: number, weekNumber: week,
        status: ReadingStatus.notStarted, assignedAt: DateTime(2026, 10, 13));

class _Repository extends AssignmentsRepository {
  final calls = <({String userId, int chapterId, int week})>[];
  final List<Assignment> existing;
  int? failChapter;
  bool failLoad = false;

  _Repository({this.existing = const []}) : super(apiClient: ApiClient());

  @override
  Future<List<Chapter>> getAssignableChapters() async {
    if (failLoad) throw Exception('Offline');
    return [
      for (final n in [16, 18, 20])
        Chapter(id: 200 + n, number: n, title: 'Reading $n', content: ''),
    ];
  }

  @override
  Future<List<Assignment>> getGroupAssignments(String groupId, {int? weekNumber}) async => existing;

  @override
  Future<Assignment> createAssignment({required String groupId,
      required String userId, required int chapterId, int weekNumber = 1,
      DateTime? scheduledDate}) async {
    calls.add((userId: userId, chapterId: chapterId, week: weekNumber));
    if (chapterId == failChapter) {
      throw DioException(requestOptions: RequestOptions(path: '/assignments'),
          response: Response(requestOptions: RequestOptions(path: '/assignments'),
              statusCode: 400, data: {'detail': 'Already assigned for this week'}));
    }
    return _assignment(chapterId, chapterId - 200, userId, weekNumber);
  }
}

class _ChapterApi extends ApiClient {
  final bool emptyMarathi;

  _ChapterApi({this.emptyMarathi = false});

  @override
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    expect(path, isIn(['/content/chapters/mr', '/content/chapters/en']));
    if (emptyMarathi && path.endsWith('/mr')) {
      return Response(requestOptions: RequestOptions(path: path), data: []);
    }
    return Response(requestOptions: RequestOptions(path: path), data: [
      for (final n in [18, 19, 16, 17, 51, 52, 53, 50])
        {'id': 200 + n, 'number': n, 'title': 'Chapter $n', 'content': '', 'language': 'mr'},
    ]);
  }
}

Future<void> _open(WidgetTester tester, _Repository repository,
    {void Function(int, int)? onAssigned}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [assignmentsRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showModalBottomSheet(
        context: context, isScrollControlled: true,
        builder: (_) => ManualAssignmentSheet(groupId: 'group', initialWeek: 2,
          members: [
            GroupMember(id: 'lead', userId: 'lead', name: 'Lead', role: 'admin', joinedAt: DateTime(2026)),
            GroupMember(id: 'member', userId: 'member', name: 'Member', role: 'member', joinedAt: DateTime(2026)),
          ],
          onAssigned: onAssigned ?? (_, __) {},
        ),
      ), child: const Text('Open manual assignment')),
    ))),
  ));
  await tester.tap(find.text('Open manual assignment'));
  await tester.pumpAndSettle();
}

void main() {
  test('server chapter IDs are retained and combined interiors are excluded', () async {
    final chapters = await AssignmentsRepository(apiClient: _ChapterApi()).getAssignableChapters();
    expect(chapters.map((chapter) => chapter.number), [16, 18, 50, 51]);
    expect(chapters.map((chapter) => chapter.id), [216, 218, 250, 251]);
  });

  test('older English-only server indexes support manual assignment', () async {
    final repo = AssignmentsRepository(apiClient: _ChapterApi(emptyMarathi: true));
    final chapters = await repo.getAssignableChapters();
    expect(chapters.map((chapter) => chapter.number), [16, 18, 50, 51]);
  });

  testWidgets('manually assign selected combined chapters to a member and week', (tester) async {
    final repo = _Repository();
    int? savedWeek;
    int? savedCount;
    await _open(tester, repo, onAssigned: (week, count) {
      savedWeek = week; savedCount = count;
    });
    expect(find.text('Chapter 16-17'), findsOneWidget);
    expect(find.text('Chapter 18-19'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('manual-save'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('manual-member')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('manual-week')), '3');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('manual-chapter-16')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('manual-chapter-18')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();
    expect(repo.calls, [(userId: 'member', chapterId: 216, week: 3),
                        (userId: 'member', chapterId: 218, week: 3)]);
    expect(savedWeek, 3);
    expect(savedCount, 2);
    expect(find.byType(ManualAssignmentSheet), findsNothing);
  });

  testWidgets('disable same-week duplicates but allow a different reading week', (tester) async {
    final repo = _Repository(existing: [_assignment(216, 16, 'lead', 2)]);
    await _open(tester, repo);
    final chapter = find.byKey(const ValueKey('manual-chapter-16'));
    expect(tester.widget<CheckboxListTile>(chapter).onChanged, isNull);
    await tester.enterText(find.byKey(const ValueKey('manual-week')), '3');
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(chapter).onChanged, isNotNull);
    await tester.tap(chapter);
    await tester.enterText(find.byKey(const ValueKey('manual-week')), '0');
    await tester.tap(chapter);
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pump();
    expect(find.text('Week ≥ 1'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('partial failures preserve unsaved choices and do not resubmit saved chapters', (tester) async {
    final repo = _Repository()..failChapter = 218;
    await _open(tester, repo);
    await tester.tap(find.byKey(const ValueKey('manual-chapter-16')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('manual-chapter-18')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();
    expect(find.text('1 assignment(s) saved. Already assigned for this week'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('manual-chapter-16'))).value, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('manual-chapter-18'))).value, isTrue);
    repo.failChapter = null;
    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();
    expect(repo.calls.map((call) => call.chapterId), [216, 218, 218]);
  });

  testWidgets('chapter loading errors offer retry', (tester) async {
    final repo = _Repository()..failLoad = true;
    await _open(tester, repo);
    expect(find.text('Could not load chapters. Please retry.'), findsOneWidget);
    repo.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 16-17'), findsOneWidget);
  });

  testWidgets('manual form stays usable with the keyboard open', (tester) async {
    await _open(tester, _Repository());
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('manual-week')), findsOneWidget);
    expect(find.byKey(const ValueKey('manual-save')), findsOneWidget);
  });
}