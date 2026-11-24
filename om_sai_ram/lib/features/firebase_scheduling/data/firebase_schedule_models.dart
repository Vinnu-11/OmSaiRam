import 'dart:convert';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

typedef FirebaseScheduleBinding = ({String uid, String groupId});

/// Firestore document-ID order is UTF8, not Dart UTF16 order.
int scheduleUidCompare(String a, String b) {
  final left = utf8.encode(a), right = utf8.encode(b);
  for (var i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return left.length.compareTo(right.length);
}

void validateScheduleBinding(FirebaseScheduleBinding binding) {
  assignmentSegment(binding.uid);
  assignmentSegment(binding.groupId);
}

/// Exact four-field scheduling snapshot; unrelated group edits do not stale it.
class FirebaseScheduleSettings {
  final String mode;
  final int chaptersPerWeek, startChapter, currentWeek;
  const FirebaseScheduleSettings({required this.mode, required this.chaptersPerWeek,
    required this.startChapter, required this.currentWeek});
  factory FirebaseScheduleSettings.fromGroup(FirebaseGroup group) => FirebaseScheduleSettings(
    mode: group.mode, chaptersPerWeek: group.chaptersPerWeek,
    startChapter: group.startChapter, currentWeek: group.currentWeek);
  void validate() {
    // Saptah is a group label only: both modes share the weekly scheduling.
    if (mode != 'chapter_wise' && mode != 'saptah') throw const FormatException('Unsupported group mode.');
    if (chaptersPerWeek < 1 || chaptersPerWeek > 48) {
      throw const FormatException('Units per member per week must be 1–48.');
    }
    FirebaseChapterUnit.fromChapter(startChapter);
    assignmentWeek(currentWeek);
  }
  @override
  bool operator ==(Object other) => other is FirebaseScheduleSettings &&
    mode == other.mode && chaptersPerWeek == other.chaptersPerWeek &&
    startChapter == other.startChapter && currentWeek == other.currentWeek;
  @override
  int get hashCode => Object.hash(mode, chaptersPerWeek, startChapter, currentWeek);
}

class FirebaseSchedulePlan {
  static const modes = ['independent', 'rotating_window', 'dense_window', 'synchronized'];
  static const remainders = ['manual', 'truncate', 'cycle', 'extend_last', 'round_robin'];
  /// Independent mode only: add the last few units to the final planned week.
  static const finishingRemainders = ['extend_last', 'round_robin'];
  final List<String> memberUids;
  final int weeksAhead;
  final String scheduleMode, remainderMode;
  final int? startChapter;
  final DateTime? firstWeekDate;
  FirebaseSchedulePlan({required Iterable<String> memberUids, required this.weeksAhead,
    required this.scheduleMode, required this.remainderMode, this.startChapter,
    DateTime? firstWeekDate}) : memberUids = List.unmodifiable(memberUids),
    firstWeekDate = firstWeekDate == null ? null : _instant(firstWeekDate);
  static DateTime _instant(DateTime date) {
    if (!date.isUtc) throw const FormatException('Use an explicit UTC instant or null.');
    // JavaScript Date precision; no device clock or local calendar conversion.
    return DateTime.fromMillisecondsSinceEpoch(date.millisecondsSinceEpoch, isUtc: true);
  }
}

class FirebaseScheduledUnit {
  final String userId;
  final int weekNumber;
  final FirebaseChapterUnit unit;
  final DateTime? scheduledDate;
  const FirebaseScheduledUnit(this.userId, this.weekNumber, this.unit, this.scheduledDate);
  String path(String groupId) => 'groups/$groupId/readingWeeks/$weekNumber/members/$userId/assignments/${unit.key}';
}

typedef FirebaseUnfilledSlot = ({String userId, int weekNumber, int slot, int unitPosition});

class FirebaseSchedulePreview {
  final FirebaseScheduleSettings settings;
  final FirebaseSchedulePlan plan;
  final List<FirebaseScheduledUnit> assignments;
  final List<FirebaseUnfilledSlot> unfilled;
  final int requestedCount;
  /// Units added to the final week by extend_last/round_robin to finish the book.
  final int extraCount;
  FirebaseSchedulePreview._(this.settings, this.plan, Iterable<FirebaseScheduledUnit> assignments,
    Iterable<FirebaseUnfilledSlot> unfilled, this.requestedCount, this.extraCount)
    : assignments = List.unmodifiable(assignments), unfilled = List.unmodifiable(unfilled);
  int get unfilledCount => unfilled.length;
  bool get reviewRequired => plan.remainderMode == 'manual' && unfilled.isNotEmpty;
  String? get commitBlock {
    if (assignments.isEmpty || assignments.length > 48 ||
        assignments.map((row) => row.userId).toSet().length > 12) {
      return 'Atomic commit requires 1–48 assignment writes and at most 12 target UIDs. Create separate explicit reviewed plans; no automatic chunks or skips.';
    }
    return null;
  }
}

/// Formula parity with firebase/src/scheduling.mjs; order is explicitly supplied.
FirebaseSchedulePreview previewFirebaseSchedule(FirebaseScheduleSettings settings, FirebaseSchedulePlan plan) {
  settings.validate();
  if (!FirebaseSchedulePlan.modes.contains(plan.scheduleMode) ||
      !FirebaseSchedulePlan.remainders.contains(plan.remainderMode)) {
    throw const FormatException('Unsupported schedule or remainder mode.');
  }
  final finishing = FirebaseSchedulePlan.finishingRemainders.contains(plan.remainderMode);
  if (finishing && plan.scheduleMode != 'independent') {
    throw const FormatException('extend_last and round_robin require the independent schedule mode.');
  }
  if (plan.memberUids.isEmpty || plan.memberUids.length > 50) {
    throw const FormatException('Select 1–50 ordered member UIDs.');
  }
  for (final uid in plan.memberUids) { assignmentSegment(uid); }
  if (plan.memberUids.toSet().length != plan.memberUids.length) {
    throw const FormatException('Duplicate member UID.');
  }
  if (plan.weeksAhead < 1 || plan.weeksAhead > 12 ||
      settings.currentWeek + plan.weeksAhead - 1 > 10000) {
    throw const FormatException('Weeks ahead includes current: 1–12, ending at most at week 10000.');
  }
  final requested = plan.memberUids.length * plan.weeksAhead * settings.chaptersPerWeek;
  if (requested > 4096) throw const FormatException('Preview exceeds 4096 requested slots.');
  final start = FirebaseChapterUnit.fromChapter(plan.startChapter ?? settings.startChapter);
  final base = FirebaseChapterUnit.all.indexWhere((unit) => unit.key == start.key);
  final date = plan.firstWeekDate;
  if (date != null) {
    final end = date.add(Duration(days: (plan.weeksAhead - 1) * 7));
    if (date.year < 1 || date.year > 9999 || end.year < 1 || end.year > 9999) {
      throw const FormatException('Dates must fit the Firestore timestamp range.');
    }
  }
  final assignments = <FirebaseScheduledUnit>[];
  final unfilled = <FirebaseUnfilledSlot>[];
  final width = settings.chaptersPerWeek;
  for (var k = 0; k < plan.weeksAhead; k++) {
    final week = settings.currentWeek + k;
    for (var i = 0; i < plan.memberUids.length; i++) {
      final offset = switch (plan.scheduleMode) {
        'independent' => (k * plan.memberUids.length + i) * width,
        'rotating_window' => (k + i) * width,
        'dense_window' => k * width + i,
        _ => k * width,
      };
      for (var slot = 0; slot < width; slot++) {
        final position = base + offset + slot;
        if (position >= 48 && plan.remainderMode != 'cycle') {
          unfilled.add((userId: plan.memberUids[i], weekNumber: week, slot: slot, unitPosition: position + 1));
        } else {
          assignments.add(FirebaseScheduledUnit(plan.memberUids[i], week,
            FirebaseChapterUnit.all[position % 48], date?.add(Duration(days: k * 7))));
        }
      }
    }
  }
  // Independent plans consume contiguous units, so the leftover is one number.
  final extras = 48 - base - requested;
  final finishes = finishing && extras > 0 && extras < plan.memberUids.length * width;
  for (var extra = 0; finishes && extra < extras; extra++) {
    assignments.add(FirebaseScheduledUnit(
      plan.memberUids[plan.remainderMode == 'extend_last' ? plan.memberUids.length - 1 : extra % plan.memberUids.length],
      settings.currentWeek + plan.weeksAhead - 1, FirebaseChapterUnit.all[base + requested + extra],
      date?.add(Duration(days: (plan.weeksAhead - 1) * 7))));
  }
  return FirebaseSchedulePreview._(settings, plan, assignments, unfilled, requested, finishes ? extras : 0);
}

class FirebaseScheduleHead {
  final FirebaseGroup group;
  final FirebaseMembership actor;
  final FirebasePage<FirebaseMembership> members;
  const FirebaseScheduleHead(this.group, this.actor, this.members);
  FirebaseScheduleSettings get settings => FirebaseScheduleSettings.fromGroup(group);
}

/// Positions are zero-based in the explicitly selected subset, not the roster.
class FirebaseScheduleHint {
  final int position, chapterStart;
  const FirebaseScheduleHint({required this.position, required this.chapterStart});
  factory FirebaseScheduleHint.parse(Map<String, Object?> value) {
    if (value.length != 2 || value['position'] is! int || value['chapterStart'] is! int) {
      throw const FormatException('Hints require exactly integer position and chapterStart fields.');
    }
    return FirebaseScheduleHint(position: value['position'] as int, chapterStart: value['chapterStart'] as int);
  }
}

class FirebaseScheduleSuggestion {
  final String detectedMode;
  final int detectedStep;
  final FirebaseSchedulePlan plan;
  final FirebaseSchedulePreview preview;
  const FirebaseScheduleSuggestion._(this.detectedMode, this.detectedStep, this.plan, this.preview);
}

/// Exact suggestSchedule reference parity: validate the bounded preview FIRST.
/// One week's hints cannot distinguish independent from rotating_window.
FirebaseScheduleSuggestion suggestFirebaseSchedule(FirebaseScheduleSettings settings,
    FirebaseSchedulePlan plan, Iterable<FirebaseScheduleHint> hints) {
  previewFirebaseSchedule(settings, plan);
  final ordered = List<FirebaseScheduleHint>.of(hints);
  if (ordered.length < 2 || ordered.length > plan.memberUids.length) {
    throw const FormatException('Provide 2..member-count hints.');
  }
  final indices = <int, int>{};
  for (final hint in ordered) {
    if (hint.position < 0 || hint.position >= plan.memberUids.length) {
      throw const FormatException('Hint position is outside the selected subset.');
    }
    final unit = FirebaseChapterUnit.fromChapter(hint.chapterStart);
    if (indices.containsKey(hint.position)) throw const FormatException('Duplicate hint position.');
    indices[hint.position] = FirebaseChapterUnit.all.indexWhere((entry) => entry.key == unit.key);
  }
  ordered.sort((a, b) => a.position.compareTo(b.position));
  final gap = ordered[1].position - ordered[0].position;
  final difference = indices[ordered[1].position]! - indices[ordered[0].position]!;
  final step = difference ~/ gap;
  final base = indices[ordered[0].position]! - ordered[0].position * step;
  if (difference % gap != 0 || step < 0 || base < 0 || base >= 48 ||
      ordered.any((hint) => indices[hint.position] != base + hint.position * step)) {
    throw const FormatException('Hints must define a consistent nonnegative integral unit pattern.');
  }
  final mode = step == 0 ? 'synchronized'
    : step == settings.chaptersPerWeek ? 'rotating_window' : step == 1 ? 'dense_window' : null;
  if (mode == null) throw const FormatException('Custom hint steps are not supported.');
  final suggested = FirebaseSchedulePlan(memberUids: plan.memberUids, weeksAhead: plan.weeksAhead,
    scheduleMode: mode, remainderMode: plan.remainderMode,
    startChapter: FirebaseChapterUnit.all[base].start, firstWeekDate: plan.firstWeekDate);
  return FirebaseScheduleSuggestion._(mode, step, suggested, previewFirebaseSchedule(settings, suggested));
}

void requireScheduler(FirebaseMembership actor) {
  if (actor.role != FirebaseGroupRole.admin && actor.role != FirebaseGroupRole.groupLead) {
    throw const FormatException('Only current admins and group leads can schedule.');
  }
}