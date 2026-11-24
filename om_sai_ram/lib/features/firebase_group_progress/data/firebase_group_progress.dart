import '../../firebase_assignments/data/firebase_assignment_models.dart';
import '../../firebase_assignments/data/firestore_assignments_gateway.dart';
import '../../firebase_groups/data/firebase_group_models.dart';
import '../../firebase_groups/data/firestore_groups_gateway.dart';
import '../../firebase_member_display/data/firebase_member_display_models.dart';
import '../../firebase_member_display/data/firestore_member_display_gateway.dart';
import '../../firebase_tasks/data/firebase_task_models.dart';

typedef FirebaseGroupProgressBinding = ({String uid, String groupId, int week});

void validateGroupProgressBinding(FirebaseGroupProgressBinding binding, [String? cursor]) {
  assignmentSegment(binding.uid);
  assignmentSegment(binding.groupId);
  assignmentWeek(binding.week);
  if (cursor != null) assignmentSegment(cursor);
}

class FirebaseGroupProgressMember {
  final FirebaseMembership member;
  final FirebaseMemberDisplay? sharedName;
  final List<FirebaseAssignment> assignments;
  FirebaseGroupProgressMember(this.member, this.sharedName, Iterable<FirebaseAssignment> assignments)
      : assignments = List.unmodifiable(assignments);
  FirebaseTaskSummary get summary => taskSummary(assignments.where((row) => row.activeFor(member)));
}

class FirebaseGroupProgressPage {
  final FirebaseGroupDetail detail;
  final List<FirebaseGroupProgressMember> members;
  FirebaseGroupProgressPage(this.detail, Iterable<FirebaseGroupProgressMember> members)
      : members = List.unmodifiable(members);
  FirebaseTaskSummary get summary => taskSummary(members.expand((entry) => entry.assignments.where((row) => row.activeFor(entry.member))));
  void validate(FirebaseGroupProgressBinding binding, String? after) {
    validateGroupProgressBinding(binding, after);
    final roster = detail.members;
    if (detail.group.id != binding.groupId || detail.self.uid != binding.uid ||
        roster.items.length > 10 ||
        roster.hasMore != (roster.items.length == 10) ||
        roster.cursor != (roster.items.isEmpty ? after : roster.items.last.uid) ||
        members.length != roster.items.length) {
      throw const FormatException('Progress roster scope or pagination mismatch.');
    }
    var previous = after;
    for (var index = 0; index < members.length; index++) {
      final entry = members[index];
      final uid = assignmentSegment(entry.member.uid);
      final expected = roster.items[index];
      if (expected.uid != uid || expected.role != entry.member.role ||
          (previous != null && memberDisplayIdCompare(uid, previous) <= 0) ||
          (entry.sharedName != null && (entry.sharedName!.uid != uid || entry.sharedName!.groupId != binding.groupId)) ||
          entry.assignments.length > 48 ||
          entry.assignments.map((row) => row.unit.key).toSet().length != entry.assignments.length ||
          entry.assignments.any((row) => row.groupId != binding.groupId || row.userId != uid || row.weekNumber != binding.week)) {
        throw const FormatException('Progress member, name or assignment scope mismatch.');
      }
      previous = uid;
    }
  }
}

class FirebaseGroupProgressGateway {
  final FirebaseGroupsGateway groups;
  final FirebaseAssignmentsGateway assignments;
  final FirebaseMemberDisplayGateway names;
  final bool Function() isCurrent;
  FirebaseGroupProgressGateway(this.groups, this.assignments, this.names, this.isCurrent);
  Future<T> _checked<T>(Future<T> Function() action) async {
    if (!isCurrent()) throw StateError('Firebase account changed.');
    try {
      final result = await action();
      if (!isCurrent()) throw StateError('Firebase account changed.');
      return result;
    } catch (_) {
      if (!isCurrent()) throw StateError('Firebase account changed.');
      rethrow;
    }
  }
  Future<FirebaseGroupProgressPage> read(FirebaseGroupProgressBinding binding, {String? cursor}) async {
    validateGroupProgressBinding(binding, cursor);
    final detail = await _checked(() => groups.detail(binding.groupId, pageSize: 10, cursor: cursor));
    FirebaseGroupProgressPage(detail, detail.members.items.map((member) =>
      FirebaseGroupProgressMember(member, null, const []))).validate(binding, cursor);
    final uids = detail.members.items.map((member) => member.uid).toList();
    final display = uids.isEmpty ? <FirebaseMemberDisplay>[] :
      await _checked(() => names.readMembers(binding.groupId, uids));
    if (display.length > uids.length || display.map((name) => name.uid).toSet().length != display.length ||
        display.any((name) => name.groupId != binding.groupId || !uids.contains(name.uid))) {
      throw const FormatException('Progress shared name scope mismatch.');
    }
    final shared = {for (final name in display) name.uid: name};
    final members = <FirebaseGroupProgressMember>[];
    for (final member in detail.members.items) {
      final result = await _checked(() => assignments.read((uid: binding.uid,
        groupId: binding.groupId, memberUid: member.uid, week: binding.week)));
      if (result.group.id != binding.groupId || result.self.uid != binding.uid ||
          result.member.uid != member.uid || result.member.role != member.role) {
        throw const FormatException('Progress assignment authority changed. Refresh.');
      }
      members.add(FirebaseGroupProgressMember(member, shared[member.uid], result.assignments));
    }
    final page = FirebaseGroupProgressPage(detail, members);
    page.validate(binding, cursor);
    if (!isCurrent()) throw StateError('Firebase account changed.');
    return page;
  }
}

String groupProgressAssignmentsLocation(FirebaseGroupProgressBinding binding, String memberUid) =>
  Uri(pathSegments: ['', 'groups', binding.groupId, 'assignments'],
    queryParameters: {'member': memberUid, 'week': '${binding.week}'}).toString();