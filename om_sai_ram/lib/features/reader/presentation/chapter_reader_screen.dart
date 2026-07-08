// Om Sai Ram
// Chapter reader screen — displays the full content of a single chapter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/reader_provider.dart';

/// Full-screen reader for a single Satcharita chapter.
///
/// Design priorities:
/// - Large, readable serif font for comfortable reading
/// - Generous line height and padding
/// - Clean, distraction-free layout
/// - Scroll progress indicator
/// - Chapter title at top with prev/next navigation
class ChapterReaderScreen extends ConsumerStatefulWidget {
  final int chapterId;

  const ChapterReaderScreen({super.key, required this.chapterId});

  @override
  ConsumerState<ChapterReaderScreen> createState() =>
      _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends ConsumerState<ChapterReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0) {
      setState(() {
        _scrollProgress = _scrollController.offset /
            _scrollController.position.maxScrollExtent;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapterAsync = ref.watch(chapterProvider(widget.chapterId));

    return Scaffold(
      appBar: AppBar(
        title: chapterAsync.whenData((ch) => ch).valueOrNull != null
            ? Text('${AppStrings.chapter} ${chapterAsync.value!.chapterLabel ?? chapterAsync.value!.number}')
            : Text('${AppStrings.chapter} ${widget.chapterId}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: _scrollProgress,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.saffron.withOpacity(0.7),
            ),
            minHeight: 3,
          ),
        ),
      ),
      body: chapterAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.saffron),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text(
                  'Could not load chapter',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (chapter) {
          if (chapter == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.book_outlined, size: 48, color: AppColors.lightText),
                  const SizedBox(height: 16),
                  Text(
                    'Chapter not found',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chapter label — centered, prominent
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Chapter ${chapter.chapterLabel ?? chapter.number}',
                        style: TextStyle(
                          color: AppColors.saffron,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 1.5,
                            decoration: BoxDecoration(
                              color: AppColors.saffron.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.saffron,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 32,
                            height: 1.5,
                            decoration: BoxDecoration(
                              color: AppColors.saffron.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Chapter content — structured rendering
                ..._buildContentWidgets(context, chapter.content),

                const SizedBox(height: 48),

                // Navigation buttons (prev/next chapter)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.chapterId > 1)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, __, ___) => ChapterReaderScreen(
                                  chapterId: widget.chapterId - 1,
                                ),
                                transitionsBuilder: (_, a, __, child) =>
                                    FadeTransition(opacity: a, child: child),
                                transitionDuration:
                                    const Duration(milliseconds: 200),
                              ),
                            );
                          },
                          icon: const Icon(Icons.arrow_back_ios, size: 16),
                          label: const Text('Previous'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.mediumText,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      if (widget.chapterId < ref.read(chaptersProvider).chapters.length)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, __, ___) => ChapterReaderScreen(
                                  chapterId: widget.chapterId + 1,
                                ),
                                transitionsBuilder: (_, a, __, child) =>
                                    FadeTransition(opacity: a, child: child),
                                transitionDuration:
                                    const Duration(milliseconds: 200),
                              ),
                            );
                          },
                          icon: const Text('Next'),
                          label: const Icon(Icons.arrow_forward_ios, size: 16),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.saffron,
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Parses "N. text" footnote lines after --- into a map keyed by number.
  Map<int, String> _parseFootnotes(String content) {
    final result = <int, String>{};
    if (!content.contains('---')) return result;
    final afterSep = content.substring(content.indexOf('---') + 3).trim();
    for (final line in afterSep.split('\n')) {
      final trimmed = line.trim();
      final match = RegExp(r'^(\d+)\.\s+(.+)').firstMatch(trimmed);
      if (match != null) {
        result[int.parse(match.group(1)!)] = match.group(2)!;
      }
    }
    return result;
  }

  /// Builds structured content widgets from the markdown-like chapter content.
  List<Widget> _buildContentWidgets(BuildContext context, String content) {
    final footnotes = _parseFootnotes(content);
    // One GlobalKey per footnote number — only the first occurrence gets the anchor.
    final footnoteKeys = <int, GlobalKey>{
      for (final n in footnotes.keys) n: GlobalKey(),
    };
    // Track which footnote numbers have already been assigned their anchor key.
    final usedFootnoteKeys = <int>{};

    final blocks = content.split('\n\n');
    final widgets = <Widget>[];
    bool inFootnotes = false;

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      // Main heading: # TITLE
      if (trimmed.startsWith('# ')) {
        continue;
      }

      // Subtitle: _italic text_
      if (trimmed.startsWith('_') && trimmed.endsWith('_')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Text(
            trimmed.substring(1, trimmed.length - 1),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: 15,
                  height: 1.7,
                  color: AppColors.mediumText,
                ),
          ),
        ));
        continue;
      }

      // Subheading: ## Section Title
      if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            trimmed.substring(3),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  height: 1.4,
                ),
          ),
        ));
        continue;
      }

      // Footnote separator: ---
      if (trimmed == '---') {
        inFootnotes = true;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: AppColors.lightGrey)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.lightText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Container(height: 1, color: AppColors.lightGrey)),
            ],
          ),
        ));
        continue;
      }

      // "Bow to Shri Sai" ending
      if (trimmed.contains('Bow to Shri Sai')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 16),
          child: Center(
            child: Text(
              trimmed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.saffron,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
            ),
          ),
        ));
        continue;
      }

      // Footnote definition lines (after ---)
      if (inFootnotes) {
        final match = RegExp(r'^(\d+)\.\s+(.+)').firstMatch(trimmed);
        if (match != null) {
          final num = int.parse(match.group(1)!);
          final text = match.group(2)!;
          // Only the first occurrence of a given number gets the scroll anchor key.
          final key = usedFootnoteKeys.contains(num) ? null : footnoteKeys[num];
          usedFootnoteKeys.add(num);
          widgets.add(_FootnoteEntry(key: key, number: num, text: text));
        }
        continue;
      }

      // Regular paragraph — render with tappable footnote superscripts
      if (footnotes.isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _ParagraphWithFootnoteLinks(
            text: trimmed,
            footnoteKeys: footnoteKeys,
            scrollController: _scrollController,
            context: context,
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            trimmed,
            textAlign: TextAlign.left,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.8,
                  fontSize: 17,
                ),
          ),
        ));
      }
    }

    return widgets;
  }
}

