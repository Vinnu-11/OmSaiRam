// Om Sai Ram
// Group detail screen — shows members, assignments, and progress.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../data/group_model.dart';
import '../data/groups_repository.dart';

/// Displays detailed view of a group with tabs for members and assignments.
///
/// Shows:
/// - Group name and reading mode
/// - Invite code (shareable)
/// - Members list with their roles
/// - Chapter assignments and progress per member
class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Group? _group;
  List<GroupMember> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
      setState(() {
        _group = result['group'] as Group;
        _members = result['members'] as List<GroupMember>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.saffron),
        ),
      );
    }

    if (_group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline, size: 40, color: AppColors.error),
              ),
              const SizedBox(height: 16),
              Text(
                'Group not found',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'This group may have been deleted',
                style: TextStyle(color: AppColors.lightText),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_group!.name),
        actions: [
          // Share invite code
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
          tabs: const [
            Tab(text: AppStrings.members),
            Tab(text: AppStrings.assignments),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MembersTab(members: _members),
          _AssignmentsTab(groupId: widget.groupId, mode: _group!.mode),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.lightText,
                  ),
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
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
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

/// Tab showing the list of group members.
class _MembersTab extends StatelessWidget {
  final List<GroupMember> members;

  const _MembersTab({required this.members});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.lightGrey),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.saffron.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: AppColors.saffron,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            title: Text(
              member.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              member.isAdmin ? 'Admin' : 'Member',
              style: TextStyle(fontSize: 12, color: AppColors.lightText),
            ),
            trailing: member.isAdmin
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: AppColors.saffron, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          'Admin',
                          style: TextStyle(
                            color: AppColors.saffron,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// Tab showing chapter assignments (placeholder — full implementation in assignments feature).
class _AssignmentsTab extends StatelessWidget {
  final String groupId;
  final ReadingMode mode;

  const _AssignmentsTab({required this.groupId, required this.mode});

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
              child: Icon(
                Icons.assignment_outlined,
                size: 44,
                color: AppColors.saffron,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No assignments yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              mode == ReadingMode.chapterWise
                  ? 'Assign chapters to members'
                  : 'Set up weekly Saptah schedule',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.lightText,
                  ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                // TODO: Navigate to assignment creation
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Assignments'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.saffron,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
