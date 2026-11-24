class FirebaseFeedMetadata {
  final DateTime fetchedAt, freshUntil;
  final bool stale;
  final String sourceUrl;
  FirebaseFeedMetadata._(
      this.fetchedAt, this.freshUntil, this.stale, this.sourceUrl);
  factory FirebaseFeedMetadata.parse(Map<String, dynamic> data,
      {required bool live, required DateTime now}) {
    final source = live ? liveFeedSource : festivalFeedSource;
    final fetched = _instant(data['fetchedAt']);
    final until = _instant(data['freshUntil']);
    final stale = data['stale'];
    final interval =
        live ? const Duration(seconds: 30) : const Duration(hours: 6);
    if (data['sourceUrl'] != source ||
        stale is! bool ||
        until.difference(fetched) != interval ||
        fetched.isAfter(now.add(const Duration(minutes: 5))) ||
        (live && stale) ||
        (!stale && !now.isBefore(until)) ||
        (stale && now.difference(fetched) >= const Duration(days: 7))) {
      throw const FormatException('Invalid or expired feed metadata.');
    }
    return FirebaseFeedMetadata._(fetched, until, stale, source);
  }
}

const liveFeedSource =
    'https://sai.org.in/node/504?width=960&height=540&iframe=true';
const festivalFeedSource = 'https://sai.org.in/en/festivals';

DateTime _instant(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
          .hasMatch(value)) {
    throw const FormatException('Invalid feed timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String() != value) {
    throw const FormatException('Invalid feed timestamp.');
  }
  return parsed;
}

Map<String, dynamic> feedFields(Object? raw, Set<String> fields) {
  if (raw is! Map<String, dynamic> ||
      raw.length != fields.length ||
      !raw.keys.toSet().containsAll(fields)) {
    throw const FormatException('Invalid feed fields.');
  }
  return raw;
}

Uri firebaseStreamUri(Object? value) {
  final uri =
      value is String && value.length <= 4096 ? Uri.tryParse(value) : null;
  final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ?? '';
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasFragment ||
      host.contains(':') ||
      RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host) ||
      !host.contains('.') ||
      RegExp(r'(^|\.)(localhost|local|internal)$').hasMatch(host) ||
      !uri.path.toLowerCase().endsWith('.m3u8')) {
    throw const FormatException('Invalid stream URL.');
  }
  return uri;
}

class FirebaseLiveFeed {
  final Uri url;
  final FirebaseFeedMetadata metadata;
  FirebaseLiveFeed._(this.url, this.metadata);
  factory FirebaseLiveFeed.parse(Object? raw, DateTime now) {
    final data = feedFields(
        raw, {'url', 'sourceUrl', 'fetchedAt', 'freshUntil', 'stale'});
    return FirebaseLiveFeed._(firebaseStreamUri(data['url']),
        FirebaseFeedMetadata.parse(data, live: true, now: now));
  }
}

class FirebaseFestival {
  final String id, title, dateLabel;
  final DateTime? eventDate;
  final String? description;
  FirebaseFestival._(
      this.id, this.title, this.dateLabel, this.eventDate, this.description);
  factory FirebaseFestival.parse(Object? raw) {
    final data = feedFields(
        raw, {'id', 'title', 'dateLabel', 'eventDate', 'description'});
    String text(String key, int maximum) {
      final value = data[key];
      if (value is! String || value.trim().isEmpty || value.length > maximum) {
        throw const FormatException('Invalid festival text.');
      }
      return value;
    }

    final id = text('id', 64);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
      throw const FormatException('Invalid festival identity.');
    }
    DateTime? date;
    if (data['eventDate'] != null) {
      final value = data['eventDate'];
      if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        throw const FormatException('Invalid calendar date.');
      }
      date = DateTime.tryParse('${value}T00:00:00.000Z');
      if (date == null || date.toIso8601String().substring(0, 10) != value) {
        throw const FormatException('Invalid calendar date.');
      }
    }
    final description =
        data['description'] == null ? null : text('description', 2000);
    return FirebaseFestival._(
        id, text('title', 255), text('dateLabel', 100), date, description);
  }
}

class FirebaseFestivalFeed {
  final List<FirebaseFestival> events;
  final bool truncated;
  final FirebaseFeedMetadata metadata;
  FirebaseFestivalFeed._(this.events, this.truncated, this.metadata);
  factory FirebaseFestivalFeed.parse(Object? raw, DateTime now) {
    final data = feedFields(raw, {
      'events',
      'truncated',
      'sourceUrl',
      'fetchedAt',
      'freshUntil',
      'stale'
    });
    final events = data['events'];
    if (events is! List || events.length > 50 || data['truncated'] is! bool) {
      throw const FormatException('Invalid festival page.');
    }
    final parsed = events.map(FirebaseFestival.parse).toList();
    if (parsed.map((event) => event.id).toSet().length != parsed.length) {
      throw const FormatException('Duplicate festivals.');
    }
    return FirebaseFestivalFeed._(
        List.unmodifiable(parsed),
        data['truncated'] as bool,
        FirebaseFeedMetadata.parse(data, live: false, now: now));
  }
}
