// SDK-shaped test doubles only; production code does not subclass SDK types.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firebase_assignment_models.dart';
import 'package:om_sai_ram/features/firebase_assignments/data/firestore_assignments_gateway.dart';
import 'firebase_assignments_test.dart' as assignments_test;
import 'firebase_groups_test.dart' as groups_test;

typedef Data = Map<String, dynamic>;

class SdkUser extends Fake implements User {
  @override
  final String uid;
  SdkUser(this.uid);
}

class SdkAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = SdkUser('a');
}

class Metadata extends Fake implements SnapshotMetadata {
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
  Metadata({this.isFromCache = false, this.hasPendingWrites = false});
}

class Snapshot extends Fake implements DocumentSnapshot<Data> {
  @override
  final String id;
  final Data? raw;
  @override
  final SnapshotMetadata metadata;
  Snapshot(this.id, this.raw, this.metadata);
  @override
  bool get exists => raw != null;
  @override
  Data? data() => raw;
}

class QueryDocument extends Snapshot implements QueryDocumentSnapshot<Data> {
  QueryDocument(super.id, super.raw, super.metadata);
  @override
  Data data() => raw!;
}

class QueryResult extends Fake implements QuerySnapshot<Data> {
  @override
  final List<QueryDocumentSnapshot<Data>> docs;
  @override
  final SnapshotMetadata metadata;
  QueryResult(this.docs, this.metadata);
}

/// Controlled SDK-shaped doubles test calls/checks, NOT rules or real server
/// transaction atomicity, retries, auth tokens, or network behaviour.
class SdkDb extends Fake implements FirebaseFirestore {
  final documents = <String, Data>{};
  final reads = <String>[];
  final sources = <Source?>[];
  final writes = <({String path, Data data, bool transaction})>[];
  final cached = <String>{}, pending = <String>{};
  final gates = <String, Completer<void>>{};
  final errors = <String, Object>{};
  Object? orderedField;
  int? queryLimit;
  String? queryPath;
  bool queryCached = false, queryPending = false;
  String? poisonId;
  int transactions = 0;
  @override
  CollectionReference<Data> collection(String path) =>
      SdkCollection(this, path);
  Metadata metadata(String path) => Metadata(
      isFromCache: cached.contains(path),
      hasPendingWrites: pending.contains(path));
  Future<Snapshot> read(String path, GetOptions? options) async {
    reads.add(path);
    sources.add(options?.source);
    if (gates[path] != null) await gates[path]!.future;
    if (errors[path] != null) throw errors[path]!;
    return Snapshot(path.split('/').last, documents[path], metadata(path));
  }

  @override
  Future<T> runTransaction<T>(
      Future<T> Function(Transaction) transactionHandler,
      {Duration timeout = const Duration(seconds: 30),
      int maxAttempts = 5}) async {
    transactions++;
    return transactionHandler(SdkTransaction(this));
  }
}

class SdkCollection extends Fake implements CollectionReference<Data> {
  final SdkDb db;
  @override
  final String path;
  SdkCollection(this.db, this.path);
  @override
  DocumentReference<Data> doc([String? path]) =>
      SdkDocument(db, '${this.path}/$path');
  @override
  Query<Data> orderBy(Object field, {bool descending = false}) {
    db.orderedField = field;
    return SdkQuery(db, path);
  }
}

class SdkDocument extends Fake implements DocumentReference<Data> {
  final SdkDb db;
  @override
  final String path;
  SdkDocument(this.db, this.path);
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Data> collection(String collectionPath) =>
      SdkCollection(db, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Data>> get([GetOptions? options]) =>
      db.read(path, options);
  @override
  Future<void> update(Map<Object, Object?> data) async {
    if (db.gates['update'] != null) await db.gates['update']!.future;
    if (db.errors['update'] != null) throw db.errors['update']!;
    db.writes.add((
      path: path,
      data: data.map((key, value) => MapEntry(key as String, value)),
      transaction: false
    ));
  }
}

class SdkQuery extends Fake implements Query<Data> {
  final SdkDb db;
  final String path;
  SdkQuery(this.db, this.path);
  @override
  Query<Data> limit(int limit) {
    db.queryLimit = limit;
    return this;
  }

