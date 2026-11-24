import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../data/firebase_membership_models.dart';
import '../providers/firebase_membership_provider.dart';

/// Binding is captured when opened, never replaced by a subsequent account.
class FirebaseDepartureDialog extends ConsumerStatefulWidget {
  final FirebaseMembershipBinding binding;
  final String targetUid;
  final FirebaseDepartureReason reason;
  const FirebaseDepartureDialog({super.key, required this.binding,
    required this.targetUid, required this.reason});
  @override
  ConsumerState<FirebaseDepartureDialog> createState() => _DepartureDialogState();
}

class _DepartureDialogState extends ConsumerState<FirebaseDepartureDialog> {
  bool _confirmed = false;
  bool _allowed() {
    final session = ref.read(firebaseSessionProvider);
    final auth = ref.read(firebaseAuthGatewayProvider);
    if (!session.ready || session.user?.uid != widget.binding.uid ||
        auth.currentUser?.uid != widget.binding.uid) {
      return false;
    }
    final detail = ref.read(firebaseGroupsProvider(
      (uid: widget.binding.uid, groupId: widget.binding.groupId))).detail;
    if (detail == null || detail.group.id != widget.binding.groupId ||
        detail.self.uid != widget.binding.uid) {
      return false;
    }
    if (widget.reason == FirebaseDepartureReason.left) {
      return widget.targetUid == widget.binding.uid && canLeaveGroup(detail.group, detail.self);
    }
    final targets = detail.members.items.where((m) => m.uid == widget.targetUid);
    return targets.length == 1 && canRemoveMember(detail.group, detail.self, targets.single);
  }
  @override
  Widget build(BuildContext context) {
    ref.watch(firebaseSessionProvider);
    ref.watch(firebaseGroupsProvider((uid: widget.binding.uid, groupId: widget.binding.groupId)));
    final allowed = !_confirmed && _allowed();
    return AlertDialog(
      title: Text(allowed ? (widget.reason == FirebaseDepartureReason.left
        ? 'Confirm group leave' : 'Confirm member removal') : 'Membership confirmation unavailable'),
      content: allowed ? SingleChildScrollView(child: Text(
        'Group: ${widget.binding.groupId}\nTarget UID: ${widget.targetUid}\n\n$membershipRetentionWarning'))
        : const Text('Account, role or roster changed. Close and refresh before any action.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        if (allowed) FilledButton(onPressed: () {
          if (_confirmed || !_allowed()) return;
          _confirmed = true; // Synchronous double-confirm guard, before pop.
          Navigator.of(context).pop(true);
        }, child: const Text('Confirm departure')),
      ],
    );
  }
}