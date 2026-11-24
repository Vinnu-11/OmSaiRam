import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase_groups/data/firebase_group_models.dart';

enum FirebaseDepartureReason { left, removed }

class FirebaseDeparture {
  final String groupId, uid, removedBy;
  final FirebaseDepartureReason reason;
  final Timestamp removedAt, changedAt;
  final int revision;
  final bool restored;
  const FirebaseDeparture._(this.groupId, this.uid, this.removedBy, this.reason,
      this.removedAt, this.changedAt, this.revision, this.restored);
  factory FirebaseDeparture.parse(String groupId, String uid, Map<String, dynamic>? raw) {
    final data = exactData(raw, {'userId', 'removedBy', 'removedAt', 'reason'}, {'restored', 'revision', 'changedBy', 'changedAt'});
    documentId(groupId); documentId(uid);
    if (data['userId'] != uid) throw const FormatException('Departure UID mismatch.');
    final reason = switch (data['reason']) {
      'left' => FirebaseDepartureReason.left, 'removed' => FirebaseDepartureReason.removed,
      _ => throw const FormatException('Invalid departure reason.'),
    };
    final removedBy = documentId(textField(data, 'removedBy', 1500));
    dateField(data, 'removedAt');
    const fields = {'restored', 'revision', 'changedBy', 'changedAt'};
    final versioned = data.keys.any(fields.contains);
    if (versioned) {
      if (!data.keys.toSet().containsAll(fields) || data['restored'] is! bool) throw const FormatException('Invalid membership lifecycle.');
      intField(data, 'revision', 1, 2147483647);
      documentId(textField(data, 'changedBy', 1500)); dateField(data, 'changedAt');
    }
    return FirebaseDeparture._(groupId, uid, removedBy, reason, data['removedAt'] as Timestamp,
      (versioned ? data['changedAt'] : data['removedAt']) as Timestamp,
      versioned ? data['revision'] as int : 0, versioned ? data['restored'] as bool : false);
  }
}

/// UI hints and transaction prewrite checks share the same strict role policy.
/// These are never a replacement for the coordinated Firestore rules.
bool canLeaveGroup(FirebaseGroup group, FirebaseMembership actor) =>
  !group.archived && group.ownerUid != actor.uid &&
    (actor.role == FirebaseGroupRole.member || actor.role == FirebaseGroupRole.groupLead);

bool canRemoveMember(FirebaseGroup group, FirebaseMembership actor,
    FirebaseMembership target) =>
    !group.archived && target.uid != group.ownerUid && target.uid != actor.uid &&
    (actor.role == FirebaseGroupRole.admin ||
      (actor.role == FirebaseGroupRole.groupLead && target.role == FirebaseGroupRole.member));

void requireDeparture(FirebaseGroup group, FirebaseMembership actor,
    FirebaseMembership target, FirebaseDepartureReason reason) {
  final allowed = reason == FirebaseDepartureReason.left
      ? actor.uid == target.uid && canLeaveGroup(group, actor)
      : canRemoveMember(group, actor, target);
  if (!allowed) {
    throw const FormatException('Current membership roles do not permit this departure. The owner cannot depart.');
  }
}

const membershipRetentionWarning =
    'Assignments, reading status, chat and highlights remain for remaining members. '
    'Only an admin can explicitly restore this UID as a fresh ordinary member. Previous work remains history-only. '
    'This is not account deletion or privacy erasure. Another client loses access on its next server read; '
    'previously downloaded data is not erased.';