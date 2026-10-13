import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/chapter_units.dart';
import '../../../core/theme/app_colors.dart';
import '../../reader/data/chapter_model.dart';
import '../data/assignment_model.dart';
import '../data/assignments_repository.dart';
import '../data/group_model.dart';

/// Lets a group lead choose the member, reading week and individual units.
class ManualAssignmentSheet extends ConsumerStatefulWidget {
  final String groupId;
  final List<GroupMember> members;
  final int initialWeek;
  final void Function(int week, int count) onAssigned;

  const ManualAssignmentSheet({
    super.key,
    required this.groupId,
    required this.members,
    required this.initialWeek,
    required this.onAssigned,
  });

  @override
  ConsumerState<ManualAssignmentSheet> createState() =>
      _ManualAssignmentSheetState();
}

class _ManualAssignmentSheetState extends ConsumerState<ManualAssignmentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _selectedIds = <int>{};
  late final TextEditingController _weekController;
  String? _userId;
  List<Chapter> _chapters = [];
  List<Assignment> _existing = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weekController = TextEditingController(text: '${widget.initialWeek}');
    _userId = widget.members.isEmpty ? null : widget.members.first.userId;
    _load();
  }

  @override
  void dispose() {
    _weekController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = ref.read(assignmentsRepositoryProvider);
      final chapters = await repo.getAssignableChapters();
      final assignments = await repo.getGroupAssignments(widget.groupId);
      if (!mounted) return;
      setState(() { _chapters = chapters; _existing = List.of(assignments); });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load chapters. Please retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _alreadyAssigned(Chapter chapter) => _existing.any((assignment) =>
      assignment.userId == _userId &&
      assignment.weekNumber == int.tryParse(_weekController.text) &&
      ChapterUnits.start(assignment.chapterNumber ?? assignment.chapterId) ==
          chapter.number);

  String _failureMessage(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final detail = (error.response!.data as Map)['detail'];
      if (detail is String) return detail;
    }
    return 'Could not save the assignment. Please try again.';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedIds.isEmpty) return;
    final week = int.parse(_weekController.text);
    final userId = _userId!;
    final selected = _chapters.where((chapter) => _selectedIds.contains(chapter.id)).toList();
    var created = 0;
    String? failure;
    setState(() { _saving = true; _error = null; });
    try {
      final repo = ref.read(assignmentsRepositoryProvider);
      for (final chapter in selected) {
        final assignment = await repo.createAssignment(
          groupId: widget.groupId,
          userId: userId,
          chapterId: chapter.id,
          weekNumber: week,
        );
        created++;
        _existing.add(assignment);
        _selectedIds.remove(chapter.id);
      }
    } catch (error) {
      failure = _failureMessage(error);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = failure == null ? null :
          '${created == 0 ? '' : '$created assignment(s) saved. '}$failure';
    });
    if (failure == null) Navigator.pop(context);
    if (created > 0) widget.onAssigned(week, created);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final visible = _chapters.where((chapter) =>
        '${ChapterUnits.label(chapter.number)} ${chapter.title}'
            .toLowerCase().contains(_query)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: (media.size.height - media.viewInsets.bottom) * 0.88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(2)),
                  )),
                  const SizedBox(height: 16),
                  const Text('Manual Assign', style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Choose a member, week and chapters. Combined chapters count as one reading.',
                      style: TextStyle(fontSize: 12, color: AppColors.mediumText)),
                  Expanded(child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: DropdownButtonFormField<String>(
                        key: const ValueKey('manual-member'),
                        initialValue: _userId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Member',
                            border: OutlineInputBorder()),
                        items: widget.members.map((member) => DropdownMenuItem(
                          value: member.userId,
                          child: Text(member.name, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: _saving ? null : (value) => setState(() {
                          _userId = value; _selectedIds.clear(); _error = null;
                        }),
                        validator: (value) => value == null ? 'Choose a member' : null,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(
                        key: const ValueKey('manual-week'),
                        controller: _weekController,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Week',
                            border: OutlineInputBorder()),
                        validator: (value) => (int.tryParse(value ?? '') ?? 0) < 1
                            ? 'Week ≥ 1' : null,
                        onChanged: (_) => setState(() {
                          _selectedIds.clear(); _error = null;
                        }),
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      hintText: 'Search chapters', prefixIcon: Icon(Icons.search),
                      isDense: true, border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                    _loading
                      ? const SizedBox(height: 160,
                        child: Center(child: CircularProgressIndicator()))
                      : _chapters.isEmpty
                          ? Center(child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error ?? 'No chapters available to assign.'),
                                TextButton(onPressed: _load, child: const Text('Retry')),
                              ],
                            ))
                          : visible.isEmpty
                              ? const Center(child: Text('No matching chapters'))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final chapter = visible[index];
                                    final assigned = _alreadyAssigned(chapter);
                                    return CheckboxListTile(
                                      key: ValueKey('manual-chapter-${chapter.number}'),
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      activeColor: AppColors.saffron,
                                      title: Text('Chapter ${ChapterUnits.label(chapter.number)}',
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text(assigned ? 'Already assigned for this week' : chapter.title,
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                      value: _selectedIds.contains(chapter.id),
                                      onChanged: _saving || assigned ? null : (selected) => setState(() {
                                        if (selected == true) {
                                          _selectedIds.add(chapter.id);
                                        } else {
                                          _selectedIds.remove(chapter.id);
                                        }
                                        _error = null;
                                      }),
                                    );
                                  },
                                ),
                      ],
                    ),
                  )),
                  if (_error != null && _chapters.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    key: const ValueKey('manual-save'),
                    onPressed: _loading || _saving || _userId == null || _selectedIds.isEmpty
                        ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.saffron,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.assignment_add),
                    label: Text(_saving ? 'Assigning…' :
                        'Assign${_selectedIds.isEmpty ? ' chapters' : ' ${_selectedIds.length} reading(s)'}'),
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}