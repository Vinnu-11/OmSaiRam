import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_highlights/data/firebase_highlight_models.dart';
import '../../firebase_highlights/data/firestore_highlights_gateway.dart';
import '../../firebase_highlights/providers/firebase_highlights_provider.dart';
import '../data/firebase_assignment_models.dart';

typedef FirebaseReaderShareBinding = ({FirebaseAssignmentsScope scope, String unitKey});

class FirebaseReaderShareState {
  final bool busy, verifyBeforeRetry;
  final FirebaseHighlightDelivery delivery;
  final String? error;
  const FirebaseReaderShareState({this.busy = false, this.verifyBeforeRetry = false,
      this.delivery = FirebaseHighlightDelivery.notAttempted, this.error});
}

/// Retained for the container lifetime, not the route lifetime. Stores only
/// delivery control, never quotes, comments, paragraph anchors or server pages.
/// Separate from the manual highlights composer and its auto-disposed state.
class FirebaseReaderShareController extends StateNotifier<FirebaseReaderShareState> {
  final FirebaseHighlightsGateway gateway;
  final FirebaseHighlightsBinding binding;
  final void Function() acknowledged;
  FirebaseReaderShareController(this.gateway, this.binding, this.acknowledged)
      : super(const FirebaseReaderShareState());

  Future<FirebaseHighlightDelivery> send(FirebaseHighlightDraft draft,
      {required bool Function() current,
      required Future<void> Function() freshAccess}) async {
    if (!mounted || state.busy || state.verifyBeforeRetry || !current()) {
      return FirebaseHighlightDelivery.notAttempted;
    }
    state = const FirebaseReaderShareState(busy: true);
    var invoked = false, ack = false;
    try {
      await freshAccess();
      if (!mounted || !current()) return FirebaseHighlightDelivery.notAttempted;
      invoked = true;
      await gateway.send(binding.groupId, draft);
      ack = true;
      if (!mounted) {
        return FirebaseHighlightDelivery.acknowledged;
      }
      state = const FirebaseReaderShareState(busy: true,
          delivery: FirebaseHighlightDelivery.acknowledged);
      if (!current()) return FirebaseHighlightDelivery.acknowledged;
      acknowledged();
      final page = await gateway.read(binding.groupId);
      if (!mounted || !current()) return FirebaseHighlightDelivery.acknowledged;
      page.validate(binding, 20, null);
      state = const FirebaseReaderShareState(delivery: FirebaseHighlightDelivery.acknowledged);
    } catch (error) {
      if (!mounted) {
        return ack ? FirebaseHighlightDelivery.acknowledged
            : FirebaseHighlightDelivery.notAttempted;
      }
      // Unknown exceptions after invocation may mask a committed auto-ID write,
      // including SDK identity drift. Only a definite format rejection is safe.
      final uncertain = invoked && !ack && error is! FormatException;
      state = FirebaseReaderShareState(
          delivery: ack ? FirebaseHighlightDelivery.acknowledged : uncertain
              ? FirebaseHighlightDelivery.uncertain : FirebaseHighlightDelivery.notAttempted,
          verifyBeforeRetry: uncertain,
          error: ack ? 'Highlight write acknowledged; head refresh unavailable. Do not resend.'
              : uncertain ? highlightUncertainMessage
              : current() ? highlightsError(error) : null);
    } finally {
      if (mounted && state.busy) {
        state = FirebaseReaderShareState(delivery: ack
            ? FirebaseHighlightDelivery.acknowledged : state.delivery,
            verifyBeforeRetry: state.verifyBeforeRetry, error: state.error);
      }
    }
    return mounted ? state.delivery : FirebaseHighlightDelivery.notAttempted;
  }

  /// Explicit newest-page server verification only. Absence is NOT proof of
  /// non-delivery; the UI displays that warning and the returned head to review.
  Future<FirebaseHighlightsPage?> verifyHead(bool Function() current) async {
    if (!mounted || state.busy || !state.verifyBeforeRetry || !current()) return null;
    state = const FirebaseReaderShareState(busy: true, verifyBeforeRetry: true,
        delivery: FirebaseHighlightDelivery.uncertain);
    try {
      final page = await gateway.read(binding.groupId);
      if (!mounted || !current()) return null;
      page.validate(binding, 20, null);
      state = const FirebaseReaderShareState();
      return page;
    } catch (error) {
      if (mounted) {
        state = FirebaseReaderShareState(verifyBeforeRetry: true,
            delivery: FirebaseHighlightDelivery.uncertain,
            error: current() ? highlightsError(error) : null);
      }
      return null;
    } finally {
      if (mounted && state.busy) {
        state = const FirebaseReaderShareState(verifyBeforeRetry: true,
            delivery: FirebaseHighlightDelivery.uncertain);
      }
    }
  }
}

final firebaseReaderShareProvider = StateNotifierProvider.family<
    FirebaseReaderShareController, FirebaseReaderShareState,
    FirebaseReaderShareBinding>((ref, binding) {
  validateAssignmentsScope(binding.scope);
  final highlights = (uid: binding.scope.uid, groupId: binding.scope.groupId);
  return FirebaseReaderShareController(ref.watch(firebaseHighlightsGatewayProvider),
      highlights, () => ref.invalidate(firebaseHighlightsProvider(highlights)));
});