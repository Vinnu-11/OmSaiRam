import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_schedule_models.dart';

abstract class FirebaseSchedulingGateway {
  Future<FirebaseScheduleHead> load(FirebaseScheduleBinding binding, {int pageSize = 20, String? cursor});
  Future<void> commit(FirebaseScheduleBinding binding, FirebaseScheduleSettings settings, FirebaseSchedulePlan plan);
  Future<int> advance(FirebaseScheduleBinding binding);
}

final firebaseSchedulingGatewayProvider = Provider<FirebaseSchedulingGateway>((ref) {
  throw StateError('Firebase scheduling bootstrap has not completed.');
});

/// Same named-app Auth/Firestore. Client formula is not certified by rules.
class FirestoreSchedulingGateway implements FirebaseSchedulingGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreSchedulingGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);
  void _same(FirebaseScheduleBinding binding) {
    if (_auth.currentUser?.uid != binding.uid) throw StateError('Firebase account changed.');
  }
  Future<T> _checked<T>(FirebaseScheduleBinding binding, Future<T> Function() action) async {
    _same(binding);
    try { final value = await action(); _same(binding); return value; }
    catch (_) { _same(binding); rethrow; }
  }
  void _metadata(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) throw StateError('Confirmed server data required.');
  }
  void _document(DocumentSnapshot<Map<String, dynamic>> snapshot, String path) {
    _metadata(snapshot.metadata);
    if (snapshot.reference.path != path || snapshot.id != path.split('/').last ||
        snapshot.exists != (snapshot.data() != null)) {
      throw const FormatException('Server document path/existence mismatch.');
    }
  }
  Future<void> _ready(FirebaseScheduleBinding binding) async {
    validateScheduleBinding(binding);
    final reference = _db.collection('users').doc(binding.uid);
    final snapshot = await _checked(binding, () => reference.get(_server));
    _document(snapshot, reference.path);
    final data = exactData(snapshot.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt'); dateField(data, 'updatedAt');
  }
  FirebaseGroup _group(String id, Map<String, dynamic>? data) {
    final group = FirebaseGroup.parse(id, data);
    assignmentSegment(group.createdBy);
    return group;
  }
  @override
  Future<FirebaseScheduleHead> load(FirebaseScheduleBinding binding, {int pageSize = 20, String? cursor}) async {
    validateScheduleBinding(binding); boundedPageSize(pageSize);
    if (cursor != null) assignmentSegment(cursor);
    await _checked(binding, () => _ready(binding));
    final group = _db.collection('groups').doc(binding.groupId);
    final actor = group.collection('members').doc(binding.uid);
    final groupDoc = await _checked(binding, () => group.get(_server));
    _document(groupDoc, group.path);
    final actorDoc = await _checked(binding, () => actor.get(_server));
    _document(actorDoc, actor.path);
    final parsedGroup = _group(binding.groupId, groupDoc.data());
    final parsedActor = FirebaseMembership.parse(binding.uid, actorDoc.data());
    requireScheduler(parsedActor);
    var query = group.collection('members').orderBy(FieldPath.documentId).limit(pageSize);
    if (cursor != null) query = query.startAfter([cursor]);
    final roster = await _checked(binding, () => query.get(_server));
    _metadata(roster.metadata);
    if (roster.docs.length > pageSize) throw const FormatException('Oversized roster response.');
    final members = <FirebaseMembership>[];
    String? previous = cursor;
    for (final doc in roster.docs) {
      assignmentSegment(doc.id);
      _document(doc, '${group.path}/members/${doc.id}');
      if (previous != null && scheduleUidCompare(doc.id, previous) <= 0) {
        throw const FormatException('Invalid roster ordering or cursor.');
      }
      members.add(FirebaseMembership.parse(doc.id, doc.data())); previous = doc.id;
    }
    _same(binding);
    return FirebaseScheduleHead(parsedGroup, parsedActor, FirebasePage(members,
      cursor: roster.docs.isEmpty ? cursor : roster.docs.last.id, hasMore: roster.docs.length == pageSize));
  }
  @override
  Future<void> commit(FirebaseScheduleBinding binding, FirebaseScheduleSettings settings, FirebaseSchedulePlan plan) async {
    validateScheduleBinding(binding);
    // Pure immutable capture and atomic limits BEFORE any IO. Never accept arbitrary rows.
    final preview = previewFirebaseSchedule(settings, plan);
    final block = preview.commitBlock;
    if (block != null) throw FormatException(block);
    final targets = preview.assignments.map((row) => row.userId).toSet().toList();
    final paths = preview.assignments.map((row) => row.path(binding.groupId)).toList();
    if (paths.toSet().length != paths.length) throw const FormatException('Duplicate canonical assignment in plan.');
    await _checked(binding, () => _ready(binding));
    final group = _db.collection('groups').doc(binding.groupId);
    final references = [for (final row in preview.assignments)
      group.collection('readingWeeks').doc('${row.weekNumber}').collection('members')
        .doc(row.userId).collection('assignments').doc(row.unit.key)];
    await _checked(binding, () => _db.runTransaction((transaction) async {
      _same(binding); // SDK retries revalidate ALL authority and settings.
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> ref) async {
        final doc = await _checked(binding, () => transaction.get(ref));
        _document(doc, ref.path); return doc;
      }
      final groupDoc = await _checked(binding, () => read(group));
      final actorDoc = await _checked(binding, () => read(group.collection('members').doc(binding.uid)));
      final current = _group(binding.groupId, groupDoc.data());
      current.requireWritable();
      requireScheduler(FirebaseMembership.parse(binding.uid, actorDoc.data()));
      if (FirebaseScheduleSettings.fromGroup(current) != settings) {
        throw const FormatException('Group scheduling settings changed; preview again.');
      }
      for (final uid in targets) {
        final doc = await _checked(binding, () => read(group.collection('members').doc(uid)));
        FirebaseMembership.parse(uid, doc.data());
      }
      for (final reference in references) {
        final existing = await _checked(binding, () => read(reference));
        if (existing.exists) throw const FormatException('Assignment already exists; entire plan rejected.');
      }
      // ALL reads precede ALL writes. Create-only even for self assignments.
      _same(binding);
      for (var i = 0; i < references.length; i++) {
        final row = preview.assignments[i];
        transaction.set(references[i], {
          'groupId': binding.groupId, 'userId': row.userId, 'weekNumber': row.weekNumber,
          'unitKey': row.unit.key, 'chapterStart': row.unit.start, 'chapterEnd': row.unit.end,
          'scheduledDate': row.scheduledDate == null ? null : Timestamp.fromDate(row.scheduledDate!),
          'createdBy': binding.uid, 'createdAt': FieldValue.serverTimestamp(),
          'status': 'not_started', 'progressUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    }));
  }
  @override
  Future<int> advance(FirebaseScheduleBinding binding) async {
    validateScheduleBinding(binding);
    await _checked(binding, () => _ready(binding));
    final group = _db.collection('groups').doc(binding.groupId);
    final actor = group.collection('members').doc(binding.uid);
    return _checked(binding, () => _db.runTransaction((transaction) async {
      _same(binding);
      final groupDoc = await _checked(binding, () => transaction.get(group));
      _document(groupDoc, group.path);
      final actorDoc = await _checked(binding, () => transaction.get(actor));
      _document(actorDoc, actor.path);
      final current = _group(binding.groupId, groupDoc.data());
      current.requireWritable();
      if (!isGroupLeader(FirebaseMembership.parse(binding.uid, actorDoc.data()).role)) {
        throw const FormatException('Only the group admin or a group lead can move to the next week.');
      }
      if (current.currentWeek == 10000) throw const FormatException('Cannot advance beyond week 10000.');
      _same(binding);
      transaction.update(group, {'currentWeek': current.currentWeek + 1, 'updatedAt': FieldValue.serverTimestamp()});
      return current.currentWeek + 1; // Retry-current +1, NOT expected/stale week semantics; Saptah allowed.
    }));
  }
}