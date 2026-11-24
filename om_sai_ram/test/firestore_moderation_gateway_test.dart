// SDK-shaped doubles exercise Dart validation/calls, NOT rules, real SDK ACKs,
// server transaction atomicity, auth tokens or retry semantics.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firebase_chat_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firebase_moderation_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firestore_moderation_gateway.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;
import 'firebase_groups_test.dart' as groups;

const memberPath = 'groups/g/members/a';
const targetPath = 'groups/g/messages/z';
const markerPath = 'groups/g/moderationRecords/messages/items/z';
const reportsPath = '$targetPath/reports';
const reportPath = '$reportsPath/r';
final time = Timestamp(1700000000, 123456789);
Map<String, dynamic> reportData({String uid = 'r', String status = 'open'}) => {
  'reporterUid': uid, 'reason': 'spam', 'details': '', 'createdAt': time,
  'status': status, 'resolvedBy': status == 'open' ? null : 'a',
  'resolvedAt': status == 'open' ? null : time,
};
Map<String, dynamic> markerData() => {'targetKind': 'messages', 'targetId': 'z',
  'authorUid': 'public-uid', 'moderatedBy': 'a', 'moderatedAt': time, 'reason': 'other'};

class ModerationDb extends chat.ChatDb {
  final deletes = <String>[];
  final operations = <String>[];
  void Function()? beforeTransaction;
  @override
  CollectionReference<sdk.Data> collection(String path) => ModerationCollection(this, path);
  @override
  Future<T> runTransaction<T>(Future<T> Function(Transaction) handler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    transactions++;
    beforeTransaction?.call();
    final result = await handler(ModerationTransaction(this));
    if (gates['commit'] != null) await gates['commit']!.future;
    if (errors['commit'] != null) throw errors['commit']!;
    return result;
  }
}
class ModerationCollection extends sdk.SdkCollection {
  ModerationCollection(ModerationDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) => ModerationDocument(db as ModerationDb, '${this.path}/$path');
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) {
    (db as ModerationDb).orders.add((field: field, descending: descending));
    return ModerationQuery(db as ModerationDb, path);
  }
}
class ModerationDocument extends sdk.SdkDocument {
  ModerationDocument(ModerationDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String path) => ModerationCollection(db as ModerationDb, '${this.path}/$path');
}
class ModerationQuery extends Fake implements Query<sdk.Data> {
  final ModerationDb db;
  final String path;
  ModerationQuery(this.db, this.path);
  @override
  Query<sdk.Data> limit(int value) { db.queryLimit = value; return this; }
  @override
  Query<sdk.Data> startAfter(Iterable<Object?> values) { db.after = values.toList(); return this; }
  @override
  Future<QuerySnapshot<sdk.Data>> get([GetOptions? options]) async {
    db.queryPath = path; db.sources.add(options?.source);
    if (db.gates['query'] != null) await db.gates['query']!.future;
    if (db.errors['query'] != null) throw db.errors['query']!;
    final ids = db.forcedIds ?? (db.documents.keys.where((key) => key.startsWith('$path/') &&
      !key.substring(path.length + 1).contains('/')).map((key) => key.split('/').last).toList()..sort(chatIdCompare));
    return sdk.QueryResult(ids.where((id) => db.after == null || chatIdCompare(id, db.after!.single as String) > 0)
      .take(db.queryLimit!).map((id) => chat.ChatQueryDocument(db,
        db.poisonPath ?? '$path/$id', db.documents['$path/$id'], db.metadata('$path/$id'))).toList(),
      sdk.Metadata(isFromCache: db.queryCached, hasPendingWrites: db.queryPending));
  }
}
class ModerationTransaction extends sdk.SdkTransaction {
  ModerationTransaction(ModerationDb super.db);
  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    (db as ModerationDb).operations.add('update:${reference.path}');
    db.writes.add((path: reference.path, data: data.map((key, value) => MapEntry(key as String, value)), transaction: true));
    return this;
  }
  @override
  Transaction set<T>(DocumentReference<T> reference, T data, [SetOptions? options]) {
    (db as ModerationDb).operations.add('set:${reference.path}');
    return super.set(reference, data, options);
  }
  @override
  Transaction delete(DocumentReference reference) {
    (db as ModerationDb).operations.add('delete:${reference.path}');
    (db as ModerationDb).deletes.add(reference.path);
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ModerationDb db;
  late sdk.SdkAuth auth;
  late FirestoreModerationGateway gateway;
  test('archived reports remain readable but resolution and removal cannot stage writes', () async {
    db.documents['groups/g']!.addAll({'archived': true, 'lifecycleRevision': 1,
      'lifecycleChangedBy': 'a', 'lifecycleChangedAt': time});
    expect((await gateway.read('g', 'z')).archived, true);
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved), throwsFormatException);
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsFormatException);
    expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
  });
  setUp(() {
    db = ModerationDb(); auth = sdk.SdkAuth();
    db.documents['groups/g'] = {...groups.groupData(), 'updatedAt': time};
    db.documents.addAll({memberPath: {'userId': 'a', 'role': 'admin', 'joinedAt': time},
      targetPath: chat.messageData(), reportPath: reportData()});
    gateway = FirestoreModerationGateway(auth, db);
  });
  test('read exact scope documentID ASC default20 server only no private profiles', () async {
    final page = await gateway.read('g', 'z');
    expect(page.binding, (uid: 'a', groupId: 'g', messageId: 'z'));
    expect(page.reports.single.reporterUid, 'r');
    expect(db.reads, [memberPath, 'groups/g', targetPath, markerPath]);
    expect(db.sources.every((source) => source == Source.server), isTrue);
    expect(db.queryPath, reportsPath); expect(db.queryLimit, 20);
    expect(db.orders, [(field: FieldPath.documentId, descending: false)]);
    expect(identical(page.target!.createdAt, chat.instant), isTrue);
  });
  test('bounded UID cursor pages and max50 never collectionGroup', () async {
    db.documents['$reportsPath/s'] = reportData(uid: 's');
    final first = await gateway.read('g', 'z', pageSize: 1);
    final next = await gateway.read('g', 'z', pageSize: 1, after: first.cursor);
    expect(first.cursor, 'r'); expect(next.cursor, 's'); expect(db.after, ['r']);
    await gateway.read('g', 'z', pageSize: 50); expect(db.queryLimit, 50);
  });
  test('reports readable under absent target with optional confirmed marker', () async {
    db.documents.remove(targetPath);
    var page = await gateway.read('g', 'z');
    expect(page.target, isNull); expect(page.marker, isNull); expect(page.reports.length, 1);
    db.documents[markerPath] = markerData(); page = await gateway.read('g', 'z');
    expect(page.marker!.reason, FirebaseReportReason.other);
  });
  test('empty reports have no cursor or continuation', () async {
    db.documents.remove(reportPath);
    final page = await gateway.read('g', 'z'); expect(page.cursor, isNull); expect(page.hasMore(20), isFalse);
  });
  for (final bad in ['', '.', '..', 'a/b', '__reserved__', 'é' * 751]) {
    test('invalid segment $bad fails before SDK for every action', () async {
      await expectLater(gateway.read(bad, 'z'), throwsFormatException);
      await expectLater(gateway.read('g', bad), throwsFormatException);
      await expectLater(gateway.read('g', 'z', after: bad), throwsFormatException);
      await expectLater(gateway.resolve('g', 'z', bad, FirebaseReportStatus.resolved), throwsFormatException);
      await expectLater(gateway.remove('g', bad, FirebaseReportReason.spam), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  for (final size in [0, 51]) {
    test('invalid size $size before SDK', () async {
      await expectLater(gateway.read('g', 'z', pageSize: size), throwsFormatException); expect(db.sources, isEmpty);
    });
  }
  for (final patch in <Map<String, dynamic>>[
    {'reporterUid': 'different'}, {'reason': 'unknown'}, {'details': 1}, {'details': 'x' * 1001},
    {'status': 'unknown'}, {'createdAt': DateTime.utc(2026)}, {'createdAt': null},
    {'resolvedBy': 'a'}, {'resolvedAt': time}, {'email': 'private'},
  ]) {
    test('strict report rejects $patch whole page', () async {
      db.documents[reportPath] = {...reportData(), ...patch};
      await expectLater(gateway.read('g', 'z'), throwsFormatException);
    });
  }
  test('all seven fields required and immutable original Timestamp', () {
    for (final key in reportData().keys) {
      expect(() => FirebaseModerationReport.parse('r', reportData()..remove(key)), throwsFormatException);
    }
    expect(identical(FirebaseModerationReport.parse('r', reportData()).createdAt, time), isTrue);
  });
  for (final status in ['resolved', 'dismissed']) {
    test('$status requires UID and Timestamp, no DateTime coercion', () {
      final raw = reportData(status: status);
      expect(FirebaseModerationReport.parse('r', raw).resolvedBy, 'a');
      for (final patch in [{'resolvedBy': null}, {'resolvedBy': 'a/b'}, {'resolvedAt': null}, {'resolvedAt': DateTime.utc(2026)}]) {
        expect(() => FirebaseModerationReport.parse('r', {...raw, ...patch}), throwsFormatException);
      }
    });
  }
  for (final patch in <Map<String, dynamic>>[
    {'targetKind': 'highlights'}, {'targetId': 'other'}, {'authorUid': 'a/b'},
    {'moderatedBy': null}, {'moderatedAt': DateTime.utc(2026)}, {'reason': 'invalid'}, {'text': 'copied'},
  ]) {
    test('strict selected marker rejects $patch', () async {
      db.documents.remove(targetPath); db.documents[markerPath] = {...markerData(), ...patch};
      await expectLater(gateway.read('g', 'z'), throwsFormatException);
    });
  }
  for (final role in ['member', 'group_lead']) {
    test('$role denied all moderation actions but actual role readable', () async {
      db.documents[memberPath]!['role'] = role;
      expect(await gateway.role('g'), role == 'member' ? FirebaseGroupRole.member : FirebaseGroupRole.groupLead);
      await expectLater(gateway.read('g', 'z'), throwsFormatException);
      await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved), throwsFormatException);
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.transactions, 0);
    });
  }
  test('missing malformed membership and SDK signout fail closed', () async {
    db.documents.remove(memberPath); await expectLater(gateway.read('g', 'z'), throwsFormatException);
    db.documents[memberPath] = {'userId': 'b', 'role': 'admin', 'joinedAt': time};
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsFormatException);
    auth.currentUser = null; await expectLater(gateway.role('g'), throwsFormatException); expect(db.writes, isEmpty);
  });
  for (final path in [memberPath, targetPath, markerPath, reportPath, 'query']) {
    test('cache and pending $path rejected', () async {
      for (final pending in [false, true]) {
        if (path == 'query') { db.queryCached = !pending; db.queryPending = pending; }
        else { db.cached.clear(); db.pending.clear(); (pending ? db.pending : db.cached).add(path); }
        await expectLater(gateway.read('g', 'z'), throwsStateError);
      }
    });
  }
  test('cross-group report path duplicate and wrong ordering rejected', () async {
    db.poisonPath = 'groups/other/messages/z/reports/r';
    await expectLater(gateway.read('g', 'z'), throwsFormatException); db.poisonPath = null;
    db.forcedIds = ['r', 'r']; await expectLater(gateway.read('g', 'z'), throwsFormatException);
    db.documents['$reportsPath/s'] = reportData(uid: 's'); db.forcedIds = ['s', 'r'];
    await expectLater(gateway.read('g', 'z'), throwsFormatException);
  });
  for (final status in [FirebaseReportStatus.resolved, FirebaseReportStatus.dismissed]) {
    test('resolve ${status.name} exact three-field UPDATE SDK UID server time no target prerequisite', () async {
      db.documents.remove(targetPath); await gateway.resolve('g', 'z', 'r', status);
      expect(db.reads, [memberPath, reportPath, 'groups/g', memberPath, reportPath]);
      expect(db.operations, ['update:$reportPath']);
      expect(db.writes.single.data, {'status': status.name, 'resolvedBy': 'a', 'resolvedAt': FieldValue.serverTimestamp()});
      expect(db.deletes, isEmpty);
    });
  }
  test('no reopen no missing report no overwrite of handled report', () async {
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.open), throwsFormatException);
    expect(db.reads, isEmpty);
    db.documents[reportPath] = reportData(status: 'resolved');
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.dismissed), throwsFormatException);
    db.documents.remove(reportPath);
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved), throwsFormatException);
    expect(db.writes, isEmpty);
  });
  test('resolution race reads open report again inside transaction', () async {
    db.beforeTransaction = () => db.documents[reportPath] = reportData(status: 'dismissed');
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved), throwsFormatException);
    expect(db.writes, isEmpty);
  });
  for (final operation in ['resolve', 'remove']) {
    test('$operation role rechecked prewrite transaction on revocation', () async {
      db.beforeTransaction = () => db.documents[memberPath]!['role'] = 'group_lead';
      await expectLater(operation == 'remove' ? gateway.remove('g', 'z', FirebaseReportReason.other) :
        gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  for (final reason in FirebaseReportReason.values) {
    test('remove ${reason.name} reads target AND marker then exact audit+delete transaction without report', () async {
      db.documents.remove(reportPath); await gateway.remove('g', 'z', reason);
      expect(db.reads, [memberPath, 'groups/g', memberPath, targetPath, markerPath]);
      expect(db.operations, ['set:$markerPath', 'delete:$targetPath']); expect(db.transactions, 1);
      expect(db.writes.single.transaction, isTrue);
      expect(db.writes.single.data, {'targetKind': 'messages', 'targetId': 'z', 'authorUid': 'public-uid',
        'moderatedBy': 'a', 'moderatedAt': FieldValue.serverTimestamp(), 'reason': reason.name});
      expect(db.deletes, [targetPath]);
    });
  }
  test('duplicate marker never overwritten missing/malformed target never deleted', () async {
    db.documents[markerPath] = markerData();
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsFormatException);
    db.documents.remove(markerPath); db.documents.remove(targetPath);
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsFormatException);
    db.documents[targetPath] = {...chat.messageData(), 'createdAt': DateTime.utc(2026)};
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsFormatException);
    expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
  });
  for (final path in [targetPath, markerPath, reportPath]) {
    test('transaction cached/pending $path aborts no writes', () async {
      for (final pending in [false, true]) {
        db.cached.clear(); db.pending.clear(); (pending ? db.pending : db.cached).add(path);
        await expectLater(path == reportPath ? gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved) :
          gateway.remove('g', 'z', FirebaseReportReason.spam), throwsStateError);
        expect(db.writes, isEmpty);
      }
    });
  }
  for (final boundary in [memberPath, targetPath, markerPath, reportPath, 'query', 'commit']) {
    test('UID switch during $boundary drops old result and prevents later writes', () async {
      db.gates[boundary] = Completer();
      final request = boundary == reportPath ? gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved) :
        boundary == 'commit' ? gateway.remove('g', 'z', FirebaseReportReason.spam) : gateway.read('g', 'z');
      final check = expectLater(request, throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('b'); db.gates[boundary]!.complete(); await check;
      if (boundary != 'commit') expect(db.writes, isEmpty);
    });
  }
  test('account switch during failed server read replaces old error', () async {
    db.gates['query'] = Completer(); db.errors['query'] = const FormatException('old error');
    final check = expectLater(gateway.read('g', 'z'), throwsStateError);
    await chat.flush(); auth.currentUser = sdk.SdkUser('b'); db.gates['query']!.complete(); await check;
  });
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code is not swallowed or acknowledged by gateway', () async {
      db.errors['query'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.read('g', 'z'), throwsA(isA<FirebaseException>()));
      db.errors['commit'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam), throwsA(isA<FirebaseException>()));
    });
  }
}