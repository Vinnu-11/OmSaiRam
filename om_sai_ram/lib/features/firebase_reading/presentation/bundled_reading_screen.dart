import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/s.dart';
import '../../firebase_home/data/home_text.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/providers/reader_settings_provider.dart';
import '../../../core/providers/reading_progress_provider.dart';
import '../data/bundled_reading.dart';
import '../providers/bundled_reading_provider.dart';
import '../../audio/data/audio_data.dart';
import '../../audio/presentation/satcharitra_audio_screen.dart';

class BundledReadingScreen extends ConsumerStatefulWidget {
  final String? chapterNumber;
  const BundledReadingScreen({super.key, this.chapterNumber});
  @override
  ConsumerState<BundledReadingScreen> createState() => _BundledReadingScreenState();
}

class _BundledReadingScreenState extends ConsumerState<BundledReadingScreen> {
  String _query = '';
  final _search = TextEditingController();
  final _jump = TextEditingController();
  String? _jumpError;
  bool _savingBookmark = false;
  bool _savingPosition = false;
  final _scroll = ScrollController();
  (int, String)? _restoredSelection;

  void _restorePosition(int number, String language) {
    final selection = (number, language);
    if (_restoredSelection == selection) return;
    _restoredSelection = selection;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(readingProgressProvider.notifier).ready;
        if (!mounted || widget.chapterNumber != '$number' ||
            ref.read(languageProvider).readerLanguage.code != language ||
            !_scroll.hasClients) {
          return;
        }
        final saved = ref.read(readingProgressProvider);
        final position = saved.resumeChapter == number && saved.resumePosition.isFinite
            ? saved.resumePosition.clamp(0.0, 1.0).toDouble() : 0.0;
        _scroll.jumpTo(position * _scroll.position.maxScrollExtent);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved reading position could not be loaded.')));
        }
      }
    });
  }

  Future<void> _savePosition(int number) async {
    if (!_scroll.hasClients) return;
    final maximum = _scroll.position.maxScrollExtent;
    final position = maximum > 0 ? (_scroll.offset / maximum).clamp(0.0, 1.0).toDouble() : 0.0;
    setState(() => _savingPosition = true);
    try {
      await ref.read(readingProgressProvider.notifier).saveResumePosition(number, position);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reading position saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reading position could not be saved. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _savingPosition = false);
    }
  }

  @override
  void didUpdateWidget(covariant BundledReadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterNumber != widget.chapterNumber) _restoredSelection = null;
  }

  Future<void> _toggleBookmark(int number) async {
    setState(() => _savingBookmark = true);
    try {
      await ref.read(readingProgressProvider.notifier).toggleBookmark(number);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bookmark could not be saved. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _savingBookmark = false);
    }
  }
  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _jump.dispose();
    super.dispose();
  }

  void _openJump() {
    try {
      final number = parseOriginalChapter(_jump.text);
      setState(() => _jumpError = null);
      context.go('/reader/$number');
    } on FormatException catch (error) {
      setState(() => _jumpError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.chapterNumber;
    int? requested;
    if (route != null) {
      try {
        requested = parseOriginalChapter(route);
      } on FormatException {
        return Scaffold(
          appBar: AppBar(title: const Text('Read Satcharita')),
          body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Invalid original chapter link. Use numbers 1–53.'),
            TextButton(onPressed: () => context.go('/reader'),
                child: const Text('Chapter catalogue')),
          ])));
      }
    }
    final language = ref.watch(languageProvider).readerLanguage;
    final settings = ref.watch(readerSettingsProvider);
    final fontSize = settings.fontSize.isFinite
        ? settings.fontSize.clamp(minFontSize, maxFontSize).toDouble()
        : defaultFontSize;
    final selection = (language: language.code, chapterNumber: route ?? '1');
    Widget failure() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('The book could not be opened. Please try again.'),
      OutlinedButton(onPressed: () => retryBundledReading(ref, language.code),
          child: const Text('Try again')),
    ]);
    final number = requested;
    final appCode = ref.watch(languageProvider).appLanguage.code;
    final tr = S(appCode);
    final progress = ref.watch(readingProgressProvider);
    final resume = progress.resumeChapter;
    final bookmarks = progress.bookmarks
      .where((chapter) => chapter >= 1 && chapter <= 53).toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(number == null ? homeText(appCode, 'readBook') : '${tr.chapter} $number'),
        actions: [if (number != null && ref.watch(bundledReadingProvider(selection)).hasValue)
          IconButton(key: const Key('save-reading-position'),
            tooltip: 'Save reading position',
            onPressed: _savingPosition ? null : () => _savePosition(number),
            icon: const Icon(Icons.save_outlined))],
        leading: IconButton(tooltip: number == null ? 'Home' : 'All chapters',
            onPressed: () => context.go(number == null ? '/' : '/reader'),
            icon: const Icon(Icons.arrow_back))),
      body: Align(alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(key: ValueKey((route, language.code)), controller: _scroll,
            padding: const EdgeInsets.all(20), children: [
              DropdownButtonFormField<AppLanguage>(
                key: ValueKey(language), initialValue: language, isExpanded: true,
                decoration: InputDecoration(labelText: tr.language),
                items: [for (final lang in {...AppLanguage.available, language})
                  DropdownMenuItem(value: lang,
                    child: Text('${lang.label}${lang.isBeta ? ' (Beta)' : ''}'))],
                onChanged: (lang) { if (lang != null) {
                  ref.read(languageProvider.notifier).setReaderLanguage(lang);
                }}),
              const SizedBox(height: 16),
              // Jumping by number belongs to the chapter list; inside a chapter
              // the text comes first.
              if (number == null) ...[
                TextField(controller: _jump, key: const Key('original-chapter-jump'),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Go to chapter (1–53)',
                      errorText: _jumpError), onSubmitted: (_) => _openJump()),
                const SizedBox(height: 12),
              ],
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (number == null)
                  OutlinedButton(onPressed: _openJump, child: const Text('Open chapter')),
                if (number != null) ...[
                  OutlinedButton(onPressed: number > 1 ? () => context.go('/reader/${number - 1}') : null,
                    child: Text(number > 1 ? 'Previous: chapter ${number - 1}' : 'Start of book')),
                  OutlinedButton(onPressed: number < 53 ? () => context.go('/reader/${number + 1}') : null,
                    child: Text(number < 53 ? 'Next: chapter ${number + 1}' : 'End of book')),
                  IconButton(tooltip: 'Decrease reader font',
                    onPressed: fontSize > minFontSize ? () => ref.read(readerSettingsProvider.notifier).setFontSize(fontSize - 1) : null,
                    icon: const Icon(Icons.text_decrease)),
                  IconButton(tooltip: 'Increase reader font',
                    onPressed: fontSize < maxFontSize ? () => ref.read(readerSettingsProvider.notifier).setFontSize(fontSize + 1) : null,
                    icon: const Icon(Icons.text_increase)),
                ],
              ]),
              const SizedBox(height: 16),
              if (number == null) ...[
                if (resume != null && resume >= 1 && resume <= 53)
                  ListTile(key: const Key('continue-reading'),
                    leading: const Icon(Icons.history),
                    title: Text(tr.continueReading),
                    subtitle: Text('${tr.chapter} $resume'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/reader/$resume')),
                if (bookmarks.isNotEmpty) ...[
                  Text(tr.bookmarks, style: Theme.of(context).textTheme.titleMedium),
                  for (final saved in bookmarks)
                    ListTile(key: ValueKey('bookmark-$saved'),
                      leading: const Icon(Icons.bookmark),
                      title: Text('${tr.chapter} $saved'),
                      onTap: () => context.go('/reader/$saved')),
                  const Divider(),
                ],
                TextField(controller: _search, key: const Key('catalogue-search'),
                  decoration: const InputDecoration(labelText: 'Search by title or number',
                    prefixIcon: Icon(Icons.search)),
                  onChanged: (value) => setState(() => _query = value)),
                ref.watch(bundledCatalogueProvider(language.code)).when(
                  skipLoadingOnRefresh: false, skipLoadingOnReload: false,
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => failure(),
                  data: (entries) {
                    final matches = searchBundledCatalogue(entries, _query);
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (matches.isEmpty) const Text('No chapters found. Try another word or number.'),
                      for (final entry in matches)
                        ListTile(key: ValueKey('catalogue-${entry.number}'),
                          title: Text('${tr.chapter} ${entry.chapterLabel ?? entry.number}'),
                          subtitle: Text(entry.title.isEmpty ? entry.heading ?? '' : entry.title),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.go('/reader/${entry.number}')),
                    ]);
                  }),
              ] else
                ref.watch(bundledReadingProvider(selection)).when(
                  skipLoadingOnRefresh: false, skipLoadingOnReload: false,
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => failure(),
                  data: (chapter) {
                    _restorePosition(number, language.code);
                    final actual = AppLanguage.fromCode(chapter.language);
                    final rtl = const ['ur', 'sd'].contains(chapter.language);
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Align(alignment: Alignment.centerLeft,
                        child: Semantics(toggled: bookmarks.contains(number),
                          child: IconButton(
                            key: const Key('bundled-bookmark-toggle'),
                            tooltip: bookmarks.contains(number) ? 'Remove bookmark' : 'Bookmark chapter $number',
                            onPressed: _savingBookmark ? null : () => _toggleBookmark(number),
                            icon: Icon(bookmarks.contains(number) ? Icons.bookmark : Icons.bookmark_border)))),
                      if (chapter.language != language.code) ...[
                        Text('Text language: ${actual.englishLabel}', key: const Key('bundled-source-language')),
                        Text('This chapter is not available in ${language.englishLabel} yet. Showing it in Marathi.'),
                      ],
                      ReaderAudioControls(tracks: audioTracksForChapters([(chapter.language, number)])),
                      if (chapter.lastNumber > chapter.number) ...[
                        Text('This section covers chapters ${chapter.chapterLabel ?? chapter.number}.'),
                        const Text('In this language some chapters are combined, so the next chapter number may show this same text again.'),
                      ],
                      const SizedBox(height: 16),
                      Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (chapter.heading?.trim().isNotEmpty ?? false)
                            Text(chapter.heading!, style: Theme.of(context).textTheme.titleLarge),
                          if (chapter.title.trim().isNotEmpty)
                            Text(chapter.title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          SelectableText(chapter.content, key: const Key('bundled-reader-content'),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: fontSize, height: 1.8)),
                        ])),
                    ]);
                  }),
            ]))));
  }
}