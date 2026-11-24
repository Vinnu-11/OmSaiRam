import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/features/firebase_feeds/data/direct_feed_sources.dart';
import 'package:om_sai_ram/features/firebase_feeds/data/firebase_feed_models.dart';
import 'package:om_sai_ram/features/firebase_feeds/data/firebase_feeds_gateway.dart';

const stream = 'https://stream.example.org/live.m3u8?token=fixture&second=1';

class PageAdapter implements HttpClientAdapter {
  final requests = <Uri>[];
  final List<ResponseBody Function(Uri)> replies;
  PageAdapter(this.replies);
  static ResponseBody page(String body, {String type = 'text/html; charset=utf-8', int status = 200}) =>
      ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: [type]});
  static ResponseBody redirect(String location) =>
      ResponseBody.fromString('', 302, headers: {'location': [location]});
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options.uri);
    return replies[requests.length - 1](options.uri);
  }

  @override
  void close({bool force = false}) {}
}

Dio dio(PageAdapter adapter) => Dio()..httpClientAdapter = adapter;

BackendConfig release() => BackendConfig.parse(mode: 'firebase', projectId: 'om-sai-sannidhi',
    apiKey: 'key', appId: 'app', messagingSenderId: '123', feedsBaseUrl: '',
    debug: false, web: false, platform: TargetPlatform.android);

