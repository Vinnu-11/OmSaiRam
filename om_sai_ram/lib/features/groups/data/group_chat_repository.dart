// Om Sai Ram
// Group chat repository — messages and highlight comment API calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/constants/app_constants.dart';
import 'chat_model.dart';

final groupChatRepositoryProvider = Provider<GroupChatRepository>((ref) {
  return GroupChatRepository(apiClient: ref.read(apiClientProvider));
});

class GroupChatRepository {
  final ApiClient _apiClient;

  GroupChatRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<GroupMessage>> getMessages(String groupId, {String? beforeId}) async {
    final params = <String, dynamic>{'limit': 50};
    if (beforeId != null) params['before_id'] = beforeId;
    final response = await _apiClient.get(
      '${AppConstants.groupsEndpoint}/$groupId/messages',
      queryParameters: params,
    );
    final List<dynamic> data = response.data as List;
    return data.map((j) => GroupMessage.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<GroupMessage> sendMessage(String groupId, String content) async {
    final response = await _apiClient.post(
      '${AppConstants.groupsEndpoint}/$groupId/messages',
      data: {'content': content},
    );
    return GroupMessage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteMessage(String groupId, String messageId) async {
    await _apiClient.delete(
      '${AppConstants.groupsEndpoint}/$groupId/messages/$messageId',
    );
  }

  Future<List<HighlightComment>> getHighlightComments(String groupId, {int? chapterId}) async {
    final params = <String, dynamic>{};
    if (chapterId != null) params['chapter_id'] = chapterId;
    final response = await _apiClient.get(
      '${AppConstants.groupsEndpoint}/$groupId/highlights',
      queryParameters: params,
    );
    final List<dynamic> data = response.data as List;
    return data.map((j) => HighlightComment.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<HighlightComment> postHighlightComment({
    required String groupId,
    required int chapterId,
    required String highlightedText,
    required int paragraphIndex,
    required String comment,
  }) async {
    final response = await _apiClient.post(
      '${AppConstants.groupsEndpoint}/$groupId/highlights',
      data: {
        'chapter_id': chapterId,
        'highlighted_text': highlightedText,
        'paragraph_index': paragraphIndex,
        'comment': comment,
      },
    );
    return HighlightComment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteHighlightComment(String groupId, String highlightId) async {
    await _apiClient.delete(
      '${AppConstants.groupsEndpoint}/$groupId/highlights/$highlightId',
    );
  }
}
