// SDK-shaped doubles verify Dart calls and staged writes only. These are NOT
// certification of real Firestore rules, atomicity, ACKs or transaction retries.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_membership/data/firestore_membership_gateway.dart';
import 'package:om_sai_ram/features/firebase_membership/data/firebase_membership_models.dart';
import 'firestore_group_admin_gateway_test.dart' as admin;
import 'firebase_groups_test.dart' as groups;
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;

const actorPath = 'groups/g/members/a';
const targetPath = 'groups/g/members/b';
const sharedPath = 'groups/g/memberProfiles/b';
const indexPath = 'users/b/groups/g';
const markerPath = 'groups/g/departures/b';
final instant = Timestamp(1700000000, 123456789);
sdk.Data profile() => {'displayName': 'Private', 'createdAt': instant, 'updatedAt': instant};
sdk.Data member(String uid, String role) => {'userId': uid, 'role': role, 'joinedAt': instant};

class MembershipDb extends chat.ChatDb {
  final operations = <String>[];
  final committed = <String>[];
  void Function(int)? beforeAttempt;
  int attempts = 1;
  @override
  Future<chat.ChatSnapshot> read(String path, GetOptions? options) async {
    operations.add('read:$path');
    final snapshot = await super.read(path, options);
    return chat.ChatSnapshot(this, poisonPath ?? path, snapshot.raw, snapshot.metadata);
  }
  @override
  Future<T> runTransaction<T>(Future<T> Function(Transaction) handler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    transactions++;
    for (var i = 0; i < attempts; i++) {
      beforeAttempt?.call(i);
      final transaction = MembershipTransaction(this);
      final result = await handler(transaction);
      if (i < attempts - 1) continue; // Discard staged writes on simulated retry.
      if (gates['commit'] != null) await gates['commit']!.future;
      if (errors['commit'] != null) throw errors['commit']!;
      // Model ONLY the two commit preconditions needed for failure tests.
      // This is deliberately not presented as a security-rules implementation.
      final marker = transaction.sets.single.path;
      final target = marker.split('/').last;
      if (documents.containsKey(marker) || !documents.containsKey('users/$target/groups/g')) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      }
      for (final write in transaction.sets) { documents[write.path] = write.data; }
      for (final path in transaction.deletes) { documents.remove(path); }
      writes.addAll(transaction.sets);
      committed.addAll(transaction.deletes);
      return result;
    }
    throw StateError('No attempt.');
  }
}
class MembershipTransaction extends sdk.SdkTransaction {
  final sets = <({String path, sdk.Data data, bool transaction})>[];
  final deletes = <String>[];
  bool writing = false;
  MembershipTransaction(MembershipDb super.db);
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> reference) {
    if (writing) throw StateError('Read after write.');
    return super.get(reference);
  }
  @override
  Transaction set<T>(DocumentReference<T> reference, T data, [SetOptions? options]) {
    writing = true;
    (db as MembershipDb).operations.add('set:${reference.path}');
    sets.add((path: reference.path, data: data as sdk.Data, transaction: true));
    expect(options, isNull);
    return this;
  }
  @override
  Transaction delete(DocumentReference reference) {
    writing = true;
    (db as MembershipDb).operations.add('delete:${reference.path}');
    deletes.add(reference.path);
    return this;
  }
}

