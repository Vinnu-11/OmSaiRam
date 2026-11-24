import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_group_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_planner.dart';
import 'firebase_assignments_test.dart' as fixtures;

void main() {
  tz_data.initializeTimeZones();
  final india = tz.getLocation('Asia/Kolkata');
  final monday = DateTime.utc(2026, 10, 18, 18, 30);
  final before = monday.subtract(const Duration(days: 1));
  final preferences = FirebaseReminderPreferences.defaults
      .copyWith(readingReminderEnabled: true);
  FirebaseAssignment assignment(
      {int chapter = 16,
      FirebaseAssignmentsScope scope = fixtures.own,
      FirebaseReadingStatus status = FirebaseReadingStatus.notStarted,
      bool dated = true,
      DateTime? date}) {
    return FirebaseAssignment.parse(
        scope, FirebaseChapterUnit.fromChapter(chapter).key, {
      ...fixtures.assignmentData(
          scope: scope, chapter: chapter, status: status),
      'scheduledDate': dated
          ? Timestamp.fromDate(date ?? monday.add(const Duration(hours: 12)))
          : null
    });
  }

  FirebaseReminderWeek week(
          {List<FirebaseAssignment>? assignments,
          DateTime? anchor,
          bool confirmed = true,
          FirebaseGroupReminderDraft? schedule}) =>
      FirebaseReminderWeek(
          groupId: 'g',
          weekNumber: 1,
          confirmedMondayUtc: confirmed ? anchor ?? monday : null,
          schedule: schedule ?? FirebaseGroupReminderDraft.defaults,
          assignments: assignments ?? [assignment()]);
  FirebaseReminderPlan plan(
          {List<FirebaseReminderWeek>? weeks,
          FirebaseReminderPreferences? prefs,
          DateTime? now}) =>
      planFirebaseReminders(
          uid: 'a',
          preferences: prefs ?? preferences,
          weeks: weeks ?? [week()],
          nowUtc: now ?? before,
          location: india);

  test(
      'confirmed India Monday generates precise initial and six future escalation UTC instants',
      () {
    final result = plan();
    expect(result.items.length, 7);
    expect(result.items.first.fireAtUtc, DateTime.utc(2026, 10, 19, 3, 30));
    expect(result.items.last.fireAtUtc, DateTime.utc(2026, 10, 25, 14, 30));
    expect(result.items.first.body, 'Chapter 16-17');
    expect(result.items.every((item) => item.uid == 'a'), true);
    expect(
        result.items
            .every((item) => item.id >= 0x40000000 && item.id <= 0x7fffffff),
        true);
    expect(() => result.items.clear(), throwsUnsupportedError);
  });
  test(
      'missing anchor, undated/completed/outside-week assignments are skipped, never guessed',
      () {
    expect(plan(weeks: [week(confirmed: false)]).items, isEmpty);
    final result = plan(weeks: [
      week(assignments: [
        assignment(chapter: 1, dated: false),
        assignment(chapter: 2, status: FirebaseReadingStatus.completed),
        assignment(
            chapter: 3, date: monday.subtract(const Duration(seconds: 1))),
        assignment(chapter: 4, date: monday.add(const Duration(days: 7)))
      ])
    ]);
    expect(result.items, isEmpty);
    expect(result.skippedAssignments, 4);
    final absent = FirebaseReminderWeek(
        groupId: 'g',
        weekNumber: 1,
        confirmedMondayUtc: monday,
        schedule: null,
        assignments: [assignment()]);
    expect(plan(weeks: [absent]).items, isEmpty);
  });
  test('defaults off, escalation off, past/equal instants never schedule', () {
    expect(plan(prefs: FirebaseReminderPreferences.defaults).items, isEmpty);
    expect(
        plan(weeks: [
          week(
              schedule: FirebaseGroupReminderDraft.defaults
                  .copyWith(escalationEnabled: false))
        ]).items.length,
        1);
    expect(plan(now: DateTime.utc(2026, 10, 26)).items, isEmpty);
    final initial = plan().items.first.fireAtUtc;
    expect(plan(now: initial).items.any((item) => item.fireAtUtc == initial),
        false);
  });
  test('escalations never precede the configured initial reminder', () {
    final result = plan(weeks: [
      week(
          schedule: FirebaseGroupReminderDraft.defaults.copyWith(initialDay: 6))
    ]);
    expect(result.items.length, 4);
    expect(result.items.first.fireAtUtc, DateTime.utc(2026, 10, 25, 3, 30));
  });
  test(
      'stable IDs do not depend on clock, input order, process hashCode or status',
      () {
    final first =
        week(assignments: [assignment(chapter: 1), assignment(chapter: 2)]);
    final second = week(assignments: [
      assignment(chapter: 2, status: FirebaseReadingStatus.inProgress),
      assignment(chapter: 1)
    ]);
    expect(plan(weeks: [first]).items.map((item) => item.id),
        plan(weeks: [second]).items.map((item) => item.id));
    expect(
        plan(now: before.add(const Duration(hours: 1)))
            .items
            .map((item) => item.id),
        plan().items.map((item) => item.id));
    expect(firebaseReminderNotificationId('a'),
        isNot(firebaseReminderNotificationId('b')));
    expect(firebaseReminderNotificationId('a'), 0x640c292c);
  });
  test('cross-account scope rejected even when preferences are off', () {
    expect(
        () => plan(weeks: [
              week(assignments: [assignment(scope: fixtures.other)])
            ], prefs: FirebaseReminderPreferences.defaults),
        throwsFormatException);
  });
  test('only exact confirmed UTC Monday midnight in India is accepted', () {
    for (final anchor in [
      DateTime.utc(2026, 10, 19),
      monday.add(const Duration(days: 1)),
      monday.add(const Duration(microseconds: 1)),
      monday.toLocal()
    ]) {
      expect(() => plan(weeks: [week(anchor: anchor)]), throwsFormatException);
    }
    expect(
        () => planFirebaseReminders(
            uid: 'a',
            preferences: preferences,
            weeks: [],
            nowUtc: before,
            location: tz.getLocation('UTC')),
        throwsFormatException);
  });
  test(
      'duplicate/mismatched scopes and units fail closed; input list is frozen',
      () {
    final assignments = [assignment()];
    final snapshot = week(assignments: assignments);
    assignments.clear();
    expect(snapshot.assignments.length, 1);
    expect(() => plan(weeks: [snapshot, snapshot]), throwsFormatException);
    expect(() => week(assignments: [assignment(), assignment()]),
        throwsFormatException);
    expect(
        () => FirebaseReminderWeek(
            groupId: 'other',
            weekNumber: 1,
            confirmedMondayUtc: monday,
            schedule: null,
            assignments: [assignment()]),
        throwsFormatException);
    expect(() => plan(weeks: List.generate(9, (_) => snapshot)),
        throwsFormatException);
  });
  test(
      'daily verse queues seven distinct India-calendar dates with rotating text',
      () {
    final enabled =
        FirebaseReminderPreferences.defaults.copyWith(dailyVerseEnabled: true);
    final first = plan(weeks: [], prefs: enabled, now: monday);
    final after = plan(
        weeks: [], prefs: enabled, now: monday.add(const Duration(hours: 12)));
    expect(first.items.length, 7);
    expect(after.items.length, 7);
    expect(first.items.first.fireAtUtc, DateTime.utc(2026, 10, 19, 3, 30));
    expect(after.items.first.fireAtUtc, DateTime.utc(2026, 10, 20, 3, 30));
    expect(first.items.map((item) => item.body).toSet().length, 7);
    expect(first.items.every((item) => item.groupId == null), true);
  });
  test(
      'queue is deterministic chronological and bounded, overflow explicitly counted',
      () {
    final result = plan(weeks: [
      week(assignments: [
        for (final unit in FirebaseChapterUnit.all)
          assignment(chapter: unit.start)
      ])
    ]);
    expect(result.items.length, firebaseReminderQueueLimit);
    expect(result.truncated, 48 * 7 - firebaseReminderQueueLimit);
    expect(result.items.map((item) => item.id).toSet().length,
        firebaseReminderQueueLimit);
    for (var index = 1; index < result.items.length; index++) {
      expect(
          result.items[index].fireAtUtc
              .isBefore(result.items[index - 1].fireAtUtc),
          false);
    }
  });
}
