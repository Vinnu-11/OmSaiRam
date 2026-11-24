import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firestore_assignments_gateway.dart';
import '../../firebase_assignments/providers/firebase_assignments_provider.dart';
import '../../firebase_groups/data/firestore_groups_gateway.dart';
import '../../firebase_member_display/data/firestore_member_display_gateway.dart';
import '../data/firebase_group_progress.dart';

class FirebaseGroupProgressState {
  final bool busy;
  final String? error;
  final FirebaseGroupProgressPage? page;
  const FirebaseGroupProgressState({this.busy = false, this.error, this.page});
}

class FirebaseGroupProgressController extends StateNotifier<FirebaseGroupProgressState> {
  final FirebaseGroupProgressGateway? gateway;
  final FirebaseGroupProgressBinding binding;
  final bool Function() isCurrent;
  String? _cursor;
  int _generation = 0;
  FirebaseGroupProgressController(this.gateway, this.binding, this.isCurrent) : super(const FirebaseGroupProgressState());
  Future<void> refresh({String? cursor, bool restart = false}) async {
    if (!mounted || state.busy || !isCurrent()) return;
    final after = restart ? null : cursor ?? _cursor;
    final generation = ++_generation;
    state = const FirebaseGroupProgressState(busy: true);
    bool current() => mounted && generation == _generation && isCurrent();
    try {
      validateGroupProgressBinding(binding, after);
      final page = await gateway!.read(binding, cursor: after);
      if (!current()) return;
      page.validate(binding, after);
      _cursor = after;
      state = FirebaseGroupProgressState(page: page);
    } catch (error) {
      if (current()) {
        _cursor = after;
        state = FirebaseGroupProgressState(error: assignmentsError(error));
      }
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseGroupProgressState();
    }
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseGroupProgressProvider = StateNotifierProvider.autoDispose.family<
  FirebaseGroupProgressController, FirebaseGroupProgressState, FirebaseGroupProgressBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((session) => (session.ready, session.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  try { validateGroupProgressBinding(binding); }
  on FormatException { return FirebaseGroupProgressController(null, binding, () => false); }
  if (!sessionBinding.$1 || sessionBinding.$2 != binding.uid || !current()) {
    return FirebaseGroupProgressController(null, binding, () => false);
  }
  return FirebaseGroupProgressController(FirebaseGroupProgressGateway(
    ref.watch(firebaseGroupsGatewayProvider), ref.watch(firebaseAssignmentsGatewayProvider),
    ref.watch(firebaseMemberDisplayGatewayProvider), current), binding, current);
});