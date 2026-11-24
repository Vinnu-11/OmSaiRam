import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../../firebase_assignments/providers/firebase_assignments_provider.dart';
import '../../firebase_tasks/providers/firebase_tasks_provider.dart';
import '../../firebase_group_progress/providers/firebase_group_progress_provider.dart';
import '../../firebase_chat/providers/firebase_chat_provider.dart';
import '../../firebase_highlights/providers/firebase_highlights_provider.dart';
import '../../firebase_moderation/providers/firebase_moderation_provider.dart';
import '../data/firebase_membership_models.dart';
import '../data/firestore_membership_gateway.dart';
import '../../firebase_reminders/providers/firebase_device_reminders_provider.dart';

typedef FirebaseMembershipBinding = ({String uid, String groupId});

class FirebaseMembershipState {
  final bool busy, acknowledged, verifyBeforeRetry;
  final String? targetUid, error;
  const FirebaseMembershipState({this.busy = false, this.acknowledged = false,
    this.verifyBeforeRetry = false, this.targetUid, this.error});
}

class FirebaseMembershipController extends StateNotifier<FirebaseMembershipState> {
  final FirebaseMembershipGateway Function() gateway;
  final FirebaseMembershipBinding binding;
  final bool Function() isCurrent;
  final void Function() clearDetail, invalidateData;
  final Future<String?> Function() reloadDetail;
  final Set<String> _completed = {};
  FirebaseMembershipController(this.gateway, this.binding, this.isCurrent,
      this.clearDetail, this.invalidateData, this.reloadDetail)
      : super(const FirebaseMembershipState());
  bool get _current => mounted && isCurrent();

  Future<bool> depart(String targetUid, FirebaseDepartureReason reason) => _change(targetUid, reason);
  Future<bool> restore(FirebaseDeparture baseline) => _change(baseline.uid, FirebaseDepartureReason.removed, restoration: baseline);
  Future<bool> _change(String targetUid, FirebaseDepartureReason reason, {FirebaseDeparture? restoration}) async {
    final operation = restoration == null ? 'departure:$targetUid' : 'restore:$targetUid:${restoration.revision}';
    final label = restoration == null ? 'Departure' : 'Restoration';
    if (!_current || state.busy || state.verifyBeforeRetry || _completed.contains(operation)) return false;
    state = FirebaseMembershipState(busy: true, targetUid: targetUid);
    clearDetail(); // Roster, group and invite secrets disappear BEFORE awaiting.
    var acknowledged = false;
    try {
      if (restoration != null && restoration.groupId != binding.groupId) {
        throw const FormatException('Restoration group mismatch.');
      }
      if (reason == FirebaseDepartureReason.left && targetUid != binding.uid) {
        throw const FormatException('Self leave must target the current account.');
      }
      if (restoration != null) {
        await gateway().restore(restoration);
      } else if (reason == FirebaseDepartureReason.left) {
        await gateway().leave(binding.groupId);
      } else {
        await gateway().remove(binding.groupId, targetUid);
      }
      acknowledged = true;
      if (!_current) return false;
      _completed.add(operation);
      if (restoration != null) _completed.remove('departure:$targetUid');
      state = FirebaseMembershipState(busy: true, acknowledged: true, targetUid: targetUid);
      invalidateData();
      // Leaving must not attempt a now-forbidden detail read. The groups list
      // refreshes on navigation. Removal always restarts at the roster head.
      final error = reason == FirebaseDepartureReason.removed ? await reloadDetail() : null;
      if (!_current) return false;
      state = FirebaseMembershipState(acknowledged: true, targetUid: targetUid,
        error: error == null ? null : '$label write acknowledged; roster refresh unavailable. Refresh manually. Do not repeat the write.');
      return true;
    } catch (error) {
      if (!_current) {
        return false;
      }
      state = FirebaseMembershipState(acknowledged: acknowledged, targetUid: targetUid,
        verifyBeforeRetry: !acknowledged && error is! FormatException,
        error: acknowledged ? '$label write acknowledged; roster refresh unavailable. Do not repeat the write.'
          : '$label not confirmed. Refresh current membership before another attempt. No automatic retry.');
      return acknowledged;
    } finally {
      if (mounted && state.busy) state = const FirebaseMembershipState();
    }
  }
  void verifiedRefresh() {
    if (_current && !state.busy) {
      state = FirebaseMembershipState(
        acknowledged: state.acknowledged, targetUid: state.targetUid, error: state.error);
    }
  }
}

final firebaseMembershipProvider = StateNotifierProvider.autoDispose.family<
    FirebaseMembershipController, FirebaseMembershipState, FirebaseMembershipBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() => active && sessionBinding.$1 && sessionBinding.$2 == binding.uid &&
      auth.currentUser?.uid == binding.uid;
  final groupScope = (uid: binding.uid, groupId: binding.groupId);
  final controller = FirebaseMembershipController(
    () => ref.read(firebaseMembershipGatewayProvider), binding, current,
    () => ref.read(firebaseGroupsProvider(groupScope).notifier).clearForDeparture(),
    () {
      ref.invalidate(firebaseGroupsProvider((uid: binding.uid, groupId: null)));
      // Clear all in-memory session family variants (member/week/item/cursor).
      // No SDK deletion; content is bundled and not user/group data. Existing
      // screens still require their next server read to authorize access.
      ref.invalidate(firebaseAssignmentsProvider);
      ref.invalidate(firebaseTasksProvider);
      ref.invalidate(firebaseGroupProgressProvider);
      ref.invalidate(firebaseChatProvider);
      ref.invalidate(firebaseHighlightsProvider);
      ref.invalidate(firebaseModerationProvider);
      ref.invalidate(firebaseTargetModerationProvider);
      ref.invalidate(firebaseModerationRoleProvider);
    },
    () async {
      final controller = ref.read(firebaseGroupsProvider(groupScope).notifier);
      await controller.refresh();
      return current() ? ref.read(firebaseGroupsProvider(groupScope)).error : 'Account changed.';
    });
  controller.addListener(
      (next) => reconcileFirebaseDeviceReminders(ref, busy: next.busy),
      fireImmediately: false);
  return controller;
});