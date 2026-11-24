// SDK-shaped doubles only: no real Google/Apple consent, SMS delivery or
// Auth-emulator transport. Emulator credentials are covered by
// firebase/tests/auth-providers.test.mjs.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_account/presentation/firebase_sign_in_methods_screen.dart';
import 'package:om_sai_ram/features/firebase_account/providers/firebase_link_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_provider_gateway.dart';
import 'package:om_sai_ram/features/firebase_auth/presentation/firebase_auth_screen.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_auth_mode_test.dart' as authentication;

class Info extends Fake implements UserInfo {
  @override
  final String providerId;
  Info(this.providerId);
}
class Credential extends Fake implements UserCredential {}
class PhoneCredential extends Fake implements PhoneAuthCredential {
  @override
  String get providerId => 'phone';
}

class ProviderUser extends Fake implements User {
  final ProviderAuth auth;
  @override
  final String uid;
  final List<String> providers;
  ProviderUser(this.auth, this.uid, [List<String>? providers])
      : providers = providers ?? ['password'];
  @override
  List<UserInfo> get providerData => [for (final id in providers) Info(id)];
  Future<UserCredential> _link(String call, String providerId) async {
    auth.calls.add(call);
    if (auth.error != null) throw auth.error!;
    providers.add(providerId);
    return Credential();
  }
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) {
    auth.credential = credential;
    return _link('link-credential:${credential.providerId}', credential.providerId);
  }
  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) =>
      _link('link-provider:${provider.providerId}', provider.providerId);
  @override
  Future<UserCredential> linkWithPopup(AuthProvider provider) =>
      _link('link-popup:${provider.providerId}', provider.providerId);
}

class ProviderAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser;
  final calls = <String>[];
  Object? error;
  AuthCredential? credential;
  String? requestedPhone;
  /// 'code', 'auto', 'failed' or 'throw'.
  String phone = 'code';
  Future<UserCredential> _signIn(String call) async {
    calls.add(call);
    if (error != null) throw error!;
    return Credential();
  }
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) {
    this.credential = credential;
    return _signIn('signin-credential:${credential.providerId}');
  }
  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) =>
      _signIn('signin-popup:${provider.providerId}');
  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) =>
      _signIn('signin-provider:${provider.providerId}');
  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    calls.add('verify-phone');
    requestedPhone = phoneNumber;
    switch (phone) {
      case 'auto': verificationCompleted(PhoneCredential());
      case 'failed': verificationFailed(FirebaseAuthException(code: 'invalid-phone-number'));
      case 'throw': throw FirebaseAuthException(code: 'quota-exceeded');
      default: codeSent('verification-1', null); codeAutoRetrievalTimeout('verification-1');
    }
  }
}

