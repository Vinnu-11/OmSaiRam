import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_assignments/providers/firebase_assignments_provider.dart';
import '../../firebase_group_progress/providers/firebase_group_progress_provider.dart';
import '../data/firebase_group_models.dart';
import '../providers/firebase_groups_provider.dart';
import 'group_text.dart';
import 'group_widgets.dart';

String groupChapterText(WidgetRef ref, FirebaseChapterUnit unit) => unit.start == unit.end
  ? ref.gt('chapter', {'c': unit.start}) : ref.gt('chapters', {'c': '${unit.start}–${unit.end}'});

/// `/groups/:id`: this week's reading first, then the group's places.
class FirebaseGroupHomeScreen extends StatelessWidget {
  final String groupId;
  const FirebaseGroupHomeScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context) =>
    GroupSessionGate(builder: (uid) => _GroupHome(uid: uid, groupId: groupId));
}

class _GroupHome extends ConsumerStatefulWidget {
  final String uid, groupId;
  const _GroupHome({required this.uid, required this.groupId});
  @override
  ConsumerState<_GroupHome> createState() => _GroupHomeState();
}

class _GroupHomeState extends ConsumerState<_GroupHome> {
  FirebaseGroupsScope get _scope => (uid: widget.uid, groupId: widget.groupId);
  String get _path => '/groups/${Uri.encodeComponent(widget.groupId)}';

  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pages opened from the group (chat, members...) stack on top of this one;
    // load only while this is the page people see, and again on coming back.
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    // The week cards load their own data when they appear.
    if (visible && !_visible) Future.microtask(() => _load(cards: false));
    _visible = visible;
  }

  Future<void> _load({bool cards = true}) async {
    if (!mounted) return;
    await ref.read(firebaseGroupsProvider(_scope).notifier).refresh();
    if (!mounted || !cards) return;
    final week = ref.read(firebaseGroupsProvider(_scope)).detail?.group.currentWeek;
    if (week == null) return;
    ref.read(firebaseAssignmentsProvider(_mine(week)).notifier).refresh();
    ref.read(firebaseGroupProgressProvider((uid: widget.uid, groupId: widget.groupId, week: week)).notifier).refresh();
  }

  FirebaseAssignmentsScope _mine(int week) =>
    (uid: widget.uid, groupId: widget.groupId, memberUid: widget.uid, week: week);

  String _inviteMessage(String groupName, String token) {
    final lines = [ref.gtr('inviteMessage', {'group': groupName, 'code': displayInvite(token)})];
    // The web app uses hash routes; phones open the app and type the code.
    if (kIsWeb && Uri.base.hasScheme && Uri.base.scheme.startsWith('http')) {
      lines.add(ref.gtr('inviteLink', {'link': '${Uri.base.origin}${Uri.base.path}#/groups/join?code=$token'}));
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const Scaffold();
    final state = ref.watch(firebaseGroupsProvider(_scope));
    final controller = ref.read(firebaseGroupsProvider(_scope).notifier);
    final detail = state.detail;
    final group = detail?.group;
    final leader = detail != null && isGroupLeader(detail.self.role);
    return Scaffold(
      appBar: AppBar(title: Text(group?.name ?? ref.gt('loading')),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/groups'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(20), children: [
          if (state.busy) const LinearProgressIndicator(),
          if (state.error != null)
            GroupErrorRetry(key: const Key('groups-error'), message: state.error!, onRetry: state.busy ? null : _load),
          if (group != null) ...[
            Text([
              ref.gt('week', {'n': group.currentWeek}),
              groupRoleText(ref, detail!.self.role),
              if (group.archived) ref.gt('closed'),
            ].join(' · '), key: const Key('group-home-summary'), style: Theme.of(context).textTheme.titleMedium),
            if (group.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(group.description)),
            const SizedBox(height: 16),
            _MyWeek(scope: _mine(group.currentWeek), groupPath: _path, archived: group.archived),
            _WeekCount(binding: (uid: widget.uid, groupId: widget.groupId, week: group.currentWeek)),
            const SizedBox(height: 8),
            if (leader && !group.archived)
              GroupBigButton(key: const Key('group-plan-weeks'), primary: true,
                icon: Icons.edit_calendar_outlined, label: ref.gt('planWeeks'),
                onPressed: () => context.go('$_path/scheduling')),
            GroupBigButton(key: const Key('group-my-schedule'), icon: Icons.calendar_month_outlined,
              label: ref.gt('mySchedule'), onPressed: () => context.go('$_path/assignments')),
            if (leader && !group.archived) ...[
              GroupBigButton(key: const Key('group-invite'), primary: state.issued == null, icon: Icons.person_add_alt_1,
                label: ref.gt('invite'), onPressed: state.busy ? null : controller.issue),
              if (state.issued != null) _InviteCard(code: state.issued!.token,
                until: state.issued!.expiresAt, busy: state.busy,
                message: _inviteMessage(group.name, state.issued!.token),
                onStop: controller.revoke),
            ],
            GroupBigButton(key: const Key('group-chat'), icon: Icons.forum_outlined, label: ref.gt('chat'),
              onPressed: () => context.go('$_path/chat')),
            GroupBigButton(key: const Key('group-quotes'), icon: Icons.format_quote_outlined, label: ref.gt('quotes'),
              onPressed: () => context.go('$_path/highlights')),
            GroupBigButton(key: const Key('group-members'), icon: Icons.people_outline, label: ref.gt('members'),
              onPressed: () => context.go('$_path/members')),
            GroupBigButton(key: const Key('group-reading-times'), icon: Icons.alarm, label: ref.gt('reminders'),
              onPressed: () => context.go('$_path/reminder-schedule')),
            if (leader) GroupBigButton(key: const Key('group-manage'), icon: Icons.settings_outlined,
              label: ref.gt('manage'), onPressed: () => context.go('$_path/manage')),
          ],
        ])))));
  }
}

