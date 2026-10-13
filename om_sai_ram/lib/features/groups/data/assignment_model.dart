// Om Sai Ram
// Assignment and schedule models for group reading.

import 'package:equatable/equatable.dart';
import '../../../core/constants/chapter_units.dart';

/// Reading progress status for an assignment.
enum ReadingStatus { notStarted, inProgress, completed }

/// A chapter assignment for a member within a group.
class Assignment extends Equatable {
  final String id;
  final String groupId;
  final String userId;
  final String? userName;
  final int chapterId;
  final int? chapterNumber;
  final String? chapterLabel;
  final int? chapterEndNumber;
  final String? chapterTitle;
  final int weekNumber;
  final DateTime? scheduledDate;
  final ReadingStatus status;
  final DateTime assignedAt;

  const Assignment({
    required this.id,
    required this.groupId,
    required this.userId,
    this.userName,
    required this.chapterId,
    this.chapterNumber,
    this.chapterLabel,
    this.chapterEndNumber,
    this.chapterTitle,
    required this.weekNumber,
    this.scheduledDate,
    required this.status,
    required this.assignedAt,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String?,
      chapterId: json['chapter_id'] as int,
      chapterNumber: json['chapter_number'] as int?,
      chapterLabel: json['chapter_label'] as String?,
      chapterEndNumber: json['chapter_end_number'] as int?,
      chapterTitle: json['chapter_title'] as String?,
      weekNumber: json['week_number'] as int? ?? 1,
      scheduledDate: json['scheduled_date'] != null
          ? DateTime.parse(json['scheduled_date'] as String)
          : null,
      status: _parseStatus(json['status'] as String? ?? 'not_started'),
      assignedAt: DateTime.parse(json['assigned_at'] as String),
    );
  }

    String get displayChapterLabel =>
      chapterLabel ?? ChapterUnits.label(chapterNumber ?? chapterId);

    int get lastChapterNumber =>
      chapterEndNumber ?? ChapterUnits.end(chapterNumber ?? chapterId);

    static ReadingStatus _parseStatus(String s) {
    switch (s) {
      case 'in_progress':
        return ReadingStatus.inProgress;
      case 'completed':
        return ReadingStatus.completed;
      default:
        return ReadingStatus.notStarted;
    }
  }

  @override
  List<Object?> get props => [id, groupId, userId, chapterId, weekNumber];
}
