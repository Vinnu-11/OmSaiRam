import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../data/firebase_reminder_models.dart';
import '../data/firestore_reminders_gateway.dart';
import 'firebase_device_reminders_provider.dart';

class FirebaseRemindersState {
  final bool busy, loaded, acknowledged, verifyBeforeSave;
  final FirebaseReminderPreferences? draft;
  final FirebaseReminderRecord? record;
  final String? error;
  const FirebaseRemindersState({this.busy = false, this.loaded = false,
    this.acknowledged = false, this.verifyBeforeSave = false, this.draft, this.record, this.error});
  bool get canEdit => loaded && !busy && !verifyBeforeSave && draft != null;
}

class FirebaseRemindersController extends StateNotifier<FirebaseRemindersState> {
  final String uid;
  final FirebaseRemindersGateway Function() gateway;
  final bool Function() isCurrent;
  int _generation = 0;
  FirebaseRemindersController(this.uid, this.gateway, this.isCurrent)
      : super(const FirebaseRemindersState());
  bool get _current => mounted && isCurrent();
  bool _valid(int generation) => _current && generation == _generation;
  void _validate(FirebaseReminderRecord? record) {
    if (record != null && record.uid != uid) throw const FormatException('Reminder response account mismatch.');
  }
  void _clearIfChanged() {
    if (mounted && !isCurrent()) state = const FirebaseRemindersState();
  }
  Future<void> load() async {
    if (!_current) { _clearIfChanged(); return; }
    if (state.busy) return;
    final generation = ++_generation;
    final acknowledged = state.acknowledged;
    final retained = state.verifyBeforeSave ? state.draft : null;
    state = FirebaseRemindersState(busy: true, acknowledged: acknowledged, draft: retained);
    try {
      final record = await gateway().read();
      if (!_valid(generation)) return;
      _validate(record);
      state = FirebaseRemindersState(loaded: true, record: record,
        draft: record?.preferences ?? FirebaseReminderPreferences.defaults);
    } catch (error) {
      if (_valid(generation)) {
        state = FirebaseRemindersState(draft: retained,
          acknowledged: acknowledged, verifyBeforeSave: true,
          error: acknowledged ? 'Preferences saved; server reload failed. Retry server read, not the write.' : groupsError(error));
      }
    } finally { _clearIfChanged(); }
  }
  void edit(FirebaseReminderPreferences preferences) {
    if (!_current) { _clearIfChanged(); return; }
    if (!state.canEdit) return;
    state = FirebaseRemindersState(loaded: true, record: state.record, draft: preferences);
  }
  Future<bool> save() async {
    if (!_current) { _clearIfChanged(); return false; }
    if (!state.canEdit) return false;
    final draft = state.draft!;
    final generation = ++_generation;
    state = FirebaseRemindersState(busy: true, draft: draft);
    var acknowledged = false;
    try {
      await gateway().save(draft);
      acknowledged = true;
      if (!_valid(generation)) return false;
      state = FirebaseRemindersState(busy: true, acknowledged: true, draft: draft);
      final record = await gateway().read();
      if (!_valid(generation)) return false;
      _validate(record);
      if (record == null) throw const FormatException('Saved preferences missing from server reload.');
      state = FirebaseRemindersState(loaded: true, acknowledged: true,
        record: record, draft: record.preferences);
      return true;
    } catch (error) {
      if (!_valid(generation)) return false;
      state = FirebaseRemindersState(draft: draft, acknowledged: acknowledged, verifyBeforeSave: true,
        error: acknowledged
          ? 'Preferences saved; server reload failed. Retry server read, not the write.'
          : '${groupsError(error)} Save not acknowledged; server state is uncertain. Draft retained. Retry server read before saving again.');
      return acknowledged;
    } finally { _clearIfChanged(); }
  }
  @override
  void dispose() { ++_generation; super.dispose(); }
}

final firebaseRemindersProvider = StateNotifierProvider.autoDispose.family<
    FirebaseRemindersController, FirebaseRemindersState, String>((ref, uid) {
  ref.listenSelf((previous, next) => reconcileFirebaseDeviceReminders(ref, busy: next.busy));
  final binding = ref.watch(firebaseSessionProvider.select((s) => (s.ready, s.user?.uid)));
  final auth = ref.watch(firebaseAuthGatewayProvider);
  var active = true;
  ref.onDispose(() => active = false);
  bool current() {
    final session = ref.read(firebaseSessionProvider);
    return active && binding.$1 && binding.$2 == uid && session.ready &&
      session.user?.uid == uid && auth.currentUser?.uid == uid;
  }
  return FirebaseRemindersController(uid, () => ref.read(firebaseRemindersGatewayProvider), current);
});