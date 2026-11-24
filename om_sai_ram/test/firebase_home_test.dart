// Home, language choice, text size and Naam Jaap. Local preferences are mocked;
// nothing here touches Firebase, the legacy API or the network.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/app.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/providers/language_provider.dart';
import 'package:om_sai_ram/core/providers/text_scale_provider.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/core/theme/app_colors.dart';
import 'package:om_sai_ram/core/theme/app_theme.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/presentation/firebase_auth_screen.dart';
import 'package:om_sai_ram/features/firebase_home/data/home_text.dart';
import 'package:om_sai_ram/features/firebase_home/presentation/firebase_home_screen.dart';
import 'package:om_sai_ram/features/firebase_home/presentation/naam_jaap_screen.dart';
import 'package:om_sai_ram/features/firebase_home/providers/naam_jaap_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_auth_mode_test.dart' as authentication;

double _luminance(Color color) => color.computeLuminance();
double contrast(Color a, Color b) {
  final high = _luminance(a) > _luminance(b) ? _luminance(a) : _luminance(b);
  final low = _luminance(a) > _luminance(b) ? _luminance(b) : _luminance(a);
  return (high + 0.05) / (low + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(authentication.FakeGateway, ProviderContainer)> pumpApp(
      WidgetTester tester,
      {Map<String, Object> preferences = const {'app_language': 'en'},
      Size? size}) async {
    SharedPreferences.setMockInitialValues(preferences);
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }
    final gateway = authentication.FakeGateway();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(gateway),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth was accessed')),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API was accessed')),
    ]);
    // The real app widget, so the theme and the text-size builder are exercised.
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const OmSaiRamApp()));
    gateway.emit(null);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await gateway.changes.close();
    });
    return (gateway, container);
  }

  String path(ProviderContainer container) =>
      container.read(routerProvider).routeInformationProvider.value.uri.path;
  // Bounded pumps: the book catalogue keeps a progress bar while assets load.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> open(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  group('theme for older readers', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      test(
          '${theme.brightness.name}: text and buttons meet AA contrast, type and targets are large',
          () {
        final scheme = theme.colorScheme;
        expect(contrast(scheme.onSurface, theme.scaffoldBackgroundColor),
            greaterThanOrEqualTo(7));
        expect(contrast(scheme.onSurfaceVariant, theme.scaffoldBackgroundColor),
            greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.primary, scheme.surface),
            greaterThanOrEqualTo(4.5));
        for (final style in [
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.labelLarge,
          theme.textTheme.titleMedium
        ]) {
          expect(style!.fontSize, greaterThanOrEqualTo(17));
        }
        expect(theme.textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(16));
        final minimum =
            theme.filledButtonTheme.style!.minimumSize!.resolve({})!;
        expect(minimum.height, greaterThanOrEqualTo(56));
        expect(
            theme.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height,
            greaterThanOrEqualTo(56));
      });
    }
    test(
        'the old white-on-saffron button pairing is below AA and no longer used for buttons',
        () {
      expect(contrast(AppColors.white, AppColors.saffron), lessThan(4.5));
      expect(AppTheme.lightTheme.colorScheme.primary, AppColors.kumkum);
    });
  });

  testWidgets(
      'first open asks for a language in its own script, then shows home in that language',
      (tester) async {
    final (_, container) = await pumpApp(tester, preferences: const {});
    expect(find.byKey(const Key('language-chooser')), findsOneWidget);
    expect(find.byKey(const Key('home-read')), findsNothing);
    // Hindi, Marathi and Telugu come first.
    final labels = tester
        .widgetList<OutlinedButton>(find.byType(OutlinedButton))
        .take(4)
        .map((button) => (button.key! as ValueKey<String>).value)
        .toList();
    expect(
        labels, ['language-hi', 'language-mr', 'language-te', 'language-en']);
    expect(find.text('हिंदी'), findsOneWidget);
    await tester.tap(find.byKey(const Key('language-hi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-chooser')), findsNothing);
    expect(find.text(homeText('hi', 'readBook')), findsOneWidget);
    expect(find.text('नाम जप'), findsOneWidget);
    expect(container.read(languageProvider).appLanguage, AppLanguage.hindi);
    expect((await SharedPreferences.getInstance()).getString('app_language'),
        'hi');
  });

  testWidgets('language can be changed again from the home screen',
      (tester) async {
    final (_, container) = await pumpApp(tester);
    expect(find.text('Read Satcharita'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-te')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-chooser')), findsNothing);
    expect(find.text(homeText('te', 'readBook')), findsOneWidget);
    expect(container.read(languageProvider).appLanguage, AppLanguage.telugu);
  });

  testWidgets(
      'text-size button cycles three sizes, scales the whole app and is remembered',
      (tester) async {
    final (_, container) = await pumpApp(tester);
    double scaleOf(Finder finder) =>
        MediaQuery.textScalerOf(tester.element(finder)).scale(1);
    final button = find.byKey(const Key('home-text-size'));
    expect(
        find.descendant(of: button, matching: find.text('A')), findsOneWidget);
    expect(scaleOf(button), 1.0);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: button, matching: find.text('A+')), findsOneWidget);
    expect(scaleOf(button), closeTo(1.2, 0.001));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(scaleOf(button), closeTo(1.4, 0.001));
    expect((await SharedPreferences.getInstance()).getDouble('app_text_scale'),
        1.4);
    // Other screens inherit the same size.
    container.read(routerProvider).go('/jaap');
    await tester.pumpAndSettle();
    expect(scaleOf(find.byType(NaamJaapScreen)), closeTo(1.4, 0.001));
    container.read(routerProvider).go('/');
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(container.read(textScaleProvider), 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'every home tile opens its screen; group reading leads to sign-in when signed out',
      (tester) async {
    final (_, container) = await pumpApp(tester);
    for (final (key, route) in [
      ('home-read', '/reader'),
      ('home-groups-sign-in', '/login'),
      ('home-live', '/live'),
      ('home-listen', '/audio'),
      ('home-programme', '/daily-programme'),
      ('home-events', '/events'),
      ('home-jaap', '/jaap'),
      ('home-help', '/faq'),
      ('home-sign-in', '/login')
    ]) {
      await open(tester, find.byKey(Key(key)));
      expect(path(container), route, reason: key);
      container.read(routerProvider).go('/');
      await settle(tester);
    }
    expect(find.byKey(const Key('home-groups')), findsNothing);
    expect(find.byKey(const Key('home-tasks')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home tiles keep the requested two-column order', (tester) async {
    await pumpApp(tester);
    double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
    expect(top('home-read'), closeTo(top('home-groups-sign-in'), 0.1));
    expect(top('home-live'), closeTo(top('home-listen'), 0.1));
    expect(top('home-programme'), closeTo(top('home-events'), 0.1));
    expect(top('home-read'), lessThan(top('home-live')));
    expect(top('home-live'), lessThan(top('home-programme')));
    expect(top('home-programme'), lessThan(top('home-jaap')));
  });

  testWidgets('signed-in home greets by name and offers groups and My account',
      (tester) async {
    final (gateway, container) = await pumpApp(tester);
    gateway.profile = 'Lakshmi';
    gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-groups-sign-in')), findsNothing);
    expect(find.byKey(const Key('home-groups')), findsOneWidget);
    final greeting = find.byKey(const Key('home-greeting'));
    await tester.scrollUntilVisible(greeting, 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<Text>(greeting).data, 'Namaste, Lakshmi');
    expect(find.byKey(const Key('home-sign-in')), findsNothing);
    await open(tester, find.byKey(const Key('home-account')));
    expect(path(container), '/me');
    expect(find.byType(FirebaseAuthScreen), findsOneWidget);
    expect(find.text('Signed in as Lakshmi'), findsOneWidget);
    // The sign-in pages have nothing to offer a signed-in reader.
    for (final route in ['/login', '/signup', '/phone-login']) {
      container.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(find.byType(FirebaseHomeScreen), findsOneWidget, reason: route);
      expect(find.byType(FirebaseAuthScreen), findsNothing, reason: route);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'teaching card shows another teaching on tap and continue-reading resumes the saved chapter',
      (tester) async {
    final (_, container) = await pumpApp(tester,
        preferences: const {'app_language': 'en', 'resume_chapter': 12});
    String teaching() => tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('home-teaching')),
            matching: find.byType(Text)))
        .elementAt(1)
        .data!;
    final first = teaching();
    await tester.tap(find.byKey(const Key('home-teaching')));
    await tester.pumpAndSettle();
    expect(teaching(), isNot(first));
    expect(find.text('Continue Reading: Chapter 12'), findsOneWidget);
    await open(tester, find.byKey(const Key('home-continue')));
    expect(path(container), '/reader/12');
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(412, 900),
    const Size(1024, 768)
  ]) {
    testWidgets(
        'home, language chooser and Naam Jaap fit ${size.width.toInt()}px at the largest text size',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (_, container) = await pumpApp(tester,
          preferences: const {'app_language': 'hi', 'app_text_scale': 1.4},
          size: size);
      // Phone 1.5 x app 1.4 is capped at 2.0.
      expect(
          MediaQuery.textScalerOf(
                  tester.element(find.byType(FirebaseHomeScreen)))
              .scale(1),
          2.0);
      await tester.scrollUntilVisible(
          find.byKey(const Key('home-sign-in')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(
          find.byKey(const Key('home-language')), -300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-language')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('language-chooser')), findsOneWidget);
      container.read(routerProvider).go('/jaap');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('jaap-chant')), findsOneWidget);
      container.read(routerProvider).go('/login');
      await tester.pumpAndSettle();
      expect(find.byType(FirebaseAuthScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('Naam Jaap', () {
    test(
        '108 chants complete one mala; progress is saved for today and restarts tomorrow',
        () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 11, 22, 6);
      final jaap = NaamJaapNotifier(now: () => now);
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 107; i++) {
        expect(jaap.chant(), isFalse);
      }
      expect(jaap.state.count, 107);
      expect(jaap.state.malas, 0);
      expect(jaap.chant(), isTrue);
      expect(jaap.state.count, 0);
      expect(jaap.state.malas, 1);
      jaap.chant();
      jaap.chant();
      await pumpEventQueue();
      final sameDay = NaamJaapNotifier(now: () => now);
      await pumpEventQueue();
      expect(sameDay.state.count, 2);
      expect(sameDay.state.malas, 1);
      now = DateTime(2026, 11, 23, 6);
      final nextDay = NaamJaapNotifier(now: () => now);
      await pumpEventQueue();
      expect(nextDay.state.count, 0);
      expect(nextDay.state.malas, 0);
      jaap.reset();
      expect(jaap.state.count, 0);
      expect(jaap.state.malas, 0);
      for (final notifier in [jaap, sameDay, nextDay]) {
        notifier.dispose();
      }
    });
    test('damaged saved values are ignored', () async {
      final now = DateTime(2026, 11, 22);
      for (final bad in [
        {'jaap_count': 108},
        {'jaap_count': -1},
        {'jaap_malas': -3}
      ]) {
        SharedPreferences.setMockInitialValues({
          'jaap_date': '2026-11-22',
          'jaap_count': 5,
          'jaap_malas': 1,
          ...bad
        });
        final jaap = NaamJaapNotifier(now: () => now);
        await pumpEventQueue();
        expect(jaap.state.count, 0);
        expect(jaap.state.malas, 0);
        jaap.dispose();
      }
    });
    testWidgets(
        'one large button counts each chant; starting again needs confirmation',
        (tester) async {
      final (_, container) = await pumpApp(tester);
      await open(tester, find.byKey(const Key('home-jaap')));
      final button = find.byKey(const Key('jaap-chant'));
      expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(150));
      for (var i = 0; i < 3; i++) {
        await tester.tap(button);
        await tester.pump();
      }
      expect(
          tester.widget<Text>(find.byKey(const Key('jaap-count'))).data, '3');
      expect(find.text('3 / 108'), findsOneWidget);
      final restart = find.text('Start again');
      Future<void> tapRestart() async {
        await tester.ensureVisible(restart);
        await tester.pumpAndSettle();
        await tester.tap(restart);
        await tester.pumpAndSettle();
      }

      await tapRestart();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(container.read(naamJaapProvider).count, 3);
      await tapRestart();
      await tester.tap(find.byKey(const Key('jaap-reset-confirm')));
      await tester.pumpAndSettle();
      expect(container.read(naamJaapProvider).count, 0);
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(path(container), '/');
      expect(tester.takeException(), isNull);
    });
  });
}
