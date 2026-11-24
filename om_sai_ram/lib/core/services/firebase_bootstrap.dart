import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/firebase_account/data/firebase_account_gateway.dart';
import '../../features/firebase_account/data/firebase_password_gateway.dart';
import '../../features/firebase_reminders/data/firestore_reminders_gateway.dart';
import '../../features/firebase_reminders/data/firestore_group_reminders_gateway.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../config/backend_config.dart';
import '../../features/firebase_auth/data/firebase_auth_repository.dart';
import '../../features/firebase_auth/data/firebase_provider_gateway.dart';
import '../../features/firebase_groups/data/firestore_groups_gateway.dart';
import '../../features/firebase_assignments/data/firestore_assignments_gateway.dart';
import '../../features/firebase_tasks/data/firestore_tasks_gateway.dart';
import '../../features/firebase_chat/data/firestore_chat_gateway.dart';
import '../../features/firebase_highlights/data/firestore_highlights_gateway.dart';
import '../../features/firebase_moderation/data/firestore_moderation_gateway.dart';
import '../../features/firebase_membership/data/firestore_membership_gateway.dart';
import '../../features/firebase_group_admin/data/firestore_group_admin_gateway.dart';
import '../../features/firebase_scheduling/data/firestore_scheduling_gateway.dart';
import '../../features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'firebase_web_emulator_stub.dart'
    if (dart.library.js_interop) 'firebase_web_emulator.dart';

class FirebaseServiceBundle {
  final FirebaseAuthGateway auth;
  final FirebaseGroupsGateway groups;
  final FirebaseAssignmentsGateway assignments;
  final FirebaseTasksGateway tasks;
  final FirebaseChatGateway chat;
  final FirebaseModerationGateway moderation;
    // Optional only for existing injected bundles; bootstrap always supplies it.
    final FirebaseHighlightsGateway? highlights;
  final FirebaseMembershipGateway? membership;
  final FirebaseGroupAdminGateway? groupAdmin;
  final FirebaseMemberDisplayGateway? memberDisplay;
  final FirebaseRemindersGateway? reminders;
  final FirebaseGroupRemindersGateway? groupReminders;
  final FirebaseSchedulingGateway? scheduling;
  final FirebaseAccountGateway? account;
  final FirebasePasswordGateway? password;
  final FirebaseProviderGateway? providers;
  const FirebaseServiceBundle(
      this.auth, this.groups, this.assignments, this.tasks, this.chat, this.moderation,
      {this.highlights, this.membership, this.groupAdmin, this.memberDisplay, this.reminders, this.groupReminders, this.scheduling, this.account, this.password, this.providers});
}

Future<FirebaseServiceBundle> bootstrapFirebase(BackendConfig config) async {
  // Revalidate before any SDK initialization, including injected configurations:
  // the build-time environment alone decides emulator versus real project.
  final validated = BackendConfig.fromEnvironment();
  if (config.mode != BackendMode.firebase ||
      validated.mode != BackendMode.firebase ||
      validated.projectId != config.projectId ||
      validated.emulator != config.emulator) {
    throw StateError(
        'Firebase bootstrap requires the build-time Firebase configuration.');
  }
  final production = config.production;
  if (kIsWeb && production == null) {
    prepareWebAuthEmulator(
        _emulatorApp, config.emulatorHost, BackendConfig.authPort);
  }
  final app = production == null
      ? await Firebase.initializeApp(
          name: _emulatorApp,
          options: FirebaseOptions(
            // Static nonsecret emulator placeholders; no google-services/cloud config.
            apiKey: 'fake-api-key',
            appId: '1:1234567890:android:0123456789abcdef012345',
            messagingSenderId: '1234567890',
            projectId: config.projectId,
          ),
        )
      : await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: production.apiKey,
            appId: production.appId,
            messagingSenderId: production.messagingSenderId,
            projectId: config.projectId,
            authDomain: production.authDomain,
          ),
        );
  final auth = FirebaseAuth.instanceFor(app: app);
  // Emulator endpoints are attached for the demo project only; a real project
  // never falls back to them and the demo project never reaches the cloud.
  if (production == null) {
    await auth.useAuthEmulator(config.emulatorHost, BackendConfig.authPort,
        automaticHostMapping: false);
  }
  // Web session restoration stays entirely SDK-managed, never secure storage.
  if (kIsWeb) {
    await auth.setPersistence(Persistence.LOCAL);
  }
  final firestore = FirebaseFirestore.instanceFor(app: app);
  firestore.settings = const Settings(persistenceEnabled: false);
  if (production == null) {
    firestore.useFirestoreEmulator(
        config.emulatorHost, BackendConfig.firestorePort,
        automaticHostMapping: false);
  }
  final serverClientId = production?.googleServerClientId ?? '';
  final membership = FirestoreMembershipGateway(auth, firestore);
  return FirebaseServiceBundle(
      FirebaseAuthRepository(auth, firestore, leaveGroup: membership.leave),
      FirestoreGroupsGateway(auth, firestore),
      FirestoreAssignmentsGateway(auth, firestore),
      FirestoreTasksGateway(auth, firestore),
      FirestoreChatGateway(auth, firestore),
      FirestoreModerationGateway(auth, firestore),
      highlights: FirestoreHighlightsGateway(auth, firestore),
      membership: membership,
      groupAdmin: FirestoreGroupAdminGateway(auth, firestore),
      scheduling: FirestoreSchedulingGateway(auth, firestore),
      memberDisplay: FirestoreMemberDisplayGateway(auth, firestore),
      reminders: FirestoreRemindersGateway(auth, firestore),
      groupReminders: FirestoreGroupRemindersGateway(auth, firestore),
      account: SdkFirebaseAccountGateway(auth, firestore),
      password: SdkFirebasePasswordGateway(auth),
      providers: SdkFirebaseProviderGateway(auth,
          web: kIsWeb,
          nativeGoogle: () => googleSignInCredential(
              serverClientId: serverClientId.isEmpty ? null : serverClientId)));
}

const _emulatorApp = 'om-sai-ram-emulator';
