// Om Sai Ram
// Profile screen — user profile, settings, and app info.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/router_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Profile screen showing user info, settings, and logout.
///
/// Sections:
/// - User avatar and name
/// - Settings list (language, notifications, etc.)
/// - About and logout
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.profile),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // User info header
          Container(
            padding: const EdgeInsets.all(24),
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
              children: [
                // Avatar with ring
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.saffron.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.saffron.withOpacity(0.12),
                    child: Text(
                      user?.name.isNotEmpty == true
                          ? user!.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.saffron,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user?.name ?? 'User',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.lightText,
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Settings section label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.lightText,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
            ),
          ),

          // Settings list
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.person_outlined,
                  title: AppStrings.editProfile,
                  onTap: () {},
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                _SettingsTile(
                  icon: Icons.language_outlined,
                  title: AppStrings.language,
                  subtitle: 'English',
                  onTap: () {},
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: AppStrings.notifications,
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Support section label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Support',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.lightText,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.help_outline,
                  title: AppStrings.faq,
                  onTap: () => context.go(AppRoutes.faq),
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                _SettingsTile(
                  icon: Icons.info_outlined,
                  title: AppStrings.about,
                  subtitle: 'Version 1.0.0',
                  onTap: () => _showAboutDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Logout button
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withOpacity(0.2)),
            ),
            child: _SettingsTile(
              icon: Icons.logout_rounded,
              title: AppStrings.logout,
              iconColor: AppColors.error,
              titleColor: AppColors.error,
              showChevron: false,
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await ref.read(authStateProvider.notifier).logout();
                }
              },
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
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
              child: Icon(Icons.auto_stories, color: AppColors.saffron, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(AppStrings.appName),
          ],
        ),
        content: const Text(
          'Om Sai Ram helps devotees organize group readings of the '
          'Shri Sai Satcharita.\n\n'
          'Built with devotion for the Sai community.\n\n'
          'Version 1.0.0',
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

/// A single settings row with icon, title, optional subtitle, and tap action.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? titleColor;
  final bool showChevron;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.showChevron = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.mediumText).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.mediumText, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: AppColors.lightText),
            )
          : null,
      trailing: showChevron
          ? Icon(Icons.chevron_right, color: AppColors.lightText, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
