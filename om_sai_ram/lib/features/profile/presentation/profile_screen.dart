// Om Sai Ram
// Profile screen — user profile, settings, and app info.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/router_service.dart';
import '../../../core/services/notifications_service.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/providers/reader_settings_provider.dart';
import '../../../core/providers/reading_progress_provider.dart';
import '../../../core/l10n/s.dart';
import '../../auth/providers/auth_provider.dart';
import '../../reader/providers/reader_provider.dart';

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
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final langState = ref.watch(languageProvider);
    final readerSettings = ref.watch(readerSettingsProvider);
    final readingProgress = ref.watch(readingProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.profile),
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
              tr.settings,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.lightText,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
            ),
          ),

          // Reading stats row
          Row(
            children: [
              _MiniStatCard(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.deepOrange,
                value: '${readingProgress.currentStreak}',
                label: 'Streak',
              ),
              const SizedBox(width: 10),
              _MiniStatCard(
                icon: Icons.menu_book_rounded,
                color: AppColors.saffron,
                value: '${readingProgress.completedChapters.length}',
                label: 'Read',
              ),
              const SizedBox(width: 10),
              _MiniStatCard(
                icon: Icons.bookmark_rounded,
                color: Colors.indigo,
                value: '${readingProgress.bookmarks.length}',
                label: 'Saved',
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Settings list
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.person_outlined,
                  title: tr.editProfile,
                  onTap: () {},
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                _SettingsTile(
                  icon: Icons.language_outlined,
                  title: tr.language,
                  subtitle: langState.appLanguage.label,
                  onTap: () => _showLanguageDialog(context, ref, langState),
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                // Dark mode toggle
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.mediumText.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      readerSettings.darkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: AppColors.mediumText,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    tr.darkMode,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                  ),
                  trailing: Switch(
                    value: readerSettings.darkMode,
                    onChanged: (_) =>
                        ref.read(readerSettingsProvider.notifier).toggleDarkMode(),
                    activeColor: AppColors.saffron,
                  ),
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                _NotificationsTile(),
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
                  title: tr.faq,
                  onTap: () => context.go(AppRoutes.faq),
                ),
                Divider(height: 1, indent: 56, color: AppColors.lightGrey),
                _SettingsTile(
                  icon: Icons.info_outlined,
                  title: tr.about,
                  subtitle: 'Version 1.0.0',
                  onTap: () => _showAboutDialog(context, tr),
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
              title: tr.logout,
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
                    title: Text(tr.logout),
                    content: Text(tr.logoutConfirmBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        child: Text(tr.logout),
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

  void _showLanguageDialog(
      BuildContext context, WidgetRef ref, LanguageState langState) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LanguageSettingsSheet(langState: langState),
    );
  }

  void _showAboutDialog(BuildContext context, AppTr tr) {
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
            Text(tr.appName),
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

/// Bottom sheet for choosing app language and reader language.
class _LanguageSettingsSheet extends ConsumerStatefulWidget {
  final LanguageState langState;

  const _LanguageSettingsSheet({required this.langState});

  @override
  ConsumerState<_LanguageSettingsSheet> createState() =>
      _LanguageSettingsSheetState();
}

class _LanguageSettingsSheetState
    extends ConsumerState<_LanguageSettingsSheet> {
  late AppLanguage _appLang;
  late AppLanguage _readerLang;

  @override
  void initState() {
    super.initState();
    _appLang = widget.langState.appLanguage;
    _readerLang = widget.langState.readerLanguage;
  }

  @override
  Widget build(BuildContext context) {
    final tr = S(ref.watch(languageProvider).appLanguage.code);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              // Fixed header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.language_outlined,
                            color: AppColors.saffron, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          tr.languageSettings,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Scrollable language lists
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    // App language section
                    Text(
                      tr.appLanguageLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.mediumText,
                          ),
                    ),
                    const SizedBox(height: 10),
                    ...AppLanguage.values.map((lang) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _langRow(
                            lang: lang,
                            selected: _appLang == lang,
                            onTap: () => setState(() {
                              _appLang = lang;
                              _readerLang = lang;
                            }),
                          ),
                        )),

                    const SizedBox(height: 20),

                    // Reader language section
                    Text(
                      tr.readerLanguageLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.mediumText,
                          ),
                    ),
                    Text(
                      tr.readerLanguageHint,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.lightText),
                    ),
                    const SizedBox(height: 10),
                    ...AppLanguage.values.map((lang) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _langRow(
                            lang: lang,
                            selected: _readerLang == lang,
                            onTap: () =>
                                setState(() => _readerLang = lang),
                          ),
                        )),

                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // Fixed save button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.saffron,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(tr.save,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _langRow({
    required AppLanguage lang,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.saffron.withOpacity(0.08) : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.saffron : AppColors.lightGrey,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                lang.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: selected ? AppColors.saffron : AppColors.darkText,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: AppColors.saffron, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final notifier = ref.read(languageProvider.notifier);
    await notifier.setAppLanguage(_appLang);
    await notifier.setReaderLanguage(_readerLang);
    // Reload chapters with the new reader language.
    ref
        .read(chaptersProvider.notifier)
        .loadChapters(language: _readerLang.code);
    if (mounted) Navigator.pop(context);
  }
}

/// Notifications toggle — enables/disables daily verse reminder.
class _NotificationsTile extends StatefulWidget {
  @override
  State<_NotificationsTile> createState() => _NotificationsTileState();
}

class _NotificationsTileState extends State<_NotificationsTile> {
  bool _enabled = false;
  final _svc = NotificationsService();

  @override
  void initState() {
    super.initState();
    _svc.isEnabled().then((v) => setState(() => _enabled = v));
  }

  Future<void> _toggle() async {
    if (_enabled) {
      await _svc.cancelDailyVerse();
      setState(() => _enabled = false);
    } else {
      final granted = await _svc.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable notifications in system settings.')),
          );
        }
        return;
      }
      await _svc.scheduleDailyVerse(hour: 7, minute: 0);
      setState(() => _enabled = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily verse reminder set for 7:00 AM 🙏')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.mediumText.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.notifications_outlined, color: AppColors.mediumText, size: 20),
      ),
      title: const Text('Daily Verse',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
      subtitle: Text(
        _enabled ? 'Reminder at 7:00 AM' : 'Off',
        style: TextStyle(fontSize: 12, color: AppColors.lightText),
      ),
      trailing: Switch(
        value: _enabled,
        onChanged: (_) => _toggle(),
        activeColor: AppColors.saffron,
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MiniStatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: TextStyle(fontSize: 11, color: AppColors.lightText)),
          ],
        ),
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
