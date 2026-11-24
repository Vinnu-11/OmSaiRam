import '../../reader/data/chapter_model.dart';
import '../../firebase_highlights/data/firebase_highlight_models.dart';
import 'firebase_assignment_models.dart';

/// A snapshot of exact displayed text. Never infer a paragraph from its offset.
class FirebaseReaderHighlightSelection {
  final Chapter content;
  final String requestedLanguage, quote;
  final int start, end;
  final List<int> chapters;
  final List<String> languages;
  FirebaseReaderHighlightSelection._(this.content, this.requestedLanguage,
      this.start, this.end, this.quote, this.chapters, this.languages);

  factory FirebaseReaderHighlightSelection.capture(Chapter content,
      String requestedLanguage, FirebaseChapterUnit unit, int start, int end) {
    final text = content.content;
    bool splitsPair(int offset) => offset > 0 && offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF;
    if (start < 0 || start >= end || end > text.length ||
        splitsPair(start) || splitsPair(end)) {
      throw const FormatException('Select a complete, nonempty text range.');
    }
    final quote = highlightText(text.substring(start, end), 'Selected quote', 500);
    final sources = content.sourceSegments.where(
        (source) => source.start < end && source.end > start).toList();
    final chapters = <int>{};
    final languages = <String>{};
    if (content.sourceSegments.isEmpty) {
      // A single original/merged entry already declares its original range.
      // It still has no paragraph precision; an explicit anchor is required.
      chapters.addAll([for (var n = unit.start; n <= unit.end; n++)
        if (content.covers(n)) n]);
      if (chapters.isEmpty) {
        throw const FormatException('Selected source does not cover this assignment.');
      }
      languages.add(content.language);
    } else {
      var covered = start;
      for (final source in sources) {
        if (source.start > covered || source.end > text.length ||
            source.start < 0 || source.end <= source.start ||
            source.chapterStart < 1 || source.chapterEnd > 53 ||
            source.chapterStart > source.chapterEnd) {
          throw const FormatException('Selection source is unavailable. Reselect text within one source.');
        }
        if (source.end > covered) covered = source.end;
        for (var n = unit.start; n <= unit.end; n++) {
          if (n >= source.chapterStart && n <= source.chapterEnd) chapters.add(n);
        }
        languages.add(source.language);
      }
      if (covered < end || chapters.isEmpty || languages.isEmpty) {
        throw const FormatException('Selection source is unavailable. Reselect text within one source.');
      }
    }
    return FirebaseReaderHighlightSelection._(content, requestedLanguage,
        start, end, quote, List.unmodifiable(chapters.toList()..sort()),
        List.unmodifiable(languages));
  }

  FirebaseHighlightDraft draft(int? chapter, String paragraph, String comment) {
    if (chapter == null || !chapters.contains(chapter)) {
      throw const FormatException('Choose an original chapter from the selected source in this assignment.');
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(paragraph)) {
      throw const FormatException('Enter a paragraph index from 0 to 2147483647.');
    }
    final index = int.tryParse(paragraph);
    if (index == null) {
      throw const FormatException('Enter a paragraph index from 0 to 2147483647.');
    }
    return FirebaseHighlightDraft(chapter, index, quote, comment);
  }
}