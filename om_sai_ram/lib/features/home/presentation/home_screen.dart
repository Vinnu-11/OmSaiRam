// Om Sai Ram
// Home screen — overview dashboard with quick stats and navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/router_service.dart';
import '../../../core/providers/reading_progress_provider.dart';
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
    // Only load groups if authenticated
    final isLoggedIn = ref.read(authStateProvider).isAuthenticated;
    if (isLoggedIn) {
      Future.microtask(() => ref.read(groupsProvider.notifier).loadGroups());
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final groupsState = ref.watch(groupsProvider);
    final readingProgress = ref.watch(readingProgressProvider);
    final isLoggedIn = authState.isAuthenticated;
    final userName = authState.user?.name ?? 'Devotee';

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.schedule_rounded),
            tooltip: 'Daily Programme',
            onPressed: () => context.go(AppRoutes.dailyProgramme),
          ),
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

            const SizedBox(height: 14),

            // Daily Programme banner
            GestureDetector(
              onTap: () => context.go(AppRoutes.dailyProgramme),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.saffron.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.saffron.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.schedule_rounded,
                          color: AppColors.saffron, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Daily Programme',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.darkText,
                            ),
                          ),
                          Text(
                            'Shirdi temple schedule — aartis & timings',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 14, color: AppColors.saffron),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Streak + progress row
            Row(
              children: [
                // Streak card
                Expanded(
                  child: _StatCard(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: AppColors.deepOrange,
                    value: '${readingProgress.currentStreak}',
                    label: 'Day Streak',
                  ),
                ),
                const SizedBox(width: 12),
                // Chapters read card
                Expanded(
                  child: _StatCard(
                    icon: Icons.menu_book_rounded,
                    iconColor: AppColors.saffron,
                    value: '${readingProgress.completedChapters.length}',
                    label: 'Chapters Read',
                  ),
                ),
                const SizedBox(width: 12),
                // Bookmarks card
                Expanded(
                  child: _StatCard(
                    icon: Icons.bookmark_rounded,
                    iconColor: Colors.indigo,
                    value: '${readingProgress.bookmarks.length}',
                    label: 'Bookmarks',
                  ),
                ),
              ],
            ),

            // Resume reading button (if there's a saved position)
            if (readingProgress.resumeChapter != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => context.go('/reader/${readingProgress.resumeChapter}'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.saffron.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.saffron.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.play_circle_rounded, color: AppColors.saffron, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Continue Reading',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.saffron,
                              ),
                            ),
                            Text(
                              'Chapter ${readingProgress.resumeChapter} · ${(readingProgress.resumePosition * 100).toStringAsFixed(0)}% complete',
                              style: TextStyle(fontSize: 12, color: AppColors.mediumText),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.saffron),
                    ],
                  ),
                ),
              ),
            ],

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
                    onTap: () {
                      if (isLoggedIn) {
                        context.go('/groups/create');
                      } else {
                        context.go(AppRoutes.login);
                      }
                    },
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

            // My Groups summary (only when logged in)
            if (!isLoggedIn) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.lightGrey),
                ),
                child: Column(
                  children: [
                    Icon(Icons.group_outlined, size: 36, color: AppColors.saffron),
                    const SizedBox(height: 12),
                    Text(
                      'Sign in for Group Reading',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create or join a group to read together',
                      style: TextStyle(color: AppColors.lightText, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.login),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.saffron,
                      ),
                      child: const Text('Sign In'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ] else ...[

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
            ], // end else (logged-in groups section)

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

/// A compact stat card showing an icon, value, and label.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: iconColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppColors.lightText),
            textAlign: TextAlign.center,
          ),
        ],
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
