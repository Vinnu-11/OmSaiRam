import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

const reminderPreferencesDisclosure =
  'Saving preferences does not enable notifications. Android delivery requires separate device opt-in.';

/// Immutable, exact five-field preferences. No delivery or identity fields.
class FirebaseReminderPreferences {
  final bool readingReminderEnabled, dailyVerseEnabled;
  final int reminderHour, reminderMinute;
  final String timezone;
  const FirebaseReminderPreferences._(this.readingReminderEnabled,
      this.dailyVerseEnabled, this.reminderHour, this.reminderMinute, this.timezone);
  static const defaults = FirebaseReminderPreferences._(false, false, 9, 0, 'Asia/Kolkata');
  static const fields = {'readingReminderEnabled', 'dailyVerseEnabled',
    'reminderHour', 'reminderMinute', 'timezone'};

  factory FirebaseReminderPreferences.parse(Map<String, dynamic>? raw) {
    final data = exactData(raw, fields);
    final reading = data['readingReminderEnabled'], verse = data['dailyVerseEnabled'];
    final hour = data['reminderHour'], minute = data['reminderMinute'];
    if (reading is! bool || verse is! bool || hour is! int || minute is! int ||
        hour < 0 || hour > 23 || minute < 0 || minute > 59 || data['timezone'] != 'Asia/Kolkata') {
      throw const FormatException('Invalid reminder preferences. India timezone and integer time required.');
    }
    return FirebaseReminderPreferences._(reading, verse, hour, minute, 'Asia/Kolkata');
  }
  Map<String, dynamic> toData() => {
    'readingReminderEnabled': readingReminderEnabled, 'dailyVerseEnabled': dailyVerseEnabled,
    'reminderHour': reminderHour, 'reminderMinute': reminderMinute, 'timezone': timezone,
  };
  FirebaseReminderPreferences copyWith({bool? readingReminderEnabled,
      bool? dailyVerseEnabled, int? reminderHour, int? reminderMinute}) =>
    FirebaseReminderPreferences.parse({...toData(),
      'readingReminderEnabled': readingReminderEnabled ?? this.readingReminderEnabled,
      'dailyVerseEnabled': dailyVerseEnabled ?? this.dailyVerseEnabled,
      'reminderHour': reminderHour ?? this.reminderHour,
      'reminderMinute': reminderMinute ?? this.reminderMinute});
  String get timeLabel => '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}';
}

class FirebaseReminderRecord {
  final String uid;
  final FirebaseReminderPreferences preferences;
  final Timestamp updatedAt;
  FirebaseReminderRecord._(this.uid, this.preferences, this.updatedAt);
  factory FirebaseReminderRecord.parse(String uid, Map<String, dynamic>? raw) {
    assignmentSegment(uid);
    final data = exactData(raw, {...FirebaseReminderPreferences.fields, 'updatedAt'});
    final timestamp = data['updatedAt'];
    if (timestamp is! Timestamp || timestamp.seconds < -62135596800 ||
        timestamp.seconds > 253402300799 || timestamp.nanoseconds < 0 ||
        timestamp.nanoseconds > 999999999) {
      throw const FormatException('Invalid server updatedAt Timestamp.');
    }
    return FirebaseReminderRecord._(uid, FirebaseReminderPreferences.parse({
      for (final field in FirebaseReminderPreferences.fields) field: data[field],
    }), timestamp); // Retain exact SDK seconds/nanoseconds, never DateTime.
  }
}