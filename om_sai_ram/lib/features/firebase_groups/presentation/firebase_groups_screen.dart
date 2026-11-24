import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_membership/data/firebase_membership_models.dart';
import '../../firebase_membership/providers/firebase_membership_provider.dart';
import '../../firebase_membership/presentation/firebase_departure_dialog.dart';
import '../../firebase_membership/presentation/firebase_restore_member_dialog.dart';
import '../../firebase_group_admin/data/firebase_group_admin_models.dart';
import '../../firebase_group_admin/providers/firebase_group_admin_provider.dart';
import '../../firebase_group_admin/presentation/firebase_member_role_dialog.dart';
import '../../firebase_group_admin/presentation/firebase_add_member_dialog.dart';
import '../../firebase_member_display/data/firestore_member_display_gateway.dart';
import '../data/firebase_group_models.dart';
import '../providers/firebase_groups_provider.dart';
import 'group_text.dart';
import 'group_widgets.dart';

/// `/groups/:id/members`: roster with shared names, roles and admin actions.
/// UID-keyed inner widget destroys dialogs and drafts on account change.
class FirebaseGroupsScreen extends ConsumerWidget {
  final String groupId;
  const FirebaseGroupsScreen({super.key, required this.groupId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    if (!session.ready) {
      return const Scaffold(body: Center(child: Text('Please sign in to use groups.')));
    }
    return _GroupsWorkspace(key: ValueKey((session.user!.uid, groupId)),
        scope: (uid: session.user!.uid, groupId: groupId));
  }
}

class _GroupsWorkspace extends ConsumerStatefulWidget {
  final FirebaseGroupsScope scope;
  const _GroupsWorkspace({super.key, required this.scope});
  @override
  ConsumerState<_GroupsWorkspace> createState() => _GroupsWorkspaceState();
}

class _GroupsWorkspaceState extends ConsumerState<_GroupsWorkspace> {
  bool _roleDialogOpen = false;
  bool _addDialogOpen = false;
  bool _lifecycleDialogOpen = false;
  String _memberDraft = '';
  bool _loadingNames = false;
  FirebaseGroupDetail? _namesDetail;
  Map<String, String> _sharedNames = {};
  String? _namesError;

  Future<void> _loadNames(FirebaseGroupDetail detail) async {
    if (!_current || _loadingNames) return;
    final uids = detail.members.items.map((member) => member.uid).toList();
    bool current() => mounted && _current &&
      identical(ref.read(firebaseGroupsProvider(widget.scope)).detail, detail);
    setState(() { _loadingNames = true; _namesDetail = detail; _sharedNames = {}; _namesError = null; });
    try {
      final names = await ref.read(firebaseMemberDisplayGatewayProvider).readMembers(detail.group.id, uids);
      if (!current()) return;
      if (names.length > uids.length || names.map((name) => name.uid).toSet().length != names.length ||
          names.any((name) => name.groupId != detail.group.id || !uids.contains(name.uid))) {
        throw const FormatException('Shared name response scope mismatch.');
      }
      setState(() => _sharedNames = {for (final name in names) name.uid: name.displayName});
    } catch (_) {
      if (current()) setState(() => _namesError = 'Names could not be loaded. Pull down or tap Refresh to try again.');
    } finally {
      if (mounted) setState(() => _loadingNames = false);
    }
  }

