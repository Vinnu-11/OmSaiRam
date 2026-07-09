// Om Sai Ram
// Chat and highlight comment models for group discussions.

import 'package:equatable/equatable.dart';

/// A message posted to a group chat.
class GroupMessage extends Equatable {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final String content;
  final DateTime createdAt;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? '',
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, groupId, userId, createdAt];
}

/// A comment anchored to a highlighted verse or paragraph in a chapter.
class HighlightComment extends Equatable {
  final String id;
  final String groupId;
  final String userId;
  final String userName;
  final int chapterId;
  final int? chapterNumber;
  final String highlightedText;
  final int paragraphIndex;
  final String comment;
  final DateTime createdAt;

  const HighlightComment({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.chapterId,
    this.chapterNumber,
    required this.highlightedText,
    required this.paragraphIndex,
    required this.comment,
    required this.createdAt,
  });

  factory HighlightComment.fromJson(Map<String, dynamic> json) {
    return HighlightComment(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String? ?? '',
      chapterId: json['chapter_id'] as int,
      chapterNumber: json['chapter_number'] as int?,
      highlightedText: json['highlighted_text'] as String,
      paragraphIndex: json['paragraph_index'] as int? ?? 0,
      comment: json['comment'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, groupId, chapterId, paragraphIndex];
}
