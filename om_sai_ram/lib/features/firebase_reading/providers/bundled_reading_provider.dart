import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reader/data/chapter_model.dart';
import '../../reader/data/content_repository.dart';
import '../data/bundled_reading.dart';

typedef BundledReadingSelection = ({String language, String chapterNumber});

final bundledCatalogueProvider = FutureProvider.autoDispose
    .family<List<Chapter>, String>((ref, language) async {
  validateReadingLanguage(language);
  final entries = await ref.watch(bundledContentRepositoryProvider)
      .getChapters(language: language);
  if (entries.isEmpty) {
    throw const FormatException('Bundled catalogue is unavailable. Retry local data.');
  }
  for (final entry in entries) {
    validateBundledEntry(entry);
    if (entry.language != language) {
      throw const FormatException('Bundled catalogue language is invalid.');
    }
  }
  return List.unmodifiable(entries);
});

final bundledReadingProvider = FutureProvider.autoDispose
    .family<Chapter, BundledReadingSelection>((ref, selection) async {
  // Validate before even constructing the local repository.
  final number = parseOriginalChapter(selection.chapterNumber);
  validateReadingLanguage(selection.language);
  final chapter = await ref.watch(bundledContentRepositoryProvider)
      .getChapter(number, language: selection.language);
  if (chapter == null) {
    throw const FormatException('Bundled chapter is unavailable. Retry local data.');
  }
  validateBundledEntry(chapter, requested: number);
  if (chapter.language != selection.language && chapter.language != 'mr') {
    throw const FormatException('Unexpected bundled fallback language.');
  }
  return chapter;
});

void retryBundledReading(WidgetRef ref, String language) {
  final repository = ref.read(bundledContentRepositoryProvider);
  repository.clearCache(language);
  if (language != 'mr') repository.clearCache('mr');
  ref.invalidate(bundledCatalogueProvider(language));
  ref.invalidate(bundledReadingProvider);
}