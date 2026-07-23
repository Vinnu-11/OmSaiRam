// Om Sai Ram
// Groups list screen — displays all groups the user belongs to.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/providers/language_provider.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../core/l10n/s.dart';
import '../data/group_model.dart';
import '../providers/groups_provider.dart';

/// Displays the user's groups with options to create or join a group.
///
/// Shows a card for each group with:
/// - Group name and description
/// - Reading mode badge (Chapter-wise / Saptah)
/// - Member count
/// - Tap to navigate to group detail
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    // Load groups when screen is first displayed
    Future.microtask(() => ref.read(groupsProvider.notifier).loadGroups());
  }

  @override
  Widget build(BuildContext context) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    final groupsState = ref.watch(groupsProvider);

    // Show error snackbar on failures
    ref.listen<GroupsState>(groupsProvider, (prev, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(next.error!)),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
        ref.read(groupsProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.groups),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'create_group_fab',
            onPressed: () => context.go('/groups/create'),
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.saffron,
            elevation: 2,
            icon: const Icon(Icons.add),
            label: Text(tr.createGroup),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'join_group_fab',
            onPressed: () => _showJoinGroupDialog(context, tr),
            backgroundColor: AppColors.saffron,
            foregroundColor: AppColors.white,
            icon: const Icon(Icons.group_add_outlined),
            label: Text(tr.joinGroup),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: _buildBody(groupsState, tr),
    );
  }

  Widget _buildBody(GroupsState state, AppTr tr) {
    if (state.isLoading && state.groups.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.saffron),
      );
    }

    if (state.groups.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: AppColors.saffron,
      onRefresh: () => ref.read(groupsProvider.notifier).loadGroups(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: state.groups.length,
        itemBuilder: (context, index) => _GroupCard(group: state.groups[index], tr: tr),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.saffron.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.group_outlined,
                size: 56,
                color: AppColors.saffron,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No groups yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new group or join one\nwith an invite code',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.lightText,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Shows dialog to enter an invite code to join a group.
  void _showJoinGroupDialog(BuildContext context, AppTr tr) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

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
              child: Icon(Icons.group_add, color: AppColors.saffron, size: 20),
            ),
            const SizedBox(width: 10),
            Text(tr.joinGroup),
          ],
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            validator: Validators.inviteCode,
            decoration: InputDecoration(
              hintText: 'Enter invite code',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr.cancel),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              final success = await ref
                  .read(groupsProvider.notifier)
                  .joinGroup(controller.text.trim());
              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Successfully joined group!'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.saffron),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

/// Card widget displaying a single group's summary.
class _GroupCard extends StatelessWidget {
  final Group group;
  final AppTr tr;

  const _GroupCard({required this.group, required this.tr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lightGrey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.go('/groups/${group.id}'),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Group icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.saffron.withOpacity(0.15),
                            AppColors.saffron.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_stories,
                        color: AppColors.saffron,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Group name and mode
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _ModeBadge(mode: group.mode, tr: tr),
                        ],
                      ),
                    ),
                    // Arrow
                    Icon(Icons.chevron_right, color: AppColors.lightText, size: 20),
                  ],
                ),
                if (group.description != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    group.description!,
                    style: TextStyle(
                      color: AppColors.mediumText,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                // Member count
                Row(
                  children: [
                    Icon(Icons.people_outline, size: 15, color: AppColors.lightText),
                    const SizedBox(width: 4),
                    Text(
                      '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'}',
                      style: TextStyle(
                        color: AppColors.lightText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge showing the reading mode (Chapter-wise / Weekly Saptah).
class _ModeBadge extends StatelessWidget {
  final ReadingMode mode;
  final AppTr tr;

  const _ModeBadge({required this.mode, required this.tr});

  @override
  Widget build(BuildContext context) {
    final isChapter = mode == ReadingMode.chapterWise;
    final color = isChapter ? AppColors.info : AppColors.deepOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isChapter ? tr.chapterWise : tr.weeklySaptah,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
