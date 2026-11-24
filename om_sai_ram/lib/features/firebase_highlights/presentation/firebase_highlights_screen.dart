import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/presentation/group_widgets.dart';
import '../../firebase_moderation/providers/firebase_moderation_provider.dart';
import '../data/firebase_highlight_models.dart';
import '../providers/firebase_highlights_provider.dart';

class FirebaseHighlightsScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseHighlightsScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try { assignmentSegment(groupId); }
    on FormatException {
      return const Scaffold(body: Center(child: Text('Invalid group ID.')));
    }
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready) {
      return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    }
    final binding = (uid: session.user!.uid, groupId: groupId);
    return _HighlightsWorkspace(key: ValueKey(binding), binding: binding);
  }
}
class _HighlightsWorkspace extends ConsumerStatefulWidget {
  final FirebaseHighlightsBinding binding;
  const _HighlightsWorkspace({super.key, required this.binding});
  @override
  ConsumerState<_HighlightsWorkspace> createState() => _HighlightsWorkspaceState();
}
class _HighlightsWorkspaceState extends ConsumerState<_HighlightsWorkspace> {
  final _chapter = TextEditingController(), _paragraph = TextEditingController();
  final _quote = TextEditingController(), _comment = TextEditingController();
  final _form = GlobalKey<FormState>();
  FirebaseHighlightsController? _ownedController;
  FirebaseHighlightsController get _controller => ref.read(firebaseHighlightsProvider(widget.binding).notifier);
  bool get _current {
    if (!mounted) return false;
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == widget.binding.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.binding.uid;
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (_current) {
        _ownedController = _controller;
        _ownedController!.refresh(head: true);
      }
    });
  }
  @override
  void dispose() {
    _ownedController?.cancelPending();
    for (final controller in [_chapter, _paragraph, _quote, _comment]) { controller.dispose(); }
    super.dispose();
  }
  String? _number(String? value, int min, int max) {
    final number = int.tryParse(value ?? '');
    return number == null || number < min || number > max ? 'Enter an integer from $min to $max.' : null;
  }
  String? _text(String? value, String label, int maximum) {
    try { highlightText(value ?? '', label, maximum); return null; }
    on FormatException catch (error) { return error.message; }
  }
  Future<void> _send() async {
    if (!_current || !_form.currentState!.validate()) return;
    final delivery = await _controller.send(int.parse(_chapter.text), int.parse(_paragraph.text),
      _quote.text, _comment.text);
    if (!_current) return;
    if (delivery == FirebaseHighlightDelivery.acknowledged) {
      for (final controller in [_chapter, _paragraph, _quote, _comment]) { controller.clear(); }
    }
  }
  Future<void> _report(FirebaseHighlight highlight) async {
    if (!_current) return;
    final controller = _controller; // Never submit a surviving dialog as a new UID.
    await showDialog<void>(context: context, builder: (_) => _HighlightReportDialog(
      binding: widget.binding, current: () => _current,
      submit: (reason, details) => controller.report(highlight.id, reason, details)));
    if (!_current) return;
  }
  Future<void> _moderate(FirebaseHighlight highlight) async {
    if (!_current) return;
    final controller = _controller;
    await context.push<void>('/groups/${Uri.encodeComponent(widget.binding.groupId)}/highlights/${Uri.encodeComponent(highlight.id)}/moderation');
    if (!_current) return;
    ref.invalidate(firebaseModerationRoleProvider(widget.binding));
    await controller.refresh(head: true);
  }
  Future<void> _refresh({FirebaseHighlightCursor? after, bool head = false}) async {
    if (!_current) return;
    ref.invalidate(firebaseModerationRoleProvider(widget.binding));
    await _controller.refresh(after: after, head: head);
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseHighlightsProvider(widget.binding));
    final admin = ref.watch(firebaseModerationRoleProvider(widget.binding)).asData?.value == FirebaseGroupRole.admin;
    final page = state.page;
    final archived = page?.archived ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared quotes'),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/groups/${Uri.encodeComponent(widget.binding.groupId)}'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Quotes members found meaningful, newest first. Tap Refresh newest to see new ones.'),
          const Text('Quotes are typed by members and are not checked against the book.'),
          const Text('Reporting a quote tells the group admin; it does not hide it. The admin can remove quotes.'),
          Wrap(spacing: 12, children: [
            OutlinedButton(onPressed: state.busy ? null : () => _refresh(head: true), child: const Text('Refresh newest')),
            OutlinedButton(onPressed: state.busy ? null : () => _refresh(), child: const Text('Retry page')),
            if (page != null && page.hasMore(20)) OutlinedButton(
              onPressed: state.busy ? null : () => _refresh(after: page.cursor), child: const Text('Older highlights')),
          ]),
          if (state.busy) const LinearProgressIndicator(),
          if (state.error != null) Text(state.error!, key: const Key('highlights-error')),
          if (state.delivery == FirebaseHighlightDelivery.acknowledged) const Text('Highlight write acknowledged.'),
          if (page != null && page.highlights.isEmpty) const Text('No highlights on this page.'),
          if (archived) const Text('Archived • Read-only'),
          if (page != null) for (final highlight in page.highlights) Card(child: Padding(
            padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chapter ${highlight.chapterNumber} • paragraph ${highlight.paragraphIndex}'),
              Text(highlight.quote), Text(highlight.text),
              Text(groupAuthorName(ref, groupNamesKey(widget.binding.uid, widget.binding.groupId,
                page.highlights.map((h) => h.senderUid)), highlight.senderUid)),
              TextButton(onPressed: state.busy || archived ? null : () => _report(highlight), child: const Text('Report')),
              if (admin) TextButton(onPressed: state.busy ? null : () => _moderate(highlight), child: const Text('Moderate')),
            ]))),
          const Divider(),
          const Text('Share a quote'),
          Form(key: _form, child: Column(children: [
            TextFormField(key: const Key('highlight-chapter'), controller: _chapter, enabled: !state.busy && !archived,
              keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Chapter number (1–53)'),
              validator: (value) => _number(value, 1, 53)),
            TextFormField(key: const Key('highlight-paragraph'), controller: _paragraph, enabled: !state.busy && !archived,
              keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Paragraph number (0 = first paragraph)'),
              validator: (value) => _number(value, 0, 2147483647)),
            TextFormField(key: const Key('highlight-quote'), controller: _quote, enabled: !state.busy && !archived,
              maxLength: 500, maxLines: 2, decoration: const InputDecoration(labelText: 'Quote'),
              validator: (value) => _text(value, 'Quote', 500)),
            TextFormField(key: const Key('highlight-comment'), controller: _comment, enabled: !state.busy && !archived,
              maxLength: 2000, maxLines: 3, decoration: const InputDecoration(labelText: 'Comment'),
              validator: (value) => _text(value, 'Comment', 2000)),
            FilledButton(onPressed: state.busy || archived || state.verifyBeforeRetry ? null : _send, child: const Text('Share highlight')),
          ])),
        ]))),
    );
  }
}
class _HighlightReportDialog extends ConsumerStatefulWidget {
  final FirebaseHighlightsBinding binding;
  final bool Function() current;
  final Future<String?> Function(FirebaseHighlightReportReason, String) submit;
  const _HighlightReportDialog({required this.binding, required this.current, required this.submit});
  @override
  ConsumerState<_HighlightReportDialog> createState() => _HighlightReportDialogState();
}
class _HighlightReportDialogState extends ConsumerState<_HighlightReportDialog> {
  final _details = TextEditingController();
  FirebaseHighlightReportReason _reason = FirebaseHighlightReportReason.spam;
  bool _busy = false, _acknowledged = false;
  String? _error;
  @override
  void dispose() { _details.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firebaseSessionProvider);
    final current = session.ready && session.user?.uid == widget.binding.uid && widget.current();
    if (!current) {
      _details.clear(); _reason = FirebaseHighlightReportReason.spam;
      _error = null; _acknowledged = false; _busy = false;
      return AlertDialog(title: const Text('Report closed: account changed.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]);
    }
    return AlertDialog(title: Text(_acknowledged ? 'Report submitted.' : 'Report highlight'),
      content: _acknowledged ? const Text('Report write acknowledged. This does not hide or remove the highlight. Current group admins can review reports.')
        : SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<FirebaseHighlightReportReason>(initialValue: _reason,
            items: [for (final reason in FirebaseHighlightReportReason.values) DropdownMenuItem(value: reason, child: Text(reason.name))],
            onChanged: _busy ? null : (reason) => setState(() => _reason = reason!)),
          TextField(key: const Key('highlight-report-details'), controller: _details, enabled: !_busy, maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Details (optional)')),
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
        ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (!_acknowledged) FilledButton(onPressed: _busy ? null : () async {
          if (!widget.current()) return;
          setState(() { _busy = true; _error = null; });
          final error = await widget.submit(_reason, _details.text);
          if (!mounted || !widget.current()) return;
          setState(() { _busy = false; _error = error; _acknowledged = error == null; });
        }, child: const Text('Submit report')),
      ]);
  }
}