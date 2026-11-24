import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_password_gateway.dart';

class FirebasePasswordState {
  final bool busy, complete, uncertain;
  final String? error;
  const FirebasePasswordState({this.busy = false, this.complete = false,
    this.uncertain = false, this.error});
  bool get canSubmit => !busy && !complete && !uncertain;
}

class FirebasePasswordController extends StateNotifier<FirebasePasswordState> {
  final FirebasePasswordGateway gateway;
  final bool Function() isCurrent;
  int _generation = 0;
  FirebasePasswordController(this.gateway, this.isCurrent)
      : super(const FirebasePasswordState());
  bool _valid(int generation) => mounted && generation == _generation && isCurrent();

  Future<void> submit(String current, String next, String confirmation) async {
    if (!mounted) return;
    if (!isCurrent()) { state = const FirebasePasswordState(); return; }
    if (!state.canSubmit) return;
    final metadata = gateway.identity;
    if (!metadata.eligible) {
      state = FirebasePasswordState(error: metadata.unavailable); return;
    }
    final validation = validatePasswordChange(current, next, confirmation);
    if (validation != null) {
      state = FirebasePasswordState(error: validation); return;
    }
    if (!isCurrent()) { state = const FirebasePasswordState(); return; }
    final generation = ++_generation;
    state = const FirebasePasswordState(busy: true);
    try {
      await gateway.change(current, next, confirmation);
      if (_valid(generation)) state = const FirebasePasswordState(complete: true);
    } catch (error) {
      if (_valid(generation)) {
        state = error is FirebasePasswordFailure
            ? FirebasePasswordState(error: error.message, uncertain: error.uncertain)
            : const FirebasePasswordState(error: passwordUpdateUncertain, uncertain: true);
      }
    } finally {
      if (mounted && !isCurrent()) state = const FirebasePasswordState();
    }
  }

  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebasePasswordProvider = StateNotifierProvider.autoDispose.family<
    FirebasePasswordController, FirebasePasswordState, String>((ref, uid) {
  final binding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  final gateway = ref.watch(firebasePasswordGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && binding == (true, uid) && session.ready &&
        session.user?.uid == uid && auth.currentUser?.uid == uid &&
        gateway.identity.uid == uid;
  }
  final controller = FirebasePasswordController(gateway, current);
  // Navigation must not permit overlapping dispatches or bypass uncertainty.
  // Session binding changes still destroy this scope, including logout/login
  // with the same UID. A completed form can be reopened explicitly.
  void Function()? release;
  final removeListener = controller.addListener((next) {
    if (next.busy || next.uncertain) {
      release ??= ref.keepAlive().close;
    } else {
      release?.call();
      release = null;
    }
  }, fireImmediately: false);
  ref.onDispose(removeListener);
  return controller;
});