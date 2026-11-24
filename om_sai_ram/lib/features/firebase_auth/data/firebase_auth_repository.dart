import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A Firebase identity, never the legacy API User/JWT model.
class FirebaseIdentity {
  final String uid;
  final String? email;
  final String? phoneNumber;
  const FirebaseIdentity(this.uid, this.email, {this.phoneNumber});
}

/// Soft, self-reversible state; the Auth account and all data are retained.
class FirebaseAccountDeactivated implements Exception {
  const FirebaseAccountDeactivated();
}

abstract class FirebaseAuthGateway {
  FirebaseIdentity? get currentUser;
  Stream<FirebaseIdentity?> authStateChanges();
  Future<void> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  /// Throws [FirebaseAccountDeactivated] for a deactivated account.
  Future<String?> readProfile(String uid);
  Future<String> ensureProfile(String uid, String displayName);
  /// Write ACK only; [readProfile] confirms the resulting state. Throws
  /// [FormatException] when a precondition refuses the change before any write.
  Future<void> setAccountDeactivated(String uid, bool deactivated);
  /// Permanent. Leaves every writable group, deletes private data and then the
  /// Auth user. Returns how many archived (read-only) groups keep an anonymous
  /// membership. Throws [FormatException] when refused before any removal.
  Future<int> deleteAccount(String uid);
}

String validateDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > 100) {
    throw const FormatException('Display name must contain 1–100 characters.');
  }
  return trimmed;
}

class FirebaseAuthRepository implements FirebaseAuthGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  /// The coordinated self-departure transaction of the membership gateway.
  final Future<void> Function(String groupId)? _leaveGroup;
  FirebaseAuthRepository(this._auth, this._firestore,
      {Future<void> Function(String groupId)? leaveGroup})
      : _leaveGroup = leaveGroup;

  FirebaseIdentity? _identity(User? user) => user == null
      ? null
      : FirebaseIdentity(user.uid, user.email, phoneNumber: user.phoneNumber);
  @override
  FirebaseIdentity? get currentUser => _identity(_auth.currentUser);
  @override
  Stream<FirebaseIdentity?> authStateChanges() =>
      _auth.authStateChanges().map(_identity);
  @override
  Future<void> signUp(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  void _requireSelf(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw StateError('A self profile requires the current Firebase user.');
    }
  }

  /// An active profile has exactly three fields; a deactivated one also
  /// carries the `deactivatedAt` marker. Anything else fails closed.
  ({String name, bool deactivated})? _profile(Map<String, dynamic>? data) {
    if (data == null) return null;
    final deactivated = data.containsKey('deactivatedAt');
    if (data.length != (deactivated ? 4 : 3) ||
        data['createdAt'] is! Timestamp ||
        data['updatedAt'] is! Timestamp ||
        data['displayName'] is! String ||
        (deactivated && data['deactivatedAt'] is! Timestamp)) {
      throw StateError('Invalid private profile.');
    }
    return (
      name: validateDisplayName(data['displayName'] as String),
      deactivated: deactivated
    );
  }

  static const _server = GetOptions(source: Source.server);

  @override
  Future<String?> readProfile(String uid) async {
    _requireSelf(uid);
    final profile = _profile(
        (await _firestore.collection('users').doc(uid).get(_server)).data());
    if (profile != null && profile.deactivated) {
      throw const FirebaseAccountDeactivated();
    }
    return profile?.name;
  }

  /// Rules cannot enumerate groups, so this own-index scan is the ownership
  /// precondition. It is not atomic with the writes that follow it.
  Future<List<({String id, String name, bool owned, bool archived})>> _groups(
      String uid) async {
    const page = 50, maxGroups = 500;
    final groups = <({String id, String name, bool owned, bool archived})>[];
    String? after;
    for (;;) {
      var query = _firestore.collection('users').doc(uid).collection('groups')
          .orderBy(FieldPath.documentId).limit(page);
      if (after != null) query = query.startAfter([after]);
      final index = await query.get(_server);
      if (index.metadata.isFromCache) throw StateError('Confirmed server index required.');
      for (final entry in index.docs) {
        final data = (await _firestore.collection('groups').doc(entry.id).get(_server)).data();
        if (data == null) throw StateError('Group index is inconsistent.');
        groups.add((
          id: entry.id,
          name: data['name'] is String ? data['name'] as String : entry.id,
          owned: (data['ownerUid'] ?? data['createdBy']) == uid,
          archived: data['archived'] == true
        ));
      }
      if (index.docs.length < page) return groups;
      if (groups.length >= maxGroups) {
        throw const FormatException(
            'Too many groups to verify ownership. Leave some groups first.');
      }
      after = index.docs.last.id;
    }
  }

  void _requireNoOwnedGroups(
      List<({String id, String name, bool owned, bool archived})> groups, String action) {
    final owned = [for (final group in groups) if (group.owned) group.name];
    if (owned.isNotEmpty) {
      throw FormatException('Transfer ownership of ${owned.length} group(s) before '
          '$action: ${owned.take(3).join(', ')}${owned.length > 3 ? ', …' : ''}.');
    }
  }

  @override
  Future<void> setAccountDeactivated(String uid, bool deactivated) async {
    _requireSelf(uid);
    if (deactivated) {
      _requireNoOwnedGroups(await _groups(uid), 'deactivating');
      _requireSelf(uid);
    }
    final document = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction((transaction) async {
      _requireSelf(uid);
      final current = _profile((await transaction.get(document)).data());
      if (current == null) throw StateError('Private profile required.');
      if (current.deactivated == deactivated) return;
      // Restoration removes the marker: active profiles keep three fields.
      transaction.update(document, {
        'deactivatedAt':
            deactivated ? FieldValue.serverTimestamp() : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<int> deleteAccount(String uid) async {
    _requireSelf(uid);
    final user = _auth.currentUser!;
    // Firebase refuses to delete a user without a recent sign-in. Check first,
    // so that data is not removed while the sign-in itself would survive.
    final signedIn = user.metadata.lastSignInTime;
    if (signedIn == null ||
        DateTime.now().difference(signedIn) > const Duration(minutes: 5)) {
      throw const FormatException(
          'For your security, log out, log in again and delete the account within five minutes.');
    }
    final groups = await _groups(uid);
    _requireNoOwnedGroups(groups, 'deleting the account');
    var retained = 0;
    for (final group in groups) {
      _requireSelf(uid);
      if (group.archived) {
        retained++; // Archived groups are read-only: the membership stays.
      } else {
        final leave = _leaveGroup;
        if (leave == null) throw StateError('Group departure is unavailable.');
        await leave(group.id);
      }
    }
    _requireSelf(uid);
    final profile = _firestore.collection('users').doc(uid);
    final batch = _firestore.batch()
      ..delete(profile.collection('settings').doc('reminders'))
      ..delete(profile);
    await batch.commit();
    _requireSelf(uid);
    await user.delete();
    return retained;
  }

  @override
  Future<String> ensureProfile(String uid, String displayName) async {
    _requireSelf(uid);
    final name = validateDisplayName(displayName);
    final document = _firestore.collection('users').doc(uid);
    // Existing profiles remain untouched, including their original createdAt.
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);
      if (snapshot.exists) {
        _profile(snapshot.data());
        return;
      }
      transaction.set(document, {
        'displayName': name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    final saved = await readProfile(uid);
    if (saved == null) {
      throw StateError('Private profile is not yet available.');
    }
    return saved;
  }
}

final firebaseAuthGatewayProvider = Provider<FirebaseAuthGateway>((ref) {
  throw StateError('Firebase emulator bootstrap has not completed.');
});
