import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firebase_member_display_models.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'firebase_groups_test.dart' as groups;

/// The group home page (`/groups/:id`) sits under every group route and reads
/// this week's assignments and shared names. Tests that only care about another
/// group page add these quiet gateways so the home page can render.
class EmptyAssignments extends Fake implements FirebaseAssignmentsGateway {
  final reads = <FirebaseAssignmentsScope>[];
  @override
  Future<FirebaseAssignmentsResult> read(FirebaseAssignmentsScope scope) async {
    reads.add(scope);
    final detail = groups.detailFor(FirebaseGroupRole.member);
    return FirebaseAssignmentsResult(detail.group, detail.self,
      FirebaseMembership(scope.memberUid, FirebaseGroupRole.member, detail.self.joinedAt), const []);
  }
}

class EmptyDisplays extends Fake implements FirebaseMemberDisplayGateway {
  @override
  Future<List<FirebaseMemberDisplay>> readMembers(String groupId, List<String> memberUids) async => const [];
}

List<Override> groupHomeOverrides({bool assignments = true, bool names = true}) => [
  if (assignments) firebaseAssignmentsGatewayProvider.overrideWithValue(EmptyAssignments()),
  if (names) firebaseMemberDisplayGatewayProvider.overrideWithValue(EmptyDisplays()),
];
