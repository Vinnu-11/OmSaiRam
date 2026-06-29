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
        title: Text('${AppStrings.chapter} ${widget.chapterId}'),
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
                // Chapter label badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Chapter ${chapter.chapterLabel ?? chapter.number}',
                    style: TextStyle(
                      color: AppColors.saffron,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Chapter title
                Text(
                  chapter.title,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 22,
                        height: 1.3,
                      ),
                ),
                const SizedBox(height: 20),

                // Decorative divider
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.saffron,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.saffron.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
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

  /// Builds structured content widgets from the markdown-like chapter content.
  List<Widget> _buildContentWidgets(BuildContext context, String content) {
    final blocks = content.split('\n\n');
    final widgets = <Widget>[];
    bool inFootnotes = false;

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      // Main heading: # TITLE
      if (trimmed.startsWith('# ')) {
        // Already shown in the header, skip
        continue;
      }

      // Subtitle: _italic text_
      if (trimmed.startsWith('_') && trimmed.endsWith('_')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            trimmed.substring(1, trimmed.length - 1),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  fontSize: 15,
                  height: 1.6,
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
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.lightGrey,
                ),
              ),
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
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.lightGrey,
                ),
              ),
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

      // Footnote text (after ---)
      if (inFootnotes) {
        widgets.add(_FootnoteWidget(text: trimmed));
        continue;
      }

      // Regular paragraph
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

    return widgets;
  }
}

/// Expandable footnote widget — tap to show/hide footnote text.
class _FootnoteWidget extends StatefulWidget {
  final String text;
  const _FootnoteWidget({required this.text});

  @override
  State<_FootnoteWidget> createState() => _FootnoteWidgetState();
}

class _FootnoteWidgetState extends State<_FootnoteWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Show first ~60 chars as preview, full text when expanded
    final preview = widget.text.length > 60
        ? '${widget.text.substring(0, 60)}...'
        : widget.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.saffron.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.lightGrey),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppColors.lightText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _expanded ? widget.text : preview,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.mediumText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
