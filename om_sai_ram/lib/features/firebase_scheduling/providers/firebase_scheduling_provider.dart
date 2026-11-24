import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_reminders/providers/firebase_device_reminders_provider.dart';
import '../../../core/utils/utc_schedule_date.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../../firebase_assignments/providers/firebase_assignments_provider.dart';
import '../../firebase_tasks/providers/firebase_tasks_provider.dart';
import '../data/firebase_schedule_models.dart';
import '../data/firestore_scheduling_gateway.dart';

/// Capability local to this controller generation, never a claimed server role.
class FirebaseScheduleConfirmation {
  final FirebaseScheduleBinding binding;
  final int generation;
  final FirebaseSchedulePreview? preview;
  final FirebaseScheduleSettings settings;
  const FirebaseScheduleConfirmation._(this.binding, this.generation, this.settings, this.preview);
  bool get advancing => preview == null;
}

class FirebaseSchedulingState {
  final bool busy, acknowledged, uncertain;
  final String? error, outcome;
  final FirebaseScheduleHead? head;
  final FirebaseSchedulePreview? preview;
  final FirebaseScheduleSuggestion? suggestion;
  final List<String> selected;
  const FirebaseSchedulingState({this.busy = false, this.acknowledged = false, this.uncertain = false,
    this.error, this.outcome, this.head, this.preview, this.suggestion, this.selected = const []});
}

