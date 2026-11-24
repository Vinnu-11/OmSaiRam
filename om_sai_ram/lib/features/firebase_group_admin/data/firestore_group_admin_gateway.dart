import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_group_admin_models.dart';

abstract class FirebaseGroupAdminGateway {
  Future<FirebaseGroupSettingsSnapshot> load(String groupId);
  Future<void> save(FirebaseGroupSettingsSnapshot baseline, FirebaseGroupSettingsDraft draft);
  Future<void> changeRole(String groupId, String targetUid,
      FirebaseGroupRole expected, FirebaseGroupRole next);
  Future<void> addMember(String groupId, String targetUid);
  Future<void> setArchived(FirebaseGroupSettingsSnapshot baseline, bool archived);
  Future<void> transferOwnership(FirebaseGroupSettingsSnapshot baseline, FirebaseMembership successor);
}

final firebaseGroupAdminGatewayProvider = Provider<FirebaseGroupAdminGateway>((ref) {
  throw StateError('Firebase group admin bootstrap has not completed.');
});

/// Same named-app SDK instances as authentication. No caller actor identity.
class FirestoreGroupAdminGateway implements FirebaseGroupAdminGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreGroupAdminGateway(this._auth, this._db);
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
  Future<void> _ready(String uid) async {
    final doc = _db.collection('users').doc(uid);
    final snapshot = await _checked(uid, () => doc.get(_server));
    _confirmed(snapshot, doc.path);
    final data = exactData(snapshot.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt'); dateField(data, 'updatedAt');
  }
  @override
  Future<FirebaseGroupSettingsSnapshot> load(String groupId) async {
    assignmentSegment(groupId);
    final uid = _uid();
    await _checked(uid, () => _ready(uid));
    final group = _db.collection('groups').doc(groupId);
    final actor = group.collection('members').doc(uid);
    final groupDoc = await _checked(uid, () => group.get(_server));
    _confirmed(groupDoc, group.path);
    final actorDoc = await _checked(uid, () => actor.get(_server));
    _confirmed(actorDoc, actor.path);
    final baseline = FirebaseGroupSettingsSnapshot.parse(groupId, groupDoc.data());
    requireActualAdmin(FirebaseMembership.parse(uid, actorDoc.data()));
    return baseline;
  }
  @override
  Future<void> save(FirebaseGroupSettingsSnapshot baseline, FirebaseGroupSettingsDraft draft) async {
    final id = assignmentSegment(baseline.group.id);
    draft.requireMode(baseline.group.mode); // Before any SDK call.
    final uid = _uid();
    await _checked(uid, () => _ready(uid));
    final group = _db.collection('groups').doc(id);
    final actor = group.collection('members').doc(uid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid); // Every SDK retry rechecks actor and current server version.
      final groupDoc = await _checked(uid, () => transaction.get(group));
      _confirmed(groupDoc, group.path);
      final actorDoc = await _checked(uid, () => transaction.get(actor));
      _confirmed(actorDoc, actor.path);
      final current = FirebaseGroupSettingsSnapshot.parse(id, groupDoc.data());
      current.group.requireWritable();
      requireActualAdmin(FirebaseMembership.parse(uid, actorDoc.data()));
      if (current.updatedAt != baseline.updatedAt) {
        throw const FormatException('Group settings changed. Reload before saving; your unsaved form has been retained.');
      }
      draft.requireMode(current.group.mode);
      _same(uid);
      transaction.update(group, draft.changes); // Never advances week or reschedules.
    }));
  }
  @override
  Future<void> addMember(String groupId, String targetUid) async {
    assignmentSegment(groupId); assignmentSegment(targetUid);
    final uid = _uid();
    if (uid == targetUid) throw const FormatException('You are already a group member.');
    await _checked(uid, () => _ready(uid));
    final group = _db.collection('groups').doc(groupId);
    final actor = group.collection('members').doc(uid);
    final target = group.collection('members').doc(targetUid);
    final departure = group.collection('departures').doc(targetUid);
    final discovery = _db.collection('users').doc(targetUid).collection('groups').doc(groupId);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid);
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> doc) async {
        final snapshot = await _checked(uid, () => transaction.get(doc));
        _confirmed(snapshot, doc.path);
        return snapshot;
      }
      FirebaseGroupSettingsSnapshot.parse(groupId, (await read(group)).data()).group.requireWritable();
      requireActualAdmin(FirebaseMembership.parse(uid, (await read(actor)).data()));
      if ((await read(target)).exists) throw const FormatException('Member already exists.');
      if ((await read(departure)).exists) {
        throw const FormatException('Rejoining after departure is not supported.');
      }
      _same(uid);
      final time = FieldValue.serverTimestamp();
      transaction.set(target, {'userId': targetUid, 'role': 'member', 'joinedAt': time});
      transaction.set(discovery, {'groupId': groupId, 'joinedAt': time});
    }));
  }

  @override
  Future<void> changeRole(String groupId, String targetUid,
      FirebaseGroupRole expected, FirebaseGroupRole next) async {
    assignmentSegment(groupId); assignmentSegment(targetUid);
    validateRoleChange(expected, next); // Never grant admin, even before reads.
    final uid = _uid();
    if (uid == targetUid) throw const FormatException('Self role changes are not supported.');
    await _checked(uid, () => _ready(uid));
    final group = _db.collection('groups').doc(groupId);
    final actor = group.collection('members').doc(uid);
    final target = group.collection('members').doc(targetUid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid);
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> doc) async {
        final snapshot = await _checked(uid, () => transaction.get(doc));
        _confirmed(snapshot, doc.path);
        return snapshot;
      }
      final groupDoc = await _checked(uid, () => read(group));
      final actorDoc = await _checked(uid, () => read(actor));
      final targetDoc = await _checked(uid, () => read(target));
      final actualGroup = FirebaseGroupSettingsSnapshot.parse(groupId, groupDoc.data()).group;
      actualGroup.requireWritable();
      requireRoleChange(actualGroup, FirebaseMembership.parse(uid, actorDoc.data()),
        FirebaseMembership.parse(targetUid, targetDoc.data()), expected, next);
      _same(uid);
      transaction.update(target, {'role': next == FirebaseGroupRole.groupLead ? 'group_lead' : 'member'});
    }));
  }

  @override
  Future<void> setArchived(FirebaseGroupSettingsSnapshot baseline, bool archived) async {
    final id = assignmentSegment(baseline.group.id);
    if (baseline.group.archived == archived || baseline.group.lifecycleRevision >= 2147483647) {
      throw const FormatException('Reload the group before changing archive status.');
    }
    final uid = _uid();
    await _checked(uid, () => _ready(uid));
    final group = _db.collection('groups').doc(id);
    final actor = group.collection('members').doc(uid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid);
      final groupDoc = await _checked(uid, () => transaction.get(group));
      _confirmed(groupDoc, group.path);
      final actorDoc = await _checked(uid, () => transaction.get(actor));
      _confirmed(actorDoc, actor.path);
      final current = FirebaseGroupSettingsSnapshot.parse(id, groupDoc.data());
      requireActualAdmin(FirebaseMembership.parse(uid, actorDoc.data()));
      if (current.updatedAt != baseline.updatedAt ||
          current.group.lifecycleRevision != baseline.group.lifecycleRevision ||
          current.group.archived != baseline.group.archived) {
        throw const FormatException('Group changed. Reload before confirming archive status.');
      }
      _same(uid);
      transaction.update(group, {
        'archived': archived, 'lifecycleRevision': current.group.lifecycleRevision + 1,
        'lifecycleChangedBy': uid, 'lifecycleChangedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }));
  }

  @override
  Future<void> transferOwnership(FirebaseGroupSettingsSnapshot baseline, FirebaseMembership successor) async {
    final id = assignmentSegment(baseline.group.id), uid = _uid();
    assignmentSegment(successor.uid);
    baseline.group.requireWritable();
    if (baseline.group.ownerUid != uid || successor.uid == uid || successor.role == FirebaseGroupRole.admin ||
        baseline.group.ownershipRevision >= 2147483647) {
      throw const FormatException('Only the current owner can confirm a different member or lead as successor.');
    }
    await _checked(uid, () => _ready(uid));
    final root = _db.collection('groups').doc(id);
    final actor = root.collection('members').doc(uid), target = root.collection('members').doc(successor.uid);
    final revision = baseline.group.ownershipRevision + 1;
    final audit = root.collection('ownershipChanges').doc('$revision');
    await _checked(uid, () => _db.runTransaction((transaction) async {
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> document) async {
        final snapshot = await _checked(uid, () => transaction.get(document));
        _confirmed(snapshot, document.path); return snapshot;
      }
      final current = FirebaseGroupSettingsSnapshot.parse(id, (await read(root)).data());
      current.group.requireWritable();
      requireActualAdmin(FirebaseMembership.parse(uid, (await read(actor)).data()));
      final member = FirebaseMembership.parse(successor.uid, (await read(target)).data());
      final expectedJoin = successor.joinedAtToken ?? Timestamp.fromDate(successor.joinedAt);
      if (current.group.ownerUid != uid || current.updatedAt != baseline.updatedAt ||
          current.group.ownershipRevision != baseline.group.ownershipRevision ||
          member.role != successor.role || member.joinedAtToken != expectedJoin) {
        throw const FormatException('Owner, group or successor changed. Reload before confirming.');
      }
      if ((await read(audit)).exists) throw const FormatException('Ownership version already exists.');
      _same(uid);
      final time = FieldValue.serverTimestamp();
      transaction.update(root, {'ownerUid': successor.uid, 'ownershipRevision': revision,
        'ownershipChangedBy': uid, 'ownershipChangedAt': time, 'updatedAt': time});
      transaction.update(actor, {'role': 'group_lead'});
      transaction.update(target, {'role': 'admin'});
      transaction.set(audit, {'groupId': id, 'fromOwner': uid, 'toOwner': successor.uid,
        'revision': revision, 'changedBy': uid, 'changedAt': time});
    }));
  }
}