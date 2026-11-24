import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_chat/data/firestore_chat_gateway.dart';
import '../../firebase_groups/presentation/group_text.dart';
import '../../firebase_groups/presentation/group_widgets.dart';
import '../../firebase_tasks/data/firebase_task_models.dart';
import '../data/firebase_group_progress.dart';
import '../providers/firebase_group_progress_provider.dart';

class FirebaseGroupProgressScreen extends ConsumerWidget {
  final String groupId;
  final String? initialWeek;
  const FirebaseGroupProgressScreen(
      {super.key, required this.groupId, this.initialWeek});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready || session.user == null) {
      return const Scaffold(
          body: Center(child: Text('A ready Firebase session is required.')));
    }
    final binding = (
      uid: session.user!.uid,
      groupId: groupId,
      week: initialWeek == null ? 1 : int.tryParse(initialWeek!) ?? 0
    );
    try {
      validateGroupProgressBinding(binding);
    } on FormatException {
      return Scaffold(
          appBar: AppBar(
              leading: IconButton(
                tooltip: 'Back to group',
                onPressed: () =>
                    context.go('/groups/${Uri.encodeComponent(groupId)}'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: const Text('Reading this week')),
          body: const Center(
              child: Text('Select a valid group and week (1-10000).')));
    }
    return _ProgressWorkspace(key: ValueKey(binding), binding: binding);
  }
}

class _ProgressWorkspace extends ConsumerStatefulWidget {
  final FirebaseGroupProgressBinding binding;
  const _ProgressWorkspace({super.key, required this.binding});
  @override
  ConsumerState<_ProgressWorkspace> createState() => _ProgressWorkspaceState();
}

