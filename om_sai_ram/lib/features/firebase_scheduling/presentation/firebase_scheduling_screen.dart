import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/utc_schedule_date_field.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/presentation/group_text.dart';
import '../../firebase_groups/presentation/group_widgets.dart';
import '../data/firebase_schedule_models.dart';
import '../providers/firebase_scheduling_provider.dart';

const _modeText = {
  'independent': 'Each member reads different chapters',
  'rotating_window': 'Members take turns through the book',
  'dense_window': 'Members start one chapter apart',
  'synchronized': 'Everyone reads the same chapters',
};
const _modeOptionText = {
  'independent': 'Give each member different chapters',
  'rotating_window': 'Continue each person next week (7–8 → 9–10)',
  'dense_window': 'Start members one chapter apart',
  'synchronized': 'Everyone reads the same chapters',
};
const _remainderText = {
  'manual': 'At the end of the book: stop and show me',
  'truncate': 'At the end of the book: stop',
  'cycle': 'At the end of the book: start again from chapter 1',
  'extend_last': 'Last few chapters: give to the last member',
  'round_robin': 'Last few chapters: share one each',
};

class FirebaseSchedulingScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseSchedulingScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready) return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    try { assignmentSegment(groupId); }
    on FormatException { return const Scaffold(body: Center(child: Text('Invalid scheduling path.'))); }
    final binding = (uid: session.user!.uid, groupId: groupId);
    return _SchedulingWorkspace(key: ValueKey(binding), binding: binding);
  }
}

class _SchedulingWorkspace extends ConsumerStatefulWidget {
  final FirebaseScheduleBinding binding;
  const _SchedulingWorkspace({super.key, required this.binding});
  @override
  ConsumerState<_SchedulingWorkspace> createState() => _SchedulingWorkspaceState();
}

