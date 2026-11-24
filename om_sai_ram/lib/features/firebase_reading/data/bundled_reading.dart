import '../../../core/providers/language_provider.dart';
import '../../reader/data/chapter_model.dart';

/// Original Marathi chapter numbers, never SQL IDs or assignment units.
int parseOriginalChapter(String value) {
  if (!RegExp(r'^(?:[1-9]|[1-4][0-9]|5[0-3])$').hasMatch(value)) {
    throw const FormatException('Enter an original chapter number from 1 to 53.');
  }
  return int.parse(value);
}

void validateReadingLanguage(String language) {
  if (!AppLanguage.values.any((value) => value.code == language)) {
    throw const FormatException('Unknown bundled language.');
  }
}

/// Validate the asset's range literally; do not infer assignment combinations.
Chapter validateBundledEntry(Chapter chapter, {int? requested}) {
  parseOriginalChapter('${chapter.number}');
  final label = chapter.chapterLabel;
  var end = chapter.number;
  if (label != null) {
    final parts = label.split('-');
    if (parts.length > 2 || parseOriginalChapter(parts.first) != chapter.number) {
      throw const FormatException('Invalid bundled chapter range.');
    }
    end = parseOriginalChapter(parts.last);
  }
  validateReadingLanguage(chapter.language);
  if (end < chapter.number || chapter.id < 0 ||
      chapter.content.trim().isEmpty ||
      (requested != null && (requested < chapter.number || requested > end))) {
    throw const FormatException('Bundled chapter content is unavailable or invalid.');
  }
  return chapter;
}

List<Chapter> searchBundledCatalogue(List<Chapter> entries, String query) {
  final text = query.trim().toLowerCase();
  final number = int.tryParse(text);
  return entries.where((entry) => text.isEmpty ||
      (number != null && entry.covers(number)) ||
      '${entry.title} ${entry.heading ?? ''} ${entry.chapterLabel ?? entry.number}'
          .toLowerCase().contains(text)).toList();
}