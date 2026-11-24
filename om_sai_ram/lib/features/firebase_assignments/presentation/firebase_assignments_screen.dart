import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/utc_schedule_date_field.dart';
import 'firebase_manual_assignment_dialog.dart';
import 'firebase_assignment_lifecycle_dialog.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../data/firebase_assignment_models.dart';
import '../providers/firebase_assignments_provider.dart';

class FirebaseAssignmentsScreen extends ConsumerWidget {
  final String groupId;
  final String? initialMember;
  final int? initialWeek;
  const FirebaseAssignmentsScreen(
      {super.key, required this.groupId, this.initialMember, this.initialWeek});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    final sdkUid = ref.watch(firebaseAuthGatewayProvider).currentUser?.uid;
    if (!session.ready || sdkUid != session.user?.uid) {
      return const Scaffold(
          body: Center(child: Text('Ready Firebase session required.')));
    }
    return _AssignmentsWorkspace(
        key: ValueKey((session.user!.uid, groupId)),
        uid: session.user!.uid,
        groupId: groupId,
        initialMember: initialMember,
        initialWeek: initialWeek);
  }
}

class _AssignmentsWorkspace extends ConsumerStatefulWidget {
  final String uid, groupId;
  final String? initialMember;
  final int? initialWeek;
  const _AssignmentsWorkspace(
      {super.key,
      required this.uid,
      required this.groupId,
      this.initialMember,
      this.initialWeek});
  @override
  ConsumerState<_AssignmentsWorkspace> createState() =>
      _AssignmentsWorkspaceState();
}

class _AssignmentsWorkspaceState extends ConsumerState<_AssignmentsWorkspace> {
  final _weekText = TextEditingController();
  final _weekForm = GlobalKey<FormState>();
  int? _week;
  String? _member;
  FirebaseGroupsScope get _groupScope =>
      (uid: widget.uid, groupId: widget.groupId);
  @override
  void initState() {
    super.initState();
    _member = widget.initialMember;
    _week = widget.initialWeek;
    Future.microtask(() {
      if (mounted) {
        ref.read(firebaseGroupsProvider(_groupScope).notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _weekText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(firebaseGroupsProvider(_groupScope));
    final detail = groups.detail?.self.uid == widget.uid ? groups.detail : null;
    final members = <String, FirebaseMembership>{
      if (detail != null) detail.self.uid: detail.self,
      if (detail != null)
        for (final member in detail.members.items) member.uid: member,
    };
    final selected = members.containsKey(_member) ? _member! : widget.uid;
    final week = _week ?? detail?.group.currentWeek;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Assignments'),
          leading: IconButton(
              tooltip: 'Back to group',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/groups/${widget.groupId}'))),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                const Text(
                    'Local Firebase • server reads only • manual assignments'),
                const Text(
                    'Bundled assignment reader • explicit assignee completion'),
                OutlinedButton(
                    onPressed: groups.busy
                        ? null
                        : () => ref
                            .read(firebaseGroupsProvider(_groupScope).notifier)
                            .refresh(),
                    child: const Text('Refresh roster')),
                if (groups.busy) const LinearProgressIndicator(),
                if (groups.error != null)
                  Text(groups.error!,
                      key: const Key('assignments-roster-error')),
                if (detail != null && week != null) ...[
                  Text(
                      '${detail.group.name} • Server current week: ${detail.group.currentWeek}'),
                  const Text(
                      'Roster contains UIDs and actual roles only; no private profiles.'),
                  DropdownButtonFormField<String>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Member'),
                      items: [
                        for (final member in members.values)
                          DropdownMenuItem(
                              value: member.uid,
                              child: Text(
                                  '${member.uid}${member.uid == widget.uid ? ' (you)' : ''} • ${member.roleLabel}'))
                      ],
                      onChanged: (value) => setState(() => _member = value)),
                  if (detail.members.hasMore)
                    OutlinedButton(
                        onPressed: () {
                          setState(() => _member = widget.uid);
                          ref
                              .read(
                                  firebaseGroupsProvider(_groupScope).notifier)
                              .refresh(cursor: detail.members.cursor);
                        },
                        child: const Text('Next members page')),
                  Text('Selected week: $week'),
                  Form(
                      key: _weekForm,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: TextFormField(
                                    controller: _weekText,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                        labelText: 'Week (1–10000)',
                                        hintText: '$week'),
                                    validator: (value) {
                                      final number = int.tryParse(value ?? '');
                                      return number == null ||
                                              number < 1 ||
                                              number > 10000
                                          ? 'Enter 1–10000.'
                                          : null;
                                    })),
                            const SizedBox(width: 12),
                            Flexible(child: FilledButton(
                                onPressed: () {
                                  if (_weekForm.currentState!.validate()) {
                                    setState(() =>
                                        _week = int.parse(_weekText.text));
                                  }
                                },
                                child: const Text('Select week'))),
                          ])),
                  _AssignmentRows(
                      key: ValueKey(
                          (widget.uid, widget.groupId, selected, week)),
                      scope: (
                        uid: widget.uid,
                        groupId: widget.groupId,
                        memberUid: selected,
                        week: week
                      )),
                ],
              ]))),
    );
  }
}

