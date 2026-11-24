import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_native_notifications.dart';
import '../providers/firebase_device_reminders_provider.dart';

class FirebaseDeviceReminderHost extends ConsumerStatefulWidget {
  final Widget child;
  const FirebaseDeviceReminderHost({super.key, required this.child});
  @override
  ConsumerState<FirebaseDeviceReminderHost> createState() =>
      _FirebaseDeviceReminderHostState();
}

class _FirebaseDeviceReminderHostState
    extends ConsumerState<FirebaseDeviceReminderHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(firebaseDeviceRemindersProvider.notifier).refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(firebaseDeviceRemindersProvider);
    return widget.child;
  }
}

class FirebaseDeviceReminderControls extends ConsumerStatefulWidget {
  final String uid;
  const FirebaseDeviceReminderControls({super.key, required this.uid});
  @override
  ConsumerState<FirebaseDeviceReminderControls> createState() =>
      _FirebaseDeviceReminderControlsState();
}

class _FirebaseDeviceReminderControlsState
    extends ConsumerState<FirebaseDeviceReminderControls> {
  final _group = TextEditingController(),
      _week = TextEditingController(text: '1');
  DateTime? _monday;
  String? _error;
  bool _active = true;
  FirebaseDeviceRemindersController get _controller =>
      ref.read(firebaseDeviceRemindersProvider.notifier);
  bool get _current =>
      _active &&
      mounted &&
      ref.read(firebaseSessionProvider).ready &&
      ref.read(firebaseSessionProvider).user?.uid == widget.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.uid;
  @override
  void initState() {
    super.initState();
    if (firebaseNativeReminderPlatform) {
      Future.microtask(() {
        if (_current) unawaited(_controller.sessionChanged(widget.uid));
      });
    }
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _group.dispose();
    _week.dispose();
    super.dispose();
  }

  Future<void> _pickMonday() async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final selected = await showDatePicker(
        context: context,
        initialDate: _monday ?? monday,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31),
        selectableDayPredicate: (date) => date.weekday == DateTime.monday);
    if (_current && selected != null) setState(() => _monday = selected);
  }

  Future<void> _add() async {
    if (!_current) return;
    try {
      final date = _monday, week = int.tryParse(_week.text);
      if (date == null || week == null) {
        throw const FormatException('Select a Monday and a valid week number.');
      }
      final anchor = tz.TZDateTime(
              tz.getLocation('Asia/Kolkata'), date.year, date.month, date.day)
          .toUtc();
      final registration =
          FirebaseReminderRegistration(_group.text.trim(), week, anchor);
      setState(() => _error = null);
      await _controller.register(registration);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _enable() async {
    if (!_current) return;
    final registrations =
        ref.read(firebaseDeviceRemindersProvider).registrations;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Enable reminders on this device?'),
                content: SingleChildScrollView(
                    child: Text('Account: ${widget.uid}\nAsia/Kolkata (IST)\n'
                        'Saved personal preferences; ${registrations.length} confirmed group weeks.\n'
                        'Only the next 64 future slots are queued. Android may delay delivery.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Enable on device'))
                ]));
    if (confirmed == true &&
        _current &&
        identical(registrations,
            ref.read(firebaseDeviceRemindersProvider).registrations)) {
      await _controller.enable();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!firebaseNativeReminderPlatform) {
      return const Text(
          'Device delivery: Android only. Web preferences remain storage-only.');
    }
    final state = ref.watch(firebaseDeviceRemindersProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(),
      Text('This device', style: Theme.of(context).textTheme.titleMedium),
      Text(state.enabled
          ? 'On: ${state.scheduled} queued; ${state.skipped} skipped; ${state.truncated} deferred.'
          : 'Device reminders: off'),
      const Text(
          'IST. Seven future verse days; refresh when the app resumes. No server push.'),
      if (state.busy) const LinearProgressIndicator(),
      if (state.error != null)
        Text(state.error!, key: const Key('device-reminders-error')),
      if (_error != null) Text(_error!),
      TextField(
          controller: _group,
          decoration: const InputDecoration(labelText: 'Group ID')),
      TextField(
          controller: _week,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Week (1-10000)')),
      OutlinedButton.icon(
          onPressed: state.busy ? null : _pickMonday,
          icon: const Icon(Icons.date_range),
          label: Text(_monday == null
              ? 'Confirm week Monday (IST)'
              : 'Monday: ${_monday!.year}-${_monday!.month}-${_monday!.day} (IST)')),
      OutlinedButton.icon(
          onPressed: state.busy ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('Add device week')),
      for (final registration in state.registrations)
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${registration.groupId} / week ${registration.week}'),
            subtitle: Text(
                'Monday UTC instant: ${registration.mondayUtc.toIso8601String()}'),
            trailing: IconButton(
                tooltip: 'Remove device week',
                icon: const Icon(Icons.delete_outline),
                onPressed: state.busy
                    ? null
                    : () {
                        if (_current) {
                          unawaited(
                              _controller.register(registration, remove: true));
                        }
                      })),
      Wrap(spacing: 8, children: [
        FilledButton.icon(
            key: const Key('device-reminders-enable'),
            onPressed: state.busy ? null : _enable,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Enable on this device')),
        OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () {
                    if (_current) unawaited(_controller.refresh());
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh queue')),
        OutlinedButton.icon(
            onPressed: () {
              if (_current) unawaited(_controller.disable());
            },
            icon: const Icon(Icons.notifications_off_outlined),
            label: const Text('Disable on this device')),
      ]),
    ]);
  }
}
