import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/providers/firebase_groups_provider.dart';
import '../data/firebase_membership_models.dart';
import '../data/firestore_membership_gateway.dart';
import '../providers/firebase_membership_provider.dart';

class FirebaseRestoreMemberDialog extends ConsumerStatefulWidget {
  final FirebaseMembershipBinding binding;
  final bool Function() isCurrent;
  const FirebaseRestoreMemberDialog({super.key, required this.binding, required this.isCurrent});
  @override
  ConsumerState<FirebaseRestoreMemberDialog> createState() => _RestoreState();
}

class _RestoreState extends ConsumerState<FirebaseRestoreMemberDialog> {
  final _target = TextEditingController();
  final _form = GlobalKey<FormState>();
  FirebaseDeparture? _baseline;
  String? _error;
  bool _busy = false;
  bool get _current {
    if (!mounted) return false;
    final session = ref.read(firebaseSessionProvider);
    final detail = ref.read(firebaseGroupsProvider(widget.binding)).detail;
    return mounted && widget.isCurrent() && session.ready && session.user?.uid == widget.binding.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.binding.uid &&
        detail != null && detail.group.id == widget.binding.groupId && !detail.group.archived &&
        detail.self.uid == widget.binding.uid && detail.self.role == FirebaseGroupRole.admin;
  }
  Future<void> _load() async {
    if (!_current || _busy || !_form.currentState!.validate()) return;
    final uid = _target.text.trim();
    setState(() { _busy = true; _baseline = null; _error = null; });
    try {
      final baseline = await ref.read(firebaseMembershipGatewayProvider).departure(widget.binding.groupId, uid);
      if (!_current || _target.text.trim() != uid) return;
      if (baseline.groupId != widget.binding.groupId || baseline.uid != uid || baseline.restored) {
        throw const FormatException('Departed membership scope mismatch.');
      }
      setState(() => _baseline = baseline);
    } catch (error) {
      if (_current) setState(() => _error = error is FormatException ? error.message : 'Departure unavailable. Refresh and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() { _target.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    ref.watch(firebaseSessionProvider); ref.watch(firebaseAuthGatewayProvider); ref.watch(firebaseGroupsProvider(widget.binding));
    if (!_current) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }
    final baseline = _baseline;
    return AlertDialog(title: const Text('Restore departed member'),
      content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Group: ${widget.binding.groupId}'),
          TextFormField(key: const Key('restore-member-uid'), controller: _target, enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Departed member UID'),
            onChanged: (_) => setState(() { _baseline = null; _error = null; }),
            validator: (value) { try { assignmentSegment(value?.trim() ?? ''); } on FormatException { return 'Enter an exact departed member UID.'; } return null; }),
          OutlinedButton.icon(onPressed: _busy ? null : _load, icon: const Icon(Icons.search), label: const Text('Review departure')),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (baseline != null) ...[
            Text('Target UID: ${baseline.uid}\nVersion: ${baseline.revision}\nReason: ${baseline.reason.name}\n'
              'Removed by: ${baseline.removedBy}\nRemoved: ${baseline.removedAt.toDate().toUtc().toIso8601String()}'),
            const Text('Restoration creates a fresh ordinary membership and discovery entry. Old assignments and progress remain history-only. '
              'No former role or shared name is restored. New active work needs an explicit fresh assignment version.'),
          ],
        ]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('confirm-member-restoration'), onPressed: baseline == null || _busy ? null : () {
          if (_current && _target.text.trim() == baseline.uid) Navigator.pop(context, baseline);
        }, child: const Text('Confirm restoration'))]);
  }
}