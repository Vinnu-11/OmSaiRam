// Om Sai Ram
// Chapter reader screen — displays the full content of a single chapter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/reader_provider.dart';
import '../../groups/data/group_chat_repository.dart';
import '../../groups/providers/groups_provider.dart';

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
    final footnoteKeys = <int, GlobalKey>{
      for (final n in footnotes.keys) n: GlobalKey(),
    };
    final usedFootnoteKeys = <int>{};

    final blocks = content.split('\n\n');
    final widgets = <Widget>[];
    bool inFootnotes = false;
    int paragraphIndex = 0;

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('# ')) continue;

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

      if (trimmed == '---') {
        inFootnotes = true;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(child: Container(height: 1, color: AppColors.lightGrey)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Notes',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightText,
                        fontWeight: FontWeight.w500)),
              ),
              Expanded(child: Container(height: 1, color: AppColors.lightGrey)),
            ],
          ),
        ));
        continue;
      }

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

      if (inFootnotes) {
        final match = RegExp(r'^(\d+)\.\s+(.+)').firstMatch(trimmed);
        if (match != null) {
          final num = int.parse(match.group(1)!);
          final text = match.group(2)!;
          final key = usedFootnoteKeys.contains(num) ? null : footnoteKeys[num];
          usedFootnoteKeys.add(num);
          widgets.add(_FootnoteEntry(key: key, number: num, text: text));
        }
        continue;
      }

      // Regular paragraph — long-press to share as highlight
      final pIndex = paragraphIndex;
      paragraphIndex++;

      Widget textWidget;
      if (footnotes.isNotEmpty) {
        textWidget = _ParagraphWithFootnoteLinks(
          text: trimmed,
          footnoteKeys: footnoteKeys,
          scrollController: _scrollController,
          context: context,
        );
      } else {
        textWidget = Text(
          trimmed,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.8,
                fontSize: 17,
              ),
        );
      }

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(
          onLongPress: () => _showShareHighlightSheet(
            context,
            text: trimmed,
            paragraphIndex: pIndex,
            chapterId: widget.chapterId,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
            ),
            child: textWidget,
          ),
        ),
      ));
    }

    return widgets;
  }

  void _showShareHighlightSheet(
    BuildContext context, {
    required String text,
    required int paragraphIndex,
    required int chapterId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ShareHighlightSheet(
        highlightedText: text.length > 200 ? '${text.substring(0, 200)}…' : text,
        paragraphIndex: paragraphIndex,
        chapterId: chapterId,
      ),
    );
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

/// Bottom sheet that lets the user add a comment and share a highlighted verse with a group.
class _ShareHighlightSheet extends ConsumerStatefulWidget {
  final String highlightedText;
  final int paragraphIndex;
  final int chapterId;

  const _ShareHighlightSheet({
    required this.highlightedText,
    required this.paragraphIndex,
    required this.chapterId,
  });

  @override
  ConsumerState<_ShareHighlightSheet> createState() => _ShareHighlightSheetState();
}

class _ShareHighlightSheetState extends ConsumerState<_ShareHighlightSheet> {
  final TextEditingController _commentController = TextEditingController();
  String? _selectedGroupId;
  String? _selectedGroupName;
  bool _loading = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.format_quote_rounded, color: AppColors.saffron, size: 22),
              const SizedBox(width: 8),
              const Text('Share Highlight',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Long press any verse to share it with your group',
              style: TextStyle(fontSize: 12, color: AppColors.lightText)),
          const SizedBox(height: 14),
          // Highlighted text preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.saffron.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: AppColors.saffron, width: 3)),
            ),
            child: Text(
              '"${widget.highlightedText}"',
              style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.mediumText,
                  fontSize: 13,
                  height: 1.6),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 14),
          // Group picker
          if (groups.groups.isEmpty)
            Text('You are not in any group yet.',
                style: TextStyle(color: AppColors.lightText))
          else ...[
            Text('Share with:', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: groups.groups.map((g) {
                final selected = _selectedGroupId == g.id;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedGroupId = g.id;
                    _selectedGroupName = g.name;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.saffron.withOpacity(0.1)
                          : AppColors.cream,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected ? AppColors.saffron : AppColors.lightGrey),
                    ),
                    child: Text(
                      g.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color:
                              selected ? AppColors.saffron : AppColors.darkText),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          // Comment field
          TextField(
            controller: _commentController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Add your thought or reflection…',
              hintStyle: TextStyle(color: AppColors.lightText, fontSize: 14),
              filled: true,
              fillColor: AppColors.cream,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_selectedGroupId == null || _loading)
                  ? null
                  : _shareHighlight,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.saffron,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Share with Group',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareHighlight() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write your reflection first.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(groupChatRepositoryProvider).postHighlightComment(
        groupId: _selectedGroupId!,
        chapterId: widget.chapterId,
        highlightedText: widget.highlightedText,
        paragraphIndex: widget.paragraphIndex,
        comment: comment,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shared with $_selectedGroupName!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share. Please try again.')),
        );
      }
    }
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
