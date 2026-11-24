import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

typedef FirebaseGroupAdminBinding = ({String uid, String groupId});

/// A server-confirmed version, kept as Timestamp (including nanoseconds).
/// Never reconstruct this optimistic concurrency token from FirebaseGroup dates.
class FirebaseGroupSettingsSnapshot {
  final FirebaseGroup group;
  final Timestamp updatedAt;
  const FirebaseGroupSettingsSnapshot._(this.group, this.updatedAt);
  factory FirebaseGroupSettingsSnapshot.parse(String id, Map<String, dynamic>? raw) {
    assignmentSegment(id);
    final group = FirebaseGroup.parse(id, raw);
    assignmentSegment(group.createdBy);
    return FirebaseGroupSettingsSnapshot._(group, raw!['updatedAt'] as Timestamp);
  }
}

class FirebaseGroupSettingsDraft {
  final String name, description;
  final int? chaptersPerWeek, startChapter;
  FirebaseGroupSettingsDraft(String name, String description,
      {this.chaptersPerWeek, this.startChapter})
      : name = name.trim(), description = description.trim() {
    if (this.name.isEmpty || this.name.length > 100 || this.description.length > 1000 ||
        (chaptersPerWeek == null) != (startChapter == null) ||
        (chaptersPerWeek != null && (chaptersPerWeek! < 1 || chaptersPerWeek! > 48)) ||
        (startChapter != null && (startChapter! < 1 || startChapter! > 53))) {
      throw const FormatException('Name: 1–100 characters; description: up to 1000; width: 1–48; start: 1–53.');
    }
  }
  /// Both group modes share weekly scheduling, so both need width and start.
  void requireMode(String mode) {
    if (chaptersPerWeek == null) {
      throw const FormatException('Group settings require width and start.');
    }
  }
  Map<String, dynamic> get changes => {
    'name': name, 'description': description,
    if (chaptersPerWeek != null) 'chaptersPerWeek': chaptersPerWeek,
    if (startChapter != null) 'startChapter': startChapter,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

void requireActualAdmin(FirebaseMembership actor) {
  if (actor.role != FirebaseGroupRole.admin) {
    throw const FormatException('Only an actual group admin can manage group settings and member roles.');
  }
}

void validateRoleChange(FirebaseGroupRole expected, FirebaseGroupRole next) {
  if (expected == FirebaseGroupRole.admin || next == FirebaseGroupRole.admin || expected == next) {
    throw const FormatException('Only member ↔ group lead changes are supported. No admin grants or ownership transfer.');
  }
}

bool canChangeMemberRole(FirebaseGroup group, FirebaseMembership actor, FirebaseMembership target) =>
  !group.archived && actor.role == FirebaseGroupRole.admin && target.uid != actor.uid &&
    target.uid != group.ownerUid && target.role != FirebaseGroupRole.admin;

void requireRoleChange(FirebaseGroup group, FirebaseMembership actor,
    FirebaseMembership target, FirebaseGroupRole expected, FirebaseGroupRole next) {
  validateRoleChange(expected, next);
  requireActualAdmin(actor);
  if (!canChangeMemberRole(group, actor, target)) {
    throw const FormatException('Owner, self and admin memberships are protected.');
  }
  if (target.role != expected) {
    throw const FormatException('Member role changed. Refresh before confirming a new action.');
  }
}