  Future<void> _addMember() async {
    final groupId = widget.scope.groupId;
    if (groupId == null || !_current || _addDialogOpen) return;
    _addDialogOpen = true;
    try {
      final binding = (uid: widget.scope.uid, groupId: groupId);
      final target = await showDialog<String>(context: context,
        builder: (_) => FirebaseAddMemberDialog(binding: binding, initialTarget: _memberDraft));
      if (target == null || !mounted || !_current) return;
      setState(() => _memberDraft = target);
      final acknowledged = await ref.read(firebaseGroupAdminProvider(binding).notifier).addMember(target);
      if (mounted && _current && acknowledged) setState(() => _memberDraft = '');
    } finally { _addDialogOpen = false; }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  /// Reload the roster, then the names members chose to share.
  Future<void> _refresh({String? cursor}) async {
    if (!mounted || !_current) return;
    await _controller.refresh(cursor: cursor);
    final detail = mounted ? ref.read(firebaseGroupsProvider(widget.scope)).detail : null;
    if (detail != null && detail.members.items.isNotEmpty) await _loadNames(detail);
  }

  FirebaseGroupsController get _controller =>
      ref.read(firebaseGroupsProvider(widget.scope).notifier);
  bool get _current {
    final session = ref.read(firebaseSessionProvider);
    return session.ready && session.user?.uid == widget.scope.uid &&
      ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.scope.uid;
  }

  Future<void> _depart(String targetUid, FirebaseDepartureReason reason) async {
    final groupId = widget.scope.groupId;
    if (groupId == null || !_current) return;
    final binding = (uid: widget.scope.uid, groupId: groupId);
    final accepted = await showDialog<bool>(context: context,
      builder: (_) => FirebaseDepartureDialog(binding: binding, targetUid: targetUid, reason: reason));
    if (accepted != true || !mounted || !_current) return;
    final acknowledged = await ref.read(firebaseMembershipProvider(binding).notifier).depart(targetUid, reason);
    if (!mounted || !_current || !acknowledged) return;
    if (reason == FirebaseDepartureReason.left) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('You have left the group. To come back, ask the group admin.')));
      context.go('/groups');
    }
  }

  Future<void> _changeRole(FirebaseMembership member) async {
    final groupId = widget.scope.groupId;
    if (groupId == null || !_current || _roleDialogOpen) return;
    final binding = (uid: widget.scope.uid, groupId: groupId);
    final expected = member.role;
    final next = expected == FirebaseGroupRole.member ? FirebaseGroupRole.groupLead : FirebaseGroupRole.member;
    _roleDialogOpen = true;
    try {
      final accepted = await showDialog<bool>(context: context, builder: (_) =>
        FirebaseMemberRoleDialog(binding: binding, targetUid: member.uid, expected: expected, next: next));
      if (accepted != true || !mounted || !_current) return;
      await ref.read(firebaseGroupAdminProvider(binding).notifier).changeRole(member.uid, expected, next);
    } finally { _roleDialogOpen = false; }
  }

  Future<void> _changeArchive() async {
    final groupId = widget.scope.groupId;
    if (groupId == null || !_current || _lifecycleDialogOpen) return;
    _lifecycleDialogOpen = true;
    final binding = (uid: widget.scope.uid, groupId: groupId);
    try {
      final controller = ref.read(firebaseGroupAdminProvider(binding).notifier);
      await controller.load();
      if (!mounted || !_current || ModalRoute.of(context)?.isCurrent != true) return;
      final baseline = ref.read(firebaseGroupAdminProvider(binding)).snapshot;
      if (baseline == null) return;
      final accepted = await showDialog<bool>(context: context,
        builder: (_) => _GroupArchiveDialog(binding: binding, group: baseline.group));
      if (accepted != true || !mounted || !_current || ModalRoute.of(context)?.isCurrent != true) return;
      await controller.setArchived(baseline, !baseline.group.archived);
    } finally { _lifecycleDialogOpen = false; }
  }

  Future<void> _restoreMember() async {
    final groupId = widget.scope.groupId;
    if (groupId == null || !_current || _lifecycleDialogOpen) return;
    _lifecycleDialogOpen = true;
    final binding = (uid: widget.scope.uid, groupId: groupId);
    try {
      final baseline = await showDialog<FirebaseDeparture>(context: context,
        builder: (_) => FirebaseRestoreMemberDialog(binding: binding, isCurrent: () => mounted && _current));
      if (baseline == null || !mounted || !_current) return;
      await ref.read(firebaseMembershipProvider(binding).notifier).restore(baseline);
    } finally { _lifecycleDialogOpen = false; }
  }

  Future<void> _transferOwnership(FirebaseMembership successor) async {
    final groupId = widget.scope.groupId;
    if (groupId == null || !_current || _lifecycleDialogOpen) return;
    _lifecycleDialogOpen = true;
    final binding = (uid: widget.scope.uid, groupId: groupId);
    try {
      final controller = ref.read(firebaseGroupAdminProvider(binding).notifier);
      await controller.load();
      if (!mounted || !_current || ModalRoute.of(context)?.isCurrent != true) return;
      final baseline = ref.read(firebaseGroupAdminProvider(binding)).snapshot;
      if (baseline == null || baseline.group.ownerUid != binding.uid || baseline.group.archived) return;
      final accepted = await showDialog<bool>(context: context, builder: (_) => _OwnershipDialog(
        binding: binding, successor: successor, group: baseline.group));
      if (accepted != true || !mounted || !_current || ModalRoute.of(context)?.isCurrent != true) return;
      await controller.transferOwnership(baseline, successor);
    } finally { _lifecycleDialogOpen = false; }
  }

  String _name(FirebaseGroupDetail detail, FirebaseMembership member, int index) =>
    groupMemberName(ref, identical(_namesDetail, detail) ? _sharedNames : const {}, member.uid, index, widget.scope.uid);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(firebaseGroupsProvider(widget.scope));
    final detail = state.detail;
    final membershipBinding = (uid: widget.scope.uid, groupId: widget.scope.groupId!);
    final membership = ref.watch(firebaseMembershipProvider(membershipBinding));
    final admin = ref.watch(firebaseGroupAdminProvider(membershipBinding));
    final busy = state.busy || membership.busy || admin.busy;
    final groupPath = '/groups/${Uri.encodeComponent(widget.scope.groupId!)}';
    final isAdmin = detail != null && detail.self.uid == widget.scope.uid && detail.self.role == FirebaseGroupRole.admin;
    return Scaffold(
      appBar: AppBar(title: Text(ref.gt('members')),
        leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(groupPath))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          OutlinedButton.icon(onPressed: busy ? null : () async {
            await _refresh();
            if (mounted && _current && ref.read(firebaseGroupsProvider(widget.scope)).detail != null) {
              ref.read(firebaseMembershipProvider(membershipBinding).notifier).verifiedRefresh();
              ref.read(firebaseGroupAdminProvider(membershipBinding).notifier).verifiedRefresh();
            }
          }, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
          if (busy) const LinearProgressIndicator(),
          if (membership.acknowledged) const Text('Done. The member list will update when you refresh.', key: Key('departure-ack')),
          if (membership.error != null) Text(membership.error!, key: const Key('departure-error')),
          if (admin.acknowledged) const Text('Saved. Tap Refresh before making another change.', key: Key('admin-ack')),
          if (admin.error != null) Text(admin.error!, key: const Key('admin-error')),
          if (admin.verifyBeforeRetry && _memberDraft.isNotEmpty)
            SelectableText('Not yet confirmed: account $_memberDraft'),
          if (state.error != null) GroupErrorRetry(key: const Key('groups-error'), message: state.error!,
            onRetry: busy ? null : _refresh),
          if (detail != null) ...[
            Text(detail.group.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(groupRoleText(ref, detail.self.role)),
            if (detail.group.archived)
              Text(ref.gt('closed'), key: const Key('group-archived')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: busy ? null : () => context.go('$groupPath/member-names'),
              icon: const Icon(Icons.badge_outlined), label: const Text('Change the name others see')),
            if (isAdmin)
              OutlinedButton.icon(key: const Key('group-archive-action'),
                onPressed: busy || admin.acknowledged || admin.verifyBeforeRetry ? null : _changeArchive,
                icon: Icon(detail.group.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                label: Text(detail.group.archived ? 'Reopen group' : 'Close group (read only)')),
            if (isAdmin && !detail.group.archived)
              OutlinedButton.icon(key: const Key('add-member'),
                onPressed: busy || admin.acknowledged || admin.verifyBeforeRetry ? null : _addMember,
                icon: const Icon(Icons.person_add_outlined), label: const Text('Add member by account ID')),
            if (isAdmin && !detail.group.archived)
              OutlinedButton.icon(key: const Key('restore-member'),
                onPressed: busy || membership.verifyBeforeRetry ? null : _restoreMember,
                icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('Bring back a member who left')),
            if (detail.self.uid == widget.scope.uid && canLeaveGroup(detail.group, detail.self))
              OutlinedButton.icon(onPressed: busy || membership.verifyBeforeRetry ? null :
                () => _depart(widget.scope.uid, FirebaseDepartureReason.left),
                icon: const Icon(Icons.logout), label: const Text('Leave group')),
            const SizedBox(height: 16),
            if (_loadingNames) const LinearProgressIndicator(),
            if (identical(_namesDetail, detail) && _namesError != null) Text(_namesError!, key: const Key('roster-names-error')),
            if (detail.members.items.isEmpty) const Text('No members on this page.'),
            for (final (index, member) in detail.members.items.indexed)
              ListTile(key: ValueKey('member-${member.uid}'), contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline, size: 32),
                title: Text(_name(detail, member, index), style: Theme.of(context).textTheme.titleMedium),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(member.roleLabel),
                Wrap(spacing: 8, children: [
                  if (!detail.group.archived && isAdmin && detail.group.ownerUid == widget.scope.uid &&
                      member.uid != widget.scope.uid && member.role != FirebaseGroupRole.admin)
                    TextButton.icon(key: ValueKey('transfer-owner-${member.uid}'),
                      onPressed: busy || admin.acknowledged || admin.verifyBeforeRetry
                        ? null : () => _transferOwnership(member),
                      icon: const Icon(Icons.manage_accounts_outlined), label: const Text('Transfer ownership')),
                  if (detail.self.uid == widget.scope.uid && canChangeMemberRole(detail.group, detail.self, member))
                    TextButton(key: ValueKey('change-role-${member.uid}'),
                      onPressed: busy || admin.acknowledged || admin.verifyBeforeRetry ? null : () => _changeRole(member),
                      child: Text(member.role == FirebaseGroupRole.member ? 'Promote to group lead' : 'Demote to member')),
                  if (detail.self.uid == widget.scope.uid && canRemoveMember(detail.group, detail.self, member))
                    TextButton(key: ValueKey('remove-member-${member.uid}'),
                    onPressed: busy || membership.verifyBeforeRetry ? null :
                      () => _depart(member.uid, FirebaseDepartureReason.removed), child: const Text('Remove member')),
                ]),
              ])),
            if (detail.members.hasMore) OutlinedButton(
              onPressed: busy ? null : () => _refresh(cursor: detail.members.cursor),
              child: const Text('Next members page')),
          ],
        ]))),
    );
  }
}

