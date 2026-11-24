import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../data/firebase_assignment_models.dart';
import '../providers/firebase_assignments_provider.dart';

class FirebaseManualAssignmentDialog extends ConsumerWidget {
  final FirebaseAssignmentsScope scope;
  final FirebaseChapterUnit unit;
  final DateTime? date;
  final bool Function() isCurrent;
  const FirebaseManualAssignmentDialog({super.key, required this.scope,
    required this.unit, required this.date, required this.isCurrent});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(firebaseSessionProvider);
    var current = session.ready && session.user?.uid == scope.uid &&
      ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == scope.uid && isCurrent();
    if (current) {
      final state = ref.watch(firebaseAssignmentsProvider(scope));
      final role = state.result?.self.role;
      current = !state.busy && !state.acknowledged && !state.verifyBeforeRetry &&
        (role == FirebaseGroupRole.admin || role == FirebaseGroupRole.groupLead);
    }
    if (!current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop(false);
      });
      return const SizedBox.shrink();
    }
    return AlertDialog(title: const Text('Confirm manual assignment'),
      content: SingleChildScrollView(child: SelectableText('Group: ${scope.groupId}\n'
        'Member UID: ${scope.memberUid}\nWeek: ${scope.week}\nChapters: ${unit.key}\n'
        'Scheduled (UTC): ${date?.toIso8601String() ?? "Unscheduled"}')),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm assignment'))]);
  }
}