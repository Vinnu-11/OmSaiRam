import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firebase_auth_repository.dart';
import '../data/firebase_provider_gateway.dart';
import '../../firebase_account/data/firebase_account_gateway.dart';
import '../../firebase_account/data/firebase_account_models.dart';

class FirebaseSession {
  final FirebaseIdentity? user;
  final String? displayName;
  final bool busy;
  final String? error;
  /// Server-confirmed soft deactivation: signed in, but never [ready].
  final bool deactivated;
  /// Non-blocking outcome of an account lifecycle request.
  final String? notice;
  const FirebaseSession(
      {this.user, this.displayName, this.busy = false, this.error,
      this.deactivated = false, this.notice});
  bool get ready =>
      user != null && displayName != null && !busy && error == null && !deactivated;
}

String friendlyFirebaseError(Object error) {
  if (error is FormatException) return error.message;
  if (error is FirebaseProviderFailure) return error.message;
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'account-exists-with-different-credential' =>
        'An account already uses this email with a different sign-in method. Log in with that method, then link the new one from your account. Accounts are never merged automatically.',
      'credential-already-in-use' || 'provider-already-linked' =>
        'That sign-in is already linked to an account. Nothing was linked or merged.',
      'invalid-verification-code' => 'The code is incorrect. Check it and try again.',
      'invalid-verification-id' || 'session-expired' || 'code-expired' =>
        'The code has expired. Request a new one.',
      'invalid-phone-number' => 'Enter a valid phone number with country code.',
      'quota-exceeded' => 'SMS limit reached. Try again later.',
      'operation-not-allowed' => 'This sign-in method is not enabled for this project.',
      'popup-closed-by-user' || 'cancelled-popup-request' ||
      'web-context-cancelled' || 'web-context-canceled' || 'canceled' =>
        'Sign-in was cancelled.',
      'popup-blocked' => 'The sign-in window was blocked. Allow pop-ups and try again.',
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' => 'Choose a password with at least six characters.',
      'email-already-in-use' =>
        'This email is already registered. Log in instead.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Email or password is incorrect.',
      'user-disabled' => 'This account is disabled.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      'network-request-failed' =>
        'Cannot reach the sign-in service. Check your connection and try again.',
      _ => 'Authentication failed. Try again.',
    };
  }
  return 'Private profile setup/read failed. Check your connection and retry. Your account has not been deleted.';
}

class FirebaseSessionController extends StateNotifier<FirebaseSession> {
  final FirebaseAuthGateway gateway;
  late final StreamSubscription<FirebaseIdentity?> _subscription;
  int _generation = 0;
  bool _operation = false;
  bool _seenAuth = false;
  FirebaseSessionController(this.gateway)
      : super(const FirebaseSession(busy: true)) {
    _subscription = gateway.authStateChanges().listen((user) {
      if (_operation || (_seenAuth && user?.uid == state.user?.uid)) return;
      _seenAuth = true;
      unawaited(_restore(user));
    }, onError: (Object error) {
      if (mounted && !_operation) {
        state = FirebaseSession(error: friendlyFirebaseError(error));
      }
    });
  }

  FirebaseSession _failed(FirebaseIdentity? user, Object error, {String? notice}) =>
      error is FirebaseAccountDeactivated
          ? FirebaseSession(user: user, deactivated: true, notice: notice)
          : FirebaseSession(user: user, error: friendlyFirebaseError(error));

  Future<void> _restore(FirebaseIdentity? user) async {
    final generation = ++_generation;
    state = FirebaseSession(user: user, busy: user != null);
    if (user == null) return;
    try {
      final name = await gateway.readProfile(user.uid);
      if (mounted && generation == _generation) {
        state = FirebaseSession(user: user, displayName: name);
      }
    } catch (error) {
      if (mounted && generation == _generation) state = _failed(user, error);
    }
  }

  Future<void> _run(Future<void> Function() action, {String? name}) async {
    if (state.busy || _operation) return;
    _operation = true;
    _seenAuth = true;
    ++_generation;
    state = FirebaseSession(
        user: state.user, displayName: state.displayName,
        deactivated: state.deactivated, busy: true);
    try {
      await action();
      final user = gateway.currentUser;
      final profile = user == null
          ? null
          : name == null
              ? await gateway.readProfile(user.uid)
              : await gateway.ensureProfile(user.uid, name);
      if (mounted) state = FirebaseSession(user: user, displayName: profile);
    } catch (error) {
      if (mounted) state = _failed(gateway.currentUser, error);
    } finally {
      _operation = false;
    }
  }

