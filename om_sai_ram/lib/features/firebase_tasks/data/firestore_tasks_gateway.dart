import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_task_models.dart';

abstract class FirebaseTasksGateway {
  Future<FirebaseTaskPage> read(
      {FirebaseTaskOptions options = defaultTaskOptions, String? cursor});
}

final firebaseTasksGatewayProvider = Provider<FirebaseTasksGateway>((ref) {
  throw StateError('Firebase tasks bootstrap has not completed.');
});

/// Independent owned-index discovery. No roster, collection-group, other private
/// profiles, writes or cached fallback. Sequential reads are not atomic and
/// cannot erase previously downloaded data after revocation.
/// At most 10*3*48 assignments + 10 indexes + 10 metadata + 1 self profile
/// documents returned. NOT a billing cap: rule reads/minimum query charges add.
class FirestoreTasksGateway implements FirebaseTasksGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreTasksGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);

  String _require() => assignmentSegment(_auth.currentUser?.uid ?? '');
  void _same(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw StateError('Firebase account changed. Retry.');
    }
  }

  Future<T> _checked<T>(String uid, Future<T> Function() action) async {
    _same(uid);
    try {
      final result = await action();
      _same(uid);
      return result;
    } catch (_) {
      _same(uid);
      rethrow;
    }
  }

  void _confirmed(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required.');
    }
  }

  @override
  Future<FirebaseTaskPage> read(
      {FirebaseTaskOptions options = defaultTaskOptions,
      String? cursor}) async {
    validateTaskOptions(options, cursor);
    final uid = _require();
    final profile = await _checked(
        uid, () => _db.collection('users').doc(uid).get(_server));
    _same(uid);
    _confirmed(profile.metadata);
    final data =
        exactData(profile.data(), {'displayName', 'createdAt', 'updatedAt'});
    validateDisplayName(textField(data, 'displayName', 100));
    dateField(data, 'createdAt');
    dateField(data, 'updatedAt');
    Query<Map<String, dynamic>> query = _db
        .collection('users')
        .doc(uid)
        .collection('groups')
        .orderBy(FieldPath.documentId)
        .limit(options.pageSize);
    if (cursor != null) query = query.startAfter([cursor]);
    final index = await _checked(uid, () => query.get(_server));
    _same(uid);
    _confirmed(index.metadata);
    if (index.docs.length > options.pageSize) {
      throw const FormatException('Unbounded index response.');
    }
    final groups = <FirebaseTaskGroup>[];
    for (final doc in index.docs) {
      _confirmed(doc.metadata);
      assignmentSegment(doc.id);
      final entry = FirebaseGroupIndex.parse(doc.id, doc.data());
      final groupRef = _db.collection('groups').doc(entry.groupId);
      final metadata = await _checked(uid, () => groupRef.get(_server));
      _same(uid);
      _confirmed(metadata.metadata);
      final group = FirebaseGroup.parse(entry.groupId, metadata.data());
      final weeks = <FirebaseTaskWeek>[];
      for (final week in taskWeeks(group, options)) {
        final result = await _checked(
            uid,
            () => groupRef
                .collection('readingWeeks')
                .doc('$week')
                .collection('members')
                .doc(uid)
                .collection('assignments')
                .orderBy(FieldPath.documentId)
                .limit(48)
                .get(_server));
        _same(uid);
        _confirmed(result.metadata);
        if (result.docs.length > 48) {
          throw const FormatException('Unbounded assignment response.');
        }
        final scope = (uid: uid, groupId: group.id, memberUid: uid, week: week);
        final rows = result.docs.map((row) {
          _confirmed(row.metadata);
          return FirebaseAssignment.parse(scope, row.id, row.data());
        }).where((row) => row.activeSince(doc.data()['joinedAt'] as Timestamp)).toList();
        weeks.add(FirebaseTaskWeek(week, rows));
      }
      groups.add(FirebaseTaskGroup(group, weeks));
    }
    final more = index.docs.length == options.pageSize;
    final page = FirebaseTaskPage(uid, groups,
        cursor: more ? index.docs.last.id : null, hasMore: more);
    page.validate((uid: uid, options: options), cursor);
    _same(uid);
    return page;
  }
}
