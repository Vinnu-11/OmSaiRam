import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_group_reminder_models.dart';
import '../providers/firebase_group_reminders_provider.dart';

class FirebaseGroupRemindersScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseGroupRemindersScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      assignmentSegment(groupId);
    } catch (_) {
      return const Scaffold(body: Center(child: Text('Invalid group ID.')));
    }
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready ||
        ref.watch(firebaseAuthGatewayProvider).currentUser?.uid !=
            session.user?.uid) {
      return const Scaffold(
          body: Center(child: Text('Ready Firebase session required.')));
    }
    final scope = (uid: session.user!.uid, groupId: groupId);
    return _GroupReminderWorkspace(key: ValueKey(scope), scope: scope);
  }
}

class _GroupReminderWorkspace extends ConsumerStatefulWidget {
  final FirebaseGroupReminderScope scope;
  const _GroupReminderWorkspace({super.key, required this.scope});
  @override
  ConsumerState<_GroupReminderWorkspace> createState() =>
      _GroupReminderWorkspaceState();
}

class _GroupReminderWorkspaceState
    extends ConsumerState<_GroupReminderWorkspace> {
  bool _active = true;
  int _formEpoch = 0;
  String? _formError;
  FirebaseGroupRemindersController get _controller =>
      ref.read(firebaseGroupRemindersProvider(widget.scope).notifier);
  bool get _current {
    if (!_active || !mounted) return false;
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == widget.scope.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid ==
            widget.scope.uid;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (_current) _controller.load();
    });
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

  void _change(Map<String, dynamic> changes) {
    if (!_current) return;
    final state = ref.read(firebaseGroupRemindersProvider(widget.scope));
    if (!state.canEdit) return;
    try {
      _controller.edit(FirebaseGroupReminderDraft.parse(
          {...state.draft!.toData(), ...changes}));
      setState(() => _formError = null);
    } on FormatException catch (error) {
      setState(() {
        _formError = error.message;
        _formEpoch++;
      });
    }
  }

  Future<void> _pickTime(bool initial) async {
    if (!_current) return;
    final state = ref.read(firebaseGroupRemindersProvider(widget.scope));
    if (!state.canEdit) return;
    final draft = state.draft!;
    final selected = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: initial ? draft.initialHour : draft.deadlineHour,
            minute: initial ? draft.initialMinute : draft.deadlineMinute),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (!_current ||
        selected == null ||
        !identical(ref.read(firebaseGroupRemindersProvider(widget.scope)).draft,
            draft)) {
      return;
    }
    _change(initial
        ? {'initialHour': selected.hour, 'initialMinute': selected.minute}
        : {'deadlineHour': selected.hour, 'deadlineMinute': selected.minute});
  }

  Future<void> _save() async {
    if (!_current) return;
    final state = ref.read(firebaseGroupRemindersProvider(widget.scope));
    if (!state.canEdit || _formError != null) return;
    final draft = state.draft!, baseline = state.snapshot;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Save group reminder schedule?'),
                content: SingleChildScrollView(
                    child: Text('Group: ${widget.scope.groupId}\n'
                        'Initial: ${draft.initialLabel}\nDeadline: ${draft.deadlineLabel}\nAsia/Kolkata (IST)\n'
                        'Escalation intent: ${draft.escalationEnabled ? 'on' : 'off'}\n'
                        'Expected revision: ${baseline?.record?.revision ?? 0}\n\n$groupReminderDisclosure')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel')),
                  FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Confirm save'))
                ]));
    if (!_current || confirmed != true) return;
    final current = ref.read(firebaseGroupRemindersProvider(widget.scope));
    if (current.canEdit &&
        identical(current.draft, draft) &&
        identical(current.snapshot, baseline)) {
      await _controller.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupRemindersProvider(widget.scope)),
        draft = state.draft;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Group reminder schedule'),
            leading: IconButton(
                tooltip: 'Back to group',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(
                    '/groups/${Uri.encodeComponent(widget.scope.groupId)}'))),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child:
                        ListView(padding: const EdgeInsets.all(24), children: [
                      Text('Group: ${widget.scope.groupId}'),
                      const SizedBox(height: 12),
                      const Text(groupReminderDisclosure),
                      const SizedBox(height: 12),
                      const Text(
                          'India time: Asia/Kolkata (IST, UTC+05:30). Monday = day 0; Sunday = day 6.'),
                      if (state.busy) const LinearProgressIndicator(),
                      if (state.loaded && state.snapshot?.record == null)
                        const Text(
                            'No saved group schedule. Defaults are unsaved.',
                            key: Key('group-reminders-missing')),
                      if (state.snapshot?.record != null)
                        Text(
                            'Server revision: ${state.snapshot!.record!.revision}'),
                      if (state.acknowledged)
                        Text(
                            state.loaded
                                ? 'Schedule saved and reloaded from server.'
                                : 'Save acknowledged; server values unavailable.',
                            key: const Key('group-reminders-saved')),
                      if (state.error != null)
                        Text(state.error!,
                            key: const Key('group-reminders-error')),
                      if (_formError != null)
                        Text(_formError!,
                            key: const Key('group-reminders-validation'),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () {
                                  if (_current) {
                                    setState(() => _formError = null);
                                    _controller.load();
                                  }
                                },
                          icon: const Icon(Icons.refresh),
                          label: Text(state.error == null
                              ? 'Reload from server'
                              : 'Retry server read')),
                      if (state.retainedDraft != null) ...[
                        Text(
                            'Retained draft (not confirmed saved): ${state.retainedDraft!.initialLabel} to ${state.retainedDraft!.deadlineLabel}; escalation ${state.retainedDraft!.escalationEnabled ? 'on' : 'off'}.'),
                        Wrap(spacing: 12, children: [
                          OutlinedButton(
                              onPressed: state.canEdit
                                  ? () {
                                      if (_current) _controller.restoreDraft();
                                    }
                                  : null,
                              child: const Text('Restore retained draft')),
                          TextButton(
                              onPressed: state.busy
                                  ? null
                                  : () {
                                      if (_current) _controller.discardDraft();
                                    },
                              child: const Text('Discard retained draft'))
                        ]),
                      ],
                      if (state.loaded && draft != null) ...[
                        Text('Initial reminder: ${draft.initialLabel}'),
                        Text('Deadline: ${draft.deadlineLabel}'),
                        if (!(state.snapshot?.canEdit ?? false))
                          Text(
                              'Read-only. Escalation intent: ${draft.escalationEnabled ? 'on' : 'off'}. Only admins/leads can edit.'),
                        if (state.canEdit) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                              key: ValueKey((
                                'initial-day',
                                draft.initialDay,
                                _formEpoch
                              )),
                              initialValue: draft.initialDay,
                              decoration: const InputDecoration(
                                  labelText: 'Initial reminder day'),
                              isExpanded: true,
                              items: [
                                for (var day = 0; day < 7; day++)
                                  DropdownMenuItem(
                                      value: day,
                                      child: Text(FirebaseGroupReminderDraft
                                          .weekdays[day]))
                              ],
                              onChanged: (day) {
                                if (day != null) _change({'initialDay': day});
                              }),
                          OutlinedButton.icon(
                              key: const Key('group-reminders-initial-time'),
                              onPressed: () => _pickTime(true),
                              icon: const Icon(Icons.schedule),
                              label: const Text('Initial reminder time')),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                              key: ValueKey((
                                'deadline-day',
                                draft.deadlineDay,
                                _formEpoch
                              )),
                              initialValue: draft.deadlineDay,
                              decoration: const InputDecoration(
                                  labelText: 'Deadline day'),
                              isExpanded: true,
                              items: [
                                for (var day = 0; day < 7; day++)
                                  DropdownMenuItem(
                                      value: day,
                                      child: Text(FirebaseGroupReminderDraft
                                          .weekdays[day]))
                              ],
                              onChanged: (day) {
                                if (day != null) _change({'deadlineDay': day});
                              }),
                          OutlinedButton.icon(
                              key: const Key('group-reminders-deadline-time'),
                              onPressed: () => _pickTime(false),
                              icon: const Icon(Icons.schedule),
                              label: const Text('Deadline time')),
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Escalation intent'),
                              value: draft.escalationEnabled,
                              onChanged: (value) =>
                                  _change({'escalationEnabled': value})),
                          FilledButton.icon(
                              key: const Key('group-reminders-save'),
                              onPressed: _formError == null ? _save : null,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('Save schedule')),
                        ],
                      ],
                    ])))));
  }
}
