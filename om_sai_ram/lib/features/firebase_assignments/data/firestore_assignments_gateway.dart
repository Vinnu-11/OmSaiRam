import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/utc_schedule_date.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_assignment_models.dart';

abstract class FirebaseAssignmentsGateway {
  Future<FirebaseAssignmentsResult> read(FirebaseAssignmentsScope scope);
  Future<void> create(FirebaseAssignmentsScope scope, FirebaseChapterUnit unit,
      {required DateTime? scheduledDate});
  Future<void> updateStatus(FirebaseAssignmentsScope scope,
      FirebaseChapterUnit unit, FirebaseReadingStatus status);
    Future<void> transition(FirebaseAssignmentsScope scope, FirebaseAssignment baseline,
      {required bool archived, required DateTime? scheduledDate, String? reassignTo});
    Future<FirebaseAssignment> version(FirebaseAssignmentsScope scope, FirebaseChapterUnit unit, int revision);
}

final firebaseAssignmentsGatewayProvider =
    Provider<FirebaseAssignmentsGateway>((ref) {
  throw StateError('Firebase assignments bootstrap has not completed.');
});

/// Same named-app auth/database as bootstrap. Rules remain authoritative.
class FirestoreAssignmentsGateway implements FirebaseAssignmentsGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreAssignmentsGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);

  void _same(FirebaseAssignmentsScope scope) {
    if (_auth.currentUser?.uid != scope.uid) {
      throw StateError('Firebase account changed. Retry.');
    }
  }

  /// Check before AND after each async boundary, including failed futures.
  Future<T> _checked<T>(
      FirebaseAssignmentsScope scope, Future<T> Function() action) async {
    _same(scope);
    try {
      final result = await action();
      _same(scope);
      return result;
    } catch (_) {
      _same(scope);
      rethrow;
    }
  }

  void _confirmed(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required.');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _get(
      FirebaseAssignmentsScope scope,
      DocumentReference<Map<String, dynamic>> doc) async {
    final snapshot = await _checked(scope, () => doc.get(_server));
    _same(scope);
    _confirmed(snapshot.metadata);
    return snapshot;
  }

  Future<
      ({
        FirebaseGroup group,
        FirebaseMembership self,
        FirebaseMembership member
      })> _access(FirebaseAssignmentsScope scope) async {
    validateAssignmentsScope(scope);
    _same(scope);
    final profile = await _checked(
        scope, () => _get(scope, _db.collection('users').doc(scope.uid)));
    _same(scope);
    final data =
        exactData(profile.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt');
    dateField(data, 'updatedAt');
    final groupRef = _db.collection('groups').doc(scope.groupId);
    final group = await _checked(scope, () => _get(scope, groupRef));
    _same(scope);
    final self = await _checked(scope,
        () => _get(scope, groupRef.collection('members').doc(scope.uid)));
    _same(scope);
    final member = scope.uid == scope.memberUid
        ? self
        : await _checked(
            scope,
            () => _get(
                scope, groupRef.collection('members').doc(scope.memberUid)));
    _same(scope);
    return (
      group: FirebaseGroup.parse(scope.groupId, group.data()),
      self: FirebaseMembership.parse(scope.uid, self.data()),
      member: FirebaseMembership.parse(scope.memberUid, member.data())
    );
  }

  CollectionReference<Map<String, dynamic>> _collection(
          FirebaseAssignmentsScope scope) =>
      _db
          .collection('groups')
          .doc(scope.groupId)
          .collection('readingWeeks')
          .doc('${scope.week}')
          .collection('members')
          .doc(scope.memberUid)
          .collection('assignments');

  @override
  Future<FirebaseAssignmentsResult> read(FirebaseAssignmentsScope scope) async {
    final access = await _checked(scope, () => _access(scope));
    access.group.requireWritable();
    _same(scope);
    final snapshot = await _checked(
        scope,
        () => _collection(scope)
            .orderBy(FieldPath.documentId)
            .limit(48)
            .get(_server));
    _same(scope);
    _confirmed(snapshot.metadata);
    final rows = snapshot.docs.map((doc) {
      _confirmed(doc.metadata);
      return FirebaseAssignment.parse(scope, doc.id, doc.data());
    }).toList();
    // Sequential server reads are NOT a multi-document atomic snapshot.
    return FirebaseAssignmentsResult(
        access.group, access.self, access.member, rows);
  }

  @override
  Future<void> create(FirebaseAssignmentsScope scope, FirebaseChapterUnit unit,
      {required DateTime? scheduledDate}) async {
    final date = utcScheduleDate(scheduledDate);
    final access = await _checked(scope, () => _access(scope));
    _same(scope);
    if (access.self.role != FirebaseGroupRole.admin &&
        access.self.role != FirebaseGroupRole.groupLead) {
      throw const FormatException(
          'Only an actual admin or group lead can assign.');
    }
    final doc = _collection(scope).doc(unit.key);
    await _checked(
        scope,
        () => _db.runTransaction((transaction) async {
              _same(scope);
              final existing =
                  await _checked(scope, () => transaction.get(doc));
              _same(scope);
              _confirmed(existing.metadata);
              if (existing.exists) {
                throw const FormatException('Assignment already exists.');
              }
              transaction.set(doc, {
                'groupId': scope.groupId,
                'userId': scope.memberUid,
                'weekNumber': scope.week,
                'unitKey': unit.key,
                'chapterStart': unit.start,
                'chapterEnd': unit.end,
                'scheduledDate': date == null ? null : Timestamp.fromDate(date),
                'createdBy': scope.uid,
                'createdAt': FieldValue.serverTimestamp(),
                'status': FirebaseReadingStatus.notStarted.key,
                'progressUpdatedAt': FieldValue.serverTimestamp()
              });
            }));
    _same(scope);
  }

  @override
  Future<void> updateStatus(FirebaseAssignmentsScope scope,
      FirebaseChapterUnit unit, FirebaseReadingStatus status) async {
    validateAssignmentsScope(scope);
    _same(scope);
    if (scope.memberUid != scope.uid) {
      throw const FormatException(
          'Only the assignee can update progress, including admins.');
    }
    final access = await _checked(scope, () => _access(scope));
    access.group.requireWritable();
    _same(scope);
    final doc = _collection(scope).doc(unit.key);
    final existing = await _checked(scope, () => _get(scope, doc));
    _same(scope);
    final assignment = FirebaseAssignment.parse(scope, doc.id, existing.data());
    if (!assignment.activeFor(access.member)) throw const FormatException('Assignment predates membership or is archived. Retained history is read-only.');
    // Immutable metadata is untouched. Concurrent valid updates are last-write-wins.
    await _checked(
        scope,
        () => doc.update({
              'status': status.key,
              'progressUpdatedAt': FieldValue.serverTimestamp()
            }));
    _same(scope);
  }

  @override
  Future<FirebaseAssignment> version(FirebaseAssignmentsScope scope, FirebaseChapterUnit unit, int revision) async {
    validateAssignmentsScope(scope);
    if (revision < 0 || revision >= 2147483647) throw const FormatException('Invalid assignment version.');
    await _checked(scope, () => _access(scope));
    final reference = _collection(scope).doc(unit.key).collection('versions').doc('$revision');
    final snapshot = await _get(scope, reference);
    if (snapshot.reference.path != reference.path || snapshot.id != '$revision') throw const FormatException('Assignment version path mismatch.');
    final result = FirebaseAssignment.parse(scope, unit.key, snapshot.data());
    if (result.revision != revision) throw const FormatException('Assignment version mismatch.');
    return result;
  }

  @override
  Future<void> transition(FirebaseAssignmentsScope scope, FirebaseAssignment baseline,
      {required bool archived, required DateTime? scheduledDate, String? reassignTo}) async {
    validateAssignmentsScope(scope);
    final date = utcScheduleDate(scheduledDate);
    if (baseline.groupId != scope.groupId || baseline.userId != scope.memberUid || baseline.weekNumber != scope.week ||
        baseline.archived == archived || baseline.revision >= 2147483647 ||
        (reassignTo != null && (!archived || assignmentSegment(reassignTo) == scope.memberUid))) {
      throw const FormatException('Confirm a current assignment and a different reassignment target.');
    }
    await _checked(scope, () => _access(scope));
    final group = _db.collection('groups').doc(scope.groupId);
    final reference = _collection(scope).doc(baseline.unit.key);
    final history = reference.collection('versions').doc('${baseline.revision}');
    final target = reassignTo == null ? null : group.collection('readingWeeks').doc('${scope.week}')
        .collection('members').doc(reassignTo).collection('assignments').doc(baseline.unit.key);
    await _checked(scope, () => _db.runTransaction((transaction) async {
      Future<DocumentSnapshot<Map<String, dynamic>>> read(DocumentReference<Map<String, dynamic>> document) async {
        final snapshot = await _checked(scope, () => transaction.get(document));
        _confirmed(snapshot.metadata);
        if (snapshot.reference.path != document.path || snapshot.id != document.id) {
          throw const FormatException('Assignment document path mismatch.');
        }
        return snapshot;
      }
      FirebaseGroup.parse(scope.groupId, (await read(group)).data()).requireWritable();
      final actor = FirebaseMembership.parse(scope.uid, (await read(group.collection('members').doc(scope.uid))).data());
      if (actor.role != FirebaseGroupRole.admin && actor.role != FirebaseGroupRole.groupLead) {
        throw const FormatException('Only a current admin or group lead can manage assignment versions.');
      }
      final currentDoc = await read(reference);
      final current = FirebaseAssignment.parse(scope, baseline.unit.key, currentDoc.data());
      if (current.revision != baseline.revision || current.archived != baseline.archived || current.progressToken != baseline.progressToken) {
        throw const FormatException('Assignment changed. Reload before confirming.');
      }
      if ((await read(history)).exists) throw const FormatException('Assignment version already retained.');
      if (!archived || reassignTo != null) {
        final targetUid = reassignTo ?? scope.memberUid;
        FirebaseMembership.parse(targetUid, (await read(group.collection('members').doc(targetUid))).data());
      }
      if (target != null && (await read(target)).exists) throw const FormatException('Target assignment already exists.');
      final fresh = <String, dynamic>{
        'scheduledDate': date == null ? null : Timestamp.fromDate(date), 'createdBy': scope.uid,
        'createdAt': FieldValue.serverTimestamp(), 'status': 'not_started', 'progressUpdatedAt': FieldValue.serverTimestamp(),
      };
      _same(scope);
      transaction.set(history, currentDoc.data()!);
      transaction.update(reference, {'archived': archived, 'revision': current.revision + 1,
        'changedBy': scope.uid, 'changedAt': FieldValue.serverTimestamp(), if (!archived) ...fresh});
      if (target != null) {
        transaction.set(target, {'groupId': scope.groupId, 'userId': reassignTo, 'weekNumber': scope.week,
          'unitKey': current.unit.key, 'chapterStart': current.unit.start, 'chapterEnd': current.unit.end, ...fresh});
      }
    }));
  }
}
