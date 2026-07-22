// Om Sai Ram
// ScheduleSuggestion — result of the pattern-detect /suggest API endpoint.

/// One suggested chapter assignment in the preview grid.
class SuggestedSlot {
  final int weekNumber;
  final int position;        // 0-based member position in join order
  final String userId;
  final String userName;
  final List<int> chapterNumbers;
  final bool isManual;       // true = provided by lead, false = computed

  const SuggestedSlot({
    required this.weekNumber,
    required this.position,
    required this.userId,
    required this.userName,
    required this.chapterNumbers,
    required this.isManual,
  });

  factory SuggestedSlot.fromJson(Map<String, dynamic> json) {
    return SuggestedSlot(
      weekNumber: json['week_number'] as int,
      position: json['position'] as int,
      userId: json['user_id'] as String,
      userName: json['user_name'] as String,
      chapterNumbers: (json['chapter_numbers'] as List).cast<int>(),
      isManual: json['is_manual'] as bool,
    );
  }

  /// Human-readable chapter range label, e.g. "Ch.1–2" or "Ch.1, 2, 3".
  String get label {
    if (chapterNumbers.isEmpty) return '—';
    if (chapterNumbers.length == 1) return 'Ch.${chapterNumbers.first}';
    final first = chapterNumbers.first;
    final last = chapterNumbers.last;
    // Consecutive range
    if (last - first == chapterNumbers.length - 1) return 'Ch.$first–$last';
    return 'Ch.${chapterNumbers.join(', ')}';
  }
}

/// Full suggestion result returned from the /suggest endpoint.
class ScheduleSuggestion {
  /// 'non_overlapping' | 'dense' | 'custom'
  final String detectedMode;
  final int detectedStep;
  final int chaptersPerMember;
  final List<SuggestedSlot> suggestions;
  final List<int> remainderChapters;

  const ScheduleSuggestion({
    required this.detectedMode,
    required this.detectedStep,
    required this.chaptersPerMember,
    required this.suggestions,
    required this.remainderChapters,
  });

  factory ScheduleSuggestion.fromJson(Map<String, dynamic> json) {
    return ScheduleSuggestion(
      detectedMode: json['detected_mode'] as String,
      detectedStep: json['detected_step'] as int,
      chaptersPerMember: json['chapters_per_member'] as int,
      suggestions: (json['suggestions'] as List)
          .map((j) => SuggestedSlot.fromJson(j as Map<String, dynamic>))
          .toList(),
      remainderChapters: (json['remainder_chapters'] as List).cast<int>(),
    );
  }

  /// Friendly mode name for display.
  String get modeLabel {
    switch (detectedMode) {
      case 'non_overlapping':
        return 'Non-overlapping (Independent)';
      case 'dense':
        return 'Dense Sliding Window';
      default:
        return 'Custom (step = $detectedStep)';
    }
  }

  /// The backend schedule_mode string that matches this suggestion.
  /// Used when calling auto-schedule to confirm.
  String get backendMode {
    switch (detectedMode) {
      case 'non_overlapping':
        return 'independent';
      case 'dense':
        return 'dense_window';
      default:
        return 'independent'; // fallback
    }
  }

  /// Return slots for a specific [week].
  List<SuggestedSlot> slotsForWeek(int week) =>
      suggestions.where((s) => s.weekNumber == week).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  /// All unique week numbers, sorted.
  List<int> get weeks {
    final ws = suggestions.map((s) => s.weekNumber).toSet().toList()..sort();
    return ws;
  }
}
