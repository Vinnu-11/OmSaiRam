// Om Sai Ram
// Content repository — loads Satcharita chapters from assets or server.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
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

  /// Returns a single chapter by its number for the given language.
  Future<Chapter?> getChapter(int chapterNumber, {String language = 'en'}) async {
    final chapters = await getChapters(language: language);
    try {
      return chapters.firstWhere((c) => c.number == chapterNumber);
    } catch (_) {
      return null;
    }
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
        final List<dynamic> data = chaptersResponse.data['chapters'];
        _cache[language] = data.map((j) => Chapter.fromJson(j)).toList();
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
