import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_account_gateway.dart';
import '../data/firebase_account_models.dart';

class FirebaseAccountState {
  final bool busy, acknowledged, verifyBeforeSave;
  final FirebasePrivateProfile? profile;
  final String? draft, error;
  const FirebaseAccountState({this.busy = false, this.acknowledged = false,
    this.verifyBeforeSave = false, this.profile, this.draft, this.error});
  bool get canEdit => !busy && !verifyBeforeSave && profile != null;
}

class FirebaseAccountController extends StateNotifier<FirebaseAccountState> {
  final String uid;
  final FirebaseAccountGateway Function() gateway;
  final bool Function() isCurrent;
  final Future<FirebasePrivateProfile> Function() readConfirmed;
  int _generation = 0;
  FirebaseAccountController(this.uid, this.gateway, this.isCurrent,
      this.readConfirmed) : super(const FirebaseAccountState());
  bool get _current => mounted && isCurrent();
  bool _valid(int generation) => _current && generation == _generation;
  void _clearIfChanged() {
    if (mounted && !isCurrent()) state = const FirebaseAccountState();
  }
  void _validate(FirebasePrivateProfile profile) {
    if (profile.uid != uid) throw const FormatException('Private profile account mismatch.');
  }
  Future<void> load() async {
    if (!_current) { _clearIfChanged(); return; }
    if (state.busy) return;
    final generation = ++_generation;
    final ack = state.acknowledged;
    final draft = state.verifyBeforeSave ? state.draft : null;
    state = FirebaseAccountState(busy: true, acknowledged: ack, draft: draft);
    try {
      final profile = await readConfirmed();
      if (!_valid(generation)) return;
      _validate(profile);
      state = FirebaseAccountState(profile: profile, draft: profile.displayName,
          acknowledged: ack);
    } catch (_) {
      if (_valid(generation)) {
        state = FirebaseAccountState(draft: draft, acknowledged: ack,
          verifyBeforeSave: true, error: ack
            ? 'Save acknowledged; server reload failed. Retry server read, not the write.'
            : 'Private profile unavailable. Retry server read before editing.');
      }
    } finally { _clearIfChanged(); }
  }
  void edit(String draft) {
    if (!_current) { _clearIfChanged(); return; }
    if (!state.canEdit) return;
    state = FirebaseAccountState(profile: state.profile, draft: draft);
  }
  Future<void> save() async {
    if (!_current) { _clearIfChanged(); return; }
    if (!state.canEdit || state.acknowledged) return;
    late final String name;
    try { name = validateDisplayName(state.draft ?? ''); }
    on FormatException catch (error) {
      state = FirebaseAccountState(profile: state.profile, draft: state.draft,
          error: error.message);
      return;
    }
    final generation = ++_generation;
    final draft = state.draft;
    var ack = false;
    state = FirebaseAccountState(busy: true, draft: draft);
    try {
      await gateway().updateName(name);
      ack = true;
      if (!_valid(generation)) return;
      state = FirebaseAccountState(busy: true, acknowledged: true, draft: draft);
      final profile = await readConfirmed();
      if (!_valid(generation)) return;
      _validate(profile);
      state = FirebaseAccountState(profile: profile, draft: profile.displayName,
          acknowledged: true);
    } catch (_) {
      if (_valid(generation)) {
        state = FirebaseAccountState(draft: draft, acknowledged: ack,
          verifyBeforeSave: true, error: ack
            ? 'Save acknowledged; server reload failed. Retry server read, not the write.'
            : 'Save not acknowledged; server state is uncertain. Draft retained. Retry server read before saving again.');
      }
    } finally { _clearIfChanged(); }
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseAccountProvider = StateNotifierProvider.autoDispose.family<
    FirebaseAccountController, FirebaseAccountState, String>((ref, uid) {
  final binding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && binding.$1 && binding.$2 == uid && session.ready &&
      session.user?.uid == uid && auth.currentUser?.uid == uid;
  }
  FirebaseAccountGateway gateway() => ref.read(firebaseAccountGatewayProvider);
  return FirebaseAccountController(uid, gateway, current, () => ref
      .read(firebaseSessionProvider.notifier).readConfirmedAccountProfile(uid, gateway()));
});

class FirebasePasswordResetState {
  final bool busy, requested;
  final String? error;
  const FirebasePasswordResetState({this.busy = false, this.requested = false, this.error});
}

class FirebasePasswordResetController extends StateNotifier<FirebasePasswordResetState> {
  final FirebaseAccountGateway Function() gateway;
  final bool Function() isCurrent;
  FirebasePasswordResetController(this.gateway, this.isCurrent)
      : super(const FirebasePasswordResetState());
  Future<void> request(String email) async {
    if (!mounted || !isCurrent() || state.busy || state.requested) return;
    late final String validEmail;
    try { validEmail = resetEmail(email); }
    on FormatException catch (error) {
      state = FirebasePasswordResetState(error: error.message); return;
    }
    state = const FirebasePasswordResetState(busy: true);
    try {
      await gateway().requestPasswordReset(validEmail);
      if (mounted && isCurrent()) state = const FirebasePasswordResetState(requested: true);
    } catch (error) {
      if (mounted && isCurrent()) {
        state = FirebasePasswordResetState(error: accountError(error));
      }
    } finally {
      if (mounted && !isCurrent()) state = const FirebasePasswordResetState();
    }
  }
}

final firebasePasswordResetProvider = StateNotifierProvider.autoDispose<
    FirebasePasswordResetController, FirebasePasswordResetState>((ref) {
  final binding = ref.watch(firebaseSessionProvider.select((s) => (s.user?.uid, s.busy)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() => active && binding == (null, false) &&
      ref.read(firebaseSessionProvider).user == null &&
      !ref.read(firebaseSessionProvider).busy && auth.currentUser == null;
  return FirebasePasswordResetController(() => ref.read(firebaseAccountGatewayProvider), current);
});