void seed(MembershipDb db) {
  db.documents.addAll({
    'users/a': profile(),
    'groups/g': {...groups.groupData(), 'createdBy': 'creator'},
    actorPath: member('a', 'admin'), targetPath: member('b', 'member'),
    indexPath: {'groupId': 'g', 'joinedAt': instant},
    'users/a/groups/g': {'groupId': 'g', 'joinedAt': instant},
    'groups/g/readingWeeks/1/members/b/assignments/1': {'history': 'assignment'},
    'groups/g/messages/z': {'history': 'chat'},
    'groups/g/highlights/z': {'history': 'highlight'},
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MembershipDb db;
  late sdk.SdkAuth auth;
  late FirestoreMembershipGateway gateway;
  setUp(() { db = MembershipDb(); seed(db); auth = sdk.SdkAuth(); gateway = FirestoreMembershipGateway(auth, db); });

  for (final shared in [false, true]) {
    test('remove exact transaction with optional display $shared all reads before writes', () async {
      if (shared) db.documents[sharedPath] = profile();
      await gateway.remove('g', 'b');
      expect(db.reads, ['users/a', 'groups/g', actorPath, targetPath, sharedPath, markerPath]);
      expect(db.sources.first, Source.server);
      expect(db.operations, ['read:users/a', 'read:groups/g', 'read:$actorPath',
        'read:$targetPath', 'read:$sharedPath', 'read:$markerPath', 'set:$markerPath', 'delete:$targetPath',
        'delete:$indexPath', if (shared) 'delete:$sharedPath']);
      expect(db.writes.single.data, {'userId': 'b', 'removedBy': 'a',
        'removedAt': FieldValue.serverTimestamp(), 'reason': 'removed'});
      expect(db.writes.single.transaction, isTrue);
      expect(db.committed, [targetPath, indexPath, if (shared) sharedPath]);
      expect(db.transactions, 1);
    });
  }
  for (final role in ['member', 'group_lead']) {
    test('self $role leave exact marker and no duplicate actor read', () async {
      db.documents[actorPath] = member('a', role);
      db.documents['groups/g/memberProfiles/a'] = profile();
      await gateway.leave('g');
      expect(db.reads, ['users/a', 'groups/g', actorPath, 'groups/g/memberProfiles/a', 'groups/g/departures/a']);
      expect(db.writes.single.path, 'groups/g/departures/a');
      expect(db.writes.single.data, {'userId': 'a', 'removedBy': 'a',
        'removedAt': FieldValue.serverTimestamp(), 'reason': 'left'});
      expect(db.committed, [actorPath, 'users/a/groups/g', 'groups/g/memberProfiles/a']);
    });
  }
  for (final actor in ['admin', 'group_lead', 'member']) {
    for (final target in ['admin', 'group_lead', 'member']) {
      test('prewrite $actor removes $target only under exact policy', () async {
        db.documents[actorPath] = member('a', actor);
        db.documents[targetPath] = member('b', target);
        if (actor == 'admin' || (actor == 'group_lead' && target == 'member')) {
          await gateway.remove('g', 'b'); expect(db.writes.length, 1);
        } else {
          await expectLater(gateway.remove('g', 'b'), throwsFormatException);
          expect(db.writes, isEmpty); expect(db.committed, isEmpty);
        }
      });
    }
    test('$actor cannot remove itself', () async {
      db.documents[actorPath] = member('a', actor);
      await expectLater(gateway.remove('g', 'a'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
    test('creator $actor cannot leave', () async {
      db.documents['groups/g']!['createdBy'] = 'a';
      db.documents[actorPath] = member('a', actor);
      await expectLater(gateway.leave('g'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
    test('$actor cannot remove creator regardless target role', () async {
      db.documents['groups/g']!['createdBy'] = 'b';
      db.documents[actorPath] = member('a', actor);
      await expectLater(gateway.remove('g', 'b'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  test('noncreator admin cannot self leave', () async {
    await expectLater(gateway.leave('g'), throwsFormatException); expect(db.writes, isEmpty);
  });
  for (final invalid in ['', '.', '..', 'a/b', '__reserved__', 'é' * 751]) {
    test('invalid segment length ${invalid.length} rejected before SDK', () async {
      expect(() => gateway.remove(invalid, 'b'), throwsFormatException);
      expect(() => gateway.remove('g', invalid), throwsFormatException);
      expect(() => gateway.leave(invalid), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  for (final path in ['users/a', 'groups/g', actorPath, targetPath]) {
    test('missing $path fails no staged/committed writes', () async {
      db.documents.remove(path);
      await expectLater(gateway.remove('g', 'b'), throwsFormatException);
      expect(db.operations.any((op) => op.startsWith('set:')), isFalse);
      expect(db.committed, isEmpty);
    });
    test('extra private fields in $path rejected no copying', () async {
      db.documents[path]!['email'] = 'private@example.com';
      await expectLater(gateway.remove('g', 'b'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final path in [actorPath, targetPath]) {
    for (final patch in <sdk.Data>[{'role': 'owner'}, {'role': null}, {'userId': 'other'}, {'joinedAt': DateTime.utc(2026)}]) {
      test('strict $path rejects $patch atomically', () async {
        db.documents[path]!.addAll(patch);
        await expectLater(gateway.remove('g', 'b'), throwsFormatException);
        expect(db.writes, isEmpty); expect(db.committed, isEmpty);
      });
    }
  }
  for (final patch in <sdk.Data>[{'createdBy': 'a/b'}, {'currentWeek': '1'}, {'createdAt': null}, {'mode': 'invalid'}]) {
    test('strict prewrite group rejects $patch', () async {
      db.documents['groups/g']!.addAll(patch);
      await expectLater(gateway.remove('g', 'b'), throwsFormatException); expect(db.writes, isEmpty);
    });
  }
  for (final patch in <sdk.Data>[{'displayName': ' '}, {'createdAt': DateTime.utc(2026)}, {'email': 'private'}]) {
    test('malformed optional shared display rejects $patch before any write', () async {
      db.documents[sharedPath] = {...profile(), ...patch};
      await expectLater(gateway.remove('g', 'b'), throwsFormatException); expect(db.writes, isEmpty);
    });
  }
  for (final path in ['users/a', 'groups/g', actorPath, targetPath, sharedPath]) {
    for (final pending in [false, true]) {
      test('${pending ? 'pending' : 'cache'} $path rejected including absent optional display', () async {
        (pending ? db.pending : db.cached).add(path);
        await expectLater(gateway.remove('g', 'b'), throwsStateError);
        expect(db.writes, isEmpty); expect(db.committed, isEmpty);
      });
    }
    test('UID switch at $path stops old transaction writes', () async {
      db.gates[path] = Completer();
      final check = expectLater(gateway.remove('g', 'b'), throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('new');
      db.gates[path]!.complete(); await check;
      expect(db.writes, isEmpty); expect(db.committed, isEmpty);
    });
  }
  test('signout before request does not read or impersonate actor', () {
    auth.currentUser = null;
    expect(() => gateway.leave('g'), throwsFormatException);
    expect(() => gateway.remove('g', 'b'), throwsFormatException); expect(db.reads, isEmpty);
  });
  test('UID changed during failed read replaces prior account error', () async {
    db.gates[targetPath] = Completer(); db.errors[targetPath] = const FormatException('old');
    final check = expectLater(gateway.remove('g', 'b'), throwsStateError);
    await chat.flush(); auth.currentUser = sdk.SdkUser('new');
    db.gates[targetPath]!.complete(); await check; expect(db.writes, isEmpty);
  });
  test('UID changed before transaction retry aborts retry', () async {
    db.attempts = 2; db.beforeAttempt = (i) { if (i == 1) auth.currentUser = sdk.SdkUser('new'); };
    await expectLater(gateway.remove('g', 'b'), throwsStateError);
    expect(db.writes, isEmpty); expect(db.committed, isEmpty);
  });
  test('role revoked on retry rechecks actual prewrite role no partial commit', () async {
    db.attempts = 2; db.beforeAttempt = (i) { if (i == 1) db.documents[actorPath]!['role'] = 'member'; };
    await expectLater(gateway.remove('g', 'b'), throwsFormatException);
    expect(db.reads.where((p) => p == actorPath).length, 2);
    expect(db.writes, isEmpty); expect(db.committed, isEmpty); expect(db.documents[targetPath], isNotNull);
  });
  test('target promoted on lead retry blocks removal', () async {
    db.documents[actorPath]!['role'] = 'group_lead'; db.attempts = 2;
    db.beforeAttempt = (i) { if (i == 1) db.documents[targetPath]!['role'] = 'group_lead'; };
    await expectLater(gateway.remove('g', 'b'), throwsFormatException); expect(db.writes, isEmpty);
  });
  test('creator changed on retry blocks removal', () async {
    db.attempts = 2; db.beforeAttempt = (i) { if (i == 1) db.documents['groups/g']!['createdBy'] = 'b'; };
    await expectLater(gateway.remove('g', 'b'), throwsFormatException); expect(db.writes, isEmpty);
  });
  test('successful retry rereads all optional display and stages one commit only', () async {
    db.attempts = 2; db.beforeAttempt = (i) { if (i == 1) db.documents[sharedPath] = profile(); };
    await gateway.remove('g', 'b');
    expect(db.reads.where((p) => p == sharedPath).length, 2);
    expect(db.writes.length, 1); expect(db.committed, contains(sharedPath));
  });
  test('history retained exactly and no private index/departure/profile-other reads', () async {
    final history = Map<String, sdk.Data>.fromEntries(db.documents.entries.where((e) => e.key.contains('/readingWeeks/') || e.key.contains('/messages/') || e.key.contains('/highlights/')));
    await gateway.remove('g', 'b');
    for (final entry in history.entries) { expect(db.documents[entry.key], entry.value); }
    expect(db.reads, isNot(contains(indexPath))); expect(db.reads, contains(markerPath));
    expect(db.reads, isNot(contains('users/b')));
    expect(db.committed.any((p) => history.containsKey(p)), isFalse);
  });
  test('duplicate call target no longer member fails not fake success', () async {
    await gateway.remove('g', 'b');
    await expectLater(gateway.remove('g', 'b'), throwsFormatException);
    expect(db.writes.length, 1);
  });
  for (final inconsistent in ['marker', 'index']) {
    test('coordinated $inconsistent failure modeled at commit no partial membership delete', () async {
      if (inconsistent == 'marker') {
        db.documents[markerPath] = {'immutable': true};
      } else {
        db.documents.remove(indexPath);
      }
      await expectLater(gateway.remove('g', 'b'), inconsistent == 'marker' ? throwsFormatException : throwsA(isA<FirebaseException>()));
      expect(db.writes, isEmpty); expect(db.committed, isEmpty); expect(db.documents[targetPath], isNotNull);
      expect(db.reads, isNot(contains(indexPath))); expect(db.reads, contains(markerPath));
    });
  }
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code commit not acknowledged and no partial staged application', () async {
      db.errors['commit'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.remove('g', 'b'), throwsA(isA<FirebaseException>()));
      expect(db.writes, isEmpty); expect(db.committed, isEmpty); expect(db.documents[targetPath], isNotNull);
    });
  }
  test('account changed during ACK discards response even if old write committed', () async {
    db.gates['commit'] = Completer();
    final check = expectLater(gateway.remove('g', 'b'), throwsStateError);
    await chat.flush(); auth.currentUser = sdk.SdkUser('new'); db.gates['commit']!.complete(); await check;
    expect(db.writes.length, 1); // No rollback claim after old SDK commit.
  });
  test('poisoned server snapshot path fails closed', () async {
    db.poisonPath = 'users/other';
    await expectLater(gateway.remove('g', 'b'), throwsFormatException); expect(db.writes, isEmpty);
  });
  group('restoration', () {
    late admin.AdminDb store;
    late FirestoreMembershipGateway service;
    FirebaseDeparture baseline() => FirebaseDeparture.parse('g', 'b', Map.of(store.documents[markerPath]!));
    setUp(() {
      store = admin.AdminDb(); admin.seed(store);
      store.documents.remove(targetPath);
      store.documents[markerPath] = {'userId': 'b', 'removedBy': 'a', 'removedAt': instant, 'reason': 'removed'};
      service = FirestoreMembershipGateway(auth, store);
    });
    test('review and four-write transaction preserve exact before-image, fresh ordinary role and discovery', () async {
      final original = Map.of(store.documents[markerPath]!);
      final confirmed = await service.departure('g', 'b');
      await service.restore(confirmed);
      expect(store.writes.length, 4);
      expect(store.documents['$markerPath/versions/0'], original);
      expect(store.documents[targetPath]!['role'], 'member');
      expect(store.documents[targetPath]!['joinedAt'], store.documents[indexPath]!['joinedAt']);
      expect(store.documents[markerPath]!['restored'], true);
      expect(store.reads, isNot(contains('users/b'))); expect(store.reads, isNot(contains(indexPath)));
      expect(store.documents.containsKey(sharedPath), false);
    });
    for (final race in ['role', 'account', 'member', 'revision', 'timestamp', 'archive']) {
      test('retry rechecks $race and discards all writes', () async {
        final old = baseline(); store.attempts = 2;
        store.beforeAttempt = (attempt) {
          if (attempt == 0) return;
          if (race == 'role') store.documents[actorPath]!['role'] = 'member';
          if (race == 'account') auth.currentUser = sdk.SdkUser('other');
          if (race == 'member') store.documents[targetPath] = member('b', 'member');
          if (race == 'timestamp') store.documents[markerPath]!['removedAt'] = Timestamp(instant.seconds, instant.nanoseconds + 1);
          if (race == 'revision') store.documents[markerPath]!.addAll({'restored': false, 'revision': 2, 'changedBy': 'a', 'changedAt': instant});
          if (race == 'archive') {
            store.documents['groups/g']!.addAll({'archived': true, 'lifecycleRevision': 1,
              'lifecycleChangedBy': 'a', 'lifecycleChangedAt': instant});
          }
        };
        await expectLater(service.restore(old), race == 'account' ? throwsStateError : throwsFormatException);
        expect(store.writes, isEmpty); expect(store.documents.containsKey('$markerPath/versions/0'), false);
      });
    }
    for (final path in ['groups/g', actorPath, targetPath, markerPath, '$markerPath/versions/0']) {
      test('pending $path aborts restoration', () async {
        store.pending.add(path);
        await expectLater(service.restore(baseline()), throwsStateError); expect(store.writes, isEmpty);
      });
    }
    test('commit failure remains unacknowledged with no partial history or membership', () async {
      store.errors['commit'] = StateError('unavailable');
      await expectLater(service.restore(baseline()), throwsStateError);
      expect(store.writes, isEmpty); expect(store.documents.containsKey(targetPath), false);
      expect(store.documents.containsKey('$markerPath/versions/0'), false);
    });
    test('departure parser rejects incomplete and malformed lifecycle metadata', () {
      final raw = {...store.documents[markerPath]!, 'restored': false, 'revision': 2, 'changedBy': 'a', 'changedAt': instant};
      for (final field in ['restored', 'revision', 'changedBy', 'changedAt']) {
        expect(() => FirebaseDeparture.parse('g', 'b', Map.of(raw)..remove(field)), throwsFormatException);
      }
      for (final patch in [{'restored': 1}, {'revision': 0}, {'revision': 2147483648}, {'changedAt': null}, {'changedBy': ''}]) {
        expect(() => FirebaseDeparture.parse('g', 'b', {...raw, ...patch}), throwsFormatException);
      }
    });
  });
}