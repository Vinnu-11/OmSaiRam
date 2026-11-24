import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/utc_schedule_date_field.dart';
import '../../firebase_auth/data/firebase_auth_repository.dart';
import '../../firebase_auth/providers/firebase_session_provider.dart';
import '../data/firebase_assignment_models.dart';
import '../data/firestore_assignments_gateway.dart';
import '../providers/firebase_assignments_provider.dart';

typedef FirebaseAssignmentChange = ({DateTime? date, String? target});

bool _ready(WidgetRef ref, FirebaseAssignmentsScope scope) {
  final session = ref.watch(firebaseSessionProvider);
  return session.ready && session.user?.uid == scope.uid &&
      ref.watch(firebaseAuthGatewayProvider).currentUser?.uid == scope.uid;
}

Widget _close(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
  });
  return const SizedBox.shrink();
}

class FirebaseAssignmentLifecycleDialog extends ConsumerStatefulWidget {
  final FirebaseAssignmentsScope scope;
  final FirebaseAssignment baseline;
  final String action;
  final bool Function() isCurrent;
  const FirebaseAssignmentLifecycleDialog({super.key, required this.scope, required this.baseline,
    required this.action, required this.isCurrent});
  @override
  ConsumerState<FirebaseAssignmentLifecycleDialog> createState() => _LifecycleState();
}

class _LifecycleState extends ConsumerState<FirebaseAssignmentLifecycleDialog> {
  final _target = TextEditingController();
  final _form = GlobalKey<FormState>();
  DateTime? _date;
  @override
  void dispose() { _target.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!_ready(ref, widget.scope) || !widget.isCurrent()) return _close(context);
    final reassign = widget.action == 'reassign', replace = widget.action == 'replace';
    return AlertDialog(
      title: Text(reassign ? 'Reassign unit?' : replace ? 'Create fresh active version?' : 'Archive unit?'),
      content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Group: ${widget.scope.groupId}\nMember: ${widget.scope.memberUid}\nWeek: ${widget.scope.week}\nChapters: ${widget.baseline.unit.key}\nVersion: ${widget.baseline.revision}'),
          const SizedBox(height: 12),
          Text(replace ? 'Previous progress remains history-only. New active work starts as Not started.'
            : 'Current progress is retained in immutable history, not carried into new active work.'),
          if (reassign) TextFormField(key: const Key('reassignment-target'), controller: _target,
            decoration: const InputDecoration(labelText: 'New assignee UID'), validator: (value) {
              try {
                if (assignmentSegment(value?.trim() ?? '') == widget.scope.memberUid) return 'Choose a different current member.';
              } on FormatException { return 'Enter an exact current member UID.'; }
              return null;
            }),
          if (replace || reassign) UtcScheduleDateField(key: const Key('replacement-date'), label: 'New scheduled date',
            value: _date, enabled: true, isCurrent: widget.isCurrent, onChanged: (date) => setState(() => _date = date)),
          if (replace || reassign) Text(_date == null ? 'New work will be unscheduled.' : 'New date: ${_date!.toIso8601String()}'),
        ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('confirm-assignment-lifecycle'), onPressed: () {
          if (_form.currentState!.validate() && widget.isCurrent()) {
            Navigator.pop<FirebaseAssignmentChange>(context, (date: _date, target: reassign ? _target.text.trim() : null));
          }
        }, child: Text(reassign ? 'Reassign' : replace ? 'Create version' : 'Archive'))]);
  }
}

class FirebaseAssignmentHistoryDialog extends ConsumerStatefulWidget {
  final FirebaseAssignmentsScope scope;
  final FirebaseAssignment baseline;
  final bool Function() isCurrent;
  const FirebaseAssignmentHistoryDialog({super.key, required this.scope, required this.baseline, required this.isCurrent});
  @override
  ConsumerState<FirebaseAssignmentHistoryDialog> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<FirebaseAssignmentHistoryDialog> {
  final _version = TextEditingController();
  FirebaseAssignment? _row;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState(); _version.text = '${widget.baseline.revision - 1}';
    Future.microtask(_load);
  }
  bool get _current {
    if (!mounted) return false;
    final session = ref.read(firebaseSessionProvider);
    return mounted && widget.isCurrent() && session.ready && session.user?.uid == widget.scope.uid &&
        ref.read(firebaseAuthGatewayProvider).currentUser?.uid == widget.scope.uid;
  }
  Future<void> _load() async {
    if (!_current || _busy) return;
    final revision = int.tryParse(_version.text);
    setState(() { _row = null; _error = null; });
    if (revision == null || revision < 0 || revision >= widget.baseline.revision) {
      setState(() => _error = 'Enter a retained version from 0 to ${widget.baseline.revision - 1}.'); return;
    }
    setState(() => _busy = true);
    try {
      final row = await ref.read(firebaseAssignmentsGatewayProvider).version(widget.scope, widget.baseline.unit, revision);
      if (!_current) return;
      if (row.groupId != widget.scope.groupId || row.userId != widget.scope.memberUid ||
          row.weekNumber != widget.scope.week || row.unit.key != widget.baseline.unit.key || row.revision != revision) {
        throw const FormatException('Retained assignment scope mismatch.');
      }
      setState(() => _row = row);
    } catch (error) {
      if (_current) setState(() => _error = assignmentsError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  void dispose() { _version.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!_ready(ref, widget.scope) || !widget.isCurrent()) return _close(context);
    final row = _row;
    return AlertDialog(title: Text('Retained versions - ${widget.baseline.unit.key}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Group: ${widget.scope.groupId}\nMember: ${widget.scope.memberUid}\nWeek: ${widget.scope.week}'),
          Row(children: [Expanded(child: TextField(controller: _version, enabled: !_busy,
            keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Version (0-${widget.baseline.revision - 1})'))),
            IconButton(tooltip: 'Load retained version', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (row != null) SelectableText('Version: ${row.revision}\nStatus: ${row.status.label}\n'
            'Scheduled: ${row.scheduledDate?.toIso8601String() ?? 'Unscheduled'}\n'
            'Created by: ${row.createdBy}\nCreated: ${row.createdAt.toIso8601String()}\n'
            'Progress updated: ${row.progressUpdatedAt.toIso8601String()}\nHistory only - no active progress is restored.'),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]);
  }
}