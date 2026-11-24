import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../data/firebase_group_admin_models.dart';
import '../providers/firebase_group_admin_provider.dart';

class FirebaseGroupSettingsScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseGroupSettingsScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready) return const Scaffold(body: Center(child: Text('Ready Firebase session required.')));
    try { assignmentSegment(groupId); }
    on FormatException { return const Scaffold(body: Center(child: Text('Invalid group settings path.'))); }
    return _SettingsForm(key: ValueKey((session.user!.uid, groupId)),
      binding: (uid: session.user!.uid, groupId: groupId));
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final FirebaseGroupAdminBinding binding;
  const _SettingsForm({super.key, required this.binding});
  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _name = TextEditingController(), _description = TextEditingController();
  final _width = TextEditingController(), _start = TextEditingController();
  final _form = GlobalKey<FormState>();
  FirebaseGroupSettingsSnapshot? _baseline;
  String? _validationError;
  bool _loading = false;
  FirebaseGroupAdminController get _controller => ref.read(firebaseGroupAdminProvider(widget.binding).notifier);
  bool get _current {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == widget.binding.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.binding.uid;
  }
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted && _current) _load(); });
  }
  Future<void> _load() async {
    if (!_current || _loading) return;
    setState(() => _loading = true);
    await _controller.load();
    if (!mounted || !_current) return;
    final snapshot = ref.read(firebaseGroupAdminProvider(widget.binding)).snapshot;
    setState(() {
      _loading = false;
      if (snapshot == null) return;
      // Only an explicit reload (or initial load) seeds the form. Provider
      // rebuilds and background ACK reads NEVER overwrite unsaved text.
      _baseline = snapshot;
      _name.text = snapshot.group.name; _description.text = snapshot.group.description;
      _width.text = '${snapshot.group.chaptersPerWeek}'; _start.text = '${snapshot.group.startChapter}';
      _validationError = null;
    });
  }
  Future<void> _save() async {
    if (!_current || _baseline == null || !_form.currentState!.validate()) return;
    try {
      final draft = FirebaseGroupSettingsDraft(_name.text, _description.text,
        chaptersPerWeek: int.parse(_width.text), startChapter: int.parse(_start.text));
      await _controller.save(_baseline!, draft);
    } on FormatException catch (error) {
      if (mounted && _current) setState(() => _validationError = error.message);
    }
  }
  String? _number(String? value, int max) {
    final number = int.tryParse(value ?? '');
    return number == null || number < 1 || number > max ? 'Enter 1–$max.' : null;
  }
  @override
  void dispose() {
    for (final c in [_name, _description, _width, _start]) { c.dispose(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupAdminProvider(widget.binding));
    final enabled = !state.busy && !_loading && !state.acknowledged && !state.verifyBeforeRetry &&
      !(_baseline?.group.archived ?? false);
    final theme = Theme.of(context);
    return Scaffold(appBar: AppBar(title: const Text('Group settings'),
      leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () =>
        context.go('/groups/${Uri.encodeComponent(widget.binding.groupId)}'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          Text('Keep the group name and weekly reading pattern up to date.',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (state.busy || _loading) const LinearProgressIndicator(),
          if (state.acknowledged) const Text('Settings saved. Reload before making another change.', key: Key('admin-ack')),
          if (state.error != null) Text(state.error!, key: const Key('admin-error'),
            style: TextStyle(color: theme.colorScheme.error)),
          if (_validationError != null) Text(_validationError!, style: TextStyle(color: theme.colorScheme.error)),
          if (_baseline?.group.archived ?? false) const Text('Archived • Read-only'),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: state.busy || _loading ? null : _load,
            icon: const Icon(Icons.refresh), label: const Text('Reload settings (discards edits)'))),
          // Failure/pending clears authority. Keep local form values privately,
          // but do not render or allow editing under stale permissions.
          if (_baseline != null && state.snapshot != null)
            Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _SettingsSection(icon: Icons.groups_outlined, title: 'Group details', children: [
                TextFormField(key: const Key('settings-name'), controller: _name, enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Group name'),
                  validator: (v) => v == null || v.trim().isEmpty || v.trim().length > 100 ? 'Enter 1–100 characters.' : null),
                const SizedBox(height: 12),
                TextFormField(key: const Key('settings-description'), controller: _description, enabled: enabled,
                  minLines: 2, maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description', hintText: 'Optional note for group members'),
                  validator: (v) => (v?.trim().length ?? 0) > 1000 ? 'Maximum 1000 characters.' : null),
              ]),
              _SettingsSection(icon: Icons.auto_stories_outlined, title: 'Reading plan', children: [
                Text('These values are used when you create the next plan.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                if (_baseline!.group.mode == 'saptah') ...[
                  const SizedBox(height: 8),
                  const Text('Saptah is a label only and uses the same weekly planning tools as chapter-by-chapter groups.'),
                ],
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final width = TextFormField(key: const Key('settings-width'), controller: _width, enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Chapters each person reads', helperText: 'Per week, 1–48'),
                    validator: (v) => _number(v, 48));
                  final start = TextFormField(key: const Key('settings-start'), controller: _start, enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Group start chapter', helperText: 'Chapter 1–53'),
                    validator: (v) => _number(v, 53));
                  return constraints.maxWidth < 520
                    ? Column(children: [width, const SizedBox(height: 12), start])
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: width), const SizedBox(width: 12), Expanded(child: start)]);
                }),
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8)),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, size: 20), SizedBox(width: 8),
                    Expanded(child: Text('Settings do not reschedule existing assignments. Open Plan the next weeks to create future readings.')),
                  ])),
              ]),
              const SizedBox(height: 8),
              FilledButton.icon(onPressed: enabled ? _save : null,
                icon: const Icon(Icons.save_outlined), label: const Text('Save settings')),
            ])),
        ]))));
  }
}

class _SettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.icon, required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Icon(icon, size: 22), const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))]),
      const SizedBox(height: 16),
      ...children,
    ]),
  ));
}