import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

typedef FirebaseTaskOptions = ({int pageSize, int weeksAhead, int? weekNumber});
const defaultTaskOptions = (pageSize: 5, weeksAhead: 1, weekNumber: null);
typedef FirebaseTaskBinding = ({String uid, FirebaseTaskOptions options});
typedef FirebaseTaskSummary = ({
  int total,
  int notStarted,
  int inProgress,
  int completed
});

void validateTaskOptions(FirebaseTaskOptions options, [String? cursor]) {
  if (options.pageSize < 1 ||
      options.pageSize > 10 ||
      options.weeksAhead < 1 ||
      options.weeksAhead > 3) {
    throw const FormatException('Tasks require 1–10 groups and 1–3 weeks.');
  }
  if (options.weekNumber != null) assignmentWeek(options.weekNumber!);
  if (cursor != null) assignmentSegment(cursor);
}

List<int> taskWeeks(FirebaseGroup group, FirebaseTaskOptions options) {
  validateTaskOptions(options);
  assignmentWeek(group.currentWeek);
  final start = options.weekNumber ?? group.currentWeek;
  return [
    for (var i = 0; i < options.weeksAhead && start + i <= 10000; i++) start + i
  ];
}

FirebaseTaskSummary taskSummary(Iterable<FirebaseAssignment> rows) {
  var total = 0, notStarted = 0, inProgress = 0, completed = 0;
  for (final row in rows) {
    if (row.archived) continue;
    total++;
    switch (row.status) {
      case FirebaseReadingStatus.notStarted:
        notStarted++;
      case FirebaseReadingStatus.inProgress:
        inProgress++;
      case FirebaseReadingStatus.completed:
        completed++;
    }
  }
  return (
    total: total,
    notStarted: notStarted,
    inProgress: inProgress,
    completed: completed
  );
}

class FirebaseTaskWeek {
  final int weekNumber;
  final List<FirebaseAssignment> assignments;
  final FirebaseTaskSummary summary;
  FirebaseTaskWeek(this.weekNumber, Iterable<FirebaseAssignment> assignments,
      {FirebaseTaskSummary? summary})
      : assignments = List.unmodifiable(assignments),
        summary = summary ?? taskSummary(assignments);
}

class FirebaseTaskGroup {
  final FirebaseGroup group;
  final List<FirebaseTaskWeek> weeks;
  FirebaseTaskGroup(this.group, Iterable<FirebaseTaskWeek> weeks)
      : weeks = List.unmodifiable(weeks);
}

class FirebaseTaskPage {
  final String uid;
  final List<FirebaseTaskGroup> groups;
  final String? cursor;
  final bool hasMore;
  FirebaseTaskPage(this.uid, Iterable<FirebaseTaskGroup> groups,
      {this.cursor, required this.hasMore})
      : groups = List.unmodifiable(groups);

  /// Check even injected responses. Counts are per own UID/selected group-week,
  /// never group-wide or all-time totals. Empty groups remain cursor-bearing.
  void validate(FirebaseTaskBinding binding, String? after) {
    assignmentSegment(binding.uid);
    validateTaskOptions(binding.options, after);
    if (uid != binding.uid ||
        groups.length > binding.options.pageSize ||
        hasMore != (groups.length == binding.options.pageSize) ||
        cursor != (hasMore ? groups.last.group.id : null)) {
      throw const FormatException('Tasks page scope or cursor mismatch.');
    }
    var previous = after;
    for (final entry in groups) {
      final group = entry.group;
      assignmentSegment(group.id);
      if (previous != null && group.id.compareTo(previous) <= 0) {
        throw const FormatException('Tasks index order mismatch.');
      }
      previous = group.id;
      final selected = taskWeeks(group, binding.options);
      if (entry.weeks.length != selected.length) {
        throw const FormatException('Tasks selected weeks mismatch.');
      }
      for (var i = 0; i < selected.length; i++) {
        final week = entry.weeks[i];
        if (week.weekNumber != selected[i] ||
            week.assignments.length > 48 ||
            week.assignments.map((a) => a.unit.key).toSet().length !=
                week.assignments.length ||
            week.assignments.any((a) =>
                a.groupId != group.id ||
                a.userId != uid ||
                a.weekNumber != week.weekNumber) ||
            week.summary != taskSummary(week.assignments)) {
          throw const FormatException(
              'Tasks assignment or summary scope mismatch.');
        }
      }
    }
  }
}

String taskReaderLocation(FirebaseAssignment task) =>
    '/groups/${Uri.encodeComponent(task.groupId)}/assignments/read/'
    '${Uri.encodeComponent(task.userId)}/${Uri.encodeComponent('${task.weekNumber}')}/'
    '${Uri.encodeComponent(task.unit.key)}';
