// Om Sai Ram
// Main entry point for the Om Sai Ram application.
// This app helps devotees organize group readings of the Sai Baba Satcharita.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/backend_config.dart';
import 'core/services/firebase_bootstrap.dart';
import 'features/firebase_auth/data/firebase_auth_repository.dart';
import 'features/firebase_auth/data/firebase_provider_gateway.dart';
import 'features/firebase_account/data/firebase_account_gateway.dart';
import 'features/firebase_account/data/firebase_password_gateway.dart';
import 'features/firebase_groups/data/firestore_groups_gateway.dart';
import 'features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'features/firebase_tasks/data/firestore_tasks_gateway.dart';
import 'features/firebase_chat/data/firestore_chat_gateway.dart';
import 'features/firebase_highlights/data/firestore_highlights_gateway.dart';
import 'features/firebase_moderation/data/firestore_moderation_gateway.dart';
import 'features/firebase_membership/data/firestore_membership_gateway.dart';
import 'features/firebase_group_admin/data/firestore_group_admin_gateway.dart';
import 'features/firebase_scheduling/data/firestore_scheduling_gateway.dart';
import 'features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'features/firebase_reminders/data/firestore_reminders_gateway.dart';
import 'features/firebase_reminders/data/firestore_group_reminders_gateway.dart';
import 'register_web_plugins_stub.dart'
    if (dart.library.html) 'register_web_plugins.dart' as web_plugins;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  late final BackendConfig config;
  FirebaseServiceBundle? firebase;
  try {
    config = BackendConfig.fromEnvironment();
    if (config.mode == BackendMode.firebase) {
      firebase = await bootstrapFirebase(config);
    }
  } catch (error) {
    runApp(MaterialApp(
        home: Scaffold(
            body: SafeArea(
                child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(error is FormatException
          ? error.message
          : config.emulator
              ? 'Firebase emulator startup failed. Start Auth on 9099 and Firestore on 8085 for demo-om-sai-ram. Cloud fallback is not available.'
              : 'The app could not start. Check your connection and open it again.'),
    )))));
    return;
  }
  // Manually register just_audio_web on web — the auto-generated plugin
  // registrant sometimes fails to take effect in release builds.
  if (kIsWeb) {
    web_plugins.registerJustAudioWeb();
  }
  runApp(
    // ProviderScope wraps the entire app to enable Riverpod state management.
    ProviderScope(
      overrides: [
        backendConfigProvider.overrideWithValue(config),
        if (firebase != null)
          firebaseAuthGatewayProvider.overrideWithValue(firebase.auth),
        if (firebase != null)
          firebaseGroupsGatewayProvider.overrideWithValue(firebase.groups),
        if (firebase != null)
          firebaseAssignmentsGatewayProvider
              .overrideWithValue(firebase.assignments),
        if (firebase != null)
          firebaseTasksGatewayProvider.overrideWithValue(firebase.tasks),
        if (firebase != null)
          firebaseChatGatewayProvider.overrideWithValue(firebase.chat),
        if (firebase?.highlights != null)
          firebaseHighlightsGatewayProvider.overrideWithValue(firebase!.highlights!),
        if (firebase != null)
          firebaseModerationGatewayProvider.overrideWithValue(firebase.moderation),
        if (firebase?.membership != null)
          firebaseMembershipGatewayProvider.overrideWithValue(firebase!.membership!),
        if (firebase?.groupAdmin != null)
          firebaseGroupAdminGatewayProvider.overrideWithValue(firebase!.groupAdmin!),
        if (firebase?.scheduling != null)
          firebaseSchedulingGatewayProvider.overrideWithValue(firebase!.scheduling!),
        if (firebase?.memberDisplay != null)
          firebaseMemberDisplayGatewayProvider.overrideWithValue(firebase!.memberDisplay!),
        if (firebase?.reminders != null)
          firebaseRemindersGatewayProvider.overrideWithValue(firebase!.reminders!),
        if (firebase?.groupReminders != null)
          firebaseGroupRemindersGatewayProvider.overrideWithValue(firebase!.groupReminders!),
        if (firebase?.account != null)
          firebaseAccountGatewayProvider.overrideWithValue(firebase!.account!),
        if (firebase?.password != null)
          firebasePasswordGatewayProvider.overrideWithValue(firebase!.password!),
        if (firebase?.providers != null)
          firebaseProviderGatewayProvider.overrideWithValue(firebase!.providers!),
      ],
      child: const OmSaiRamApp(),
    ),
  );
}
