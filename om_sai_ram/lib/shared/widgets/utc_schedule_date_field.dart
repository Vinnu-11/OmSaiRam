import 'package:flutter/material.dart';
import '../../core/utils/utc_schedule_date.dart';

class UtcScheduleDateField extends StatefulWidget {
  final String label;
  final DateTime? value;
  final bool enabled;
  final bool Function() isCurrent;
  final ValueChanged<DateTime?> onChanged;
  const UtcScheduleDateField({super.key, required this.label, required this.value,
    required this.enabled, required this.isCurrent, required this.onChanged});
  @override
  State<UtcScheduleDateField> createState() => _UtcScheduleDateFieldState();
}

class _UtcScheduleDateFieldState extends State<UtcScheduleDateField> {
  bool _choosing = false;
  int _generation = 0;
  BuildContext? _pickerContext;
  @override
  void didUpdateWidget(UtcScheduleDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || !widget.enabled) ++_generation;
  }
  Future<void> _choose() async {
    if (_choosing || !widget.enabled || !widget.isCurrent()) return;
    final generation = ++_generation;
    bool current() => mounted && generation == _generation && widget.enabled && widget.isCurrent();
    setState(() => _choosing = true);
    try {
      final initial = widget.value ?? DateTime.now().toUtc();
      final date = await showDatePicker(context: context,
        helpText: '${widget.label} - UTC date',
        initialDate: DateTime(initial.year, initial.month, initial.day),
        firstDate: DateTime(1), lastDate: DateTime(9999, 12, 31),
        builder: (context, child) { _pickerContext = context; return child!; });
      if (date == null || !mounted || !current()) return;
      final time = await showTimePicker(context: context,
        helpText: '${widget.label} - UTC time',
        initialTime: widget.value == null ? const TimeOfDay(hour: 0, minute: 0) :
          TimeOfDay(hour: initial.hour, minute: initial.minute),
        builder: (context, child) {
          _pickerContext = context;
          return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!);
        });
      if (time != null && current()) {
        widget.onChanged(utcScheduleDate(DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)));
      }
    } finally {
      _pickerContext = null;
      if (mounted) setState(() => _choosing = false);
    }
  }
  @override
  void dispose() {
    ++_generation;
    final context = _pickerContext;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context != null && context.mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('${widget.label} (UTC)'),
    Text(widget.value?.toIso8601String() ?? 'Unscheduled'),
    Wrap(children: [
      IconButton(tooltip: 'Choose ${widget.label} (UTC)', icon: const Icon(Icons.calendar_month_outlined),
        onPressed: widget.enabled && !_choosing ? _choose : null),
      IconButton(tooltip: 'Clear ${widget.label}', icon: const Icon(Icons.clear),
        onPressed: widget.enabled && !_choosing && widget.value != null ? () {
          if (widget.isCurrent()) widget.onChanged(null);
        } : null),
    ]),
  ]);
}