/// App-level double: a successful sign-in publishes an identity like the SDK.
class FakeProviders implements FirebaseProviderGateway {
  final authentication.FakeGateway auth;
  FakeProviders(this.auth);
  final calls = <String>[];
  Object? error;
  FirebasePhoneChallenge challenge = const FirebasePhoneChallenge(verificationId: 'v');
  String signedInUid = 'provider-uid';
  @override
  Set<String> linkedProviders = {'password'};
  void _done(String providerId, String? linkToUid) {
    if (error != null) throw error!;
    if (linkToUid == null) {
      auth.emit(FirebaseIdentity(signedInUid, null, phoneNumber: providerId == 'phone' ? '+919876543210' : null));
    } else {
      linkedProviders = {...linkedProviders, providerId};
    }
  }
  @override
  Future<void> oauth(FirebaseOAuthProvider provider, {String? linkToUid}) async {
    calls.add('${provider.name}:$linkToUid');
    _done(provider == FirebaseOAuthProvider.google ? 'google.com' : 'apple.com', linkToUid);
  }
  @override
  Future<FirebasePhoneChallenge> requestPhoneCode(String phoneNumber) async {
    calls.add('request:${validPhoneNumber(phoneNumber)}');
    if (error != null) throw error!;
    return challenge;
  }
  @override
  Future<void> confirmPhoneCode(FirebasePhoneChallenge challenge, String code, {String? linkToUid}) async {
    calls.add('confirm:$code:$linkToUid');
    _done('phone', linkToUid);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SDK provider gateway', () {
    late ProviderAuth auth;
    final google = GoogleAuthProvider.credential(idToken: 'id', accessToken: 'access');
    SdkFirebaseProviderGateway gateway({bool web = false, Future<OAuthCredential?> Function()? source}) =>
        SdkFirebaseProviderGateway(auth, web: web, nativeGoogle: source ?? () async => google);
    setUp(() => auth = ProviderAuth());

    test('native Google signs in with the picked credential only', () async {
      await gateway().oauth(FirebaseOAuthProvider.google);
      expect(auth.calls, ['signin-credential:google.com']);
      expect(identical(auth.credential, google), isTrue);
    });
    test('native Google cancellation and plugin failure never reach Firebase', () async {
      await expectLater(gateway(source: () async => null).oauth(FirebaseOAuthProvider.google),
          throwsA(isA<FirebaseProviderFailure>().having((e) => e.message, 'message', contains('cancelled'))));
      await expectLater(gateway(source: () async => throw PlatformException(code: 'sign_in_failed', message: 'secret 10'))
          .oauth(FirebaseOAuthProvider.google),
          throwsA(isA<FirebaseProviderFailure>().having((e) => e.message, 'message', isNot(contains('secret')))));
      expect(auth.calls, isEmpty);
    });
    test('web uses popups and native Apple uses the provider flow', () async {
      await gateway(web: true).oauth(FirebaseOAuthProvider.google);
      await gateway(web: true).oauth(FirebaseOAuthProvider.apple);
      await gateway().oauth(FirebaseOAuthProvider.apple);
      expect(auth.calls, ['signin-popup:google.com', 'signin-popup:apple.com', 'signin-provider:apple.com']);
    });
    test('linking targets the current account and never signs in', () async {
      final user = ProviderUser(auth, 'a'); auth.currentUser = user;
      await gateway().oauth(FirebaseOAuthProvider.google, linkToUid: 'a');
      await gateway().oauth(FirebaseOAuthProvider.apple, linkToUid: 'a');
      user.providers.remove('apple.com');
      await gateway(web: true).oauth(FirebaseOAuthProvider.apple, linkToUid: 'a');
      expect(auth.calls, ['link-credential:google.com', 'link-provider:apple.com', 'link-popup:apple.com']);
      expect(gateway().linkedProviders, {'password', 'google.com', 'apple.com'});
    });
    test('wrong, missing or already signed-in accounts are refused before any provider UI', () async {
      var picked = 0;
      Future<OAuthCredential?> source() async { picked++; return google; }
      await expectLater(gateway(source: source).oauth(FirebaseOAuthProvider.google, linkToUid: 'a'), throwsStateError);
      auth.currentUser = ProviderUser(auth, 'b');
      await expectLater(gateway(source: source).oauth(FirebaseOAuthProvider.google, linkToUid: 'a'), throwsStateError);
      await expectLater(gateway(source: source).oauth(FirebaseOAuthProvider.google), throwsStateError);
      await expectLater(gateway().requestPhoneCode('+919876543210').then((challenge) =>
          gateway().confirmPhoneCode(challenge, '123456', linkToUid: 'a')), throwsStateError);
      expect(picked, 0); expect(auth.calls, ['verify-phone']);
    });
    test('an account switch during the Google picker cancels linking and sign-in', () async {
      auth.currentUser = ProviderUser(auth, 'a');
      await expectLater(gateway(source: () async { auth.currentUser = ProviderUser(auth, 'b'); return google; })
          .oauth(FirebaseOAuthProvider.google, linkToUid: 'a'), throwsStateError);
      auth.currentUser = null;
      await expectLater(gateway(source: () async { auth.currentUser = ProviderUser(auth, 'b'); return google; })
          .oauth(FirebaseOAuthProvider.google), throwsStateError);
      expect(auth.calls, isEmpty);
    });
    test('SDK errors such as an already-used credential propagate unchanged', () async {
      auth.currentUser = ProviderUser(auth, 'a');
      auth.error = FirebaseAuthException(code: 'credential-already-in-use');
      await expectLater(gateway().oauth(FirebaseOAuthProvider.google, linkToUid: 'a'),
          throwsA(isA<FirebaseAuthException>().having((e) => e.code, 'code', 'credential-already-in-use')));
      expect(gateway().linkedProviders, {'password'});
    });
    for (final bad in ['', '9876543210', '+0123456789', '+12', '+1234567890123456', '+91abc', 'tel:+919876543210']) {
      test('invalid phone "$bad" is rejected before any SMS request', () {
        expect(() => gateway().requestPhoneCode(bad), throwsFormatException);
        expect(auth.calls, isEmpty);
      });
    }
    test('code challenge normalizes the number and confirms with the typed code', () async {
      final challenge = await gateway().requestPhoneCode(' +91 98765-43210 ');
      expect(auth.requestedPhone, '+919876543210');
      expect(challenge.needsCode, isTrue); expect(challenge.verificationId, 'verification-1');
      for (final bad in ['', '12345', '1234567', 'abcdef']) {
        expect(() => gateway().confirmPhoneCode(challenge, bad), throwsFormatException);
      }
      await gateway().confirmPhoneCode(challenge, ' 123456 ');
      expect(auth.calls, ['verify-phone', 'signin-credential:phone']);
      expect((auth.credential! as PhoneAuthCredential).smsCode, '123456');
      expect((auth.credential! as PhoneAuthCredential).verificationId, 'verification-1');
    });
    test('instant Android verification needs no code; phone linking stays on the same account', () async {
      auth.phone = 'auto';
      final user = ProviderUser(auth, 'a'); auth.currentUser = user;
      final challenge = await gateway().requestPhoneCode('+919876543210');
      expect(challenge.needsCode, isFalse);
      await gateway().confirmPhoneCode(challenge, '', linkToUid: 'a');
      expect(auth.calls, ['verify-phone', 'link-credential:phone']);
      expect(user.providers, ['password', 'phone']);
    });
    for (final failure in ['failed', 'throw']) {
      test('phone verification $failure surfaces the SDK error once', () async {
        auth.phone = failure;
        await expectLater(gateway().requestPhoneCode('+919876543210'), throwsA(isA<FirebaseAuthException>()));
      });
    }
  });

  test('safe messages for provider errors never suggest merging or leak SDK text', () {
    String message(String code) => friendlyFirebaseError(FirebaseAuthException(code: code, message: 'secret'));
    expect(message('account-exists-with-different-credential'), contains('never merged'));
    expect(message('credential-already-in-use'), contains('Nothing was linked'));
    expect(message('invalid-verification-code'), contains('incorrect'));
    expect(message('session-expired'), contains('expired'));
    expect(message('popup-closed-by-user'), contains('cancelled'));
    expect(message('operation-not-allowed'), contains('not enabled'));
    for (final code in ['account-exists-with-different-credential', 'credential-already-in-use', 'quota-exceeded']) {
      expect(message(code), isNot(contains('secret')));
    }
    expect(friendlyFirebaseError(const FirebaseProviderFailure('Sign-in was cancelled.')), 'Sign-in was cancelled.');
  });

  group('session', () {
    late authentication.FakeGateway gateway;
    late FakeProviders providers;
    late ProviderContainer container;
    late FirebaseSessionController controller;
    FirebaseSession session() => container.read(firebaseSessionProvider);
    setUp(() async {
      gateway = authentication.FakeGateway(); providers = FakeProviders(gateway);
      container = ProviderContainer(overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)]);
      container.listen(firebaseSessionProvider, (_, __) {});
      controller = container.read(firebaseSessionProvider.notifier);
      gateway.emit(null);
      await Future<void>.delayed(Duration.zero);
    });
    tearDown(() async { container.dispose(); await gateway.changes.close(); });

    test('a new provider account waits for an explicit display name; no profile is guessed', () async {
      await controller.signInWithProvider(() => providers.oauth(FirebaseOAuthProvider.google));
      expect(session().user?.uid, 'provider-uid'); expect(session().ready, isFalse);
      expect(session().error, isNull); expect(gateway.writes, 0);
      await controller.retryProfile('Sai');
      expect(session().ready, isTrue); expect(session().displayName, 'Sai');
    });
    test('an existing provider account opens its own profile', () async {
      gateway.profile = 'Existing';
      await controller.signInWithProvider(() => providers.confirmPhoneCode(providers.challenge, '123456'));
      expect(session().ready, isTrue); expect(session().user?.phoneNumber, '+919876543210');
      expect(gateway.writes, 0);
    });
    test('a conflicting email stays signed out with link-explicitly guidance', () async {
      providers.error = FirebaseAuthException(code: 'account-exists-with-different-credential');
      await controller.signInWithProvider(() => providers.oauth(FirebaseOAuthProvider.apple));
      expect(session().user, isNull); expect(session().error, contains('never merged'));
      expect(gateway.reads, 0); expect(gateway.writes, 0);
      providers.error = const FirebaseProviderFailure('Sign-in was cancelled.');
      await controller.signInWithProvider(() => providers.oauth(FirebaseOAuthProvider.google));
      expect(session().user, isNull); expect(session().error, 'Sign-in was cancelled.');
      providers.error = null;
      await controller.signInWithProvider(() => providers.oauth(FirebaseOAuthProvider.google));
      expect(session().user?.uid, 'provider-uid');
    });
  });

  group('link controller', () {
    late authentication.FakeGateway gateway;
    late FakeProviders providers;
    var current = true;
    FirebaseLinkController controller() => FirebaseLinkController('a', () => providers, () => current);
    setUp(() { gateway = authentication.FakeGateway(); providers = FakeProviders(gateway); current = true; });
    tearDown(() => gateway.changes.close());

    test('linking keeps the UID and refreshes providers from the SDK', () async {
      final c = controller()..refresh();
      expect(c.state.providers, {'password'});
      await c.linkOAuth(FirebaseOAuthProvider.google);
      expect(providers.calls, ['google:a']);
      expect(c.state.providers, {'password', 'google.com'});
      expect(c.state.message, contains('unchanged')); expect(gateway.currentUser, isNull);
      c.dispose();
    });
    test('a credential owned by another account is refused without merging', () async {
      final c = controller()..refresh();
      providers.error = FirebaseAuthException(code: 'credential-already-in-use', message: 'secret');
      await c.linkOAuth(FirebaseOAuthProvider.apple);
      expect(c.state.providers, {'password'}); expect(c.state.message, isNull);
      expect(c.state.error, contains('Nothing was linked')); expect(c.state.error, isNot(contains('secret')));
      providers.error = StateError('secret transport');
      await c.linkOAuth(FirebaseOAuthProvider.apple);
      expect(c.state.error, contains('could not be confirmed')); expect(c.state.error, isNot(contains('secret')));
      c.dispose();
    });
    test('phone linking requests, validates and confirms; a wrong code keeps the challenge', () async {
      final c = controller()..refresh();
      await c.confirmPhoneCode('123456'); expect(providers.calls, isEmpty);
      await c.requestPhoneCode('12345'); expect(c.state.error, contains('country code'));
      await c.requestPhoneCode('+919876543210'); expect(c.state.challenge, isNotNull);
      providers.error = FirebaseAuthException(code: 'invalid-verification-code');
      await c.confirmPhoneCode('000000');
      expect(c.state.challenge, isNotNull); expect(c.state.error, contains('incorrect'));
      providers.error = null;
      await c.confirmPhoneCode('123456');
      expect(c.state.challenge, isNull); expect(c.state.providers, contains('phone'));
      expect(providers.calls.last, 'confirm:123456:a');
      c.dispose();
    });
    test('a session change discards results and blocks further requests', () async {
      final c = controller()..refresh();
      await c.requestPhoneCode('+919876543210');
      current = false;
      await c.confirmPhoneCode('123456'); await c.linkOAuth(FirebaseOAuthProvider.google);
      c.cancelPhone(); c.refresh();
      expect(providers.calls, ['request:+919876543210']);
      expect(c.state.providers, isEmpty); expect(c.state.challenge, isNull);
      c.dispose();
    });
  });

  Future<(authentication.FakeGateway, FakeProviders, ProviderContainer)> pumpRouter(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final gateway = authentication.FakeGateway(); final providers = FakeProviders(gateway);
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(gateway),
      firebaseProviderGatewayProvider.overrideWithValue(providers),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth was accessed')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API was accessed')),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp.router(routerConfig: container.read(routerProvider))));
    gateway.emit(null);
    await tester.pumpAndSettle();
    return (gateway, providers, container);
  }
  Future<void> tap(WidgetTester tester, Finder finder) async {
    // The home screen is a lazy list: scroll first so the target is built.
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder); await tester.pump();
    await tester.tap(finder); await tester.pumpAndSettle();
  }
  Future<void> close(WidgetTester tester, authentication.FakeGateway gateway, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await gateway.changes.close();
  }

  testWidgets('Google and Apple buttons sign in and continue to explicit naming', (tester) async {
    final (gateway, providers, container) = await pumpRouter(tester);
    await tap(tester, find.byKey(const Key('home-sign-in')));
    await tap(tester, find.byKey(const Key('signin-apple')));
    expect(providers.calls, ['apple:null']);
    expect(find.text('One more step: tell us your name'), findsOneWidget);
    expect(find.byKey(const Key('signin-google')), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Sai');
    await tap(tester, find.text('Save my name'));
    // A finished sign-in returns to the home screen.
    final greeting = find.byKey(const Key('home-greeting'));
    await tester.scrollUntilVisible(greeting, 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Text>(greeting).data, 'Namaste, Sai');
    await tap(tester, find.byKey(const Key('home-account')));
    expect(find.text('Signed in as Sai'), findsOneWidget);
    await tap(tester, find.text('Log out'));
    await tap(tester, find.byKey(const Key('signin-google')));
    expect(providers.calls, ['apple:null', 'google:null']);
    expect(find.text('Signed in as Sai'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester, gateway, container);
  });

  testWidgets('phone sign-in sends a code, survives a wrong code and finishes naming', (tester) async {
    final (gateway, providers, container) = await pumpRouter(tester);
    await tap(tester, find.byKey(const Key('home-sign-in')));
    await tap(tester, find.byKey(const Key('signin-phone')));
    expect(find.byType(FirebaseAuthScreen), findsOneWidget);
    expect(find.text('Sign in with phone'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone-number')), '98765');
    await tap(tester, find.byKey(const Key('phone-send')));
    expect(find.byKey(const Key('phone-error')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone-number')), '+91 98765 43210');
    await tap(tester, find.byKey(const Key('phone-send')));
    expect(providers.calls, ['request:+919876543210']);
    await tester.enterText(find.byKey(const Key('phone-code')), '12');
    await tap(tester, find.byKey(const Key('phone-confirm')));
    expect(find.text('Enter the six-digit code.'), findsOneWidget);
    providers.error = FirebaseAuthException(code: 'invalid-verification-code');
    await tester.enterText(find.byKey(const Key('phone-code')), '000000');
    await tap(tester, find.byKey(const Key('phone-confirm')));
    expect(find.byKey(const Key('firebase-error')), findsOneWidget);
    expect(find.byKey(const Key('phone-code')), findsOneWidget);
    providers.error = null;
    await tester.enterText(find.byKey(const Key('phone-code')), '123456');
    await tap(tester, find.byKey(const Key('phone-confirm')));
    expect(providers.calls.last, 'confirm:123456:null');
    expect(find.text('+919876543210'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Your name'), 'Phone user');
    await tap(tester, find.text('Save my name'));
    final greeting = find.byKey(const Key('home-greeting'));
    await tester.scrollUntilVisible(greeting, 200, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Text>(greeting).data, 'Namaste, Phone user');
    expect(tester.takeException(), isNull);
    await close(tester, gateway, container);
  });

  testWidgets('sign-in methods lists linked providers, links more and is guarded', (tester) async {
    final (gateway, providers, container) = await pumpRouter(tester);
    final router = container.read(routerProvider);
    router.go('/account/sign-in-methods');
    await tester.pumpAndSettle();
    expect(find.byType(FirebaseSignInMethodsScreen), findsNothing);
    gateway.profile = 'Sai';
    gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
    await tester.pumpAndSettle();
    router.go('/account/sign-in-methods');
    await tester.pumpAndSettle();
    expect(find.text('Email and password'), findsOneWidget);
    await tap(tester, find.byKey(const Key('link-google')));
    expect(providers.calls, ['google:a']);
    expect(find.text('Google'), findsOneWidget);
    expect(find.byKey(const Key('link-google')), findsNothing);
    expect(find.byKey(const Key('link-message')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('link-phone-number')), '+919876543210');
    await tap(tester, find.byKey(const Key('link-phone-send')));
    await tester.enterText(find.byKey(const Key('link-phone-code')), '123456');
    await tap(tester, find.byKey(const Key('link-phone-confirm')));
    expect(providers.calls.last, 'confirm:123456:a');
    expect(find.byKey(const Key('link-phone-number')), findsNothing);
    expect(gateway.currentUser?.uid, 'a');
    expect(tester.takeException(), isNull);
    await close(tester, gateway, container);
  });
}
