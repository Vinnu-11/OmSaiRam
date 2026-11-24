import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_member_display_models.dart';

abstract class FirebaseMemberDisplayGateway {
  Future<FirebaseMemberDisplayPage> read(String groupId, {int pageSize = 20, String? after});
  Future<List<FirebaseMemberDisplay>> readMembers(String groupId, List<String> memberUids);
  /// SDK actor only. Acknowledges the transaction, not the follow-up read.
  Future<void> publish(String groupId, String displayName);
}

final firebaseMemberDisplayGatewayProvider = Provider<FirebaseMemberDisplayGateway>((ref) {
  throw StateError('Firebase member display bootstrap has not completed.');
});

/// Same injected named-app Auth/Firestore pair. No users/profile/roster reads,
/// identity backfill, delete operation or caller-supplied writer UID.
class FirestoreMemberDisplayGateway implements FirebaseMemberDisplayGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreMemberDisplayGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);
  String _uid() => assignmentSegment(_auth.currentUser?.uid ?? '');
  void _same(String uid) {
    if (_auth.currentUser?.uid != uid) throw StateError('Firebase account changed.');
  }
  Future<T> _checked<T>(String uid, Future<T> Function() operation) async {
    _same(uid);
    try {
      final value = await operation();
      _same(uid);
      return value;
    } catch (_) { _same(uid); rethrow; }
  }
  void _metadata(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required.');
    }
  }
  void _document(DocumentSnapshot<Map<String, dynamic>> snapshot, String path) {
    _metadata(snapshot.metadata);
    if (snapshot.reference.path != path || snapshot.id != path.split('/').last) {
      throw const FormatException('Server document path mismatch.');
    }
  }
  @override
  Future<FirebaseMemberDisplayPage> read(String groupId, {int pageSize = 20, String? after}) async {
    assignmentSegment(groupId); boundedPageSize(pageSize);
    if (after != null) assignmentSegment(after);
    final uid = _uid();
    final group = _db.collection('groups').doc(groupId);
    Future<DocumentSnapshot<Map<String, dynamic>>> get(DocumentReference<Map<String, dynamic>> doc) async {
      final snapshot = await _checked(uid, () => doc.get(_server));
      _document(snapshot, doc.path);
      return snapshot;
    }
    final parsedGroup = FirebaseGroup.parse(groupId, (await _checked(uid, () => get(group))).data());
    FirebaseMembership.parse(uid, (await _checked(uid, () => get(group.collection('members').doc(uid)))).data());
    final profiles = group.collection('memberProfiles');
    // Read own exact document independently, even when it is outside this page.
    final ownDoc = await _checked(uid, () => get(profiles.doc(uid)));
    final own = ownDoc.exists ? FirebaseMemberDisplay.parse(groupId, uid, ownDoc.data()) : null;
    Query<Map<String, dynamic>> query = profiles.orderBy(FieldPath.documentId).limit(pageSize);
    if (after != null) query = query.startAfter([after]);
    final snapshot = await _checked(uid, () => query.get(_server));
    _metadata(snapshot.metadata);
    final names = snapshot.docs.map((doc) {
      assignmentSegment(doc.id);
      _document(doc, '${profiles.path}/${doc.id}');
      return FirebaseMemberDisplay.parse(groupId, doc.id, doc.data());
    });
    final page = FirebaseMemberDisplayPage((uid: uid, groupId: groupId), names,
        own: own, pageSize: pageSize, after: after, archived: parsedGroup.archived);
    _same(uid);
    return page;
  }
  @override
  Future<List<FirebaseMemberDisplay>> readMembers(String groupId, List<String> memberUids) async {
    assignmentSegment(groupId);
    final members = List<String>.unmodifiable(memberUids);
    if (members.length > 20 || members.toSet().length != members.length) {
      throw const FormatException('Shared names require at most 20 distinct roster UIDs.');
    }
    for (final member in members) { assignmentSegment(member); }
    final uid = _uid();
    final group = _db.collection('groups').doc(groupId);
    Future<DocumentSnapshot<Map<String, dynamic>>> get(DocumentReference<Map<String, dynamic>> doc) async {
      final snapshot = await _checked(uid, () => doc.get(_server));
      _document(snapshot, doc.path);
      return snapshot;
    }
    FirebaseGroup.parse(groupId, (await get(group)).data());
    FirebaseMembership.parse(uid, (await get(group.collection('members').doc(uid))).data());
    final names = <FirebaseMemberDisplay>[];
    for (final member in members) {
      final snapshot = await get(group.collection('memberProfiles').doc(member));
      if (snapshot.exists) names.add(FirebaseMemberDisplay.parse(groupId, member, snapshot.data()));
    }
    _same(uid);
    return List.unmodifiable(names);
  }

  @override
  Future<void> publish(String groupId, String displayName) async {
    assignmentSegment(groupId); memberDisplayName(displayName);
    final uid = _uid();
    final group = _db.collection('groups').doc(groupId);
    final member = group.collection('members').doc(uid);
    final own = group.collection('memberProfiles').doc(uid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid); // Every SDK retry must revalidate current membership/group.
      Future<DocumentSnapshot<Map<String, dynamic>>> get(DocumentReference<Map<String, dynamic>> doc) async {
        final snapshot = await _checked(uid, () => transaction.get(doc));
        _document(snapshot, doc.path);
        return snapshot;
      }
      FirebaseGroup.parse(groupId, (await _checked(uid, () => get(group))).data()).requireWritable();
      FirebaseMembership.parse(uid, (await _checked(uid, () => get(member))).data());
      final existing = await _checked(uid, () => get(own));
      final current = existing.exists ? FirebaseMemberDisplay.parse(groupId, uid, existing.data()) : null;
      _same(uid);
      transaction.set(own, {
        'displayName': displayName,
        'createdAt': current?.createdAt ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }));
  }
}