class _ProgressWorkspaceState extends ConsumerState<_ProgressWorkspace> {
  late final _week = TextEditingController(text: '${widget.binding.week}');
  final _form = GlobalKey<FormState>();
  bool _sending = false;
  String? _sendError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(firebaseGroupProgressProvider(widget.binding).notifier)
            .refresh();
      }
    });
  }

  @override
  void dispose() {
    _week.dispose();
    super.dispose();
  }

  bool _finished(FirebaseTaskSummary summary) =>
      summary.total > 0 && summary.completed == summary.total;

  String _status(FirebaseTaskSummary summary) {
    if (summary.total == 0) return ref.gt('nothingGiven');
    if (_finished(summary)) return ref.gt('finished');
    final parts = [
      if (summary.completed > 0)
        '${ref.gt('finished')}: ${summary.completed}/${summary.total}',
      if (summary.inProgress > 0)
        '${ref.gt('inProgress')}: ${summary.inProgress}',
      if (summary.notStarted > 0)
        '${ref.gt('notStarted')}: ${summary.notStarted}',
    ];
    return parts.join(' · ');
  }

  Future<void> _remind(List<String> names) async {
    final message = (await showDialog<String>(
                context: context,
                builder: (context) => _ReminderDialog(
                    initial:
                        ref.gtr('reminderText', {'names': names.join(', ')}),
                    title: ref.gtr('remind'),
                    cancel: ref.gtr('cancel'),
                    send: ref.gtr('send'))))
            ?.trim() ??
        '';
    if (message.isEmpty || !mounted) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(firebaseChatGatewayProvider)
          .send(widget.binding.groupId, message);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ref.gtr('reminderSent'))));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _sendError = error is FormatException
            ? error.message
            : 'The reminder could not be sent. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupProgressProvider(widget.binding));
    final controller =
        ref.read(firebaseGroupProgressProvider(widget.binding).notifier);
    final page = state.page;
    final names = {
      for (final entry
          in page?.members ?? const <FirebaseGroupProgressMember>[])
        if (entry.sharedName != null)
          entry.member.uid: entry.sharedName!.displayName
    };
    String name(int index) => groupMemberName(
        ref, names, page!.members[index].member.uid, index, widget.binding.uid);
    final waiting = [
      if (page != null)
        for (final (index, entry) in page.members.indexed)
          if (entry.summary.total > 0 && !_finished(entry.summary)) index,
    ];
    final finished =
        page?.members.where((entry) => _finished(entry.summary)).length ?? 0;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Reading this week'),
            leading: IconButton(
                tooltip: 'Back to group',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(
                    '/groups/${Uri.encodeComponent(widget.binding.groupId)}'))),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Form(
                      key: _form,
                      child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                                width: 160,
                                child: TextFormField(
                                    key: const Key('progress-week'),
                                    controller: _week,
                                    enabled: !state.busy,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Week number'),
                                    validator: (value) {
                                      final week = int.tryParse(value ?? '');
                                      return week == null ||
                                              week < 1 ||
                                              week > 10000
                                          ? 'Enter week 1-10000.'
                                          : null;
                                    })),
                            FilledButton.icon(
                                icon: const Icon(Icons.search),
                                label: const Text('Show this week'),
                                onPressed: state.busy
                                    ? null
                                    : () {
                                        if (!_form.currentState!.validate()) {
                                          return;
                                        }
                                        final week = int.parse(_week.text);
                                        if (week == widget.binding.week) {
                                          controller.refresh(restart: true);
                                        } else {
                                          context.go(
                                              '/groups/${Uri.encodeComponent(widget.binding.groupId)}/progress?week=$week');
                                        }
                                      }),
                            IconButton(
                                tooltip: 'Refresh',
                                icon: const Icon(Icons.refresh),
                                onPressed: state.busy
                                    ? null
                                    : () => controller.refresh()),
                            TextButton(
                                onPressed: state.busy
                                    ? null
                                    : () => controller.refresh(restart: true),
                                child: const Text('Back to the first members')),
                          ])),
                  if (state.busy) const LinearProgressIndicator(),
                  if (state.error != null)
                    Text(state.error!,
                        key: const Key('progress-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (page != null) ...[
                    const SizedBox(height: 16),
                    Text(
                        '${page.detail.group.name} · ${ref.gt('week', {
                              'n': widget.binding.week
                            })}',
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text(
                        ref.gt('haveRead',
                            {'done': finished, 'total': page.members.length}),
                        key: const Key('progress-page-totals'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    Text(ref.gt('notRead'),
                        style: Theme.of(context).textTheme.titleLarge),
                    if (waiting.isEmpty)
                      Text(ref.gt('everyoneRead'),
                          key: const Key('progress-everyone-read')),
                    for (final index in waiting)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.hourglass_empty),
                          title: Text(name(index)),
                          subtitle: Text(_status(page.members[index].summary))),
                    if (_sendError != null)
                      Text(_sendError!,
                          key: const Key('progress-reminder-error'),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (waiting.isNotEmpty && !page.detail.group.archived)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: FilledButton.icon(
                              key: const Key('progress-remind'),
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(56)),
                              icon: const Icon(Icons.campaign_outlined),
                              label: Text(ref.gt('remind')),
                              onPressed: _sending || state.busy
                                  ? null
                                  : () => _remind([
                                        for (final index in waiting) name(index)
                                      ]))),
                    const Divider(height: 32),
                    Text(ref.gt('members'),
                        style: Theme.of(context).textTheme.titleLarge),
                    if (page.members.isEmpty)
                      const Text('No members on this page.'),
                    for (final (index, entry) in page.members.indexed)
                      ListTile(
                          key: ValueKey('progress-member-${entry.member.uid}'),
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              _finished(entry.summary)
                                  ? Icons.check_circle
                                  : Icons.person_outline,
                              color: _finished(entry.summary)
                                  ? Colors.green
                                  : null),
                          title: Text(name(index)),
                          subtitle: Text(
                              '${groupRoleText(ref, entry.member.role)} · ${_status(entry.summary)}'),
                          trailing: IconButton(
                              tooltip:
                                  'Readings for ${name(index)}, week ${widget.binding.week}',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: () => context.go(
                                  groupProgressAssignmentsLocation(
                                      widget.binding, entry.member.uid)))),
                    if (page.detail.members.hasMore)
                      OutlinedButton.icon(
                          icon: const Icon(Icons.navigate_next),
                          onPressed: state.busy
                              ? null
                              : () => controller.refresh(
                                  cursor: page.detail.members.cursor),
                          label: const Text('More members')),
                  ],
                ]))));
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog(
      {required this.initial,
      required this.title,
      required this.cancel,
      required this.send});
  final String initial, title, cancel, send;
  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  late final _text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: TextField(
              key: const Key('progress-reminder-text'),
              controller: _text,
              maxLines: 5,
              maxLength: 1000),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(widget.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, _text.text),
                child: Text(widget.send)),
          ]);
}
