import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/presentation/firebase_auth_screen.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_home/presentation/firebase_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

BackendConfig config(
        {String mode = 'firebase',
        String host = '127.0.0.1',
        String project = BackendConfig.demoProjectId,
        bool debug = true,
        bool web = false,
        TargetPlatform platform = TargetPlatform.android}) =>
    BackendConfig.parse(
        mode: mode,
        host: host,
        projectId: project,
        debug: debug,
        web: web,
        platform: platform);

class FakeGateway implements FirebaseAuthGateway {
  final changes = StreamController<FirebaseIdentity?>.broadcast();
  @override
  FirebaseIdentity? currentUser;
  String? profile;
  Object? authError;
  Object? profileError;
  Completer<void>? authGate;
  Completer<String?>? readGate;
  int signups = 0;
  int signins = 0;
  int reads = 0;
  int writes = 0;
  @override
  Stream<FirebaseIdentity?> authStateChanges() => changes.stream;
  void emit(FirebaseIdentity? user) {
    currentUser = user;
    changes.add(user);
  }

  @override
  Future<void> signUp(String email, String password) async {
    signups++;
    await authGate?.future;
    if (authError != null) throw authError!;
    emit(FirebaseIdentity('firebase-uid', email));
  }

  @override
  Future<void> signIn(String email, String password) async {
    signins++;
    if (authError != null) throw authError!;
    emit(FirebaseIdentity('firebase-uid', email));
  }

  @override
  Future<void> signOut() async => emit(null);
  @override
  Future<String?> readProfile(String uid) async {
    reads++;
    if (profileError != null) throw profileError!;
    if (readGate != null) return readGate!.future;
    if (deactivated) throw const FirebaseAccountDeactivated();
    return profile;
  }

  @override
  Future<String> ensureProfile(String uid, String displayName) async {
    writes++;
    final name = validateDisplayName(displayName);
    if (profileError != null) throw profileError!;
    if (deactivated) throw const FirebaseAccountDeactivated();
    return profile ??= name;
  }

  bool deactivated = false;
  Object? lifecycleError;
  final lifecycle = <bool>[];
  @override
  Future<void> setAccountDeactivated(String uid, bool value) async {
    lifecycle.add(value);
    if (lifecycleError != null) throw lifecycleError!;
    deactivated = value;
  }

  Object? deleteError;
  int deletions = 0, retained = 0;
  @override
  Future<int> deleteAccount(String uid) async {
    deletions++;
    if (deleteError != null) throw deleteError!;
    profile = null;
    emit(null);
    return retained;
  }
}

class NoNetworkAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody.fromString('{}', 401);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('emulator configuration', () {
    test('Firebase is the default on Android and web; desktop and iOS default to FastAPI', () {
      final value = BackendConfig.parse(
          debug: false, web: false, platform: TargetPlatform.linux);
      expect(value.mode, BackendMode.fastapi);
      expect(value.emulatorHost, '127.0.0.1');
      expect(BackendConfig.parse(debug: true, web: false, platform: TargetPlatform.iOS).mode,
          BackendMode.fastapi);
      for (final web in [false, true]) {
        final firebase = BackendConfig.parse(debug: true, web: web,
            platform: web ? TargetPlatform.linux : TargetPlatform.android);
        expect(firebase.mode, BackendMode.firebase); expect(firebase.emulator, isTrue);
        expect(firebase.production, isNull);
      }
      expect(
          config(
                  mode: 'fastapi',
                  host: 'cloud.invalid',
                  project: 'live',
                  debug: false)
              .mode,
          BackendMode.fastapi);
      expect(BackendConfig.fromEnvironment().mode, BackendMode.firebase);
      expect(BackendConfig.fromEnvironment().emulator, isTrue);
    });
    group('real Firebase project', () {
      BackendConfig real({String project = 'om-sai-sannidhi', String apiKey = 'key', String appId = 'app',
              String sender = '123', String host = '127.0.0.1', String feeds = '', String domain = '',
              bool debug = false}) =>
          BackendConfig.parse(mode: 'firebase', projectId: project, apiKey: apiKey, appId: appId,
              messagingSenderId: sender, host: host, feedsBaseUrl: feeds, authDomain: domain,
              debug: debug, web: false, platform: TargetPlatform.android);
      test('release and debug builds accept complete public options and never the emulator', () {
        for (final debug in [false, true]) {
          final value = real(debug: debug);
          expect(value.mode, BackendMode.firebase); expect(value.emulator, isFalse);
          expect(value.projectId, 'om-sai-sannidhi');
          expect(value.production!.apiKey, 'key'); expect(value.production!.appId, 'app');
          expect(value.production!.messagingSenderId, '123');
          expect(value.production!.authDomain, 'om-sai-sannidhi.firebaseapp.com');
        }
        expect(real(domain: 'auth.example.org').production!.authDomain, 'auth.example.org');
      });
      test('a release without a project explains the build configuration', () {
        expect(() => config(debug: false), throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('firebase.production.json'))));
      });
      test('missing options, demo-like or malformed IDs and emulator hosts fail closed', () {
        expect(() => real(apiKey: ''), throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('FIREBASE_API_KEY'))));
        for (final action in <BackendConfig Function()>[
          () => real(appId: ''), () => real(sender: ''), () => real(project: 'demo-live'),
          () => real(project: 'Bad_ID'), () => real(project: 'ab'), () => real(host: '10.0.2.2'),
          () => real(host: 'localhost'),
        ]) { expect(action, throwsFormatException); }
      });
      test('feed URL must be plain https; it is optional', () {
        expect(real().production!.feedsBaseUrl, isEmpty);
        expect(real(feeds: 'https://asia-south1-om-sai-sannidhi.cloudfunctions.net').production!.feedsBaseUrl,
            startsWith('https://'));
        for (final feeds in ['http://example.org', 'https://', 'ftp://example.org', 'https://u:p@example.org',
          'https://example.org?x=1', 'https://example.org#x', 'not a url']) {
          expect(() => real(feeds: feeds), throwsFormatException);
        }
      });
    });
    for (final mode in ['Firebase', 'cloud', ' fastapi']) {
      test('invalid mode $mode fails closed',
          () => expect(() => config(mode: mode), throwsFormatException));
    }
    test('release/profile emulator forbidden',
        () => expect(() => config(debug: false), throwsFormatException));
    test('only pinned demo project accepted', () {
      for (final project in [
        'live-project',
        'demo-other',
        '',
        'demo-om-sai-ram '
      ]) {
        expect(() => config(project: project), throwsFormatException);
      }
    });
    for (final host in ['127.0.0.1', 'localhost', '10.0.2.2']) {
      test('explicit Android host $host retained without implicit mapping',
          () => expect(config(host: host).emulatorHost, host));
    }
    for (final host in [
      'https://localhost',
      '127.0.0.1:9099',
      '192.168.1.2',
      'example.com',
      '0.0.0.0',
      '127.0.0.2',
      '',
      ' localhost'
    ]) {
      test('reject nonallowed endpoint $host',
          () => expect(() => config(host: host), throwsFormatException));
    }
    test('web debug allowed; Android bridge host forbidden on web', () {
      expect(config(web: true, platform: TargetPlatform.linux).mode,
          BackendMode.firebase);
      expect(() => config(web: true, host: '10.0.2.2'), throwsFormatException);
    });
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia
    ]) {
      test(
          'native $platform unsupported',
          () =>
              expect(() => config(platform: platform), throwsFormatException));
    }
  });

  test('all legacy HTTP blocked before storage/network, including 401 refresh',
      () async {
    var storageCalls = 0;
    var expiredCalls = 0;
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      storageCalls++;
      return 'stale-legacy-token';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final adapter = NoNetworkAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(config: config(), dio: dio)
      ..onSessionExpired = () => expiredCalls++;
    for (final request in <Future<Response> Function()>[
      () => client.get('/auth/me'),
      () => client.post('/auth/login'),
      () => client.post('/auth/refresh'),
      () => client.put('/groups/a'),
      () => client.patch('/profile'),
      () => client.delete('/auth/me'),
      () => client.get('https://example.com/anything'),
    ]) {
      await expectLater(
          request(),
          throwsA(isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)));
    }
    // A synthetic 401 must also not enter the refresh path.
    dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(
          DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 401)),
          true);
    }));
    await expectLater(client.get('/groups'), throwsA(isA<DioException>()));
    expect(adapter.calls, 0);
    expect(storageCalls, 0);
    expect(expiredCalls, 0);
  });

  group('Firebase sessions', () {
    late FakeGateway gateway;
    late ProviderContainer container;
    late FirebaseSessionController controller;
    setUp(() async {
      gateway = FakeGateway();
      container = ProviderContainer(
          overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)]);
      container.listen(firebaseSessionProvider, (_, __) {});
      controller = container.read(firebaseSessionProvider.notifier);
      gateway.emit(null);
      await Future<void>.delayed(Duration.zero);
    });
    tearDown(() async {
      container.dispose();
      await gateway.changes.close();
    });
    test('login failure is friendly, no secret or profile work', () async {
      gateway.authError = FirebaseAuthException(
          code: 'invalid-credential', message: 'password/token secret');
      await controller.signIn('test@example.com', 'secret');
      final session = container.read(firebaseSessionProvider);
      expect(session.user, isNull);
      expect(session.error, 'Email or password is incorrect.');
      expect(session.busy, isFalse);
      expect(gateway.reads, 0);
    });
    test(
        'signup Auth success plus profile failure retains user and error despite stream event; repair retry',
        () async {
      gateway.profileError = StateError('Firestore offline');
      await controller.signUp('test@example.com', 'secret', ' Sai ');
      gateway.emit(gateway.currentUser);
      await Future<void>.delayed(Duration.zero);
      var session = container.read(firebaseSessionProvider);
      expect(session.user?.uid, 'firebase-uid');
      expect(session.ready, isFalse);
      expect(session.error, contains('not been deleted'));
      gateway.profileError = null;
      await controller.retryProfile('Sai');
      session = container.read(firebaseSessionProvider);
      expect(session.ready, isTrue);
      expect(session.displayName, 'Sai');
      expect(gateway.signups, 1);
      expect(gateway.writes, 2);
    });
    test('restoration waits for server profile, missing profile is not ready',
        () async {
      gateway.readGate = Completer<String?>();
      gateway.emit(const FirebaseIdentity('restored', 'restored@example.com'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(firebaseSessionProvider).busy, isTrue);
      expect(container.read(firebaseSessionProvider).ready, isFalse);
      gateway.readGate!.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(firebaseSessionProvider).busy, isFalse);
      expect(container.read(firebaseSessionProvider).ready, isFalse);
      expect(gateway.writes, 0);
    });
    test('restored existing profile succeeds; logout clears session', () async {
      gateway.profile = 'Existing name';
      gateway.emit(const FirebaseIdentity('restored', 'test@example.com'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(firebaseSessionProvider).ready, isTrue);
      expect(
          container.read(firebaseSessionProvider).displayName, 'Existing name');
      await controller.signOut();
      expect(container.read(firebaseSessionProvider).user, isNull);
    });
    test('restoration failure stays visible until explicit read retry',
        () async {
      gateway.profileError = StateError('permission denied');
      gateway.emit(const FirebaseIdentity('restored', 'test@example.com'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(firebaseSessionProvider).error, isNotNull);
      gateway.profileError = null;
      gateway.profile = 'Existing';
      await controller.reloadProfile();
      expect(container.read(firebaseSessionProvider).ready, isTrue);
    });
    test('concurrent signup disabled and profile not ready before completion',
        () async {
      gateway.authGate = Completer<void>();
      final first = controller.signUp('test@example.com', 'secret', 'Sai');
      await controller.signUp('test@example.com', 'secret', 'Sai');
      expect(gateway.signups, 1);
      expect(container.read(firebaseSessionProvider).busy, isTrue);
      expect(container.read(firebaseSessionProvider).ready, isFalse);
      gateway.authGate!.complete();
      await first;
      expect(container.read(firebaseSessionProvider).ready, isTrue);
    });
    test('invalid name never creates Auth account', () async {
      for (final name in ['   ', 'x' * 101]) {
        await controller.signUp('test@example.com', 'secret', name);
        expect(container.read(firebaseSessionProvider).error, isNotNull);
      }
      expect(gateway.signups, 0);
      expect(validateDisplayName('x' * 100).length, 100);
    });
    test('stale restoration cannot resurrect logged-out user', () async {
      gateway.readGate = Completer<String?>();
      gateway.emit(const FirebaseIdentity('restored', 'test@example.com'));
      await Future<void>.delayed(Duration.zero);
      gateway.emit(null);
      await Future<void>.delayed(Duration.zero);
      gateway.readGate!.complete('Old name');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(firebaseSessionProvider).user, isNull);
    });
  });

  testWidgets(
      'router isolates every experimental route from legacy auth/APIs and shell',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final gateway = FakeGateway();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(config()),
      firebaseAuthGatewayProvider.overrideWithValue(gateway),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth was accessed')),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API was accessed')),
    ]);
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    gateway.emit(null);
    await tester.pumpAndSettle();
    // Home is public: tiles for everyone, group tiles only once signed in.
    expect(find.byType(FirebaseHomeScreen), findsOneWidget);
    for (final key in ['home-read', 'home-listen', 'home-live', 'home-jaap']) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    expect(find.byKey(const Key('home-groups')), findsNothing);
    for (final path in ['/login', '/signup', '/phone-login', '/me']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.byType(FirebaseAuthScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    // Protected and unknown routes fall back to the public home.
    for (final path in ['/groups', '/tasks', '/profile', '/unknown']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.byType(FirebaseHomeScreen), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await gateway.changes.close();
  });

  testWidgets(
      'signup screen shows pending profile error and enables explicit repair',
      (tester) async {
    final gateway = FakeGateway()..profileError = StateError('offline');
    await tester.pumpWidget(ProviderScope(
        overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: FirebaseAuthScreen(signup: true))));
    gateway.emit(null);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'secret');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'), 'Sai');
    await tester
        .ensureVisible(find.widgetWithText(FilledButton, 'Create account'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-error')), findsOneWidget);
    expect(find.byKey(const Key('firebase-ready')), findsNothing);
    expect(find.text('One more step: tell us your name'), findsOneWidget);
    gateway.profileError = null;
    await tester.ensureVisible(find.text('Save my name'));
    await tester.tap(find.text('Save my name'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as Sai'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-ready')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await gateway.changes.close();
  });
}
