// Om Sai Ram
// Groups repository — handles group CRUD and membership API calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/api_client.dart';
import 'group_model.dart';

/// Provider for the groups repository.
final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(apiClient: ref.read(apiClientProvider));
});

/// Handles all group-related API operations.
///
/// Responsibilities:
/// - Fetch user's groups
/// - Create a new group
/// - Join a group via invite code
/// - Get group details with members
/// - Leave/delete a group
class GroupsRepository {
  final ApiClient _apiClient;

  GroupsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Fetches all groups the current user belongs to.
  Future<List<Group>> getMyGroups() async {
    final response = await _apiClient.get(AppConstants.groupsEndpoint);
    final List<dynamic> data = response.data['groups'];
    return data.map((json) => Group.fromJson(json)).toList();
  }

  /// Creates a new group with the given name, description, and reading mode.
  Future<Group> createGroup({
    required String name,
    String? description,
    required ReadingMode mode,
  }) async {
    final response = await _apiClient.post(
      AppConstants.groupsEndpoint,
      data: {
        'name': name,
        'description': description,
        'mode': mode == ReadingMode.saptah ? 'saptah' : 'chapter_wise',
      },
    );
    return Group.fromJson(response.data);
  }

  /// Joins an existing group using an invite code.
  Future<Group> joinGroup(String inviteCode) async {
    final response = await _apiClient.post(
      AppConstants.joinGroupEndpoint,
      data: {'invite_code': inviteCode},
    );
    return Group.fromJson(response.data);
  }

  /// Fetches details of a specific group including its members.
  Future<Map<String, dynamic>> getGroupDetail(String groupId) async {
    final response = await _apiClient.get(
      '${AppConstants.groupsEndpoint}/$groupId',
    );
    return {
      'group': Group.fromJson(response.data['group']),
      'members': (response.data['members'] as List)
          .map((m) => GroupMember.fromJson(m))
          .toList(),
    };
  }

  /// Removes the current user from a group.
  Future<void> leaveGroup(String groupId) async {
    await _apiClient.delete(
      '${AppConstants.groupsEndpoint}/$groupId/leave',
    );
  }

  /// Deletes a group (admin only).
  Future<void> deleteGroup(String groupId) async {
    await _apiClient.delete('${AppConstants.groupsEndpoint}/$groupId');
  }
}
