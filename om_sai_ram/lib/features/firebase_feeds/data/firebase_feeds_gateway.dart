import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/backend_config.dart';
import 'direct_feed_sources.dart';
import 'firebase_feed_models.dart';

class FirebaseFeedsGateway {
  final BackendConfig config;
  final Dio http;
  final DateTime Function() now;
  FirebaseFeedsGateway(this.config, this.http, {DateTime Function()? now})
      : now = now ?? DateTime.now;

  /// Releases without deployed Functions read sai.org.in themselves; the temple
  /// pages send `Access-Control-Allow-Origin: *`, so browsers can too.
  bool get direct => config.mode == BackendMode.firebase &&
      config.production != null && config.production!.feedsBaseUrl.isEmpty;

  Uri endpoint(String name) {
    if (config.mode != BackendMode.firebase ||
        !['liveDarshan', 'festivals'].contains(name)) {
      throw const FormatException('Firebase feed configuration required.');
    }
    final production = config.production;
    if (production != null) {
      // Deployed Functions need the Blaze plan, so a release may ship without them.
      if (production.feedsBaseUrl.isEmpty) {
        throw const FormatException('This feed is not available in this release.');
      }
      final base = Uri.parse(production.feedsBaseUrl);
      return base.replace(
          path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/$name');
    }
    return Uri(
        scheme: 'http',
        host: config.emulatorHost,
        port: BackendConfig.functionsPort,
        path: '/${BackendConfig.demoProjectId}/us-central1/$name');
  }

  Future<Object?> _get(String name) async {
    final uri = endpoint(name);
    final cancel = CancelToken();
    try {
      final response = await http.getUri<String>(uri,
          options: Options(
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (status) => status == 200,
              extra: {'withCredentials': false}),
          cancelToken: cancel, onReceiveProgress: (received, total) {
        if (received > 262144 || total > 262144) cancel.cancel();
      }).timeout(const Duration(seconds: 15), onTimeout: () {
        cancel.cancel();
        throw const FormatException('Feed request timed out.');
      });
      final body = response.data;
      if (body == null ||
          utf8.encode(body).length > 262144 ||
          !(response.headers.value(Headers.contentTypeHeader) ?? '')
              .toLowerCase()
              .startsWith('application/json')) {
        throw const FormatException('Invalid feed response.');
      }
      return jsonDecode(body);
    } catch (_) {
      throw const FormatException(
          'Feed unavailable. Check your connection and retry.');
    }
  }

  Future<Map<String, Object?>> _direct(bool live) async {
    final source = live ? liveFeedSource : festivalFeedSource;
    final fetched = now().toUtc();
    final Map<String, Object?> body;
    try {
      final page = await fetchSourceHtml(http, source);
      if (live) {
        body = {'url': parseLiveHtml(page)};
      } else {
        final festivals = parseFestivalHtml(page);
        body = {'events': festivals.events, 'truncated': festivals.truncated};
      }
    } catch (_) {
      throw const FormatException('Feed unavailable. Check your connection and retry.');
    }
    final stamp = DateTime.fromMillisecondsSinceEpoch(fetched.millisecondsSinceEpoch, isUtc: true);
    return {
      ...body,
      'sourceUrl': source,
      'fetchedAt': stamp.toIso8601String(),
      'freshUntil': stamp.add(live ? const Duration(seconds: 30) : const Duration(hours: 6)).toIso8601String(),
      'stale': false,
    };
  }

  Future<T> _feed<T>(String name, T Function(Object?, DateTime) parse) async {
    if (config.mode != BackendMode.firebase) {
      throw const FormatException('Firebase feed configuration required.');
    }
    if (!direct) {
      try {
        return parse(await _get(name), now().toUtc());
      } on FormatException {
        // The feed service is only a cache; the temple page is the source.
      }
    }
    return parse(await _direct(name == 'liveDarshan'), now().toUtc());
  }

  Future<FirebaseLiveFeed> liveDarshan() => _feed('liveDarshan', FirebaseLiveFeed.parse);
  Future<FirebaseFestivalFeed> festivals() => _feed('festivals', FirebaseFestivalFeed.parse);
}

final firebaseFeedsGatewayProvider = Provider<FirebaseFeedsGateway>((ref) {
  final config = ref.watch(backendConfigProvider);
  final http = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 15)));
  ref.onDispose(() => http.close(force: true));
  return FirebaseFeedsGateway(config, http);
});
final firebaseLiveFeedProvider = FutureProvider.autoDispose<FirebaseLiveFeed>(
    (ref) => ref.watch(firebaseFeedsGatewayProvider).liveDarshan());
final firebaseFestivalFeedProvider =
    FutureProvider.autoDispose<FirebaseFestivalFeed>(
        (ref) => ref.watch(firebaseFeedsGatewayProvider).festivals());
