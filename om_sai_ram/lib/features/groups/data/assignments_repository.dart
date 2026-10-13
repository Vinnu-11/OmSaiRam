// Om Sai Ram
// Assignments repository — chapter assignment and schedule API calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/chapter_units.dart';
import '../../reader/data/chapter_model.dart';
import 'assignment_model.dart';
import 'schedule_suggestion_model.dart';

final assignmentsRepositoryProvider = Provider<AssignmentsRepository>((ref) {
  return AssignmentsRepository(apiClient: ref.read(apiClientProvider));
});

class AssignmentsRepository {
  final ApiClient _apiClient;

  AssignmentsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Use the server chapter index: bundled chapter IDs are not database IDs.
  Future<List<Chapter>> getAssignableChapters() async {
    var response = await _apiClient.get('${AppConstants.chaptersEndpoint}/mr');
    // Older databases may have an English index instead of the Marathi index.
    if ((response.data as List).isEmpty) {
      response = await _apiClient.get('${AppConstants.chaptersEndpoint}/en');
    }
    final chapters = (response.data as List)
        .map((json) => Chapter.fromJson(json as Map<String, dynamic>))
        .where((chapter) => ChapterUnits.start(chapter.number) == chapter.number)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    final seen = <int>{};
    return chapters.where((chapter) => seen.add(chapter.number)).toList();
  }

  Future<List<Assignment>> getGroupAssignments(String groupId, {int? weekNumber}) async {
    final params = <String, dynamic>{};
    if (weekNumber != null) params['week_number'] = weekNumber;
    final response = await _apiClient.get(
      '${AppConstants.assignmentsEndpoint}/group/$groupId',
      queryParameters: params,
    );
    final List<dynamic> data = response.data as List;
    return data.map((j) => Assignment.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<List<Assignment>> getMyAssignments() async {
    final response = await _apiClient.get('${AppConstants.assignmentsEndpoint}/my');
    final List<dynamic> data = response.data as List;
    return data.map((j) => Assignment.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Assignment> createAssignment({
    required String groupId,
    required String userId,
    required int chapterId,
    int weekNumber = 1,
    DateTime? scheduledDate,
  }) async {
    final response = await _apiClient.post(
      AppConstants.assignmentsEndpoint,
      data: {
        'group_id': groupId,
        'user_id': userId,
        'chapter_id': chapterId,
        'week_number': weekNumber,
        if (scheduledDate != null) 'scheduled_date': scheduledDate.toIso8601String(),
      },
    );
    return Assignment.fromJson(response.data as Map<String, dynamic>);
  }

  /// Auto-schedules chapters for all members using the given mode.
  ///
  /// [scheduleMode]: 'independent' | 'rotating_window' | 'dense_window' | 'synchronized'
  /// [remainderMode]: 'manual' | 'truncate' | 'extend_last' | 'round_robin' | 'cycle'
  Future<({List<Assignment> assignments, List<Map<String, dynamic>> remainderChapters})>
      autoSchedule({
    required String groupId,
    required int startChapter,
    int weeksAhead = 4,
    String scheduleMode = 'independent',
    String remainderMode = 'manual',
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.assignmentsEndpoint}/auto-schedule',
      data: {
        'group_id': groupId,
        'start_chapter': startChapter,
        'weeks_ahead': weeksAhead,
        'schedule_mode': scheduleMode,
        'remainder_mode': remainderMode,
      },
    );
    final body = response.data as Map<String, dynamic>;
    final assignments = (body['assignments'] as List)
        .map((j) => Assignment.fromJson(j as Map<String, dynamic>))
        .toList();
    final remainder = (body['remainder_chapters'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return (assignments: assignments, remainderChapters: remainder);
  }

  /// Detect the lead's chapter-assignment pattern from 2+ manual hints and
  /// return a full suggested grid for all members × [weeksAhead] weeks.
  ///
  /// No database writes — call [autoSchedule] with the returned mode to confirm.
  Future<ScheduleSuggestion> suggestSchedule({
    required String groupId,
    required int weekNumber,
    required List<({int position, int chapterStart})> hints,
    int weeksAhead = 3,
    String remainderMode = 'manual',
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.assignmentsEndpoint}/suggest',
      data: {
        'group_id': groupId,
        'week_number': weekNumber,
        'hints': hints
            .map((h) => {'position': h.position, 'chapter_start': h.chapterStart})
            .toList(),
        'weeks_ahead': weeksAhead,
        'remainder_mode': remainderMode,
      },
    );
    return ScheduleSuggestion.fromJson(response.data as Map<String, dynamic>);
  }

  Future<int> advanceWeek(String groupId) async {
    final response = await _apiClient.post(
      '${AppConstants.assignmentsEndpoint}/advance-week/$groupId',
    );
    return response.data['current_week'] as int;
  }

  Future<void> deleteAssignment(String assignmentId) async {
    await _apiClient.delete('${AppConstants.assignmentsEndpoint}/$assignmentId');
  }

  Future<void> updateProgress(String assignmentId, String status) async {
    await _apiClient.patch(
      '${AppConstants.progressEndpoint}/$assignmentId',
      data: {'status': status},
    );
  }
}

