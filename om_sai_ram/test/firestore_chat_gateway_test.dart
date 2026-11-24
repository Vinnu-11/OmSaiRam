// SDK-shaped doubles exercise the actual Dart gateway, not security rules,
// transport acknowledgements or real Firestore transaction retry semantics.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firebase_chat_models.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firestore_chat_gateway.dart';
import 'firebase_groups_test.dart' as groups;
import 'firestore_assignments_gateway_test.dart' as sdk;

const messagesPath = 'groups/g/messages';
const messagePath = '$messagesPath/z';
const reportPath = '$messagePath/reports/a';
final instant = Timestamp(1700000000, 123456789);
Map<String, dynamic> messageData({Timestamp? time, String text = 'Original text'}) => {
  'senderUid': 'public-uid', 'text': text, 'createdAt': time ?? instant
};

class ChatSnapshot extends sdk.Snapshot {
  @override
  final DocumentReference<sdk.Data> reference;
    ChatSnapshot(ChatDb db, String path, sdk.Data? raw, SnapshotMetadata metadata)
      : reference = ChatDocument(db, path), super(path.split('/').last, raw, metadata);
}
class ChatQueryDocument extends ChatSnapshot implements QueryDocumentSnapshot<sdk.Data> {
  ChatQueryDocument(super.db, super.path, super.raw, super.metadata);
  @override
  sdk.Data data() => raw!;
}
class ChatDb extends sdk.SdkDb {
  final orders = <({Object field, bool descending})>[];
  List<Object?>? after;
  String? poisonPath;
  List<String>? forcedIds;
  int allocations = 0;
  @override
  CollectionReference<sdk.Data> collection(String path) => ChatCollection(this, path);
  @override
  Future<ChatSnapshot> read(String path, GetOptions? options) async {
    final snapshot = await super.read(path, options);
    return ChatSnapshot(this, path, snapshot.raw, snapshot.metadata);
  }
}
class ChatCollection extends sdk.SdkCollection {
  ChatCollection(ChatDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) {
    final chat = db as ChatDb;
    final id = path ?? 'auto${++chat.allocations}';
    return ChatDocument(chat, '${this.path}/$id');
  }
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) =>
      ChatQuery(db as ChatDb, path).orderBy(field, descending: descending);
}
class ChatDocument extends sdk.SdkDocument {
  ChatDocument(ChatDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String collectionPath) =>
      ChatCollection(db as ChatDb, '$path/$collectionPath');
  @override
  Future<void> set(sdk.Data data, [SetOptions? options]) async {
    if (db.gates['set'] != null) await db.gates['set']!.future;
    if (db.errors['set'] != null) throw db.errors['set']!;
    db.writes.add((path: path, data: data, transaction: false));
  }
}
class ChatQuery extends Fake implements Query<sdk.Data> {
  final ChatDb db;
  final String path;
  ChatQuery(this.db, this.path);
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) {
    db.orders.add((field: field, descending: descending)); return this;
  }
  @override
  Query<sdk.Data> limit(int limit) { db.queryLimit = limit; return this; }
  @override
  Query<sdk.Data> startAfter(Iterable<Object?> values) { db.after = values.toList(); return this; }
  @override
  Future<QuerySnapshot<sdk.Data>> get([GetOptions? options]) async {
    db.queryPath = path;
    db.sources.add(options?.source);
    if (db.gates['query'] != null) await db.gates['query']!.future;
    if (db.errors['query'] != null) throw db.errors['query']!;
    final ids = db.forcedIds ?? db.documents.keys.where((key) =>
      key.startsWith('$path/') && !key.substring(path.length + 1).contains('/'))
        .map((key) => key.split('/').last).toList();
    if (db.forcedIds == null) {
      ids.sort((a, b) => chatCursorCompare(
        FirebaseChatCursor(db.documents['$path/$a']!['createdAt'] is Timestamp
            ? db.documents['$path/$a']!['createdAt'] as Timestamp : instant, a),
        FirebaseChatCursor(db.documents['$path/$b']!['createdAt'] is Timestamp
            ? db.documents['$path/$b']!['createdAt'] as Timestamp : instant, b)));
    }
    final filtered = ids.where((id) => db.after == null || chatCursorCompare(
        FirebaseChatCursor(db.documents['$path/$id']!['createdAt'] as Timestamp, id),
        FirebaseChatCursor(db.after![0] as Timestamp, db.after![1] as String)) > 0);
    return sdk.QueryResult(filtered.take(db.queryLimit!).map((id) => ChatQueryDocument(
      db, db.poisonPath ?? '$path/$id', db.documents['$path/$id'], db.metadata('$path/$id'))).toList(),
      sdk.Metadata(isFromCache: db.queryCached, hasPendingWrites: db.queryPending));
  }
}

