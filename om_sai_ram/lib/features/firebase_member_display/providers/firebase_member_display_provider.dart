import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../data/firebase_member_display_models.dart';
import '../data/firestore_member_display_gateway.dart';

class FirebaseMemberDisplayState {
  final bool busy, acknowledged, verifyBeforeRetry;
  final String? error;
  final FirebaseMemberDisplayPage? page;
  const FirebaseMemberDisplayState({this.busy = false, this.acknowledged = false,
    this.verifyBeforeRetry = false, this.error, this.page});
}

class FirebaseMemberDisplayController extends StateNotifier<FirebaseMemberDisplayState> {
  final FirebaseMemberDisplayBinding binding;
  final FirebaseMemberDisplayGateway Function() gateway;
  final bool Function() isCurrent;
  int _generation = 0;
  String? _after;
  FirebaseMemberDisplayController(this.binding, this.gateway, this.isCurrent)
      : super(const FirebaseMemberDisplayState());
  bool get _current => mounted && isCurrent();
  bool _valid(int generation) => _current && generation == _generation;
  void _validate(FirebaseMemberDisplayPage page, String? after) {
    if (page.binding != binding || page.pageSize != 20 || page.after != after) {
      throw const FormatException('Names response scope mismatch.');
    }
  }
  Future<void> load({String? after, bool retry = false}) async {
    if (!_current || state.busy) return;
    if (!retry) _after = after;
    final generation = ++_generation;
    final acknowledged = state.acknowledged;
    state = FirebaseMemberDisplayState(busy: true, acknowledged: acknowledged);
    try {
      final page = await gateway().read(binding.groupId, after: _after);
      if (!_valid(generation)) return;
      _validate(page, _after);
      state = FirebaseMemberDisplayState(page: page);
    } catch (error) {
      if (_valid(generation)) {
        state = FirebaseMemberDisplayState(
          acknowledged: acknowledged, verifyBeforeRetry: true, error: groupsError(error));
      }
    } finally {
      if (mounted && !isCurrent()) state = const FirebaseMemberDisplayState();
    }
  }
  Future<bool> publish(String name) async {
    if (!_current || state.busy || state.page == null || state.acknowledged || state.verifyBeforeRetry) return false;
    final trimmed = name.trim();
    memberDisplayName(trimmed);
    final generation = ++_generation;
    state = const FirebaseMemberDisplayState(busy: true); // Clear before await.
    var acknowledged = false;
    try {
      await gateway().publish(binding.groupId, trimmed);
      acknowledged = true;
      if (!_valid(generation)) return false;
      state = const FirebaseMemberDisplayState(busy: true, acknowledged: true);
      _after = null;
      final page = await gateway().read(binding.groupId);
      if (!_valid(generation)) return false;
      _validate(page, null);
      state = FirebaseMemberDisplayState(acknowledged: true, page: page);
      return true;
    } catch (error) {
      if (!_valid(generation)) return false;
      state = FirebaseMemberDisplayState(acknowledged: acknowledged, verifyBeforeRetry: true,
        error: acknowledged
          ? 'Name write acknowledged; server reload unavailable. Refresh manually. Do not repeat the write.'
          : '${groupsError(error)} Verify server state before another attempt. No automatic retry.');
      return acknowledged;
    } finally {
      if (mounted && !isCurrent()) state = const FirebaseMemberDisplayState();
    }
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseMemberDisplayProvider = StateNotifierProvider.autoDispose.family<
    FirebaseMemberDisplayController, FirebaseMemberDisplayState, FirebaseMemberDisplayBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && sessionBinding.$1 && sessionBinding.$2 == binding.uid &&
      session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  // Lazy: neither default mode nor group-link rendering constructs the gateway.
  return FirebaseMemberDisplayController(binding,
    () => ref.read(firebaseMemberDisplayGatewayProvider), current);
});