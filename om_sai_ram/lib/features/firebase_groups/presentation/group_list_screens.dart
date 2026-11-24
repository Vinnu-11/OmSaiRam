import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_group_models.dart';
import '../providers/firebase_groups_provider.dart';
import 'group_text.dart';
import 'group_widgets.dart';

/// `/groups`: the reader's groups plus Start and Join.
class FirebaseGroupListScreen extends StatelessWidget {
  const FirebaseGroupListScreen({super.key});
  @override
  Widget build(BuildContext context) => GroupSessionGate(builder: (uid) => _GroupList(uid: uid));
}

class _GroupList extends ConsumerStatefulWidget {
  final String uid;
  const _GroupList({required this.uid});
  @override
  ConsumerState<_GroupList> createState() => _GroupListState();
}

class _GroupListState extends ConsumerState<_GroupList> {
  FirebaseGroupsScope get _scope => (uid: widget.uid, groupId: null);
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted) ref.read(firebaseGroupsProvider(_scope).notifier).refresh(); });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupsProvider(_scope));
    final controller = ref.read(firebaseGroupsProvider(_scope).notifier);
    final groups = state.groups;
    return Scaffold(
      appBar: AppBar(title: Text(ref.gt('myGroups')),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(onRefresh: controller.refresh, child: ListView(padding: const EdgeInsets.all(20), children: [
          GroupBigButton(key: const Key('group-start'), primary: true, icon: Icons.add,
            label: ref.gt('startGroup'), onPressed: state.busy ? null : () => context.go('/groups/new')),
          GroupBigButton(key: const Key('group-join'), icon: Icons.group_add_outlined,
            label: ref.gt('joinGroup'), onPressed: state.busy ? null : () => context.go('/groups/join')),
          const SizedBox(height: 16),
          if (state.busy) const LinearProgressIndicator(),
          if (state.error != null)
            GroupErrorRetry(key: const Key('groups-error'), message: state.error!,
              onRetry: state.busy ? null : controller.refresh),
          if (groups != null && groups.items.isEmpty)
            Padding(padding: const EdgeInsets.all(8), child: Text(ref.gt('noGroups'),
              style: Theme.of(context).textTheme.titleMedium)),
          if (groups != null)
            for (final entry in groups.items)
              Card(child: ListTile(key: ValueKey('group-${entry.group.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: const Icon(Icons.groups_outlined, size: 32),
                title: Text(entry.group.name, style: Theme.of(context).textTheme.titleLarge),
                subtitle: Text([
                  ref.gt('week', {'n': entry.group.currentWeek}),
                  groupRoleText(ref, entry.self.role),
                  if (entry.group.archived) ref.gt('closed'),
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/groups/${Uri.encodeComponent(entry.group.id)}'))),
          if (groups?.hasMore ?? false)
            OutlinedButton(onPressed: state.busy ? null : () => controller.refresh(cursor: groups!.cursor),
              child: Text(ref.gt('moreGroups'))),
        ])))));
  }
}

/// After create or join: open the group and say which name members will see.
void _openGroup(BuildContext context, WidgetRef ref, String id) {
  final name = ref.read(firebaseSessionProvider).displayName?.trim() ?? '';
  if (name.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.gtr('nameShared', {'name': name}))));
  }
  context.go('/groups/${Uri.encodeComponent(id)}');
}

/// `/groups/new`.
class FirebaseCreateGroupScreen extends StatelessWidget {
  const FirebaseCreateGroupScreen({super.key});
  @override
  Widget build(BuildContext context) => GroupSessionGate(builder: (uid) => _CreateGroup(uid: uid));
}

class _CreateGroup extends ConsumerStatefulWidget {
  final String uid;
  const _CreateGroup({required this.uid});
  @override
  ConsumerState<_CreateGroup> createState() => _CreateGroupState();
}