class FirebaseSchedulingController extends StateNotifier<FirebaseSchedulingState> {
  final FirebaseScheduleBinding binding;
  final FirebaseSchedulingGateway Function() gateway;
  final bool Function() isCurrent;
  final void Function() invalidateData;
  final Future<String?> Function() reloadDetail;
  int _generation = 0;
  FirebaseScheduleConfirmation? _confirmation;
  FirebaseSchedulingController(this.binding, this.gateway, this.isCurrent, this.invalidateData, this.reloadDetail)
    : super(const FirebaseSchedulingState());
  bool get _current => mounted && isCurrent();
  bool _valid(int generation) => _current && generation == _generation;
  bool get _editable => _current && !state.busy && !state.acknowledged && !state.uncertain && state.head != null;
  void _validateHead(FirebaseScheduleHead head) {
    validateScheduleBinding(binding);
    if (head.group.id != binding.groupId || head.actor.uid != binding.uid ||
        head.members.items.length > 50 || head.members.items.map((m) => m.uid).toSet().length != head.members.items.length) {
      throw const FormatException('Scheduling response scope mismatch.');
    }
    requireScheduler(head.actor);
    for (final member in head.members.items) { validateScheduleBinding((uid: member.uid, groupId: binding.groupId)); }
  }
  /// Only an explicit HEAD reload unlocks an uncertain/acknowledged write.
  Future<void> load({String? cursor}) async {
    if (!_current || state.busy || (cursor != null && !_editable)) return;
    final previous = state;
    final generation = ++_generation;
    _confirmation = null;
    state = FirebaseSchedulingState(busy: true, selected: previous.selected,
      acknowledged: previous.acknowledged, uncertain: previous.uncertain, outcome: previous.outcome);
    try {
      final head = await gateway().load(binding, cursor: cursor);
      if (!_valid(generation)) return;
      _validateHead(head);
      state = FirebaseSchedulingState(head: head, selected: previous.selected, outcome: previous.outcome,
        acknowledged: cursor == null ? false : previous.acknowledged,
        uncertain: cursor == null ? false : previous.uncertain);
    } catch (error) {
      if (_valid(generation)) {
        state = FirebaseSchedulingState(selected: previous.selected,
        acknowledged: previous.acknowledged, uncertain: previous.uncertain,
        outcome: previous.outcome, error: groupsError(error));
      }
    } finally { _clearOld(); }
  }
  void _clearOld() {
    if (mounted && !isCurrent()) { _confirmation = null; state = const FirebaseSchedulingState(); }
  }
  void edit() {
    if (!_editable) return;
    ++_generation; _confirmation = null;
    state = FirebaseSchedulingState(head: state.head, selected: state.selected, outcome: state.outcome);
  }
  void select(String uid, bool selected) {
    if (!_editable) return;
    final list = [...state.selected];
    if (selected) {
      if (!state.head!.members.items.any((member) => member.uid == uid) || list.contains(uid) || list.length == 50) return;
      list.add(uid); // Explicit selection order, not roster order.
    } else { list.remove(uid); }
    edit();
    state = FirebaseSchedulingState(head: state.head, selected: List.unmodifiable(list), outcome: state.outcome);
  }
  void move(String uid, int direction) {
    if (!_editable || (direction != -1 && direction != 1)) return;
    final list = [...state.selected], index = state.selected.indexOf(uid);
    final next = index + direction;
    if (index < 0 || next < 0 || next >= list.length) return;
    list[index] = list[next]; list[next] = uid;
    edit();
    state = FirebaseSchedulingState(head: state.head, selected: List.unmodifiable(list), outcome: state.outcome);
  }
  void rejectInput(String error) {
    if (!_editable) return;
    ++_generation; _confirmation = null;
    state = FirebaseSchedulingState(selected: state.selected, outcome: state.outcome, error: error);
  }
  Future<void> suggest({required int weeksAhead, required String mode, required String remainder,
      int? startChapter, DateTime? firstWeekDate, required Iterable<FirebaseScheduleHint> hints}) =>
    _generate(weeksAhead: weeksAhead, mode: mode, remainder: remainder, startChapter: startChapter,
      firstWeekDate: firstWeekDate, hints: hints);
  Future<void> preview({required int weeksAhead, required String mode, required String remainder,
      int? startChapter, DateTime? firstWeekDate}) =>
    _generate(weeksAhead: weeksAhead, mode: mode, remainder: remainder, startChapter: startChapter, firstWeekDate: firstWeekDate);
  Future<void> _generate({required int weeksAhead, required String mode, required String remainder,
      int? startChapter, DateTime? firstWeekDate, Iterable<FirebaseScheduleHint>? hints}) async {
    if (!_editable) return;
    final selected = state.selected;
    // Own the collection before any async boundary; hint values are immutable.
    final capturedHints = hints == null ? null : List<FirebaseScheduleHint>.unmodifiable(hints);
    final previous = state;
    final generation = ++_generation; _confirmation = null;
    state = FirebaseSchedulingState(busy: true, selected: selected, outcome: previous.outcome);
    try {
      final plan = FirebaseSchedulePlan(memberUids: selected, weeksAhead: weeksAhead,
        scheduleMode: mode, remainderMode: remainder, startChapter: startChapter,
        firstWeekDate: utcScheduleDate(firstWeekDate));
      // Fresh server authority/settings for every preview action. No cached role.
      final head = await gateway().load(binding);
      if (!_valid(generation)) return;
      _validateHead(head);
      final suggestion = capturedHints == null ? null : suggestFirebaseSchedule(head.settings, plan, capturedHints);
      final preview = suggestion?.preview ?? previewFirebaseSchedule(head.settings, plan);
      state = FirebaseSchedulingState(head: head, selected: selected, preview: preview,
        suggestion: suggestion, outcome: previous.outcome);
    } catch (error) {
      if (_valid(generation)) {
        state = FirebaseSchedulingState(selected: selected, error: groupsError(error), outcome: previous.outcome);
      }
    } finally { _clearOld(); }
  }
  FirebaseScheduleConfirmation? confirmation({bool advance = false}) {
    if (!_editable) return null;
    final head = state.head!;
    if (advance ? !isGroupLeader(head.actor.role) || head.group.currentWeek >= 10000
      : state.preview == null || state.preview!.commitBlock != null) {
      return null;
    }
    return _confirmation = FirebaseScheduleConfirmation._(binding, _generation,
      advance ? head.settings : state.preview!.settings, advance ? null : state.preview);
  }
  void cancel(FirebaseScheduleConfirmation confirmation) {
    if (identical(_confirmation, confirmation)) _confirmation = null;
  }
  bool canConfirm(FirebaseScheduleConfirmation confirmation) =>
    _editable && identical(_confirmation, confirmation) && confirmation.binding == binding &&
    confirmation.generation == _generation &&
    (!confirmation.advancing || isGroupLeader(state.head!.actor.role));
  Future<bool> confirm(FirebaseScheduleConfirmation confirmation) async {
    if (!canConfirm(confirmation)) return false;
    final advancing = confirmation.advancing;
    if (advancing && !isGroupLeader(state.head!.actor.role)) return false;
    final generation = ++_generation; _confirmation = null;
    final selected = state.selected;
    state = FirebaseSchedulingState(busy: true, selected: selected);
    var acknowledged = false;
    String? outcome;
    try {
      if (advancing) {
        final week = await gateway().advance(binding);
        if (!_valid(generation)) return false;
        acknowledged = true;
        if (week < 2 || week > 10000) throw const FormatException('Invalid advance response.');
        outcome = 'Week advance acknowledged: current week $week. No assignments generated.';
      } else {
        final preview = confirmation.preview!;
        await gateway().commit(binding, preview.settings, preview.plan);
        if (!_valid(generation)) return false;
        outcome = 'Schedule commit acknowledged: ${preview.assignments.length} assignments created. Group week unchanged.';
      }
      acknowledged = true;
      state = FirebaseSchedulingState(busy: true, acknowledged: true, selected: selected, outcome: outcome);
      invalidateData();
      final error = await reloadDetail();
      if (!_valid(generation)) return false;
      if (error != null) throw StateError(error);
      final head = await gateway().load(binding);
      if (!_valid(generation)) return false;
      _validateHead(head);
      state = FirebaseSchedulingState(acknowledged: true, head: head, selected: selected, outcome: outcome);
      return true;
    } catch (error) {
      if (!_valid(generation)) return false;
      state = FirebaseSchedulingState(acknowledged: acknowledged, uncertain: !acknowledged,
        selected: selected, outcome: outcome, error: acknowledged
          ? 'Write acknowledged; server reload failed. Do not repeat it. Explicitly reload server head before a new action.'
          : '${groupsError(error)} Outcome unverified. No blind retry: explicitly reload server head, inspect current week/assignments, then make a new preview/confirmation. Duplicate assignments abort a whole commit.');
      return acknowledged;
    } finally { _clearOld(); }
  }
  @override
  void dispose() { ++_generation; _confirmation = null; super.dispose(); }
}

