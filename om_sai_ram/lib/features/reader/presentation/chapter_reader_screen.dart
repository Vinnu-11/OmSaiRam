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
                // Chapter number badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${AppStrings.chapter} ${chapter.number} of 53',
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

                // Chapter content — uses serif font for readability
                Text(
                  chapter.content,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.8,
                        fontSize: 17,
                      ),
                ),

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
                      if (widget.chapterId < 53)
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
}
