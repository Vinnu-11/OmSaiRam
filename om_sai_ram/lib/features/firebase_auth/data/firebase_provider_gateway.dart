import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

enum FirebaseOAuthProvider { google, apple }

const providerLabels = {
  'password': 'Email and password',
  'google.com': 'Google',
  'apple.com': 'Apple',
  'phone': 'Phone',
};

/// Refusal with a safe message, raised before any credential reaches Firebase.
class FirebaseProviderFailure implements Exception {
  final String message;
  const FirebaseProviderFailure(this.message);
  @override
  String toString() => message;
}

/// One pending SMS verification. Android may verify instantly and supply
/// [credential] without a code; otherwise [verificationId] awaits the code.
class FirebasePhoneChallenge {
  final String? verificationId;
  final PhoneAuthCredential? credential;
  const FirebasePhoneChallenge({this.verificationId, this.credential});
  bool get needsCode => credential == null;
}

String validPhoneNumber(String input) {
  final number = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(number)) {
    throw const FormatException(
        'Enter the phone number with country code, for example +919876543210.');
  }
  return number;
}

String validSmsCode(String input) {
  final code = input.trim();
  if (!RegExp(r'^\d{6}$').hasMatch(code)) {
    throw const FormatException('Enter the six-digit code.');
  }
  return code;
}

/// Sign-in creates or opens the account that owns the credential. Linking adds
/// a credential to the CURRENT account only: nothing here looks accounts up by
/// email or merges data across UIDs.
abstract class FirebaseProviderGateway {
  Set<String> get linkedProviders;
  Future<void> oauth(FirebaseOAuthProvider provider, {String? linkToUid});
  Future<FirebasePhoneChallenge> requestPhoneCode(String phoneNumber);
  Future<void> confirmPhoneCode(FirebasePhoneChallenge challenge, String code,
      {String? linkToUid});
}

final firebaseProviderGatewayProvider = Provider<FirebaseProviderGateway>((ref) {
  throw StateError('Firebase provider bootstrap has not completed.');
});

/// Native Google account picker. A null result means the user cancelled.
/// [serverClientId] is the project's OAuth web client ID, needed for an ID
/// token when the build has no google-services resources.
Future<OAuthCredential?> googleSignInCredential({String? serverClientId}) async {
  final account = await GoogleSignIn(
          scopes: const ['email'], serverClientId: serverClientId)
      .signIn();
  if (account == null) return null;
  final tokens = await account.authentication;
  return GoogleAuthProvider.credential(
      idToken: tokens.idToken, accessToken: tokens.accessToken);
}

class SdkFirebaseProviderGateway implements FirebaseProviderGateway {
  final FirebaseAuth _auth;
  final bool _web;
  final Future<OAuthCredential?> Function() _nativeGoogle;
  SdkFirebaseProviderGateway(this._auth,
      {required bool web, Future<OAuthCredential?> Function()? nativeGoogle})
      : _web = web, _nativeGoogle = nativeGoogle ?? googleSignInCredential;

  @override
  Set<String> get linkedProviders => {
        ...?_auth.currentUser?.providerData.map((info) => info.providerId)
      };

  /// The account to link to, or null for a sign-in from a signed-out SDK.
  User? _target(String? linkToUid) {
    final user = _auth.currentUser;
    if (linkToUid == null) {
      if (user != null) throw StateError('Log out before signing in.');
      return null;
    }
    if (user == null || user.uid != linkToUid) {
      throw StateError('Firebase account changed.');
    }
    return user;
  }

  Future<void> _use(AuthCredential credential, String? linkToUid) async {
    // Recheck after every provider UI: the session may have changed meanwhile.
    final user = _target(linkToUid);
    if (user == null) {
      await _auth.signInWithCredential(credential);
    } else {
      await user.linkWithCredential(credential);
    }
  }

  @override
  Future<void> oauth(FirebaseOAuthProvider provider, {String? linkToUid}) async {
    final user = _target(linkToUid);
    if (provider == FirebaseOAuthProvider.google && !_web) {
      late final OAuthCredential? credential;
      try {
        credential = await _nativeGoogle();
      } on PlatformException {
        throw const FirebaseProviderFailure(
            'Google sign-in is unavailable in this build: its Android configuration is missing or invalid.');
      }
      if (credential == null) {
        throw const FirebaseProviderFailure('Sign-in was cancelled.');
      }
      return _use(credential, linkToUid);
    }
    final AuthProvider sdkProvider = provider == FirebaseOAuthProvider.google
        ? GoogleAuthProvider()
        : AppleAuthProvider();
    if (user == null) {
      await (_web
          ? _auth.signInWithPopup(sdkProvider)
          : _auth.signInWithProvider(sdkProvider));
    } else {
      await (_web
          ? user.linkWithPopup(sdkProvider)
          : user.linkWithProvider(sdkProvider));
    }
  }

  @override
  Future<FirebasePhoneChallenge> requestPhoneCode(String phoneNumber) {
    final number = validPhoneNumber(phoneNumber);
    final done = Completer<FirebasePhoneChallenge>();
    void fail(Object error) {
      if (!done.isCompleted) done.completeError(error);
    }
    _auth.verifyPhoneNumber(
      phoneNumber: number,
      verificationCompleted: (credential) {
        if (!done.isCompleted) {
          done.complete(FirebasePhoneChallenge(credential: credential));
        }
      },
      verificationFailed: fail,
      codeSent: (verificationId, _) {
        if (!done.isCompleted) {
          done.complete(FirebasePhoneChallenge(verificationId: verificationId));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    ).catchError(fail);
    return done.future;
  }

  @override
  Future<void> confirmPhoneCode(FirebasePhoneChallenge challenge, String code,
      {String? linkToUid}) {
    _target(linkToUid);
    final credential = challenge.credential ??
        PhoneAuthProvider.credential(
            verificationId: challenge.verificationId!,
            smsCode: validSmsCode(code));
    return _use(credential, linkToUid);
  }
}
