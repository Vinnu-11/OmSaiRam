import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import 'firebase_group_reminder_models.dart';
import 'firebase_reminder_models.dart';

const firebaseReminderQueueLimit = 64;
const firebaseReminderVerses = [
  'Why do you fear when I am here?',
  'Have faith and patience.',
  'Before we begin any task, we must first remember Sai Baba.',
  'Wherever my devotees sing my praises, I am there.',
  'Look at Me, I will look at you.',
  'My treasury is full and I can give everyone what they want.',
  'Do not be idle. Work, utter God\'s name and read the scriptures.',
];

class FirebaseReminderWeek {
  final String groupId;
  final int weekNumber;
  final DateTime? confirmedMondayUtc;
  final FirebaseGroupReminderDraft? schedule;
  final List<FirebaseAssignment> assignments;
  FirebaseReminderWeek(
      {required this.groupId,
      required this.weekNumber,
      required this.confirmedMondayUtc,
      required this.schedule,
      required Iterable<FirebaseAssignment> assignments})
      : assignments = List.unmodifiable(assignments) {
    assignmentSegment(groupId);
    assignmentWeek(weekNumber);
    if (this.assignments.length > 48 ||
        this.assignments.any((assignment) =>
            assignment.groupId != groupId ||
            assignment.weekNumber != weekNumber) ||
        this
                .assignments
                .map((assignment) => assignment.unit.key)
                .toSet()
                .length !=
            this.assignments.length) {
      throw const FormatException(
          'One bounded canonical assignment set per group/week required.');
    }
  }
}

class FirebaseReminderItem {
  final int id;
  final String key, uid, title, body;
  final DateTime fireAtUtc;
  final String? groupId, unitKey;
  final int? weekNumber;
  const FirebaseReminderItem._(this.id, this.key, this.uid, this.fireAtUtc,
      this.title, this.body, this.groupId, this.weekNumber, this.unitKey);
}

class FirebaseReminderPlan {
  final List<FirebaseReminderItem> items;
  final int skippedAssignments, truncated;
  FirebaseReminderPlan._(Iterable<FirebaseReminderItem> items,
      this.skippedAssignments, this.truncated)
      : items = List.unmodifiable(items);
}

int firebaseReminderNotificationId(String key) {
  var hash = 2166136261;
  for (final byte in utf8.encode(key)) {
    final mixed = hash ^ byte;
    hash = (mixed +
            (mixed << 1) +
            (mixed << 4) +
            (mixed << 7) +
            (mixed << 8) +
            (mixed << 24)) &
        0xffffffff;
  }
  return 0x40000000 | (hash & 0x3fffffff);
}

FirebaseReminderPlan planFirebaseReminders(
    {required String uid,
    required FirebaseReminderPreferences preferences,
    required Iterable<FirebaseReminderWeek> weeks,
    required DateTime nowUtc,
    required tz.Location location}) {
  assignmentSegment(uid);
  if (!nowUtc.isUtc || location.name != 'Asia/Kolkata') {
    throw const FormatException(
        'Explicit UTC clock and Asia/Kolkata location required.');
  }
  final input = List<FirebaseReminderWeek>.of(weeks);
  if (input.length > 8 ||
      input
              .map((week) => jsonEncode([week.groupId, week.weekNumber]))
              .toSet()
              .length !=
          input.length) {
    throw const FormatException(
        'At most eight distinct group/week scopes required.');
  }
  final candidates = <FirebaseReminderItem>[], ids = <int, String>{};
  var skipped = 0;
  void add(List<Object> scope, DateTime instant, String title, String body,
      {String? groupId, int? week, String? unit}) {
    if (!instant.isAfter(nowUtc)) return;
    final key = jsonEncode([uid, ...scope]),
        id = firebaseReminderNotificationId(jsonEncode([uid, ...scope]));
    if (ids.containsKey(id)) {
      throw const FormatException(
          'Notification ID collision; no partial plan may be scheduled.');
    }
    ids[id] = key;
    candidates.add(FirebaseReminderItem._(
        id, key, uid, instant.toUtc(), title, body, groupId, week, unit));
  }

  for (final week in input) {
    if (week.assignments.any((assignment) => assignment.userId != uid)) {
      throw const FormatException(
          'Only the current account\'s assignments may be scheduled.');
    }
    final anchor = week.confirmedMondayUtc, schedule = week.schedule;
    if (anchor != null) {
      final civil = tz.TZDateTime.from(anchor, location);
      if (!anchor.isUtc ||
          civil.weekday != DateTime.monday ||
          civil.hour != 0 ||
          civil.minute != 0 ||
          civil.second != 0 ||
          civil.millisecond != 0 ||
          civil.microsecond != 0) {
        throw const FormatException(
            'A confirmed Monday at midnight in Asia/Kolkata is required.');
      }
    }
    for (final assignment in week.assignments) {
      final date = assignment.scheduledDate;
      if (!preferences.readingReminderEnabled ||
          assignment.archived ||
          anchor == null ||
          schedule == null ||
          date == null ||
          date.isBefore(anchor) ||
          !date.isBefore(anchor.add(const Duration(days: 7))) ||
          assignment.status == FirebaseReadingStatus.completed) {
        skipped++;
        continue;
      }
      final monday = tz.TZDateTime.from(anchor, location);
      DateTime at(int day, int hour, int minute) => tz.TZDateTime(location,
              monday.year, monday.month, monday.day + day, hour, minute)
          .toUtc();
      final initial =
          at(schedule.initialDay, schedule.initialHour, schedule.initialMinute);
      final deadline = at(
          schedule.deadlineDay, schedule.deadlineHour, schedule.deadlineMinute);
      final label = 'Chapter ${assignment.unit.key}';
      void reading(String slot, DateTime instant, String title, String body) {
        if (instant.isBefore(initial)) return;
        add([week.groupId, week.weekNumber, assignment.unit.key, slot], instant,
            title, body,
            groupId: week.groupId,
            week: week.weekNumber,
            unit: assignment.unit.key);
      }

      reading('initial', initial, 'Om Sai Ram - Time to Read', label);
      if (schedule.escalationEnabled) {
        for (final hours in [72, 48, 24, 12, 6, 2]) {
          reading(
              'hours-$hours',
              deadline.subtract(Duration(hours: hours)),
              'Om Sai Ram - Reading Deadline',
              '$hours hours remaining: $label');
        }
      }
    }
  }
  if (preferences.dailyVerseEnabled) {
    final today = tz.TZDateTime.from(nowUtc, location);
    var verses = 0;
    for (var offset = 0; offset < 8 && verses < 7; offset++) {
      final instant = tz.TZDateTime(
          location,
          today.year,
          today.month,
          today.day + offset,
          preferences.reminderHour,
          preferences.reminderMinute);
      if (!instant.isAfter(nowUtc)) continue;
      final ordinal = DateTime.utc(instant.year, instant.month, instant.day)
          .difference(DateTime.utc(instant.year))
          .inDays;
      add(
          ['verse', instant.year, instant.month, instant.day],
          instant,
          'Om Sai Ram - Daily Verse',
          firebaseReminderVerses[ordinal % firebaseReminderVerses.length]);
      verses++;
    }
  }
  candidates.sort((first, second) {
    final order = first.fireAtUtc.compareTo(second.fireAtUtc);
    return order != 0 ? order : first.key.compareTo(second.key);
  });
  return FirebaseReminderPlan._(
      candidates.take(firebaseReminderQueueLimit),
      skipped,
      candidates.length > firebaseReminderQueueLimit
          ? candidates.length - firebaseReminderQueueLimit
          : 0);
}
