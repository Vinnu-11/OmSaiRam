import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_chat/data/firebase_chat_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../data/firebase_moderation_models.dart';
import '../providers/firebase_moderation_provider.dart';

class FirebaseModerationScreen extends ConsumerWidget {
  final String groupId, messageId;
  final FirebaseModerationTargetKind kind;
  const FirebaseModerationScreen(
      {super.key,
      required this.groupId,
      required this.messageId,
      this.kind = FirebaseModerationTargetKind.messages});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      assignmentSegment(groupId);
      assignmentSegment(messageId);
    } on FormatException {
      return const Scaffold(
          body: Center(child: Text('Invalid moderation route.')));
    }
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready) {
      return const Scaffold(
          body: Center(child: Text('Ready Firebase session required.')));
    }
    final binding =
        (uid: session.user!.uid, groupId: groupId, messageId: messageId);
    return _ModerationWorkspace(
        key: ValueKey((binding, kind)), binding: binding, kind: kind);
  }
}

class _ModerationWorkspace extends ConsumerStatefulWidget {
  final FirebaseModerationBinding binding;
  final FirebaseModerationTargetKind kind;
  const _ModerationWorkspace(
      {super.key, required this.binding, required this.kind});
  @override
  ConsumerState<_ModerationWorkspace> createState() =>
      _ModerationWorkspaceState();
}

class _ModerationWorkspaceState extends ConsumerState<_ModerationWorkspace> {
  bool get _highlight => widget.kind == FirebaseModerationTargetKind.highlights;
  String get _label => _highlight ? 'highlight' : 'message';
  FirebaseModerationTargetBinding get _targetBinding =>
      (scope: widget.binding, kind: widget.kind);
  FirebaseModerationController get _controller => _highlight
      ? ref.read(firebaseTargetModerationProvider(_targetBinding).notifier)
      : ref.read(firebaseModerationProvider(widget.binding).notifier);
  bool get _current {
    if (!mounted) return false;
    final session = ref.read(firebaseSessionProvider);
    return session.ready &&
        session.user?.uid == widget.binding.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid ==
            widget.binding.uid &&
        (!_highlight ||
            ref
                    .read(firebaseModerationRoleProvider((
                      uid: widget.binding.uid,
                      groupId: widget.binding.groupId
                    )))
                    .asData
                    ?.value ==
                FirebaseGroupRole.admin);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (_current) _controller.refresh(head: true);
    });
  }

  Future<void> _remove() async {
    if (!_current) return;
    final controller = _controller;
    final reason = await showDialog<FirebaseReportReason>(
        context: context,
        builder: (_) =>
            _RemovalConfirmation(binding: widget.binding, kind: widget.kind));
    if (!_current || reason == null) return;
    await controller.remove(reason);
  }

  @override
  Widget build(BuildContext context) {
    final state = _highlight
        ? ref.watch(firebaseTargetModerationProvider(_targetBinding))
        : ref.watch(firebaseModerationProvider(widget.binding));
    final page = state.page;
    final archived = page?.archived ?? false;
    final roleBinding =
        (uid: widget.binding.uid, groupId: widget.binding.groupId);
    final role = _highlight
        ? ref.watch(firebaseModerationRoleProvider(roleBinding))
        : null;
    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back to group chat',
              onPressed: () => context.go(
                  '/groups/${Uri.encodeComponent(widget.binding.groupId)}/chat'),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: Text(
                _highlight ? 'Highlight moderation' : 'Message moderation')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Text(
                      'Group: ${widget.binding.groupId} • ${_highlight ? 'Highlight' : 'Message'}: ${widget.binding.messageId}'),
                  Text(
                      'Current group admins only. Rules independently enforce access. Resolution does not remove a $_label.'),
                  const Text(
                      'Removal cannot retract already downloaded content. Reports and the minimal audit marker are retained; this is not a retention purge or a production/compliance release.'),
                  Wrap(spacing: 12, children: [
                    OutlinedButton(
                        onPressed: state.busy
                            ? null
                            : () => _controller.refresh(head: true),
                        child: const Text('Refresh first page')),
                    OutlinedButton(
                        onPressed:
                            state.busy ? null : () => _controller.refresh(),
                        child: const Text('Retry page')),
                    if (page != null && page.hasMore(20))
                      OutlinedButton(
                          onPressed: state.busy
                              ? null
                              : () => _controller.refresh(after: page.cursor),
                          child: const Text('Next reports page')),
                  ]),
                  if (state.busy) const LinearProgressIndicator(),
                  if (state.acknowledged)
                    const Text('Moderation write acknowledged.'),
                  if (state.error != null)
                    Text(state.error!, key: const Key('moderation-error')),
                  if (_highlight &&
                      role?.asData?.value != FirebaseGroupRole.admin)
                    const Text(
                        'Current group admin membership required. Refresh to verify access.'),
                  if (page != null) ...[
                    if (page.target
                        case FirebaseModerationHighlight(:final highlight)) ...[
                      const Text(
                          'User-supplied, unverified quote, anchor and comment.'),
                      Text(
                          'Original chapter ${highlight.chapterNumber} • Paragraph index ${highlight.paragraphIndex} (user-supplied)'),
                      Text('Quote: ${highlight.quote}'),
                      Text('Comment: ${highlight.text}',
                          key: const Key('moderation-target')),
                      Text('Sender UID: ${highlight.senderUid}'),
                    ] else
                      Text(
                          page.target == null
                              ? 'Removed/unavailable'
                              : page.target!.text,
                          key: const Key('moderation-target')),
                    if (page.marker != null)
                      Text(
                          'Confirmed removal: ${page.marker!.reason.name} • Target kind: ${page.marker!.kind.name} • Moderator UID: ${page.marker!.moderatedBy} • Author UID: ${page.marker!.authorUid} • ${page.marker!.moderatedAt.toDate().toUtc()}'),
                    if (archived) const Text('Archived • Read-only'),
                    if (page.target != null)
                      OutlinedButton(
                          onPressed:
                              state.busy || archived || state.verifyBeforeRetry
                                  ? null
                                  : _remove,
                          child: Text('Remove $_label')),
                    if (page.reports.isEmpty)
                      const Text('No reports on this page.'),
                    for (final report in page.reports)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Reporter UID: ${report.reporterUid}'),
                                    Text(
                                        '${report.reason.name} • ${report.status.name} • ${report.createdAt.toDate().toUtc()}'),
                                    Text(report.details),
                                    if (report.resolvedBy != null)
                                      Text(
                                          'Handled by UID: ${report.resolvedBy} • ${report.resolvedAt!.toDate().toUtc()}'),
                                    if (report.status ==
                                        FirebaseReportStatus.open)
                                      Wrap(spacing: 12, children: [
                                        for (final status in [
                                          FirebaseReportStatus.resolved,
                                          FirebaseReportStatus.dismissed
                                        ])
                                          TextButton(
                                              onPressed: state.busy ||
                                                      archived ||
                                                      state.verifyBeforeRetry
                                                  ? null
                                                  : () => _controller.resolve(
                                                      report.reporterUid,
                                                      status),
                                              child: Text(status ==
                                                      FirebaseReportStatus
                                                          .resolved
                                                  ? 'Resolve'
                                                  : 'Dismiss')),
                                      ]),
                                  ]))),
                  ],
                ]))));
  }
}

