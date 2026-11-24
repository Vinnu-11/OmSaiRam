import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../data/firebase_group_admin_models.dart';

class FirebaseAddMemberDialog extends ConsumerStatefulWidget {
  final FirebaseGroupAdminBinding binding;
  final String initialTarget;
  const FirebaseAddMemberDialog({super.key, required this.binding, this.initialTarget = ''});
  @override
  ConsumerState<FirebaseAddMemberDialog> createState() => _FirebaseAddMemberDialogState();
}

class _FirebaseAddMemberDialogState extends ConsumerState<FirebaseAddMemberDialog> {
  late final _uid = TextEditingController(text: widget.initialTarget);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() { _uid.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(firebaseSessionProvider);
    final current = session.ready && session.user?.uid == widget.binding.uid &&
        ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == widget.binding.uid;
    if (!current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }
    return AlertDialog(title: const Text('Add member by UID'),
      content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Group: ${widget.binding.groupId}'),
          const Text('Confirm the recipient wants to join. This adds an existing Firebase profile as a member, not a lead or admin. Invitations remain available for recipient-controlled joining.'),
          TextFormField(key: const Key('add-member-uid'), controller: _uid,
            autocorrect: false, enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Firebase UID'),
            validator: (value) {
              try {
                final uid = assignmentSegment((value ?? '').trim());
                return uid == widget.binding.uid ? 'You are already a member.' : null;
              } on FormatException catch (_) { return 'Enter a valid Firebase UID.'; }
            }),
        ]))),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (_form.currentState!.validate()) Navigator.of(context).pop(_uid.text.trim());
        }, child: const Text('Confirm add member'))]);
  }
}