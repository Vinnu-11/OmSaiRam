import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/data/auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_account_gateway.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_account_models.dart';
import 'package:om_sai_ram/features/firebase_account/providers/firebase_account_provider.dart';
import 'package:om_sai_ram/features/firebase_account/presentation/firebase_account_screen.dart';
import 'package:om_sai_ram/features/firebase_account/presentation/firebase_password_reset_screen.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_account_gateway_test.dart' as sdk;

class FakeAccount implements FirebaseAccountGateway {
  @override
  String? currentUid = 'a';
  FirebasePrivateProfile profile = FirebasePrivateProfile.parse('a', sdk.profileData());
  int reads = 0;
  final names = <String>[], emails = <String>[];
  Object? readError, writeError, resetError;
  Completer<void>? readGate, writeGate, resetGate;
  void Function()? afterWrite;
  @override
  Future<FirebasePrivateProfile> read() async {
    reads++; await readGate?.future;
    if (readError != null) throw readError!;
    return profile;
  }
  @override
  Future<void> updateName(String name) async {
    names.add(name); await writeGate?.future;
    if (writeError != null) throw writeError!;
    profile = FirebasePrivateProfile.parse(currentUid!, sdk.profileData(name));
    afterWrite?.call();
  }
  @override
  Future<void> requestPasswordReset(String email) async {
    emails.add(email); await resetGate?.future;
    if (resetError != null) throw resetError!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FirebaseAccountController controller(FakeAccount g, {bool Function()? current,
      Future<FirebasePrivateProfile> Function()? read}) =>
    FirebaseAccountController('a', () => g, current ?? () => true, read ?? g.read);

  test('save needs confirmed server read and explicit edit; trims and ACK prevents repeat', () async {
    final g = FakeAccount(); final c = controller(g);
    await c.save(); expect(g.names, isEmpty);
    await c.load(); expect(c.state.profile!.displayName, 'Private');
    c.edit('  Edited  '); await c.save();
    expect(g.names, ['Edited']); expect(c.state.acknowledged, isTrue);
    expect(c.state.profile!.displayName, 'Edited');
    await c.save(); expect(g.names.length, 1);
    c.edit('Again'); expect(c.state.acknowledged, isFalse);
    await c.save(); expect(g.names, ['Edited', 'Again']); c.dispose();
  });
  for (final name in ['', ' ', 'x' * 101]) {
    test('invalid controller draft length ${name.length} no writes preserves confirmed profile', () async {
      final g = FakeAccount(); final c = controller(g); await c.load();
      c.edit(name); await c.save(); expect(g.names, isEmpty);
      expect(c.state.error, contains('1–100')); expect(c.state.profile, isNotNull); c.dispose();
    });
  }
  test('read failure clears confirmed data before await; explicit retry only', () async {
    final g = FakeAccount(); final c = controller(g); await c.load();
    c.edit('Draft'); g.readGate = Completer(); g.readError = StateError('secret');
    final request = c.load(); expect(c.state.profile, isNull); expect(c.state.draft, isNull);
    g.readGate!.complete(); await request;
    expect(c.state.error, isNot(contains('secret'))); expect(c.state.canEdit, isFalse);
    c.edit('No'); await c.save(); expect(g.names, isEmpty); expect(g.reads, 2);
    g.readError = null; await c.load(); expect(c.state.canEdit, isTrue); c.dispose();
  });
  for (final ack in [false, true]) {
    test('${ack ? 'ACK then reload failure' : 'uncertain write'} retains draft disables writes until verification', () async {
      final g = FakeAccount(); final c = controller(g); await c.load(); c.edit('Draft');
      if (ack) { g.readError = StateError('offline'); }
      else { g.writeError = StateError('uncertain'); }
      await c.save(); expect(c.state.acknowledged, ack);
      expect(c.state.profile, isNull); expect(c.state.draft, 'Draft');
      expect(c.state.verifyBeforeSave, isTrue); expect(c.state.canEdit, isFalse);
      expect(c.state.error, contains(ack ? 'Save acknowledged' : 'Save not acknowledged'));
      await c.save(); expect(g.names.length, 1);
      g.readError = StateError('still offline'); await c.load();
      expect(c.state.acknowledged, ack); expect(c.state.draft, 'Draft');
      expect(g.names.length, 1); g.readError = null; await c.load();
      expect(c.state.profile, isNotNull); expect(c.state.canEdit, isTrue);
      expect(c.state.acknowledged, ack); c.dispose();
    });
  }
  test('server confirmed response, never submitted draft, drives final name', () async {
    final g = FakeAccount(); final c = controller(g); await c.load();
    c.edit('Submitted'); g.afterWrite = () => g.profile = FirebasePrivateProfile.parse('a', sdk.profileData('Server value'));
    await c.save(); expect(c.state.profile!.displayName, 'Server value');
    expect(c.state.draft, 'Server value'); c.dispose();
  });
  test('controller rejects mismatched profile UID', () async {
    final g = FakeAccount()..profile = FirebasePrivateProfile.parse('b', sdk.profileData());
    final c = controller(g); await c.load(); expect(c.state.profile, isNull);
    expect(c.state.canEdit, isFalse); c.dispose();
  });
  for (final operation in ['load', 'write', 'reload']) {
    for (final end in ['account', 'dispose']) {
      for (final failure in [false, true]) {
        test('$operation delayed $end ${failure ? 'failure' : 'success'} discards draft/ACK/profile', () async {
          var current = true; final g = FakeAccount(); final c = controller(g, current: () => current);
          await c.load(); c.edit('Old draft');
          final gate = Completer<void>();
          if (operation == 'write') {
            g.writeGate = gate; if (failure) g.writeError = StateError('old');
          } else {
            g.readGate = gate; if (failure) g.readError = StateError('old');
          }
          final request = operation == 'load' ? c.load() : c.save();
          await Future<void>.delayed(Duration.zero);
          expect(c.state.profile, isNull);
          if (operation != 'load') { await c.save(); expect(g.names.length, 1); }
          if (end == 'account') { current = false; } else { c.dispose(); }
          gate.complete(); await request;
          if (end == 'account') {
            expect(c.state.profile, isNull); expect(c.state.draft, isNull);
            expect(c.state.acknowledged, isFalse); expect(c.state.busy, isFalse); c.dispose();
          }
        });
      }
    }
  }
  test('reset validation busy double-submit generic request explicit once only', () async {
    final g = FakeAccount()..resetGate = Completer();
    final c = FirebasePasswordResetController(() => g, () => true);
    await c.request('invalid'); expect(g.emails, isEmpty); expect(c.state.error, contains('valid email'));
    final request = c.request('  a@b.com  '); expect(c.state.busy, isTrue);
    await c.request('other@b.com'); expect(g.emails, ['a@b.com']);
    g.resetGate!.complete(); await request; expect(c.state.requested, isTrue);
    await c.request('a@b.com'); expect(g.emails.length, 1); expect(g.reads, 0); expect(g.names, isEmpty); c.dispose();
  });
  for (final code in ['invalid-email', 'too-many-requests', 'network-request-failed', 'internal-error']) {
    test('reset controller maps $code safely without existence/raw detail or automatic retry', () async {
      final g = FakeAccount()..resetError = FirebaseAuthException(code: code, message: 'secret reset token');
      final c = FirebasePasswordResetController(() => g, () => true);
      await c.request('a@b.com'); expect(c.state.requested, isFalse);
      expect(c.state.error, isNot(contains('secret'))); expect(g.emails.length, 1);
      expect(g.reads, 0); c.dispose();
    });
  }
  for (final end in ['account', 'dispose']) {
    for (final failure in [false, true]) {
      test('reset pending $end ${failure ? 'failure' : 'success'} discarded', () async {
        var current = true; final g = FakeAccount()..resetGate = Completer();
        if (failure) g.resetError = StateError('old secret');
        final c = FirebasePasswordResetController(() => g, () => current);
        final request = c.request('a@b.com');
        if (end == 'dispose') { c.dispose(); } else { current = false; }
        g.resetGate!.complete(); await request;
        if (end == 'account') {
          expect(c.state.requested, isFalse); expect(c.state.error, isNull);
          expect(c.state.busy, isFalse); c.dispose();
        }
      });
    }
  }

  Future<({ProviderContainer container, authentication.FakeGateway auth, FakeAccount account})> mount(
      WidgetTester tester, {FakeAccount? gateway, bool loggedOut = false,
      bool ready = true, bool routed = true, String route = '/account'}) async {
    tester.view.physicalSize = const Size(1100, 1500); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = 'Private';
    if (!ready) auth.readGate = Completer();
    final account = gateway ?? FakeAccount(); account.currentUid = loggedOut ? null : 'a';
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseAccountGatewayProvider.overrideWithValue(account),
      authRepositoryProvider.overrideWith((ref) => throw StateError('No legacy auth')),
      apiClientProvider.overrideWith((ref) => throw StateError('No legacy API')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(loggedOut ? null : const FirebaseIdentity('a', 'private@example.com'));
    await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: routed ? MaterialApp.router(routerConfig: container.read(routerProvider))
        : MaterialApp(home: route == '/account' ? const FirebaseAccountScreen() : const FirebasePasswordResetScreen())));
    if (routed) container.read(routerProvider).go(route);
    if (account.readGate != null || !ready) { await tester.pump(); await tester.pump(); }
    else { await tester.pumpAndSettle(); }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink()); container.dispose();
      if (auth.readGate != null && !auth.readGate!.isCompleted) auth.readGate!.complete('Private');
      for (final gate in [account.readGate, account.writeGate, account.resetGate]) {
        if (gate != null && !gate.isCompleted) gate.complete();
      }
      await auth.changes.close();
    });
    return (container: container, auth: auth, account: account);
  }

  testWidgets('ready workspace links private profile; saved server value refreshes session without losing route/ACK', (tester) async {
    final f = await mount(tester, route: '/me');
    await tester.tap(find.text('Change my name')); await tester.pumpAndSettle();
    expect(find.textContaining('This name is private.'), findsOneWidget);
    expect(find.textContaining('published group names'), findsOneWidget);
    expect(find.text('Confirmed private name: Private'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  New private  ');
    await tester.tap(find.text('Save private name')); await tester.pumpAndSettle();
    expect(f.account.names, ['New private']); expect(find.byKey(const Key('account-ack')), findsOneWidget);
    expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/account');
    expect(f.container.read(firebaseSessionProvider).ready, isTrue);
    expect(f.container.read(firebaseSessionProvider).displayName, 'New private');
    expect(f.auth.writes, 0); // Never ensureProfile or Auth displayName changes.
    await tester.tap(find.byTooltip('Back to my account')); await tester.pumpAndSettle();
    expect(find.text('Signed in as New private'), findsOneWidget);
  });
  testWidgets('name session refresh uses confirmed server name, not input', (tester) async {
    final account = FakeAccount(); account.afterWrite = () => account.profile = FirebasePrivateProfile.parse('a', sdk.profileData('Confirmed only'));
    final f = await mount(tester, gateway: account);
    await tester.enterText(find.byType(TextField), 'Not confirmed');
    await tester.tap(find.text('Save private name')); await tester.pumpAndSettle();
    expect(f.container.read(firebaseSessionProvider).displayName, 'Confirmed only');
    expect(find.text('Confirmed private name: Confirmed only'), findsOneWidget);
  });
  for (final ready in [false, true]) {
    testWidgets('account route denies ${ready ? 'logged out' : 'unready'} without gateway IO', (tester) async {
      final f = await mount(tester, loggedOut: ready, ready: ready);
      expect(f.account.reads, 0); expect(f.account.names, isEmpty);
      expect(f.container.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/');
      expect(find.byType(FirebaseAccountScreen), findsNothing);
    });
  }
  testWidgets('direct account screen also denies unready session', (tester) async {
    final f = await mount(tester, ready: false, routed: false);
    expect(find.text('Ready Firebase session required.'), findsOneWidget); expect(f.account.reads, 0);
  });
  testWidgets('private read failure clears confirmed name and draft with explicit retry', (tester) async {
    final f = await mount(tester); f.account.readError = StateError('raw secret'); f.account.readGate = Completer();
    await tester.tap(find.text('Reload from server')); await tester.pump();
    expect(find.byKey(const Key('account-confirmed')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    f.account.readGate!.complete(); await tester.pumpAndSettle();
    expect(find.text('Retry server read'), findsOneWidget); expect(find.textContaining('raw secret'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save private name')).onPressed, isNull);
    expect(f.account.reads, 2); f.account.readError = null;
    await tester.tap(find.text('Retry server read')); await tester.pumpAndSettle();
    expect(find.text('Confirmed private name: Private'), findsOneWidget);
  });
  for (final ack in [false, true]) {
    testWidgets('${ack ? 'ACK/reload failure' : 'uncertain write'} UI retains unverified draft disables repeat and preserves ready session', (tester) async {
      final f = await mount(tester); await tester.enterText(find.byType(TextField), 'Retained draft');
      if (ack) { f.account.readError = StateError('offline'); } else { f.account.writeError = StateError('offline'); }
      await tester.tap(find.text('Save private name')); await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-ack')), ack ? findsOneWidget : findsNothing);
      expect(find.byKey(const Key('account-confirmed')), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Retained draft');
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(f.container.read(firebaseSessionProvider).displayName, 'Private');
      expect(f.container.read(firebaseSessionProvider).ready, isTrue);
      await tester.tap(find.text('Retry server read')); await tester.pumpAndSettle();
      expect(f.account.names.length, 1);
    });
  }
  testWidgets('private busy form blocks double submit', (tester) async {
    final f = await mount(tester, gateway: FakeAccount()..writeGate = Completer());
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.tap(find.text('Save private name')); await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save private name')).onPressed, isNull);
    expect(f.account.names, ['Draft']); f.account.writeGate!.complete(); await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-ack')), findsOneWidget);
  });
  for (final end in ['switch', 'logout', 'dispose']) {
    testWidgets('$end pending private save cannot leak draft or update new session', (tester) async {
      final f = await mount(tester, gateway: FakeAccount()..writeGate = Completer());
      await tester.enterText(find.byType(TextField), 'Old private draft');
      await tester.tap(find.text('Save private name')); await tester.pump();
      if (end == 'dispose') {
        f.container.read(routerProvider).go('/login');
      } else {
        f.auth.profile = 'New account';
        f.account.currentUid = end == 'logout' ? null : 'b';
        f.auth.emit(end == 'logout' ? null : const FirebaseIdentity('b', 'b@example.com'));
      }
      await tester.pumpAndSettle(); f.account.writeGate!.complete(); await tester.pumpAndSettle();
      expect(find.textContaining('Old private draft'), findsNothing);
      expect(f.container.read(firebaseSessionProvider).displayName, isNot('Old private draft'));
      expect(find.byKey(const Key('account-ack')), findsNothing);
    });
  }
  testWidgets('login forgot link is publicly routable with blank form and emulator disclosure', (tester) async {
    final f = await mount(tester, loggedOut: true, route: '/login');
    await tester.tap(find.text('Forgot password?')); await tester.pumpAndSettle();
    expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/forgot-password');
    expect(find.text(passwordResetEmulatorNotice), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(f.account.reads, 0); expect(f.account.emails, isEmpty);
  });
  testWidgets('public reset busy explicit once and generic success with no navigation/auth/Firestore', (tester) async {
    final f = await mount(tester, gateway: FakeAccount()..resetGate = Completer(), loggedOut: true, route: '/forgot-password');
    await tester.enterText(find.byType(TextField), '  a@example.com  ');
    await tester.tap(find.text('Request reset instructions')); await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(f.account.emails, ['a@example.com']);
    f.account.resetGate!.complete(); await tester.pumpAndSettle();
    expect(find.text(passwordResetRequested), findsOneWidget);
    expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/forgot-password');
    expect(f.auth.currentUser, isNull); expect(f.auth.signins, 0); expect(f.auth.signups, 0);
    expect(f.auth.reads, 0); expect(f.account.reads, 0); expect(f.account.names, isEmpty);
  });
  testWidgets('reset invalid input validation sends no request', (tester) async {
    final f = await mount(tester, loggedOut: true, route: '/forgot-password');
    await tester.enterText(find.byType(TextField), 'bad'); await tester.tap(find.text('Request reset instructions'));
    await tester.pumpAndSettle(); expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(f.account.emails, isEmpty);
  });
  for (final code in ['too-many-requests', 'network-request-failed', 'invalid-email', 'internal-error']) {
    testWidgets('reset $code shows safe error no SDK text/tokens and no auto retry', (tester) async {
      final f = await mount(tester, loggedOut: true, route: '/forgot-password', gateway: FakeAccount()
        ..resetError = FirebaseAuthException(code: code, message: 'secret emulator reset token'));
      await tester.enterText(find.byType(TextField), 'a@b.com'); await tester.tap(find.text('Request reset instructions'));
      await tester.pumpAndSettle(); expect(find.byKey(const Key('reset-error')), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing); expect(find.text(passwordResetRequested), findsNothing);
      expect(f.account.emails.length, 1); expect(f.account.reads, 0);
    });
  }
  for (final failure in [false, true]) {
    for (final end in ['signin', 'route']) {
      testWidgets('reset pending $end ${failure ? 'failure' : 'ACK'} discards result and form no unexpected navigation', (tester) async {
        final g = FakeAccount()..resetGate = Completer(); if (failure) g.resetError = StateError('old');
        final f = await mount(tester, gateway: g, loggedOut: true, route: '/forgot-password');
        await tester.enterText(find.byType(TextField), 'old@example.com'); await tester.tap(find.text('Request reset instructions'));
        await tester.pump();
        if (end == 'signin') {
          g.currentUid = 'b'; f.auth.emit(const FirebaseIdentity('b', 'new@example.com'));
        } else { f.container.read(routerProvider).go('/login'); }
        await tester.pumpAndSettle(); g.resetGate!.complete(); await tester.pumpAndSettle();
        expect(find.text(passwordResetRequested), findsNothing); expect(find.text('old@example.com'), findsNothing);
        expect(find.byKey(const Key('reset-error')), findsNothing);
        if (end == 'signin') {
          expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/forgot-password');
          g.currentUid = null; f.auth.emit(null); await tester.pumpAndSettle();
          expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
        } else {
          expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/login');
          f.container.read(routerProvider).go('/forgot-password'); await tester.pumpAndSettle();
          expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
        }
      });
    }
  }
  test('session method rejects old SDK UID before private read and mismatched server profile', () async {
    final auth = authentication.FakeGateway()..profile = 'Private';
    final session = FirebaseSessionController(auth); auth.emit(const FirebaseIdentity('a', null));
    await Future<void>.delayed(Duration.zero); final g = FakeAccount();
    g.currentUid = 'b'; await expectLater(session.readConfirmedAccountProfile('a', g), throwsStateError);
    expect(g.reads, 0); g.currentUid = 'a'; g.profile = FirebasePrivateProfile.parse('b', sdk.profileData());
    await expectLater(session.readConfirmedAccountProfile('a', g), throwsFormatException);
    expect(session.state.displayName, 'Private'); expect(session.state.ready, isTrue);
    session.dispose(); await auth.changes.close();
  });
  for (final end in ['switch', 'signout', 'dispose']) {
    test('session confirmed server read pending $end cannot refresh stale name', () async {
      final auth = authentication.FakeGateway()..profile = 'Private';
      final session = FirebaseSessionController(auth); auth.emit(const FirebaseIdentity('a', null));
      await Future<void>.delayed(Duration.zero); final g = FakeAccount()..readGate = Completer();
      final request = expectLater(session.readConfirmedAccountProfile('a', g), throwsStateError);
      if (end == 'dispose') { session.dispose(); }
      else { auth.emit(end == 'signout' ? null : const FirebaseIdentity('b', null)); }
      await Future<void>.delayed(Duration.zero); g.readGate!.complete(); await request;
      if (end != 'dispose') { expect(session.state.displayName, isNot('Server value')); session.dispose(); }
      await auth.changes.close();
    });
  }
}