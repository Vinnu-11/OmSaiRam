import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../../firebase_assignments/providers/firebase_assignments_provider.dart';
import '../../firebase_tasks/providers/firebase_tasks_provider.dart';
import '../../firebase_group_progress/providers/firebase_group_progress_provider.dart';
import '../../firebase_chat/providers/firebase_chat_provider.dart';
import '../../firebase_highlights/providers/firebase_highlights_provider.dart';
import '../../firebase_moderation/providers/firebase_moderation_provider.dart';
import '../../firebase_reminders/providers/firebase_device_reminders_provider.dart';
import '../data/firebase_group_admin_models.dart';
import '../data/firestore_group_admin_gateway.dart';

class FirebaseGroupAdminState {
  final bool busy, acknowledged, verifyBeforeRetry;
  final String? error;
  final FirebaseGroupSettingsSnapshot? snapshot;
  const FirebaseGroupAdminState({this.busy = false, this.acknowledged = false,
    this.verifyBeforeRetry = false, this.error, this.snapshot});
}

class FirebaseGroupAdminController extends StateNotifier<FirebaseGroupAdminState> {
  final FirebaseGroupAdminBinding binding;
  final FirebaseGroupAdminGateway Function() gateway;
  final bool Function() isCurrent;
  final void Function() clearDetail, invalidateData;
  final Future<String?> Function() reloadDetail;
  int _generation = 0;
  FirebaseGroupAdminController(this.binding, this.gateway, this.isCurrent,
      this.clearDetail, this.invalidateData, this.reloadDetail)
      : super(const FirebaseGroupAdminState());
  bool get _current => mounted && isCurrent();
  bool _valid(int generation) => _current && generation == _generation;

  Future<void> load() async {
    if (!_current || state.busy) return;
    final generation = ++_generation;
    final acknowledged = state.acknowledged;
    state = FirebaseGroupAdminState(busy: true, acknowledged: acknowledged);
    try {
      final snapshot = await gateway().load(binding.groupId);
      if (_valid(generation)) state = FirebaseGroupAdminState(snapshot: snapshot);
    } catch (error) {
      if (_valid(generation)) {
        state = FirebaseGroupAdminState(acknowledged: acknowledged,
          verifyBeforeRetry: true, error: groupsError(error));
      }
    } finally {
      if (mounted && !isCurrent()) state = const FirebaseGroupAdminState();
    }
  }

  Future<bool> save(FirebaseGroupSettingsSnapshot baseline, FirebaseGroupSettingsDraft draft) {
    if (baseline.group.id != binding.groupId) return Future.value(false);
    return _write(() => gateway().save(baseline, draft), settings: true);
  }
  Future<bool> changeRole(String targetUid, FirebaseGroupRole expected, FirebaseGroupRole next) =>
      _write(() => gateway().changeRole(binding.groupId, targetUid, expected, next));
  Future<bool> setArchived(FirebaseGroupSettingsSnapshot baseline, bool archived) {
    if (baseline.group.id != binding.groupId) return Future.value(false);
    return _write(() => gateway().setArchived(baseline, archived), settings: true);
  }
  Future<bool> transferOwnership(FirebaseGroupSettingsSnapshot baseline, FirebaseMembership successor) {
    if (baseline.group.id != binding.groupId || baseline.group.ownerUid != binding.uid) return Future.value(false);
    return _write(() => gateway().transferOwnership(baseline, successor));
  }
    Future<bool> addMember(String targetUid) =>
      _write(() => gateway().addMember(binding.groupId, targetUid));

  Future<bool> _write(Future<void> Function() action, {bool settings = false}) async {
    if (!_current || state.busy || state.acknowledged || state.verifyBeforeRetry) return false;
    final generation = ++_generation;
    state = const FirebaseGroupAdminState(busy: true);
    clearDetail(); // Cancel old roster generations BEFORE the first await.
    var acknowledged = false;
    try {
      await action();
      acknowledged = true;
      if (!_valid(generation)) return false;
      state = const FirebaseGroupAdminState(busy: true, acknowledged: true);
      invalidateData(); // No invalidation/destructive cache work on failure.
      final error = await reloadDetail();
      if (!_valid(generation)) return false;
      if (error != null) throw StateError(error);
      final snapshot = settings ? await gateway().load(binding.groupId) : null;
      if (!_valid(generation)) return false;
      state = FirebaseGroupAdminState(acknowledged: true, snapshot: snapshot);
      return true;
    } catch (error) {
      if (!_valid(generation)) return false;
      state = FirebaseGroupAdminState(acknowledged: acknowledged,
        verifyBeforeRetry: !acknowledged,
        error: acknowledged
          ? 'Admin write acknowledged; server reload unavailable. Refresh manually. Do not repeat the write.'
          : '${groupsError(error)} Refresh server state before another attempt. No automatic retry.');
      return acknowledged;
    } finally {
      if (mounted && !isCurrent()) state = const FirebaseGroupAdminState();
    }
  }
  void verifiedRefresh() {
    if (_current && !state.busy) state = const FirebaseGroupAdminState();
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseGroupAdminProvider = StateNotifierProvider.autoDispose.family<
    FirebaseGroupAdminController, FirebaseGroupAdminState, FirebaseGroupAdminBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && sessionBinding.$1 && sessionBinding.$2 == binding.uid &&
      session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  final scope = (uid: binding.uid, groupId: binding.groupId);
  // Keep the roster controller alive across settings-route reload awaits,
  // without rebuilding this mutation controller on every roster state change.
  ref.listen(firebaseGroupsProvider(scope), (_, __) {});
  final controller = FirebaseGroupAdminController(binding, () => ref.read(firebaseGroupAdminGatewayProvider), current,
    () => ref.read(firebaseGroupsProvider(scope).notifier).clearForDeparture(),
    () {
      ref.invalidate(firebaseGroupsProvider((uid: binding.uid, groupId: null)));
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
      await ref.read(firebaseGroupsProvider(scope).notifier).refresh();
      if (!current()) return 'Account changed.';
      final state = ref.read(firebaseGroupsProvider(scope));
      return state.error ?? (state.detail == null ? 'Roster verification unavailable.' : null);
    });
  var previousBusy = false;
  controller.addListener((next) {
    if (previousBusy == next.busy) return;
    previousBusy = next.busy;
    reconcileFirebaseDeviceReminders(ref, busy: next.busy);
  }, fireImmediately: false);
  return controller;
});