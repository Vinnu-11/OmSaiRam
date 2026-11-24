import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BackendMode { fastapi, firebase }

/// Public client identifiers of a real Firebase project. These are not secrets;
/// access is controlled by Auth and the deployed security rules.
class FirebaseProjectOptions {
  final String apiKey, appId, messagingSenderId, authDomain;
  /// Optional HTTPS origin of the deployed feed Functions; empty when absent.
  final String feedsBaseUrl;
  /// Optional OAuth web client ID that Google sign-in needs on Android.
  final String googleServerClientId;
  const FirebaseProjectOptions({required this.apiKey, required this.appId,
    required this.messagingSenderId, required this.authDomain,
    this.feedsBaseUrl = '', this.googleServerClientId = ''});
}

/// Firebase is the default backend on Android and web. The demo project always
/// means the local emulators (debug only); any other project is a real one and
/// never touches an emulator. There is no fallback between the two.
class BackendConfig {
  final BackendMode mode;
  final String emulatorHost;
  final String projectId;
  /// Null for the local emulators; set for a real Firebase project.
  final FirebaseProjectOptions? production;
  static const authPort = 9099;
  static const firestorePort = 8085;
  static const functionsPort = 5001;
  static const demoProjectId = 'demo-om-sai-ram';

  const BackendConfig._(this.mode, this.emulatorHost, this.projectId, [this.production]);

  /// True only for the local demo project.
  bool get emulator => mode == BackendMode.firebase && production == null;

  factory BackendConfig.fromEnvironment() => BackendConfig.parse(
        mode: const String.fromEnvironment('BACKEND_MODE'),
        host: const String.fromEnvironment('FIREBASE_EMULATOR_HOST',
            defaultValue: '127.0.0.1'),
        projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID',
            defaultValue: demoProjectId),
        apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
        appId: const String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId:
            const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        feedsBaseUrl: const String.fromEnvironment('FIREBASE_FEEDS_BASE_URL'),
        googleServerClientId:
            const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
        debug: kDebugMode,
        web: kIsWeb,
        platform: defaultTargetPlatform,
      );

  /// An empty [mode] selects the platform default: Firebase on Android and
  /// web, FastAPI elsewhere (Firebase is not configured for desktop or iOS).
  factory BackendConfig.parse({
    String mode = '',
    String host = '127.0.0.1',
    String projectId = demoProjectId,
    String apiKey = '',
    String appId = '',
    String messagingSenderId = '',
    String authDomain = '',
    String feedsBaseUrl = '',
    String googleServerClientId = '',
    required bool debug,
    required bool web,
    required TargetPlatform platform,
  }) {
    final supported = web || platform == TargetPlatform.android;
    if (mode.isEmpty) mode = supported ? 'firebase' : 'fastapi';
    if (mode != 'fastapi' && mode != 'firebase') {
      throw const FormatException('BACKEND_MODE must be fastapi or firebase.');
    }
    if (mode == 'fastapi') {
      return BackendConfig._(BackendMode.fastapi, host, projectId);
    }
    if (!supported) {
      throw const FormatException(
          'Firebase mode supports Android and web only. Use BACKEND_MODE=fastapi on native desktop/iOS.');
    }
    if (projectId == demoProjectId) {
      if (!debug) {
        throw const FormatException(
            'This release build has no Firebase project. Build with --dart-define-from-file=firebase.production.json (see docs/LAUNCH_CHECKLIST.md), or use BACKEND_MODE=fastapi.');
      }
      final allowed = {
        'localhost',
        '127.0.0.1',
        if (!web && platform == TargetPlatform.android) '10.0.2.2'
      };
      if (!allowed.contains(host)) {
        throw const FormatException(
            'FIREBASE_EMULATOR_HOST must be localhost or 127.0.0.1 (also 10.0.2.2 on Android), without scheme or port. Remote/cloud endpoints are not supported.');
      }
      return BackendConfig._(BackendMode.firebase, host, projectId);
    }
    // A real project: validated identifiers only, and never an emulator host.
    if (projectId.startsWith('demo-') ||
        !RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId)) {
      throw const FormatException(
          'FIREBASE_PROJECT_ID must be demo-om-sai-ram (local emulators) or a real Firebase project ID.');
    }
    final missing = [
      if (apiKey.isEmpty) 'FIREBASE_API_KEY',
      if (appId.isEmpty) 'FIREBASE_APP_ID',
      if (messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
    ];
    if (missing.isNotEmpty) {
      throw FormatException(
          'Firebase project $projectId is missing ${missing.join(', ')}.');
    }
    if (host != '127.0.0.1') {
      throw const FormatException(
          'FIREBASE_EMULATOR_HOST cannot be combined with a real Firebase project.');
    }
    if (feedsBaseUrl.isNotEmpty) {
      final feeds = Uri.tryParse(feedsBaseUrl);
      if (feeds == null || feeds.scheme != 'https' || feeds.host.isEmpty ||
          feeds.hasQuery || feeds.hasFragment || feeds.userInfo.isNotEmpty) {
        throw const FormatException(
            'FIREBASE_FEEDS_BASE_URL must be an https URL without query or credentials.');
      }
    }
    return BackendConfig._(
        BackendMode.firebase,
        host,
        projectId,
        FirebaseProjectOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: messagingSenderId,
            authDomain:
                authDomain.isEmpty ? '$projectId.firebaseapp.com' : authDomain,
            feedsBaseUrl: feedsBaseUrl,
            googleServerClientId: googleServerClientId));
  }
}

final backendConfigProvider =
    Provider<BackendConfig>((ref) => BackendConfig.fromEnvironment());
