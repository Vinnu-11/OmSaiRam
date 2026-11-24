import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/providers/reader_settings_provider.dart';
import '../../../core/providers/reading_progress_provider.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../reader/data/content_repository.dart';
import '../data/firebase_reader_highlight_selection.dart';
import 'firebase_reader_highlight_dialog.dart';
import '../data/firebase_assignment_models.dart';
import '../data/firebase_assignment_resume.dart';
import '../providers/firebase_assignment_resume_provider.dart';
import '../providers/firebase_assignments_provider.dart';
import '../providers/firebase_assignment_reader_provider.dart';
import '../../audio/data/audio_data.dart';
import '../../audio/presentation/satcharitra_audio_screen.dart';

class FirebaseAssignmentReaderScreen extends ConsumerWidget {
  final String groupId, memberUid, week, unitKey;
  const FirebaseAssignmentReaderScreen(
      {super.key,
      required this.groupId,
      required this.memberUid,
      required this.week,
      required this.unitKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Validate before obtaining gateways, assignment controllers or content.
    try {
      parseFirebaseReaderRoute(groupId, memberUid, week, unitKey);
    } on FormatException {
      return const Scaffold(
          body: Center(child: Text('Invalid assignment reader link.')));
    }
    final session = ref.watch(firebaseSessionProvider);
    final sdkUid = ref.watch(firebaseAuthGatewayProvider).currentUser?.uid;
    if (!session.ready || sdkUid != session.user?.uid) {
      return const Scaffold(
          body: Center(child: Text('Ready Firebase session required.')));
    }
    final scope = (
      uid: session.user!.uid,
      groupId: groupId,
      memberUid: memberUid,
      week: int.parse(week)
    );
    return _ReaderWorkspace(
        key: ValueKey((scope, unitKey)), scope: scope, unitKey: unitKey);
  }
}

class _ReaderWorkspace extends ConsumerStatefulWidget {
  final FirebaseAssignmentsScope scope;
  final String unitKey;
  const _ReaderWorkspace(
      {super.key, required this.scope, required this.unitKey});
  @override
  ConsumerState<_ReaderWorkspace> createState() => _ReaderWorkspaceState();
}

class _ReaderWorkspaceState extends ConsumerState<_ReaderWorkspace> {
  bool _verified = false, _completing = false, _completedHere = false;
  bool _sharing = false, _composerOpen = false;
  bool _active = true;
  bool _savingBookmark = false;
  final _scroll = ScrollController();
  Object? _restoreLoad;
  int _restoreEpoch = 0;
  final _selectionEpoch = ValueNotifier<int>(0);
  FirebaseReaderHighlightSelection? _selected;
  String? _selectionError, _shareAccessError;

  void _invalidateSelection() {
    _selectionEpoch.value++;
    if (mounted && _active) setState(() { _selected = null; _selectionError = null; });
  }

  @override
  void deactivate() {
    // A dialog can repaint while this State is deactivated but still mounted.
    // Do not access WidgetRef (which looks up ancestors) in that interval.
    _active = false;
    _restoreEpoch++;
    _restoreLoad = null;
    _selectionEpoch.value++;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _restoreEpoch++;
    _scroll.dispose();
    _selectionEpoch.value++;
    if (!_composerOpen) _selectionEpoch.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final selected = _selected;
    if (!_current || _sharing || _completing || selected == null) return;
    final epoch = _selectionEpoch.value;
    final session = ref.read(firebaseSessionProvider);
    final contentKey = (language: selected.requestedLanguage, unitKey: widget.unitKey);
    final contentFuture = ref.read(firebaseAssignmentContentProvider(contentKey).future);
    bool valid() => _current && epoch == _selectionEpoch.value &&
        identical(ref.read(firebaseSessionProvider), session) &&
        ref.read(languageProvider).readerLanguage.code == selected.requestedLanguage &&
        identical(ref.read(firebaseAssignmentContentProvider(contentKey).future), contentFuture) &&
        identical(ref.read(firebaseAssignmentContentProvider(contentKey)).asData?.value,
            selected.content);
    Future<void> freshAccess() async {
      if (!valid()) throw const FormatException('Reader selection changed. Select text again.');
      final provider = firebaseAssignmentsProvider(widget.scope);
      if (ref.read(provider).busy) throw const FormatException('Assignment access is busy. Retry after it finishes.');
      await ref.read(provider.notifier).refresh();
      if (!valid()) throw const FormatException('Reader selection changed. Select text again.');
      final state = ref.read(provider);
      if (state.error != null || state.busy || _row(state) == null) {
        throw const FormatException('Fresh assignment access denied or assignment removed. Reload assignment access.');
      }
    }
    setState(() { _sharing = true; _shareAccessError = null; });
    try {
      await freshAccess();
      if (!mounted || !valid()) return;
      _composerOpen = true;
      final view = await showDialog<bool>(context: context,
          builder: (_) => FirebaseReaderHighlightDialog(
              binding: (scope: widget.scope, unitKey: widget.unitKey),
              selection: selected, epoch: _selectionEpoch,
              current: valid, freshAccess: freshAccess));
      if (!mounted || !_current) return;
      _invalidateSelection();
      if (view == true) {
        context.push('/groups/${Uri.encodeComponent(widget.scope.groupId)}/highlights');
      }
    } on FormatException catch (error) {
      if (_current) setState(() => _shareAccessError = error.message);
    } finally {
      final wasOpen = _composerOpen;
      _composerOpen = false;
      if (mounted) {
        setState(() => _sharing = false);
      } else if (wasOpen) {
        _selectionEpoch.dispose();
      }
    }
  }

