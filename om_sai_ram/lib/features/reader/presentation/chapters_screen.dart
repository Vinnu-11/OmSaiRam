// Om Sai Ram
// Chapters list screen — browse all chapters of the Sai Satcharita.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/providers/reading_progress_provider.dart';
import '../providers/reader_provider.dart';

/// Displays a scrollable list of all Satcharita chapters.
///
/// Each chapter shows its number and title.
/// Tapping a chapter opens the full reader view.
/// A language toggle in the app bar lets the user switch between
/// English and Telugu for the reader independently of the app language.
class ChaptersScreen extends ConsumerStatefulWidget {
  const ChaptersScreen({super.key});

  @override
  ConsumerState<ChaptersScreen> createState() => _ChaptersScreenState();
}

class _ChaptersScreenState extends ConsumerState<ChaptersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    Future.microtask(() {
      final lang = ref.read(languageProvider).readerLanguage.code;
      ref.read(chaptersProvider.notifier).loadChapters(language: lang);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chaptersProvider);
    final readerLang = ref.watch(languageProvider).readerLanguage;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.saiSatcharita),
        actions: [
          _ReaderLanguageToggle(current: readerLang),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chapters…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(ChaptersState state) {
    if (state.isLoading && state.chapters.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.saffron),
      );
    }

    if (state.chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.saffron.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_stories_outlined,
                  size: 48,
                  color: AppColors.saffron,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Content loading...',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'The Satcharita chapters will appear here',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.lightText,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final progress = ref.watch(readingProgressProvider);
    final filtered = _searchQuery.isEmpty
        ? state.chapters
        : state.chapters
            .where((c) =>
                c.title.toLowerCase().contains(_searchQuery) ||
                '${c.number}'.contains(_searchQuery) ||
                (c.chapterLabel ?? '').toLowerCase().contains(_searchQuery))
            .toList();

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppColors.lightText),
            const SizedBox(height: 12),
            Text('No chapters match "$_searchQuery"',
                style: TextStyle(color: AppColors.lightText)),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_stories_rounded, color: AppColors.saffron, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shri Sai Satcharita',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${filtered.length} chapters · ${progress.completedChapters.length} completed',
                      style: TextStyle(color: AppColors.lightText, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Chapter list
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final chapter = filtered[index];
                final isCompleted = progress.completedChapters.contains(chapter.number);
                final isBookmarked = progress.bookmarks.contains(chapter.number);
                final isResume = progress.resumeChapter == chapter.number;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.success.withOpacity(0.04)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCompleted
                          ? AppColors.success.withOpacity(0.25)
                          : AppColors.lightGrey,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? AppColors.success.withOpacity(0.12)
                            : AppColors.saffron.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(Icons.check_rounded, color: AppColors.success, size: 20)
                            : Text(
                                chapter.chapterLabel ?? '${chapter.number}',
                                style: TextStyle(
                                  color: AppColors.saffron,
                                  fontWeight: FontWeight.w700,
                                  fontSize: (chapter.chapterLabel != null && chapter.chapterLabel!.contains('-')) ? 10 : 15,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      chapter.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: isCompleted ? AppColors.mediumText : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: isResume
                        ? Text(
                            '${(progress.resumePosition * 100).toStringAsFixed(0)}% read · tap to continue',
                            style: TextStyle(fontSize: 11, color: AppColors.saffron),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isBookmarked)
                          Icon(Icons.bookmark_rounded, color: Colors.indigo.shade300, size: 16),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, color: AppColors.lightText, size: 20),
                      ],
                    ),
                    onTap: () => context.go('/reader/${chapter.number}'),
                  ),
                );
              },
              childCount: filtered.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

/// App-bar action that toggles the reader language between English and Telugu.
class _ReaderLanguageToggle extends ConsumerWidget {
  final AppLanguage current;

  const _ReaderLanguageToggle({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showPicker(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.saffron.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.saffron.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.translate_rounded, size: 15, color: AppColors.saffron),
            const SizedBox(width: 4),
            Text(
              current.code.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.saffron,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ReaderLanguagePicker(current: current),
    );
  }
}

class _ReaderLanguagePicker extends ConsumerWidget {
  final AppLanguage current;

  const _ReaderLanguagePicker({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book_rounded,
                          color: AppColors.saffron, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Reading Language',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose the language for the Satcharita text',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.lightText),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding:
                    const EdgeInsets.fromLTRB(24, 4, 24, 32),
                children: AppLanguage.values.map((lang) {
                  final selected = current == lang;
                  return GestureDetector(
                    onTap: () async {
                      await ref
                          .read(languageProvider.notifier)
                          .setReaderLanguage(lang);
                      ref
                          .read(chaptersProvider.notifier)
                          .loadChapters(language: lang.code);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.saffron.withOpacity(0.08)
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.saffron
                              : AppColors.lightGrey,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              lang.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: selected
                                    ? AppColors.saffron
                                    : AppColors.darkText,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded,
                                color: AppColors.saffron, size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}
