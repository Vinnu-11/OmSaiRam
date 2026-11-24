import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/utc_schedule_date.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../data/firebase_assignment_models.dart';
import '../data/firestore_assignments_gateway.dart';
import '../../firebase_reminders/providers/firebase_device_reminders_provider.dart';

class FirebaseAssignmentsState {
  final bool busy;
  final bool acknowledged, verifyBeforeRetry;
  final String? error;
  final FirebaseAssignmentsResult? result;
  const FirebaseAssignmentsState({this.busy = false, this.acknowledged = false,
    this.verifyBeforeRetry = false, this.error, this.result});
}

String assignmentsError(Object error) {
  if (error is FormatException) return error.message;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Access denied. Refresh membership and retry. No cached or partial assignments are shown.';
  }
  return 'Assignments request failed. Check your session and network, then retry. No cached or partial assignments are shown.';
}

class FirebaseAssignmentsController
    extends StateNotifier<FirebaseAssignmentsState> {
  final FirebaseAssignmentsGateway? gateway;
  final FirebaseAssignmentsScope scope;
  final bool Function() isCurrent;
  int _generation = 0;
  FirebaseAssignmentsController(this.gateway, this.scope, this.isCurrent)
      : super(const FirebaseAssignmentsState());

  Future<void> _run({Future<void> Function()? write, bool creating = false}) async {
    if (!mounted || state.busy || !isCurrent()) return;
    if (creating && (state.acknowledged || state.verifyBeforeRetry)) return;
    final previous = state;
    var acknowledged = false;
    final generation = ++_generation;
    state = FirebaseAssignmentsState(busy: true, acknowledged: previous.acknowledged,
      verifyBeforeRetry: previous.verifyBeforeRetry);
    bool current() => mounted && generation == _generation && isCurrent();
    try {
      validateAssignmentsScope(scope);
      if (write != null) {
        await write();
        acknowledged = creating;
        if (!current()) return;
      }
      final result = await gateway!.read(scope);
      if (!current()) return;
      // Validate even injected gateway responses: never show another scope's data.
      if (result.group.id != scope.groupId ||
          result.self.uid != scope.uid ||
          result.member.uid != scope.memberUid ||
          result.assignments.length > 48 ||
          result.assignments.map((row) => row.unit.key).toSet().length !=
              result.assignments.length ||
          result.assignments.any((row) =>
              row.groupId != scope.groupId ||
              row.userId != scope.memberUid ||
              row.weekNumber != scope.week)) {
        throw const FormatException('Assignment response scope mismatch.');
      }
      state = FirebaseAssignmentsState(result: result, acknowledged: acknowledged);
    } catch (error) {
      if (current()) {
        state = FirebaseAssignmentsState(
          acknowledged: creating ? acknowledged : previous.acknowledged,
          verifyBeforeRetry: creating ? !acknowledged : previous.verifyBeforeRetry,
          error: creating && acknowledged
            ? 'Assignment write acknowledged; server reload unavailable. Reload assignments to verify. Do not repeat the write.'
            : assignmentsError(error));
      }
    } finally {
      // A UID mismatch without an auth event must not leave this controller sticky.
      if (mounted && generation == _generation && state.busy) {
        state = const FirebaseAssignmentsState();
      }
    }
  }

  Future<void> refresh() => _run();
  Future<void> create(FirebaseChapterUnit unit, {DateTime? scheduledDate}) {
    if (state.result?.group.archived ?? false) return Future.value();
    final role = state.result?.self.role;
    if (role != FirebaseGroupRole.admin &&
        role != FirebaseGroupRole.groupLead) {
      return Future.value();
    }
    return _run(creating: true, write: () => gateway!.create(scope, unit,
      scheduledDate: utcScheduleDate(scheduledDate)));
  }

  Future<void> updateStatus(
      FirebaseChapterUnit unit, FirebaseReadingStatus status) {
    if (scope.uid != scope.memberUid || state.result == null || state.result!.group.archived) {
      return Future.value();
    }
    if (state.result!.assignments.any((row) => row.unit.key == unit.key && !row.activeFor(state.result!.member))) return Future.value();
    return _run(write: () => gateway!.updateStatus(scope, unit, status));
  }

  Future<void> transition(FirebaseAssignment baseline, {required bool archived,
      required DateTime? scheduledDate, String? reassignTo}) {
    final result = state.result;
    if (result == null || result.group.archived ||
        ![FirebaseGroupRole.admin, FirebaseGroupRole.groupLead].contains(result.self.role) ||
        !result.assignments.contains(baseline)) {
      return Future.value();
    }
    return _run(creating: true, write: () => gateway!.transition(scope, baseline,
      archived: archived, scheduledDate: scheduledDate, reassignTo: reassignTo));
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}

final firebaseAssignmentsProvider = StateNotifierProvider.autoDispose.family<
    FirebaseAssignmentsController,
    FirebaseAssignmentsState,
    FirebaseAssignmentsScope>((ref, scope) {
  final binding =
      ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == scope.uid &&
        auth.currentUser?.uid == scope.uid;
  }

  final controller = !binding.$1 || binding.$2 != scope.uid || !current()
      ? FirebaseAssignmentsController(null, scope, () => false)
      : FirebaseAssignmentsController(
          ref.watch(firebaseAssignmentsGatewayProvider), scope, current);
  controller.addListener(
      (next) => reconcileFirebaseDeviceReminders(ref, busy: next.busy),
      fireImmediately: false);
  return controller;
});
