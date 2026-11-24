import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

const groupReminderDisclosure =
  'Saving a schedule does not enable notifications. Android delivery requires separate device opt-in.';
const groupReminderMaximumRevision = 2147483647;

class FirebaseGroupReminderDraft {
  final int initialDay,
      initialHour,
      initialMinute,
      deadlineDay,
      deadlineHour,
      deadlineMinute;
  final bool escalationEnabled;
  const FirebaseGroupReminderDraft._(
      this.initialDay,
      this.initialHour,
      this.initialMinute,
      this.deadlineDay,
      this.deadlineHour,
      this.deadlineMinute,
      this.escalationEnabled);
  static const defaults = FirebaseGroupReminderDraft._(0, 9, 0, 6, 22, 0, true);
  static const fields = {
    'initialDay',
    'initialHour',
    'initialMinute',
    'deadlineDay',
    'deadlineHour',
    'deadlineMinute',
    'escalationEnabled',
    'timezone'
  };
  static const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  factory FirebaseGroupReminderDraft.parse(Map<String, dynamic>? raw) {
    final data = exactData(raw, fields);
    int bounded(String field, int maximum) {
      final value = data[field];
      if (value is! int || value < 0 || value > maximum) {
        throw const FormatException(
            'Schedule days and times must be bounded integers.');
      }
      return value;
    }

    final startDay = bounded('initialDay', 6),
        startHour = bounded('initialHour', 23),
        startMinute = bounded('initialMinute', 59);
    final endDay = bounded('deadlineDay', 6),
        endHour = bounded('deadlineHour', 23),
        endMinute = bounded('deadlineMinute', 59);
    if (data['escalationEnabled'] is! bool ||
        data['timezone'] != 'Asia/Kolkata' ||
        endDay * 1440 + endHour * 60 + endMinute <=
            startDay * 1440 + startHour * 60 + startMinute) {
      throw const FormatException(
          'Use Asia/Kolkata and a deadline strictly after the initial reminder.');
    }
    return FirebaseGroupReminderDraft._(startDay, startHour, startMinute,
        endDay, endHour, endMinute, data['escalationEnabled'] as bool);
  }
  Map<String, dynamic> toData() => {
        'initialDay': initialDay,
        'initialHour': initialHour,
        'initialMinute': initialMinute,
        'deadlineDay': deadlineDay,
        'deadlineHour': deadlineHour,
        'deadlineMinute': deadlineMinute,
        'escalationEnabled': escalationEnabled,
        'timezone': 'Asia/Kolkata'
      };
  FirebaseGroupReminderDraft copyWith(
          {int? initialDay,
          int? initialHour,
          int? initialMinute,
          int? deadlineDay,
          int? deadlineHour,
          int? deadlineMinute,
          bool? escalationEnabled}) =>
      FirebaseGroupReminderDraft.parse({
        ...toData(),
        'initialDay': initialDay ?? this.initialDay,
        'initialHour': initialHour ?? this.initialHour,
        'initialMinute': initialMinute ?? this.initialMinute,
        'deadlineDay': deadlineDay ?? this.deadlineDay,
        'deadlineHour': deadlineHour ?? this.deadlineHour,
        'deadlineMinute': deadlineMinute ?? this.deadlineMinute,
        'escalationEnabled': escalationEnabled ?? this.escalationEnabled
      });
  String get initialLabel =>
      '${weekdays[initialDay]} ${_time(initialHour, initialMinute)}';
  String get deadlineLabel =>
      '${weekdays[deadlineDay]} ${_time(deadlineHour, deadlineMinute)}';
  static String _time(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class FirebaseGroupReminderRecord {
  final String groupId, createdBy, updatedBy;
  final int revision;
  final Timestamp createdAt, updatedAt;
  final FirebaseGroupReminderDraft schedule;
  FirebaseGroupReminderRecord._(this.groupId, this.createdBy, this.updatedBy,
      this.revision, this.createdAt, this.updatedAt, this.schedule);
  factory FirebaseGroupReminderRecord.parse(
      String groupId, Map<String, dynamic>? raw) {
    assignmentSegment(groupId);
    final data = exactData(raw, {
      ...FirebaseGroupReminderDraft.fields,
      'groupId',
      'revision',
      'createdBy',
      'updatedBy',
      'createdAt',
      'updatedAt'
    });
    final revision = data['revision'];
    if (data['groupId'] != groupId ||
        revision is! int ||
        revision < 1 ||
        revision > groupReminderMaximumRevision) {
      throw const FormatException('Invalid schedule scope or revision.');
    }
    Timestamp timestamp(String field) {
      final value = data[field];
      if (value is! Timestamp ||
          value.seconds < -62135596800 ||
          value.seconds > 253402300799 ||
          value.nanoseconds < 0 ||
          value.nanoseconds > 999999999) {
        throw const FormatException(
            'Confirmed server schedule timestamps required.');
      }
      return value;
    }

    final createdAt = timestamp('createdAt'),
        updatedAt = timestamp('updatedAt');
    if (updatedAt.compareTo(createdAt) < 0) {
      throw const FormatException('Invalid schedule audit order.');
    }
    return FirebaseGroupReminderRecord._(
        groupId,
        assignmentSegment(data['createdBy']),
        assignmentSegment(data['updatedBy']),
        revision,
        createdAt,
        updatedAt,
        FirebaseGroupReminderDraft.parse({
          for (final field in FirebaseGroupReminderDraft.fields)
            field: data[field]
        }));
  }
}

class FirebaseGroupReminderSnapshot {
  final String uid, groupId;
  final FirebaseGroupRole role;
  final bool archived;
  final FirebaseGroupReminderRecord? record;
  FirebaseGroupReminderSnapshot(
      this.uid, this.groupId, this.role, this.record, {this.archived = false}) {
    assignmentSegment(uid);
    assignmentSegment(groupId);
    if (record != null && record!.groupId != groupId) {
      throw const FormatException('Schedule scope mismatch.');
    }
  }
  bool get canEdit =>
      !archived && (role == FirebaseGroupRole.admin || role == FirebaseGroupRole.groupLead);
}
