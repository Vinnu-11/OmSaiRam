// Om Sai Ram
// App shell — bottom navigation + side drawer wrapper for main app screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/router_service.dart';
import '../../core/l10n/s.dart';
import '../../core/providers/language_provider.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Shell widget that provides bottom navigation bar and a side drawer.
///
/// Bottom nav: Home | Read | Groups (if logged in) | Live
/// Drawer: Daily Programs, Upcoming Festivals, Audio, Live, Profile
class AppShell extends ConsumerStatefulWidget {
  /// Global key used by child screens to programmatically open the drawer.
  static final scaffoldKey = GlobalKey<ScaffoldState>();

  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  Widget build(BuildContext context) {
    final langCode = ref.watch(languageProvider).appLanguage.code;
    final tr = S(langCode);
    final isLoggedIn = ref.watch(authStateProvider).isAuthenticated;
    final userName = ref.watch(authStateProvider).user?.name;

    return Scaffold(
      key: AppShell.scaffoldKey,
      body: widget.child,
      drawer: _AppDrawer(tr: tr, isLoggedIn: isLoggedIn, userName: userName),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.lightGrey, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _calculateSelectedIndex(context, isLoggedIn),
          onTap: (index) => _onItemTapped(index, context, isLoggedIn),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home),
              label: tr.home,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.auto_stories_outlined),
              activeIcon: const Icon(Icons.auto_stories),
              label: tr.read,
            ),
            if (isLoggedIn)
              BottomNavigationBarItem(
                icon: const Icon(Icons.group_outlined),
                activeIcon: const Icon(Icons.group),
                label: tr.groups,
              ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.live_tv_outlined),
              activeIcon: const Icon(Icons.live_tv),
              label: tr.live,
            ),
          ],
        ),
      ),
    );
  }

  /// Determines the active tab index based on the current route.
  int _calculateSelectedIndex(BuildContext context, bool isLoggedIn) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRoutes.reader)) return 1;
    if (isLoggedIn && location.startsWith(AppRoutes.groups)) return 2;
    if (location == AppRoutes.liveDarshan) return isLoggedIn ? 3 : 2;
    return 0; // Home
  }

  /// Navigates to the corresponding route when a tab is tapped.
  void _onItemTapped(int index, BuildContext context, bool isLoggedIn) {
    switch (index) {
      case 0:
        context.go(AppRoutes.home);
        break;
      case 1:
        context.go(AppRoutes.reader);
        break;
      case 2:
        context.go(isLoggedIn ? AppRoutes.groups : AppRoutes.liveDarshan);
        break;
      case 3:
        context.go(AppRoutes.liveDarshan);
        break;
    }
  }
}

/// Side drawer with links to Daily Programs, Festivals, Audio, Live, Profile.
class _AppDrawer extends ConsumerWidget {
  final AppTr tr;
  final bool isLoggedIn;
  final String? userName;

  const _AppDrawer({
    required this.tr,
    required this.isLoggedIn,
    required this.userName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header
          DrawerHeader(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.saffron, AppColors.deepOrange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  '🕉️',
                  style: TextStyle(fontSize: 32),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Om Sai Ram',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isLoggedIn ? (userName ?? 'Devotee') : 'Sai Satcharita',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Daily Programs
          _DrawerTile(
            icon: Icons.schedule_rounded,
            label: tr.dailyProgramme,
            onTap: () {
              Navigator.pop(context);
              context.go(AppRoutes.dailyProgramme);
            },
          ),

          // Upcoming Festivals
          _DrawerTile(
            icon: Icons.celebration_rounded,
            label: tr.upcomingEvents,
            onTap: () {
              Navigator.pop(context);
              context.go(AppRoutes.events);
            },
          ),

          // Audio
          _DrawerTile(
            icon: Icons.headphones_outlined,
            label: tr.audio,
            onTap: () {
              Navigator.pop(context);
              context.go(AppRoutes.audio);
            },
          ),

          // Live Darshan
          _DrawerTile(
            icon: Icons.live_tv_outlined,
            label: tr.live,
            onTap: () {
              Navigator.pop(context);
              context.go(AppRoutes.liveDarshan);
            },
          ),

          const Divider(height: 1),

          // Profile
          _DrawerTile(
            icon: Icons.person_outline_rounded,
            label: tr.profile,
            onTap: () {
              Navigator.pop(context);
              context.go(AppRoutes.profile);
            },
          ),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.saffron, size: 22),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.darkText,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}