class _SchedulingWorkspaceState extends ConsumerState<_SchedulingWorkspace> {
  final _weeks = TextEditingController(text: '1'), _start = TextEditingController();
  String _mode = 'independent', _remainder = 'manual';
  DateTime? _firstWeekDate;
  // UID-bound drafts; keyed TextFormFields own/dispose their own controllers.
  final _hints = <String, String>{};
  String? _error;
  bool _dialogOpen = false, _continue = false;
  // Names collected across roster pages; unnamed members get a stable "Member N".
  final _names = <String, String>{}, _fallback = <String, String>{};
  String _name(String uid) {
    if (_names[uid] case final name?) return name;
    if (uid == widget.binding.uid) return ref.gtr('you');
    return _fallback[uid] ?? ref.gtr('someMember');
  }
  FirebaseSchedulingController get _controller => ref.read(firebaseSchedulingProvider(widget.binding).notifier);
  bool get _current {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == widget.binding.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.binding.uid;
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted && _current) _controller.load(); });
  }
  Future<void> _preview({bool suggesting = false}) async {
    final weeks = int.tryParse(_weeks.text), start = _start.text.isEmpty ? null : int.tryParse(_start.text);
    if (weeks == null || (_start.text.isNotEmpty && start == null)) {
      _controller.rejectInput('Enter integer weeks and optional original start chapter. Reload server head to retry.');
      setState(() => _error = 'Enter integer weeks and optional original start chapter.'); return;
    }
    setState(() => _error = null);
    if (suggesting) {
      final selected = ref.read(firebaseSchedulingProvider(widget.binding)).selected;
      final hints = <FirebaseScheduleHint>[];
      for (var i = 0; i < selected.length; i++) {
        final text = _hints[selected[i]]?.trim() ?? '';
        if (text.isEmpty) continue;
        final chapter = int.tryParse(text);
        if (chapter == null) {
          _controller.rejectInput('Hints must be original integer chapters 1–53. Reload server head to retry.');
          return;
        }
        hints.add(FirebaseScheduleHint(position: i, chapterStart: chapter));
      }
      await _controller.suggest(weeksAhead: weeks, mode: _mode, remainder: _remainder,
        startChapter: start, hints: hints, firstWeekDate: _firstWeekDate);
    } else {
      await _controller.preview(weeksAhead: weeks, mode: _mode, remainder: _remainder,
        startChapter: start, firstWeekDate: _firstWeekDate);
    }
  }
  void _select(String uid, bool selected) {
    _controller.select(uid, selected);
    if (!selected) _hints.remove(uid);
  }
  // Ticks everyone on this roster page (in roster order), or clears them when all are ticked.
  void _selectAll(List<String> uids, List<String> selected) {
    final all = uids.every(selected.contains);
    for (final uid in uids) {
      if (selected.contains(uid) == all) _select(uid, !all);
    }
  }
  Future<void> _confirm({bool advance = false}) async {
    if (!_current || _dialogOpen) return;
    final controller = _controller, confirmation = _controller.confirmation(advance: advance);
    if (confirmation == null) return;
    setState(() => _dialogOpen = true);
    try {
      final accepted = await showDialog<bool>(context: context, builder: (_) =>
        FirebaseSchedulingConfirmationDialog(confirmation: confirmation, nameOf: _name));
      if (accepted != true || !mounted || !_current) { controller.cancel(confirmation); return; }
      await controller.confirm(confirmation);
    } finally { if (mounted) setState(() => _dialogOpen = false); }
  }
  @override
  void dispose() { _weeks.dispose(); _start.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseSchedulingProvider(widget.binding));
    final head = state.head, preview = state.preview;
    final enabled = !state.busy && !state.acknowledged && !state.uncertain && head != null && !head.group.archived && !_dialogOpen;
    if (head != null) {
      _names.addAll(ref.watch(groupMemberNamesProvider(groupNamesKey(widget.binding.uid, widget.binding.groupId,
        head.members.items.map((m) => m.uid)))).asData?.value ?? const {});
      for (final (i, member) in head.members.items.indexed) {
        _fallback[member.uid] ??= ref.gt('memberN', {'n': i + 1});
      }
    }
    final theme = Theme.of(context), muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final groupPath = '/groups/${Uri.encodeComponent(widget.binding.groupId)}';
    const gap = SizedBox(height: 12);
    final weeksField = TextField(key: const Key('schedule-weeks'), controller: _weeks, enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Weeks to plan (1–12)', helperText: 'Counting this week'),
      onChanged: (_) => _controller.edit());
    final startField = TextField(key: const Key('schedule-start'), controller: _start, enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: 'Start from chapter', helperText: 'Blank = group start'),
      onChanged: (_) => _controller.edit());
    return Scaffold(appBar: AppBar(title: const Text('Plan the next weeks'),
      leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('$groupPath/manage')),
      actions: [TextButton.icon(onPressed: state.busy ? null : () => _controller.load(),
        icon: const Icon(Icons.refresh), label: const Text('Start over'))]),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          Text('Pick who reads, choose the weeks, then tap Show plan. Nothing is saved until you tap Save this plan.',
            style: muted),
          gap,
          if (state.busy) const LinearProgressIndicator(),
          if (state.outcome != null) Text(state.outcome!, key: const Key('schedule-outcome')),
          if (state.acknowledged) ...[
            const Text('Plan saved. You can modify any saved reading.'),
            const SizedBox(height: 8),
            FilledButton.icon(key: const Key('schedule-modify-saved'),
              onPressed: () => context.go('$groupPath/assignments'),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Modify saved readings')),
          ],
          if (state.uncertain) const Text('We could not confirm if this was saved. Check the group before trying again.', key: Key('schedule-uncertain')),
          if (state.error != null) Text(state.error!, key: const Key('schedule-error'),
            style: TextStyle(color: theme.colorScheme.error)),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (head != null) ...[
            _Section(title: head.group.name, children: [
              Text('Week ${head.group.currentWeek} · ${head.group.chaptersPerWeek} chapter(s) each per week · '
                'starts at chapter ${head.group.startChapter}', style: theme.textTheme.bodyLarge),
              Text('Your role: ${groupRoleText(ref, head.actor.role)}', style: muted),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (isGroupLeader(head.actor.role))
                  OutlinedButton(onPressed: enabled && head.group.currentWeek < 10000 ? () => _confirm(advance: true) : null,
                    child: const Text('Move to next week')),
                if (head.actor.role == FirebaseGroupRole.admin && !head.group.archived)
                  TextButton(key: const Key('schedule-change-settings'),
                    onPressed: state.busy ? null : () => context.go('$groupPath/settings'),
                    child: const Text('Change chapters per week')),
                TextButton(key: const Key('schedule-open-readings'),
                  onPressed: state.busy ? null : () => context.go('$groupPath/assignments'),
                  child: const Text('Modify saved readings')),
              ]),
            ]),
            _Section(title: '1. Who will read', trailing: Text('${state.selected.length} selected', style: muted), children: [
              if (head.members.items.isNotEmpty) Builder(builder: (_) {
                final uids = [for (final member in head.members.items) member.uid];
                final picked = uids.where(state.selected.contains).length;
                return CheckboxListTile(key: const Key('schedule-select-all'), tristate: true,
                  controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                  title: Text(head.members.hasMore ? 'Select all on this page' : 'Select all'),
                  value: picked == 0 ? false : picked == uids.length ? true : null,
                  onChanged: enabled ? (_) => _selectAll(uids, state.selected) : null);
              }),
              const Divider(height: 1),
              for (final member in head.members.items)
                CheckboxListTile(key: ValueKey('schedule-member-${member.uid}'), title: Text(_name(member.uid)),
                  subtitle: Text(groupRoleText(ref, member.role)), value: state.selected.contains(member.uid),
                  controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                  onChanged: enabled ? (value) => _select(member.uid, value!) : null),
              if (head.members.hasMore) Align(alignment: Alignment.centerLeft,
                child: TextButton(onPressed: enabled ? () => _controller.load(cursor: head.members.cursor) : null,
                  child: const Text('More members'))),
            ]),
            _Section(title: '2. Reading order', subtitle: state.selected.isEmpty
                ? 'Tick members above. Readings go to them in the order they are ticked.'
                : 'Readings go to members in this order (up to 50).', children: [
              for (var i = 0; i < state.selected.length; i++)
                ListTile(key: ValueKey('schedule-selected-${state.selected[i]}'), contentPadding: EdgeInsets.zero,
                  title: Text('${i + 1}. ${_name(state.selected[i])}'),
                  subtitle: _continue ? TextFormField(key: ValueKey('schedule-hint-${state.selected[i]}'),
                    initialValue: _hints[state.selected[i]], enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Chapter they are on now (1–53)', isDense: true),
                    onChanged: (value) { _hints[state.selected[i]] = value; _controller.edit(); }) : null,
                  trailing: Wrap(children: [
                  IconButton(tooltip: 'Move up', icon: const Icon(Icons.arrow_upward), onPressed: enabled && i > 0 ? () => _controller.move(state.selected[i], -1) : null),
                  IconButton(tooltip: 'Move down', icon: const Icon(Icons.arrow_downward), onPressed: enabled && i + 1 < state.selected.length ? () => _controller.move(state.selected[i], 1) : null),
                  IconButton(tooltip: 'Remove from list', icon: const Icon(Icons.close), onPressed: enabled ? () => _select(state.selected[i], false) : null),
                ])),
              SwitchListTile(key: const Key('schedule-continue'), contentPadding: EdgeInsets.zero, value: _continue,
                title: const Text('Continue from where members are now'),
                subtitle: const Text('For groups already reading: type the chapter each member is on, '
                  'and the app works out the plan from there.'),
                onChanged: enabled ? (value) => setState(() => _continue = value) : null),
            ]),
            _Section(title: '3. Plan settings', children: [
              LayoutBuilder(builder: (context, box) => box.maxWidth < 480
                ? Column(children: [weeksField, gap, startField])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: weeksField), const SizedBox(width: 12), Expanded(child: startField)])),
              gap,
              UtcScheduleDateField(key: const Key('schedule-first-week-date'), label: 'First week date',
                value: _firstWeekDate, enabled: enabled && !_dialogOpen, isCurrent: () => mounted && _current,
                onChanged: (date) { _controller.edit(); setState(() => _firstWeekDate = date); }),
              gap,
              DropdownButtonFormField<String>(initialValue: _mode, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Weekly chapter pattern'),
                items: [for (final mode in FirebaseSchedulePlan.modes) DropdownMenuItem(value: mode,
                  child: Text(_modeOptionText[mode]!, overflow: TextOverflow.ellipsis))],
                onChanged: enabled ? (value) { _controller.edit(); setState(() => _mode = value!); } : null),
              if (_mode == 'rotating_window') ...[
                const SizedBox(height: 8),
                Text('Each person continues from their own last chapters. For example, Ramesh reads 7–8 this week and 9–10 next week.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              gap,
              DropdownButtonFormField<String>(initialValue: _remainder, isExpanded: true,
                decoration: const InputDecoration(labelText: 'When the book runs out'),
                items: [for (final mode in FirebaseSchedulePlan.remainders) DropdownMenuItem(value: mode, child: Text(_remainderText[mode]!))],
                onChanged: enabled ? (value) { _controller.edit(); setState(() => _remainder = value!); } : null),
              const SizedBox(height: 16),
              FilledButton(onPressed: enabled ? () => _preview() : null, child: const Text('Show plan')),
              if (_continue) ...[
                const SizedBox(height: 8),
                OutlinedButton(onPressed: enabled ? () => _preview(suggesting: true) : null,
                  child: const Text('Plan from the chapters members are on')),
              ],
            ]),
          ],
          if (preview != null) _Section(title: 'Plan preview', children: [
            if (state.suggestion != null)
              Text('Suggested plan: ${_modeText[state.suggestion!.detectedMode] ?? state.suggestion!.detectedMode}, '
                'starting at chapter ${state.suggestion!.plan.startChapter}. Please check it before saving.',
                key: const Key('schedule-suggestion')),
            _PreviewDetails(preview: preview, nameOf: _name),
            if (preview.commitBlock != null) Text(preview.commitBlock!, key: const Key('schedule-commit-block'),
              style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: enabled && preview.commitBlock == null ? () => _confirm() : null,
              child: const Text('Save this plan')),
          ]),
          ExpansionTile(key: const Key('schedule-details'), title: const Text('More help'),
            maintainState: true, tilePadding: EdgeInsets.zero, expandedAlignment: Alignment.centerLeft,
            childrenPadding: const EdgeInsets.only(bottom: 12), children: [
            const Text('Only the members you tick get readings, in the order shown.'),
            const Text('To continue from where members already are, turn on "Continue from where members are now", type the chapter '
              'each member is on (at least two members) and tap "Plan from the chapters members are on". One week is not enough '
              'to tell turns from different chapters; then turns are used. Always check the plan before saving.'),
            const Text('Chapters per week is one setting for the whole group. To change one person\'s reading after saving, '
              'open their reading and use Reassign or Replace.'),
            const Text('Showing the plan re-reads the group settings. If the settings change before you save, saving stops and you can start over.'),
            if (head?.group.mode == 'saptah') const Text('Saptah is a group label: scheduling is the same weekly plan as chapter-wise groups.'),
            const Text('"Give to the last member" and "share one each" only work with "Each member reads different chapters".'),
          ]),
        ]))));
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  const _Section({required this.title, this.subtitle, this.trailing, required this.children});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        const SizedBox(height: 8),
        ...children,
      ])));
  }
}

