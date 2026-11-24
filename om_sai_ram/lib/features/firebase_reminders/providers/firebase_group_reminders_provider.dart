import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../data/firebase_group_reminder_models.dart';
import '../data/firestore_group_reminders_gateway.dart';
import 'firebase_device_reminders_provider.dart';

typedef FirebaseGroupReminderScope = ({String uid, String groupId});

class FirebaseGroupRemindersState {
  final bool busy, loaded, acknowledged, verifyBeforeSave, dirty;
  final FirebaseGroupReminderSnapshot? snapshot;
  final FirebaseGroupReminderDraft? draft, retainedDraft;
  final String? error;
  const FirebaseGroupRemindersState(
      {this.busy = false,
      this.loaded = false,
      this.acknowledged = false,
      this.verifyBeforeSave = false,
      this.dirty = false,
      this.snapshot,
      this.draft,
      this.retainedDraft,
      this.error});
  bool get canEdit =>
      loaded &&
      !busy &&
      !verifyBeforeSave &&
      (snapshot?.canEdit ?? false) &&
      (snapshot?.record?.revision ?? 0) < groupReminderMaximumRevision &&
      draft != null;
}

class FirebaseGroupRemindersController
    extends StateNotifier<FirebaseGroupRemindersState> {
  final FirebaseGroupReminderScope scope;
  final FirebaseGroupRemindersGateway Function() gateway;
  final bool Function() isCurrent;
  int _generation = 0;
  FirebaseGroupRemindersController(this.scope, this.gateway, this.isCurrent)
      : super(const FirebaseGroupRemindersState());
  bool get _current => mounted && isCurrent();
  bool _valid(int generation) => _current && generation == _generation;
  void _clearIfChanged() {
    if (mounted && !isCurrent()) state = const FirebaseGroupRemindersState();
  }

  void _validate(FirebaseGroupReminderSnapshot snapshot) {
    if (snapshot.uid != scope.uid || snapshot.groupId != scope.groupId) {
      throw const FormatException('Schedule response scope/account mismatch.');
    }
  }

  Future<void> load() async {
    if (!_current) {
      _clearIfChanged();
      return;
    }
    if (state.busy) return;
    final generation = ++_generation, acknowledged = state.acknowledged;
    final retained = state.retainedDraft ??
        ((state.verifyBeforeSave || state.dirty) ? state.draft : null);
    state = FirebaseGroupRemindersState(
        busy: true, acknowledged: acknowledged, retainedDraft: retained);
    try {
      final snapshot = await gateway().read(scope.groupId);
      if (!_valid(generation)) return;
      _validate(snapshot);
      final draft =
          snapshot.record?.schedule ?? FirebaseGroupReminderDraft.defaults;
      state = FirebaseGroupRemindersState(
          loaded: true,
          snapshot: snapshot,
          draft: draft,
          retainedDraft:
              retained != null && !mapEquals(retained.toData(), draft.toData())
                  ? retained
                  : null);
    } catch (error) {
      if (_valid(generation)) {
        state = FirebaseGroupRemindersState(
            acknowledged: acknowledged,
            retainedDraft: retained,
            verifyBeforeSave: true,
            error: acknowledged
                ? 'Schedule saved; server reload failed. Retry the read, not the write.'
                : groupsError(error));
      }
    } finally {
      _clearIfChanged();
    }
  }

  void edit(FirebaseGroupReminderDraft draft) {
    if (!_current) {
      _clearIfChanged();
      return;
    }
    if (!state.canEdit) return;
    state = FirebaseGroupRemindersState(
        loaded: true,
        snapshot: state.snapshot,
        draft: draft,
        dirty: true,
        retainedDraft: state.retainedDraft);
  }

  void restoreDraft() {
    if (!_current) {
      _clearIfChanged();
      return;
    }
    final draft = state.retainedDraft;
    if (draft != null && state.canEdit) {
      edit(draft);
      state = FirebaseGroupRemindersState(
          loaded: true, snapshot: state.snapshot, draft: draft, dirty: true);
    }
  }

  void discardDraft() {
    if (!_current) {
      _clearIfChanged();
      return;
    }
    if (!state.busy) {
      state = FirebaseGroupRemindersState(
          loaded: state.loaded,
          snapshot: state.snapshot,
          draft: state.draft,
          dirty: state.dirty,
          verifyBeforeSave: state.verifyBeforeSave,
          acknowledged: state.acknowledged,
          error: state.error);
    }
  }

  Future<bool> save() async {
    if (!_current) {
      _clearIfChanged();
      return false;
    }
    if (!state.canEdit) return false;
    final baseline = state.snapshot!,
        draft = state.draft!,
        generation = ++_generation;
    state = FirebaseGroupRemindersState(busy: true, draft: draft);
    var acknowledged = false;
    try {
      await gateway().save(baseline, draft);
      acknowledged = true;
      if (!_valid(generation)) return false;
      final snapshot = await gateway().read(scope.groupId);
      if (!_valid(generation)) return false;
      _validate(snapshot);
      if (snapshot.record == null ||
          snapshot.record!.revision <= (baseline.record?.revision ?? 0)) {
        throw const FormatException(
            'Saved schedule not confirmed by server reload.');
      }
      state = FirebaseGroupRemindersState(
          loaded: true,
          acknowledged: true,
          snapshot: snapshot,
          draft: snapshot.record!.schedule);
      return true;
    } catch (error) {
      if (!_valid(generation)) return false;
      state = FirebaseGroupRemindersState(
          draft: draft,
          retainedDraft: draft,
          acknowledged: acknowledged,
          verifyBeforeSave: true,
          error: acknowledged
              ? 'Schedule saved; server reload failed. Retry the read, not the write.'
              : '${groupsError(error)} Save not acknowledged; server state may have changed. Draft retained. Read server before retrying.');
      return acknowledged;
    } finally {
      _clearIfChanged();
    }
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}

final firebaseGroupRemindersProvider = StateNotifierProvider.autoDispose.family<
    FirebaseGroupRemindersController,
    FirebaseGroupRemindersState,
    FirebaseGroupReminderScope>((ref, scope) {
  ref.listenSelf((previous, next) => reconcileFirebaseDeviceReminders(ref, busy: next.busy));
  final binding = ref.watch(firebaseSessionProvider
      .select((session) => (session.ready, session.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active &&
        binding.$1 &&
        binding.$2 == scope.uid &&
        session.ready &&
        session.user?.uid == scope.uid &&
        auth.currentUser?.uid == scope.uid;
  }

  return FirebaseGroupRemindersController(
      scope, () => ref.read(firebaseGroupRemindersGatewayProvider), current);
});
