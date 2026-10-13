// Om Sai Ram
// Content repository — loads Satcharita chapters from assets or server.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/chapter_units.dart';
import '../../../core/services/api_client.dart';
import 'chapter_model.dart';

/// Provider for the content repository.
final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  return ContentRepository(apiClient: ref.read(apiClientProvider));
});

/// Manages loading and caching of Satcharita chapter content.
///
/// Strategy:
/// 1. Load bundled content from app assets (offline-first)
/// 2. Check server for newer content version
/// 3. If server has updates, fetch and cache new content
///
/// This ensures the app works offline with bundled content
/// while supporting content updates without app store releases.
class ContentRepository {
  final ApiClient _apiClient;
  // Per-language cache so switching languages doesn't invalidate the other.
  final Map<String, List<Chapter>> _cache = {};

  ContentRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Loads all chapters for the given language, using per-language cache.
  Future<List<Chapter>> getChapters({String language = 'en'}) async {
    if (_cache.containsKey(language)) return _cache[language]!;

    _cache[language] = await _loadBundledChapters(language);
    _checkForUpdates(language);
    return _cache[language]!;
  }

  /// Returns the entry covering Marathi adhyaya [chapterNumber] (entries may
  /// span a range, e.g. "16-17", in translations that merge adhyayas).
  Future<Chapter?> getChapter(int chapterNumber, {String language = 'en'}) async {
    final chapters = await getChapters(language: language);
    for (final c in chapters) {
      if (c.covers(chapterNumber)) return c;
    }
    // Translation lacks this adhyaya (e.g. Gunaji English folds 50 into 39):
    // fall back to the Marathi original.
    return language == 'mr' ? null : getChapter(chapterNumber, language: 'mr');
  }

  /// Assemble separate Marathi originals for a combined group assignment,
  /// without changing the standalone chapter list.
  Future<Chapter?> getAssignmentChapter(int chapterNumber,
      {String language = 'en'}) async {
    final start = ChapterUnits.start(chapterNumber);
    final end = ChapterUnits.end(chapterNumber);
    final parts = <Chapter>[];
    for (var n = start; n <= end; n++) {
      final chapter = await getChapter(n, language: language);
      if (chapter == null) return null;
      if (!parts.any((part) => part.number == chapter.number)) {
        parts.add(chapter);
      }
    }
    if (parts.length == 1) return parts.first;
    final first = parts.first;
    return Chapter(
      id: first.id,
      number: start,
      chapterLabel: ChapterUnits.label(start),
      title: first.title,
      content: parts.map((part) =>
          '${part.heading ?? 'Chapter ${part.number}'}\n\n${part.content}').join('\n\n'),
      language: first.language,
      version: first.version,
    );
  }

  /// Loads chapters from the bundled JSON asset file.
  Future<List<Chapter>> _loadBundledChapters(String language) async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/content/satcharita_$language.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((j) => Chapter.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Checks the server for a newer content version.
  /// If available, fetches and updates the cache.
  Future<void> _checkForUpdates(String language) async {
    try {
      final response = await _apiClient.get(
        AppConstants.contentVersionsEndpoint,
        queryParameters: {'language': language},
      );

      final serverVersion = response.data['version'] as int;
      final cached = _cache[language];
      final localVersion =
          cached != null && cached.isNotEmpty ? cached.first.version : 0;

      if (serverVersion > localVersion) {
        final chaptersResponse = await _apiClient.get(
          '${AppConstants.chaptersEndpoint}/$language',
        );
        // Backend returns a bare JSON list of chapters.
        final List<dynamic> data = chaptersResponse.data;
        // Never let a partial server copy replace the full bundled book.
        if (data.length >= (cached?.length ?? 0)) {
          _cache[language] = data.map((j) => Chapter.fromJson(j)).toList();
        }
      }
    } catch (_) {
      // Server unavailable — continue with bundled content
    }
  }

  /// Clears the cache for one language, or all languages if null.
  void clearCache([String? language]) {
    if (language != null) {
      _cache.remove(language);
    } else {
      _cache.clear();
    }
  }
}
