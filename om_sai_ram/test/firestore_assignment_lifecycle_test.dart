import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firebase_task_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'firestore_group_admin_gateway_test.dart' as admin;
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firebase_assignments_test.dart' as assignments;

const scope = (uid: 'a', groupId: 'g', memberUid: 'b', week: 1);
const path = 'groups/g/readingWeeks/1/members/b/assignments/16-17';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late admin.AdminDb db;
  late sdk.SdkAuth auth;
  late FirestoreAssignmentsGateway gateway;
  FirebaseAssignment baseline() => FirebaseAssignment.parse(scope, '16-17', Map.of(db.documents[path]!));
  setUp(() {
    db = admin.AdminDb(); admin.seed(db); auth = sdk.SdkAuth(); gateway = FirestoreAssignmentsGateway(auth, db);
    db.documents[path] = assignments.assignmentData(scope: scope);
  });
  test('archive retains exact history and replacement resets progress and date', () async {
    db.documents[path]!['status'] = 'completed';
    final original = Map.of(db.documents[path]!);
    await gateway.transition(scope, baseline(), archived: true, scheduledDate: null);
    expect(db.documents['$path/versions/0'], original);
    expect(baseline().archived, true); expect(baseline().status, FirebaseReadingStatus.completed);
    expect(taskSummary([baseline()]).total, 0);
    await gateway.transition(scope, baseline(), archived: false, scheduledDate: null);
    expect(baseline().revision, 2); expect(baseline().status, FirebaseReadingStatus.notStarted);
    expect(db.documents['$path/versions/1']!['status'], 'completed');
    expect((await gateway.version(scope, baseline().unit, 0)).status, FirebaseReadingStatus.completed);
  });
  test('reassignment stages history, source archive and fresh target in one transaction', () async {
    await gateway.transition(scope, baseline(), archived: true, scheduledDate: DateTime.utc(2026, 11, 1), reassignTo: 'a');
    expect(db.writes.length, 3);
    expect(db.documents['groups/g/readingWeeks/1/members/a/assignments/16-17']!['status'], 'not_started');
    expect(db.documents[path]!['archived'], true);
  });
  for (final changed in ['role', 'progress', 'revision', 'account', 'group']) {
    test('retry rechecks $changed and discards all staged writes', () async {
      final old = baseline(); db.attempts = 2;
      db.beforeAttempt = (attempt) {
        if (attempt == 0) return;
        if (changed == 'role') db.documents[admin.actorPath]!['role'] = 'member';
        if (changed == 'progress') db.documents[path]!['progressUpdatedAt'] = Timestamp(old.progressToken.seconds, old.progressToken.nanoseconds + 1);
        if (changed == 'revision') db.documents[path]!.addAll({'archived': true, 'revision': 1, 'changedBy': 'a', 'changedAt': admin.instant});
        if (changed == 'account') auth.currentUser = sdk.SdkUser('other');
        if (changed == 'group') {
          db.documents[admin.groupPath]!.addAll({'archived': true, 'lifecycleRevision': 1,
            'lifecycleChangedBy': 'a', 'lifecycleChangedAt': admin.instant});
        }
      };
      await expectLater(gateway.transition(scope, old, archived: true, scheduledDate: null),
        changed == 'account' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  test('duplicate target and failed commit leave source/history untouched', () async {
    db.documents['groups/g/readingWeeks/1/members/a/assignments/16-17'] = assignments.assignmentData();
    await expectLater(gateway.transition(scope, baseline(), archived: true, scheduledDate: null, reassignTo: 'a'), throwsFormatException);
    expect(db.writes, isEmpty);
    db.errors['commit'] = StateError('unavailable');
    await expectLater(gateway.transition(scope, baseline(), archived: true, scheduledDate: null), throwsStateError);
    expect(db.writes, isEmpty); expect(db.documents.containsKey('$path/versions/0'), false);
  });
  test('lifecycle fields are all-or-none, typed and bounded', () {
    final raw = {...db.documents[path]!, 'archived': true, 'revision': 1, 'changedBy': 'a', 'changedAt': admin.instant};
    for (final key in ['archived', 'revision', 'changedBy', 'changedAt']) {
      expect(() => FirebaseAssignment.parse(scope, '16-17', Map.of(raw)..remove(key)), throwsFormatException);
    }
    for (final patch in [{'archived': 1}, {'revision': 0}, {'revision': 2147483648}, {'changedBy': ''}, {'changedAt': null}]) {
      expect(() => FirebaseAssignment.parse(scope, '16-17', {...raw, ...patch}), throwsFormatException);
    }
  });
  test('fresh join nanosecond boundary prevents silent history inheritance', () {
    final row = baseline();
    final joined = Timestamp(row.createdToken.seconds, row.createdToken.nanoseconds + 1);
    final member = FirebaseMembership.parse('b', {'userId': 'b', 'role': 'member', 'joinedAt': joined});
    expect(row.activeFor(member), false);
    expect(row.activeSince(row.createdToken), true);
  });
}