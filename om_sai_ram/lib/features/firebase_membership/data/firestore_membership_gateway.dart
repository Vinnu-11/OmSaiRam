import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_membership_models.dart';

abstract class FirebaseMembershipGateway {
  Future<void> leave(String groupId);
  Future<void> remove(String groupId, String targetUid);
  Future<FirebaseDeparture> departure(String groupId, String targetUid);
  Future<void> restore(FirebaseDeparture baseline);
}

final firebaseMembershipGatewayProvider = Provider<FirebaseMembershipGateway>((ref) {
  throw StateError('Firebase membership bootstrap has not completed.');
});

/// Named-app Auth/Firestore only. Actor identity is captured from the SDK, not
/// supplied by a caller. A single transaction retains every historical record.
class FirestoreMembershipGateway implements FirebaseMembershipGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreMembershipGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);

  String _uid() => assignmentSegment(_auth.currentUser?.uid ?? '');
  void _same(String uid) {
    if (_auth.currentUser?.uid != uid) throw StateError('Firebase account changed.');
  }
  Future<T> _checked<T>(String uid, Future<T> Function() operation) async {
    _same(uid);
    try {
      final result = await operation();
      _same(uid);
      return result;
    } catch (_) { _same(uid); rethrow; }
  }
  void _confirmed(DocumentSnapshot<Map<String, dynamic>> snapshot, String path) {
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required.');
    }
    if (snapshot.reference.path != path || snapshot.id != path.split('/').last) {
      throw const FormatException('Server document path mismatch.');
    }
  }
  void _profile(Map<String, dynamic>? raw) {
    final data = exactData(raw, {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt');
    dateField(data, 'updatedAt');
  }
  @override
  Future<void> leave(String groupId) {
    assignmentSegment(groupId);
    final uid = _uid();
    return _depart(groupId, uid, uid, FirebaseDepartureReason.left);
  }
  @override
  Future<void> remove(String groupId, String targetUid) {
    assignmentSegment(groupId); assignmentSegment(targetUid);
    final uid = _uid();
    return _depart(groupId, uid, targetUid, FirebaseDepartureReason.removed);
  }
  Future<void> _depart(String groupId, String uid, String targetUid,
      FirebaseDepartureReason reason) async {
    final privateProfile = _db.collection('users').doc(uid);
    final ready = await _checked(uid, () => privateProfile.get(_server));
    _confirmed(ready, privateProfile.path);
    _profile(ready.data());
    _same(uid);
    final groupRef = _db.collection('groups').doc(groupId);
    final actorRef = groupRef.collection('members').doc(uid);
    final targetRef = groupRef.collection('members').doc(targetUid);
    final sharedRef = groupRef.collection('memberProfiles').doc(targetUid);
    final indexRef = _db.collection('users').doc(targetUid).collection('groups').doc(groupId);
    final departureRef = groupRef.collection('departures').doc(targetUid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid); // Also checked on EVERY SDK transaction retry.
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> doc) async {
        final snapshot = await _checked(uid, () => transaction.get(doc));
        _confirmed(snapshot, doc.path);
        return snapshot;
      }
      final groupDoc = await _checked(uid, () => read(groupRef));
      final actorDoc = await _checked(uid, () => read(actorRef));
      final targetDoc = uid == targetUid ? actorDoc : await _checked(uid, () => read(targetRef));
      final group = FirebaseGroup.parse(groupId, groupDoc.data());
      assignmentSegment(group.ownerUid);
      final actor = FirebaseMembership.parse(uid, actorDoc.data());
      final target = FirebaseMembership.parse(targetUid, targetDoc.data());
      requireDeparture(group, actor, target, reason);
      final shared = await _checked(uid, () => read(sharedRef));
      if (shared.exists) _profile(shared.data());
      final marker = await read(departureRef);
      final previous = marker.exists ? FirebaseDeparture.parse(groupId, targetUid, marker.data()) : null;
      if (previous != null && (!previous.restored || previous.revision >= 2147483647)) {
        throw const FormatException('Membership lifecycle changed. Refresh before departure.');
      }
      final history = previous == null ? null : departureRef.collection('versions').doc('${previous.revision}');
      if (history != null && (await read(history)).exists) throw const FormatException('Membership version already retained.');
      _same(uid);
      // All reads precede every write. Do NOT read another user's private index
      // or private profile. Rules require the index and a new marker/version,
      // otherwise the entire commit fails. No partial departure or history delete.
      if (history != null) transaction.set(history, marker.data()!);
      transaction.set(departureRef, {'userId': targetUid, 'removedBy': uid,
        'removedAt': FieldValue.serverTimestamp(), 'reason': reason.name,
        if (previous != null) ...{'restored': false, 'revision': previous.revision + 1,
          'changedBy': uid, 'changedAt': FieldValue.serverTimestamp()}});
      transaction.delete(targetRef);
      transaction.delete(indexRef);
      if (shared.exists) transaction.delete(sharedRef);
    }));
  }

  Future<void> _ready(String uid) async {
    final profile = _db.collection('users').doc(uid);
    final snapshot = await _checked(uid, () => profile.get(_server));
    _confirmed(snapshot, profile.path); _profile(snapshot.data());
  }
  void _admin(String groupId, String uid, Map<String, dynamic>? group, Map<String, dynamic>? actor) {
    FirebaseGroup.parse(groupId, group).requireWritable();
    if (FirebaseMembership.parse(uid, actor).role != FirebaseGroupRole.admin) {
      throw const FormatException('Only a current admin can restore membership.');
    }
  }
  @override
  Future<FirebaseDeparture> departure(String groupId, String targetUid) async {
    assignmentSegment(groupId); assignmentSegment(targetUid);
    final uid = _uid(); await _ready(uid);
    final root = _db.collection('groups').doc(groupId);
    Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> document) async {
      final snapshot = await _checked(uid, () => document.get(_server));
      _confirmed(snapshot, document.path); return snapshot;
    }
    final group = await read(root), actor = await read(root.collection('members').doc(uid));
    _admin(groupId, uid, group.data(), actor.data());
    if ((await read(root.collection('members').doc(targetUid))).exists) throw const FormatException('This UID is already a current member.');
    final marker = await read(root.collection('departures').doc(targetUid));
    final result = FirebaseDeparture.parse(groupId, targetUid, marker.data());
    if (result.restored || result.revision >= 2147483647) throw const FormatException('A departed membership with an available next version is required.');
    return result;
  }
  @override
  Future<void> restore(FirebaseDeparture baseline) async {
    final uid = _uid(); await _ready(uid);
    if (baseline.restored || baseline.revision >= 2147483647) throw const FormatException('Confirm a departed membership.');
    final root = _db.collection('groups').doc(baseline.groupId);
    final member = root.collection('members').doc(baseline.uid);
    final marker = root.collection('departures').doc(baseline.uid);
    final history = marker.collection('versions').doc('${baseline.revision}');
    await _checked(uid, () => _db.runTransaction((transaction) async {
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> document) async {
        final snapshot = await _checked(uid, () => transaction.get(document));
        _confirmed(snapshot, document.path); return snapshot;
      }
      final group = await read(root), actor = await read(root.collection('members').doc(uid));
      _admin(baseline.groupId, uid, group.data(), actor.data());
      if ((await read(member)).exists) throw const FormatException('Membership changed. Refresh before restoring.');
      final old = await read(marker);
      final current = FirebaseDeparture.parse(baseline.groupId, baseline.uid, old.data());
      if (current.restored || current.revision != baseline.revision || current.removedAt != baseline.removedAt || current.changedAt != baseline.changedAt) {
        throw const FormatException('Membership version changed. Refresh before restoring.');
      }
      if ((await read(history)).exists) throw const FormatException('Membership version already retained.');
      _same(uid);
      transaction.set(history, old.data()!);
      transaction.update(marker, {'restored': true, 'revision': current.revision + 1, 'changedBy': uid, 'changedAt': FieldValue.serverTimestamp()});
      transaction.set(member, {'userId': baseline.uid, 'role': 'member', 'joinedAt': FieldValue.serverTimestamp()});
      transaction.set(_db.collection('users').doc(baseline.uid).collection('groups').doc(baseline.groupId),
        {'groupId': baseline.groupId, 'joinedAt': FieldValue.serverTimestamp()});
    }));
  }
}