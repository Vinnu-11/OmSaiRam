import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../data/firebase_chat_models.dart';
import '../data/firestore_chat_gateway.dart';

class FirebaseChatState {
  final bool busy, verifyBeforeRetry;
  final FirebaseChatPage? page;
  final String? error;
  final FirebaseChatDelivery delivery;
  const FirebaseChatState({this.busy = false, this.verifyBeforeRetry = false,
    this.page, this.error, this.delivery = FirebaseChatDelivery.notAttempted});
}

class FirebaseChatController extends StateNotifier<FirebaseChatState> {
  final FirebaseChatGateway? gateway;
  final FirebaseChatBinding binding;
  final bool Function() isCurrent;
  final int pageSize;
  FirebaseChatCursor? _requested;
  int _generation = 0;
  FirebaseChatController(this.gateway, this.binding, this.isCurrent, {this.pageSize = 20})
      : super(const FirebaseChatState());
  bool get _current => mounted && isCurrent();

  Future<void> refresh({FirebaseChatCursor? after, bool head = false}) async {
    if (!_current || state.busy) return;
    final requested = head ? null : after ?? _requested;
    _requested = requested; // Preserve failed older cursor for explicit retry.
    final generation = ++_generation;
    final delivery = state.delivery;
    final verify = state.verifyBeforeRetry;
    state = FirebaseChatState(busy: true, delivery: delivery, verifyBeforeRetry: verify);
    try {
      final page = await gateway!.read(binding.groupId, pageSize: pageSize, after: requested);
      if (!_current || generation != _generation) return;
      page.validate(binding, pageSize, requested);
      state = FirebaseChatState(page: page, delivery: delivery,
          verifyBeforeRetry: requested != null && verify);
    } catch (error) {
      if (_current && generation == _generation) {
        state = FirebaseChatState(error: chatError(error), delivery: delivery, verifyBeforeRetry: verify);
      }
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseChatState();
    }
  }

  Future<FirebaseChatDelivery> send(String text) async {
    if (!_current || state.busy || state.verifyBeforeRetry) return FirebaseChatDelivery.notAttempted;
    final generation = ++_generation;
    state = const FirebaseChatState(busy: true); // No stale history or optimistic bubble.
    var acknowledged = false;
    try {
      chatText(text);
      await gateway!.send(binding.groupId, text);
      acknowledged = true;
      if (!_current || generation != _generation) return FirebaseChatDelivery.notAttempted;
      _requested = null;
      final page = await gateway!.read(binding.groupId, pageSize: pageSize);
      if (!_current || generation != _generation) return FirebaseChatDelivery.notAttempted;
      page.validate(binding, pageSize, null);
      state = FirebaseChatState(page: page, delivery: FirebaseChatDelivery.acknowledged);
    } catch (error) {
      if (!_current || generation != _generation) return FirebaseChatDelivery.notAttempted;
      final uncertain = error is FirebaseChatDeliveryUncertain;
      state = FirebaseChatState(
        delivery: acknowledged ? FirebaseChatDelivery.acknowledged : uncertain
            ? FirebaseChatDelivery.uncertain : FirebaseChatDelivery.notAttempted,
        verifyBeforeRetry: uncertain,
        error: acknowledged ? 'Message write acknowledged; history refresh unavailable. Refresh newest messages.'
            : uncertain ? chatUncertainMessage : chatError(error));
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseChatState();
    }
    return _current ? state.delivery : FirebaseChatDelivery.notAttempted;
  }

  Future<String?> report(String messageId, FirebaseReportReason reason, String details) async {
    if (!_current || state.busy) return 'Ready Firebase session required.';
    final generation = ++_generation;
    final delivery = state.delivery, verify = state.verifyBeforeRetry;
    state = FirebaseChatState(busy: true, delivery: delivery, verifyBeforeRetry: verify);
    try {
      assignmentSegment(messageId);
      reportDetails(details);
      await gateway!.report(binding.groupId, messageId, reason, details);
      if (!_current || generation != _generation) return 'Firebase account changed.';
      state = FirebaseChatState(delivery: delivery, verifyBeforeRetry: verify);
      return null; // Only an acknowledged transaction reaches confirmation.
    } catch (error) {
      final message = error is FormatException ? error.message
          : 'Report confirmation unavailable. Refresh and check before retrying.';
      if (_current && generation == _generation) {
        state = FirebaseChatState(error: message, delivery: delivery, verifyBeforeRetry: verify);
      }
      return message;
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseChatState();
    }
  }
  void cancelPending() {
    final generation = ++_generation; // Cancel immediately, no lifecycle notification.
    Future.microtask(() {
      if (mounted && generation == _generation) state = const FirebaseChatState();
    });
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseChatProvider = StateNotifierProvider.autoDispose
    .family<FirebaseChatController, FirebaseChatState, FirebaseChatBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  try {
    assignmentSegment(binding.uid);
    assignmentSegment(binding.groupId);
    boundedPageSize(20);
  } on FormatException {
    return FirebaseChatController(null, binding, () => false);
  }
  if (!sessionBinding.$1 || sessionBinding.$2 != binding.uid || !current()) {
    return FirebaseChatController(null, binding, () => false);
  }
  return FirebaseChatController(ref.watch(firebaseChatGatewayProvider), binding, current);
});