import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/sai_quotes.dart';
import '../../../core/l10n/s.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/providers/reading_progress_provider.dart';
import '../../../core/providers/text_scale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/home_text.dart';
import 'diya_lamp.dart';

/// The first screen for everyone, signed in or not: today's teaching, one way
/// back into the book, and a large tile for each thing the app does.
class FirebaseHomeScreen extends ConsumerStatefulWidget {
  const FirebaseHomeScreen({super.key});
  @override
  ConsumerState<FirebaseHomeScreen> createState() => _FirebaseHomeScreenState();
}

class _FirebaseHomeScreenState extends ConsumerState<FirebaseHomeScreen> {
  final _diya = GlobalKey<DiyaLampState>();
  // A different teaching each day; tapping the card moves to the next one.
  int _quote =
      DateTime.now().difference(DateTime(2024)).inDays % kSaiQuotes.length;

  Future<void> _chooseLanguage() => showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
          child: SafeArea(
              child: LanguageChooser(onChosen: () => Navigator.pop(context)))));

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    if (!language.chosen) {
      return const Scaffold(body: SafeArea(child: LanguageChooser()));
    }
    final code = language.appLanguage.code;
    final tr = S(code);
    final theme = Theme.of(context);
    final session = ref.watch(firebaseSessionProvider);
    final resume = ref.watch(readingProgressProvider).resumeChapter;
    final scale = ref.watch(textScaleProvider);
    final step = TextScaleNotifier.steps.indexOf(scale);
    final quote = kSaiQuotes[_quote];

    final tiles = <_Tile>[
      _Tile('home-read', Icons.menu_book_rounded, homeText(code, 'readBook'),
          '/reader'),
      // Group reading is the reason many people install the app, so it stays
      // near the top; before sign-in the same tile leads to the sign-in page.
      if (session.ready)
        _Tile('home-groups', Icons.groups_rounded, tr.myGroups, '/groups')
      else
        _Tile(
            'home-groups-sign-in', Icons.groups_rounded, tr.myGroups, '/login'),
      _Tile('home-live', Icons.live_tv_rounded, tr.liveDarshan, '/live'),
      _Tile('home-listen', Icons.headphones_rounded, homeText(code, 'listen'),
          '/audio'),
      _Tile('home-programme', Icons.schedule_rounded, tr.dailyProgramme,
          '/daily-programme'),
      _Tile('home-events', Icons.event_rounded, tr.upcomingEvents, '/events'),
      _Tile('home-jaap', Icons.self_improvement_rounded, homeText(code, 'jaap'),
          '/jaap'),
    ];

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text('ॐ साई राम',
                            style: theme.textTheme.displayMedium
                                ?.copyWith(color: theme.colorScheme.primary)),
                        Wrap(spacing: 8, children: [
                          OutlinedButton.icon(
                              key: const Key('home-language'),
                              onPressed: _chooseLanguage,
                              icon: const Icon(Icons.language),
                              label: Text(language.appLanguage.label)),
                          Semantics(
                            label: homeText(code, 'textSize'),
                            child: OutlinedButton.icon(
                                key: const Key('home-text-size'),
                                onPressed: () => ref
                                    .read(textScaleProvider.notifier)
                                    .set(TextScaleNotifier.steps[(step + 1) %
                                        TextScaleNotifier.steps.length]),
                                icon: const Icon(Icons.text_fields),
                                label: Text(const [
                                  'A',
                                  'A+',
                                  'A++'
                                ][step < 0 ? 0 : step])),
                          ),
                          IconButton(
                            key: const Key('home-help'),
                            tooltip: homeText(code, 'help'),
                            onPressed: () => context.go('/faq'),
                            icon: const Icon(Icons.help_outline_rounded),
                          ),
                        ]),
                      ]),
                  const SizedBox(height: 16),
                  Material(
                    color: AppColors.kumkum,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('home-teaching'),
                      onTap: () {
                        setState(
                            () => _quote = (_quote + 1) % kSaiQuotes.length);
                        _diya.currentState?.light();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                DiyaLamp(key: _diya, size: 72),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Text(homeText(code, 'teaching'),
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                                color: AppColors.marigold))),
                              ]),
                              const SizedBox(height: 12),
                              Text(quote.text,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4)),
                              const SizedBox(height: 12),
                              Text(quote.source,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: AppColors.sandal)),
                              const SizedBox(height: 4),
                              Text(homeText(code, 'another'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.sandalOutline)),
                            ]),
                      ),
                    ),
                  ),
                  if (resume != null) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        key: const Key('home-continue'),
                        onPressed: () => context.go('/reader/$resume'),
                        icon: const Icon(Icons.play_arrow_rounded, size: 32),
                        label: Text(
                            '${tr.continueReading}: ${tr.chapter} $resume')),
                  ],
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, constraints) {
                    // One column when the screen is narrow or the text is very large.
                    final wide = constraints.maxWidth >= 330 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.35;
                    if (!wide) {
                      return Column(children: [
                        for (final tile in tiles)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _HomeTile(tile, wide: false)),
                      ]);
                    }
                    return Column(children: [
                      for (var i = 0; i < tiles.length; i += 2)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          // An odd last tile spans the row instead of leaving a gap.
                          child: i + 1 == tiles.length
                              ? _HomeTile(tiles[i], wide: false)
                              : IntrinsicHeight(
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                            child: _HomeTile(tiles[i],
                                                wide: true)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: _HomeTile(tiles[i + 1],
                                                wide: true)),
                                      ]),
                                ),
                        ),
                    ]);
                  }),
                  const SizedBox(height: 8),
                  if (session.busy) const LinearProgressIndicator(),
                  if (session.notice != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(session.notice!,
                            key: const Key('home-notice'))),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (session.ready) ...[
                              Text(
                                  '${homeText(code, 'namaste')}, ${session.displayName}',
                                  key: const Key('home-greeting'),
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                  key: const Key('home-account'),
                                  onPressed: () => context.go('/me'),
                                  icon: const Icon(Icons.person_outline),
                                  label: Text(homeText(code, 'account'))),
                            ] else if (session.user != null &&
                                !session.busy) ...[
                              Text(homeText(code, 'finishSetup'),
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 12),
                              FilledButton(
                                  key: const Key('home-finish-setup'),
                                  onPressed: () => context.go('/me'),
                                  child: Text(homeText(code, 'account'))),
                            ] else ...[
                              Text(homeText(code, 'signInPrompt'),
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                  key: const Key('home-sign-in'),
                                  onPressed: session.busy
                                      ? null
                                      : () => context.go('/login'),
                                  icon: const Icon(Icons.login),
                                  label: Text(tr.signIn)),
                            ],
                          ]),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}

