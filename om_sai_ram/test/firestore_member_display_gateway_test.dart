// SDK-shaped doubles: not verification of real transport, rules, or SDK retries.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firebase_member_display_models.dart';
import 'package:om_sai_ram/features/firebase_member_display/data/firestore_member_display_gateway.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;
import 'firebase_groups_test.dart' as groups;

const groupPath = 'groups/g', memberPath = 'groups/g/members/a';
const profilesPath = 'groups/g/memberProfiles', ownPath = '$profilesPath/a';
final instant = Timestamp(1700000000, 123456789);
sdk.Data display([String name = 'Shared name']) => {
  'displayName': name, 'createdAt': instant, 'updatedAt': instant,
};

class DisplayDb extends chat.ChatDb {
  int attempts = 1, queries = 0;
  void Function(int)? beforeAttempt;
  @override
  CollectionReference<sdk.Data> collection(String path) => DisplayCollection(this, path);
  @override
  Future<chat.ChatSnapshot> read(String path, GetOptions? options) async {
    final snapshot = await super.read(path, options);
    return chat.ChatSnapshot(this, poisonPath ?? path, snapshot.raw, snapshot.metadata);
  }
  @override
  Future<T> runTransaction<T>(Future<T> Function(Transaction) handler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    transactions++;
    for (var i = 0; i < attempts; i++) {
      beforeAttempt?.call(i);
      final txn = DisplayTransaction(this);
      final result = await handler(txn);
      if (i < attempts - 1) continue;
      if (gates['commit'] != null) await gates['commit']!.future;
      if (errors['commit'] != null) throw errors['commit']!;
      writes.addAll(txn.staged);
      for (final write in txn.staged) {
        documents[write.path] = write.data.map((key, value) => MapEntry(key,
          value is FieldValue ? Timestamp(instant.seconds + transactions, instant.nanoseconds) : value));
      }
      return result;
    }
    throw StateError('No attempt');
  }
}
class DisplayCollection extends chat.ChatCollection {
  DisplayCollection(DisplayDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) => DisplayDocument(db as DisplayDb, '${this.path}/$path');
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) =>
    DisplayQuery(db as DisplayDb, path).orderBy(field, descending: descending);
}
class DisplayDocument extends chat.ChatDocument {
  DisplayDocument(DisplayDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String collectionPath) => DisplayCollection(db as DisplayDb, '$path/$collectionPath');
}
class DisplayQuery extends chat.ChatQuery {
  DisplayQuery(DisplayDb super.db, super.path);
  @override
  Future<QuerySnapshot<sdk.Data>> get([GetOptions? options]) async {
    final store = db as DisplayDb;
    store.queries++; store.queryPath = path; store.sources.add(options?.source);
    if (store.gates['query'] != null) await store.gates['query']!.future;
    if (store.errors['query'] != null) throw store.errors['query']!;
    final ids = store.forcedIds ?? store.documents.keys.where((key) =>
      key.startsWith('$path/') && !key.substring(path.length + 1).contains('/'))
      .map((key) => key.split('/').last).toList();
    if (store.forcedIds == null) ids.sort(memberDisplayIdCompare);
    final filtered = ids.where((id) => store.after == null || memberDisplayIdCompare(id, store.after!.single as String) > 0);
    return sdk.QueryResult(filtered.take(store.queryLimit!).map((id) => chat.ChatQueryDocument(
      store, store.poisonPath ?? '$path/$id', store.documents['$path/$id'], store.metadata('$path/$id'))).toList(),
      sdk.Metadata(isFromCache: store.queryCached, hasPendingWrites: store.queryPending));
  }
}
class DisplayTransaction extends sdk.SdkTransaction {
  final staged = <({String path, sdk.Data data, bool transaction})>[];
  DisplayTransaction(DisplayDb super.db);
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> reference) {
    if (staged.isNotEmpty) throw StateError('Read after write');
    return super.get(reference);
  }
  @override
  Transaction set<T>(DocumentReference<T> reference, T data, [SetOptions? options]) {
    expect(options, isNull);
    staged.add((path: reference.path, data: data as sdk.Data, transaction: true));
    return this;
  }
}
void seed(DisplayDb db) {
  db.documents.addAll({groupPath: groups.groupData(), memberPath: {
    'userId': 'a', 'role': 'member', 'joinedAt': instant,
  }, 'users/a': {'displayName': 'PRIVATE NEVER COPY', 'email': 'private@example.test'},
    '$profilesPath/z': display()});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DisplayDb db;
  late sdk.SdkAuth auth;
  late FirestoreMemberDisplayGateway gateway;
  setUp(() { db = DisplayDb(); seed(db); auth = sdk.SdkAuth(); gateway = FirestoreMemberDisplayGateway(auth, db); });

  test('archived names stay readable but publishing is rejected', () async {
    db.documents[groupPath]!.addAll({'archived': true, 'lifecycleRevision': 1,
      'lifecycleChangedBy': 'a', 'lifecycleChangedAt': db.documents[groupPath]!['updatedAt']});
    final page = await gateway.read('g');
    expect(page.archived, true); expect(page.names, isNotEmpty);
    expect(await gateway.readMembers('g', ['z']), isNotEmpty);
    await expectLater(gateway.publish('g', 'No change'), throwsFormatException);
    expect(db.writes, isEmpty);
  });

  test('roster names read only exact requested group-visible paths and omit absent names', () async {
    final names = await gateway.readMembers('g', ['b', 'z']);
    expect(names.single.uid, 'z');
    expect(db.reads, [groupPath, memberPath, '$profilesPath/b', '$profilesPath/z']);
    expect(db.sources, everyElement(Source.server));
    expect(db.reads.any((path) => path.startsWith('users/')), isFalse);
    expect(db.queries, 0);
  });
  for (final uids in [List.filled(21, 'b'), ['b', 'b'], ['x/y']]) {
    test('invalid roster name selection $uids rejects before SDK', () async {
      await expectLater(gateway.readMembers('g', uids), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  test('failed name lookup never returns preceding partial names', () async {
    db.documents['$profilesPath/b'] = display('First');
    db.errors['$profilesPath/z'] = StateError('offline');
    await expectLater(gateway.readMembers('g', ['b', 'z']), throwsStateError);
  });
  test('caller mutation during an await cannot expand the requested name set', () async {
    final uids = ['z']; db.gates[groupPath] = Completer();
    final request = gateway.readMembers('g', uids);
    uids.addAll(List.generate(25, (index) => 'extra-$index'));
    db.gates[groupPath]!.complete(); await request;
    expect(db.reads, [groupPath, memberPath, '$profilesPath/z']);
  });
  test('account changes during exact name lookup discard old response', () async {
    db.gates['$profilesPath/z'] = Completer();
    final request = expectLater(gateway.readMembers('g', ['z']), throwsStateError);
    await chat.flush(); auth.currentUser = sdk.SdkUser('new');
    db.gates['$profilesPath/z']!.complete(); await request;
  });
  test('strict three fields retain raw timestamps including nanoseconds and untrusted text', () {
    final value = FirebaseMemberDisplay.parse('g', 'a', display('<b> Same </b>'));
    expect(value.displayName, '<b> Same </b>'); expect(identical(value.createdAt, instant), isTrue);
    expect(identical(value.updatedAt, instant), isTrue); expect(value.createdAt.nanoseconds, 123456789);
  });
  for (final field in ['role', 'userId', 'email', 'avatar', 'verified', 'extra']) {
    test('model rejects extra $field no identity copies', () {
      expect(() => FirebaseMemberDisplay.parse('g', 'a', {...display(), field: 'private'}), throwsFormatException);
    });
  }
  for (final field in ['displayName', 'createdAt', 'updatedAt']) {
    test('model rejects missing $field', () {
      expect(() => FirebaseMemberDisplay.parse('g', 'a', display()..remove(field)), throwsFormatException);
    });
  }
  for (final bad in <Object?>[null, 1, true, '', '   ', 'x' * 101]) {
    test('invalid name $bad', () {
      expect(() => FirebaseMemberDisplay.parse('g', 'a', {...display(), 'displayName': bad}), throwsFormatException);
    });
  }
  for (final field in ['createdAt', 'updatedAt']) {
    for (final bad in <Object?>[null, 1, 'date', DateTime.utc(2026)]) {
      test('model rejects non Timestamp $field $bad', () {
        expect(() => FirebaseMemberDisplay.parse('g', 'a', {...display(), field: bad}), throwsFormatException);
      });
    }
  }
  test('null data rejected as FormatException', () {
    expect(() => FirebaseMemberDisplay.parse('g', 'a', null), throwsFormatException);
  });
  for (final bad in ['', '.', '..', 'x/y', '__reserved__', 'é' * 751]) {
    test('robust segment length ${bad.length} denied before SDK', () async {
      expect(() => FirebaseMemberDisplay.parse(bad, 'a', display()), throwsFormatException);
      expect(() => FirebaseMemberDisplay.parse('g', bad, display()), throwsFormatException);
      await expectLater(gateway.read(bad), throwsFormatException);
      await expectLater(gateway.read('g', after: bad), throwsFormatException);
      await expectLater(gateway.publish(bad, 'Name'), throwsFormatException);
      expect(db.sources, isEmpty); expect(db.writes, isEmpty);
    });
  }
  test('name exact boundaries and no model normalization', () {
    expect(memberDisplayName('x'), 'x'); expect(memberDisplayName('x' * 100).length, 100);
    expect(FirebaseMemberDisplay.parse('g', 'a', display('  Name  ')).displayName, '  Name  ');
  });
  test('server read default20 exact own independent of page no users/roster reads', () async {
    final result = await gateway.read('g');
    expect(result.own, isNull); expect(result.names.single.uid, 'z');
    expect(db.reads, [groupPath, memberPath, ownPath]);
    expect(db.queryLimit, 20); expect(db.queryPath, profilesPath);
    expect(db.orders, [(field: FieldPath.documentId, descending: false)]);
    expect(db.sources, everyElement(Source.server)); expect(db.writes, isEmpty);
  });
  test('own exact read remains available on later page independent directory', () async {
    db.documents[ownPath] = display('Own published');
    final result = await gateway.read('g', after: 'b');
    expect(result.own!.displayName, 'Own published'); expect(result.names.single.uid, 'z');
    expect(db.after, ['b']); expect(db.reads, [groupPath, memberPath, ownPath]);
  });
  for (final size in [0, 51, -1]) {
    test('invalid page size $size before SDK', () async {
      await expectLater(gateway.read('g', pageSize: size), throwsFormatException); expect(db.sources, isEmpty);
    });
  }
  test('max50 accepted', () async { await gateway.read('g', pageSize: 50); expect(db.queryLimit, 50); });
  test('full final page then empty page no polling replacement cursor', () async {
    final first = await gateway.read('g', pageSize: 1);
    expect(first.hasMore, isTrue); expect(first.cursor, 'z');
    final last = await gateway.read('g', pageSize: 1, after: first.cursor);
    expect(last.names, isEmpty); expect(last.cursor, isNull); expect(last.hasMore, isFalse); expect(db.queries, 2);
  });
  test('nonunique names preserve separate UID rows', () async {
    db.documents[ownPath] = display();
    final result = await gateway.read('g');
    expect(result.names.map((n) => n.displayName), ['Shared name', 'Shared name']);
    expect(result.names.map((n) => n.uid), ['a', 'z']);
  });
  test('UTF8 order not UTF16', () { expect(memberDisplayIdCompare('\u{10000}', '\uE000'), greaterThan(0)); });
  for (final ids in [<String>['z', 'z'], <String>['z', 'a']]) {
    test('duplicate or unordered response $ids fails closed', () async {
      db.documents[ownPath] = display(); db.forcedIds = ids;
      await expectLater(gateway.read('g'), throwsFormatException);
    });
  }
  for (final role in ['admin', 'group_lead', 'member']) {
    test('$role publish exact self three fields membership unchanged', () async {
      db.documents[memberPath]!['role'] = role;
      final member = Map.of(db.documents[memberPath]!);
      await gateway.publish('g', 'Public differs from private');
      expect(db.reads, [groupPath, memberPath, ownPath]); expect(db.sources, [null, null, null]);
      expect(db.writes.single.path, ownPath); expect(db.writes.single.transaction, isTrue);
      expect(db.writes.single.data, {
        'displayName': 'Public differs from private', 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp()});
      expect(db.documents[memberPath], member); expect(db.reads.any((p) => p.startsWith('users/')), isFalse);
    });
  }
  test('change and repeated same name retain EXACT createdAt raw nanos no role change', () async {
    db.documents[ownPath] = display('Old');
    await gateway.publish('g', 'New'); await gateway.publish('g', 'New');
    for (final write in db.writes) {
      expect(identical(write.data['createdAt'], instant), isTrue);
      expect((write.data['createdAt'] as Timestamp).nanoseconds, 123456789);
      expect(write.data.keys.toSet(), {'displayName', 'createdAt', 'updatedAt'});
      expect(write.data['updatedAt'], FieldValue.serverTimestamp());
    }
    expect(db.documents[memberPath]!['role'], 'member');
  });
  for (final bad in ['', ' ', 'x' * 101]) {
    test('invalid publish name length ${bad.length} no SDK', () async {
      await expectLater(gateway.publish('g', bad), throwsFormatException); expect(db.sources, isEmpty);
    });
  }
  for (final path in [groupPath, memberPath, ownPath, '$profilesPath/z']) {
    for (final kind in ['extra', 'cache', 'pending']) {
      test('read $kind $path fails closed', () async {
        db.documents[ownPath] = display();
        if (kind == 'extra') db.documents[path]!['email'] = 'bad';
        if (kind == 'cache') db.cached.add(path);
        if (kind == 'pending') db.pending.add(path);
        await expectLater(gateway.read('g'), kind == 'extra' ? throwsFormatException : throwsStateError);
      });
    }
  }
  for (final path in [groupPath, memberPath, ownPath]) {
    for (final kind in ['extra', 'cache', 'pending']) {
      test('transaction $kind $path never commits', () async {
        db.documents[ownPath] = display();
        if (kind == 'extra') db.documents[path]!['email'] = 'bad';
        if (kind == 'cache') db.cached.add(path);
        if (kind == 'pending') db.pending.add(path);
        await expectLater(gateway.publish('g', 'Name'), kind == 'extra' ? throwsFormatException : throwsStateError);
        expect(db.writes, isEmpty);
      });
    }
    for (final operation in ['read', 'publish']) {
      for (final failRead in [false, true]) {
        test('$operation switch account during $path ${failRead ? 'error' : 'success'} discards', () async {
          db.gates[path] = Completer(); if (failRead) db.errors[path] = const FormatException('old');
          final request = expectLater(operation == 'read' ? gateway.read('g') : gateway.publish('g', 'Name'), throwsStateError);
          await chat.flush(); auth.currentUser = sdk.SdkUser('new'); db.gates[path]!.complete(); await request;
          expect(db.writes, isEmpty);
        });
      }
    }
  }
  for (final operation in ['read', 'publish']) {
    for (final path in [groupPath, memberPath]) {
      test('$operation missing $path blocks', () async {
        db.documents.remove(path);
        await expectLater(operation == 'read' ? gateway.read('g') : gateway.publish('g', 'Name'), throwsFormatException);
        expect(db.writes, isEmpty);
      });
    }
    test('$operation wrong snapshot path blocked', () async {
      db.poisonPath = 'groups/other';
      await expectLater(operation == 'read' ? gateway.read('g') : gateway.publish('g', 'Name'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final patch in <sdk.Data>[{'role': 'owner'}, {'userId': 'b'}, {'joinedAt': null}]) {
    test('actual membership malformed $patch transaction blocks', () async {
      db.documents[memberPath]!.addAll(patch);
      await expectLater(gateway.publish('g', 'Name'), throwsFormatException); expect(db.writes, isEmpty);
    });
  }
  for (final changed in ['membership', 'group', 'uid', 'createdAt']) {
    test('retry revalidates $changed no staged commit', () async {
      db.documents[ownPath] = display(); db.attempts = 2;
      db.beforeAttempt = (i) {
        if (i == 0) return;
        if (changed == 'membership') db.documents.remove(memberPath);
        if (changed == 'group') db.documents.remove(groupPath);
        if (changed == 'uid') auth.currentUser = sdk.SdkUser('new');
        if (changed == 'createdAt') db.documents[ownPath]!['createdAt'] = DateTime.utc(2026);
      };
      await expectLater(gateway.publish('g', 'Name'), changed == 'uid' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  test('retry permits current any-role membership and preserves newest exact timestamp', () async {
    final newer = Timestamp(instant.seconds, instant.nanoseconds + 1);
    db.attempts = 2; db.beforeAttempt = (i) {
      if (i == 1) { db.documents[memberPath]!['role'] = 'group_lead'; db.documents[ownPath] = {...display(), 'createdAt': newer}; }
    };
    await gateway.publish('g', 'Name'); expect(db.writes.length, 1);
    expect(identical(db.writes.single.data['createdAt'], newer), isTrue);
    expect(db.reads.where((p) => p == memberPath).length, 2);
  });
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code commit no false ACK', () async {
      db.errors['commit'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.publish('g', 'Name'), throwsA(isA<FirebaseException>())); expect(db.writes, isEmpty);
    });
    test('$code query fails entire page', () async {
      db.errors['query'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.read('g'), throwsA(isA<FirebaseException>())); expect(db.writes, isEmpty);
    });
  }
  for (final pending in [false, true]) {
    test('query ${pending ? 'pending' : 'cached'} rejected', () async {
      db.queryPending = pending; db.queryCached = !pending;
      await expectLater(gateway.read('g'), throwsStateError);
    });
  }
  test('switch during query prevents data response', () async {
    db.gates['query'] = Completer(); final request = expectLater(gateway.read('g'), throwsStateError);
    await chat.flush(); auth.currentUser = null; db.gates['query']!.complete(); await request;
  });
  test('switch during commit discards ACK but cannot roll back committed write', () async {
    db.gates['commit'] = Completer(); final request = expectLater(gateway.publish('g', 'Name'), throwsStateError);
    await chat.flush(); auth.currentUser = null; db.gates['commit']!.complete(); await request;
    expect(db.writes.length, 1);
  });
  test('logged out no SDK calls', () async {
    auth.currentUser = null;
    await expectLater(gateway.read('g'), throwsFormatException);
    await expectLater(gateway.publish('g', 'Name'), throwsFormatException); expect(db.sources, isEmpty);
  });
  for (final invalid in ['wrongOwn', 'wrongGroup', 'oversize', 'beforeCursor']) {
    test('strict page $invalid', () {
      expect(() => FirebaseMemberDisplayPage((uid: 'a', groupId: 'g'),
        [FirebaseMemberDisplay.parse(invalid == 'wrongGroup' ? 'h' : 'g', 'b', display())],
        own: invalid == 'wrongOwn' ? FirebaseMemberDisplay.parse('g', 'b', display()) : null,
        pageSize: invalid == 'oversize' ? 0 : 20, after: invalid == 'beforeCursor' ? 'z' : null), throwsFormatException);
    });
  }
}