final firebaseSchedulingProvider = StateNotifierProvider.autoDispose.family<
  FirebaseSchedulingController, FirebaseSchedulingState, FirebaseScheduleBinding>((ref, binding) {
  final sessionBinding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true; ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && sessionBinding.$1 && sessionBinding.$2 == binding.uid &&
      session.ready && session.user?.uid == binding.uid && auth.currentUser?.uid == binding.uid;
  }
  final scope = (uid: binding.uid, groupId: binding.groupId);
  // Do not initialize other SDK dependencies under an unready binding.
  if (current()) ref.listen(firebaseGroupsProvider(scope), (_, __) {});
  final controller = FirebaseSchedulingController(binding, () => ref.read(firebaseSchedulingGatewayProvider), current,
    () {
      ref.invalidate(firebaseGroupsProvider((uid: binding.uid, groupId: null)));
      ref.invalidate(firebaseAssignmentsProvider);
      ref.invalidate(firebaseTasksProvider);
      ref.read(firebaseGroupsProvider(scope).notifier).clearForDeparture();
    }, () async {
      await ref.read(firebaseGroupsProvider(scope).notifier).refresh();
      if (!current()) return 'Account changed.';
      final groups = ref.read(firebaseGroupsProvider(scope));
      return groups.error ?? (groups.detail == null ? 'Group reload unavailable.' : null);
    });
  controller.addListener(
      (next) => reconcileFirebaseDeviceReminders(ref, busy: next.busy),
      fireImmediately: false);
  return controller;
});