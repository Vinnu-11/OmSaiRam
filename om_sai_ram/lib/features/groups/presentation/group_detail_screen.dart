// Om Sai Ram
// Group detail screen — Members, Schedule, and Chat tabs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/l10n/s.dart';
import '../data/group_model.dart';
import '../data/assignment_model.dart';
import '../data/chat_model.dart';
import '../data/groups_repository.dart';
import '../data/assignments_repository.dart';
import '../data/group_chat_repository.dart';
import '../../auth/providers/auth_provider.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  Group? _group;
  List<GroupMember> _members = [];
  bool _isLoading = true;
  String _myRole = 'member';

  // Group lead = admin OR group_lead — they have identical permissions.
  bool get _isLead => _myRole == 'admin' || _myRole == 'group_lead';
  // Aliases kept for compatibility with child widgets
  bool get _canAssign => _isLead;
  bool get _isAdmin => _isLead;

  @override
  void initState() {
    super.initState();
    // Start with 2 tabs; will be rebuilt to 3 after role is known if user is lead
    _tabController = TabController(length: 2, vsync: this);
    _loadGroupDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupDetail() async {
    try {
      final repo = ref.read(groupsRepositoryProvider);
      final result = await repo.getGroupDetail(widget.groupId);
      final authState = ref.read(authStateProvider);
      final myUserId = authState.user?.id;
      final members = result['members'] as List<GroupMember>;
      final myMembership = members.firstWhere(
        (m) => m.userId == myUserId,
        orElse: () => GroupMember(
          id: '', userId: '', name: '', role: 'member',
          joinedAt: DateTime.now(),
        ),
      );
      final role = myMembership.role;
      final isLead = role == 'admin' || role == 'group_lead';
      final tabCount = isLead ? 3 : 2;

      if (!mounted) return;

      // Recreate controller only if tab count changed
      if (_tabController.length != tabCount) {
        final old = _tabController;
        _tabController = TabController(length: tabCount, vsync: this);
        old.dispose();
      }

      setState(() {
        _group = result['group'] as Group;
        _members = members;
        _myRole = role;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('GroupDetail._loadGroupDetail error: $e\n$st');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(color: AppColors.saffron)),
      );
    }

    if (_group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Group not found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_group!.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share invite code',
            onPressed: () => _showInviteCode(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.saffron,
          unselectedLabelColor: AppColors.lightText,
          indicatorColor: AppColors.saffron,
          tabs: [
            if (_isLead)
              Tab(icon: const Icon(Icons.people_outline, size: 20), text: S(ref.watch(languageProvider).appLanguage.code).members),
            Tab(icon: const Icon(Icons.calendar_today_outlined, size: 20), text: S(ref.watch(languageProvider).appLanguage.code).schedule),
            Tab(icon: const Icon(Icons.chat_bubble_outline, size: 20), text: S(ref.watch(languageProvider).appLanguage.code).groupChat),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (_isLead)
            _MembersTab(
              members: _members,
              isAdmin: _isAdmin,
              groupId: widget.groupId,
              onRoleChanged: _loadGroupDetail,
            ),
          _ScheduleTab(
            groupId: widget.groupId,
            group: _group!,
            canAssign: _canAssign,
            isAdmin: _isAdmin,
            members: _members,
          ),
          _ChatTab(groupId: widget.groupId),
        ],
      ),
    );
  }

  void _showInviteCode(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.saffron.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.share_outlined, color: AppColors.saffron, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Invite Code'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this code with others to join:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.lightText),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.saffron.withOpacity(0.2)),
              ),
              child: Center(
                child: SelectableText(
                  _group!.inviteCode,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 5,
                    color: AppColors.saffron,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ─── Members Tab ─────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final List<GroupMember> members;
  final bool isAdmin;
  final String groupId;
  final VoidCallback onRoleChanged;

  const _MembersTab({
    required this.members,
    required this.isAdmin,
    required this.groupId,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        return _MemberCard(
          member: member,
          isAdmin: isAdmin,
          groupId: groupId,
          onRoleChanged: onRoleChanged,
        );
      },
    );
  }
}

class _MemberCard extends ConsumerWidget {
  final GroupMember member;
  final bool isAdmin;
  final String groupId;
  final VoidCallback onRoleChanged;

  const _MemberCard({
    required this.member,
    required this.isAdmin,
    required this.groupId,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: _Avatar(name: member.name),
        title: Text(member.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(
          _roleLabel(member.role, tr),
          style: TextStyle(fontSize: 12, color: AppColors.lightText),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoleBadge(role: member.role),
            // Admin can tap to change role
            if (isAdmin && member.role != 'admin') ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showRoleSheet(context, ref),
                child: Icon(Icons.edit_outlined, size: 18, color: AppColors.lightText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role, AppTr tr) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'group_lead':
        return tr.groupLead;
      default:
        return tr.memberLabel;
    }
  }

  void _showRoleSheet(BuildContext context, WidgetRef ref) {
    final tr = S(ref.read(languageProvider).appLanguage.code);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Role for ${member.name}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Group Lead can assign chapters but cannot delete the group.',
                style: TextStyle(color: AppColors.lightText, fontSize: 13)),
            const SizedBox(height: 20),
            _RoleOption(
              icon: Icons.star_outline_rounded,
              label: tr.groupLead,
              description: 'Can assign & schedule chapters',
              selected: member.role == 'group_lead',
              onTap: () {
                Navigator.pop(ctx);
                _setRole(context, ref, 'group_lead');
              },
            ),
            const SizedBox(height: 8),
            _RoleOption(
              icon: Icons.person_outline,
              label: tr.memberLabel,
              description: 'Regular reader',
              selected: member.role == 'member',
              onTap: () {
                Navigator.pop(ctx);
                _setRole(context, ref, 'member');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRole(BuildContext context, WidgetRef ref, String role) async {
    try {
      await ref.read(groupsRepositoryProvider).setMemberRole(
        groupId: groupId,
        userId: member.userId,
        role: role,
      );
      onRoleChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update role. Please try again.')),
        );
      }
    }
  }
}

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _RoleOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.saffron.withOpacity(0.08) : AppColors.cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.saffron : AppColors.lightGrey,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.saffron : AppColors.mediumText, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected ? AppColors.saffron : AppColors.darkText)),
                  Text(description,
                      style: TextStyle(fontSize: 12, color: AppColors.lightText)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: AppColors.saffron, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Schedule Tab ─────────────────────────────────────────────────────────────

class _ScheduleTab extends ConsumerStatefulWidget {
  final String groupId;
  final Group group;
  final bool canAssign;
  final bool isAdmin;
  final List<GroupMember> members;

  const _ScheduleTab({
    required this.groupId,
    required this.group,
    required this.canAssign,
    required this.isAdmin,
    required this.members,
  });

  @override
  ConsumerState<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<_ScheduleTab> {
  List<Assignment> _assignments = [];
  bool _loading = true;
  int _selectedWeek = 1;
  int _currentWeek = 1;

  @override
  void initState() {
    super.initState();
    _currentWeek = widget.group.currentWeek;
    _selectedWeek = widget.group.currentWeek;
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(assignmentsRepositoryProvider);
      final all = await repo.getGroupAssignments(widget.groupId, weekNumber: _selectedWeek);
      setState(() {
        _assignments = all;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _autoSchedule() async {
    // Find the next unscheduled chapter (sequential — continue from where we left off)
    final allAssignments = await ref
        .read(assignmentsRepositoryProvider)
        .getGroupAssignments(widget.groupId);
    final assignedChapters = allAssignments.map((a) => a.chapterNumber ?? 0).toSet();
    int startChapter = 1;
    while (assignedChapters.contains(startChapter)) startChapter++;

    try {
      final result = await ref.read(assignmentsRepositoryProvider).autoSchedule(
        groupId: widget.groupId,
        startChapter: startChapter,
        weeksAhead: 4,
      );

      if (!mounted) return;
      _loadAssignments();

      // If there are remainder chapters, show a dialog asking what to do
      if (result.remainderChapters.isNotEmpty) {
        _showRemainderDialog(result.remainderChapters);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.assignments.length} assignments scheduled across 4 weeks ✓'
                  ' (chapters $startChapter–${startChapter + result.assignments.length - 1})',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not schedule: $e')),
        );
      }
    }
  }

  /// Shows a dialog informing the group lead about remainder chapters
  /// that couldn't be evenly distributed across members.
  void _showRemainderDialog(List<Map<String, dynamic>> remainders) {
    // Group by week for clarity
    final byWeek = <int, List<Map<String, dynamic>>>{};
    for (final r in remainders) {
      final w = r['week_number'] as int;
      byWeek.putIfAbsent(w, () => []).add(r);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Remainder Chapters'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'These chapters couldn\'t be evenly distributed because '
                'chapters-per-week isn\'t divisible by the number of members. '
                'You can assign them manually.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...byWeek.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Week ${entry.key}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ...entry.value.map((r) => Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      '• Ch.${r['chapter_number']} — ${r['chapter_title']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  )),
                  const SizedBox(height: 8),
                ],
              )),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text('Got it — I\'ll assign manually'),
          ),
        ],
      ),
    );
  }

  Future<void> _advanceWeek() async {
    try {
      final newWeek = await ref
          .read(assignmentsRepositoryProvider)
          .advanceWeek(widget.groupId);
      setState(() {
        _currentWeek = newWeek;
        _selectedWeek = newWeek;
      });
      _loadAssignments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to Week $_currentWeek')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not advance week. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Week selector + controls
        Container(
          color: AppColors.cream,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Week $_selectedWeek',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.darkText),
                    ),
                  ),
                  if (_selectedWeek > 1)
                    _WeekArrow(
                      icon: Icons.chevron_left,
                      onTap: () {
                        setState(() => _selectedWeek--);
                        _loadAssignments();
                      },
                    ),
                  const SizedBox(width: 6),
                  _WeekArrow(
                    icon: Icons.chevron_right,
                    onTap: () {
                      setState(() => _selectedWeek++);
                      _loadAssignments();
                    },
                  ),
                ],
              ),
              if (widget.canAssign) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.auto_awesome_outlined,
                        label: 'Auto-Schedule',
                        onTap: _autoSchedule,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.arrow_forward_outlined,
                        label: 'Next Week',
                        onTap: _advanceWeek,
                        outlined: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // Assignment list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.saffron))
              : _assignments.isEmpty
                  ? _EmptySchedule(canAssign: widget.canAssign, onAutoSchedule: _autoSchedule)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _assignments.length,
                      itemBuilder: (context, index) {
                        return _AssignmentCard(
                          assignment: _assignments[index],
                          canAssign: widget.canAssign,
                          onDelete: () async {
                            await ref
                                .read(assignmentsRepositoryProvider)
                                .deleteAssignment(_assignments[index].id);
                            _loadAssignments();
                          },
                          onProgressChanged: (status) async {
                            await ref
                                .read(assignmentsRepositoryProvider)
                                .updateProgress(_assignments[index].id, status);
                            _loadAssignments();
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _WeekArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _WeekArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.lightGrey),
        ),
        child: Icon(icon, size: 20, color: AppColors.saffron),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: outlined ? AppColors.white : AppColors.saffron,
          borderRadius: BorderRadius.circular(10),
          border: outlined ? Border.all(color: AppColors.saffron) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16,
                color: outlined ? AppColors.saffron : AppColors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: outlined ? AppColors.saffron : AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final bool canAssign;
  final VoidCallback onDelete;
  final void Function(String status) onProgressChanged;

  const _AssignmentCard({
    required this.assignment,
    required this.canAssign,
    required this.onDelete,
    required this.onProgressChanged,
  });

  Color get _statusColor {
    switch (assignment.status) {
      case ReadingStatus.completed:
        return AppColors.progressComplete;
      case ReadingStatus.inProgress:
        return AppColors.progressInProgress;
      default:
        return AppColors.progressNotStarted;
    }
  }

  String _statusLabel(AppTr tr) {
    switch (assignment.status) {
      case ReadingStatus.completed:
        return tr.completed;
      case ReadingStatus.inProgress:
        return tr.inProgress;
      default:
        return tr.notStarted;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use English fallback for status labels in this StatelessWidget
    final tr = S('en');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.go(
            '/reader/${assignment.chapterId}',
            extra: {
              'assignmentId': assignment.id,
              'groupId': assignment.groupId,
              'chapterTitle': assignment.chapterTitle ?? 'Chapter ${assignment.chapterNumber}',
            },
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.saffron.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ch. ${assignment.chapterNumber ?? assignment.chapterId}',
                  style: TextStyle(
                      color: AppColors.saffron,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  assignment.chapterTitle ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canAssign)
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.close, size: 18, color: AppColors.lightText),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: AppColors.lightText),
              const SizedBox(width: 4),
              Text(
                assignment.userName ?? 'Unassigned',
                style: TextStyle(fontSize: 13, color: AppColors.mediumText),
              ),
              const Spacer(),
              // Progress badge — tap to cycle status
              GestureDetector(
                onTap: () {
                  final next = assignment.status == ReadingStatus.notStarted
                      ? 'in_progress'
                      : assignment.status == ReadingStatus.inProgress
                          ? 'completed'
                          : 'not_started';
                  onProgressChanged(next);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    _statusLabel(tr),
                    style: TextStyle(
                        fontSize: 12,
                        color: _statusColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          if (assignment.scheduledDate != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.lightText),
                const SizedBox(width: 4),
                Text(
                  _formatDate(assignment.scheduledDate!),
                  style: TextStyle(fontSize: 12, color: AppColors.lightText),
                ),
              ],
            ),
          ],
        ],
      ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }
}