void main() {
  test('live settings are JSON-unescaped and must agree', () {
    final value = jsonEncode(stream).replaceAll('/', r'\/').replaceFirst('&', r'\u0026');
    expect(parseLiveHtml('<script>settings = {"newurl":$value};</script>'), stream);
    final script = '<script>{"newurl":${jsonEncode(stream)}}</script>';
    expect(parseLiveHtml(script + script), stream);
    expect(() => parseLiveHtml('$script<script>{"newurl":"https://stream.example.org/other.m3u8"}</script>'),
        throwsFormatException);
    expect(() => parseLiveHtml('<p>Stream offline</p>'), throwsFormatException);
    expect(() => parseLiveHtml('<script>{"newurl":"http://stream.example.org/live.m3u8"}</script>'),
        throwsFormatException);
  });

  for (final (label, expected) in [('28.07.2026', '2026-07-28'), ('28/07/2026', '2026-07-28'),
    ('28-07-2026', '2026-07-28'), ('July 28, 2026', '2026-07-28'), ('Jul 28, 2026', '2026-07-28'),
    ('29.02.2028', '2028-02-29'), ('29.02.2026', null), ('31.04.2026', null), ('28.07/2026', null),
    ('Januaryx 28, 2026', null), ('28-30 July 2026', null), ('Date pending', null)]) {
    test('festival date $label', () => expect(festivalDate(label), expected));
  }

  test('festival table ignores headers, deduplicates and puts unknown dates last', () {
    final parsed = parseFestivalHtml('''<table><tr><th>Date</th><th>Event</th></tr>
        <tr><td>Pending</td><td>Undated event</td></tr>
        <tr><td>28.07.2026</td><td>Guru &amp; Pournima</td><td><p>Actual description</p></td></tr>
        <tr><td>28.07.2026</td><td>Guru &amp; Pournima</td></tr></table>''');
    expect(parsed.events, hasLength(2));
    expect(parsed.events[0]['title'], 'Guru & Pournima');
    expect(parsed.events[0]['description'], 'Actual description');
    expect(parsed.events[1]['eventDate'], isNull);
    expect(parsed.truncated, isFalse);
  });

  test('festival heading uses only an explicit date', () {
    final parsed = parseFestivalHtml('<h3>Guru Pournima - 28.07.2026</h3><p>Celebration</p><h3>Diwali</h3>');
    expect(parsed.events, hasLength(1));
    expect(parsed.events.single['title'], 'Guru Pournima');
    expect(parsed.events.single['eventDate'], '2026-07-28');
    expect(parsed.events.single['description'], 'Celebration');
  });

  test('temple four-column layout maps the explicit date', () {
    final parsed = parseFestivalHtml('''<table>
        <tr><td>2Day</td><td>Main day</td><td>Tuesday</td><td>20.10.2026</td></tr>
        <tr><td>1Day</td><td>Opening day</td><td>Monday</td><td>19.10.2026</td></tr>
        <tr><td>3Day</td><td>Unconfirmed day</td><td>Pending</td><td>Date pending</td></tr></table>''');
    expect(parsed.events.map((event) => event['title']), ['Opening day', 'Main day', 'Unconfirmed day']);
    expect(parsed.events[0]['eventDate'], '2026-10-19');
    expect(parsed.events[0]['description'], isNull);
    expect(parsed.events[2]['dateLabel'], 'Date pending');
  });

  test('festival bounds, official empty state and invalid pages', () {
    final rows = List.generate(60, (index) => '<tr><td>Pending</td><td>Event $index</td><td>${'x' * 2200}</td></tr>').join();
    final parsed = parseFestivalHtml('<table>$rows</table>');
    expect(parsed.events, hasLength(50));
    expect(parsed.truncated, isTrue);
    expect((parsed.events[0]['description'] as String).length, 2000);
    final empty = parseFestivalHtml('<h2>Upcoming Festivals</h2><div class="view view-festivals-page"></div>');
    expect(empty.events, isEmpty);
    expect(empty.truncated, isFalse);
    expect(() => parseFestivalHtml('<h1>Challenge</h1>'), throwsFormatException);
    expect(() => parseFestivalHtml('x' * (maxSourceHtmlBytes + 1)), throwsFormatException);
  });

  test('release without a feed service reads the temple pages directly', () async {
    final now = DateTime.utc(2026, 10, 15, 12, 0, 0, 123, 456);
    final adapter = PageAdapter([
      (_) => PageAdapter.redirect('https://www.sai.org.in/en/live'),
      (_) => PageAdapter.page('<script>{"newurl":${jsonEncode(stream)}}</script>'),
      (_) => PageAdapter.page('<table><tr><td>19.10.2026</td><td>Vijayadashami</td></tr></table>'),
    ]);
    final gateway = FirebaseFeedsGateway(release(), dio(adapter), now: () => now);
    expect(gateway.direct, isTrue);
    final live = await gateway.liveDarshan();
    expect(live.url.toString(), stream);
    expect(live.metadata.stale, isFalse);
    expect(adapter.requests.first.toString(), liveFeedSource);
    final festivals = await gateway.festivals();
    expect(festivals.events.single.title, 'Vijayadashami');
    expect(festivals.events.single.eventDate, DateTime.utc(2026, 10, 19));
    expect(adapter.requests.last.toString(), festivalFeedSource);
  });

  test('a failing feed service falls back to the temple page', () async {
    final config = BackendConfig.parse(mode: 'firebase', projectId: 'om-sai-sannidhi',
        apiKey: 'key', appId: 'app', messagingSenderId: '123', feedsBaseUrl: 'https://feeds.example.org',
        debug: false, web: true, platform: TargetPlatform.android);
    final adapter = PageAdapter([
      (_) => PageAdapter.page('{}', status: 502, type: 'application/json'),
      (_) => PageAdapter.page('<script>{"newurl":${jsonEncode(stream)}}</script>'),
    ]);
    final gateway = FirebaseFeedsGateway(config, dio(adapter));
    expect(gateway.direct, isFalse);
    expect((await gateway.liveDarshan()).url.toString(), stream);
    expect(adapter.requests.map((uri) => uri.toString()),
        ['https://feeds.example.org/liveDarshan', liveFeedSource]);
  });

  test('direct reads refuse foreign redirects, non-HTML and error pages', () async {
    for (final reply in <ResponseBody Function(Uri)>[
      (_) => PageAdapter.redirect('https://evil.example.org/live'),
      (_) => PageAdapter.redirect('http://www.sai.org.in/live'),
      (_) => PageAdapter.page('{"newurl":"x"}', type: 'application/json'),
      (_) => PageAdapter.page('<p>down</p>', status: 503),
      (_) => PageAdapter.page('<p>Stream offline</p>'),
    ]) {
      final adapter = PageAdapter([reply, reply]);
      await expectLater(FirebaseFeedsGateway(release(), dio(adapter)).liveDarshan(),
          throwsA(isA<FormatException>().having((error) => error.message, 'message', contains('Feed unavailable'))));
      expect(adapter.requests.length, 1);
    }
    final loop = PageAdapter(List.filled(5, (_) => PageAdapter.redirect('https://sai.org.in/again')));
    await expectLater(FirebaseFeedsGateway(release(), dio(loop)).festivals(), throwsFormatException);
    expect(loop.requests.length, 4);
  });
}
