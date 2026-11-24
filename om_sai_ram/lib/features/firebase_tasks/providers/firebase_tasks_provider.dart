import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_assignments/providers/firebase_assignments_provider.dart';
import '../data/firebase_task_models.dart';
import '../data/firestore_tasks_gateway.dart';

class FirebaseTasksState {
  final bool busy;
  final String? error;
  final FirebaseTaskPage? page;
  const FirebaseTasksState({this.busy = false, this.error, this.page});
}

class FirebaseTasksController extends StateNotifier<FirebaseTasksState> {
  final FirebaseTasksGateway? gateway;
  final FirebaseTaskBinding binding;
  final bool Function() isCurrent;
  String? _cursor;
  int _generation = 0;
  FirebaseTasksController(this.gateway, this.binding, this.isCurrent)
      : super(const FirebaseTasksState());
  Future<void> refresh({String? cursor, bool restart = false}) async {
    if (!mounted || state.busy || !isCurrent()) return;
    final requested = restart ? null : cursor ?? _cursor;
    final generation = ++_generation;
    state = const FirebaseTasksState(busy: true);
    bool current() => mounted && generation == _generation && isCurrent();
    try {
      assignmentSegment(binding.uid);
      validateTaskOptions(binding.options, requested);
      final page =
          await gateway!.read(options: binding.options, cursor: requested);
      if (!current()) return;
      page.validate(binding, requested);
      _cursor = requested; // Advance only after the whole response succeeds.
      state = FirebaseTasksState(page: page);
    } catch (error) {
      if (current()) state = FirebaseTasksState(error: assignmentsError(error));
      // Keep failed next-page cursor for a retry, never skip it.
      if (current()) _cursor = requested;
    } finally {
      if (mounted && generation == _generation && state.busy) {
        state = const FirebaseTasksState();
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}

final firebaseTasksProvider = StateNotifierProvider.autoDispose
    .family<FirebaseTasksController, FirebaseTasksState, FirebaseTaskBinding>(
        (ref, binding) {
  final sessionBinding =
      ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == binding.uid &&
        auth.currentUser?.uid == binding.uid;
  }

  // Validate before constructing even an injected gateway.
  try {
    assignmentSegment(binding.uid);
    validateTaskOptions(binding.options);
  } on FormatException {
    return FirebaseTasksController(null, binding, () => false);
  }
  if (!sessionBinding.$1 || sessionBinding.$2 != binding.uid || !current()) {
    return FirebaseTasksController(null, binding, () => false);
  }
  return FirebaseTasksController(
      ref.watch(firebaseTasksGatewayProvider), binding, current);
});