class _PreviewDetails extends StatelessWidget {
  final FirebaseSchedulePreview preview;
  final String Function(String uid) nameOf;
  const _PreviewDetails({required this.preview, required this.nameOf});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('${preview.assignments.length} reading(s) planned • ${preview.unfilledCount} could not be filled'
      '${preview.reviewRequired ? " • please check the end of the book" : ""}', key: const Key('schedule-summary')),
    if (preview.extraCount > 0) Text('Includes ${preview.extraCount} extra chapter(s) in the final week to finish the book.', key: const Key('schedule-extras')),
    Text('${_modeText[preview.plan.scheduleMode]} • ${_remainderText[preview.plan.remainderMode]}'),
    Text('Order: ${preview.plan.memberUids.map(nameOf).join(", ")}'),
    Text('Starts at chapter ${preview.assignments.isEmpty ? "-" : preview.assignments.first.unit.start}'
      '${preview.plan.startChapter == null ? " (group start)" : ""}'),
    // Readings grouped under a heading per week.
    for (final week in {...preview.assignments.map((row) => row.weekNumber), ...preview.unfilled.map((slot) => slot.weekNumber)}.toList()..sort()) ...[
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text('Week $week', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
      for (final row in preview.assignments.where((row) => row.weekNumber == week)) Text('${nameOf(row.userId)}: '
        '${row.unit.start == row.unit.end ? "chapter ${row.unit.start}" : "chapters ${row.unit.start}–${row.unit.end}"}'
        '${row.scheduledDate == null ? "" : " · ${row.scheduledDate!.toIso8601String().substring(0, 10)}"}'),
      for (final slot in preview.unfilled.where((slot) => slot.weekNumber == week))
        Text('Not filled: ${nameOf(slot.userId)} (the book has ended)'),
    ],
  ]);
}

