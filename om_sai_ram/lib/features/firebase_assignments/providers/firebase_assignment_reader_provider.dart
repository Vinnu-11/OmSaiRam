import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reader/data/chapter_model.dart';
import '../../reader/data/content_repository.dart';
import '../data/firebase_assignment_models.dart';

typedef FirebaseReaderSelection = ({String language, String unitKey});

/// Strict URL parsing deliberately does not normalize original-number aliases.
({String groupId, String memberUid, int week, FirebaseChapterUnit unit})
    parseFirebaseReaderRoute(
        String groupId, String memberUid, String week, String unitKey) {
  assignmentSegment(groupId);
  assignmentSegment(memberUid);
  if (!RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(week)) {
    throw const FormatException('Invalid reader week.');
  }
  final number = assignmentWeek(int.parse(week));
  final unit = FirebaseChapterUnit.all.firstWhere((unit) => unit.key == unitKey,
      orElse: () => throw const FormatException('Invalid reader unit.'));
  return (groupId: groupId, memberUid: memberUid, week: number, unit: unit);
}

/// The UI subscribes only after a fresh server assignment read authorizes the unit.
/// Language/unit changes dispose old subscriptions; no legacy reader hooks run.
final firebaseAssignmentContentProvider = FutureProvider.autoDispose
    .family<Chapter, FirebaseReaderSelection>((ref, selection) async {
  final unit =
      parseFirebaseReaderRoute('content', 'content', '1', selection.unitKey)
          .unit;
  final chapter = await ref
      .watch(bundledContentRepositoryProvider)
      .getAssignmentChapter(unit.start, language: selection.language);
  if (chapter == null || chapter.content.trim().isEmpty) {
    throw const FormatException('Bundled assignment content is unavailable.');
  }
  return chapter;
});
