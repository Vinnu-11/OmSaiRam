// Om Sai Ram
// Group model — represents a reading group.

import 'package:equatable/equatable.dart';

/// Reading mode for a group.
enum ReadingMode {
  chapterWise, // Individual chapters assigned to members
  saptah, // 7-day weekly reading cycle
}

/// Represents a group of devotees reading together.
///
/// A group has a name, mode (chapter-wise or saptah),
/// an invite code for joining, and a list of members.
class Group extends Equatable {
  final String id;
  final String name;
  final String? description;
  final ReadingMode mode;
  final String inviteCode;
  final String createdBy;
  final int memberCount;
  final DateTime createdAt;

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.mode,
    required this.inviteCode,
    required this.createdBy,
    required this.memberCount,
    required this.createdAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      mode: json['mode'] == 'saptah' ? ReadingMode.saptah : ReadingMode.chapterWise,
      inviteCode: json['invite_code'] as String,
      createdBy: json['created_by'] as String,
      memberCount: json['member_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'mode': mode == ReadingMode.saptah ? 'saptah' : 'chapter_wise',
      'invite_code': inviteCode,
      'created_by': createdBy,
      'member_count': memberCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, name, mode, inviteCode, createdBy];
}

/// Represents a member within a group.
class GroupMember extends Equatable {
  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String role; // 'admin' or 'member'
  final DateTime joinedAt;

  const GroupMember({
    required this.id,
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';

  @override
  List<Object?> get props => [id, userId, name, role];
}
