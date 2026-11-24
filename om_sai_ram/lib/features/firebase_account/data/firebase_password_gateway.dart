import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirebasePasswordIdentity {
  final String? uid;
  final String? unavailable;
  const FirebasePasswordIdentity(this.uid, this.unavailable);
  bool get eligible => uid != null && unavailable == null;
}

class FirebasePasswordFailure implements Exception {
  final String message;
  final bool uncertain;
  const FirebasePasswordFailure(this.message, {this.uncertain = false});
  @override
  String toString() => message;
}

const passwordUpdateUncertain =
    'Password update was sent but not confirmed. Do not retry here. Log out, then verify by logging in; if needed, use Forgot password? on the login screen.';
const passwordAccountChanged =
    'Account changed. This result was discarded. An already-sent password update cannot be undone here.';

String? validatePasswordChange(String current, String next, String confirmation) {
  if (current.isEmpty) return 'Enter your current password.';
  if (next.length < 6) return 'Choose a new password with at least six characters.';
  if (next != confirmation) return 'New password and confirmation must match.';
  return null;
}

abstract class FirebasePasswordGateway {
  FirebasePasswordIdentity get identity;
  Future<void> change(String current, String next, String confirmation);
}

final firebasePasswordGatewayProvider = Provider<FirebasePasswordGateway>((ref) {
  throw StateError('Firebase password bootstrap has not completed.');
});

String _reauthError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' || 'wrong-password' => 'Current password is incorrect.',
      'weak-password' => 'New password does not meet the server password policy.',
      'requires-recent-login' => 'Recent login required. Log out and log in again.',
      'network-request-failed' => 'Cannot reach authentication. No password update was sent. Check your connection and try again.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'user-disabled' => 'This account is disabled. No password update was sent.',
      _ => 'Reauthentication failed. No password update was sent.',
    };
  }
  return 'Reauthentication failed. No password update was sent.';
}

String _updateError(Object error) {
  final detail = error is FirebaseAuthException ? switch (error.code) {
    'weak-password' => 'The server reported that the password does not meet its policy. ',
    'requires-recent-login' => 'The server requires a recent login. ',
    'network-request-failed' => 'Authentication connection failed. ',
    'too-many-requests' => 'The server reported too many attempts. ',
    'user-disabled' => 'The server reported that this account is disabled. ',
    _ => '',
  } : '';
  return '$detail$passwordUpdateUncertain';
}

/// Only the explicitly injected named-app Auth instance; no profile/storage I/O.
class SdkFirebasePasswordGateway implements FirebasePasswordGateway {
  final FirebaseAuth _auth;
  SdkFirebasePasswordGateway(this._auth);

  FirebasePasswordIdentity _identity(User? user) {
    if (user == null) {
      return const FirebasePasswordIdentity(null, 'Log in before changing your password.');
    }
    final eligible = !user.isAnonymous && user.uid.isNotEmpty &&
        (user.email?.trim().isNotEmpty ?? false) &&
        user.providerData.any((provider) => provider.providerId == 'password');
    return FirebasePasswordIdentity(user.uid, eligible ? null :
        'Password change requires a non-anonymous email/password account with a linked password provider.');
  }

  @override
  FirebasePasswordIdentity get identity => _identity(_auth.currentUser);

  @override
  Future<void> change(String current, String next, String confirmation) async {
    final validation = validatePasswordChange(current, next, confirmation);
    if (validation != null) throw FirebasePasswordFailure(validation);
    final user = _auth.currentUser;
    final metadata = _identity(user);
    if (!metadata.eligible || user == null) {
      throw FirebasePasswordFailure(metadata.unavailable!);
    }
    final uid = user.uid;
    var changed = false;
    var dispatched = false;
    // FlutterFire currentUser returns fresh wrappers. Reauth may replace the
    // platform object too: pin this Auth instance + UID, not wrapper identity.
    final subscription = _auth.authStateChanges().listen((value) {
      if (value?.uid != uid) changed = true;
    }, onError: (Object _) { changed = true; });
    void same() {
      if (changed || user.uid != uid || _auth.currentUser?.uid != uid) {
        throw FirebasePasswordFailure(passwordAccountChanged, uncertain: dispatched);
      }
    }
    try {
      same();
      final credential = EmailAuthProvider.credential(
          email: user.email!, password: current);
      same();
      final result = await user.reauthenticateWithCredential(credential);
      same();
      if (result.user?.uid != uid) {
        throw const FirebasePasswordFailure('Reauthentication account mismatch. No password update was sent.');
      }
      same();
      dispatched = true;
      await user.updatePassword(next);
      same(); // Only an ACK for the still-current account is success.
    } catch (error) {
      same(); // Also reject failed futures belonging to an old account.
      if (dispatched) {
        throw FirebasePasswordFailure(_updateError(error), uncertain: true);
      }
      if (error is FirebasePasswordFailure) rethrow;
      throw FirebasePasswordFailure(_reauthError(error));
    } finally {
      // No authentication retries or hidden sign-in. Cancel the local observer.
      unawaited(subscription.cancel());
    }
  }
}