class _OwnershipDialog extends ConsumerWidget {
  final FirebaseGroupAdminBinding binding;
  final FirebaseMembership successor;
  final FirebaseGroup group;
  const _OwnershipDialog({required this.binding, required this.successor, required this.group});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    final detail = ref.watch(firebaseGroupsProvider(binding)).detail;
    final allowed = session.ready && session.user?.uid == binding.uid &&
      ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == binding.uid &&
      detail != null && !detail.group.archived && detail.group.ownerUid == binding.uid &&
      detail.self.uid == binding.uid && detail.self.role == FirebaseGroupRole.admin &&
      detail.members.items.any((member) => member.uid == successor.uid && member.role == successor.role &&
        member.joinedAt == successor.joinedAt && member.joinedAtToken == successor.joinedAtToken);
    if (!allowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context, false);
      });
      return const SizedBox.shrink();
    }
    return AlertDialog(title: const Text('Hand over the group?'),
      content: const SingleChildScrollView(child: Text(
        'This member will run the group as its admin. You will become a group lead and can no longer '
        'change roles, settings or close the group. Only the new admin can hand it over again. '
        'All readings, progress and messages stay as they are.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const Key('confirm-ownership-transfer'), onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes, hand over'))]);
  }
}

class _GroupArchiveDialog extends ConsumerWidget {
  final FirebaseGroupAdminBinding binding;
  final FirebaseGroup group;
  const _GroupArchiveDialog({required this.binding, required this.group});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    final current = session.ready && session.user?.uid == binding.uid &&
      ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == binding.uid;
    if (!current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop(false);
      });
      return const SizedBox.shrink();
    }
    return AlertDialog(title: Text(group.archived ? 'Reopen the group?' : 'Close the group?'),
      content: SingleChildScrollView(child: Text('${group.name}\n\n'
        '${group.archived ? 'Members can read, chat and mark progress again.' : 'Members can still see everything, but nobody can add or change anything until you reopen it.'}\n'
        'Nothing is deleted.')),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton.icon(onPressed: () => Navigator.of(context).pop(true),
          icon: Icon(group.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
          label: Text(group.archived ? 'Yes, reopen' : 'Yes, close'))]);
  }
}