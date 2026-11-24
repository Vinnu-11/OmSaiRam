import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/presentation/group_widgets.dart';
import '../../firebase_moderation/providers/firebase_moderation_provider.dart';
import '../data/firebase_chat_models.dart';
import '../providers/firebase_chat_provider.dart';

class FirebaseChatScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseChatScreen({super.key, required this.groupId});
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
    return _ChatWorkspace(key: ValueKey(binding), binding: binding);
  }
}

class _ChatWorkspace extends ConsumerStatefulWidget {
  final FirebaseChatBinding binding;
  const _ChatWorkspace({super.key, required this.binding});
  @override
  ConsumerState<_ChatWorkspace> createState() => _ChatWorkspaceState();
}

class _ChatWorkspaceState extends ConsumerState<_ChatWorkspace> {
  final _draft = TextEditingController();
  FirebaseChatController? _ownedController;
  FirebaseChatController get _controller => ref.read(firebaseChatProvider(widget.binding).notifier);
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
    _draft.dispose();
    super.dispose();
  }
  Future<void> _send() async {
    if (!_current) return;
    final delivery = await _controller.send(_draft.text);
    if (_current && delivery == FirebaseChatDelivery.acknowledged) _draft.clear();
  }
  Future<void> _report(FirebaseChatMessage message) async {
    if (!_current) return;
    // Capture the old controller and UID. A dialog cannot submit as a new account.
    final controller = _controller;
    await showDialog<void>(context: context, builder: (_) => _ReportDialog(
      binding: widget.binding, current: () => _current,
      submit: (reason, details) => controller.report(message.id, reason, details)));
  }
  Future<void> _moderate(FirebaseChatMessage message) async {
    if (!_current) return;
    final controller = _controller;
    await context.push<void>('/groups/${Uri.encodeComponent(widget.binding.groupId)}/moderation/${Uri.encodeComponent(message.id)}');
    if (!_current) return;
    ref.invalidate(firebaseModerationRoleProvider(widget.binding));
    await controller.refresh(head: true); // Clear old cards before reading server head.
  }
  Future<void> _refresh({FirebaseChatCursor? after, bool head = false}) async {
    if (!_current) return;
    ref.invalidate(firebaseModerationRoleProvider(widget.binding));
    await _controller.refresh(after: after, head: head);
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseChatProvider(widget.binding));
    final admin = ref.watch(firebaseModerationRoleProvider(widget.binding)).asData?.value == FirebaseGroupRole.admin;
    final page = state.page;
    final archived = page?.archived ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Group chat'),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/groups/${Uri.encodeComponent(widget.binding.groupId)}'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Newest messages first. Tap Refresh newest to see new messages.'),
          const Text('Reporting a message tells the group admin; it does not hide it. The admin can remove messages.'),
          Wrap(spacing: 12, children: [
            OutlinedButton(onPressed: state.busy ? null : () => _refresh(head: true), child: const Text('Refresh newest')),
            OutlinedButton(onPressed: state.busy ? null : () => _refresh(), child: const Text('Retry page')),
            if (page != null && page.hasMore(20)) OutlinedButton(
              onPressed: state.busy ? null : () => _refresh(after: page.cursor), child: const Text('Older messages')),
          ]),
          if (state.busy) const LinearProgressIndicator(),
          if (state.error != null) Text(state.error!, key: const Key('chat-error')),
          if (state.delivery == FirebaseChatDelivery.acknowledged) const Text('Message sent.'),
          if (page != null && page.messages.isEmpty) const Text('No messages on this page.'),
          if (archived) const Text('Archived • Read-only'),
          if (page != null) for (final message in page.messages) ListTile(
            title: Text(message.text), subtitle: Text(groupAuthorName(ref, groupNamesKey(widget.binding.uid,
              widget.binding.groupId, page.messages.map((m) => m.senderUid)), message.senderUid)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: state.busy || archived ? null : () => _report(message), child: const Text('Report')),
              if (admin) TextButton(onPressed: state.busy ? null : () => _moderate(message), child: const Text('Moderate')),
            ])),
          TextField(key: const Key('chat-draft'), controller: _draft, enabled: !state.busy && !archived,
            maxLength: 2000, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
          FilledButton(onPressed: state.busy || archived || state.verifyBeforeRetry ? null : _send, child: const Text('Send')),
        ]))),
    );
  }
}

class _ReportDialog extends ConsumerStatefulWidget {
  final FirebaseChatBinding binding;
  final bool Function() current;
  final Future<String?> Function(FirebaseReportReason, String) submit;
  const _ReportDialog({required this.binding, required this.current, required this.submit});
  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}
class _ReportDialogState extends ConsumerState<_ReportDialog> {
  final _details = TextEditingController();
  FirebaseReportReason _reason = FirebaseReportReason.spam;
  bool _busy = false, _acknowledged = false;
  String? _error;
  @override
  void dispose() { _details.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firebaseSessionProvider);
    final current = session.ready && session.user?.uid == widget.binding.uid && widget.current();
    if (!current) {
      // Erase old-account form contents even though the modal route survives.
      _details.clear();
      return AlertDialog(title: const Text('Report closed: account changed.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]);
    }
    return AlertDialog(title: Text(_acknowledged ? 'Report submitted.' : 'Report message'),
      content: _acknowledged ? const Text('Report write acknowledged. This does not hide or remove the message.') :
        Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<FirebaseReportReason>(initialValue: _reason,
            items: [for (final reason in FirebaseReportReason.values) DropdownMenuItem(value: reason, child: Text(reason.name))],
            onChanged: _busy ? null : (reason) => setState(() => _reason = reason!)),
          TextField(key: const Key('report-details'), controller: _details, enabled: !_busy, maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Details (optional)')),
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
        ]),
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