import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../data/firebase_highlight_models.dart';
import '../data/firestore_highlights_gateway.dart';

class FirebaseHighlightsState {
  final bool busy, verifyBeforeRetry;
  final FirebaseHighlightsPage? page;
  final String? error;
  final FirebaseHighlightDelivery delivery;
  const FirebaseHighlightsState({this.busy = false, this.verifyBeforeRetry = false,
    this.page, this.error, this.delivery = FirebaseHighlightDelivery.notAttempted});
}
class FirebaseHighlightsController extends StateNotifier<FirebaseHighlightsState> {
  final FirebaseHighlightsGateway? gateway;
  final FirebaseHighlightsBinding binding;
  final bool Function() isCurrent;
  final int pageSize;
  FirebaseHighlightCursor? _requested;
  int _generation = 0;
  FirebaseHighlightsController(this.gateway, this.binding, this.isCurrent, {this.pageSize = 20})
      : super(const FirebaseHighlightsState());
  bool get _current => mounted && isCurrent();
  Future<void> refresh({FirebaseHighlightCursor? after, bool head = false}) async {
    if (!_current || state.busy) return;
    final requested = head ? null : after ?? _requested;
    _requested = requested;
    final generation = ++_generation;
    final delivery = state.delivery, verify = state.verifyBeforeRetry;
    state = FirebaseHighlightsState(busy: true, delivery: delivery, verifyBeforeRetry: verify);
    try {
      final page = await gateway!.read(binding.groupId, pageSize: pageSize, after: requested);
      if (!_current || generation != _generation) return;
      page.validate(binding, pageSize, requested);
      state = FirebaseHighlightsState(page: page, delivery: delivery,
        verifyBeforeRetry: requested != null && verify);
    } catch (error) {
      if (_current && generation == _generation) {
        state = FirebaseHighlightsState(error: highlightsError(error), delivery: delivery,
          verifyBeforeRetry: verify);
      }
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseHighlightsState();
    }
  }
  Future<FirebaseHighlightDelivery> send(int chapterNumber, int paragraphIndex,
      String quote, String text) async {
    if (!_current || state.busy || state.verifyBeforeRetry) return FirebaseHighlightDelivery.notAttempted;
    final generation = ++_generation;
    state = const FirebaseHighlightsState(busy: true);
    var acknowledged = false;
    try {
      final draft = FirebaseHighlightDraft(chapterNumber, paragraphIndex, quote, text);
      await gateway!.send(binding.groupId, draft);
      acknowledged = true;
      if (!_current || generation != _generation) return FirebaseHighlightDelivery.notAttempted;
      _requested = null;
      final page = await gateway!.read(binding.groupId, pageSize: pageSize);
      if (!_current || generation != _generation) return FirebaseHighlightDelivery.notAttempted;
      page.validate(binding, pageSize, null);
      state = FirebaseHighlightsState(page: page, delivery: FirebaseHighlightDelivery.acknowledged);
    } catch (error) {
      if (!_current || generation != _generation) return FirebaseHighlightDelivery.notAttempted;
      final uncertain = error is FirebaseHighlightDeliveryUncertain;
      state = FirebaseHighlightsState(
        delivery: acknowledged ? FirebaseHighlightDelivery.acknowledged : uncertain
          ? FirebaseHighlightDelivery.uncertain : FirebaseHighlightDelivery.notAttempted,
        verifyBeforeRetry: uncertain,
        error: acknowledged ? 'Highlight write acknowledged; head refresh unavailable. Refresh newest highlights.'
          : uncertain ? highlightUncertainMessage : highlightsError(error));
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseHighlightsState();
    }
    return _current ? state.delivery : FirebaseHighlightDelivery.notAttempted;
  }
  Future<String?> report(String id, FirebaseHighlightReportReason reason, String details) async {
    if (!_current || state.busy) return 'Ready Firebase session required.';
    final generation = ++_generation;
    final delivery = state.delivery, verify = state.verifyBeforeRetry;
    state = FirebaseHighlightsState(busy: true, delivery: delivery, verifyBeforeRetry: verify);
    try {
      assignmentSegment(id);
      highlightReportDetails(details);
      await gateway!.report(binding.groupId, id, reason, details);
      if (!_current || generation != _generation) return 'Firebase account changed.';
      state = FirebaseHighlightsState(delivery: delivery, verifyBeforeRetry: verify);
      return null;
    } catch (error) {
      final message = error is FormatException ? error.message
        : 'Report confirmation unavailable. Refresh and check before retrying.';
      if (_current && generation == _generation) {
        state = FirebaseHighlightsState(error: message, delivery: delivery, verifyBeforeRetry: verify);
      }
      return message;
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseHighlightsState();
    }
  }
  void cancelPending() {
    _requested = null;
    final generation = ++_generation;
    Future.microtask(() {
      if (mounted && generation == _generation) state = const FirebaseHighlightsState();
    });
  }
  @override
  void dispose() { _requested = null; ++_generation; super.dispose(); }
}
final firebaseHighlightsProvider = StateNotifierProvider.autoDispose
    .family<FirebaseHighlightsController, FirebaseHighlightsState, FirebaseHighlightsBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  try { assignmentSegment(binding.uid); assignmentSegment(binding.groupId); }
  on FormatException { return FirebaseHighlightsController(null, binding, () => false); }
  if (!sessionBinding.$1 || sessionBinding.$2 != binding.uid || !current()) {
    return FirebaseHighlightsController(null, binding, () => false);
  }
  return FirebaseHighlightsController(ref.watch(firebaseHighlightsGatewayProvider), binding, current);
});