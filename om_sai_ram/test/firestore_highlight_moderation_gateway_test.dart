// SDK-shaped doubles verify Dart contracts, NOT deployed rules, SDK transport,
// transaction atomicity/retries, authenticated tokens or server acknowledgements.
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_chat/data/firebase_chat_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firebase_moderation_models.dart';
import 'package:om_sai_ram/features/firebase_moderation/data/firestore_moderation_gateway.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;
import 'firestore_highlights_gateway_test.dart' as highlights;
import 'firestore_moderation_gateway_test.dart' as moderation;
import 'firebase_groups_test.dart' as groups;

const kind = FirebaseModerationTargetKind.highlights;
const target = 'groups/g/highlights/z';
const marker = 'groups/g/moderationRecords/highlights/items/z';
const reports = '$target/reports';
const report = '$reports/r';
Map<String, dynamic> audit() => {...moderation.markerData(), 'targetKind': 'highlights'};

class ScopedModerationDb extends moderation.ModerationDb {
  String? poisonRead, replacement;
  @override
  Future<chat.ChatSnapshot> read(String path, GetOptions? options) async {
    final snapshot = await super.read(path, options);
    return chat.ChatSnapshot(this, path == poisonRead ? replacement! : path, snapshot.raw, snapshot.metadata);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScopedModerationDb db;
  late sdk.SdkAuth auth;
  late FirestoreModerationGateway gateway;
  setUp(() {
    db = ScopedModerationDb(); auth = sdk.SdkAuth();
    db.documents['groups/g'] = {...groups.groupData(), 'updatedAt': moderation.time};
    db.documents.addAll({moderation.memberPath: {'userId': 'a', 'role': 'admin', 'joinedAt': moderation.time},
      target: highlights.highlightData(), report: moderation.reportData(),
      moderation.targetPath: chat.messageData(), moderation.reportPath: moderation.reportData()});
    gateway = FirestoreModerationGateway(auth, db);
  });
  test('highlight server read uses own paths exact six-field model and default20 documentID cursor', () async {
    final page = await gateway.read('g', 'z', kind: kind);
    expect(page.kind, kind); expect(page.target, isA<FirebaseModerationHighlight>());
    final highlight = (page.target! as FirebaseModerationHighlight).highlight;
    expect(highlight.chapterNumber, 17); expect(highlight.paragraphIndex, 0);
    expect(highlight.quote, '  Original quote  '); expect(highlight.text, 'Reflection');
    expect(identical(highlight.createdAt, highlights.instant), isTrue);
    expect(db.reads, [moderation.memberPath, 'groups/g', target, marker]);
    expect(db.queryPath, reports); expect(db.queryLimit, 20);
    expect(db.orders, [(field: FieldPath.documentId, descending: false)]);
    expect(db.sources.every((source) => source == Source.server), isTrue);
  });
  test('same ID message and highlight read independently with no kind inference', () async {
    final message = await gateway.read('g', 'z');
    final highlight = await gateway.read('g', 'z', kind: kind);
    expect(message.target, isA<FirebaseModerationMessage>());
    expect(message.target!.text, 'Original text'); expect(highlight.target!.text, 'Reflection');
    expect(() => highlight.validate(message.binding, 20, null), throwsFormatException);
    expect(() => message.validate(highlight.binding, 20, null, expectedKind: kind), throwsFormatException);
  });
  test('same ID independent minimal markers delete only their kind reports retained', () async {
    await gateway.remove('g', 'z', FirebaseReportReason.other, kind: kind);
    expect(db.operations, ['set:$marker', 'delete:$target']);
    expect(db.documents[report], isNotNull); expect(db.documents[moderation.reportPath], isNotNull);
    // The double records operations without pretending to commit server state.
    db.documents.remove(target); db.documents[marker] = audit();
    final removed = await gateway.read('g', 'z', kind: kind);
    expect(removed.target, isNull); expect(removed.marker!.kind, kind); expect(removed.reports.length, 1);
    expect((await gateway.read('g', 'z')).target, isA<FirebaseModerationMessage>());
    await gateway.remove('g', 'z', FirebaseReportReason.spam);
    expect(db.deletes, [target, moderation.targetPath]);
    expect(db.writes.map((w) => w.data['targetKind']), ['highlights', 'messages']);
  });
  test('max50 and ascending doc ID pagination under deleted highlight', () async {
    db.documents.remove(target);
    for (var i = 0; i < 55; i++) {
      final uid = 's${i.toString().padLeft(2, '0')}'; db.documents['$reports/$uid'] = moderation.reportData(uid: uid);
    }
    final first = await gateway.read('g', 'z', kind: kind, pageSize: 50);
    final second = await gateway.read('g', 'z', kind: kind, after: first.cursor, pageSize: 50);
    expect(first.reports.length, 50); expect(second.reports.length, 6);
    expect(db.after, [first.cursor]); expect(second.target, isNull); expect(second.marker, isNull);
  });
  for (final key in highlights.highlightData().keys) {
    test('highlight target missing $key rejects read and delete', () async {
      db.documents[target] = highlights.highlightData()..remove(key);
      await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.other, kind: kind), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  for (final patch in <Map<String, dynamic>>[
    {'chapterNumber': 0}, {'chapterNumber': 54}, {'chapterNumber': 17.0},
    {'paragraphIndex': -1}, {'paragraphIndex': 2147483648}, {'paragraphIndex': 0.0},
    {'quote': ''}, {'quote': ' '}, {'quote': 'x' * 501}, {'text': ' '}, {'text': 'x' * 2001},
    {'createdAt': null}, {'createdAt': DateTime.utc(2026)}, {'senderUid': 'a/b'},
    {'authorUid': 'forged'}, {'targetKind': 'messages'},
  ]) {
    test('strict highlight schema rejects $patch before mutation', () async {
      db.documents[target] = {...highlights.highlightData(), ...patch};
      await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam, kind: kind), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  test('three-field chat schema is not accepted as highlight and vice versa', () async {
    db.documents[target] = chat.messageData();
    await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
    db.documents[moderation.targetPath] = highlights.highlightData();
    await expectLater(gateway.read('g', 'z'), throwsFormatException);
  });
  for (final patch in <Map<String, dynamic>>[
    {'targetKind': 'messages'}, {'targetId': 'wrong'}, {'authorUid': 'a/b'},
    {'moderatedBy': null}, {'moderatedAt': DateTime.utc(2026)}, {'reason': 'invalid'},
    {'quote': 'copied'}, {'text': 'copied'},
  ]) {
    test('kind-bound minimal audit rejects forged $patch and cannot overwrite', () async {
      db.documents.remove(target); db.documents[marker] = {...audit(), ...patch};
      await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
      db.documents[target] = highlights.highlightData();
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam, kind: kind), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  test('all six audit fields required no target/marker coexistence', () async {
    for (final key in audit().keys) {
      expect(() => FirebaseMessageModerationRecord.parse('z', audit()..remove(key), kind: kind), throwsFormatException);
    }
    db.documents[marker] = audit();
    await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
  });
  for (final reason in FirebaseReportReason.values) {
    test('remove ${reason.name} admin+highlight+marker transaction exact six fields author from sender', () async {
      await gateway.remove('g', 'z', reason, kind: kind);
      expect(db.reads, [moderation.memberPath, 'groups/g', moderation.memberPath, target, marker]);
      expect(db.operations, ['set:$marker', 'delete:$target']); expect(db.transactions, 1);
      expect(db.writes.single.transaction, isTrue);
      expect(db.writes.single.data, {'targetKind': 'highlights', 'targetId': 'z', 'authorUid': 'public-uid',
        'moderatedBy': 'a', 'moderatedAt': FieldValue.serverTimestamp(), 'reason': reason.name});
      expect(db.documents[report], isNotNull); expect(db.deletes, [target]);
    });
  }
  test('duplicate transaction marker and absent target abort without overwrite', () async {
    db.beforeTransaction = () => db.documents[marker] = audit();
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.other, kind: kind), throwsFormatException);
    db.beforeTransaction = null; db.documents.remove(marker); db.documents.remove(target);
    await expectLater(gateway.remove('g', 'z', FirebaseReportReason.other, kind: kind), throwsFormatException);
    expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
  });
  for (final status in [FirebaseReportStatus.resolved, FirebaseReportStatus.dismissed]) {
    test('highlight ${status.name} uses own report UPDATE without forced target deletion', () async {
      db.documents.remove(target); await gateway.resolve('g', 'z', 'r', status, kind: kind);
      expect(db.reads, [moderation.memberPath, report, 'groups/g', moderation.memberPath, report]);
      expect(db.operations, ['update:$report']); expect(db.deletes, isEmpty);
      expect(db.writes.single.data, {'status': status.name, 'resolvedBy': 'a', 'resolvedAt': FieldValue.serverTimestamp()});
      expect(db.documents[moderation.reportPath]!['status'], 'open');
    });
  }
  test('highlight resolve no reopen or overwrite after concurrent resolution', () async {
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.open, kind: kind), throwsFormatException);
    expect(db.reads, isEmpty);
    db.beforeTransaction = () => db.documents[report] = moderation.reportData(status: 'dismissed');
    await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved, kind: kind), throwsFormatException);
    expect(db.writes, isEmpty);
  });
  for (final role in ['member', 'group_lead']) {
    test('$role actual SDK membership denies each highlight action', () async {
      db.documents[moderation.memberPath]!['role'] = role;
      expect(await gateway.role('g'), role == 'member' ? FirebaseGroupRole.member : FirebaseGroupRole.groupLead);
      await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
      await expectLater(gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved, kind: kind), throwsFormatException);
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.spam, kind: kind), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.transactions, 0);
    });
  }
  for (final operation in ['resolve', 'remove']) {
    test('highlight $operation rechecks revoked role inside transaction', () async {
      db.beforeTransaction = () => db.documents[moderation.memberPath]!['role'] = 'member';
      await expectLater(operation == 'remove' ? gateway.remove('g', 'z', FirebaseReportReason.spam, kind: kind)
        : gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved, kind: kind), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  for (final path in [moderation.memberPath, target, marker, report, 'query']) {
    test('highlight cached/pending $path never accepted', () async {
      for (final pending in [false, true]) {
        db.cached.clear(); db.pending.clear();
        if (path == 'query') { db.queryCached = !pending; db.queryPending = pending; }
        else { (pending ? db.pending : db.cached).add(path); }
        await expectLater(gateway.read('g', 'z', kind: kind), throwsStateError);
      }
    });
  }
  for (final path in [moderation.memberPath, target, marker, report, 'query', 'commit']) {
    test('highlight UID switch across await $path fails closed', () async {
      db.gates[path] = Completer();
      final request = path == report ? gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved, kind: kind)
        : path == 'commit' ? gateway.remove('g', 'z', FirebaseReportReason.spam, kind: kind)
        : gateway.read('g', 'z', kind: kind);
      final check = expectLater(request, throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('b'); db.gates[path]!.complete(); await check;
      if (path != 'commit') expect(db.writes, isEmpty);
    });
  }
  for (final path in ['groups/other/highlights/z/reports/r', 'groups/g/messages/z/reports/r',
      '$target/reports/other']) {
    test('report path scope $path rejected', () async {
      db.poisonPath = path; await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
    });
  }
  for (final bad in ['', '..', 'a/b', '__reserved__']) {
    test('invalid highlight scope/cursor $bad rejected before SDK', () async {
      await expectLater(gateway.read('g', bad, kind: kind), throwsFormatException);
      await expectLater(gateway.read(bad, 'z', kind: kind), throwsFormatException);
      await expectLater(gateway.read('g', 'z', kind: kind, after: bad), throwsFormatException);
      await expectLater(gateway.remove('g', bad, FirebaseReportReason.other, kind: kind), throwsFormatException);
      await expectLater(gateway.resolve('g', 'z', bad, FirebaseReportStatus.resolved, kind: kind), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  for (final size in [0, 51]) {
    test('highlight report page size $size rejected before SDK', () async {
      await expectLater(gateway.read('g', 'z', pageSize: size, kind: kind), throwsFormatException);
      expect(db.reads, isEmpty);
    });
  }
  test('duplicate/order poison reports rejected no partial page', () async {
    db.forcedIds = ['r', 'r']; await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
    db.documents['$reports/s'] = moderation.reportData(uid: 's'); db.forcedIds = ['s', 'r'];
    await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
  });
  for (final pair in [(moderation.memberPath, 'groups/other/members/a'),
      (target, moderation.targetPath), (marker, moderation.markerPath)]) {
    test('highlight selected document path ${pair.$1} cannot alias other group/kind', () async {
      db.poisonRead = pair.$1; db.replacement = pair.$2;
      await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
      await expectLater(gateway.remove('g', 'z', FirebaseReportReason.other, kind: kind), throwsFormatException);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  for (final path in [moderation.memberPath, target, marker, report]) {
    test('highlight transaction metadata $path prevents every write', () async {
      db.beforeTransaction = () => db.pending.add(path);
      await expectLater(path == report ? gateway.resolve('g', 'z', 'r', FirebaseReportStatus.resolved, kind: kind)
        : gateway.remove('g', 'z', FirebaseReportReason.other, kind: kind), throwsStateError);
      expect(db.writes, isEmpty); expect(db.deletes, isEmpty);
    });
  }
  for (final patch in <Map<String, dynamic>>[
    {'reporterUid': 'other'}, {'status': 'resolved', 'resolvedAt': null}, {'reason': 'invented'}, {'text': 'copied'},
  ]) {
    test('highlight report exact schema rejects $patch', () async {
      db.documents[report] = {...moderation.reportData(), ...patch};
      await expectLater(gateway.read('g', 'z', kind: kind), throwsFormatException);
    });
  }
  test('highlight UID switch during failed server response does not leak old error', () async {
    db.gates['query'] = Completer(); db.errors['query'] = const FormatException('old response');
    final check = expectLater(gateway.read('g', 'z', kind: kind), throwsStateError);
    await chat.flush(); auth.currentUser = sdk.SdkUser('b'); db.gates['query']!.complete(); await check;
  });
}