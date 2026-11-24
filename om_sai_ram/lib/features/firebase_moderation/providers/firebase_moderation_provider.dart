import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_chat/data/firebase_chat_models.dart';
import '../data/firebase_moderation_models.dart';
import '../data/firestore_moderation_gateway.dart';

typedef FirebaseModerationRoleBinding = ({String uid, String groupId});
final firebaseModerationRoleProvider = FutureProvider.autoDispose
    .family<FirebaseGroupRole?, FirebaseModerationRoleBinding>((ref, binding) async {
  ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  var active = true;
  ref.onDispose(() => active = false);
  if (!current()) return null;
  try {
    assignmentSegment(binding.uid);
    assignmentSegment(binding.groupId);
    final role = await ref.read(firebaseModerationGatewayProvider).role(binding.groupId);
    return active && current() ? role : null;
  } catch (_) { return null; } // No stale admin link or private-profile fallback.
});

class FirebaseModerationState {
  final bool busy, acknowledged, verifyBeforeRetry;
  final FirebaseModerationPage? page;
  final String? error;
  const FirebaseModerationState({this.busy = false, this.acknowledged = false,
    this.verifyBeforeRetry = false, this.page, this.error});
}

class FirebaseModerationController extends StateNotifier<FirebaseModerationState> {
  final FirebaseModerationGateway? gateway;
  final FirebaseModerationBinding binding;
  final bool Function() isCurrent;
  final int pageSize;
  final FirebaseModerationTargetKind kind;
  int _generation = 0;
  String? _requested;
  FirebaseModerationController(this.gateway, this.binding, this.isCurrent,
      {this.pageSize = 20, this.kind = FirebaseModerationTargetKind.messages})
    : super(const FirebaseModerationState());
  bool get _current => mounted && isCurrent();
  Future<FirebaseModerationPage> _read(String? after) async {
    final page = await gateway!.read(binding.groupId, binding.messageId, pageSize: pageSize, after: after, kind: kind);
    if (_current) page.validate(binding, pageSize, after, expectedKind: kind);
    return page;
  }
  Future<void> refresh({String? after, bool head = false}) async {
    if (!_current) {
      if (mounted) state = const FirebaseModerationState();
      return;
    }
    if (state.busy) return;
    final generation = ++_generation;
    final ack = state.acknowledged, verify = state.verifyBeforeRetry;
    _requested = head ? null : after ?? _requested;
    state = FirebaseModerationState(busy: true, acknowledged: ack, verifyBeforeRetry: verify);
    try {
      final page = await _read(_requested);
      if (!_current || generation != _generation) return;
      state = FirebaseModerationState(page: page, acknowledged: ack);
    } catch (error) {
      if (_current && generation == _generation) {
        state = FirebaseModerationState(acknowledged: ack, verifyBeforeRetry: verify,
          error: moderationError(error));
      }
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseModerationState();
    }
  }
  Future<void> resolve(String reporter, FirebaseReportStatus status) =>
    _write(() => gateway!.resolve(binding.groupId, binding.messageId, reporter, status, kind: kind));
  Future<void> remove(FirebaseReportReason reason) =>
    _write(() => gateway!.remove(binding.groupId, binding.messageId, reason, kind: kind));
  Future<void> _write(Future<void> Function() operation) async {
    if (!_current) {
      if (mounted) state = const FirebaseModerationState();
      return;
    }
    if (state.busy || state.verifyBeforeRetry) return;
    final generation = ++_generation;
    state = const FirebaseModerationState(busy: true); // Clear all downloaded data before action.
    var acknowledged = false;
    try {
      moderationScope(binding);
      await operation();
      acknowledged = true;
      if (!_current || generation != _generation) return;
      _requested = null;
      final page = await _read(null);
      if (!_current || generation != _generation) return;
      state = FirebaseModerationState(page: page, acknowledged: true);
    } catch (error) {
      if (_current && generation == _generation) {
        state = FirebaseModerationState(acknowledged: acknowledged,
          verifyBeforeRetry: !acknowledged && error is! FormatException,
          error: acknowledged ? 'Write acknowledged; server refresh unavailable. Refresh to verify current access and data. Do not repeat the write.' :
            '${moderationError(error)}${error is FormatException ? '' : ' Write confirmation unavailable; refresh before retrying. No automatic retry.'}');
      }
    } finally {
      if (mounted && generation == _generation && state.busy) state = const FirebaseModerationState();
    }
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseModerationProvider = StateNotifierProvider.autoDispose.family<
  FirebaseModerationController, FirebaseModerationState, FirebaseModerationBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  try { moderationScope(binding); }
  on FormatException { return FirebaseModerationController(null, binding, () => false); }
  if (!sessionBinding.$1 || sessionBinding.$2 != binding.uid || !current()) {
    return FirebaseModerationController(null, binding, () => false);
  }
  return FirebaseModerationController(ref.watch(firebaseModerationGatewayProvider), binding, current);
});

/// Kind is part of provider identity, even when IDs are identical across collections.
final firebaseTargetModerationProvider = StateNotifierProvider.autoDispose.family<
  FirebaseModerationController, FirebaseModerationState, FirebaseModerationTargetBinding>((ref, target) {
  final binding = target.scope;
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  final roleBinding = (uid: binding.uid, groupId: binding.groupId);
  final role = ref.watch(firebaseModerationRoleProvider(roleBinding)).asData?.value;
  var active = true;
  ref.onDispose(() => active = false);
  ref.listen(firebaseModerationRoleProvider(roleBinding), (_, __) => active = false);
  bool current() {
    // No ref reads from a suspended provider generation during dependency changes.
    return active && sessionBinding.$1 && sessionBinding.$2 == binding.uid &&
      auth.currentUser?.uid == binding.uid && role == FirebaseGroupRole.admin;
  }
  try { moderationScope(binding); }
  on FormatException { return FirebaseModerationController(null, binding, () => false, kind: target.kind); }
  final controller = FirebaseModerationController(ref.watch(firebaseModerationGatewayProvider), binding, current, kind: target.kind);
  if (current()) Future.microtask(() { if (current()) controller.refresh(head: true); });
  return controller;
});