// Om Sai Ram
// Notification schedule repository — fetch and persist group notification config.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/constants/app_constants.dart';
import 'notification_schedule_model.dart';

final notificationScheduleRepositoryProvider =
    Provider<NotificationScheduleRepository>((ref) {
  return NotificationScheduleRepository(apiClient: ref.read(apiClientProvider));
});

class NotificationScheduleRepository {
  final ApiClient _apiClient;

  NotificationScheduleRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  String _url(String groupId) =>
      '${AppConstants.groupNotificationScheduleEndpoint}/$groupId/notification-schedule';

  /// Fetch the notification schedule for [groupId].
  /// Returns null if none has been configured yet (404).
  Future<GroupNotificationSchedule?> getSchedule(String groupId) async {
    try {
      final response = await _apiClient.get(_url(groupId));
      return GroupNotificationSchedule.fromJson(
          response.data as Map<String, dynamic>);
    } catch (e) {
      // 404 means the lead hasn't set a schedule yet — that's fine.
      return null;
    }
  }

  /// Create or update the notification schedule for [groupId].
  Future<GroupNotificationSchedule> setSchedule(
    String groupId,
    GroupNotificationSchedule schedule,
  ) async {
    final response = await _apiClient.put(
      _url(groupId),
      data: schedule.toJson(),
    );
    return GroupNotificationSchedule.fromJson(
        response.data as Map<String, dynamic>);
  }
}
