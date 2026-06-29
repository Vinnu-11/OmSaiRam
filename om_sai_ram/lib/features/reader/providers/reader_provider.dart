// Om Sai Ram
// Reader state provider — manages chapter list and current reading state.

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Provider for the chapters list.
final chaptersProvider =
    StateNotifierProvider<ChaptersNotifier, ChaptersState>((ref) {
  return ChaptersNotifier(repository: ref.read(contentRepositoryProvider));
});

/// Manages loading and state of Satcharita chapters.
class ChaptersNotifier extends StateNotifier<ChaptersState> {
  final ContentRepository _repository;

  ChaptersNotifier({required ContentRepository repository})
      : _repository = repository,
        super(const ChaptersState());

  /// Loads all chapters from bundled content/server.
  Future<void> loadChapters({String language = 'en'}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final chapters = await _repository.getChapters(language: language);
      state = ChaptersState(chapters: chapters);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

/// Provider for a single chapter by number.
final chapterProvider =
    FutureProvider.family<Chapter?, int>((ref, chapterNumber) async {
  final repo = ref.read(contentRepositoryProvider);
  return repo.getChapter(chapterNumber);
});
