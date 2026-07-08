// Om Sai Ram
// Chapters list screen — browse all chapters of the Sai Satcharita.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/reader_provider.dart';

/// Displays a scrollable list of all Satcharita chapters.
///
/// Each chapter shows its number and title.
/// Tapping a chapter opens the full reader view.
class ChaptersScreen extends ConsumerStatefulWidget {
  const ChaptersScreen({super.key});

  @override
  ConsumerState<ChaptersScreen> createState() => _ChaptersScreenState();
}

class _ChaptersScreenState extends ConsumerState<ChaptersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(chaptersProvider.notifier).loadChapters());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chaptersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.saiSatcharita),
      ),
      body: _buildBody(state),
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

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.saffron.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_stories_rounded,
                    color: AppColors.saffron,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shri Sai Satcharita',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '${state.chapters.length} chapters',
                      style: TextStyle(
                        color: AppColors.lightText,
                        fontSize: 13,
                      ),
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
                final chapter = state.chapters[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.saffron.withOpacity(0.15),
                            AppColors.saffron.withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: Text(
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: AppColors.lightText,
                      size: 20,
                    ),
                    onTap: () => context.go('/reader/${chapter.number}'),
                  ),
                );
              },
              childCount: state.chapters.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}
