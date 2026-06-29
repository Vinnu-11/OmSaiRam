// Om Sai Ram
// Root application widget — configures theme, routing, and localization.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/services/router_service.dart';

/// The root widget of the Om Sai Ram application.
///
/// Sets up MaterialApp with:
/// - Custom minimalist theme (warm saffron/white palette)
/// - GoRouter-based declarative navigation
/// - Localization support for future multi-language content
class OmSaiRamApp extends ConsumerWidget {
  const OmSaiRamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
