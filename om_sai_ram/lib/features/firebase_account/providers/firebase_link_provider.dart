import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/data/firebase_provider_gateway.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';

class FirebaseLinkState {
  final bool busy;
  final Set<String> providers;
  final FirebasePhoneChallenge? challenge;
  final String? message, error;
  const FirebaseLinkState({this.busy = false, this.providers = const {},
    this.challenge, this.message, this.error});
}

String linkError(Object error) =>
    error is FirebaseAuthException || error is FormatException || error is FirebaseProviderFailure
        ? friendlyFirebaseError(error)
        : 'Linking could not be confirmed. Reload to check your sign-in methods.';

/// Explicit linking to the signed-in UID only. A credential that already
/// belongs to another account is refused by Firebase; nothing is ever merged.
class FirebaseLinkController extends StateNotifier<FirebaseLinkState> {
  final String uid;
  final FirebaseProviderGateway Function() gateway;
  final bool Function() isCurrent;
  FirebaseLinkController(this.uid, this.gateway, this.isCurrent)
      : super(const FirebaseLinkState());
  bool get _current => mounted && isCurrent();
  void _clearIfChanged() {
    if (mounted && !isCurrent()) state = const FirebaseLinkState();
  }

  void refresh() {
    if (!_current) { _clearIfChanged(); return; }
    if (!state.busy) state = FirebaseLinkState(providers: gateway().linkedProviders);
  }

  Future<void> _link(Future<void> Function() action, {FirebasePhoneChallenge? keep}) async {
    if (!_current) { _clearIfChanged(); return; }
    if (state.busy) return;
    state = FirebaseLinkState(busy: true, providers: state.providers, challenge: keep);
    try {
      await action();
      if (_current) {
        state = FirebaseLinkState(providers: gateway().linkedProviders,
            message: 'Linked. Your account, UID and data are unchanged.');
      }
    } catch (error) {
      if (_current) {
        state = FirebaseLinkState(providers: gateway().linkedProviders,
            challenge: keep, error: linkError(error));
      }
    } finally { _clearIfChanged(); }
  }

  Future<void> linkOAuth(FirebaseOAuthProvider provider) =>
      _link(() => gateway().oauth(provider, linkToUid: uid));

  Future<void> requestPhoneCode(String number) async {
    if (!_current) { _clearIfChanged(); return; }
    if (state.busy) return;
    final providers = state.providers;
    state = FirebaseLinkState(busy: true, providers: providers);
    try {
      final challenge = await gateway().requestPhoneCode(number);
      if (_current) state = FirebaseLinkState(providers: providers, challenge: challenge);
    } catch (error) {
      if (_current) state = FirebaseLinkState(providers: providers, error: linkError(error));
    } finally { _clearIfChanged(); }
  }

  Future<void> confirmPhoneCode(String code) {
    final challenge = state.challenge;
    if (challenge == null) return Future.value();
    return _link(() => gateway().confirmPhoneCode(challenge, code, linkToUid: uid),
        keep: challenge);
  }

  void cancelPhone() {
    if (_current && !state.busy) state = FirebaseLinkState(providers: state.providers);
  }
}

final firebaseLinkProvider = StateNotifierProvider.autoDispose.family<
    FirebaseLinkController, FirebaseLinkState, String>((ref, uid) {
  final binding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && binding.$1 && binding.$2 == uid && session.ready &&
      session.user?.uid == uid && auth.currentUser?.uid == uid;
  }
  return FirebaseLinkController(
      uid, () => ref.read(firebaseProviderGatewayProvider), current);
});
