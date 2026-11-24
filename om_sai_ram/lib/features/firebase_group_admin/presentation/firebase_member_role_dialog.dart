import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../data/firebase_group_admin_models.dart';

/// Immutable confirmation identity: UID, group, member and expected/new roles.
class FirebaseMemberRoleDialog extends ConsumerWidget {
  final FirebaseGroupAdminBinding binding;
  final String targetUid;
  final FirebaseGroupRole expected, next;
  const FirebaseMemberRoleDialog({super.key, required this.binding, required this.targetUid,
    required this.expected, required this.next});
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
    return AlertDialog(title: const Text('Confirm member role change'),
      content: Text('Group: ${binding.groupId}\nTarget UID: $targetUid\n'
        '${expected.name} → ${next.name}\n'
        'No admin grants or ownership transfer. New requests use current server authority; other clients are not guaranteed a push refresh.'),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm role change'))]);
  }
}