  @override
  Future<QuerySnapshot<Data>> get([GetOptions? options]) async {
    db.queryPath = path;
    db.sources.add(options?.source);
    if (db.gates['query'] != null) await db.gates['query']!.future;
    if (db.errors['query'] != null) throw db.errors['query']!;
    final entries = db.documents.entries
        .where((entry) =>
            entry.key.startsWith('$path/') &&
            !entry.key.substring(path.length + 1).contains('/'))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return QueryResult(
        entries
            .take(db.queryLimit!)
            .map((entry) => QueryDocument(
                db.poisonId ?? entry.key.split('/').last,
                entry.value,
                db.metadata(entry.key)))
            .toList(),
        Metadata(
            isFromCache: db.queryCached, hasPendingWrites: db.queryPending));
  }
}

class SdkTransaction extends Fake implements Transaction {
  final SdkDb db;
  SdkTransaction(this.db);
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
          DocumentReference<T> reference) async =>
      await db.read(reference.path, null) as DocumentSnapshot<T>;
  @override
  Transaction set<T>(DocumentReference<T> reference, T data,
      [SetOptions? options]) {
    db.writes
        .add((path: reference.path, data: data as Data, transaction: true));
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const own = assignments_test.own;
  const other = assignments_test.other;
  const collectionPath = 'groups/g/readingWeeks/1/members/a/assignments';
  const assignmentPath = '$collectionPath/16-17';
  late SdkAuth auth;
  late SdkDb db;
  late FirestoreAssignmentsGateway gateway;
  setUp(() {
    auth = SdkAuth();
    db = SdkDb();
    gateway = FirestoreAssignmentsGateway(auth, db);
    db.documents.addAll({
      'users/a': {
        'displayName': 'Private',
        'createdAt': Timestamp.fromDate(groups_test.now),
        'updatedAt': Timestamp.fromDate(groups_test.now)
      },
      'groups/g': groups_test.groupData(),
      'groups/g/members/a': {
        'userId': 'a',
        'role': 'admin',
        'joinedAt': Timestamp.fromDate(groups_test.now)
      },
      'groups/g/members/public-uid-b': {
        'userId': 'public-uid-b',
        'role': 'member',
        'joinedAt': Timestamp.fromDate(groups_test.now)
      },
      assignmentPath: assignments_test.assignmentData(),
      'groups/g/readingWeeks/1/members/public-uid-b/assignments/16-17':
          assignments_test.assignmentData(scope: other),
    });
  });
  test(
      'actual gateway uses only server source exact member/week path limit48 documentID order',
      () async {
    final result = await gateway.read(own);
    expect(db.queryPath, collectionPath);
    expect(db.queryLimit, 48);
    expect(db.orderedField, FieldPath.documentId);
    expect(db.sources.every((source) => source == Source.server), isTrue);
    expect(result.assignments.single.unit.key, '16-17');
    expect(db.reads, ['users/a', 'groups/g', 'groups/g/members/a']);
  });
  test(
      'ordinary member reads other roster progress without reading private profile',
      () async {
    db.documents['groups/g/members/a']!['role'] = 'member';
    final result = await gateway.read(other);
    expect(result.member.uid, 'public-uid-b');
    expect(db.queryPath,
        'groups/g/readingWeeks/1/members/public-uid-b/assignments');
    expect(db.reads, isNot(contains('users/public-uid-b')));
  });
  test('UID mismatch fails before any SDK database work', () async {
    auth.currentUser = SdkUser('b');
    await expectLater(gateway.read(own), throwsStateError);
    expect(db.reads, isEmpty);
  });
  for (final boundary in [
    'users/a',
    'groups/g',
    'groups/g/members/a',
    'groups/g/members/public-uid-b',
    'query'
  ]) {
    test('account switch during $boundary aborts the actual gateway', () async {
      db.gates[boundary] = Completer();
      final request = gateway.read(other);
      final expected = expectLater(request, throwsStateError);
      // Flush the deterministic sequence of immediate futures up to this gate.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      auth.currentUser = SdkUser('b');
      db.gates[boundary]!.complete();
      await expected;
      expect(db.writes, isEmpty);
    });
  }
  test('cached pending profile and malformed private profile all fail closed',
      () async {
    db.cached.add('users/a');
    await expectLater(gateway.read(own), throwsStateError);
    db.cached.clear();
    db.pending.add('users/a');
    await expectLater(gateway.read(own), throwsStateError);
    db.pending.clear();
    db.documents['users/a']!['admin'] = true;
    await expectLater(gateway.read(own), throwsFormatException);
    expect(db.queryPath, isNull);
  });
  test('missing target actual membership blocks creation', () async {
    db.documents.remove('groups/g/members/public-uid-b');
    await expectLater(
        gateway.create(other, FirebaseChapterUnit.fromChapter(1),
            scheduledDate: null),
        throwsFormatException);
    expect(db.transactions, 0);
    expect(db.writes, isEmpty);
  });
  test('creator metadata does not grant assign authority to a member',
      () async {
    db.documents['groups/g/members/a']!['role'] = 'member';
    await expectLater(
        gateway.create(own, FirebaseChapterUnit.fromChapter(1),
            scheduledDate: null),
        throwsFormatException);
    expect(db.transactions, 0);
    expect(db.writes, isEmpty);
  });
  for (final role in ['admin', 'group_lead']) {
    test(
        '$role self assignment uses transaction and eleven exact canonical fields',
        () async {
      db.documents['groups/g/members/a']!['role'] = role;
      await gateway.create(own, FirebaseChapterUnit.fromChapter(53),
          scheduledDate: null);
      expect(db.transactions, 1);
      final write = db.writes.single;
      expect(write.transaction, isTrue);
      expect(write.path, '$collectionPath/51-53');
      expect(write.data.keys.toSet(),
          assignments_test.assignmentData(chapter: 53).keys.toSet());
      expect(write.data['scheduledDate'], isNull);
      expect(write.data['createdBy'], 'a');
      expect(write.data['status'], 'not_started');
      expect(write.data['chapterStart'], 51);
      expect(write.data['chapterEnd'], 53);
      expect(write.data['createdAt'], isA<FieldValue>());
      expect(write.data['progressUpdatedAt'], isA<FieldValue>());
    });
  }
  test('duplicate transaction read prevents any metadata overwrite', () async {
    final before = Map<String, dynamic>.from(db.documents[assignmentPath]!);
    await expectLater(
        gateway.create(own, FirebaseChapterUnit.fromChapter(17),
            scheduledDate: null),
        throwsFormatException);
    expect(db.transactions, 1);
    expect(db.writes, isEmpty);
    expect(db.documents[assignmentPath], before);
  });
  test('explicit UTC date persists as timestamp without changing canonical metadata', () async {
    db.documents['groups/g/members/a']!['role'] = 'admin';
    final date = DateTime.utc(2026, 3, 8, 18, 30, 1, 123, 456);
    await gateway.create(own, FirebaseChapterUnit.fromChapter(1), scheduledDate: date);
    expect(db.writes.single.data['scheduledDate'], Timestamp.fromDate(DateTime.utc(2026, 3, 8, 18, 30, 1, 123)));
    expect(db.writes.single.data['status'], 'not_started');
    expect(db.writes.single.transaction, isTrue);
  });
  for (final date in [DateTime(2026), DateTime.utc(0), DateTime.utc(10000)]) {
    test('invalid UTC date $date rejects before SDK reads/writes', () async {
      await expectLater(gateway.create(own, FirebaseChapterUnit.fromChapter(1), scheduledDate: date), throwsFormatException);
      expect(db.reads, isEmpty); expect(db.writes, isEmpty);
    });
  }
  test(
      'only own status update writes exactly status and server progress timestamp',
      () async {
    await expectLater(
        gateway.updateStatus(other, FirebaseChapterUnit.fromChapter(16),
            FirebaseReadingStatus.completed),
        throwsFormatException);
    expect(db.reads, isEmpty);
    await gateway.updateStatus(own, FirebaseChapterUnit.fromChapter(17),
        FirebaseReadingStatus.completed);
    expect(db.transactions, 0);
    final write = db.writes.single;
    expect(write.transaction, isFalse);
    expect(write.path, assignmentPath);
    expect(write.data.keys.toSet(), {'status', 'progressUpdatedAt'});
    expect(write.data['status'], 'completed');
    expect(write.data['progressUpdatedAt'], isA<FieldValue>());
  });
  test('progress validates existing immutable metadata before issuing update',
      () async {
    db.documents[assignmentPath]!['userId'] = 'b';
    await expectLater(
        gateway.updateStatus(own, FirebaseChapterUnit.fromChapter(16),
            FirebaseReadingStatus.completed),
        throwsFormatException);
    expect(db.writes, isEmpty);
  });
  test('account switch during transaction get prevents transaction set',
      () async {
    const path = '$collectionPath/1';
    db.gates[path] = Completer();
    final request = gateway.create(own, FirebaseChapterUnit.fromChapter(1),
        scheduledDate: null);
    final expected = expectLater(request, throwsStateError);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    auth.currentUser = SdkUser('b');
    db.gates[path]!.complete();
    await expected;
    expect(db.writes, isEmpty);
  });
  test('account switch during update completion throws instead of fake success',
      () async {
    db.gates['update'] = Completer();
    final request = gateway.updateStatus(own,
        FirebaseChapterUnit.fromChapter(16), FirebaseReadingStatus.completed);
    final expected = expectLater(request, throwsStateError);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    auth.currentUser = SdkUser('b');
    db.gates['update']!.complete();
    await expected;
  });
  test('cache/pending query metadata and poisoned IDs reject the entire list',
      () async {
    db.queryCached = true;
    await expectLater(gateway.read(own), throwsStateError);
    db.queryCached = false;
    db.queryPending = true;
    await expectLater(gateway.read(own), throwsStateError);
    db.queryPending = false;
    db.poisonId = '17';
    await expectLater(gateway.read(own), throwsFormatException);
  });
  test(
      'permission and network exceptions propagate with no partial result; retry succeeds',
      () async {
    db.errors['query'] =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await expectLater(gateway.read(own), throwsA(isA<FirebaseException>()));
    db.errors['query'] = StateError('offline');
    await expectLater(gateway.read(own), throwsStateError);
    db.errors.clear();
    expect((await gateway.read(own)).assignments.length, 1);
  });
}
