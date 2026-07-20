// Om Sai Ram
// App shell — bottom navigation wrapper for main app screens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/router_service.dart';

/// Shell widget that provides bottom navigation bar.
///
/// Wraps the main app screens (Home, Groups, Reader, Profile)
/// with a persistent bottom navigation bar for easy switching.
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.lightGrey, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _calculateSelectedIndex(context),
          onTap: (index) => _onItemTapped(index, context),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: AppStrings.home,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories_outlined),
              activeIcon: Icon(Icons.auto_stories),
              label: AppStrings.reader,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.headphones_outlined),
              activeIcon: Icon(Icons.headphones),
              label: 'Audio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.live_tv_outlined),
              activeIcon: Icon(Icons.live_tv),
              label: 'Live',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outlined),
              activeIcon: Icon(Icons.person),
              label: AppStrings.profile,
            ),
          ],
        ),
      ),
    );
  }

  /// Determines the active tab index based on the current route.
  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(AppRoutes.reader)) return 1;
    if (location.startsWith(AppRoutes.audio)) return 2;
    if (location == AppRoutes.liveDarshan) return 3;
    if (location.startsWith(AppRoutes.profile)) return 4;
    return 0; // Home
  }

  /// Navigates to the corresponding route when a tab is tapped.
  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go(AppRoutes.home);
        break;
      case 1:
        context.go(AppRoutes.reader);
        break;
      case 2:
        context.go(AppRoutes.audio);
        break;
      case 3:
        context.go(AppRoutes.liveDarshan);
        break;
      case 4:
        context.go(AppRoutes.profile);
        break;
    }
  }
}
