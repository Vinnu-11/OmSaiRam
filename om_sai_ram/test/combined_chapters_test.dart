import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/constants/chapter_units.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/features/groups/data/assignment_model.dart';
import 'package:om_sai_ram/features/groups/data/schedule_suggestion_model.dart';
import 'package:om_sai_ram/features/reader/data/chapter_model.dart';
import 'package:om_sai_ram/features/reader/data/content_repository.dart';

class _ContentRepository extends ContentRepository {
  final Map<String, List<Chapter>> chapters;

  _ContentRepository(this.chapters) : super(apiClient: ApiClient());

  @override
  Future<List<Chapter>> getChapters({String language = 'en'}) async =>
      chapters[language] ?? [];
}

void main() {
  test('combined ranges advance once and retain their full labels', () {
    expect(ChapterUnits.advance(15, 3), 20);
    for (final range in ChapterUnits.combined.entries) {
      expect(ChapterUnits.start(range.value), range.key);
      expect(ChapterUnits.next(range.key), range.value + 1);
      expect(ChapterUnits.previous(range.value + 1), range.key);
      expect(ChapterUnits.label(range.value), '${range.key}-${range.value}');
    }
  });

  test('assignment and preview labels include combined ranges', () {
    final assignment = Assignment.fromJson({
      'id': 'assignment', 'group_id': 'group', 'user_id': 'user',
      'chapter_id': 16, 'chapter_number': 16,
      'assigned_at': '2026-10-13T00:00:00',
    });
    expect(assignment.displayChapterLabel, '16-17');
    expect(assignment.lastChapterNumber, 17);
    const slot = SuggestedSlot(weekNumber: 1, position: 0, userId: 'user',
        userName: 'Reader', chapterNumbers: [16, 18], isManual: false);
    expect(slot.label, 'Ch.16-17, 18-19');
  });

  for (final range in ChapterUnits.combined.entries) {
    test('translation ${range.key}-${range.value} is read only once', () async {
      final chapter = Chapter(id: range.key, number: range.key,
          chapterLabel: '${range.key}-${range.value}',
          title: 'Combined', content: 'Combined content');
      final repo = _ContentRepository({'en': [chapter]});
      final result = await repo.getAssignmentChapter(range.value);
      expect(result, same(chapter));
      expect(result!.content, 'Combined content');
    });

    test('Marathi ${range.key}-${range.value} includes every original', () async {
      final originals = [
        for (var n = range.key; n <= range.value; n++)
          Chapter(id: n, number: n, chapterLabel: '$n', title: 'Original $n',
              content: 'Original content $n', language: 'mr'),
      ];
      final repo = _ContentRepository({'mr': originals});
      final result = await repo.getAssignmentChapter(range.value, language: 'mr');
      expect(result!.chapterLabel, '${range.key}-${range.value}');
      for (final chapter in originals) {
        expect(result.content, contains(chapter.content));
      }
      // Standalone Marathi chapters remain separate.
      expect(await repo.getChapter(range.key, language: 'mr'), same(originals.first));
    });
  }
}