/// Renders a paragraph with inline footnote numbers as tappable superscript links.
/// Pattern matched: a word followed by a standalone number that has a footnote entry.
class _ParagraphWithFootnoteLinks extends StatelessWidget {
  final String text;
  final Map<int, GlobalKey> footnoteKeys;
  final ScrollController scrollController;
  final BuildContext context;

  const _ParagraphWithFootnoteLinks({
    required this.text,
    required this.footnoteKeys,
    required this.scrollController,
    required this.context,
  });

  void _scrollToFootnote(int number) {
    final key = footnoteKeys[number];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.2,
    );
  }

  @override
  Widget build(BuildContext ctx) {
    // Match standalone footnote numbers in text: word boundary, 1–2 digits, not part of year/larger number
    final pattern = RegExp(r'(\s)(\d{1,2})(?=[\s,;.\)]|$)');
    final spans = <InlineSpan>[];
    int last = 0;

    for (final match in pattern.allMatches(text)) {
      final num = int.tryParse(match.group(2)!);
      if (num == null || !footnoteKeys.containsKey(num)) continue;

      // Text before this match (include the leading space from group 1)
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start + 1)));
      } else {
        spans.add(TextSpan(text: match.group(1)));
      }

      // Tappable superscript
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: GestureDetector(
          onTap: () => _scrollToFootnote(num),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$num',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.saffron,
                height: 1,
              ),
            ),
          ),
        ),
      ));

      last = match.end;
    }

    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    final bodyStyle = Theme.of(ctx).textTheme.bodyLarge?.copyWith(
          height: 1.8,
          fontSize: 17,
        );

    return spans.length == 1 && spans.first is TextSpan
        ? Text(text, style: bodyStyle)
        : RichText(
            text: TextSpan(style: bodyStyle, children: spans),
          );
  }
}

/// A single footnote entry with an anchor key for scroll targeting.
class _FootnoteEntry extends StatelessWidget {
  final int number;
  final String text;

  const _FootnoteEntry({super.key, required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1, right: 10),
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.saffron,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.mediumText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
