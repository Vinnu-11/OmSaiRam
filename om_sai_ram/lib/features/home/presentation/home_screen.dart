// Om Sai Ram
// Home screen — overview dashboard with quick stats and navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/router_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';

/// Home/Overview screen — the main dashboard after login.
///
/// Shows:
/// - Welcome message with user's name
/// - Quick action cards (Create Group, Read Chapter, etc.)
/// - Groups summary
/// - Inspirational quote at bottom
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(groupsProvider.notifier).loadGroups());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final groupsState = ref.watch(groupsProvider);
    final userName = authState.user?.name ?? 'Devotee';

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: AppStrings.faq,
            onPressed: () => context.go(AppRoutes.faq),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome section with greeting
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.saffron.withOpacity(0.08),
                    AppColors.saffron.withOpacity(0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Om Sai Ram,',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.saffron,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userName,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 26,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.appTagline,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.lightText,
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Quick action cards
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.group_add_outlined,
                    label: AppStrings.createGroup,
                    color: AppColors.saffron,
                    onTap: () => context.go('/groups/create'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.auto_stories_outlined,
                    label: 'Read',
                    color: AppColors.deepOrange,
                    onTap: () => context.go(AppRoutes.reader),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // My Groups summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Groups',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                TextButton.icon(
                  onPressed: () => context.go(AppRoutes.groups),
                  icon: const Text('View All'),
                  label: const Icon(Icons.arrow_forward_ios, size: 14),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.saffron,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (groupsState.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.saffron),
                ),
              )
            else if (groupsState.groups.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.lightGrey),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.saffron.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.group_outlined,
                        size: 40,
                        color: AppColors.saffron,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No groups yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create or join a group to get started',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.lightText,
                          ),
                    ),
                  ],
                ),
              )
            else
              ...groupsState.groups.take(3).map(
                    (group) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.lightGrey),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.saffron.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_stories,
                            color: AppColors.saffron,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          group.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${group.memberCount} members',
                          style: TextStyle(
                            color: AppColors.lightText,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: AppColors.mediumText,
                        ),
                        onTap: () => context.go('/groups/${group.id}'),
                      ),
                    ),
                  ),

            const SizedBox(height: 32),

            // Inspirational quote
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.saffron.withOpacity(0.06),
                    AppColors.deepOrange.withOpacity(0.03),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.saffron.withOpacity(0.15),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.format_quote_rounded,
                      color: AppColors.saffron,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '"Before we begin any task, we must first remember Sai Baba and seek His blessings."',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '— Sai Satcharita',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.lightText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// A compact action card with icon and label.
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.lightGrey),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.darkText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
