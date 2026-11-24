// Dart port of firebase/functions/src/feed-sources.mjs, so Android releases can
// read the temple pages directly when no Cloud Functions are deployed.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'firebase_feed_models.dart';

const maxSourceHtmlBytes = 1024 * 1024;
const maxFestivalEvents = 50;

Future<String> fetchSourceHtml(Dio http, String source) async {
  if (source != liveFeedSource && source != festivalFeedSource) {
    throw const FormatException('Invalid feed source.');
  }
  final cancel = CancelToken();
  Future<String> run() async {
    var url = Uri.parse(source);
    for (var redirects = 0; redirects <= 3; redirects++) {
      final response = await http.getUri<String>(url,
          options: Options(
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (_) => true,
              headers: {'Accept': 'text/html'}),
          cancelToken: cancel, onReceiveProgress: (received, total) {
        if (received > maxSourceHtmlBytes || total > maxSourceHtmlBytes) cancel.cancel();
      });
      final status = response.statusCode ?? 0;
      if (const [301, 302, 303, 307, 308].contains(status)) {
        final location = response.headers.value('location');
        if (location == null || redirects == 3) throw const FormatException('Invalid redirect.');
        final next = url.resolve(location);
        if (next.scheme != 'https' ||
            !const ['sai.org.in', 'www.sai.org.in'].contains(next.host) ||
            next.userInfo.isNotEmpty ||
            next.port != 443) {
          throw const FormatException('Invalid redirect.');
        }
        url = next;
        continue;
      }
      final body = response.data;
      if (status != 200 ||
          body == null ||
          !(response.headers.value(Headers.contentTypeHeader) ?? '').toLowerCase().startsWith('text/html') ||
          utf8.encode(body).length > maxSourceHtmlBytes) {
        throw const FormatException('Feed source unavailable.');
      }
      return body;
    }
    throw const FormatException('Invalid redirect.');
  }

  return run().timeout(const Duration(seconds: 10), onTimeout: () {
    cancel.cancel();
    throw const FormatException('Feed request timed out.');
  });
}

Document _document(String source) {
  if (utf8.encode(source).length > maxSourceHtmlBytes) {
    throw const FormatException('Feed source too large.');
  }
  return html.parse(source);
}

String parseLiveHtml(String source) {
  final candidates = <String>{};
  final pattern = RegExp(r'"newurl"\s*:\s*("(?:\\.|[^"\\])*")');
  for (final script in _document(source).querySelectorAll('script')) {
    for (final match in pattern.allMatches(script.text)) {
      candidates.add(firebaseStreamUri(jsonDecode(match.group(1)!)).toString());
    }
  }
  if (candidates.length != 1) throw const FormatException('Invalid stream.');
  return candidates.single;
}

const _months = ['january', 'february', 'march', 'april', 'may', 'june', 'july',
  'august', 'september', 'october', 'november', 'december'];

String? festivalDate(String label) {
  final numeric = RegExp(r'^(\d{1,2})([./-])(\d{1,2})\2(\d{4})$').firstMatch(label);
  final named = RegExp(r'^([a-z]+)\s+(\d{1,2}),\s*(\d{4})$', caseSensitive: false).firstMatch(label);
  final day = numeric != null ? int.parse(numeric[1]!) : named != null ? int.parse(named[2]!) : 0;
  final month = numeric != null
      ? int.parse(numeric[3]!)
      : named != null
          ? _months.indexWhere((value) => [value, value.substring(0, 3)].contains(named[1]!.toLowerCase())) + 1
          : 0;
  final year = int.tryParse(numeric?[4] ?? named?[3] ?? '') ?? 0;
  if (year < 1000 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date.toIso8601String().substring(0, 10)
      : null;
}

/// Returns the same JSON shape as the festivals Cloud Function, without metadata.
({List<Map<String, Object?>> events, bool truncated}) parseFestivalHtml(String source) {
  final document = _document(source);
  final events = <String, Map<String, Object?>>{};
  var truncated = false;
  String text(Element element) => element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
  void add(String title, String dateLabel, String? description) {
    if (title.isEmpty ||
        dateLabel.isEmpty ||
        RegExp(r'^(date|day|s\.?\s*no\.?|sr\.?\s*no\.?)$', caseSensitive: false).hasMatch(dateLabel)) {
      return;
    }
    if (title.length > 255 || dateLabel.length > 100 || (description?.length ?? 0) > 2000) truncated = true;
    title = title.length > 255 ? title.substring(0, 255) : title;
    dateLabel = dateLabel.length > 100 ? dateLabel.substring(0, 100) : dateLabel;
    final key = jsonEncode([title, dateLabel]);
    if (events.containsKey(key)) return;
    final clipped = description == null || description.isEmpty
        ? null
        : description.length > 2000 ? description.substring(0, 2000) : description;
    events[key] = {
      'id': sha256.convert(utf8.encode(key)).toString(),
      'title': title,
      'dateLabel': dateLabel,
      'eventDate': festivalDate(dateLabel),
      'description': clipped,
    };
  }

  for (final row in document.querySelectorAll('table tr')) {
    final cells = row.children.where((cell) => cell.localName == 'td').toList();
    if (cells.length >= 4 &&
        (RegExp(r'^\d+\s*day$', caseSensitive: false).hasMatch(text(cells[0])) ||
            festivalDate(text(cells[3])) != null)) {
      add(text(cells[1]), text(cells[3]), cells.length > 4 ? text(cells[4]) : null);
    } else if (cells.length >= 2) {
      add(text(cells[1]), text(cells[0]), cells.length > 2 ? text(cells[2]) : null);
    }
  }
  for (final heading in document.querySelectorAll('h2,h3,h4,strong')) {
    final title = text(heading);
    final dates = RegExp(r'\d{1,2}[./]\d{1,2}[./]\d{4}').allMatches(title).toList();
    if (dates.length != 1) continue;
    final label = dates.single[0]!;
    final name = title
        .replaceFirst(label, '')
        .replaceAll(RegExp(r'^[\s,:\-\u2013\u2014]+|[\s,:\-\u2013\u2014]+$'), '');
    Element? paragraph = heading.nextElementSibling;
    while (paragraph != null && paragraph.localName != 'p') {
      paragraph = paragraph.nextElementSibling;
    }
    add(name, label, paragraph == null ? null : text(paragraph));
  }
  if (events.isEmpty && document.querySelector('.view-festivals-page') != null) {
    return (events: const [], truncated: false);
  }
  if (events.isEmpty) throw const FormatException('Invalid festivals.');
  final sorted = events.values.toList()
    ..sort((left, right) {
      final byDate = ((left['eventDate'] as String?) ?? '9999-99-99')
          .compareTo((right['eventDate'] as String?) ?? '9999-99-99');
      if (byDate != 0) return byDate;
      final byTitle = (left['title'] as String).compareTo(right['title'] as String);
      return byTitle != 0 ? byTitle : (left['id'] as String).compareTo(right['id'] as String);
    });
  return (
    events: sorted.take(maxFestivalEvents).toList(),
    truncated: truncated || sorted.length > maxFestivalEvents,
  );
}
