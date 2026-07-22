// Om Sai Ram
// GroupNotificationSchedule — data model matching the backend schema.

class GroupNotificationSchedule {
  final String id;
  final String groupId;

  /// Days from the assignment's Monday (scheduled_date) when the first
  /// 'start reading' reminder fires.  0 = Monday, 6 = Sunday.
  final int initialReminderDayOffset;
  final int initialReminderHour;
  final int initialReminderMinute;

  /// Days from the assignment's Monday when the reading deadline falls.
  final int deadlineDayOffset;
  final int deadlineHour;
  final int deadlineMinute;

  /// Whether escalating reminders are enabled as the deadline approaches.
  final bool escalationEnabled;

  final String createdBy;
  final DateTime updatedAt;

  const GroupNotificationSchedule({
    required this.id,
    required this.groupId,
    required this.initialReminderDayOffset,
    required this.initialReminderHour,
    required this.initialReminderMinute,
    required this.deadlineDayOffset,
    required this.deadlineHour,
    required this.deadlineMinute,
    required this.escalationEnabled,
    required this.createdBy,
    required this.updatedAt,
  });

  factory GroupNotificationSchedule.fromJson(Map<String, dynamic> json) {
    return GroupNotificationSchedule(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      initialReminderDayOffset: json['initial_reminder_day_offset'] as int,
      initialReminderHour: json['initial_reminder_hour'] as int,
      initialReminderMinute: json['initial_reminder_minute'] as int,
      deadlineDayOffset: json['deadline_day_offset'] as int,
      deadlineHour: json['deadline_hour'] as int,
      deadlineMinute: json['deadline_minute'] as int,
      escalationEnabled: json['escalation_enabled'] as bool,
      createdBy: json['created_by'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'initial_reminder_day_offset': initialReminderDayOffset,
        'initial_reminder_hour': initialReminderHour,
        'initial_reminder_minute': initialReminderMinute,
        'deadline_day_offset': deadlineDayOffset,
        'deadline_hour': deadlineHour,
        'deadline_minute': deadlineMinute,
        'escalation_enabled': escalationEnabled,
      };

  /// Compute the absolute reminder DateTime for a given assignment week.
  DateTime reminderDateTime(DateTime scheduledDate) {
    final base = _mondayOf(scheduledDate);
    return base
        .add(Duration(days: initialReminderDayOffset))
        .copyWith(hour: initialReminderHour, minute: initialReminderMinute, second: 0, millisecond: 0);
  }

  /// Compute the absolute deadline DateTime for a given assignment week.
  DateTime deadlineDateTime(DateTime scheduledDate) {
    final base = _mondayOf(scheduledDate);
    return base
        .add(Duration(days: deadlineDayOffset))
        .copyWith(hour: deadlineHour, minute: deadlineMinute, second: 0, millisecond: 0);
  }

  /// Return the Monday of the week containing [date].
  DateTime _mondayOf(DateTime date) {
    final d = date.toLocal();
    return DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
  }

  GroupNotificationSchedule copyWith({
    int? initialReminderDayOffset,
    int? initialReminderHour,
    int? initialReminderMinute,
    int? deadlineDayOffset,
    int? deadlineHour,
    int? deadlineMinute,
    bool? escalationEnabled,
  }) {
    return GroupNotificationSchedule(
      id: id,
      groupId: groupId,
      initialReminderDayOffset: initialReminderDayOffset ?? this.initialReminderDayOffset,
      initialReminderHour: initialReminderHour ?? this.initialReminderHour,
      initialReminderMinute: initialReminderMinute ?? this.initialReminderMinute,
      deadlineDayOffset: deadlineDayOffset ?? this.deadlineDayOffset,
      deadlineHour: deadlineHour ?? this.deadlineHour,
      deadlineMinute: deadlineMinute ?? this.deadlineMinute,
      escalationEnabled: escalationEnabled ?? this.escalationEnabled,
      createdBy: createdBy,
      updatedAt: updatedAt,
    );
  }
}
