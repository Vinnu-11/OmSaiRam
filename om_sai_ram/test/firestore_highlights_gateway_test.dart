// SDK-shaped doubles: test Dart calls/contracts, not real rules or server ACKs.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firebase_highlight_models.dart';
import 'package:om_sai_ram/features/firebase_highlights/data/firestore_highlights_gateway.dart';
import 'firebase_groups_test.dart' as groups;
import 'firestore_assignments_gateway_test.dart' as sdk;

const highlightsPath = 'groups/g/highlights';
const highlightPath = '$highlightsPath/z';
const reportPath = '$highlightPath/reports/a';
final instant = Timestamp(1700000000, 123456789);
Map<String, dynamic> highlightData({Timestamp? time, int chapter = 17,
    int paragraph = 0, String quote = '  Original quote  ', String text = 'Reflection'}) => {
  'senderUid': 'public-uid', 'chapterNumber': chapter, 'paragraphIndex': paragraph,
  'quote': quote, 'text': text, 'createdAt': time ?? instant
};
FirebaseHighlightDraft draft({int chapter = 17}) => FirebaseHighlightDraft(chapter, 0, '  Original quote  ', 'Reflection');

class HighlightSnapshot extends sdk.Snapshot {
  @override
  final DocumentReference<sdk.Data> reference;
  HighlightSnapshot(HighlightsDb db, String path, sdk.Data? raw, SnapshotMetadata metadata)
      : reference = HighlightDocument(db, path), super(path.split('/').last, raw, metadata);
}
class HighlightQueryDocument extends HighlightSnapshot implements QueryDocumentSnapshot<sdk.Data> {
  HighlightQueryDocument(super.db, super.path, super.raw, super.metadata);
  @override
  sdk.Data data() => raw!;
}
class HighlightsDb extends sdk.SdkDb {
  final orders = <({Object field, bool descending})>[];
  List<Object?>? after;
  String? poisonPath, poisonRead;
  List<String>? forcedIds;
  int allocations = 0;
  @override
  CollectionReference<sdk.Data> collection(String path) => HighlightCollection(this, path);
  @override
  Future<HighlightSnapshot> read(String path, GetOptions? options) async {
    final result = await super.read(path, options);
    return HighlightSnapshot(this, poisonRead == path ? 'groups/other/highlights/z' : path, result.raw, result.metadata);
  }
}
class HighlightCollection extends sdk.SdkCollection {
  HighlightCollection(HighlightsDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) {
    final highlights = db as HighlightsDb;
    return HighlightDocument(highlights, '${this.path}/${path ?? 'auto${++highlights.allocations}'}');
  }
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) =>
      HighlightQuery(db as HighlightsDb, path).orderBy(field, descending: descending);
}
class HighlightDocument extends sdk.SdkDocument {
  HighlightDocument(HighlightsDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String collectionPath) =>
      HighlightCollection(db as HighlightsDb, '$path/$collectionPath');
  @override
  Future<void> set(sdk.Data data, [SetOptions? options]) async {
    expect(options, isNull); // No merge/overwrite API.
    if (db.gates['set'] != null) await db.gates['set']!.future;
    if (db.errors['set'] != null) throw db.errors['set']!;
    db.writes.add((path: path, data: data, transaction: false));
  }
}
class HighlightQuery extends Fake implements Query<sdk.Data> {
  final HighlightsDb db;
  final String path;
  HighlightQuery(this.db, this.path);
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
    db.queryPath = path; db.sources.add(options?.source);
    if (db.gates['query'] != null) await db.gates['query']!.future;
    if (db.errors['query'] != null) throw db.errors['query']!;
    final ids = db.forcedIds ?? db.documents.keys.where((key) => key.startsWith('$path/') &&
      !key.substring(path.length + 1).contains('/')).map((key) => key.split('/').last).toList();
    FirebaseHighlightCursor cursor(String id) => FirebaseHighlightCursor(
      db.documents['$path/$id']!['createdAt'] is Timestamp
        ? db.documents['$path/$id']!['createdAt'] as Timestamp : instant, id);
    if (db.forcedIds == null) ids.sort((a, b) => highlightCursorCompare(cursor(a), cursor(b)));
    final filtered = ids.where((id) => db.after == null || highlightCursorCompare(cursor(id),
      FirebaseHighlightCursor(db.after![0] as Timestamp, db.after![1] as String)) > 0);
    return sdk.QueryResult(filtered.take(db.queryLimit!).map((id) => HighlightQueryDocument(
      db, db.poisonPath ?? '$path/$id', db.documents['$path/$id'], db.metadata('$path/$id'))).toList(),
      sdk.Metadata(isFromCache: db.queryCached, hasPendingWrites: db.queryPending));
  }
}
void seed(HighlightsDb db) {
  db.documents.addAll({
    'users/a': {'displayName': 'Private name', 'createdAt': instant, 'updatedAt': instant},
    'groups/g': groups.groupData(),
    'groups/g/members/a': {'userId': 'a', 'role': 'member', 'joinedAt': instant},
    highlightPath: highlightData(),
  });
}
Future<void> flush() async {
  for (var i = 0; i < 16; i++) { await Future<void>.delayed(Duration.zero); }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HighlightsDb db;
  late sdk.SdkAuth auth;
  late FirestoreHighlightsGateway gateway;
  setUp(() { db = HighlightsDb(); auth = sdk.SdkAuth(); seed(db); gateway = FirestoreHighlightsGateway(auth, db); });

  test('archived highlights stay readable but cannot be shared or reported', () async {
    db.documents['groups/g']!.addAll({'archived': true, 'lifecycleRevision': 1,
      'lifecycleChangedBy': 'a', 'lifecycleChangedAt': db.documents['groups/g']!['updatedAt']});
    final page = await gateway.read('g');
    expect(page.archived, true); expect(page.highlights, isNotEmpty);
    await expectLater(gateway.send('g', draft()), throwsFormatException);
    await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.spam, ''), throwsFormatException);
    expect(db.writes, isEmpty); expect(db.allocations, 0);
  });

  test('six fields preserve original text and Timestamp object/nanos with immutable page', () {
    final row = FirebaseHighlight.parse('g', 'z', highlightData());
    expect(row.quote, '  Original quote  '); expect(row.text, 'Reflection');
    expect(identical(row.createdAt, instant), isTrue);
    expect(identical(row.cursor.createdAt, instant), isTrue);
    expect(row.createdAt.nanoseconds, 123456789);
    expect(() => FirebaseHighlightsPage('a', 'g', [row]).highlights.clear(), throwsUnsupportedError);
  });
  for (final chapter in [1, 16, 17, 18, 19, 43, 44, 51, 52, 53]) {
    test('original chapter $chapter is not normalized to assignment unit or SQL ID', () async {
      expect(FirebaseHighlight.parse('g', 'z', highlightData(chapter: chapter)).chapterNumber, chapter);
      await gateway.send('g', draft(chapter: chapter));
      expect(db.writes.single.data['chapterNumber'], chapter);
    });
  }
  for (final key in highlightData().keys) {
    test('missing $key rejects full page rather than silently dropping row', () async {
      db.documents['$highlightsPath/a'] = highlightData()..remove(key);
      await expectLater(gateway.read('g'), throwsFormatException);
    });
  }
  for (final patch in <Map<String, dynamic>>[
    {'chapterNumber': 0}, {'chapterNumber': 54}, {'chapterNumber': 17.0},
    {'chapterNumber': '17'}, {'chapterNumber': '16-17'}, {'chapterNumber': null},
    {'paragraphIndex': -1}, {'paragraphIndex': 2147483648}, {'paragraphIndex': 0.0},
    {'paragraphIndex': '0'}, {'paragraphIndex': null}, {'paragraphIndex': false},
    {'quote': ''}, {'quote': '\n \t'}, {'quote': 'x' * 501}, {'quote': 17},
    {'text': ''}, {'text': '\n \t'}, {'text': 'x' * 2001}, {'text': null},
    {'senderUid': null}, {'senderUid': true}, {'createdAt': null},
    {'createdAt': DateTime.utc(2026)}, {'createdAt': 1700000000},
    {'email': 'private'}, {'displayName': 'private'}, {'groupId': 'other'},
    {'unitKey': '16-17'}, {'chapterId': 999}, {'status': 'hidden'},
  ]) {
    test('strict schema/types/bounds rejects $patch in full SDK page', () async {
      db.documents['$highlightsPath/a'] = {...highlightData(), ...patch};
      await expectLater(gateway.read('g'), throwsFormatException);
    });
  }
  test('exact quote/comment/paragraph upper bounds and null record contract', () {
    final row = FirebaseHighlight.parse('g', 'z', highlightData(chapter: 53,
      paragraph: 2147483647, quote: 'x' * 500, text: 'y' * 2000));
    expect(row.paragraphIndex, 2147483647); expect(row.quote.length, 500);
    expect(() => FirebaseHighlight.parse('g', 'z', null), throwsFormatException);
    expect(() => FirebaseHighlightDraft(0, 0, 'q', 't'), throwsFormatException);
    expect(() => FirebaseHighlightDraft(17, -1, 'q', 't'), throwsFormatException);
    expect(() => FirebaseHighlightDraft(17, 2147483648, 'q', 't'), throwsFormatException);
    expect(() => FirebaseHighlightDraft(17, 0, ' ', 't'), throwsFormatException);
    expect(() => FirebaseHighlightDraft(17, 0, 'q', 'x' * 2001), throwsFormatException);
  });
  for (final bad in ['', '.', '..', 'a/b', '__reserved__', 'é' * 751]) {
    test('robust path validation group/id/sender/cursor/report $bad before SDK', () async {
      expect(() => FirebaseHighlightCursor(instant, bad), throwsFormatException);
      expect(() => FirebaseHighlight.parse('g', bad, highlightData()), throwsFormatException);
      expect(() => FirebaseHighlight.parse('g', 'z', {...highlightData(), 'senderUid': bad}), throwsFormatException);
      await expectLater(gateway.read(bad), throwsFormatException);
      await expectLater(gateway.send(bad, draft()), throwsFormatException);
      await expectLater(gateway.report('g', bad, FirebaseHighlightReportReason.spam, ''), throwsFormatException);
      expect(db.sources, isEmpty); expect(db.allocations, 0);
    });
  }
  test('valid 1500 UTF8 bytes and UTF8 ordering supplementary versus BMP', () {
    expect(FirebaseHighlightCursor(instant, 'é' * 750).id, 'é' * 750);
    expect(highlightIdCompare('\u{10000}', '\uE000'), greaterThan(0));
    expect(highlightCursorCompare(FirebaseHighlightCursor(Timestamp(2, 0), 'a'),
      FirebaseHighlightCursor(Timestamp(1, 999999999), 'z')), lessThan(0));
    expect(highlightCursorCompare(FirebaseHighlightCursor(Timestamp(1, 2), 'a'),
      FirebaseHighlightCursor(Timestamp(1, 1), 'z')), lessThan(0));
    expect(highlightCursorCompare(FirebaseHighlightCursor(instant, 'z'),
      FirebaseHighlightCursor(instant, 'a')), lessThan(0));
  });
  test('server read exact orders default20 max50 privacy self-profile and member only', () async {
    final page = await gateway.read('g');
    expect(page.highlights.single.senderUid, 'public-uid');
    expect(db.orders, [(field: 'createdAt', descending: true), (field: FieldPath.documentId, descending: true)]);
    expect(db.queryPath, highlightsPath); expect(db.queryLimit, 20);
    expect(db.reads, ['users/a', 'groups/g', 'groups/g/members/a']);
    expect(db.sources.every((source) => source == Source.server), isTrue);
    await gateway.read('g', pageSize: 50); expect(db.queryLimit, 50);
  });
  test('cursor object preserves nanos ties and newer head insertion does not restart older page', () async {
    db.documents['$highlightsPath/a'] = highlightData();
    final first = await gateway.read('g', pageSize: 1);
    db.documents['$highlightsPath/new'] = highlightData(time: Timestamp(instant.seconds, instant.nanoseconds + 1));
    final second = await gateway.read('g', pageSize: 1, after: first.cursor);
    expect(first.highlights.single.id, 'z'); expect(second.highlights.single.id, 'a');
    expect(identical(db.after![0], instant), isTrue); expect(db.after![1], 'z');
  });
  for (final size in [0, -1, 51]) {
    test('pageSize $size blocked before SDK', () async {
      await expectLater(gateway.read('g', pageSize: size), throwsFormatException);
      expect(db.sources, isEmpty);
    });
  }
  test('empty page no cursor no automatic query', () async {
    db.documents.remove(highlightPath);
    final page = await gateway.read('g');
    expect(page.highlights, isEmpty); expect(page.cursor, isNull); expect(page.hasMore(20), isFalse);
    expect(db.sources.length, 4);
  });
  for (final role in ['member', 'admin', 'group_lead']) {
    test('$role send/report exact six/seven bodies identity only SDK UID serverTimestamp', () async {
      db.documents['groups/g/members/a']!['role'] = role;
      await gateway.send('g', draft());
      await gateway.report('g', 'z', FirebaseHighlightReportReason.harassment, '  Details  ');
      expect(db.writes.first.path, '$highlightsPath/auto1');
      expect(db.writes.first.transaction, isFalse);
      expect(db.writes.first.data, {
        'senderUid': 'a', 'chapterNumber': 17, 'paragraphIndex': 0,
        'quote': '  Original quote  ', 'text': 'Reflection', 'createdAt': FieldValue.serverTimestamp()
      });
      expect(db.writes.last.path, reportPath);
      expect(db.writes.last.transaction, isTrue);
      expect(db.writes.last.data, {
        'reporterUid': 'a', 'reason': 'harassment', 'details': '  Details  ',
        'createdAt': FieldValue.serverTimestamp(), 'status': 'open', 'resolvedBy': null, 'resolvedAt': null
      });
      expect(db.reads.sublist(db.reads.length - 2), [reportPath, highlightPath]);
      expect(db.reads.any((path) => path.contains('public-uid') || path.contains('memberProfiles')), isFalse);
    });
  }
  for (final path in ['users/a', 'groups/g', 'groups/g/members/a']) {
    test('missing/malformed $path blocks reads writes reports before allocation', () async {
      final saved = db.documents.remove(path)!;
      await expectLater(gateway.read('g'), throwsFormatException);
      await expectLater(gateway.send('g', draft()), throwsFormatException);
      await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.other, ''), throwsFormatException);
      db.documents[path] = {...saved, 'admin': true};
      await expectLater(gateway.read('g'), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.allocations, 0);
    });
  }
  test('membership actual UID/role not creator claims validates before write', () async {
    db.documents['groups/g/members/a']!['role'] = 'owner';
    await expectLater(gateway.send('g', draft()), throwsFormatException);
    db.documents['groups/g/members/a']!['role'] = 'member';
    db.documents['groups/g/members/a']!['userId'] = 'b';
    await expectLater(gateway.send('g', draft()), throwsFormatException);
    expect(db.allocations, 0);
  });
  for (final path in ['users/a', 'groups/g', 'groups/g/members/a', highlightPath]) {
    test('cache/pending $path reject complete page', () async {
      db.cached.add(path); await expectLater(gateway.read('g'), throwsStateError);
      db.cached.clear(); db.pending.add(path); await expectLater(gateway.read('g'), throwsStateError);
    });
  }
  test('query cache/pending refuse data', () async {
    db.queryCached = true; await expectLater(gateway.read('g'), throwsStateError);
    db.queryCached = false; db.queryPending = true; await expectLater(gateway.read('g'), throwsStateError);
  });
  test('crossgroup query path tamper fails closed', () async {
    db.poisonPath = 'groups/other/highlights/z';
    await expectLater(gateway.read('g'), throwsFormatException);
  });
  for (final path in ['users/a', 'groups/g', 'groups/g/members/a', reportPath, highlightPath]) {
    test('server document path tamper $path aborts report', () async {
      db.poisonRead = path;
      await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.spam, ''), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final ids in [<String>['z', 'z'], <String>['a', 'z']]) {
    test('duplicate/order SDK page $ids rejected', () async {
      db.documents['$highlightsPath/a'] = highlightData(); db.forcedIds = ids;
      await expectLater(gateway.read('g'), throwsFormatException);
    });
  }
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code query exception no partial read explicit retry', () async {
      db.errors['query'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.read('g'), throwsA(isA<FirebaseException>()));
      db.errors.clear(); expect((await gateway.read('g')).highlights.length, 1);
    });
  }
  test('signout invalid identity blocks all SDK work', () async {
    auth.currentUser = null;
    await expectLater(gateway.read('g'), throwsFormatException);
    await expectLater(gateway.send('g', draft()), throwsFormatException);
    await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.spam, ''), throwsFormatException);
    expect(db.sources, isEmpty);
  });
  test('oversized report rejects before SDK exact1000 accepted', () async {
    await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.other, 'x' * 1001), throwsFormatException);
    expect(db.sources, isEmpty);
    await gateway.report('g', 'z', FirebaseHighlightReportReason.other, 'x' * 1000);
    expect((db.writes.single.data['details'] as String).length, 1000);
  });
  test('transport send uncertainty allocates once never automatically retries', () async {
    db.errors['set'] = StateError('possible commit');
    await expectLater(gateway.send('g', draft()), throwsA(isA<FirebaseHighlightDeliveryUncertain>()));
    expect(db.allocations, 1); expect(db.writes, isEmpty);
  });
  for (final reason in FirebaseHighlightReportReason.values) {
    test('report ${reason.name} exact schema new server createdAt not target timestamp', () async {
      await gateway.report('g', 'z', reason, '');
      expect(db.writes.single.data['reason'], reason.name);
      expect(db.writes.single.data.length, 7);
      expect(db.writes.single.data['createdAt'], FieldValue.serverTimestamp());
      expect(db.writes.single.data['createdAt'], isNot(instant));
    });
  }
  test('existing report including resolved rejected with no admin overwrite', () async {
    db.documents[reportPath] = {'status': 'resolved'};
    db.documents['groups/g/members/a']!['role'] = 'admin';
    await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.other, ''), throwsFormatException);
    expect(db.reads.sublist(3), [reportPath, highlightPath]); expect(db.writes, isEmpty);
  });
  test('removed or malformed target rejects report with no write', () async {
    db.documents.remove(highlightPath);
    await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.other, ''), throwsFormatException);
    db.documents[highlightPath] = {...highlightData(), 'createdAt': null};
    await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.other, ''), throwsFormatException);
    expect(db.writes, isEmpty);
  });
  for (final path in [reportPath, highlightPath]) {
    test('report cache/pending $path transaction cannot confirm', () async {
      db.cached.add(path);
      await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.spam, ''), throwsStateError);
      db.cached.clear(); db.pending.add(path);
      await expectLater(gateway.report('g', 'z', FirebaseHighlightReportReason.spam, ''), throwsStateError);
      expect(db.writes, isEmpty);
    });
  }
  for (final boundary in ['users/a', 'groups/g', 'groups/g/members/a', 'query', reportPath, highlightPath, 'set']) {
    test('SDK delayed UID switch at $boundary rejects result/no subsequent writes', () async {
      db.gates[boundary] = Completer();
      final request = boundary == 'set' ? gateway.send('g', draft())
        : [reportPath, highlightPath].contains(boundary)
          ? gateway.report('g', 'z', FirebaseHighlightReportReason.spam, '') : gateway.read('g');
      final check = expectLater(request, throwsStateError);
      await flush(); auth.currentUser = sdk.SdkUser('b'); db.gates[boundary]!.complete(); await check;
      if (boundary != 'set') expect(db.writes, isEmpty);
    });
  }
  test('failed await still checks current SDK UID rather than leaking old error', () async {
    db.gates['query'] = Completer(); db.errors['query'] = const FormatException('old error');
    final check = expectLater(gateway.read('g'), throwsStateError);
    await flush(); auth.currentUser = sdk.SdkUser('b'); db.gates['query']!.complete(); await check;
  });
}