class _CreateGroupState extends ConsumerState<_CreateGroup> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _width = TextEditingController(text: '2');
  final _start = TextEditingController(text: '1');
  String _mode = 'chapter_wise';
  FirebaseGroupsScope get _scope => (uid: widget.uid, groupId: null);

  @override
  void dispose() {
    for (final controller in [_name, _description, _width, _start]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _number(String? value, int max) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number < 1 || number > max ? ref.gtr('numberRange', {'max': max}) : null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final id = await ref.read(firebaseGroupsProvider(_scope).notifier).create(_name.text, _description.text,
      int.parse(_width.text.trim()), int.parse(_start.text.trim()), mode: _mode);
    if (mounted && id != null) _openGroup(context, ref, id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupsProvider(_scope));
    final busy = state.busy;
    return Scaffold(
      appBar: AppBar(title: Text(ref.gt('startGroup')),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/groups'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(key: const Key('create-name'), controller: _name, enabled: !busy, maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: ref.gt('groupName')),
            validator: (value) => value == null || value.trim().isEmpty ? ref.gtr('nameNeeded') : null),
          TextFormField(controller: _description, enabled: !busy, maxLength: 1000, maxLines: 2,
            decoration: InputDecoration(labelText: ref.gt('about'))),
          const SizedBox(height: 8),
          Text(ref.gt('kind'), style: Theme.of(context).textTheme.titleMedium),
          RadioGroup<String>(groupValue: _mode, onChanged: (value) { if (!busy && value != null) setState(() => _mode = value); },
            child: Column(children: [
              RadioListTile<String>(key: const Key('create-mode-chapter'), value: 'chapter_wise', title: Text(ref.gt('kindChapter'))),
              RadioListTile<String>(key: const Key('create-mode-saptah'), value: 'saptah', title: Text(ref.gt('kindSaptah'))),
            ])),
          TextFormField(key: const Key('create-width'), controller: _width, enabled: !busy, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: ref.gt('perWeek')), validator: (value) => _number(value, 48)),
          TextFormField(key: const Key('create-start'), controller: _start, enabled: !busy, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: ref.gt('startAt')), validator: (value) => _number(value, 53)),
          const SizedBox(height: 16),
          if (busy) const LinearProgressIndicator(),
          if (state.error != null) GroupErrorRetry(key: const Key('groups-error'), message: state.error!),
          GroupBigButton(key: const Key('create-submit'), primary: true, icon: Icons.check,
            label: ref.gt('createGroup'), onPressed: busy ? null : _submit),
        ])))));
  }
}

/// `/groups/join?code=`: accepts a code, an invite link or a pasted message.
class FirebaseJoinGroupScreen extends StatelessWidget {
  final String? initialCode;
  const FirebaseJoinGroupScreen({super.key, this.initialCode});
  @override
  Widget build(BuildContext context) =>
    GroupSessionGate(builder: (uid) => _JoinGroup(uid: uid, initialCode: initialCode));
}

class _JoinGroup extends ConsumerStatefulWidget {
  final String uid;
  final String? initialCode;
  const _JoinGroup({required this.uid, this.initialCode});
  @override
  ConsumerState<_JoinGroup> createState() => _JoinGroupState();
}

class _JoinGroupState extends ConsumerState<_JoinGroup> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  FirebaseGroupsScope get _scope => (uid: widget.uid, groupId: null);

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final id = await ref.read(firebaseGroupsProvider(_scope).notifier).join(_code.text);
    if (mounted && id != null) _openGroup(context, ref, id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupsProvider(_scope));
    final busy = state.busy;
    return Scaffold(
      appBar: AppBar(title: Text(ref.gt('joinGroup')),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/groups'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(ref.gt('codeHelp'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(key: const Key('join-code'), controller: _code, enabled: !busy,
            autocorrect: false, enableSuggestions: false, minLines: 1, maxLines: 4,
            textCapitalization: TextCapitalization.characters,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(labelText: ref.gt('codeLabel'), hintText: 'ABCD-EFGH'),
            validator: (value) {
              try { inviteFromText(value ?? ''); return null; }
              on FormatException catch (error) { return error.message; }
            }),
          const SizedBox(height: 16),
          if (busy) const LinearProgressIndicator(),
          if (state.error != null) GroupErrorRetry(key: const Key('groups-error'), message: state.error!),
          GroupBigButton(key: const Key('join-submit'), primary: true, icon: Icons.login,
            label: ref.gt('join'), onPressed: busy ? null : _submit),
        ])))));
  }
}
