import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_group_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firestore_group_reminders_gateway.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;
import 'firestore_group_admin_gateway_test.dart' as admin;

const path = 'groups/g/settings/notificationSchedule';
Map<String, dynamic> data() => {
      ...FirebaseGroupReminderDraft.defaults.toData(),
      'groupId': 'g',
      'revision': 1,
      'createdBy': 'creator',
      'updatedBy': 'a',
      'createdAt': Timestamp(100, 1),
      'updatedAt': Timestamp(101, 2)
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late admin.AdminDb db;
  late sdk.SdkAuth auth;
  late FirestoreGroupRemindersGateway gateway;
  setUp(() {
    db = admin.AdminDb();
    admin.seed(db);
    auth = sdk.SdkAuth();
    gateway = FirestoreGroupRemindersGateway(auth, db);
  });
  for (final role in ['member', 'admin', 'group_lead']) {
    test(
        '$role reads exact group/member/schedule paths server-only without private profiles or writes',
        () async {
      db.documents[admin.actorPath]!['role'] = role;
      final result = await gateway.read('g');
      expect(result.record, isNull);
      expect(result.canEdit, role != 'member');
      expect(db.reads, [admin.groupPath, admin.actorPath, path]);
      expect(db.sources, everyElement(Source.server));
      expect(db.writes, isEmpty);
    });
  }
  test(
      'create stages one exact transaction document with current SDK UID and server audit times',
      () async {
    final baseline = await gateway.read('g');
    db.reads.clear();
    db.sources.clear();
    await gateway.save(baseline, FirebaseGroupReminderDraft.defaults);
    expect(db.transactions, 1);
    expect(db.reads, [admin.groupPath, admin.actorPath, path]);
    expect(db.sources, [null, null, null]);
    final write = db.writes.single;
    expect(write.path, path);
    expect(write.transaction, true);
    expect(write.data, {
      ...FirebaseGroupReminderDraft.defaults.toData(),
      'groupId': 'g',
      'revision': 1,
      'createdBy': 'a',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': 'a',
      'updatedAt': FieldValue.serverTimestamp()
    });
    expect((await gateway.read('g')).record!.revision, 1);
  });
  test(
      'update retains creation audit precisely and advances revision, leaving other documents untouched',
      () async {
    db.documents[path] = data();
    db.documents['users/a/settings/reminders'] = {'sentinel': 'unchanged'};
    final baseline = await gateway.read('g');
    final original = Map.of(db.documents[admin.groupPath]!);
    await gateway.save(
        baseline, baseline.record!.schedule.copyWith(escalationEnabled: false));
    final write = db.writes.single.data;
    expect(write['revision'], 2);
    expect(write['createdBy'], 'creator');
    expect(write['createdAt'], Timestamp(100, 1));
    expect(write['updatedAt'], FieldValue.serverTimestamp());
    expect(write['updatedBy'], 'a');
    expect(db.documents[admin.groupPath], original);
    expect(
        db.documents['users/a/settings/reminders'], {'sentinel': 'unchanged'});
  });
  for (final kind in ['create', 'revision', 'timestamp', 'role']) {
    test('concurrent $kind changes reject stale save without committing',
        () async {
      if (kind != 'create') db.documents[path] = data();
      final baseline = await gateway.read('g');
      if (kind == 'create') db.documents[path] = data();
      if (kind == 'revision') db.documents[path]!['revision'] = 2;
      if (kind == 'timestamp') {
        db.documents[path]!['updatedAt'] = Timestamp(101, 3);
      }
      if (kind == 'role') db.documents[admin.actorPath]!['role'] = 'member';
      await expectLater(
          gateway.save(baseline, FirebaseGroupReminderDraft.defaults),
          throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final change in ['revision', 'role', 'uid']) {
    test('SDK retry rechecks $change and discards earlier staged writes',
        () async {
      db.documents[path] = data();
      final baseline = await gateway.read('g');
      db.attempts = 2;
      db.beforeAttempt = (attempt) {
        if (attempt == 0) return;
        if (change == 'revision') db.documents[path]!['revision'] = 2;
        if (change == 'role') db.documents[admin.actorPath]!['role'] = 'member';
        if (change == 'uid') auth.currentUser = sdk.SdkUser('b');
      };
      await expectLater(
          gateway.save(baseline, FirebaseGroupReminderDraft.defaults),
          change == 'uid' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final document in [admin.groupPath, admin.actorPath, path]) {
    for (final kind in ['cached', 'pending']) {
      test(
          '$kind $document rejects read and transactional save without partial results',
          () async {
        db.documents[path] = data();
        final baseline = await gateway.read('g');
        (kind == 'cached' ? db.cached : db.pending).add(document);
        await expectLater(gateway.read('g'), throwsStateError);
        await expectLater(
            gateway.save(baseline, FirebaseGroupReminderDraft.defaults),
            throwsStateError);
        expect(db.writes, isEmpty);
      });
    }
  }
  test('path mismatch and malformed group/member/schedule data fail closed',
      () async {
    db.poisonPath = 'groups/other';
    await expectLater(gateway.read('g'), throwsFormatException);
    db.poisonPath = null;
    for (final document in [admin.groupPath, admin.actorPath, path]) {
      final original = db.documents[document];
      db.documents[document] = {...?original, 'unexpected': true};
      await expectLater(gateway.read('g'), throwsFormatException);
      if (original == null) {
        db.documents.remove(document);
      } else {
        db.documents[document] = original;
      }
    }
    expect(db.writes, isEmpty);
  });
  test(
      'commit permission denial never acknowledges or persists a staged schedule',
      () async {
    final baseline = await gateway.read('g');
    db.errors['commit'] =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await expectLater(
        gateway.save(baseline, FirebaseGroupReminderDraft.defaults),
        throwsA(isA<FirebaseException>()));
    expect(db.writes, isEmpty);
    expect(db.documents.containsKey(path), false);
  });
  for (final operation in ['read', 'save']) {
    test('$operation discards a delayed SDK response after account change',
        () async {
      final baseline = await gateway.read('g');
      db.gates[admin.actorPath] = Completer<void>();
      final pending = expectLater(
          operation == 'read'
              ? gateway.read('g')
              : gateway.save(baseline, FirebaseGroupReminderDraft.defaults),
          throwsStateError);
      await chat.flush();
      auth.currentUser = sdk.SdkUser('b');
      db.gates[admin.actorPath]!.complete();
      await pending;
      expect(db.writes, isEmpty);
    });
  }
  test(
      'wrong baseline account, signed-out state and invalid path fail before SDK reads',
      () async {
    final baseline =
        FirebaseGroupReminderSnapshot('b', 'g', FirebaseGroupRole.admin, null);
    await expectLater(
        gateway.save(baseline, FirebaseGroupReminderDraft.defaults),
        throwsFormatException);
    for (final group in ['', 'a/b', '..', '__reserved__']) {
      await expectLater(gateway.read(group), throwsFormatException);
    }
    auth.currentUser = null;
    await expectLater(gateway.read('g'), throwsFormatException);
    expect(db.reads, isEmpty);
  });
}
