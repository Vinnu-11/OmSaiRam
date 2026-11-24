import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/features/firebase_feeds/data/firebase_feed_models.dart';
import 'package:om_sai_ram/features/firebase_feeds/data/firebase_feeds_gateway.dart';
import 'package:om_sai_ram/features/events/presentation/events_screen.dart';
import 'package:om_sai_ram/features/events/data/events_repository.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/audio/presentation/live_darshan_screen.dart';

final now = DateTime.utc(2026, 10, 15, 12);
Map<String, dynamic> metadata({bool live = false, bool stale = false}) => {
      'sourceUrl': live ? liveFeedSource : festivalFeedSource,
      'fetchedAt': now.toIso8601String(),
      'freshUntil': now
          .add(live ? const Duration(seconds: 30) : const Duration(hours: 6))
          .toIso8601String(),
      'stale': stale,
    };
Map<String, dynamic> event() => {
      'id': 'a' * 64,
      'title': 'Festival',
      'dateLabel': '19.10.2026',
      'eventDate': '2026-10-19',
      'description': null
    };
Map<String, dynamic> calendar() => {
      ...metadata(),
      'events': [event()],
      'truncated': false
    };
Map<String, dynamic> live() => {
      ...metadata(live: true),
      'url': 'https://stream.example.org/live.m3u8?token=fixture'
    };

class FeedAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String body = jsonEncode(calendar());
  int status = 200;
  Completer<ResponseBody>? gate;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (gate != null) return gate!.future;
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
      'Firebase feed request has an absolute deadline, even when the adapter never completes',
      (tester) async {
    final adapter = FeedAdapter()..gate = Completer<ResponseBody>();
    final http = Dio()..httpClientAdapter = adapter;
    final config = BackendConfig.parse(
        mode: 'firebase',
        debug: true,
        web: true,
        platform: TargetPlatform.linux);
    final result = expectLater(
        FirebaseFeedsGateway(config, http, now: () => now).festivals(),
        throwsFormatException);
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    // The temple-page fallback has its own 10 s deadline.
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    await result;
    expect(adapter.requests, hasLength(2));
    http.close(force: true);
  });
  testWidgets(
      'Firebase festival refresh clears old success and does not display it after failure',
      (tester) async {
    var calls = 0;
    final pending = Completer<FirebaseFestivalFeed>();
    await tester.pumpWidget(ProviderScope(overrides: [
      firebaseFestivalFeedProvider.overrideWith((ref) {
        if (++calls == 1) {
          return Future.value(FirebaseFestivalFeed.parse(calendar(), now));
        }
        return pending.future;
      })
    ], child: const MaterialApp(home: EventsScreen(firebase: true))));
    await tester.pumpAndSettle();
    expect(find.text('Festival'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry events'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Festival'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('private-upstream'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load events'), findsOneWidget);
    expect(find.text('Festival'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final liveScreen in [false, true]) {
    testWidgets(
        'public feed screen fits 320px with double-sized text: live=$liveScreen',
        (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final local = DateTime.now();
      final tomorrow = DateTime.utc(local.year, local.month, local.day + 1);
      final page = {
        ...calendar(),
        'stale': true,
        'truncated': true,
        'events': [
          {
            ...event(),
            'title': 'Festival celebration at Shirdi',
            'eventDate': tomorrow.toIso8601String().substring(0, 10),
            'description': 'Festival programme at Shirdi.'
          }
        ]
      };
      await tester.pumpWidget(ProviderScope(
          overrides: [
            firebaseFestivalFeedProvider.overrideWith(
                (ref) async => FirebaseFestivalFeed.parse(page, now))
          ],
          child: MaterialApp(
              home: liveScreen
                  ? const LiveDarshanScreen(firebase: true)
                  : const EventsScreen(firebase: true))));
      await tester.pumpAndSettle();
      if (!liveScreen) {
        await tester.scrollUntilVisible(find.text('Tomorrow'), 150);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'late festival completion after leaving screen does not update disposed state',
      (tester) async {
    final pending = Completer<FirebaseFestivalFeed>();
    await tester.pumpWidget(ProviderScope(overrides: [
      firebaseFestivalFeedProvider.overrideWith((ref) => pending.future)
    ], child: const MaterialApp(home: EventsScreen(firebase: true))));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(FirebaseFestivalFeed.parse(calendar(), now));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'public Firebase live/events direct links do not construct Auth, profile or legacy APIs',
      (tester) async {
    final config = BackendConfig.parse(
        mode: 'firebase',
        debug: true,
        web: true,
        platform: TargetPlatform.linux);
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(config),
      apiClientProvider
          .overrideWith((ref) => throw StateError('Legacy API forbidden')),
      authStateProvider
          .overrideWith((ref) => throw StateError('Legacy auth forbidden')),
      firebaseAuthGatewayProvider.overrideWith(
          (ref) => throw StateError('Firebase auth/profile forbidden')),
      eventsRepositoryProvider
          .overrideWith((ref) => throw StateError('Legacy events forbidden')),
      firebaseFestivalFeedProvider.overrideWith(
          (ref) async => FirebaseFestivalFeed.parse(calendar(), now)),
    ]);
    final router = container.read(routerProvider)..go('/events');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Festival'), findsOneWidget);
    router.go('/live');
    await tester.pumpAndSettle();
    expect(find.byType(LiveDarshanScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Watch in Browser'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  testWidgets(
      'Firebase events reuse calendar UI without constructing the legacy repository',
      (tester) async {
    final pending = FirebaseFestivalFeed.parse(
        {...calendar(), 'stale': true, 'truncated': true},
        now.add(const Duration(days: 1)));
    await tester.pumpWidget(ProviderScope(overrides: [
      eventsRepositoryProvider
          .overrideWith((ref) => throw StateError('Legacy events forbidden')),
      firebaseFestivalFeedProvider.overrideWith((ref) async => pending),
    ], child: const MaterialApp(home: EventsScreen(firebase: true))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cached data (stale)'), findsOneWidget);
    expect(find.textContaining('Some source entries were truncated.'),
        findsOneWidget);
    expect(find.text('Monday, October 19, 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Firebase events error retry completes a fresh read and never renders raw errors',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      eventsRepositoryProvider
          .overrideWith((ref) => throw StateError('Legacy events forbidden')),
      firebaseFestivalFeedProvider.overrideWith((ref) async {
        if (++calls == 1) throw StateError('private-token');
        return FirebaseFestivalFeed.parse(calendar(), now);
      }),
    ], child: const MaterialApp(home: EventsScreen(firebase: true))));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load events'), findsOneWidget);
    expect(find.textContaining('private-token'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Festival'), findsOneWidget);
  });
  test(
      'festival calendar preserves literal UTC date and immutable bounded events',
      () {
    final feed = FirebaseFestivalFeed.parse(calendar(), now);
    expect(feed.events.single.eventDate, DateTime.utc(2026, 10, 19));
    expect(() => feed.events.clear(), throwsUnsupportedError);
    final unknown = calendar()
      ..['events'] = [
        {...event(), 'eventDate': null, 'dateLabel': 'Date pending'}
      ];
    expect(FirebaseFestivalFeed.parse(unknown, now).events.single.eventDate,
        isNull);
  });
  for (final bad in [
    '2026-02-30',
    '2026-13-01',
    '2026-1-19',
    '2026-10-19T00:00:00Z'
  ]) {
    test('festival invalid calendar date rejected: $bad', () {
      final data = calendar()
        ..['events'] = [
          {...event(), 'eventDate': bad}
        ];
      expect(
          () => FirebaseFestivalFeed.parse(data, now), throwsFormatException);
    });
  }
  test(
      'duplicate, oversized, extra-field and partially malformed calendars reject the whole page',
      () {
    for (final events in [
      [event(), event()],
      List.filled(51, event()),
      [
        event(),
        {...event(), 'id': 'bad'}
      ]
    ]) {
      expect(
          () => FirebaseFestivalFeed.parse(
              {...calendar(), 'events': events}, now),
          throwsFormatException);
    }
    expect(
        () => FirebaseFestivalFeed.parse({...calendar(), 'private': 'no'}, now),
        throwsFormatException);
  });
  test('explicit stale festivals survive only within server maximum cache age',
      () {
    final data = {...calendar(), 'stale': true};
    expect(
        FirebaseFestivalFeed.parse(data, now.add(const Duration(days: 1)))
            .metadata
            .stale,
        isTrue);
    expect(
        () =>
            FirebaseFestivalFeed.parse(data, now.add(const Duration(days: 7))),
        throwsFormatException);
  });
  test(
      'live rejects stale, expired or malformed freshness without preserving an old URL',
      () {
    expect(FirebaseLiveFeed.parse(live(), now).url.scheme, 'https');
    expect(() => FirebaseLiveFeed.parse({...live(), 'stale': true}, now),
        throwsFormatException);
    expect(
        () => FirebaseLiveFeed.parse(
            live(), now.add(const Duration(seconds: 30))),
        throwsFormatException);
    expect(
        () => FirebaseLiveFeed.parse(
            {...live(), 'sourceUrl': festivalFeedSource}, now),
        throwsFormatException);
    expect(
        () => FirebaseLiveFeed.parse(
            {...live(), 'fetchedAt': '2026-02-30T00:00:00.000Z'}, now),
        throwsFormatException);
  });
  for (final url in [
    'http://stream.example.org/live.m3u8',
    'https://127.0.0.1/live.m3u8',
    'https://[::1]/live.m3u8',
    'https://localhost./live.m3u8',
    'https://stream.local./live.m3u8',
    'https://user:pass@stream.example.org/live.m3u8',
    'https://stream.example.org:5001/live.m3u8',
    'https://stream.example.org/live.m3u8#token',
    'https://stream.example.org/live.html'
  ]) {
    test('unsafe playback URL rejected: $url',
        () => expect(() => firebaseStreamUri(url), throwsFormatException));
  }
  test(
      'gateway targets pinned public Functions endpoint without auth, redirects or credentials',
      () async {
    final adapter = FeedAdapter();
    final http = Dio()..httpClientAdapter = adapter;
    final config = BackendConfig.parse(
        mode: 'firebase',
        debug: true,
        web: true,
        platform: TargetPlatform.linux);
    final gateway = FirebaseFeedsGateway(config, http, now: () => now);
    await gateway.festivals();
    final request = adapter.requests.single;
    expect(request.uri.toString(),
        'http://127.0.0.1:5001/demo-om-sai-ram/us-central1/festivals');
    expect(request.followRedirects, isFalse);
    expect(request.headers['Authorization'], isNull);
    expect(request.extra['withCredentials'], isFalse);
    expect(request.method, 'GET');
    http.close();
  });
  test(
      'gateway fails closed for legacy mode, redirect/status failure, malformed/oversized payload',
      () async {
    final adapter = FeedAdapter();
    final http = Dio()..httpClientAdapter = adapter;
    final legacy = BackendConfig.parse(
        mode: 'fastapi', debug: true, web: true, platform: TargetPlatform.linux);
    await expectLater(
        FirebaseFeedsGateway(legacy, http).festivals(), throwsFormatException);
    expect(adapter.requests, isEmpty);
    // A real project uses only its configured https Functions origin, or the temple page.
    BackendConfig real(String feeds) => BackendConfig.parse(mode: 'firebase', projectId: 'om-sai-sannidhi',
        apiKey: 'key', appId: 'app', messagingSenderId: '123', feedsBaseUrl: feeds,
        debug: false, web: false, platform: TargetPlatform.android);
    await expectLater(FirebaseFeedsGateway(real(''), http).liveDarshan(), throwsFormatException);
    expect(adapter.requests.map((r) => r.uri.toString()), [liveFeedSource]);
    adapter.requests.clear();
    expect(FirebaseFeedsGateway(real('https://feeds.example.org/api/'), http).endpoint('festivals').toString(),
        'https://feeds.example.org/api/festivals');
    expect(FirebaseFeedsGateway(real('https://feeds.example.org'), http).endpoint('liveDarshan').toString(),
        'https://feeds.example.org/liveDarshan');
    final config = BackendConfig.parse(
        mode: 'firebase',
        debug: true,
        web: true,
        platform: TargetPlatform.linux);
    final gateway = FirebaseFeedsGateway(config, http, now: () => now);
    for (final status in [302, 502]) {
      adapter.status = status;
      await expectLater(gateway.festivals(), throwsFormatException);
    }
    adapter.status = 200;
    adapter.body = 'bad JSON';
    await expectLater(gateway.festivals(), throwsFormatException);
    adapter.body = 'x' * 262145;
    await expectLater(gateway.festivals(), throwsFormatException);
    http.close();
  });
}
