import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import 'firebase_account_models.dart';

abstract class FirebaseAccountGateway {
  String? get currentUid;
  Future<FirebasePrivateProfile> read();
  /// Transaction ACK only. A separate server read confirms the saved value.
  Future<void> updateName(String name);
  Future<void> requestPasswordReset(String email);
}

final firebaseAccountGatewayProvider = Provider<FirebaseAccountGateway>((ref) {
  throw StateError('Firebase account bootstrap has not completed.');
});

String accountError(Object error) {
  if (error is FormatException) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'network-request-failed' => 'Cannot reach authentication. Check your connection and try again.',
      _ => 'Password reset request failed. Try again later.',
    };
  }
  return 'Password reset request failed. Try again later.';
}

/// Injected named-app SDK pair. No default SDK instances or caller owner UID.
class SdkFirebaseAccountGateway implements FirebaseAccountGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  SdkFirebaseAccountGateway(this._auth, this._db);
  @override
  String? get currentUid => _auth.currentUser?.uid;
  void _same(String? uid) {
    if (currentUid != uid) throw StateError('Firebase account changed.');
  }
  Future<T> _checked<T>(String? uid, Future<T> Function() operation) async {
    _same(uid);
    try {
      final value = await operation();
      _same(uid);
      return value;
    } catch (_) { _same(uid); rethrow; }
  }
  FirebasePrivateProfile _parse(String uid, DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('Confirmed server data required.');
    }
    if (snapshot.reference.path != 'users/$uid' || snapshot.id != uid) {
      throw const FormatException('Private profile path mismatch.');
    }
    final profile = FirebasePrivateProfile.parse(uid, snapshot.data());
    _same(uid);
    return profile;
  }
  @override
  Future<FirebasePrivateProfile> read() async {
    final uid = assignmentSegment(currentUid ?? '');
    final doc = _db.collection('users').doc(uid);
    return _parse(uid, await _checked(uid,
        () => doc.get(const GetOptions(source: Source.server))));
  }
  @override
  Future<void> updateName(String name) async {
    final validName = validateDisplayName(name);
    final uid = assignmentSegment(currentUid ?? '');
    final doc = _db.collection('users').doc(uid);
    await _checked(uid, () => _db.runTransaction((transaction) async {
      _same(uid); // Recheck on every SDK transaction retry, before any read.
      final snapshot = await _checked(uid, () => transaction.get(doc));
      _parse(uid, snapshot); // Missing/malformed profiles are never created.
      _same(uid);
      transaction.update(doc, {
        'displayName': validName,
        'updatedAt': FieldValue.serverTimestamp(),
      }); // createdAt remains untouched, including its original nanoseconds.
    }));
  }
  @override
  Future<void> requestPasswordReset(String email) async {
    final validEmail = resetEmail(email);
    if (currentUid != null) throw StateError('Log out before requesting a reset.');
    await _checked(null, () async {
      try {
        // SDK defaults only: no custom action URL, OOB-code lookup or logging.
        await _auth.sendPasswordResetEmail(email: validEmail);
      } on FirebaseAuthException catch (error) {
        if (error.code != 'user-not-found') rethrow;
      }
    });
  }
}