class _MyWeek extends ConsumerStatefulWidget {
  final FirebaseAssignmentsScope scope;
  final String groupPath;
  final bool archived;
  const _MyWeek({required this.scope, required this.groupPath, required this.archived});
  @override
  ConsumerState<_MyWeek> createState() => _MyWeekState();
}

class _MyWeekState extends ConsumerState<_MyWeek> {
  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void didUpdateWidget(_MyWeek old) { super.didUpdateWidget(old); if (old.scope != widget.scope) _refresh(); }
  // After this build listens; the provider auto-disposes without a listener.
  void _refresh() => Future.microtask(() {
    if (mounted) ref.read(firebaseAssignmentsProvider(widget.scope).notifier).refresh();
  });

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope, groupPath = widget.groupPath, archived = widget.archived;
    final state = ref.watch(firebaseAssignmentsProvider(scope));
    final controller = ref.read(firebaseAssignmentsProvider(scope).notifier);
    final result = state.result;
    final rows = result == null ? const <FirebaseAssignment>[]
      : result.assignments.where((row) => row.activeFor(result.member)).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ref.gt('thisWeek'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (state.busy) const LinearProgressIndicator(),
        if (state.error != null) GroupErrorRetry(message: state.error!, onRetry: state.busy ? null : controller.refresh),
        if (result != null && rows.isEmpty) Text(ref.gt('nothingYet'), key: const Key('my-week-empty')),
        for (final row in rows) Padding(key: ValueKey('my-week-${row.unit.key}'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(groupChapterText(ref, row.unit), style: Theme.of(context).textTheme.titleMedium),
            FilledButton.icon(icon: const Icon(Icons.menu_book), label: Text(ref.gt('read')),
              onPressed: () => context.go('$groupPath/assignments/read/'
                '${Uri.encodeComponent(scope.memberUid)}/${scope.week}/${row.unit.key}')),
            if (row.status == FirebaseReadingStatus.completed)
              Chip(avatar: const Icon(Icons.check_circle, color: Colors.green), label: Text(ref.gt('finished')))
            else if (!archived)
              OutlinedButton.icon(key: ValueKey('mark-read-${row.unit.key}'), icon: const Icon(Icons.check),
                label: Text(ref.gt('markRead')), onPressed: state.busy ? null : () async {
                  await controller.updateStatus(row.unit, FirebaseReadingStatus.completed);
                  if (!mounted) return;
                  ref.read(firebaseGroupProgressProvider(
                    (uid: scope.uid, groupId: scope.groupId, week: scope.week)).notifier).refresh();
                }),
          ])),
      ])));
  }
}

class _WeekCount extends ConsumerStatefulWidget {
  final ({String uid, String groupId, int week}) binding;
  const _WeekCount({required this.binding});
  @override
  ConsumerState<_WeekCount> createState() => _WeekCountState();
}

class _WeekCountState extends ConsumerState<_WeekCount> {
  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void didUpdateWidget(_WeekCount old) { super.didUpdateWidget(old); if (old.binding != widget.binding) _refresh(); }
  void _refresh() => Future.microtask(() {
    if (mounted) ref.read(firebaseGroupProgressProvider(widget.binding).notifier).refresh();
  });

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(firebaseGroupProgressProvider(widget.binding)).page;
    // Counts are exact only when every member fits on the first page.
    if (page == null || page.detail.members.hasMore) return const SizedBox.shrink();
    final done = page.members.where((entry) =>
      entry.summary.total > 0 && entry.summary.completed == entry.summary.total).length;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(
      ref.gt('haveRead', {'done': done, 'total': page.members.length}), key: const Key('group-week-count'),
      style: Theme.of(context).textTheme.titleMedium));
  }
}

class _InviteCard extends ConsumerWidget {
  final String code, message;
  final DateTime until;
  final bool busy;
  final VoidCallback onStop;
  const _InviteCard({required this.code, required this.until, required this.message,
    required this.busy, required this.onStop});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = until.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final time = '${localizations.formatShortDate(local)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    return Card(color: Theme.of(context).colorScheme.secondaryContainer, child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ref.gt('inviteHelp')),
        const SizedBox(height: 8),
        SelectableText(displayInvite(code), key: const Key('issued-token'),
          style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.bold)),
        Text(ref.gt('inviteUntil', {'time': time})),
        const SizedBox(height: 8),
        GroupBigButton(key: const Key('invite-share'), primary: true, icon: Icons.share, label: ref.gt('share'),
          onPressed: busy ? null : () => Share.share(message)),
        GroupBigButton(key: const Key('invite-copy'), icon: Icons.copy, label: ref.gt('copy'),
          onPressed: busy ? null : () async {
            await Clipboard.setData(ClipboardData(text: message));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.gtr('copied'))));
            }
          }),
        TextButton.icon(key: const Key('invite-stop'), icon: const Icon(Icons.block), label: Text(ref.gt('cancelCode')),
          onPressed: busy ? null : onStop),
      ])));
  }
}
