import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import 'firebase_group_reminder_models.dart';

abstract class FirebaseGroupRemindersGateway {
  Future<FirebaseGroupReminderSnapshot> read(String groupId);
  Future<void> save(
      FirebaseGroupReminderSnapshot baseline, FirebaseGroupReminderDraft draft);
}

final firebaseGroupRemindersGatewayProvider =
    Provider<FirebaseGroupRemindersGateway>((ref) {
  throw StateError('Firebase group reminder bootstrap has not completed.');
});

class FirestoreGroupRemindersGateway implements FirebaseGroupRemindersGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreGroupRemindersGateway(this._auth, this._db);
  static const _server = GetOptions(source: Source.server);
  String _uid() => assignmentSegment(_auth.currentUser?.uid ?? '');
  void _same(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw StateError('Firebase account changed.');
    }
  }

  Future<T> _checked<T>(String uid, Future<T> Function() operation) async {
    _same(uid);
    try {
      final result = await operation();
      _same(uid);
      return result;
    } catch (_) {
      _same(uid);
      rethrow;
    }
  }

  void _confirmed(
      DocumentSnapshot<Map<String, dynamic>> snapshot, String path) {
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('Confirmed server schedule data required.');
    }
    if (snapshot.reference.path != path || snapshot.id != path.split('/').last) {
      throw const FormatException('Schedule document path mismatch.');
    }
  }

  @override
  Future<FirebaseGroupReminderSnapshot> read(String groupId) async {
    assignmentSegment(groupId);
    final uid = _uid();
    final group = _db.collection('groups').doc(groupId);
    final actor = group.collection('members').doc(uid);
    final schedule = group.collection('settings').doc('notificationSchedule');
    Future<DocumentSnapshot<Map<String, dynamic>>> get(
        DocumentReference<Map<String, dynamic>> ref) async {
      final result = await _checked(uid, () => ref.get(_server));
      _confirmed(result, ref.path);
      return result;
    }

    final parsedGroup = FirebaseGroup.parse(groupId, (await get(group)).data());
    final membership = FirebaseMembership.parse(uid, (await get(actor)).data());
    final snapshot = await get(schedule);
    final record = snapshot.exists
        ? FirebaseGroupReminderRecord.parse(groupId, snapshot.data())
        : null;
    _same(uid);
    return FirebaseGroupReminderSnapshot(uid, groupId, membership.role, record, archived: parsedGroup.archived);
  }

  @override
  Future<void> save(FirebaseGroupReminderSnapshot baseline,
      FirebaseGroupReminderDraft draft) async {
    final groupId = assignmentSegment(baseline.groupId), uid = _uid();
    if (baseline.uid != uid || !baseline.canEdit) {
      throw const FormatException('Actual schedule editor account required.');
    }
    final data = FirebaseGroupReminderDraft.parse(draft.toData()).toData();
    final expected = baseline.record?.revision ?? 0;
    if (expected >= groupReminderMaximumRevision) {
      throw const FormatException('Schedule revision limit reached.');
    }
    final group = _db.collection('groups').doc(groupId);
    final actor = group.collection('members').doc(uid);
    final schedule = group.collection('settings').doc('notificationSchedule');
    await _checked(
        uid,
        () => _db.runTransaction((transaction) async {
              Future<DocumentSnapshot<Map<String, dynamic>>> get(
                  DocumentReference<Map<String, dynamic>> ref) async {
                final result = await _checked(uid, () => transaction.get(ref));
                _confirmed(result, ref.path);
                return result;
              }

              FirebaseGroup.parse(groupId, (await get(group)).data()).requireWritable();
              final membership =
                  FirebaseMembership.parse(uid, (await get(actor)).data());
              if (membership.role != FirebaseGroupRole.admin &&
                  membership.role != FirebaseGroupRole.groupLead) {
                throw const FormatException(
                    'Only current group admins/leads can save schedules.');
              }
              final snapshot = await get(schedule);
              final current = snapshot.exists
                  ? FirebaseGroupReminderRecord.parse(groupId, snapshot.data())
                  : null;
              if ((current?.revision ?? 0) != expected ||
                  current?.updatedAt != baseline.record?.updatedAt) {
                throw const FormatException(
                    'Schedule changed. Reload before saving; your draft is retained.');
              }
              _same(uid);
              final time = FieldValue.serverTimestamp();
              transaction.set(schedule, {
                ...data,
                'groupId': groupId,
                'revision': expected + 1,
                'createdBy': current?.createdBy ?? uid,
                'createdAt': current?.createdAt ?? time,
                'updatedBy': uid,
                'updatedAt': time
              });
            }));
  }
}
