// SDK-shaped doubles verify Dart validation, staged writes and simulated retry
// handling only. Real SDK transport, rules and transaction ACKs are NOT verified.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_group_admin/data/firebase_group_admin_models.dart';
import 'package:om_sai_ram/features/firebase_group_admin/data/firestore_group_admin_gateway.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;
import 'firebase_groups_test.dart' as groups;

const groupPath = 'groups/g', actorPath = 'groups/g/members/a', targetPath = 'groups/g/members/b';
final instant = Timestamp(1700000000, 123456789);
sdk.Data member(String uid, String role) => {'userId': uid, 'role': role, 'joinedAt': instant};

class AdminDb extends chat.ChatDb {
  int attempts = 1;
  void Function(int)? beforeAttempt;
  @override
  Future<chat.ChatSnapshot> read(String path, GetOptions? options) async {
    final result = await super.read(path, options);
    return chat.ChatSnapshot(this, poisonPath ?? path, result.raw, result.metadata);
  }
  @override
  Future<T> runTransaction<T>(Future<T> Function(Transaction) handler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    transactions++;
    for (var i = 0; i < attempts; i++) {
      beforeAttempt?.call(i);
      final transaction = AdminTransaction(this);
      final result = await handler(transaction);
      if (i < attempts - 1) continue;
      if (gates['commit'] != null) await gates['commit']!.future;
      if (errors['commit'] != null) throw errors['commit']!;
      for (final update in transaction.updates) {
        documents[update.path]!.addAll(update.data.map((key, value) =>
          MapEntry(key, value is FieldValue ? Timestamp(instant.seconds + 1, instant.nanoseconds) : value)));
      }
      writes.addAll(transaction.updates);
      for (final created in transaction.creates) {
        documents[created.path] = created.data.map((key, value) =>
          MapEntry(key, value is FieldValue ? Timestamp(instant.seconds + 1, instant.nanoseconds) : value));
      }
      writes.addAll(transaction.creates);
      return result;
    }
    throw StateError('No transaction attempt.');
  }
}
class AdminTransaction extends sdk.SdkTransaction {
  final updates = <({String path, sdk.Data data, bool transaction})>[];
  final creates = <({String path, sdk.Data data, bool transaction})>[];
  AdminTransaction(AdminDb super.db);
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> reference) {
    if (updates.isNotEmpty || creates.isNotEmpty) throw StateError('Read after write.');
    return super.get(reference);
  }
  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    updates.add((path: reference.path, data: data.map((key, value) => MapEntry(key as String, value)), transaction: true));
    return this;
  }
  @override
  Transaction set<T>(DocumentReference<T> reference, T data, [SetOptions? options]) {
    creates.add((path: reference.path, data: Map<String, dynamic>.from(data as Map), transaction: true));
    return this;
  }
}
void seed(AdminDb db) {
  db.documents.addAll({
    'users/a': {'displayName': 'Private', 'createdAt': instant, 'updatedAt': instant},
    groupPath: {...groups.groupData(), 'createdBy': 'creator', 'updatedAt': instant},
    actorPath: member('a', 'admin'), targetPath: member('b', 'member'),
  });
}
FirebaseGroupSettingsSnapshot baseline(AdminDb db) => FirebaseGroupSettingsSnapshot.parse('g', Map.of(db.documents[groupPath]!));
FirebaseGroupSettingsDraft draft() => FirebaseGroupSettingsDraft(' New name ', ' New description ', chaptersPerWeek: 48, startChapter: 53);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AdminDb db;
  late sdk.SdkAuth auth;
  late FirestoreGroupAdminGateway gateway;
  setUp(() { db = AdminDb(); seed(db); auth = sdk.SdkAuth(); gateway = FirestoreGroupAdminGateway(auth, db); });

  test('ownership handover preserves creator and membership dates with four atomic writes', () async {
    db.documents[groupPath]!['createdBy'] = 'a';
    final original = Map.of(db.documents[groupPath]!);
    final target = FirebaseMembership.parse('b', db.documents[targetPath]);
    await gateway.transferOwnership(baseline(db), target);
    expect(db.writes.length, 4); expect(db.documents[groupPath]!['createdBy'], 'a');
    expect(db.documents[groupPath]!['createdAt'], original['createdAt']);
    expect(db.documents[groupPath]!['ownerUid'], 'b');
    expect(db.documents[actorPath]!['role'], 'group_lead'); expect(db.documents[targetPath]!['role'], 'admin');
    expect(db.documents[targetPath]!['joinedAt'], target.joinedAtToken);
    expect(db.documents['groups/g/ownershipChanges/1']!['fromOwner'], 'a');
  });
  test('ownership commit failure leaves all four documents unchanged', () async {
    db.documents[groupPath]!['createdBy'] = 'a';
    final original = Map.of(db.documents[groupPath]!); db.errors['commit'] = StateError('unavailable');
    await expectLater(gateway.transferOwnership(baseline(db), FirebaseMembership.parse('b', db.documents[targetPath])), throwsStateError);
    expect(db.writes, isEmpty); expect(db.documents[groupPath], original);
    expect(db.documents[actorPath]!['role'], 'admin'); expect(db.documents[targetPath]!['role'], 'member');
  });
  test('ownership metadata is optional for legacy groups, otherwise complete and typed', () {
    expect(baseline(db).group.ownerUid, db.documents[groupPath]!['createdBy']);
    final raw = {...db.documents[groupPath]!, 'ownerUid': 'b', 'ownershipRevision': 1,
      'ownershipChangedBy': 'a', 'ownershipChangedAt': instant};
    for (final key in ['ownerUid', 'ownershipRevision', 'ownershipChangedBy', 'ownershipChangedAt']) {
      expect(() => FirebaseGroup.parse('g', Map.of(raw)..remove(key)), throwsFormatException);
    }
    for (final patch in [{'ownerUid': ''}, {'ownershipRevision': 0}, {'ownershipRevision': 2147483648},
      {'ownershipChangedBy': ''}, {'ownershipChangedAt': null}]) {
      expect(() => FirebaseGroup.parse('g', {...raw, ...patch}), throwsFormatException);
    }
  });
  for (final race in ['account', 'owner', 'role', 'join', 'updatedAt', 'target', 'archive']) {
    test('ownership retry rejects changed $race without partial writes', () async {
      db.documents[groupPath]!['createdBy'] = 'a';
      final before = baseline(db), target = FirebaseMembership.parse('b', db.documents[targetPath]);
      db.attempts = 2; db.beforeAttempt = (attempt) {
        if (attempt == 0) return;
        if (race == 'account') auth.currentUser = sdk.SdkUser('other');
        if (race == 'owner') db.documents[groupPath]!['createdBy'] = 'other';
        if (race == 'role') db.documents[targetPath]!['role'] = 'group_lead';
        if (race == 'join') db.documents[targetPath]!['joinedAt'] = Timestamp(instant.seconds, instant.nanoseconds + 1);
        if (race == 'updatedAt') db.documents[groupPath]!['updatedAt'] = Timestamp(instant.seconds, instant.nanoseconds + 1);
        if (race == 'target') db.documents.remove(targetPath);
        if (race == 'archive') {
          db.documents[groupPath]!.addAll({'archived': true, 'lifecycleRevision': 1,
            'lifecycleChangedBy': 'a', 'lifecycleChangedAt': instant});
        }
      };
      await expectLater(gateway.transferOwnership(before, target), race == 'account' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty); expect(db.documents.containsKey('groups/g/ownershipChanges/1'), false);
    });
  }

  test('archive and restore increment lifecycle only, preserving historical content', () async {
    final original = Map.of(db.documents[groupPath]!);
    await gateway.setArchived(baseline(db), true);
    expect(db.writes.single.data.keys.toSet(), {'archived', 'lifecycleRevision', 'lifecycleChangedBy', 'lifecycleChangedAt', 'updatedAt'});
    expect(db.documents[groupPath]!['archived'], true);
    expect(db.documents[groupPath]!['lifecycleRevision'], 1);
    expect(db.documents[groupPath]!['lifecycleChangedBy'], 'a');
    final archived = baseline(db);
    expect(archived.group.lifecycleChangedAt, isNotNull);
    expect(archived.group.requireWritable, throwsFormatException);
    await gateway.setArchived(archived, false);
    expect(db.documents[groupPath]!['lifecycleRevision'], 2);
    expect(db.documents[groupPath]!['archived'], false);
    for (final key in original.keys.where((key) => key != 'updatedAt')) {
      expect(db.documents[groupPath]![key], original[key]);
    }
  });
  for (final changed in ['actor', 'timestamp', 'revision', 'uid']) {
    test('archive retry rechecks $changed without applying stale writes', () async {
      final original = baseline(db); db.attempts = 2;
      db.beforeAttempt = (attempt) {
        if (attempt == 0) return;
        if (changed == 'actor') db.documents[actorPath]!['role'] = 'group_lead';
        if (changed == 'timestamp') db.documents[groupPath]!['updatedAt'] = Timestamp(instant.seconds, instant.nanoseconds + 1);
        if (changed == 'revision') {
          db.documents[groupPath]!.addAll({'archived': false, 'lifecycleRevision': 2,
            'lifecycleChangedBy': 'a', 'lifecycleChangedAt': instant});
        }
        if (changed == 'uid') auth.currentUser = sdk.SdkUser('other');
      };
      await expectLater(gateway.setArchived(original, true), changed == 'uid' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  test('archived group rejects ordinary admin writes but permits verified reads', () async {
    db.documents[groupPath]!.addAll({'archived': true, 'lifecycleRevision': 1,
      'lifecycleChangedBy': 'a', 'lifecycleChangedAt': instant});
    expect((await gateway.load('g')).group.archived, true);
    await expectLater(gateway.save(baseline(db), draft()), throwsFormatException);
    await expectLater(gateway.addMember('g', 'new'), throwsFormatException);
    await expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
    expect(db.writes, isEmpty);
  });
  test('strict lifecycle parser accepts legacy but rejects partial, malformed and unknown metadata', () {
    expect(baseline(db).group.lifecycleRevision, 0);
    final lifecycle = {'archived': true, 'lifecycleRevision': 1, 'lifecycleChangedBy': 'a', 'lifecycleChangedAt': instant};
    final raw = {...db.documents[groupPath]!, ...lifecycle};
    for (final key in lifecycle.keys) {
      final partial = Map<String, dynamic>.of(raw)..remove(key);
      expect(() => FirebaseGroup.parse('g', partial), throwsFormatException);
    }
    for (final patch in <sdk.Data>[{'archived': 1}, {'lifecycleRevision': 0}, {'lifecycleRevision': 2147483648},
      {'lifecycleRevision': 1.5}, {'lifecycleChangedBy': ''}, {'lifecycleChangedAt': Timestamp(instant.seconds, instant.nanoseconds + 1)}, {'unknown': true}]) {
      expect(() => FirebaseGroup.parse('g', {...raw, ...patch}), throwsFormatException);
    }
  });

  test('add atomically stages only member and discovery with no target profile or index read', () async {
    db.documents.remove(targetPath);
    await gateway.addMember('g', 'b');
    expect(db.reads, ['users/a', groupPath, actorPath, targetPath, 'groups/g/departures/b']);
    expect(db.writes.map((write) => write.path), [targetPath, 'users/b/groups/g']);
    expect(db.writes.first.data, {'userId': 'b', 'role': 'member', 'joinedAt': FieldValue.serverTimestamp()});
    expect(db.writes.last.data, {'groupId': 'g', 'joinedAt': FieldValue.serverTimestamp()});
    expect(db.writes, everyElement(predicate((dynamic write) => write.transaction == true)));
    expect(db.reads, isNot(contains('users/b')));
    expect(db.reads, isNot(contains('users/b/groups/g')));
  });
  for (final reason in ['duplicate', 'departure', 'member', 'group_lead']) {
    test('add rejects $reason without staged commits', () async {
      if (reason != 'duplicate') db.documents.remove(targetPath);
      if (reason == 'departure') db.documents['groups/g/departures/b'] = {};
      if (reason == 'member' || reason == 'group_lead') db.documents[actorPath]!['role'] = reason;
      await expectLater(gateway.addMember('g', 'b'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final change in ['actor', 'duplicate', 'departure', 'uid']) {
    test('add retry rechecks $change and never applies stale staged writes', () async {
      db.documents.remove(targetPath); db.attempts = 2;
      db.beforeAttempt = (attempt) {
        if (attempt == 0) return;
        if (change == 'actor') db.documents[actorPath]!['role'] = 'group_lead';
        if (change == 'duplicate') db.documents[targetPath] = member('b', 'group_lead');
        if (change == 'departure') db.documents['groups/g/departures/b'] = {};
        if (change == 'uid') auth.currentUser = sdk.SdkUser('other');
      };
      await expectLater(gateway.addMember('g', 'b'), change == 'uid' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  test('add commit denial does not acknowledge or create partial member discovery', () async {
    db.documents.remove(targetPath);
    db.errors['commit'] = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await expectLater(gateway.addMember('g', 'b'), throwsA(isA<FirebaseException>()));
    expect(db.writes, isEmpty);
    expect(db.documents.containsKey(targetPath), isFalse);
    expect(db.documents.containsKey('users/b/groups/g'), isFalse);
  });
  test('invalid target and self fail before profile lookup', () async {
    for (final target in ['a', '', '..', 'x/y', '__reserved__']) {
      await expectLater(gateway.addMember('g', target), throwsFormatException);
    }
    expect(db.reads, isEmpty);
  });
  test('load server-only exact group and actor, raw token preserves nanoseconds', () async {
    final snapshot = await gateway.load('g');
    expect(db.reads, ['users/a', groupPath, actorPath]);
    expect(db.sources, everyElement(Source.server));
    expect(identical(snapshot.updatedAt, instant), isTrue);
    expect(snapshot.updatedAt.nanoseconds, 123456789);
    expect(snapshot.group.updatedAt.microsecond, isNot(789));
  });
  test('save reads exact group actor INSIDE transaction and updates only five fields', () async {
    final original = Map.of(db.documents[groupPath]!);
    await gateway.save(baseline(db), draft());
    expect(db.reads, ['users/a', groupPath, actorPath]);
    expect(db.sources, [Source.server, null, null]);
    expect(db.transactions, 1);
    expect(db.writes.single.path, groupPath);
    expect(db.writes.single.transaction, isTrue);
    expect(db.writes.single.data, {
      'name': 'New name', 'description': 'New description', 'chaptersPerWeek': 48,
      'startChapter': 53, 'updatedAt': FieldValue.serverTimestamp()});
    for (final key in ['createdAt', 'createdBy', 'mode', 'currentWeek']) {
      expect(db.writes.single.data.containsKey(key), isFalse);
      expect(db.documents[groupPath]![key], original[key]);
    }
  });
  for (final expected in [FirebaseGroupRole.member, FirebaseGroupRole.groupLead]) {
    test('expected ${expected.name} transitions only role, immutable membership retained', () async {
      db.documents[targetPath]!['role'] = expected == FirebaseGroupRole.member ? 'member' : 'group_lead';
      final original = Map.of(db.documents[targetPath]!);
      final next = expected == FirebaseGroupRole.member ? FirebaseGroupRole.groupLead : FirebaseGroupRole.member;
      await gateway.changeRole('g', 'b', expected, next);
      expect(db.reads, ['users/a', groupPath, actorPath, targetPath]);
      expect(db.sources, [Source.server, null, null, null]);
      expect(db.writes.single.path, targetPath);
      expect(db.writes.single.transaction, isTrue);
      expect(db.writes.single.data, {'role': next == FirebaseGroupRole.member ? 'member' : 'group_lead'});
      expect(db.documents[targetPath]!['userId'], original['userId']);
      expect(db.documents[targetPath]!['joinedAt'], original['joinedAt']);
      expect(db.documents[groupPath]!['updatedAt'], instant);
      expect(db.reads, isNot(contains('users/b')));
    });
  }
  for (final role in ['member', 'group_lead']) {
    for (final operation in ['load', 'save', 'role']) {
      test('$operation rejects actual actor $role', () async {
        db.documents[actorPath]!['role'] = role;
        final request = operation == 'load' ? gateway.load('g') : operation == 'save'
          ? gateway.save(baseline(db), draft()) : gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead);
        await expectLater(request, throwsFormatException); expect(db.writes, isEmpty);
      });
    }
  }
  for (final expected in FirebaseGroupRole.values) {
    for (final next in FirebaseGroupRole.values) {
      if (expected != FirebaseGroupRole.admin && next != FirebaseGroupRole.admin && expected != next) continue;
      test('reject ${expected.name} -> ${next.name} before any SDK call', () async {
        await expectLater(gateway.changeRole('g', 'b', expected, next), throwsFormatException);
        expect(db.reads, isEmpty); expect(db.writes, isEmpty);
      });
    }
  }
  for (final protected in ['creator', 'admin', 'self']) {
    test('$protected immune to role changes', () async {
      if (protected == 'creator') db.documents[groupPath]!['createdBy'] = 'b';
      if (protected == 'admin') db.documents[targetPath]!['role'] = 'admin';
      await expectLater(gateway.changeRole('g', protected == 'self' ? 'a' : 'b',
        FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final bad in ['', '.', '..', 'x/y', '__reserved__', 'é' * 751]) {
    test('invalid path length ${bad.length} denied before SDK', () async {
      await expectLater(gateway.load(bad), throwsFormatException);
      await expectLater(gateway.changeRole(bad, 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
      await expectLater(gateway.changeRole('g', bad, FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  for (final path in ['users/a', groupPath, actorPath, targetPath]) {
    for (final kind in ['missing', 'extra', 'cache', 'pending', 'path']) {
      test('$kind $path rejects role transaction no writes', () async {
        if (kind == 'missing') db.documents.remove(path);
        if (kind == 'extra') db.documents[path]!['email'] = 'private';
        if (kind == 'cache') db.cached.add(path);
        if (kind == 'pending') db.pending.add(path);
        if (kind == 'path') db.poisonPath = 'other/path';
        await expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead),
          kind == 'cache' || kind == 'pending' ? throwsStateError : throwsFormatException);
        expect(db.writes, isEmpty);
      });
    }
    test('UID changes during $path await prevents write', () async {
      db.gates[path] = Completer();
      final request = expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('new'); db.gates[path]!.complete(); await request;
      expect(db.writes, isEmpty);
    });
    test('UID changes during failed $path read suppresses old error', () async {
      db.gates[path] = Completer(); db.errors[path] = const FormatException('old account error');
      final request = expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsStateError);
      await chat.flush(); auth.currentUser = null; db.gates[path]!.complete(); await request;
      expect(db.writes, isEmpty);
    });
  }
  for (final path in [actorPath, targetPath]) {
    for (final patch in <sdk.Data>[{'role': 'owner'}, {'role': null}, {'userId': 'other'}, {'joinedAt': DateTime.utc(2026)}]) {
      test('strict membership $path rejects $patch', () async {
        db.documents[path]!.addAll(patch);
        await expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
        expect(db.writes, isEmpty);
      });
    }
  }
  for (final patch in <sdk.Data>[{'createdBy': '__reserved__'}, {'mode': 'invalid'}, {'currentWeek': '1'}, {'updatedAt': DateTime.utc(2026)}, {'createdAt': null}]) {
    test('strict group rejects $patch', () async {
      db.documents[groupPath]!.addAll(patch);
      await expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  test('Timestamp differs by ONE nanosecond stale settings rejected no lost edit', () async {
    final original = baseline(db);
    db.documents[groupPath]!.addAll({'name': 'Concurrent edit', 'updatedAt': Timestamp(instant.seconds, instant.nanoseconds + 1)});
    await expectLater(gateway.save(original, draft()), throwsFormatException);
    expect(db.writes, isEmpty); expect(db.documents[groupPath]!['name'], 'Concurrent edit');
  });
  test('DateTime roundtrip cannot replace raw token', () async {
    final original = baseline(db);
    db.documents[groupPath]!['updatedAt'] = Timestamp.fromDate(original.group.updatedAt);
    await expectLater(gateway.save(original, draft()), throwsFormatException); expect(db.writes, isEmpty);
  });
  for (final changed in ['actor', 'timestamp', 'uid']) {
    test('save retry revalidates $changed discards first staged write', () async {
      final original = baseline(db); db.attempts = 2;
      db.beforeAttempt = (i) {
        if (i == 0) return;
        if (changed == 'actor') db.documents[actorPath]!['role'] = 'group_lead';
        if (changed == 'timestamp') db.documents[groupPath]!['updatedAt'] = Timestamp(instant.seconds, instant.nanoseconds + 1);
        if (changed == 'mode') db.documents[groupPath]!['mode'] = 'saptah';
        if (changed == 'uid') auth.currentUser = sdk.SdkUser('new');
      };
      await expectLater(gateway.save(original, draft()), changed == 'uid' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final changed in ['actor', 'target', 'creator', 'uid']) {
    test('role retry revalidates $changed no toggle by race', () async {
      db.attempts = 2;
      db.beforeAttempt = (i) {
        if (i == 0) return;
        if (changed == 'actor') db.documents[actorPath]!['role'] = 'member';
        if (changed == 'target') db.documents[targetPath]!['role'] = 'group_lead';
        if (changed == 'creator') db.documents[groupPath]!['createdBy'] = 'b';
        if (changed == 'uid') auth.currentUser = sdk.SdkUser('new');
      };
      await expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead),
        changed == 'uid' ? throwsStateError : throwsFormatException); expect(db.writes, isEmpty);
    });
  }
  for (final settings in [false, true]) {
    test('successful ${settings ? 'settings' : 'role'} retry only one commit', () async {
      db.attempts = 2;
      if (settings) { await gateway.save(baseline(db), draft()); }
      else { await gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead); }
      expect(db.writes.length, 1); expect(db.reads.where((p) => p == actorPath).length, 2);
    });
    for (final code in ['permission-denied', 'unavailable']) {
      test('${settings ? 'settings' : 'role'} $code commit not acknowledged no staged application', () async {
        db.errors['commit'] = FirebaseException(plugin: 'cloud_firestore', code: code);
        final original = Map.of(db.documents[groupPath]!);
        await expectLater(settings ? gateway.save(baseline(db), draft()) :
          gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsA(isA<FirebaseException>()));
        expect(db.writes, isEmpty); expect(db.documents[groupPath], original); expect(db.documents[targetPath]!['role'], 'member');
      });
    }
    test('account changed during ${settings ? 'settings' : 'role'} ACK discards response not rollback', () async {
      db.gates['commit'] = Completer();
      final request = expectLater(settings ? gateway.save(baseline(db), draft()) :
        gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('new'); db.gates['commit']!.complete(); await request;
      expect(db.writes.length, 1);
    });
  }
  test('saptah label saves width and start like chapter-wise and keeps its mode', () async {
    db.documents[groupPath]!.addAll({'mode': 'saptah', 'chaptersPerWeek': 53});
    await gateway.save(baseline(db), draft());
    expect(db.writes.single.data.keys, containsAll(['name', 'description', 'chaptersPerWeek', 'startChapter', 'updatedAt']));
    expect(db.writes.single.data.containsKey('mode'), isFalse); expect(db.documents[groupPath]!['mode'], 'saptah');
  });
  for (final mode in ['saptah', 'chapter_wise']) {
    test('$mode draft without width and start fails before SDK', () async {
      db.documents[groupPath]!['mode'] = mode;
      await expectLater(gateway.save(baseline(db), FirebaseGroupSettingsDraft('Name', '')), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  for (final values in <({String name, String description, int? width, int? start})>[
    (name: ' ', description: '', width: 1, start: 1),
    (name: 'x' * 101, description: '', width: 1, start: 1),
    (name: 'Name', description: 'x' * 1001, width: 1, start: 1),
    (name: 'Name', description: '', width: 0, start: 1),
    (name: 'Name', description: '', width: 49, start: 1),
    (name: 'Name', description: '', width: 1, start: 0),
    (name: 'Name', description: '', width: 1, start: 54),
    (name: 'Name', description: '', width: null, start: 1),
    (name: 'Name', description: '', width: 1, start: null),
  ]) {
    test('strict draft lengths ${values.name.length}/${values.description.length} bounds ${values.width}/${values.start}', () {
      expect(() => FirebaseGroupSettingsDraft(values.name, values.description,
        chaptersPerWeek: values.width, startChapter: values.start), throwsFormatException); expect(db.reads, isEmpty);
    });
  }
  test('draft accepts exact string and number limits and trims', () {
    final value = FirebaseGroupSettingsDraft(' ${'x' * 100} ', ' ${'y' * 1000} ', chaptersPerWeek: 1, startChapter: 1);
    expect(value.name.length, 100); expect(value.description.length, 1000);
    expect(draft().chaptersPerWeek, 48); expect(draft().startChapter, 53);
  });
  test('logged out identity cannot trigger reads', () async {
    auth.currentUser = null;
    await expectLater(gateway.load('g'), throwsFormatException);
    await expectLater(gateway.save(baseline(db), draft()), throwsFormatException);
    await expectLater(gateway.changeRole('g', 'b', FirebaseGroupRole.member, FirebaseGroupRole.groupLead), throwsFormatException);
    expect(db.reads, isEmpty);
  });
  for (final role in [FirebaseGroupRole.member, FirebaseGroupRole.groupLead]) {
    test('already changed ${role.name} rejects stale expected role without toggling', () async {
      db.documents[targetPath]!['role'] = role == FirebaseGroupRole.member ? 'group_lead' : 'member';
      final unchanged = Map.of(db.documents[targetPath]!);
      await expectLater(gateway.changeRole('g', 'b', role,
        role == FirebaseGroupRole.member ? FirebaseGroupRole.groupLead : FirebaseGroupRole.member), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.documents[targetPath], unchanged);
    });
  }
  for (final operation in ['load', 'save']) {
    for (final path in ['users/a', groupPath, actorPath]) {
      for (final pending in [false, true]) {
        test('$operation rejects ${pending ? 'pending' : 'cache'} $path no stale settings authority', () async {
          (pending ? db.pending : db.cached).add(path);
          await expectLater(operation == 'load' ? gateway.load('g') : gateway.save(baseline(db), draft()), throwsStateError);
          expect(db.writes, isEmpty);
        });
      }
      test('$operation captures SDK uid across $path await', () async {
        db.gates[path] = Completer();
        final request = expectLater(operation == 'load' ? gateway.load('g') : gateway.save(baseline(db), draft()), throwsStateError);
        await chat.flush(); auth.currentUser = sdk.SdkUser('new'); db.gates[path]!.complete(); await request;
        expect(db.writes, isEmpty);
      });
    }
  }
}