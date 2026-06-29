// Om Sai Ram
// Groups state provider — manages group list and operations.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/group_model.dart';
import '../data/groups_repository.dart';

/// State for the groups list.
class GroupsState {
  final List<Group> groups;
  final bool isLoading;
  final String? error;

  const GroupsState({
    this.groups = const [],
    this.isLoading = false,
    this.error,
  });

  GroupsState copyWith({
    List<Group>? groups,
    bool? isLoading,
    String? error,
  }) {
    return GroupsState(
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Provider for the groups list state.
final groupsProvider =
    StateNotifierProvider<GroupsNotifier, GroupsState>((ref) {
  return GroupsNotifier(repository: ref.read(groupsRepositoryProvider));
});

/// Manages the list of groups the user belongs to.
class GroupsNotifier extends StateNotifier<GroupsState> {
  final GroupsRepository _repository;

  GroupsNotifier({required GroupsRepository repository})
      : _repository = repository,
        super(const GroupsState());

  /// Loads all groups for the current user.
  Future<void> loadGroups() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final groups = await _repository.getMyGroups();
      state = GroupsState(groups: groups);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  /// Creates a new group and adds it to the list.
  /// Returns true on success, false on failure.
  Future<bool> createGroup({
    required String name,
    String? description,
    required ReadingMode mode,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final group = await _repository.createGroup(
        name: name,
        description: description,
        mode: mode,
      );
      state = GroupsState(groups: [...state.groups, group]);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  /// Joins a group via invite code.
  /// Returns true on success, false on failure.
  Future<bool> joinGroup(String inviteCode) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final group = await _repository.joinGroup(inviteCode);
      state = GroupsState(groups: [...state.groups, group]);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  /// Removes a group from the local list after leaving/deleting.
  void removeGroup(String groupId) {
    state = GroupsState(
      groups: state.groups.where((g) => g.id != groupId).toList(),
    );
  }

  /// Clears the error state.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Parses exceptions into user-friendly messages.
  String _parseError(dynamic error) {
    final errStr = error.toString();

    if (errStr.contains('SocketException') ||
        errStr.contains('Connection refused')) {
      return 'No internet connection. Please check your network.';
    }
    if (errStr.contains('TimeoutException') ||
        errStr.contains('connectTimeout')) {
      return 'Connection timed out. Please try again.';
    }
    if (errStr.contains('404')) {
      return 'Group not found. Please check the invite code.';
    }
    if (errStr.contains('409')) {
      return 'You are already a member of this group.';
    }
    if (errStr.contains('403')) {
      return 'You don\'t have permission for this action.';
    }
    if (errStr.contains('429')) {
      return 'Too many attempts. Please wait and try again.';
    }

    return 'Something went wrong. Please try again.';
  }
}
