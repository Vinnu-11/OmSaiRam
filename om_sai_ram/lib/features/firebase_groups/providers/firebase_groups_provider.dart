import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_member_display/data/firestore_member_display_gateway.dart';
import '../data/firebase_group_models.dart';
import '../data/firestore_groups_gateway.dart';

typedef FirebaseGroupsScope = ({String uid, String? groupId});

class FirebaseGroupsState {
  final bool busy;
  final String? error;
  final FirebasePage<FirebaseGroupEntry>? groups;
  final FirebaseGroupDetail? detail;
  final FirebaseGroupInvite? issued;
  const FirebaseGroupsState({this.busy = false, this.error, this.groups,
      this.detail, this.issued});
}

String groupsError(Object error) {
  if (error is FormatException) return error.message;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'This was not allowed. The invite may have expired or been cancelled, '
        'you may already be in this group, or your role may have changed. Please try again.';
  }
  return 'Could not reach the group. Check your internet connection and try again.';
}

class FirebaseGroupsController extends StateNotifier<FirebaseGroupsState> {
  final FirebaseGroupsGateway? gateway;
  final FirebaseGroupsScope scope;
  final bool Function() isCurrent;
  /// Shares the account name with a group just created or joined. Best effort:
  /// the name can also be set later under Members.
  final Future<void> Function(String groupId)? shareName;
  int _generation = 0;
  FirebaseGroupsController(this.gateway, this.scope, this.isCurrent, {this.shareName})
      : super(const FirebaseGroupsState());

  bool _valid(int generation) => mounted && generation == _generation && isCurrent();

  /// Clear before awaiting, including tokens. Discard uncancellable SDK futures
  /// when disposed, session becomes unready, or the UID changes. [keep] holds
  /// the already-verified group detail on screen during invite actions.
  Future<T?> _run<T>(Future<T> Function() action,
      FirebaseGroupsState Function(T) success, {FirebaseGroupDetail? keep}) async {
    if (!mounted || state.busy || !isCurrent()) return null;
    final generation = ++_generation;
    state = FirebaseGroupsState(busy: true, detail: keep);
    try {
      final result = await action();
      if (!_valid(generation)) return null;
      state = success(result);
      return result;
    } catch (error) {
      if (_valid(generation)) state = FirebaseGroupsState(error: groupsError(error), detail: keep);
      return null;
    }
  }

  Future<void> refresh({String? cursor}) async {
    await _run(() async {
      if (scope.groupId == null) {
        return FirebaseGroupsState(groups: await gateway!.listGroups(cursor: cursor));
      }
      return FirebaseGroupsState(detail: await gateway!.detail(scope.groupId!, cursor: cursor));
    }, (value) => value);
  }

  void clearForDeparture() {
    if (!mounted) return;
    ++_generation;
    state = const FirebaseGroupsState();
  }

  Future<String> _withName(Future<String> request) async {
    final groupId = await request;
    try {
      if (isCurrent()) await shareName?.call(groupId);
    } catch (_) {
      // The group exists; members see "Member 2" until a name is shared.
    }
    return groupId;
  }

  Future<String?> create(String name, String description, int width, int start,
          {String mode = 'chapter_wise'}) =>
      _run(() => _withName(gateway!.create(FirebaseGroupDraft(name, description,
          chaptersPerWeek: width, startChapter: start, mode: mode))), (_) => const FirebaseGroupsState());

  Future<String?> join(String text) => _run(
      () async => _withName(gateway!.join(inviteFromText(text))), (_) => const FirebaseGroupsState());

  Future<void> issue() async {
    final detail = state.detail;
    if (detail == null || !isGroupLeader(detail.self.role)) return;
    await _run(() => gateway!.issueInvite(detail.group.id),
        (invite) => FirebaseGroupsState(detail: detail, issued: invite), keep: detail);
  }

  Future<void> revoke() async {
    final detail = state.detail;
    final issued = state.issued;
    if (detail == null || issued == null || !isGroupLeader(detail.self.role)) return;
    await _run(() async {
      await gateway!.revokeInvite(issued.token);
      // Recheck current server membership and roster before redisplaying.
      return gateway!.detail(detail.group.id);
    }, (value) => FirebaseGroupsState(detail: value), keep: detail);
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}

final firebaseGroupsProvider = StateNotifierProvider.autoDispose.family<
    FirebaseGroupsController, FirebaseGroupsState, FirebaseGroupsScope>((ref, scope) {
  final binding = ref.watch(firebaseSessionProvider.select(
      (session) => (session.ready, session.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  // Never instantiate SDK groups dependencies for an unready session.
  if (!binding.$1 || binding.$2 != scope.uid || auth.currentUser?.uid != scope.uid) {
    return FirebaseGroupsController(null, scope, () => false);
  }
  final gateway = ref.watch(firebaseGroupsGatewayProvider);
  return FirebaseGroupsController(gateway, scope, () {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == scope.uid &&
        auth.currentUser?.uid == scope.uid;
  }, shareName: (groupId) async {
    final name = ref.read(firebaseSessionProvider).displayName?.trim() ?? '';
    if (name.isEmpty) return;
    await ref.read(firebaseMemberDisplayGatewayProvider)
        .publish(groupId, name.length > 100 ? name.substring(0, 100) : name);
  });
});