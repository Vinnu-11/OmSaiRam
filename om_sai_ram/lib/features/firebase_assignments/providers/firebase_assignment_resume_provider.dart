import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_assignment_resume.dart';

class FirebaseAssignmentResumeState {
  final bool busy;
  final FirebaseAssignmentResume? value;
  final String? error;
  const FirebaseAssignmentResumeState(
      {this.busy = false, this.value, this.error});
}

class FirebaseAssignmentResumeController
    extends StateNotifier<FirebaseAssignmentResumeState> {
  final String uid;
  final Future<SharedPreferences> Function() preferences;
  final bool Function() isCurrent;
  late final Future<void> ready;
  FirebaseAssignmentResumeController(this.uid, this.preferences, this.isCurrent)
      : super(const FirebaseAssignmentResumeState()) {
    ready = _load();
  }
  bool get _current => mounted && isCurrent();
  Future<void> _load() async {
    if (!_current) return;
    try {
      final prefs = await preferences();
      if (!_current) return;
      final raw = prefs.getString(firebaseAssignmentResumeKey(uid));
      state = FirebaseAssignmentResumeState(
          value:
              raw == null ? null : FirebaseAssignmentResume.decode(raw, uid));
    } catch (_) {
      if (_current) {
        state = const FirebaseAssignmentResumeState(
            error:
                'Saved assignment could not be loaded. Clear the saved pointer to remove invalid local data.');
      }
    }
  }

  Future<bool> save(FirebaseAssignmentResume value) => _write(value);
  Future<bool> clear() => _write(null);
  Future<bool> _write(FirebaseAssignmentResume? value) async {
    await ready;
    if (!_current || state.busy || (value != null && value.scope.uid != uid)) {
      return false;
    }
    final previous = state.value;
    state = FirebaseAssignmentResumeState(busy: true, value: previous);
    try {
      final prefs = await preferences();
      if (!_current) return false;
      final key = firebaseAssignmentResumeKey(uid);
      final acknowledged = value == null
          ? await prefs.remove(key)
          : await prefs.setString(key, value.encode());
      if (!_current) return false;
      if (!acknowledged) {
        throw StateError('Local storage did not acknowledge the write.');
      }
      state = FirebaseAssignmentResumeState(value: value);
      return true;
    } catch (_) {
      if (_current) {
        state = FirebaseAssignmentResumeState(
            value: previous,
            error:
                'Saved assignment change was not confirmed. Retry when local storage is available.');
      }
      return false;
    } finally {
      if (mounted && state.busy) state = const FirebaseAssignmentResumeState();
    }
  }
}

final firebaseAssignmentResumePreferencesProvider =
    Provider<Future<SharedPreferences> Function()>(
        (ref) => SharedPreferences.getInstance);

final firebaseAssignmentResumeProvider = StateNotifierProvider.autoDispose
    .family<FirebaseAssignmentResumeController, FirebaseAssignmentResumeState,
        String>((ref, uid) {
  final binding = ref.watch(firebaseSessionProvider
      .select((session) => (session.ready, session.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == uid &&
        auth.currentUser?.uid == uid;
  }

  if (!binding.$1 || binding.$2 != uid || !current()) {
    return FirebaseAssignmentResumeController(
        uid, () => throw StateError('Unready session.'), () => false);
  }
  return FirebaseAssignmentResumeController(
      uid, ref.watch(firebaseAssignmentResumePreferencesProvider), current);
});
