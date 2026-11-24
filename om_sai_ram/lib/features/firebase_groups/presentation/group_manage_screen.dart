import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_scheduling/data/firestore_scheduling_gateway.dart';
import '../data/firebase_group_models.dart';
import '../providers/firebase_groups_provider.dart';
import 'group_text.dart';
import 'group_widgets.dart';

/// `/groups/:id/manage`: the group admin's and leads' tools in one list.
class FirebaseGroupManageScreen extends StatelessWidget {
  final String groupId;
  const FirebaseGroupManageScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context) =>
    GroupSessionGate(builder: (uid) => _GroupManage(uid: uid, groupId: groupId));
}

class _GroupManage extends ConsumerStatefulWidget {
  final String uid, groupId;
  const _GroupManage({required this.uid, required this.groupId});
  @override
  ConsumerState<_GroupManage> createState() => _GroupManageState();
}

class _GroupManageState extends ConsumerState<_GroupManage> {
  bool _moving = false;
  String? _moveError;
  FirebaseGroupsScope get _scope => (uid: widget.uid, groupId: widget.groupId);
  String get _path => '/groups/${Uri.encodeComponent(widget.groupId)}';

  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted) ref.read(firebaseGroupsProvider(_scope).notifier).refresh(); });
  }

  Future<void> _nextWeek(int week) async {
    if (_moving) return;
    final ok = await confirmGroupAction(context, ref, ref.gtr('nextWeekAsk', {'from': week, 'to': week + 1}));
    if (!ok || !mounted) return;
    setState(() { _moving = true; _moveError = null; });
    try {
      final now = await ref.read(firebaseSchedulingGatewayProvider).advance((uid: widget.uid, groupId: widget.groupId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.gtr('moved', {'n': now}))));
      await ref.read(firebaseGroupsProvider(_scope).notifier).refresh();
    } catch (error) {
      if (mounted) setState(() => _moveError = groupsError(error));
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupsProvider(_scope));
    final detail = state.detail;
    final busy = state.busy || _moving;
    final group = detail?.group;
    final writable = group != null && !group.archived && isGroupLeader(detail!.self.role);
    final admin = detail?.self.role == FirebaseGroupRole.admin;
    return Scaffold(
      appBar: AppBar(title: Text(ref.gt('manage')),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(_path))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (busy) const LinearProgressIndicator(),
          if (state.error != null) GroupErrorRetry(key: const Key('groups-error'), message: state.error!,
            onRetry: busy ? null : () => ref.read(firebaseGroupsProvider(_scope).notifier).refresh()),
          if (_moveError != null) GroupErrorRetry(key: const Key('move-week-error'), message: _moveError!),
          if (group != null) ...[
            Text('${group.name} · ${ref.gt('week', {'n': group.currentWeek})}',
              key: const Key('manage-summary'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (writable) ...[
              GroupBigButton(key: const Key('manage-plan'), icon: Icons.calendar_month, label: ref.gt('planWeeks'),
                onPressed: busy ? null : () => context.go('$_path/scheduling')),
              GroupBigButton(key: const Key('manage-next-week'), icon: Icons.skip_next, label: ref.gt('nextWeek'),
                onPressed: busy || group.currentWeek >= 10000 ? null : () => _nextWeek(group.currentWeek)),
            ],
            GroupBigButton(key: const Key('manage-not-read'), icon: Icons.checklist, label: ref.gt('notRead'),
              onPressed: busy ? null : () => context.go('$_path/progress?week=${group.currentWeek}')),
            GroupBigButton(key: const Key('manage-reading-times'), icon: Icons.alarm, label: ref.gt('readingTimes'),
              onPressed: busy ? null : () => context.go('$_path/reminder-schedule')),
            GroupBigButton(key: const Key('manage-members'), icon: Icons.manage_accounts_outlined, label: ref.gt('roles'),
              onPressed: busy ? null : () => context.go('$_path/members')),
            if (admin && !group.archived)
              GroupBigButton(key: const Key('manage-settings'), icon: Icons.tune, label: ref.gt('settings'),
                onPressed: busy ? null : () => context.go('$_path/settings')),
          ],
        ]))));
  }
}
