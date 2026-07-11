// Om Sai Ram
// Reader state provider — manages chapter list and current reading state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/language_provider.dart';
import '../data/chapter_model.dart';
import '../data/content_repository.dart';

/// State for the chapters list.
class ChaptersState {
  final List<Chapter> chapters;
  final bool isLoading;
  final String? error;

  const ChaptersState({
    this.chapters = const [],
    this.isLoading = false,
    this.error,
  });

  ChaptersState copyWith({
    List<Chapter>? chapters,
    bool? isLoading,
    String? error,
  }) {
    return ChaptersState(
      chapters: chapters ?? this.chapters,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Provider for the chapters list — reacts to reader language changes.
final chaptersProvider =
    StateNotifierProvider<ChaptersNotifier, ChaptersState>((ref) {
  final notifier = ChaptersNotifier(
    repository: ref.read(contentRepositoryProvider),
    ref: ref,
  );
  // Reload when the reader language changes.
  ref.listen<LanguageState>(languageProvider, (prev, next) {
    if (prev?.readerLanguage != next.readerLanguage) {
      notifier.loadChapters(language: next.readerLanguage.code);
    }
  });
  return notifier;
});

/// Manages loading and state of Satcharita chapters.
class ChaptersNotifier extends StateNotifier<ChaptersState> {
  final ContentRepository _repository;
  // ignore: unused_field
  final Ref _ref;

  ChaptersNotifier({required ContentRepository repository, required Ref ref})
      : _repository = repository,
        _ref = ref,
        super(const ChaptersState());

  /// Loads all chapters for [language] from bundled content/server.
  Future<void> loadChapters({String? language}) async {
    final lang = language ?? _ref.read(languageProvider).readerLanguage.code;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final chapters = await _repository.getChapters(language: lang);
      state = ChaptersState(chapters: chapters);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

/// Provider for a single chapter by number — respects reader language.
final chapterProvider =
    FutureProvider.family<Chapter?, int>((ref, chapterNumber) async {
  final lang = ref.watch(languageProvider).readerLanguage.code;
  final repo = ref.read(contentRepositoryProvider);
  return repo.getChapter(chapterNumber, language: lang);
});
