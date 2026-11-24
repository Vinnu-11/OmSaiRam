// Om Sai Ram
// Root application widget — configures theme, routing, and localization.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/services/router_service.dart';
import 'core/providers/reader_settings_provider.dart';
import 'core/providers/language_provider.dart';
import 'core/providers/text_scale_provider.dart';
import 'core/config/backend_config.dart';
import 'features/firebase_reminders/providers/firebase_device_reminders_provider.dart';
import 'features/firebase_reminders/presentation/firebase_device_reminder_controls.dart';

class OmSaiRamApp extends ConsumerWidget {
  const OmSaiRamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final langCode = ref.watch(languageProvider).appLanguage.code;

    final application = MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      // The reader's own text-size choice multiplies the phone's setting,
      // capped so layouts stay usable.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = (media.textScaler.scale(1) * ref.watch(textScaleProvider))
            .clamp(1.0, 2.0);
        return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: child!);
      },
      locale: Locale(langCode),
      supportedLocales: AppLanguage.available.map((l) => Locale(l.code)).toList(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
    return ref.read(backendConfigProvider).mode == BackendMode.firebase && firebaseNativeReminderPlatform
      ? FirebaseDeviceReminderHost(child: application) : application;
  }
}
