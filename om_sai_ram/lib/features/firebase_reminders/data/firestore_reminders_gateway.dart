import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import 'firebase_reminder_models.dart';

abstract class FirebaseRemindersGateway {
  Future<FirebaseReminderRecord?> read();
  Future<void> save(FirebaseReminderPreferences preferences);
}

final firebaseRemindersGatewayProvider = Provider<FirebaseRemindersGateway>((ref) {
  throw StateError('Firebase reminder bootstrap has not completed.');
});

/// Own SDK account only; no caller UID, legacy API, listeners or notifications.
class FirestoreRemindersGateway implements FirebaseRemindersGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  FirestoreRemindersGateway(this._auth, this._db);
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
  DocumentReference<Map<String, dynamic>> _reference(String uid) =>
      _db.collection('users').doc(uid).collection('settings').doc('reminders');
  @override
  Future<FirebaseReminderRecord?> read() async {
    final uid = _uid();
    final reference = _reference(uid);
    final snapshot = await _checked(uid,
      () => reference.get(const GetOptions(source: Source.server)));
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('Confirmed server reminder data required.');
    }
    if (snapshot.reference.path != reference.path || snapshot.id != 'reminders') {
      throw const FormatException('Reminder document path mismatch.');
    }
    final record = snapshot.exists ? FirebaseReminderRecord.parse(uid, snapshot.data()) : null;
    _same(uid);
    return record; // Missing stays missing; no default write.
  }
  @override
  Future<void> save(FirebaseReminderPreferences preferences) async {
    final uid = _uid();
    final data = FirebaseReminderPreferences.parse(preferences.toData()).toData();
    final reference = _reference(uid);
    await _checked(uid, () => reference.set({
      ...data, 'updatedAt': FieldValue.serverTimestamp(),
    })); // Full replacement: deliberately no merge options.
  }
}