class FirebaseSchedulingConfirmationDialog extends ConsumerWidget {
  final FirebaseScheduleConfirmation confirmation;
  final String Function(String uid) nameOf;
  const FirebaseSchedulingConfirmationDialog({super.key, required this.confirmation, required this.nameOf});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider), binding = confirmation.binding;
    final current = session.ready && session.user?.uid == binding.uid &&
      ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == binding.uid &&
      ref.watch(firebaseSchedulingProvider(binding)).head != null &&
      ref.read(firebaseSchedulingProvider(binding).notifier).canConfirm(confirmation);
    if (!current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop(false);
      });
      return const SizedBox.shrink();
    }
    final settings = confirmation.settings;
    return AlertDialog(title: Text(confirmation.advancing ? 'Move to next week?' : 'Save this plan?'),
      content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (confirmation.advancing) Text('The group moves from week ${settings.currentWeek} to week ${settings.currentWeek + 1}. '
          'Readings already given stay as they are. If someone else moved the week at the same time, it moves once more; '
          'if you are unsure whether it worked, check the group before trying again.')
        else ...[
          const Text('Only the members ticked get these readings. Everything is saved together, or nothing is saved '
            'if any of these readings were already given.'),
          _PreviewDetails(preview: confirmation.preview!, nameOf: nameOf),
        ],
      ]))), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmation.advancing ? 'Yes, move to next week' : 'Save plan'))]);
  }
}