  bool get _current {
    if (!mounted || !_active) return false;
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == widget.scope.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid ==
            widget.scope.uid;
  }

  FirebaseAssignment? _row(FirebaseAssignmentsState state) {
    for (final row in state.result?.assignments ?? <FirebaseAssignment>[]) {
      if (row.unit.key == widget.unitKey) return row;
    }
    return null;
  }

  Future<void> _bookmark(int number) async {
    if (!_current || _savingBookmark || !_verified) return;
    final access = ref.read(firebaseAssignmentsProvider(widget.scope));
    if (access.busy || access.error != null || _row(access) == null) return;
    setState(() => _savingBookmark = true);
    try {
      await ref.read(readingProgressProvider.notifier).toggleBookmark(number);
    } catch (_) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bookmark could not be saved. Try again.')));
      }
    } finally {
      if (_current) setState(() => _savingBookmark = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    if (!_current) return;
    _restoreEpoch++;
    _restoreLoad = null;
    _invalidateSelection();
    setState(() {
      _verified = false;
      _completedHere = false;
    });
    await ref
        .read(firebaseAssignmentsProvider(widget.scope).notifier)
        .refresh();
    if (_current) setState(() => _verified = true);
  }

  Future<void> _complete(FirebaseReaderSelection selection) async {
    if (!_current ||
        _completing ||
        !_verified ||
        widget.scope.uid != widget.scope.memberUid ||
        !ref.read(firebaseAssignmentContentProvider(selection)).hasValue) {
      return;
    }
    final controller =
        ref.read(firebaseAssignmentsProvider(widget.scope).notifier);
    FirebaseAssignmentsState currentState() =>
        ref.read(firebaseAssignmentsProvider(widget.scope));
    if (currentState().busy ||
        _row(currentState()) == null ||
        !_row(currentState())!.activeFor(currentState().result!.member) ||
        _row(currentState())!.status == FirebaseReadingStatus.completed) {
      return;
    }
    setState(() {
      _completing = true;
      _completedHere = false;
    });
    try {
      // Revalidate access/existence, then let the SDK gateway recheck permission
      // at write time. Opening/scrolling never writes progress.
      await controller.refresh();
      if (!_current ||
          _row(currentState()) == null ||
          !_row(currentState())!.activeFor(currentState().result!.member) ||
          ref.read(languageProvider).readerLanguage.code !=
              selection.language) {
        return;
      }
      if (_row(currentState())!.status != FirebaseReadingStatus.completed) {
        await controller.updateStatus(
            _row(currentState())!.unit, FirebaseReadingStatus.completed);
      }
      if (_current &&
          _row(currentState())?.status == FirebaseReadingStatus.completed) {
        setState(() => _completedHere = true);
      }
    } finally {
      if (_current) setState(() => _completing = false);
    }
  }

  void _back() {
    if (!_current) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
          '/groups/${Uri.encodeComponent(widget.scope.groupId)}/assignments'
          '?member=${Uri.encodeComponent(widget.scope.memberUid)}&week=${widget.scope.week}');
    }
  }

  bool _readable(FirebaseReaderSelection selection, Object load) {
    if (!_current || !_verified ||
        ref.read(languageProvider).readerLanguage.code != selection.language) {
      return false;
    }
    final access = ref.read(firebaseAssignmentsProvider(widget.scope));
    return !access.busy && access.error == null && _row(access) != null &&
      identical(ref.read(firebaseAssignmentContentProvider(selection).future), load) &&
      ref.read(firebaseAssignmentContentProvider(selection)).hasValue;
  }

  void _restorePosition(FirebaseReaderSelection selection) {
    final load = ref.read(firebaseAssignmentContentProvider(selection).future);
    if (identical(_restoreLoad, load)) return;
    _restoreLoad = load;
    final epoch = ++_restoreEpoch;
    final controller = ref.read(firebaseAssignmentResumeProvider(widget.scope.uid).notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.ready;
      if (epoch != _restoreEpoch || !_readable(selection, load) || !_scroll.hasClients) return;
      final saved = ref.read(firebaseAssignmentResumeProvider(widget.scope.uid)).value;
      if (saved == null || !saved.matches(widget.scope, widget.unitKey, selection.language)) return;
      _scroll.jumpTo(saved.position * _scroll.position.maxScrollExtent);
    });
  }

  Future<void> _savePosition(FirebaseReaderSelection selection) async {
    final load = ref.read(firebaseAssignmentContentProvider(selection).future);
    if (!_readable(selection, load) || !_scroll.hasClients) return;
    final maximum = _scroll.position.maxScrollExtent;
    final position = maximum > 0 ? (_scroll.offset / maximum).clamp(0.0, 1.0).toDouble() : 0.0;
    final saved = FirebaseAssignmentResume(scope: widget.scope, unitKey: widget.unitKey,
      language: selection.language, position: position);
    final acknowledged = await ref.read(firebaseAssignmentResumeProvider(widget.scope.uid).notifier).save(saved);
    if (!mounted) return;
    if (_readable(selection, load) && acknowledged) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignment reading position saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseAssignmentsProvider(widget.scope));
    final row = _verified && !state.busy && state.error == null ? _row(state) : null;
    final language = ref.watch(languageProvider).readerLanguage;
    final selection = (language: language.code, unitKey: widget.unitKey);
    ref.listen(languageProvider.select((s) => s.readerLanguage), (_, __) => _invalidateSelection());
    // Never display even local content without current server authorization.
    final content = row == null && !_sharing
        ? null
        : ref.watch(firebaseAssignmentContentProvider(selection));
    if (row != null || _sharing) {
      // Future identity is a load generation even if a repository returns the
      // identical Chapter instance on retry (Chapter equality omits content).
      ref.listen(firebaseAssignmentContentProvider(selection).future, (previous, next) {
        if (!identical(previous, next)) _invalidateSelection();
      });
    }
    final settings = ref.watch(readerSettingsProvider);
    final bookmarks = ref.watch(readingProgressProvider).bookmarks;
    final resume = ref.watch(firebaseAssignmentResumeProvider(widget.scope.uid));
    if (row != null && content?.hasValue == true) _restorePosition(selection);
    final fontSize = settings.fontSize.isFinite
        ? settings.fontSize.clamp(minFontSize, maxFontSize).toDouble()
        : defaultFontSize;
    return Scaffold(
      appBar: AppBar(
          title: Text('Original chapters ${widget.unitKey}'),
          leading: IconButton(
              tooltip: 'Back to assignments',
              onPressed: _back,
              icon: const Icon(Icons.arrow_back)),
          actions: [if (row != null && content?.hasValue == true)
            IconButton(key: const Key('assignment-save-position'),
              tooltip: 'Save assignment reading position',
              onPressed: resume.busy ? null : () => _savePosition(selection),
              icon: const Icon(Icons.save_outlined)),
          ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(controller: _scroll, padding: const EdgeInsets.all(24), children: [
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                    'Member: ${widget.scope.memberUid} • Week: ${widget.scope.week}'),
                const Text(
                    'Content is bundled locally. Assignment access requires a current server read; no offline assignment access.'),
                const Text(
                    'Reader language and font preferences are installation-wide, not account-synced.'),
                OutlinedButton(
                    onPressed: state.busy || _completing ? null : _reload,
                    child: const Text('Reload assignment access')),
                if (!_verified || state.busy) const LinearProgressIndicator(),
                if (state.error != null)
                  Text(state.error!, key: const Key('reader-access-error')),
                if (_shareAccessError != null)
                  Text(_shareAccessError!, key: const Key('reader-share-access-error')),
                if (resume.error != null) Text(resume.error!, key: const Key('assignment-resume-error')),
                if (_verified &&
                    !state.busy &&
                    state.error == null &&
                    row == null)
                  const Text(
                      'This assignment is not available for this member and week.'),
                if (row != null) ...[
                  DropdownButtonFormField<AppLanguage>(
                      key: ValueKey(language),
                      initialValue: language,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Reader language'),
                      items: [
                        for (final lang in {...AppLanguage.available, language})
                          DropdownMenuItem(
                              value: lang,
                              child: Text(
                                  '${lang.label}${lang.isBeta ? ' (Beta)' : ''}'))
                      ],
                      onChanged: _completing
                          ? null
                          : (lang) {
                              if (lang != null) {
                                ref
                                    .read(languageProvider.notifier)
                                    .setReaderLanguage(lang);
                              }
                            }),
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    IconButton(
                        tooltip: 'Decrease font size',
                        onPressed: () => ref
                            .read(readerSettingsProvider.notifier)
                            .decreaseFontSize(),
                        icon: const Icon(Icons.text_decrease)),
                    Text('Font size: ${fontSize.toStringAsFixed(0)}'),
                    IconButton(
                        tooltip: 'Increase font size',
                        onPressed: () => ref
                            .read(readerSettingsProvider.notifier)
                            .increaseFontSize(),
                        icon: const Icon(Icons.text_increase)),
                  ]),
                  Text('Status: ${row.status.label}'),
                  if (widget.scope.memberUid != widget.scope.uid)
                    const Text(
                        'Read-only reader. Only the assignee can complete this assignment, including for admins.'),
                  if (content!.isLoading) const LinearProgressIndicator(),
                  if (content.hasError) ...[
                    const Text(
                        'Bundled content is unavailable. Retry loading local content.',
                        key: Key('reader-content-error')),
                    OutlinedButton(
                        onPressed: () {
                          _invalidateSelection();
                          ref
                              .read(bundledContentRepositoryProvider)
                              .clearCache();
                          ref.invalidate(
                              firebaseAssignmentContentProvider(selection));
                        },
                        child: const Text('Retry content')),
                  ],
                  if (content.hasValue) ...[
                    Wrap(spacing: 8, children: [
                      for (var number = row.unit.start; number <= row.unit.end; number++)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('Chapter $number'),
                          IconButton(key: ValueKey('assignment-bookmark-$number'),
                            tooltip: '${bookmarks.contains(number) ? 'Remove' : 'Save'} chapter $number bookmark',
                            onPressed: _savingBookmark || state.busy ? null : () => _bookmark(number),
                            icon: Icon(bookmarks.contains(number) ? Icons.bookmark : Icons.bookmark_border)),
                        ]),
                    ]),
                    if (content.requireValue.language != language.code)
                      Text(
                          'Fallback content: ${AppLanguage.fromCode(content.requireValue.language).englishLabel} (${content.requireValue.language})'),
                    Text(content.requireValue.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    ReaderAudioControls(tracks: audioTracksForChapters([
                      for (var number = row.unit.start; number <= row.unit.end; number++)
                        (content.requireValue.sourceSegments
                            .where((segment) => number >= segment.chapterStart && number <= segment.chapterEnd)
                            .firstOrNull?.language ?? content.requireValue.language, number),
                    ])),
                    SelectableText(content.requireValue.content,
                        key: const Key('reader-content'),
                        onSelectionChanged: (range, cause) {
                          _invalidateSelection();
                          try {
                            final captured = FirebaseReaderHighlightSelection.capture(
                                content.requireValue, language.code, row.unit,
                                range.start, range.end);
                            setState(() => _selected = captured);
                          } on FormatException catch (error) {
                            if (!range.isCollapsed) setState(() => _selectionError = error.message);
                          }
                        },
                        textDirection: content.requireValue.language == 'ur' ||
                                content.requireValue.language == 'sd'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: TextStyle(fontSize: fontSize, height: 1.7)),
                      if (_selectionError != null) Text(_selectionError!, key: const Key('reader-selection-error')),
                      FilledButton.tonal(
                        key: const Key('reader-share-selected'),
                        onPressed: _sharing || _completing || state.busy || (state.result?.group.archived ?? false) ||
                            _selected == null ||
                            !identical(_selected!.content, content.requireValue) ||
                            _selected!.requestedLanguage != language.code
                          ? null : _share,
                        child: const Text('Share selected text')),
                    if (widget.scope.uid == widget.scope.memberUid)
                      FilledButton(
                          key: const Key('reader-complete'),
                          onPressed: _completing ||
                              !row.activeFor(state.result!.member) ||
                              (state.result?.group.archived ?? false) ||
                                  state.busy ||
                                  row.status == FirebaseReadingStatus.completed
                              ? null
                              : () => _complete(selection),
                          child: Text(
                              row.status == FirebaseReadingStatus.completed
                                  ? 'Already completed'
                                  : 'Mark assignment completed')),
                    if (_completedHere &&
                        row.status == FirebaseReadingStatus.completed)
                      const Text('Completion confirmed by server reload.',
                          key: Key('reader-completion-success')),
                  ],
                ],
                ]),
              ]))),
    );
  }
}