class _AssignmentRows extends ConsumerStatefulWidget {
  final FirebaseAssignmentsScope scope;
  const _AssignmentRows({super.key, required this.scope});
  @override
  ConsumerState<_AssignmentRows> createState() => _AssignmentRowsState();
}

class _AssignmentRowsState extends ConsumerState<_AssignmentRows> {
  FirebaseChapterUnit _unit = FirebaseChapterUnit.all.first;
  DateTime? _date;
  int _revision = 0;
  bool _dialogOpen = false;
  BuildContext? _dialogContext;
  bool get _current {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == widget.scope.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.scope.uid;
  }
  Future<void> _assign() async {
    if (_dialogOpen || !_current) return;
    final scope = widget.scope, unit = _unit, date = _date, revision = _revision;
    bool current() => mounted && _current && revision == _revision &&
      widget.scope == scope && _unit == unit && _date == date;
    setState(() => _dialogOpen = true);
    try {
      final accepted = await showDialog<bool>(context: context, builder: (context) {
        _dialogContext = context;
        return FirebaseManualAssignmentDialog(scope: scope, unit: unit, date: date, isCurrent: current);
      });
      if (accepted != true || !current()) return;
      final controller = ref.read(firebaseAssignmentsProvider(scope).notifier);
      await controller.create(unit, scheduledDate: date);
      if (current() && ref.read(firebaseAssignmentsProvider(scope)).acknowledged) {
        setState(() { _date = null; ++_revision; });
      }
    } finally {
      _dialogContext = null;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }
  Future<void> _manage(FirebaseAssignment row, String action) async {
    if (_dialogOpen || !_current) return;
    final scope = widget.scope, revision = _revision;
    bool current() => mounted && _current && widget.scope == scope && revision == _revision;
    setState(() => _dialogOpen = true);
    try {
      if (action == 'history') {
        await showDialog<void>(context: context, builder: (context) {
          _dialogContext = context;
          return FirebaseAssignmentHistoryDialog(scope: scope, baseline: row, isCurrent: current);
        });
        return;
      }
      final change = await showDialog<FirebaseAssignmentChange>(context: context, builder: (context) {
        _dialogContext = context;
        return FirebaseAssignmentLifecycleDialog(scope: scope, baseline: row, action: action, isCurrent: current);
      });
      if (change == null || !current()) return;
      await ref.read(firebaseAssignmentsProvider(scope).notifier).transition(row,
        archived: action != 'replace', scheduledDate: change.date, reassignTo: change.target);
    } finally {
      _dialogContext = null;
      if (mounted) setState(() => _dialogOpen = false);
    }
  }
  @override
  void dispose() {
    ++_revision;
    final context = _dialogContext;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context != null && context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
    });
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(firebaseAssignmentsProvider(widget.scope).notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseAssignmentsProvider(widget.scope));
    final controller =
        ref.read(firebaseAssignmentsProvider(widget.scope).notifier);
    final result = state.result;
    final canAssign = result != null && !result.group.archived &&
      (result.self.role == FirebaseGroupRole.admin || result.self.role == FirebaseGroupRole.groupLead);
    final own = widget.scope.uid == widget.scope.memberUid;
    final editable = !state.busy && !state.acknowledged && !state.verifyBeforeRetry && !_dialogOpen;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton(
          onPressed: state.busy ? null : controller.refresh,
          child: const Text('Reload assignments')),
      if (state.busy) const LinearProgressIndicator(),
      if (state.acknowledged) const Text('Assignment write acknowledged. Reload assignments before another creation or lifecycle change.', key: Key('assignment-create-ack')),
      if (state.verifyBeforeRetry) const Text('Write unconfirmed. Reload assignments to verify before retrying.', key: Key('assignment-create-uncertain')),
      if (state.error != null)
        Text(state.error!,
            key: const Key('assignments-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (result != null) ...[
        if (result.group.archived) const Text('Archived • Read-only'),
        Text('Your actual role: ${result.self.roleLabel}'),
        if (!own)
          const Text(
              'Read-only progress. Only this assignee can change status, including for admins.'),
        if (canAssign) ...[
          const Divider(),
          const Text('Manually assign one canonical reading unit'),
          DropdownButtonFormField<String>(
              initialValue: _unit.key,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Original chapter unit (48 units)'),
              items: [
                for (final unit in FirebaseChapterUnit.all)
                  DropdownMenuItem(
                      value: unit.key, child: Text('Chapters ${unit.key}'))
              ],
              onChanged: !editable
                  ? null
                  : (value) => setState(() {
                    ++_revision;
                    _unit = FirebaseChapterUnit.all.firstWhere((unit) => unit.key == value);
                  })),
          UtcScheduleDateField(key: const Key('manual-scheduled-date'), label: 'Scheduled date',
            value: _date, enabled: editable, isCurrent: () => mounted && _current,
            onChanged: (date) => setState(() { ++_revision; _date = date; })),
          FilledButton(
              onPressed: editable ? _assign : null,
              child: const Text('Assign unit')),
        ],
        const Divider(),
        if (result.assignments.isEmpty)
          const Text('No assignments for this member and week.'),
        for (final row in result.assignments)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Chapters ${row.unit.key}',
                            key: ValueKey('assignment-${row.unit.key}')),
                        Text(row.scheduledDate == null
                            ? 'Unscheduled'
                            : 'Scheduled: ${row.scheduledDate!.toIso8601String()}'),
                        Text('Status: ${row.status.label}'),
                        if (row.archived) const Text('Archived - retained history only'),
                        if (!row.archived && !row.activeFor(result.member)) const Text('Previous membership - history only'),
                        if (row.revision > 0) Text('Version: ${row.revision}'),
                        if (canAssign || row.revision > 0)
                          Align(alignment: Alignment.centerRight, child: PopupMenuButton<String>(
                            key: ValueKey('assignment-actions-${row.unit.key}'), tooltip: 'Assignment actions',
                            enabled: editable, onSelected: (action) => _manage(row, action),
                            itemBuilder: (_) => [
                              if (canAssign && !row.archived) const PopupMenuItem(value: 'archive', child: Text('Archive')),
                              if (canAssign && !row.archived) const PopupMenuItem(value: 'reassign', child: Text('Reassign')),
                              if (canAssign && row.archived) const PopupMenuItem(value: 'replace', child: Text('Create fresh active version')),
                              if (row.revision > 0) const PopupMenuItem(value: 'history', child: Text('Retained versions')),
                            ],
                            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220),
                              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.edit_outlined, size: 20),
                                const SizedBox(width: 8),
                                Flexible(child: Text(editable ? 'Modify reading' : 'Unavailable',
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ]))))),
                        OutlinedButton(
                            onPressed: state.busy
                                ? null
                                : () async {
                                    final scope = widget.scope;
                                    await context.push(
                                        '/groups/${Uri.encodeComponent(scope.groupId)}/assignments/read/${Uri.encodeComponent(scope.memberUid)}/${scope.week}/${row.unit.key}');
                                    if (!mounted) return;
                                    final session =
                                        ref.read(firebaseSessionProvider);
                                    if (session.ready &&
                                        session.user?.uid == scope.uid &&
                                        ref
                                                .read(
                                                    firebaseAuthGatewayProvider)
                                                .currentUser
                                                ?.uid ==
                                            scope.uid) {
                                      await ref
                                          .read(
                                              firebaseAssignmentsProvider(scope)
                                                  .notifier)
                                          .refresh();
                                    }
                                  },
                            child: const Text('Read assignment')),
                        if (own)
                          DropdownButtonFormField<FirebaseReadingStatus>(
                              key: ValueKey((row.unit.key, row.status)),
                              isExpanded: true,
                              initialValue: row.status,
                              decoration: const InputDecoration(
                                  labelText: 'Reading status'),
                              items: [
                                for (final status
                                    in FirebaseReadingStatus.values)
                                  DropdownMenuItem(
                                      value: status, child: Text(status.label, maxLines: 1, overflow: TextOverflow.ellipsis))
                              ],
                              onChanged: state.busy || result.group.archived || !row.activeFor(result.member)
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        controller.updateStatus(
                                            row.unit, value);
                                      }
                                    }),
                      ]))),
      ],
    ]);
  }
}