void seed(ChatDb db) {
  db.documents.addAll({
    'users/a': {'displayName': 'Private name', 'createdAt': instant, 'updatedAt': instant},
    'groups/g': groups.groupData(),
    'groups/g/members/a': {'userId': 'a', 'role': 'member', 'joinedAt': instant},
    messagePath: messageData(),
  });
}

Future<void> flush() async {
  for (var i = 0; i < 12; i++) { await Future<void>.delayed(Duration.zero); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatDb db;
  late sdk.SdkAuth auth;
  late FirestoreChatGateway gateway;
  setUp(() { db = ChatDb(); auth = sdk.SdkAuth(); seed(db); gateway = FirestoreChatGateway(auth, db); });

  test('archived history stays readable while send/report reject before auto-ID allocation', () async {
    db.documents['groups/g']!.addAll({'archived': true, 'lifecycleRevision': 1,
      'lifecycleChangedBy': 'a', 'lifecycleChangedAt': db.documents['groups/g']!['updatedAt']});
    final page = await gateway.read('g');
    expect(page.archived, true); expect(page.messages, isNotEmpty);
    await expectLater(gateway.send('g', 'Not sent'), throwsFormatException);
    await expectLater(gateway.report('g', 'z', FirebaseReportReason.spam, ''), throwsFormatException);
    expect(db.writes, isEmpty); expect(db.allocations, 0);
  });

  test('three exact fields preserve text and original Timestamp nanoseconds', () {
    final message = FirebaseChatMessage.parse('g', 'z', messageData(text: '  text  '));
    expect(message.text, '  text  ');
    expect(identical(message.createdAt, instant), isTrue);
    expect(identical(message.cursor.createdAt, instant), isTrue);
    expect(message.createdAt.nanoseconds, 123456789);
  });
  for (final bad in ['', '.', '..', 'a/b', '__reserved__', 'é' * 751]) {
    test('robust group/message/sender/cursor segment rejects $bad', () async {
      expect(() => FirebaseChatCursor(instant, bad), throwsFormatException);
      expect(() => FirebaseChatMessage.parse('g', bad, messageData()), throwsFormatException);
      expect(() => FirebaseChatMessage.parse('g', 'z', {...messageData(), 'senderUid': bad}), throwsFormatException);
      await expectLater(gateway.read(bad), throwsFormatException);
      expect(db.sources, isEmpty);
    });
  }
  for (final patch in <Map<String, dynamic>>[
    {'email': 'private'}, {'senderUid': 1}, {'text': '   '}, {'text': 'x' * 2001},
    {'text': null}, {'createdAt': null}, {'createdAt': DateTime.utc(2026)},
  ]) {
    test('malformed message $patch rejects whole page', () async {
      db.documents['$messagesPath/a'] = {...messageData(), ...patch};
      await expectLater(gateway.read('g'), throwsFormatException);
    });
  }
  test('missing field and missing data rejected, no timestamp coercion', () {
    expect(() => FirebaseChatMessage.parse('g', 'z', messageData()..remove('text')), throwsFormatException);
    expect(() => FirebaseChatMessage.parse('g', 'z', null), throwsFormatException);
    expect(chatText('x' * 2000).length, 2000);
    expect(reportDetails('x' * 1000).length, 1000);
    expect(() => reportDetails('x' * 1001), throwsFormatException);
  });
  test('ordering compares seconds then nanos then descending UTF8 ID', () {
    expect(chatCursorCompare(FirebaseChatCursor(Timestamp(2, 0), 'a'), FirebaseChatCursor(Timestamp(1, 999999999), 'z')), lessThan(0));
    expect(chatCursorCompare(FirebaseChatCursor(Timestamp(1, 2), 'a'), FirebaseChatCursor(Timestamp(1, 1), 'z')), lessThan(0));
    expect(chatCursorCompare(FirebaseChatCursor(instant, 'z'), FirebaseChatCursor(instant, 'a')), lessThan(0));
    // UTF-16 ordering differs at this supplementary/BMP boundary.
    expect(chatIdCompare('\u{10000}', '\uE000'), greaterThan(0));
  });
  test('read exact two DESC orders default20 max50 server-only self access no roster/private others', () async {
    final page = await gateway.read('g');
    expect(page.messages.single.senderUid, 'public-uid');
    expect(db.orders, [(field: 'createdAt', descending: true), (field: FieldPath.documentId, descending: true)]);
    expect(db.queryPath, messagesPath); expect(db.queryLimit, 20);
    expect(db.reads, ['users/a', 'groups/g', 'groups/g/members/a']);
    expect(db.sources.every((s) => s == Source.server), isTrue);
    await gateway.read('g', pageSize: 50); expect(db.queryLimit, 50);
  });
  test('startAfter preserves original Timestamp object and full nanos ID tie', () async {
    db.documents['$messagesPath/a'] = messageData();
    final first = await gateway.read('g', pageSize: 1);
    final second = await gateway.read('g', pageSize: 1, after: first.cursor);
    expect(first.messages.single.id, 'z'); expect(second.messages.single.id, 'a');
    expect(identical(db.after![0], instant), isTrue); expect(db.after![1], 'z');
  });
  for (final size in [0, 51]) {
    test('pageSize $size rejected before SDK', () async {
      await expectLater(gateway.read('g', pageSize: size), throwsFormatException);
      expect(db.sources, isEmpty);
    });
  }
  test('empty page no cursor and no infinite auto fetch', () async {
    db.documents.remove(messagePath);
    final page = await gateway.read('g');
    expect(page.messages, isEmpty); expect(page.cursor, isNull); expect(page.hasMore(20), isFalse);
    expect(db.sources.length, 4);
  });
  for (final role in ['member', 'admin', 'group_lead']) {
    test('$role can read send and report; sender/reporter captured only SDK UID', () async {
      db.documents['groups/g/members/a']!['role'] = role;
      await gateway.read('g'); await gateway.send('g', '  Original  ');
      await gateway.report('g', 'z', FirebaseReportReason.harassment, 'Details');
      final send = db.writes.first, report = db.writes.last;
      expect(send.path, '$messagesPath/auto1'); expect(send.transaction, isFalse);
      expect(send.data.keys.toSet(), {'senderUid', 'text', 'createdAt'});
      expect(send.data['senderUid'], 'a'); expect(send.data['text'], '  Original  ');
      expect(send.data['createdAt'], FieldValue.serverTimestamp());
      expect(report.path, reportPath); expect(report.transaction, isTrue);
      expect(report.data, {'reporterUid': 'a', 'reason': 'harassment', 'details': 'Details',
        'createdAt': FieldValue.serverTimestamp(), 'status': 'open', 'resolvedBy': null, 'resolvedAt': null});
      expect(db.reads.sublist(db.reads.length - 2), [reportPath, messagePath]);
    });
  }
  for (final path in ['users/a', 'groups/g', 'groups/g/members/a']) {
    test('missing or malformed access $path blocks every operation', () async {
      final saved = db.documents.remove(path)!;
      await expectLater(gateway.read('g'), throwsFormatException);
      await expectLater(gateway.send('g', 'text'), throwsFormatException);
      await expectLater(gateway.report('g', 'z', FirebaseReportReason.spam, ''), throwsFormatException);
      db.documents[path] = {...saved, 'fakeAdmin': true};
      await expectLater(gateway.read('g'), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.allocations, 0);
    });
  }
  test('unknown role and membership UID mismatch fail before send allocation', () async {
    db.documents['groups/g/members/a']!['role'] = 'owner';
    await expectLater(gateway.send('g', 'text'), throwsFormatException);
    db.documents['groups/g/members/a']!['role'] = 'member';
    db.documents['groups/g/members/a']!['userId'] = 'b';
    await expectLater(gateway.send('g', 'text'), throwsFormatException);
    expect(db.allocations, 0);
  });
  for (final path in ['users/a', 'groups/g', 'groups/g/members/a', messagePath]) {
    test('cache and pending $path reject whole server page', () async {
      db.cached.add(path); await expectLater(gateway.read('g'), throwsStateError);
      db.cached.clear(); db.pending.add(path); await expectLater(gateway.read('g'), throwsStateError);
    });
  }
  test('cache and pending query reject whole page', () async {
    db.queryCached = true; await expectLater(gateway.read('g'), throwsStateError);
    db.queryCached = false; db.queryPending = true; await expectLater(gateway.read('g'), throwsStateError);
  });
  test('out of scope snapshot path fails closed', () async {
    db.poisonPath = 'groups/other/messages/z';
    await expectLater(gateway.read('g'), throwsFormatException);
  });
  for (final ids in [<String>['z', 'z'], <String>['a', 'z']]) {
    test('duplicate or incorrectly ordered SDK response $ids rejected', () async {
      db.documents['$messagesPath/a'] = messageData(); db.forcedIds = ids;
      await expectLater(gateway.read('g'), throwsFormatException);
    });
  }
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code fails with no partial page and explicit retry succeeds', () async {
      db.errors['query'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.read('g'), throwsA(isA<FirebaseException>()));
      db.errors.clear(); expect((await gateway.read('g')).messages.length, 1);
    });
  }
  test('signed out rejects without reads', () async {
    auth.currentUser = null;
    await expectLater(gateway.read('g'), throwsFormatException);
    await expectLater(gateway.send('g', 'text'), throwsFormatException);
    expect(db.sources, isEmpty);
  });
  test('invalid text and oversized details fail before any SDK work', () async {
    await expectLater(gateway.send('g', '  '), throwsFormatException);
    await expectLater(gateway.send('g', 'x' * 2001), throwsFormatException);
    await expectLater(gateway.report('g', 'z', FirebaseReportReason.other, 'x' * 1001), throwsFormatException);
    expect(db.sources, isEmpty); expect(db.allocations, 0);
  });
  test('send transport failure marks uncertainty and never retries auto-ID', () async {
    db.errors['set'] = StateError('network failed after possible commit');
    await expectLater(gateway.send('g', 'text'), throwsA(isA<FirebaseChatDeliveryUncertain>()));
    expect(db.allocations, 1); expect(db.writes, isEmpty);
  });
  for (final reason in FirebaseReportReason.values) {
    test('report reason ${reason.name} exact schema server time', () async {
      await gateway.report('g', 'z', reason, '');
      expect(db.writes.single.data['reason'], reason.name);
      expect(db.writes.single.data.length, 7);
      expect(db.writes.single.data['createdAt'], FieldValue.serverTimestamp());
    });
  }
  test('duplicate report not overwritten even for admin', () async {
    db.documents[reportPath] = {'status': 'resolved'};
    db.documents['groups/g/members/a']!['role'] = 'admin';
    await expectLater(gateway.report('g', 'z', FirebaseReportReason.other, ''), throwsFormatException);
    expect(db.reads.sublist(3), [reportPath, messagePath]); expect(db.writes, isEmpty);
  });
  test('removed target and malformed target cannot be reported', () async {
    db.documents.remove(messagePath);
    await expectLater(gateway.report('g', 'z', FirebaseReportReason.other, ''), throwsFormatException);
    db.documents[messagePath] = {...messageData(), 'text': null};
    await expectLater(gateway.report('g', 'z', FirebaseReportReason.other, ''), throwsFormatException);
    expect(db.writes, isEmpty);
  });
  for (final path in [reportPath, messagePath]) {
    test('report transaction cached/pending $path aborts', () async {
      db.cached.add(path);
      await expectLater(gateway.report('g', 'z', FirebaseReportReason.spam, ''), throwsStateError);
      db.cached.clear(); db.pending.add(path);
      await expectLater(gateway.report('g', 'z', FirebaseReportReason.spam, ''), throwsStateError);
      expect(db.writes, isEmpty);
    });
  }
  for (final boundary in ['users/a', 'groups/g', 'groups/g/members/a', 'query', reportPath, messagePath, 'set']) {
    test('SDK UID switch during $boundary discards result and prevents later writes', () async {
      db.gates[boundary] = Completer();
      final request = boundary == 'set' ? gateway.send('g', 'text')
          : [reportPath, messagePath].contains(boundary)
          ? gateway.report('g', 'z', FirebaseReportReason.spam, '') : gateway.read('g');
      final check = expectLater(request, throwsStateError);
      await flush(); auth.currentUser = sdk.SdkUser('b'); db.gates[boundary]!.complete(); await check;
      if (boundary != 'set') expect(db.writes, isEmpty);
    });
  }
  test('SDK account switch during failed async read still checks UID', () async {
    db.gates['query'] = Completer(); db.errors['query'] = const FormatException('old account');
    final request = gateway.read('g'); final check = expectLater(request, throwsStateError);
    await flush(); auth.currentUser = sdk.SdkUser('b'); db.gates['query']!.complete(); await check;
  });
}