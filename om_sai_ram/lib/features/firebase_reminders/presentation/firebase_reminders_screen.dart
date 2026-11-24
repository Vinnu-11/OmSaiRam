import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_reminder_models.dart';
import '../providers/firebase_reminders_provider.dart';
import 'firebase_device_reminder_controls.dart';

class FirebaseRemindersScreen extends ConsumerWidget {
  const FirebaseRemindersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready || ref.watch(firebaseAuthGatewayProvider).currentUser?.uid != session.user?.uid) {
      return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    }
    return _ReminderWorkspace(key: ValueKey(session.user!.uid), uid: session.user!.uid);
  }
}

class _ReminderWorkspace extends ConsumerStatefulWidget {
  final String uid;
  const _ReminderWorkspace({super.key, required this.uid});
  @override
  ConsumerState<_ReminderWorkspace> createState() => _ReminderWorkspaceState();
}

class _ReminderWorkspaceState extends ConsumerState<_ReminderWorkspace> {
  FirebaseRemindersController get _controller => ref.read(firebaseRemindersProvider(widget.uid).notifier);
  bool get _current {
    final session = ref.read(firebaseSessionProvider);
    return mounted && session.ready && session.user?.uid == widget.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.uid;
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (_current) _controller.load(); });
  }
  void _edit(FirebaseReminderPreferences preferences) {
    if (_current) _controller.edit(preferences);
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseRemindersProvider(widget.uid));
    final draft = state.draft;
    return Scaffold(appBar: AppBar(title: const Text('Personal reminder preferences'),
      leading: IconButton(tooltip: 'Back to my account', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/me'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text(reminderPreferencesDisclosure, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const Text('India timezone: Asia/Kolkata (IST, UTC+05:30). One shared time for both preferences; not your device timezone.'),
          if (state.busy) const LinearProgressIndicator(),
          if (state.loaded && state.record == null)
            const Text('No saved preferences. Defaults are off / off at 09:00 and are unsaved.', key: Key('reminders-missing')),
          if (state.acknowledged)
            Text(state.record == null ? 'Save acknowledged; server values unavailable.' : 'Preferences saved and reloaded from server.',
              key: const Key('reminders-saved')),
          if (!state.acknowledged && state.record != null)
            const Text('Loaded saved preferences. Changes require explicit Save.'),
          if (state.error != null) ...[
            Text(state.error!, key: const Key('reminders-error')),
            if (draft != null) const Text('Unsaved draft retained; server state unverified. This is not a confirmed saved setting.'),
          ],
          OutlinedButton(onPressed: state.busy ? null : () { if (_current) _controller.load(); },
            child: Text(state.error == null ? 'Reload from server' : 'Retry server read')),
          if (draft != null) ...[
            SwitchListTile(title: const Text('Reading reminder preference'), value: draft.readingReminderEnabled,
              onChanged: state.canEdit ? (value) => _edit(draft.copyWith(readingReminderEnabled: value)) : null),
            SwitchListTile(title: const Text('Daily verse preference'), value: draft.dailyVerseEnabled,
              onChanged: state.canEdit ? (value) => _edit(draft.copyWith(dailyVerseEnabled: value)) : null),
            Text('Shared India time: ${draft.timeLabel}', key: const Key('reminders-time')),
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(key: ValueKey(('hour', draft.reminderHour)),
                initialValue: draft.reminderHour, decoration: const InputDecoration(labelText: 'Hour (00–23)'),
                items: [for (var i = 0; i < 24; i++) DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0')))],
                onChanged: state.canEdit ? (value) { if (value != null) _edit(draft.copyWith(reminderHour: value)); } : null)),
              const SizedBox(width: 16),
              Expanded(child: DropdownButtonFormField<int>(key: ValueKey(('minute', draft.reminderMinute)),
                initialValue: draft.reminderMinute, decoration: const InputDecoration(labelText: 'Minute (00–59)'),
                items: [for (var i = 0; i < 60; i++) DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0')))],
                onChanged: state.canEdit ? (value) { if (value != null) _edit(draft.copyWith(reminderMinute: value)); } : null)),
            ]),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: state.canEdit ? () { if (_current) _controller.save(); } : null,
            child: const Text('Save preferences')),
          const Text('Saving with both toggles off stores preferences; it does not delete or reset the document.'),
          FirebaseDeviceReminderControls(key: ValueKey(('device', widget.uid)), uid: widget.uid),
        ]))));
  }
}