  /// Soft deactivation or restoration of the signed-in account. Whatever the
  /// write outcome, a fresh server read decides the resulting session state.
  Future<void> setAccountDeactivated(bool deactivated) async {
    final user = state.user;
    if (state.busy || _operation || user == null ||
        gateway.currentUser?.uid != user.uid ||
        (deactivated ? !state.ready : !state.deactivated)) {
      return;
    }
    _operation = true;
    ++_generation;
    state = FirebaseSession(user: user, displayName: state.displayName,
        deactivated: state.deactivated, busy: true);
    String? notice;
    try {
      await gateway.setAccountDeactivated(user.uid, deactivated);
    } on FormatException catch (error) {
      notice = error.message;
    } catch (_) {
      notice = 'Account change could not be confirmed. The state shown was reloaded from the server.';
    }
    try {
      final name = await gateway.readProfile(user.uid);
      if (mounted) {
        state = FirebaseSession(user: user, displayName: name, notice: notice);
      }
    } catch (error) {
      if (mounted) state = _failed(gateway.currentUser, error, notice: notice);
    } finally {
      _operation = false;
    }
  }

  /// Permanent account deletion. A refusal before any removal keeps the
  /// session; any later failure reloads the profile to show what remains.
  Future<void> deleteAccount() async {
    final user = state.user;
    if (state.busy || _operation || user == null || state.deactivated ||
        gateway.currentUser?.uid != user.uid) {
      return;
    }
    _operation = true;
    ++_generation;
    final previous = state;
    state = FirebaseSession(
        user: user, displayName: previous.displayName, busy: true);
    try {
      final retained = await gateway.deleteAccount(user.uid);
      if (mounted) {
        state = FirebaseSession(
            notice: retained == 0
                ? 'Your account was deleted.'
                : 'Your account was deleted. $retained archived group(s) keep an anonymous membership ID until an admin restores the group and removes it.');
      }
    } on FormatException catch (error) {
      if (mounted) {
        state = FirebaseSession(user: user, displayName: previous.displayName,
            error: previous.error, notice: error.message);
      }
    } catch (error) {
      final notice = error is FirebaseAuthException &&
              error.code == 'requires-recent-login'
          ? 'Your data was removed, but the sign-in needs a fresh login to be deleted. Log out, log in again and choose Delete account to finish.'
          : 'Account deletion did not finish; some data may already be removed. Check your connection and try again.';
      try {
        final current = gateway.currentUser;
        final name = current == null ? null : await gateway.readProfile(current.uid);
        if (mounted) {
          state = FirebaseSession(user: current, displayName: name, notice: notice);
        }
      } catch (reload) {
        if (mounted) state = _failed(gateway.currentUser, reload, notice: notice);
      }
    } finally {
      _operation = false;
    }
  }

  Future<void> signUp(String email, String password, String name) async {
    if (state.busy) return;
    try {
      final validName = validateDisplayName(name);
      await _run(() => gateway.signUp(email.trim(), password), name: validName);
    } on FormatException catch (error) {
      state = FirebaseSession(user: state.user, error: error.message);
    }
  }

  Future<void> signIn(String email, String password) =>
      _run(() => gateway.signIn(email.trim(), password));
  /// Google, Apple or phone credential sign-in. New accounts continue to the
  /// explicit display-name step; no profile is created or matched by email.
  Future<void> signInWithProvider(Future<void> Function() action) => _run(action);
  Future<void> retryProfile(String name) => _run(() async {}, name: name);
  Future<void> reloadProfile() => _run(() async {});
  Future<void> signOut() => _run(gateway.signOut);

  /// No caller-supplied confirmed name, no busy transition/route redirection.
  /// Only a fresh, SDK-bound account server read can refresh the workspace name.
  Future<FirebasePrivateProfile> readConfirmedAccountProfile(
      String uid, FirebaseAccountGateway account) async {
    final generation = _generation;
    void check() {
      if (!mounted || generation != _generation || !state.ready ||
          state.user?.uid != uid || gateway.currentUser?.uid != uid ||
          account.currentUid != uid) {
        throw StateError('Firebase account changed.');
      }
    }
    check();
    final profile = await account.read();
    check();
    if (profile.uid != uid) throw const FormatException('Private profile account mismatch.');
    state = FirebaseSession(user: state.user, displayName: profile.displayName);
    return profile;
  }

  @override
  void dispose() {
    ++_generation;
    _subscription.cancel();
    super.dispose();
  }
}

final firebaseSessionProvider = StateNotifierProvider.autoDispose<
    FirebaseSessionController, FirebaseSession>((ref) {
  return FirebaseSessionController(ref.watch(firebaseAuthGatewayProvider));
});