class _RemovalConfirmation extends ConsumerStatefulWidget {
  final FirebaseModerationBinding binding;
  final FirebaseModerationTargetKind kind;
  const _RemovalConfirmation({required this.binding, required this.kind});
  @override
  ConsumerState<_RemovalConfirmation> createState() =>
      _RemovalConfirmationState();
}

class _RemovalConfirmationState extends ConsumerState<_RemovalConfirmation> {
  FirebaseReportReason _reason = FirebaseReportReason.spam;
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firebaseSessionProvider);
    final current = session.ready &&
        session.user?.uid == widget.binding.uid &&
        ref.watch(firebaseAuthGatewayProvider).currentUser?.uid ==
            widget.binding.uid &&
        (widget.kind == FirebaseModerationTargetKind.messages ||
            ref
                    .watch(firebaseModerationRoleProvider((
                      uid: widget.binding.uid,
                      groupId: widget.binding.groupId
                    )))
                    .asData
                    ?.value ==
                FirebaseGroupRole.admin);
    final label = widget.kind == FirebaseModerationTargetKind.highlights
        ? 'highlight'
        : 'message';
    return AlertDialog(
        title: Text(current
            ? 'Confirm $label removal'
            : 'Confirmation closed: account changed.'),
        content: current
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    'Permanently delete this $label with an immutable audit marker. Reports remain. The $label ID stays reserved. Downloaded copies cannot be retracted.'),
                DropdownButtonFormField<FirebaseReportReason>(
                    initialValue: _reason,
                    items: [
                      for (final reason in FirebaseReportReason.values)
                        DropdownMenuItem(
                            value: reason, child: Text(reason.name))
                    ],
                    onChanged: (reason) => setState(() => _reason = reason!)),
              ])
            : null,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          if (current)
            FilledButton(
                onPressed: () => Navigator.pop(context, _reason),
                child: const Text('Confirm removal'))
        ]);
  }
}
