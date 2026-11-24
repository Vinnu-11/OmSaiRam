import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/language_provider.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_assignments/data/firebase_assignment_resume.dart';
import '../../firebase_assignments/providers/firebase_assignment_resume_provider.dart';
import '../data/firebase_task_models.dart';
import '../providers/firebase_tasks_provider.dart';

class FirebaseTasksScreen extends ConsumerStatefulWidget {
  const FirebaseTasksScreen({super.key});
  @override
  ConsumerState<FirebaseTasksScreen> createState() =>
      _FirebaseTasksScreenState();
}

class _FirebaseTasksScreenState extends ConsumerState<FirebaseTasksScreen> {
  FirebaseTaskOptions _options = defaultTaskOptions;
  final _week = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _week.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready ||
        ref.watch(firebaseAuthGatewayProvider).currentUser?.uid !=
            session.user?.uid) {
      return const Scaffold(
          body: Center(child: Text('Ready Firebase session required.')));
    }
    final binding = (uid: session.user!.uid, options: _options);
    return _TasksPage(
        key: ValueKey(binding),
        binding: binding,
        filters: (busy) => Form(
            key: _form,
            child: Column(children: [
              DropdownButtonFormField<int>(
                  initialValue: _options.weeksAhead,
                  decoration: const InputDecoration(
                      labelText: 'Selected weeks (including start week)'),
                  items: [
                    for (var n = 1; n <= 3; n++)
                      DropdownMenuItem(value: n, child: Text('$n'))
                  ],
                  onChanged: busy
                      ? null
                      : (n) {
                          if (n != null) {
                            setState(() => _options = (
                                  pageSize: 5,
                                  weeksAhead: n,
                                  weekNumber: _options.weekNumber
                                ));
                          }
                        }),
              TextFormField(
                  controller: _week,
                  enabled: !busy,
                  decoration: const InputDecoration(
                      labelText:
                          'Explicit start week (1–10000; blank = each group current week)'),
                  keyboardType: TextInputType.number,
                  validator: (text) => text!.isEmpty ||
                          (RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(text) &&
                              int.parse(text) <= 10000)
                      ? null
                      : 'Enter a week from 1–10000.'),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          if (_form.currentState!.validate()) {
                            setState(() => _options = (
                                  pageSize: 5,
                                  weeksAhead: _options.weeksAhead,
                                  weekNumber: _week.text.isEmpty
                                      ? null
                                      : int.parse(_week.text)
                                ));
                          }
                        },
                  child: const Text('Apply week selection')),
            ])));
  }
}

class _TasksPage extends ConsumerStatefulWidget {
  final FirebaseTaskBinding binding;
  final Widget Function(bool) filters;
  const _TasksPage({super.key, required this.binding, required this.filters});
  @override
  ConsumerState<_TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<_TasksPage> {
  bool _continuing = false;
  bool get _current {
    if (!mounted) return false;
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == widget.binding.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid ==
            widget.binding.uid;
  }

  Future<void> _continue(FirebaseAssignmentResume saved) async {
    if (!_current || _continuing) return;
    bool valid() =>
        _current &&
        identical(
            ref
                .read(firebaseAssignmentResumeProvider(widget.binding.uid))
                .value,
            saved);
    if (!valid()) return;
    setState(() => _continuing = true);
    try {
      await ref
          .read(languageProvider.notifier)
          .setReaderLanguage(AppLanguage.fromCode(saved.language));
      if (!mounted || !valid()) return;
      await context.push(saved.location);
      if (_current) await _reload();
    } catch (_) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved assignment could not be opened. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() =>
      ref.read(firebaseTasksProvider(widget.binding).notifier).refresh();
  Future<void> _read(FirebaseAssignment task) async {
    await context.push(taskReaderLocation(task));
    if (!mounted) return;
    final session = ref.read(firebaseSessionProvider);
    if (session.ready &&
        session.user?.uid == widget.binding.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid ==
            widget.binding.uid) {
      await _reload(); // Same page cursor/options after exact reader pop.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseTasksProvider(widget.binding));
    final controller = ref.read(firebaseTasksProvider(widget.binding).notifier);
    final resume =
        ref.watch(firebaseAssignmentResumeProvider(widget.binding.uid));
    final resumeController =
        ref.read(firebaseAssignmentResumeProvider(widget.binding.uid).notifier);
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to home',
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_rounded),
          ),
          title: const Text('My reading tasks'),
        ),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  if (resume.value != null) ...[
                    Text(
                        'Saved assignment: ${resume.value!.scope.groupId} / ${resume.value!.scope.memberUid} / week ${resume.value!.scope.week} / chapters ${resume.value!.unitKey} / ${AppLanguage.fromCode(resume.value!.language).englishLabel}'),
                    FilledButton.icon(
                        key: const Key('tasks-continue-saved'),
                        onPressed: resume.busy || _continuing
                            ? null
                            : () => _continue(resume.value!),
                        icon: const Icon(Icons.menu_book),
                        label: const Text('Continue saved assignment')),
                  ],
                  if (resume.error != null)
                    Text(resume.error!, key: const Key('tasks-resume-error')),
                  if (resume.value != null || resume.error != null)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                            key: const Key('tasks-clear-saved'),
                            tooltip: 'Clear saved assignment',
                            onPressed: resume.busy || _continuing
                                ? null
                                : resumeController.clear,
                            icon: const Icon(Icons.bookmark_remove_outlined))),
                  const Text(
                      'Server-only, current-member access. Counts cover only your selected group-weeks on this page, not all-time or group totals. Content is local but access requires the server. Previously downloaded data has no erasure guarantee.'),
                  const Text(
                      '5 groups per page. Next page replaces this page; a full final page may require an empty final request. No automatic polling.'),
                  widget.filters(state.busy),
                  Wrap(spacing: 12, children: [
                    OutlinedButton(
                        onPressed: state.busy ? null : _reload,
                        child: const Text('Refresh / retry page')),
                    OutlinedButton(
                        onPressed: state.busy
                            ? null
                            : () => controller.refresh(restart: true),
                        child: const Text('Restart first page')),
                    OutlinedButton(
                        onPressed: state.busy || state.page?.hasMore != true
                            ? null
                            : () =>
                                controller.refresh(cursor: state.page!.cursor),
                        child: const Text('Next page')),
                  ]),
                  if (state.busy) const LinearProgressIndicator(),
                  if (state.error != null)
                    Text(state.error!, key: const Key('tasks-error')),
                  if (state.page != null && state.page!.groups.isEmpty)
                    const Text('No more groups on this page.'),
                  for (final entry
                      in state.page?.groups ?? <FirebaseTaskGroup>[])
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.group.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  for (final week in entry.weeks) ...[
                                    Text(
                                        'Week ${week.weekNumber} • Your tasks: ${week.summary.total} • Not started: ${week.summary.notStarted} • In progress: ${week.summary.inProgress} • Completed: ${week.summary.completed}'),
                                    if (week.assignments.isEmpty)
                                      const Text(
                                          'No assignments for you in this week.'),
                                    for (final task in week.assignments)
                                      ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                              'Original chapters ${task.unit.key}'),
                                          subtitle: Text(task.status.label),
                                          trailing: FilledButton(
                                              onPressed: () => _read(task),
                                              child: const Text('Read'))),
                                  ],
                                ]))),
                ]))));
  }
}
