// Om Sai Ram
// Assignments repository — chapter assignment and schedule API calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/constants/app_constants.dart';
import 'assignment_model.dart';

final assignmentsRepositoryProvider = Provider<AssignmentsRepository>((ref) {
  return AssignmentsRepository(apiClient: ref.read(apiClientProvider));
});

class AssignmentsRepository {
  final ApiClient _apiClient;

  AssignmentsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

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

  Future<List<Assignment>> autoSchedule({
    required String groupId,
    required int startChapter,
    int weeksAhead = 4,
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.assignmentsEndpoint}/auto-schedule',
      data: {
        'group_id': groupId,
        'start_chapter': startChapter,
        'weeks_ahead': weeksAhead,
      },
    );
    final List<dynamic> data = response.data as List;
    return data.map((j) => Assignment.fromJson(j as Map<String, dynamic>)).toList();
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
