import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/language_provider.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_highlights/data/firebase_highlight_models.dart';
import '../data/firebase_reader_highlight_selection.dart';
import '../providers/firebase_assignment_reader_provider.dart';
import '../providers/firebase_reader_share_provider.dart';

class FirebaseReaderHighlightDialog extends ConsumerStatefulWidget {
  final FirebaseReaderShareBinding binding;
  final FirebaseReaderHighlightSelection selection;
  final ValueListenable<int> epoch;
  final bool Function() current;
  final Future<void> Function() freshAccess;
  const FirebaseReaderHighlightDialog({super.key, required this.binding,
      required this.selection, required this.epoch, required this.current,
      required this.freshAccess});
  @override
  ConsumerState<FirebaseReaderHighlightDialog> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<FirebaseReaderHighlightDialog> {
  final _paragraph = TextEditingController(), _comment = TextEditingController();
  int? _chapter;
  bool _started = false, _pending = false, _ack = false, _expired = false;
  String? _error;
  FirebaseHighlightsPage? _verifiedHead;
  bool get _current => mounted && !_expired && widget.current();
  @override
  void initState() {
    super.initState();
    widget.epoch.addListener(_changed);
  }
  void _changed() {
    // The originating reader may be disposing while the tree is locked.
    // Invalidate synchronously for await guards, repaint after that lifecycle.
    _expired = true;
    Future.microtask(() { if (mounted) setState(() {}); });
  }
  @override
  void dispose() {
    widget.epoch.removeListener(_changed);
    _paragraph.dispose(); _comment.dispose();
    super.dispose();
  }
  Future<void> _send() async {
    if (!_current) {
      if (mounted) setState(() => _expired = true);
      return;
    }
    if (_pending || _ack) return;
    FirebaseHighlightDraft draft;
    try {
      draft = widget.selection.draft(_chapter, _paragraph.text, _comment.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() { _pending = true; _started = true; _error = null; });
    final result = await ref.read(firebaseReaderShareProvider(widget.binding).notifier)
        .send(draft, current: () => _current, freshAccess: widget.freshAccess);
    if (!mounted) return;
    if (!widget.current()) {
      setState(() { _pending = false; _expired = true; });
      return;
    }
    setState(() {
      _pending = false;
      _ack = result == FirebaseHighlightDelivery.acknowledged;
      if (_ack) { _paragraph.clear(); _comment.clear(); _chapter = null; }
    });
  }
  Future<void> _verify() async {
    if (!_current || _pending) return;
    setState(() => _pending = true);
    final page = await ref.read(firebaseReaderShareProvider(widget.binding).notifier)
        .verifyHead(() => _current);
    if (!_current) return;
    setState(() { _pending = false; _verifiedHead = page; });
  }
  @override
  Widget build(BuildContext context) {
    // Dialog routes outlive their originating route. Independently subscribe to
    // every live identity input instead of relying on the reader repainting.
    ref.watch(firebaseSessionProvider);
    ref.watch(languageProvider);
    ref.watch(firebaseAssignmentContentProvider((
        language: widget.selection.requestedLanguage,
        unitKey: widget.binding.unitKey)));
    ref.watch(firebaseAssignmentContentProvider((
      language: widget.selection.requestedLanguage,
      unitKey: widget.binding.unitKey)).future);
    if (!_current) {
      _expired = true;
      _paragraph.clear(); _comment.clear(); _chapter = null; _verifiedHead = null;
      return AlertDialog(title: const Text('Highlight review expired.'),
          content: const Text('Account, reader content or selection changed. Select text again; nothing will be sent by this review.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]);
    }
    final state = ref.watch(firebaseReaderShareProvider(widget.binding));
    final ack = _ack || (_started && state.delivery == FirebaseHighlightDelivery.acknowledged);
    return AlertDialog(
        title: Text(ack ? 'Highlight write acknowledged.' : 'Review group highlight'),
        content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ack) const Text('The write was acknowledged. Do not resend, even if the newest-page reload fails.')
              else ...[
                Text('Group: ${widget.binding.scope.groupId} • Reading member: ${widget.binding.scope.memberUid} • Week: ${widget.binding.scope.week} • Unit: ${widget.binding.unitKey}'),
                Text('Requested language: ${widget.selection.requestedLanguage}. Selected source language: ${widget.selection.languages.join(', ')}.'),
                const Text('Exact selected quote (read-only, at most 500 UTF-16 code units):'),
                Text(widget.selection.quote, key: const Key('reader-share-quote')),
                const Text('Unverified anchor: choose the original chapter and supply a paragraph index. Displayed offsets, assembled headings and bundled source ranges do not verify original paragraph numbering, scripture or edition. Language/provenance is shown locally, not stored with the highlight.'),
                DropdownButtonFormField<int>(key: const Key('reader-share-chapter'),
                    initialValue: _chapter, isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Original chapter (required, user-supplied)'),
                    items: [for (final n in widget.selection.chapters)
                      DropdownMenuItem(value: n, child: Text('Original chapter $n'))],
                    onChanged: _pending || state.busy ? null : (n) => setState(() => _chapter = n)),
                TextField(key: const Key('reader-share-paragraph'), controller: _paragraph,
                    enabled: !_pending && !state.busy, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Paragraph index (0–2147483647, required)')),
                TextField(key: const Key('reader-share-comment'), controller: _comment,
                    enabled: !_pending && !state.busy, maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Comment (required, at most 2000 UTF-16 code units)')),
                if (state.verifyBeforeRetry) ...[
                  const Text('Sharing is blocked, including after closing/reopening this reader. Explicitly verify newest server highlights before another attempt; never automatically resend.'),
                  OutlinedButton(onPressed: _pending || state.busy ? null : _verify,
                      child: const Text('Verify newest server highlights')),
                ],
                if (_verifiedHead != null) ...[
                  const Text('Server head checked. Absence from this bounded newest page is NOT proof of non-delivery. Review for duplicates before deciding to share again.'),
                  if (_verifiedHead!.highlights.isEmpty) const Text('No highlights on this server page.'),
                  for (final row in _verifiedHead!.highlights)
                    Text('${row.senderUid} • Original chapter ${row.chapterNumber} • Paragraph ${row.paragraphIndex}\n${row.quote}\n${row.text}'),
                ],
              ],
              if (_error != null) Text(_error!, key: const Key('reader-share-validation')),
              if (state.error != null) Text(state.error!, key: const Key('reader-share-error')),
              if (_pending || state.busy) const LinearProgressIndicator(),
            ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(ack ? 'Close' : 'Cancel')),
          if (ack || state.verifyBeforeRetry) TextButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('View group highlights')),
          if (!ack) FilledButton(key: const Key('reader-share-confirm'),
              onPressed: _pending || state.busy || state.verifyBeforeRetry ? null : _send,
              child: const Text('Share highlight')),
        ]);
  }
}