class _Tile {
  final String key, label, route;
  final IconData icon;
  const _Tile(this.key, this.icon, this.label, this.route);
}

class _HomeTile extends StatelessWidget {
  final _Tile tile;
  final bool wide;
  const _HomeTile(this.tile, {required this.wide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
            color: AppColors.kesari.withValues(alpha: 0.14),
            shape: BoxShape.circle),
        child: Icon(tile.icon, size: 32, color: theme.colorScheme.primary));
    final label = Text(tile.label,
        textAlign: wide ? TextAlign.center : TextAlign.start,
        style: theme.textTheme.titleMedium);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key(tile.key),
        onTap: () => context.go(tile.route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  icon,
                  const SizedBox(height: 10),
                  label,
                ])
              : Row(children: [
                  icon,
                  const SizedBox(width: 16),
                  Expanded(child: label),
                  const Icon(Icons.chevron_right),
                ]),
        ),
      ),
    );
  }
}

/// Indian languages first, most widely read at the top; the rest follow.
List<AppLanguage> get _chooserOrder {
  const first = [
    AppLanguage.hindi,
    AppLanguage.marathi,
    AppLanguage.telugu,
    AppLanguage.english,
    AppLanguage.tamil,
    AppLanguage.kannada,
    AppLanguage.gujarati,
    AppLanguage.bengali,
    AppLanguage.malayalam,
    AppLanguage.oriya,
    AppLanguage.punjabi,
    AppLanguage.konkani,
    AppLanguage.nepali,
    AppLanguage.sindhi,
  ];
  final available = AppLanguage.available;
  return [
    ...first.where(available.contains),
    ...available.where((language) => !first.contains(language)),
  ];
}

/// Large buttons, each language written in its own script. Shown on first
/// open and from the language button on the home screen.
class LanguageChooser extends ConsumerWidget {
  final VoidCallback? onChosen;
  const LanguageChooser({super.key, this.onChosen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(languageProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('ॐ साई राम',
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 8),
          Text('भाषा चुनें  •  Choose your language',
              key: const Key('language-chooser'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          for (final language in _chooserOrder)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                  key: Key('language-${language.code}'),
                  style: current.chosen && current.appLanguage == language
                      ? OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: theme.colorScheme.primary, width: 3))
                      : null,
                  onPressed: () async {
                    await ref
                        .read(languageProvider.notifier)
                        .setAppLanguage(language);
                    onChosen?.call();
                  },
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                            child: Text(language.label,
                                style: theme.textTheme.titleLarge)),
                        Flexible(
                            child: Text(
                                language.isBeta
                                    ? '${language.englishLabel} (beta)'
                                    : language.englishLabel,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodyMedium)),
                      ])),
            ),
        ]),
      ),
    );
  }
}
