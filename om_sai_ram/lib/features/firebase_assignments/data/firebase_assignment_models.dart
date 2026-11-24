import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

String assignmentSegment(String value) {
  documentId(value);
  if (RegExp(r'^__.*__$').hasMatch(value) || utf8.encode(value).length > 1500) {
    throw const FormatException('Invalid assignment path segment.');
  }
  return value;
}

int assignmentWeek(int value) {
  if (value < 1 || value > 10000) {
    throw const FormatException('Week must be 1–10000.');
  }
  return value;
}

/// Original chapter numbers, never language-specific SQL chapter IDs.
class FirebaseChapterUnit {
  final String key;
  final int start, end;
  const FirebaseChapterUnit._(this.key, this.start, this.end);
  factory FirebaseChapterUnit.fromChapter(int number) {
    if (number < 1 || number > 53) {
      throw const FormatException('Original chapter must be 1–53.');
    }
    var start = number;
    const combined = {16: 17, 18: 19, 43: 44, 51: 53};
    for (final range in combined.entries) {
      if (number >= range.key && number <= range.value) start = range.key;
    }
    final end = combined[start] ?? start;
    return FirebaseChapterUnit._(
        start == end ? '$start' : '$start-$end', start, end);
  }
  static final List<FirebaseChapterUnit> all = List.unmodifiable([
    for (var number = 1; number <= 53; number++)
      if (FirebaseChapterUnit.fromChapter(number).start == number)
        FirebaseChapterUnit.fromChapter(number),
  ]);
}

enum FirebaseReadingStatus {
  notStarted('not_started', 'Not started'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed');

  final String key, label;
  const FirebaseReadingStatus(this.key, this.label);
  static FirebaseReadingStatus parse(Object? value) => values.firstWhere(
      (status) => status.key == value,
      orElse: () => throw const FormatException('Invalid assignment status.'));
}

typedef FirebaseAssignmentsScope = ({
  String uid,
  String groupId,
  String memberUid,
  int week
});

void validateAssignmentsScope(FirebaseAssignmentsScope scope) {
  assignmentSegment(scope.uid);
  assignmentSegment(scope.groupId);
  assignmentSegment(scope.memberUid);
  assignmentWeek(scope.week);
}

class FirebaseAssignment {
  final String groupId, userId, createdBy;
  final int weekNumber;
  final FirebaseChapterUnit unit;
  final DateTime? scheduledDate;
  final DateTime createdAt, progressUpdatedAt;
  final FirebaseReadingStatus status;
  final bool archived;
  final int revision;
  final Timestamp progressToken;
  final Timestamp createdToken;
  bool activeSince(Timestamp joinedAt) => !archived && createdToken.compareTo(joinedAt) >= 0;
  bool activeFor(FirebaseMembership member) => userId == member.uid &&
      activeSince(member.joinedAtToken ?? Timestamp.fromDate(member.joinedAt));
  const FirebaseAssignment._(
      {required this.groupId,
      required this.userId,
      required this.createdBy,
      required this.weekNumber,
      required this.unit,
      required this.scheduledDate,
      required this.createdAt,
      required this.progressUpdatedAt,
      required this.status, required this.archived, required this.revision, required this.progressToken, required this.createdToken});

  /// Exactly ELEVEN fields, matching the actual rules and canonical path.
  factory FirebaseAssignment.parse(
      FirebaseAssignmentsScope scope, String id, Map<String, dynamic>? raw) {
    validateAssignmentsScope(scope);
    final data = exactData(raw, {
      'groupId',
      'userId',
      'weekNumber',
      'unitKey',
      'chapterStart',
      'chapterEnd',
      'scheduledDate',
      'createdBy',
      'createdAt',
      'status',
      'progressUpdatedAt'
    }, {'archived', 'revision', 'changedBy', 'changedAt'});
    const lifecycle = {'archived', 'revision', 'changedBy', 'changedAt'};
    final versioned = data.keys.any(lifecycle.contains);
    if (versioned) {
      if (!data.keys.toSet().containsAll(lifecycle) || data['archived'] is! bool) {
        throw const FormatException('Invalid assignment lifecycle fields.');
      }
      intField(data, 'revision', 1, 2147483647);
      assignmentSegment(textField(data, 'changedBy', 1500));
      dateField(data, 'changedAt');
    }
    final start = intField(data, 'chapterStart', 1, 51);
    final unit = FirebaseChapterUnit.fromChapter(start);
    if (data['groupId'] != scope.groupId ||
        data['userId'] != scope.memberUid ||
        intField(data, 'weekNumber', 1, 10000) != scope.week ||
        unit.start != start ||
        data['chapterEnd'] is! int ||
        data['chapterEnd'] != unit.end ||
        data['unitKey'] != unit.key ||
        id != unit.key) {
      throw const FormatException(
          'Assignment path or canonical unit mismatch.');
    }
    final scheduled = data['scheduledDate'];
    if (scheduled != null && scheduled is! Timestamp) {
      throw const FormatException('Invalid server scheduledDate.');
    }
    return FirebaseAssignment._(
        groupId: scope.groupId,
        userId: scope.memberUid,
        createdBy: assignmentSegment(textField(data, 'createdBy', 1500)),
        weekNumber: scope.week,
        unit: unit,
        scheduledDate:
            scheduled == null ? null : dateField(data, 'scheduledDate'),
        createdAt: dateField(data, 'createdAt'),
        progressUpdatedAt: dateField(data, 'progressUpdatedAt'),
        status: FirebaseReadingStatus.parse(data['status']),
        archived: versioned ? data['archived'] as bool : false,
        revision: versioned ? data['revision'] as int : 0,
        progressToken: data['progressUpdatedAt'] as Timestamp, createdToken: data['createdAt'] as Timestamp);
  }
}

class FirebaseAssignmentsResult {
  final FirebaseGroup group;
  final FirebaseMembership self, member;
  final List<FirebaseAssignment> assignments;
  FirebaseAssignmentsResult(this.group, this.self, this.member,
      Iterable<FirebaseAssignment> assignments)
      : assignments = List.unmodifiable(assignments);
}
