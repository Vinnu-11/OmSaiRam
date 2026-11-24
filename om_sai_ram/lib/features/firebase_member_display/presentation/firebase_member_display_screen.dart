import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_member_display_models.dart';
import '../providers/firebase_member_display_provider.dart';

class FirebaseMemberDisplayScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseMemberDisplayScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready) return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    try { assignmentSegment(groupId); }
    on FormatException { return const Scaffold(body: Center(child: Text('Invalid group path.'))); }
    final binding = (uid: session.user!.uid, groupId: groupId);
    return _NamesWorkspace(key: ValueKey(binding), binding: binding);
  }
}

class _NamesWorkspace extends ConsumerStatefulWidget {
  final FirebaseMemberDisplayBinding binding;
  const _NamesWorkspace({super.key, required this.binding});
  @override
  ConsumerState<_NamesWorkspace> createState() => _NamesWorkspaceState();
}

class _NamesWorkspaceState extends ConsumerState<_NamesWorkspace> {
  final _name = TextEditingController(); // Explicit opt-in: never private data.
  final _form = GlobalKey<FormState>();
  bool _initialized = false, _dialogOpen = false;
  FirebaseMemberDisplayController get _controller => ref.read(firebaseMemberDisplayProvider(widget.binding).notifier);
  bool get _current {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == widget.binding.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.binding.uid;
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted && _current) _controller.load(); });
  }
  Future<void> _publish() async {
    if (!_current || _dialogOpen || !_form.currentState!.validate()) return;
    final name = _name.text.trim();
    _dialogOpen = true;
    setState(() {});
    try {
      final accepted = await showDialog<bool>(context: context, builder: (_) =>
        FirebaseMemberDisplayDialog(binding: widget.binding, name: name));
      if (accepted != true || !mounted || !_current) return;
      final acknowledged = await _controller.publish(name);
      if (!mounted || !_current) return;
      if (acknowledged) _name.text = name;
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseMemberDisplayProvider(widget.binding));
    ref.listen(firebaseMemberDisplayProvider(widget.binding), (_, next) {
      if (!_initialized && next.page != null && _current) {
        _name.text = next.page!.own?.displayName ?? '';
        _initialized = true;
      }
    });
    final page = state.page;
    final archived = page?.archived ?? false;
    final busy = state.busy || _dialogOpen;
    return Scaffold(appBar: AppBar(title: const Text('Group display names'),
      leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/groups/${Uri.encodeComponent(widget.binding.groupId)}'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(memberDisplayDisclosure),
          const Text('This is a bounded published-names directory, not the full roster. '
            'A missing page entry does not mean a member has no name. '
            'Roster, chat and highlights remain UID-only in this slice; no name snapshots are copied.'),
          Text('Your UID: ${widget.binding.uid}'),
          OutlinedButton(onPressed: busy ? null : () => _controller.load(), child: const Text('Refresh names')),
          if (state.busy) const LinearProgressIndicator(),
          if (state.acknowledged) const Text('Name write acknowledged. Refresh before another change.', key: Key('name-ack')),
          if (state.error != null) ...[
            Text(state.error!, key: const Key('names-error')),
            OutlinedButton(onPressed: busy ? null : () => _controller.load(retry: true), child: const Text('Retry names page')),
          ],
          if (page != null) Text(page.own == null ? 'You have not published a group name.' :
            'Your current published name: ${page.own!.displayName}', key: const Key('own-name')),
          Form(key: _form, child: Column(children: [
            if (archived) const Text('Archived • Read-only'),
            TextFormField(controller: _name, enabled: !busy && !archived && page != null, maxLength: 100,
              decoration: const InputDecoration(labelText: 'Your optional group-visible name'),
              validator: (value) {
                try { memberDisplayName((value ?? '').trim()); return null; }
                on FormatException catch (error) { return error.message; }
              }),
            FilledButton(onPressed: busy || archived || page == null || state.acknowledged || state.verifyBeforeRetry ? null : _publish,
              child: const Text('Publish / change name')),
          ])),
          if (page != null) ...[
            const Text('Published names on this page (unverified, not unique)'),
            if (page.names.isEmpty) const Text('No published names on this page.'),
            for (final name in page.names) ListTile(key: ValueKey('name-${name.uid}'),
              title: Text(name.displayName), subtitle: Text('UID: ${name.uid}')),
            if (page.hasMore) OutlinedButton(onPressed: busy ? null : () => _controller.load(after: page.cursor),
              child: const Text('Next names page')),
          ],
        ]))));
  }
}

/// Captured account/group/name; immediately hides and cancels on session change.
class FirebaseMemberDisplayDialog extends ConsumerWidget {
  final FirebaseMemberDisplayBinding binding;
  final String name;
  const FirebaseMemberDisplayDialog({super.key, required this.binding, required this.name});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    final current = session.ready && session.user?.uid == binding.uid &&
      ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == binding.uid;
    if (!current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context, false);
      });
      return const SizedBox.shrink();
    }
    return AlertDialog(title: const Text('Publish group-visible name?'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(memberDisplayDisclosure), Text('Group: ${binding.groupId}'),
        Text('UID: ${binding.uid}'), Text('Name: $name'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish name'))]);
  }
}