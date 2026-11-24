import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/data/auth_repository.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_account_gateway.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_password_gateway.dart';
import 'package:om_sai_ram/features/firebase_account/providers/firebase_password_provider.dart';
import 'package:om_sai_ram/features/firebase_account/presentation/firebase_change_password_screen.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_account_test.dart' as account;

class FakePassword implements FirebasePasswordGateway {
  @override
  FirebasePasswordIdentity identity = const FirebasePasswordIdentity('a', null);
  int calls = 0;
  Completer<void>? gate;
  Object? error;
  @override
  Future<void> change(String current, String next, String confirmation) async {
    calls++;
    // Do not retain secrets, even in test-double fields.
    expect(current == ' current ', isTrue);
    expect(next == ' new password ', isTrue);
    expect(confirmation == next, isTrue);
    await gate?.future;
    if (error != null) throw error!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> submit(FirebasePasswordController c) => c.submit(' current ', ' new password ', ' new password ');
  test('controller validates before IO, clears old errors on send, busy and ACK prevent duplicate calls', () async {
    final g = FakePassword()..gate = Completer();
    final c = FirebasePasswordController(g, () => true);
    await c.submit('', '123456', '123456'); expect(g.calls, 0);
    expect(c.state.error, 'Enter your current password.');
    await c.submit('x', 'short', 'short'); expect(g.calls, 0);
    await c.submit('x', '123456', 'mismatch'); expect(g.calls, 0);
    final request = submit(c); expect(c.state.busy, isTrue); expect(c.state.error, isNull);
    await submit(c); expect(g.calls, 1); g.gate!.complete(); await request;
    expect(c.state.complete, isTrue); await submit(c); expect(g.calls, 1); c.dispose();
  });
  test('unsupported identity blocks before validation/IO and eligibility recovery clears old error', () async {
    final g = FakePassword()..identity = const FirebasePasswordIdentity('a', 'Password provider required.');
    final c = FirebasePasswordController(g, () => true);
    await submit(c); expect(g.calls, 0); expect(c.state.error, 'Password provider required.');
    g.identity = const FirebasePasswordIdentity('a', null);
    await submit(c); expect(c.state.error, isNull); expect(c.state.complete, isTrue); c.dispose();
  });
  for (final uncertain in [false, true]) {
    test('controller ${uncertain ? 'uncertain blocks form' : 'known no-update allows explicit retry'} without auto retry', () async {
      final g = FakePassword()..error = FirebasePasswordFailure(
          uncertain ? passwordUpdateUncertain : 'Current password is incorrect.', uncertain: uncertain);
      final c = FirebasePasswordController(g, () => true);
      await submit(c); expect(c.state.uncertain, uncertain); expect(g.calls, 1);
      g.error = null; await submit(c); expect(g.calls, uncertain ? 1 : 2);
      expect(c.state.complete, !uncertain); c.dispose();
    });
  }
  test('unknown gateway failure is conservatively uncertain and never leaks exception text', () async {
    final g = FakePassword()..error = StateError('sensitive SDK detail');
    final c = FirebasePasswordController(g, () => true);
    await submit(c); expect(c.state.error, passwordUpdateUncertain);
    expect(c.state.uncertain, isTrue); await submit(c); expect(g.calls, 1); c.dispose();
  });
  for (final end in ['dispose', 'account']) {
    for (final failure in [false, true]) {
      test('controller pending $end ${failure ? 'failure' : 'ACK'} has no stale state', () async {
        var current = true;
        final g = FakePassword()..gate = Completer();
        if (failure) g.error = const FirebasePasswordFailure(passwordUpdateUncertain, uncertain: true);
        final c = FirebasePasswordController(g, () => current);
        final request = submit(c);
        if (end == 'dispose') { c.dispose(); } else { current = false; }
        g.gate!.complete(); await request;
        if (end == 'account') {
          expect(c.state.complete, isFalse); expect(c.state.error, isNull);
          expect(c.state.busy, isFalse); expect(c.state.uncertain, isFalse); c.dispose();
        }
      });
    }
  }

  Future<({ProviderContainer container, authentication.FakeGateway auth, FakePassword password, account.FakeAccount profile})> mount(
      WidgetTester tester, {FakePassword? password, bool loggedOut = false, bool ready = true,
      bool direct = false, String path = '/account/change-password'}) async {
    tester.view.physicalSize = const Size(1100, 1600); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = 'Private';
    if (!ready) auth.readGate = Completer();
    final g = password ?? FakePassword(); final profile = account.FakeAccount();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseAccountGatewayProvider.overrideWithValue(profile),
      firebasePasswordGatewayProvider.overrideWithValue(g),
      authStateProvider.overrideWith((ref) => throw StateError('No legacy session')),
      authRepositoryProvider.overrideWith((ref) => throw StateError('No legacy auth')),
      apiClientProvider.overrideWith((ref) => throw StateError('No legacy API')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(loggedOut ? null : const FirebaseIdentity('a', 'session-not-sdk@example.com'));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: direct ? const MaterialApp(home: FirebaseChangePasswordScreen())
        : MaterialApp.router(routerConfig: container.read(routerProvider))));
    if (!direct) container.read(routerProvider).go(path);
    if (!ready) { await tester.pump(); await tester.pump(); } else { await tester.pumpAndSettle(); }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink()); container.dispose();
      if (auth.readGate != null && !auth.readGate!.isCompleted) auth.readGate!.complete('Private');
      if (g.gate != null && !g.gate!.isCompleted) g.gate!.complete();
      await auth.changes.close();
    });
    return (container: container, auth: auth, password: g, profile: profile);
  }
  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), ' current ');
    await tester.enterText(find.byType(TextField).at(1), ' new password ');
    await tester.enterText(find.byType(TextField).at(2), ' new password ');
  }
  Finder button() => find.widgetWithText(FilledButton, 'Change password');
  void blankFields(WidgetTester tester) {
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      if (field.obscureText) expect(field.controller!.text.isEmpty, isTrue);
    }
  }

  testWidgets('private-account button opens ready-only form with secure fields and no profile/legacy I/O', (tester) async {
    final f = await mount(tester, path: '/account');
    final reads = f.profile.reads;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change password')); await tester.pumpAndSettle();
    expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/account/change-password');
    expect(find.byType(TextField), findsNWidgets(3));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.obscureText, isTrue); expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse); expect(field.autofillHints, isEmpty);
    }
    expect(f.profile.reads, reads); expect(f.profile.names, isEmpty);
    expect(f.auth.signins, 0); expect(f.auth.signups, 0); expect(f.auth.writes, 0);
    expect(find.textContaining('revocation of other sessions'), findsOneWidget);
  });
  for (final mode in ['logout', 'unready', 'direct-unready', 'direct-logout']) {
    testWidgets('$mode denies password form before gateway mutation', (tester) async {
      final f = await mount(tester, loggedOut: mode.contains('logout'),
          ready: !mode.contains('unready'), direct: mode.startsWith('direct'));
      expect(find.byType(TextField).evaluate().where((e) => (e.widget as TextField).obscureText).length,
          mode.startsWith('direct') ? 0 : lessThan(3));
      expect(f.password.calls, 0); expect(f.profile.reads, 0);
      if (!mode.startsWith('direct')) {
        expect(f.container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
      } else { expect(find.text('Ready Firebase session required.'), findsOneWidget); }
    });
  }
  testWidgets('provider unsupported disables all fields and action with clear reason', (tester) async {
    final g = FakePassword()..identity = const FirebasePasswordIdentity('a', 'Password provider required.');
    await mount(tester, password: g);
    expect(find.text('Password provider required.'), findsOneWidget);
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) { expect(field.enabled, isFalse); }
    expect(g.calls, 0);
  });
  testWidgets('invalid form clears all fields, sends no request; next valid submit resets error', (tester) async {
    final f = await mount(tester);
    await tester.enterText(find.byType(TextField).at(0), 'x');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.tap(button()); await tester.pumpAndSettle(); blankFields(tester);
    expect(f.password.calls, 0); expect(find.byKey(const Key('password-error')), findsOneWidget);
    await fill(tester); await tester.tap(button()); await tester.pumpAndSettle();
    blankFields(tester); expect(find.byKey(const Key('password-error')), findsNothing);
    expect(find.byKey(const Key('password-ack')), findsOneWidget);
  });
  testWidgets('valid submit clears immediately, busy blocks duplicate; ACK disables form without signout', (tester) async {
    final f = await mount(tester, password: FakePassword()..gate = Completer());
    final authReads = f.auth.reads;
    await fill(tester); await tester.tap(button()); await tester.pump(); blankFields(tester);
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    expect(f.password.calls, 1); f.password.gate!.complete(); await tester.pumpAndSettle();
    blankFields(tester); expect(find.byKey(const Key('password-ack')), findsOneWidget);
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    expect(f.container.read(firebaseSessionProvider).ready, isTrue);
    expect(f.auth.reads, authReads); expect(f.profile.reads, 0);
    expect(f.auth.signins, 0); expect(f.auth.signups, 0); expect(f.auth.writes, 0);
  });
  for (final uncertain in [false, true]) {
    testWidgets('${uncertain ? 'uncertain update' : 'reauth error'} clears fields and ${uncertain ? 'blocks repeat' : 'permits explicit retry'}', (tester) async {
      final f = await mount(tester, password: FakePassword()..error = FirebasePasswordFailure(
          uncertain ? passwordUpdateUncertain : 'Current password is incorrect.', uncertain: uncertain));
      await fill(tester); await tester.tap(button()); await tester.pumpAndSettle(); blankFields(tester);
      expect(find.byKey(const Key('password-ack')), findsNothing);
      expect(tester.widget<FilledButton>(button()).onPressed == null, uncertain);
      expect(f.password.calls, 1);
      if (uncertain) {
        await tester.tap(find.text('Log out to verify or reset')); await tester.pumpAndSettle();
        expect(f.container.read(firebaseSessionProvider).user, isNull);
        expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/login');
        expect(find.text('Forgot password?'), findsOneWidget);
        expect(f.auth.signins, 0);
      }
    });
  }
  for (final end in ['switch', 'logout', 'route']) {
    for (final failure in [false, true]) {
      testWidgets('pending $end ${failure ? 'error' : 'ACK'} clears old form and discards stale provider/UI result', (tester) async {
        final g = FakePassword()..gate = Completer();
        if (failure) g.error = StateError('sensitive SDK detail');
        final f = await mount(tester, password: g);
        await fill(tester); await tester.tap(button()); await tester.pump();
        if (end == 'route') { f.container.read(routerProvider).go('/account'); }
        else {
          g.identity = FirebasePasswordIdentity(end == 'logout' ? null : 'b', null);
          f.auth.emit(end == 'logout' ? null : const FirebaseIdentity('b', 'b@example.com'));
        }
        await tester.pumpAndSettle(); g.gate!.complete(); await tester.pumpAndSettle();
        expect(find.byKey(const Key('password-ack')), findsNothing);
        expect(find.byKey(const Key('password-error')), findsNothing);
        expect(find.textContaining('sensitive'), findsNothing); blankFields(tester);
        if (end == 'switch') {
          expect(find.byType(TextField), findsNWidgets(3));
          expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);
        }
        if (end == 'logout') {
          expect(f.container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
        }
      });
    }
  }
  testWidgets('unsubmitted secrets clear on account switch and fresh route entry', (tester) async {
    final f = await mount(tester); await fill(tester);
    f.password.identity = const FirebasePasswordIdentity('b', null);
    f.auth.emit(const FirebaseIdentity('b', 'b@example.com')); await tester.pumpAndSettle(); blankFields(tester);
    f.container.read(routerProvider).go('/account'); await tester.pumpAndSettle();
    f.container.read(routerProvider).go('/account/change-password'); await tester.pumpAndSettle(); blankFields(tester);
    expect(f.password.calls, 0);
  });
  testWidgets('navigation cannot bypass pending or uncertain operation; logout/login resets scope', (tester) async {
    final g = FakePassword()..gate = Completer()
      ..error = const FirebasePasswordFailure(passwordUpdateUncertain, uncertain: true);
    final f = await mount(tester, password: g);
    await fill(tester); await tester.tap(button()); await tester.pump();
    f.container.read(routerProvider).go('/account'); await tester.pumpAndSettle();
    f.container.read(routerProvider).go('/account/change-password'); await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<FilledButton>(button()).onPressed, isNull); blankFields(tester);
    g.gate!.complete(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('password-error')), findsOneWidget);
    f.container.read(routerProvider).go('/account'); await tester.pumpAndSettle();
    f.container.read(routerProvider).go('/account/change-password'); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    expect(g.calls, 1); blankFields(tester);
    f.auth.emit(null); await tester.pumpAndSettle();
    f.auth.emit(const FirebaseIdentity('a', 'same-account@example.com')); await tester.pumpAndSettle();
    f.container.read(routerProvider).go('/account/change-password'); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);
    expect(find.byKey(const Key('password-error')), findsNothing); blankFields(tester);
  });
  testWidgets('completed form stays disabled until explicit fresh navigation', (tester) async {
    final f = await mount(tester); await fill(tester); await tester.tap(button()); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    f.container.read(routerProvider).go('/account'); await tester.pumpAndSettle();
    f.container.read(routerProvider).go('/account/change-password'); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);
    expect(find.byKey(const Key('password-ack')), findsNothing); blankFields(tester);
  });
  test('injection is optional for old bundles, bootstrap supplies named Auth gateway and main overrides it', () {
    final bootstrap = File('lib/core/services/firebase_bootstrap.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    expect(bootstrap, contains('final FirebasePasswordGateway? password;'));
    expect(bootstrap, contains('password: SdkFirebasePasswordGateway(auth)'));
    expect(bootstrap, contains('FirebaseAuth.instanceFor(app: app)'));
    expect(main, contains('firebasePasswordGatewayProvider.overrideWithValue(firebase!.password!)'));
  });
  test('new password path has no Firestore/legacy/storage/logging/sign-in APIs; FastAPI route branch unchanged', () {
    final gateway = File('lib/features/firebase_account/data/firebase_password_gateway.dart').readAsStringSync();
    for (final forbidden in ['cloud_firestore', 'FirebaseAuth.instance', 'signInWith', 'signOut(', 'readProfile(', 'ensureProfile(', 'api_client', 'secure_storage', 'print(', 'debugPrint(']) {
      expect(gateway.contains(forbidden), isFalse, reason: forbidden);
    }
    final router = File('lib/core/services/router_service.dart').readAsStringSync();
    final legacy = router.substring(router.indexOf('// Only login/logout'));
    expect(legacy.contains('/account/change-password'), isFalse);
    expect(legacy, contains('const ChangePasswordScreen()'));
  });
}