class _EmptySchedule extends StatelessWidget {
  final bool canAssign;
  final VoidCallback onAutoSchedule;

  const _EmptySchedule({required this.canAssign, required this.onAutoSchedule});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.saffron.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.calendar_today_outlined, size: 44, color: AppColors.saffron),
            ),
            const SizedBox(height: 20),
            Text('No chapters this week',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              canAssign
                  ? 'Tap Auto-Schedule to assign 2–3 chapters per week automatically'
                  : 'The group lead will assign chapters soon',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.lightText),
            ),
            if (canAssign) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAutoSchedule,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Auto-Schedule'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.saffron),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Chat Tab ─────────────────────────────────────────────────────────────────

class _ChatTab extends ConsumerStatefulWidget {
  final String groupId;

  const _ChatTab({required this.groupId});

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab> {
  final List<GroupMessage> _messages = [];
  final List<HighlightComment> _highlights = [];
  bool _loading = true;
  bool _showHighlights = false;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(groupChatRepositoryProvider);
      final msgs = await repo.getMessages(widget.groupId);
      final highs = await repo.getHighlightComments(widget.groupId);
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs.reversed); // oldest first
        _highlights
          ..clear()
          ..addAll(highs);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    try {
      final msg = await ref
          .read(groupChatRepositoryProvider)
          .sendMessage(widget.groupId, text);
      setState(() => _messages.add(msg));
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message. Please try again.')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String? get _myUserId {
    return ref.read(authStateProvider).user?.id;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toggle: Chat / Highlights
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: _ToggleChip(
                  label: 'Group Chat',
                  icon: Icons.chat_bubble_outline,
                  selected: !_showHighlights,
                  onTap: () => setState(() => _showHighlights = false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToggleChip(
                  label: 'Shared Highlights',
                  icon: Icons.format_quote_rounded,
                  selected: _showHighlights,
                  onTap: () => setState(() => _showHighlights = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.saffron))
              : _showHighlights
                  ? _HighlightsList(
                      highlights: _highlights,
                      myUserId: _myUserId,
                      groupId: widget.groupId,
                      onDelete: (id) async {
                        await ref.read(groupChatRepositoryProvider)
                            .deleteHighlightComment(widget.groupId, id);
                        _loadAll();
                      },
                    )
                  : _MessagesList(
                      messages: _messages,
                      myUserId: _myUserId,
                      scrollController: _scrollController,
                      groupId: widget.groupId,
                      onDelete: (id) async {
                        await ref.read(groupChatRepositoryProvider)
                            .deleteMessage(widget.groupId, id);
                        _loadAll();
                      },
                    ),
        ),
        // Message input (only for chat view)
        if (!_showHighlights)
          _MessageInput(
            controller: _inputController,
            onSend: _sendMessage,
          ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.saffron : AppColors.cream,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.saffron : AppColors.lightGrey),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? AppColors.white : AppColors.mediumText),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.white : AppColors.mediumText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  final List<GroupMessage> messages;
  final String? myUserId;
  final ScrollController scrollController;
  final String groupId;
  final void Function(String id) onDelete;

  const _MessagesList({
    required this.messages,
    required this.myUserId,
    required this.scrollController,
    required this.groupId,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.lightGrey),
            const SizedBox(height: 14),
            Text('No messages yet',
                style: TextStyle(color: AppColors.lightText, fontSize: 15)),
            const SizedBox(height: 6),
            Text('Say Sai Ram to start! 🙏',
                style: TextStyle(color: AppColors.lightText, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMe = msg.userId == myUserId;
        return _MessageBubble(
          message: msg,
          isMe: isMe,
          onLongPress: () => _confirmDelete(context, msg.id),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This will remove the message from the group.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(id);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMe;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _Avatar(name: message.userName, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppColors.saffron
                      : AppColors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  border: isMe ? null : Border.all(color: AppColors.lightGrey),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        message.userName,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.saffron),
                      ),
                    if (!isMe) const SizedBox(height: 2),
                    Text(
                      message.content,
                      style: TextStyle(
                          fontSize: 14,
                          color: isMe ? AppColors.white : AppColors.darkText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _time(message.createdAt),
                      style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? AppColors.white.withOpacity(0.7)
                              : AppColors.lightText),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _time(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _MessageInput({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.lightGrey)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: AppColors.lightText),
                filled: true,
                fillColor: AppColors.cream,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.saffron,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: AppColors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsList extends StatelessWidget {
  final List<HighlightComment> highlights;
  final String? myUserId;
  final String groupId;
  final void Function(String id) onDelete;

  const _HighlightsList({
    required this.highlights,
    required this.myUserId,
    required this.groupId,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.format_quote_rounded, size: 48, color: AppColors.lightGrey),
              const SizedBox(height: 14),
              Text('No highlights yet',
                  style: TextStyle(color: AppColors.lightText, fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                'Open a chapter, long-press a verse to share it here',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.lightText, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: highlights.length,
      itemBuilder: (context, index) {
        final h = highlights[index];
        final isMe = h.userId == myUserId;
        return _HighlightCard(
          highlight: h,
          isMe: isMe,
          onDelete: () => _confirmDelete(context, h.id),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete highlight?'),
        content: const Text('This will remove the highlight and your comment.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(id);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final HighlightComment highlight;
  final bool isMe;
  final VoidCallback onDelete;

  const _HighlightCard({
    required this.highlight,
    required this.isMe,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.saffron.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Highlighted verse
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.saffron,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chapter ${highlight.chapterNumber ?? highlight.chapterId}',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.saffron,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '"${highlight.highlightedText}"',
                        style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: AppColors.mediumText),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Comment
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(name: highlight.userName, size: 26),
                    const SizedBox(width: 8),
                    Text(highlight.userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    if (isMe)
                      GestureDetector(
                        onTap: onDelete,
                        child: Icon(Icons.delete_outline,
                            size: 17, color: AppColors.lightText),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(highlight.comment,
                    style: const TextStyle(fontSize: 14, color: AppColors.darkText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final double size;

  const _Avatar({required this.name, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.saffron.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: AppColors.saffron,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    if (role == 'member') return const SizedBox.shrink();

    final isLead = role == 'group_lead';
    // Use English fallback since this is a StatelessWidget without ref
    final label = isLead ? S('en').groupLead : 'Admin';
    final color = isLead ? AppColors.info : AppColors.saffron;
    final icon = isLead ? Icons.star_half_rounded : Icons.star_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
