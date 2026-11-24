import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../../core/config/backend_config.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_assignments/data/firestore_assignments_gateway.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_group_reminder_models.dart';
import '../data/firebase_native_notifications.dart';
import '../data/firebase_reminder_delivery.dart';
import '../data/firebase_reminder_models.dart';
import '../data/firebase_reminder_planner.dart';
import '../data/firestore_group_reminders_gateway.dart';
import '../data/firestore_reminders_gateway.dart';

class FirebaseDeviceRemindersState {
  final bool busy, enabled;
  final int scheduled, skipped, truncated;
  final List<FirebaseReminderRegistration> registrations;
  final String? error;
  const FirebaseDeviceRemindersState(
      {this.busy = false,
      this.enabled = false,
      this.scheduled = 0,
      this.skipped = 0,
      this.truncated = 0,
      this.registrations = const [],
      this.error});
}

class FirebaseDeviceRemindersController
    extends StateNotifier<FirebaseDeviceRemindersState> {
  final bool supported;
  final FirebaseReminderDelivery delivery;
  final FirebaseReminderDeviceStore store;
  final String? Function() currentUid;
  final Future<FirebaseReminderRecord?> Function() readPreferences;
  final Future<FirebaseGroupReminderSnapshot> Function(String) readSchedule;
  final Future<FirebaseAssignmentsResult> Function(FirebaseAssignmentsScope)
      readAssignments;
  final tz.Location location;
  final DateTime Function() clock;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _observedSession = false;
  FirebaseDeviceRemindersController(
      {required this.supported,
      required this.delivery,
      required this.store,
      required this.currentUid,
      required this.readPreferences,
      required this.readSchedule,
      required this.readAssignments,
      required this.location,
      required this.clock})
      : super(const FirebaseDeviceRemindersState());
  void _check(String uid, int generation) {
    if (!mounted || generation != _generation || currentUid() != uid) {
      throw StateError('Device reminder account changed.');
    }
  }

  Future<void> _run(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> sessionChanged(String? uid,
      {bool signedOut = false, bool observed = true}) {
    if (!supported) return Future.value();
    _observedSession = _observedSession || observed;
    ++_generation;
    final generation = _generation;
    if (mounted) state = const FirebaseDeviceRemindersState();
    final cleanup = delivery.invalidate();
    return _run(() async {
      try {
        await cleanup;
        final enabledUid = await store.enabledUid();
        if (signedOut ||
            (uid != null && enabledUid != null && enabledUid != uid)) {
          await store.setEnabledUid(null);
        }
        if (!mounted || generation != _generation) return;
        state = const FirebaseDeviceRemindersState();
        if (uid != null) {
          await _refresh(uid, generation, requestPermission: false);
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          state = const FirebaseDeviceRemindersState(
              error: 'Device reminder cleanup failed. Retry before enabling.');
        }
      }
    });
  }

  Future<void> refresh() {
    if (!_observedSession) return Future.value();
    final uid = currentUid(), generation = _generation;
    if (!supported || uid == null) return Future.value();
    return _run(() => _refresh(uid, generation, requestPermission: false));
  }

  Future<void> enable() {
    _observedSession = true;
    final uid = currentUid(), generation = _generation;
    if (!supported || uid == null) return Future.value();
    return _run(() => _refresh(uid, generation, requestPermission: true));
  }

  Future<void> disable() {
    ++_generation;
    final generation = _generation, cleanup = delivery.invalidate();
    return _run(() async {
      try {
        await cleanup;
        await store.setEnabledUid(null);
        if (mounted && generation == _generation) {
          state =
              FirebaseDeviceRemindersState(registrations: state.registrations);
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          state = FirebaseDeviceRemindersState(
              registrations: state.registrations,
              error: 'Could not verify device cancellation. Retry disable.');
        }
      }
    });
  }

  Future<void> suspend() {
    if (!supported) return Future.value();
    ++_generation;
    return delivery.invalidate().catchError((Object _) {
      if (mounted) {
        state = const FirebaseDeviceRemindersState(
            error: 'Device cancellation failed. Retry disable.');
      }
    });
  }

  Future<void> register(FirebaseReminderRegistration value,
      {bool remove = false}) {
    final uid = currentUid(), generation = _generation;
    if (!supported || uid == null) return Future.value();
    return _run(() async {
      try {
        _check(uid, generation);
        final registrations = await store.registrations(uid);
        _check(uid, generation);
        registrations.removeWhere(
            (item) => item.groupId == value.groupId && item.week == value.week);
        if (!remove) registrations.add(value);
        if (registrations.length > 8) {
          throw const FormatException('At most eight device weeks.');
        }
        planFirebaseReminders(
            uid: uid,
            preferences: FirebaseReminderPreferences.defaults,
            weeks: [
              FirebaseReminderWeek(
                  groupId: value.groupId,
                  weekNumber: value.week,
                  confirmedMondayUtc: value.mondayUtc,
                  schedule: null,
                  assignments: [])
            ],
            nowUtc: clock(),
            location: location);
        await store.saveRegistrations(uid, registrations);
        _check(uid, generation);
        await _refresh(uid, generation, requestPermission: false);
      } catch (error) {
        var cleanupFailed = false;
        if (mounted && generation == _generation) {
          try {
            await delivery.invalidate();
            await store.setEnabledUid(null);
          } catch (_) {
            cleanupFailed = true;
          }
        }
        if (mounted && generation == _generation) {
          state = FirebaseDeviceRemindersState(
              registrations: state.registrations,
              error: cleanupFailed
                  ? 'Could not verify device cancellation. Retry Disable on this device.'
                  : error is FormatException
                      ? error.message
                      : 'Device week registration failed.');
        }
      }
    });
  }

  Future<void> _refresh(String uid, int generation,
      {required bool requestPermission}) async {
    var registrations = <FirebaseReminderRegistration>[];
    try {
      _check(uid, generation);
      state = FirebaseDeviceRemindersState(
          busy: true, registrations: state.registrations);
      registrations = await store.registrations(uid);
      _check(uid, generation);
      final enabled = await store.enabledUid();
      _check(uid, generation);
      if (!requestPermission && enabled != uid) {
        state = FirebaseDeviceRemindersState(
            registrations: List.unmodifiable(registrations));
        return;
      }
      final record = await readPreferences();
      _check(uid, generation);
      if (record == null || record.uid != uid) {
        throw const FormatException(
            'Save and verify personal reminder preferences first.');
      }
      if (!record.preferences.dailyVerseEnabled &&
          !record.preferences.readingReminderEnabled) {
        await delivery.invalidate();
        await store.setEnabledUid(null);
        _check(uid, generation);
        state = FirebaseDeviceRemindersState(
            registrations: List.unmodifiable(registrations));
        return;
      }
      final weeks = <FirebaseReminderWeek>[];
      if (record.preferences.readingReminderEnabled) {
        for (final registration in registrations) {
          final schedule = await readSchedule(registration.groupId);
          _check(uid, generation);
          if (schedule.uid != uid || schedule.groupId != registration.groupId) {
            throw const FormatException('Group reminder scope mismatch.');
          }
          final scope = (
            uid: uid,
            groupId: registration.groupId,
            memberUid: uid,
            week: registration.week
          );
          final assignments = await readAssignments(scope);
          _check(uid, generation);
          if (assignments.group.id != scope.groupId ||
              assignments.self.uid != uid ||
              assignments.member.uid != uid) {
            throw const FormatException('Own assignments required.');
          }
          if (assignments.group.archived) continue;
          weeks.add(FirebaseReminderWeek(
              groupId: scope.groupId,
              weekNumber: scope.week,
              confirmedMondayUtc: registration.mondayUtc,
              schedule: schedule.record?.schedule,
              assignments: assignments.assignments.where((row) => row.activeFor(assignments.member))));
        }
      }
      final plan = planFirebaseReminders(
          uid: uid,
          preferences: record.preferences,
          weeks: weeks,
          nowUtc: clock(),
          location: location);
      _check(uid, generation);
      await delivery.apply(uid, plan, requestPermission: requestPermission);
      _check(uid, generation);
      await store.setEnabledUid(uid);
      _check(uid, generation);
      state = FirebaseDeviceRemindersState(
          enabled: true,
          scheduled: plan.items.length,
          skipped: plan.skippedAssignments,
          truncated: plan.truncated,
          registrations: List.unmodifiable(registrations));
    } catch (error) {
      if (!mounted || generation != _generation) return;
      var cleanupFailed = false;
      try {
        await delivery.invalidate();
        await store.setEnabledUid(null);
      } catch (_) {
        cleanupFailed = true;
      }
      if (mounted && generation == _generation) {
        state = FirebaseDeviceRemindersState(
            registrations: List.unmodifiable(registrations),
            error: cleanupFailed
                ? 'Could not verify device cancellation. Retry Disable on this device.'
                : error is FormatException
                    ? error.message
                    : 'Device reminders paused. Verify permissions, session and server data, then enable again.');
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(delivery.invalidate().catchError((Object _) {}));
    super.dispose();
  }
}

bool get firebaseNativeReminderPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
final firebaseDeviceRemindersProvider = StateNotifierProvider<
    FirebaseDeviceRemindersController, FirebaseDeviceRemindersState>((ref) {
  tz_data.initializeTimeZones();
  final location = tz.getLocation('Asia/Kolkata');
  String? uid() {
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
            ref.read(firebaseAuthGatewayProvider).currentUser?.uid ==
                session.user?.uid
        ? session.user!.uid
        : null;
  }

  final supported =
      ref.read(backendConfigProvider).mode == BackendMode.firebase &&
          firebaseNativeReminderPlatform;
  final controller = FirebaseDeviceRemindersController(
      supported: supported,
      delivery: FirebaseReminderDelivery(
          FirebaseAndroidNotificationDriver(
              FlutterLocalNotificationsPlugin(), location),
          SharedFirebaseNotificationJournal(),
          uid),
      store: SharedFirebaseReminderDeviceStore(),
      currentUid: uid,
      readPreferences: () => ref.read(firebaseRemindersGatewayProvider).read(),
      readSchedule: (group) =>
          ref.read(firebaseGroupRemindersGatewayProvider).read(group),
      readAssignments: (scope) =>
          ref.read(firebaseAssignmentsGatewayProvider).read(scope),
      location: location,
      clock: () => DateTime.now().toUtc());
  if (supported) unawaited(controller.sessionChanged(null, observed: false));
  return controller;
});

void reconcileFirebaseDeviceReminders(Ref ref, {required bool busy}) {
  if (!firebaseNativeReminderPlatform ||
      ref.read(backendConfigProvider).mode != BackendMode.firebase) {
    return;
  }
  final controller = ref.read(firebaseDeviceRemindersProvider.notifier);
  unawaited(busy ? controller.suspend() : controller.refresh());
}
