// SDK-shaped doubles only: not live transport, rules, real retries or ACK certification.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_scheduling/data/firebase_schedule_models.dart';
import 'package:om_sai_ram/features/firebase_scheduling/data/firestore_scheduling_gateway.dart';
import 'firebase_schedule_models_test.dart' as models;
import 'firebase_groups_test.dart' as groups;
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;

const binding = (uid: 'a', groupId: 'g');
const groupPath = 'groups/g', actorPath = '$groupPath/members/a', targetPath = '$groupPath/members/b';
const assignmentPath = '$groupPath/readingWeeks/1/members/b/assignments/16-17';
final instant = Timestamp(1700000000, 123456789);
sdk.Data member(String uid, String role) => {'userId': uid, 'role': role, 'joinedAt': instant};
FirebaseScheduleSettings settings(ScheduleDb db) => FirebaseScheduleSettings(
  mode: db.documents[groupPath]!['mode'] as String,
  chaptersPerWeek: db.documents[groupPath]!['chaptersPerWeek'] as int,
  startChapter: db.documents[groupPath]!['startChapter'] as int,
  currentWeek: db.documents[groupPath]!['currentWeek'] as int);
FirebaseSchedulePlan plan() => models.plan(members: ['b'], weeks: 1, start: 17);

class ScheduleDb extends chat.ChatDb {
  int attempts = 1;
  bool loseAck = false;
  void Function(int)? beforeAttempt;
  @override
  CollectionReference<sdk.Data> collection(String path) => ScheduleCollection(this, path);
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
      final transaction = ScheduleTransaction(this);
      final result = await handler(transaction);
      if (i < attempts - 1) continue;
      if (gates['commit'] != null) await gates['commit']!.future;
      if (errors['commit'] != null) throw errors['commit']!;
      for (final write in transaction.staged) {
        final data = write.data.map((key, value) => MapEntry(key,
          value is FieldValue ? instant : value));
        if (write.path == groupPath) { documents[write.path]!.addAll(data); }
        else { documents[write.path] = data; }
      }
      writes.addAll(transaction.staged);
      if (loseAck) throw StateError('Simulated lost ACK');
      return result;
    }
    throw StateError('No attempts');
  }
}
class ScheduleTransaction extends sdk.SdkTransaction {
  final staged = <({String path, sdk.Data data, bool transaction})>[];
  ScheduleTransaction(ScheduleDb super.db);
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> reference) {
    if (staged.isNotEmpty) throw StateError('Read after write');
    return super.get(reference);
  }
  @override
  Transaction set<T>(DocumentReference<T> reference, T data, [SetOptions? options]) {
    if (options != null || reference.path == groupPath) throw StateError('No merge or group set');
    staged.add((path: reference.path, data: Map.of(data as sdk.Data), transaction: true)); return this;
  }
  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    if (reference.path != groupPath) throw StateError('Only group advance updates');
    staged.add((path: reference.path, data: data.map((key, value) => MapEntry(key as String, value)), transaction: true)); return this;
  }
}
class ScheduleCollection extends chat.ChatCollection {
  ScheduleCollection(ScheduleDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) => ScheduleDocument(db as ScheduleDb, '${this.path}/$path');
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) =>
    ScheduleQuery(db as ScheduleDb, path).orderBy(field, descending: descending);
}
class ScheduleDocument extends chat.ChatDocument {
  ScheduleDocument(ScheduleDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String path) => ScheduleCollection(db as ScheduleDb, '${this.path}/$path');
}
class ScheduleQuery extends chat.ChatQuery {
  ScheduleQuery(ScheduleDb super.db, super.path);
  @override
  Future<QuerySnapshot<sdk.Data>> get([GetOptions? options]) async {
    db.queryPath = path; db.sources.add(options?.source);
    if (db.gates['query'] != null) await db.gates['query']!.future;
    if (db.errors['query'] != null) throw db.errors['query']!;
    final ids = db.forcedIds ?? (db.documents.keys.where((p) => p.startsWith('$path/') &&
      !p.substring(path.length+1).contains('/')).map((p) => p.split('/').last).toList()..sort(scheduleUidCompare));
    return sdk.QueryResult(ids.where((id) => db.after == null || scheduleUidCompare(id, db.after!.single as String) > 0)
      .take(db.queryLimit!).map((id) => chat.ChatQueryDocument(db, db.poisonPath ?? '$path/$id',
        db.documents['$path/$id'], db.metadata('$path/$id'))).toList(),
      sdk.Metadata(isFromCache: db.queryCached, hasPendingWrites: db.queryPending));
  }
}
void seed(ScheduleDb db) {
  db.documents.addAll({'users/a': {'displayName': 'Private', 'createdAt': instant, 'updatedAt': instant},
    groupPath: {...groups.groupData(), 'chaptersPerWeek': 1, 'startChapter': 1, 'currentWeek': 1},
    actorPath: member('a', 'admin'), targetPath: member('b', 'member')});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScheduleDb db;
  late sdk.SdkAuth auth;
  late FirestoreSchedulingGateway gateway;
  setUp(() { db = ScheduleDb(); seed(db); auth = sdk.SdkAuth(); gateway = FirestoreSchedulingGateway(auth, db); });
  test('suggested plan uses unchanged gateway canonical paths and exact stale-settings guard', () async {
    db.documents[groupPath]!['chaptersPerWeek']=2;
    final head=await gateway.load(binding);
    final result=suggestFirebaseSchedule(head.settings,models.plan(members:['b','a'],weeks:1),const [
      FirebaseScheduleHint(position:0,chapterStart:17),FirebaseScheduleHint(position:1,chapterStart:20)]);
    expect(db.writes,isEmpty);expect(db.transactions,0);
    final before=Map.of(db.documents[groupPath]!);
    await gateway.commit(binding,result.preview.settings,result.plan);
    expect(db.writes.map((w)=>w.path),[
      '$groupPath/readingWeeks/1/members/b/assignments/16-17',
      '$groupPath/readingWeeks/1/members/b/assignments/18-19',
      '$groupPath/readingWeeks/1/members/a/assignments/20',
      '$groupPath/readingWeeks/1/members/a/assignments/21']);
    expect(db.documents[groupPath],before);
  });
  test('suggestion changed settings before confirmation reject all gateway writes', () async {
    final head=await gateway.load(binding);
    final result=suggestFirebaseSchedule(head.settings,models.plan(members:['a','b'],weeks:1),const [
      FirebaseScheduleHint(position:0,chapterStart:17),FirebaseScheduleHint(position:1,chapterStart:19)]);
    db.documents[groupPath]!['currentWeek']=2;
    await expectLater(gateway.commit(binding,result.preview.settings,result.plan),throwsFormatException);
    expect(db.writes,isEmpty);
  });
  test('server-only scoped roster default20 max50 ordered replacement pages no private targets', () async {
    for (var i = 0; i < 25; i++) { db.documents['$groupPath/members/u${i.toString().padLeft(2,"0")}'] = member('u${i.toString().padLeft(2,"0")}', 'member'); }
    final first = await gateway.load(binding);
    expect(first.members.items.length, 20); expect(first.members.hasMore, isTrue);
    final second = await gateway.load(binding, cursor: first.members.cursor);
    expect(second.members.items.length, 7); expect(second.members.hasMore, isFalse);
    expect(db.after, [first.members.cursor]); expect(db.queryPath, '$groupPath/members');
    expect(db.orders.every((o) => o.field == FieldPath.documentId && !o.descending), isTrue);
    expect(db.sources, everyElement(Source.server)); expect(db.reads.toSet(), {'users/a',groupPath,actorPath});
    db.after = null; await gateway.load(binding, pageSize: 50); expect(db.queryLimit, 50);
  });
  for (final role in ['admin','group_lead']) {
    test('$role canonical assignment exact11 fields all reads before writes group unchanged', () async {
      db.documents[actorPath]!['role'] = role;
      final groupBefore = Map.of(db.documents[groupPath]!);
      await gateway.commit(binding, settings(db), plan());
      expect(db.reads, ['users/a',groupPath,actorPath,targetPath,assignmentPath]);
      expect(db.sources, [Source.server,null,null,null,null]);
      expect(db.writes.single.path, assignmentPath);
      expect(db.writes.single.data, {'groupId':'g','userId':'b','weekNumber':1,'unitKey':'16-17',
        'chapterStart':16,'chapterEnd':17,'scheduledDate':null,'createdBy':'a','createdAt':FieldValue.serverTimestamp(),
        'status':'not_started','progressUpdatedAt':FieldValue.serverTimestamp()});
      expect(db.documents[groupPath], groupBefore); expect(db.reads, isNot(contains('users/b')));
    });
  }
  test('self assignment still reads target membership and canonical missing doc', () async {
    await gateway.commit(binding, settings(db), models.plan(members:['a'], weeks:1, start:53));
    expect(db.reads.where((p) => p == actorPath).length, 2);
    expect(db.writes.single.path, '$groupPath/readingWeeks/1/members/a/assignments/51-53');
  });
  test('explicit date model transaction preserves seven UTC days', () async {
    final date = DateTime.utc(2026,3,8,2);
    await gateway.commit(binding, settings(db), models.plan(members:['b'], weeks:2, date:date));
    expect(db.writes.map((w) => w.data['scheduledDate']), [Timestamp.fromDate(date),Timestamp.fromDate(date.add(const Duration(days:7)))]);
  });
  test('atomic bounds48 writes12 targets accepted reads all missing docs before staging', () async {
    final members = List.generate(12, (i) => 'u$i');
    for (final uid in members) { db.documents['$groupPath/members/$uid'] = member(uid,'member'); }
    db.documents[groupPath]!['chaptersPerWeek'] = 4;
    await gateway.commit(binding, settings(db), models.plan(members:members, weeks:1, mode:'synchronized'));
    expect(db.writes.length, 48); expect(db.reads.length, 1+2+12+48);
  });
  for (final p in [models.plan(members:List.generate(13,(i)=>'u$i'), weeks:1),
    models.plan(members:['b'],weeks:12,remainder:'cycle'), models.plan(members:['b','b'],weeks:1),
    models.plan(mode:'synchronized',remainder:'extend_last')]) {
    test('oversized or invalid atomic plan rejected before IO ${p.memberUids.length}/${p.weeksAhead}/${p.remainderMode}', () async {
      final s = models.settings(width:p.weeksAhead == 12 ? 48 : 1, week:1);
      await expectLater(gateway.commit(binding,s,p), throwsFormatException);
      expect(db.reads,isEmpty); expect(db.transactions,0);
    });
  }
  for (final field in ['mode','chaptersPerWeek','startChapter','currentWeek']) {
    test('exact settings compare $field including combined aliases rejects stale', () async {
      if (field == 'startChapter') db.documents[groupPath]![field] = 51;
      final expected = settings(db);
      db.documents[groupPath]![field] = switch(field) {'mode'=>'saptah','chaptersPerWeek'=>2,'startChapter'=>53,_=>2};
      await expectLater(gateway.commit(binding,expected,plan()),throwsFormatException); expect(db.writes,isEmpty);
    });
  }
  test('unrelated name/updatedAt change allowed exact scheduling snapshot only', () async {
    final expected = settings(db); db.documents[groupPath]!['name']='Concurrent name';
    db.documents[groupPath]!['updatedAt']=Timestamp(instant.seconds,instant.nanoseconds+1);
    await gateway.commit(binding,expected,plan()); expect(db.writes.length,1);
  });
  for (final changed in ['settings','actor','target','duplicate','uid']) {
    test('commit retry revalidates $changed discards first attempt staged writes', () async {
      final expected = settings(db); db.attempts=2;
      db.beforeAttempt=(i) { if(i==0)return;
        switch(changed) {
          case 'settings': db.documents[groupPath]!['currentWeek']=2;
          case 'actor': db.documents[actorPath]!['role']='member';
          case 'target': db.documents.remove(targetPath);
          case 'duplicate': db.documents[assignmentPath]={'existing':'even malformed blocks overwrite'};
          case 'uid': auth.currentUser=sdk.SdkUser('new');
        }
      };
      await expectLater(gateway.commit(binding,expected,plan()),changed=='uid'?throwsStateError:throwsFormatException);
      expect(db.writes,isEmpty);
    });
  }
  test('duplicate at LAST row aborts entire multi assignment plan no skips', () async {
    db.documents['$groupPath/readingWeeks/1/members/b/assignments/18-19']={'existing':true};
    db.documents[groupPath]!['chaptersPerWeek']=2;
    await expectLater(gateway.commit(binding,settings(db),plan()),throwsFormatException);
    expect(db.writes,isEmpty); expect(db.documents.containsKey(assignmentPath),isFalse);
  });
  test('successful transaction retry commits once', () async {
    db.attempts=3; await gateway.commit(binding,settings(db),plan());
    expect(db.writes.length,1); expect(db.reads.where((p)=>p==assignmentPath).length,3);
  });
  test('caller collection mutation during await cannot alter captured targets or writes', () async {
    final members = ['b'];
    final captured = models.plan(members: members, weeks: 1, start: 17);
    db.gates['users/a'] = Completer();
    final request = gateway.commit(binding,settings(db),captured);
    members.clear(); members.add('new-user');
    db.gates['users/a']!.complete(); await request;
    expect(db.writes.single.path,assignmentPath);
    expect(db.reads,isNot(contains('$groupPath/members/new-user')));
  });
  test('Firestore UTF8 roster order accepts supplementary after BMP UID', () async {
    for (final uid in ['\uE000','\u{10000}']) { db.documents['$groupPath/members/$uid'] = member(uid,'member'); }
    final head = await gateway.load(binding);
    expect(head.members.items.map((m)=>m.uid),['a','b','\uE000','\u{10000}']);
  });
  for (final path in ['users/a',groupPath,actorPath,targetPath,assignmentPath]) {
    for (final kind in ['cache','pending','path']) {
      test('commit $kind $path validates even missing canonical doc', () async {
        if(kind=='cache')db.cached.add(path);
        if(kind=='pending')db.pending.add(path);
        if(kind=='path')db.poisonPath='wrong/path';
        await expectLater(gateway.commit(binding,settings(db),plan()),kind=='path'?throwsFormatException:throwsStateError);
        expect(db.writes,isEmpty);
      });
    }
    for (final failed in [false,true]) {
      test('commit UID switch $path ${failed ? "failed" : "successful"} async boundary', () async {
        db.gates[path]=Completer(); if(failed)db.errors[path]=const FormatException('old');
        final request=expectLater(gateway.commit(binding,settings(db),plan()),throwsStateError);
        await chat.flush(); auth.currentUser=sdk.SdkUser('new'); db.gates[path]!.complete(); await request;
        expect(db.writes,isEmpty);
      });
    }
  }
  for (final path in ['users/a',groupPath,actorPath,targetPath]) {
    for (final kind in ['missing','extra']) {
      test('strict commit $kind $path', () async {
        final expected=settings(db);
        if(kind=='missing'){db.documents.remove(path);}else{db.documents[path]!['email']='private';}
        await expectLater(gateway.commit(binding,expected,plan()),throwsFormatException); expect(db.writes,isEmpty);
      });
    }
  }
  for (final patch in <sdk.Data>[{'role':'owner'},{'userId':'wrong'},{'joinedAt':DateTime.utc(2026)}]) {
    test('target membership parse $patch', () async {
      db.documents[targetPath]!.addAll(patch);
      await expectLater(gateway.commit(binding,settings(db),plan()),throwsFormatException); expect(db.writes,isEmpty);
    });
  }
  for (final operation in ['load','commit','advance']) {
    test('$operation actual member cannot act despite creator metadata', () async {
      db.documents[actorPath]!['role']='member'; db.documents[groupPath]!['createdBy']='a';
      final request=operation=='load'?gateway.load(binding):operation=='commit'?gateway.commit(binding,settings(db),plan()):gateway.advance(binding);
      await expectLater(request,throwsFormatException); expect(db.writes,isEmpty);
    });
    for (final code in ['permission-denied','unavailable']) {
      test('$operation $code propagates no partial writes', () async {
        db.errors[operation=='load'?'query':'commit']=FirebaseException(plugin:'cloud_firestore',code:code);
        final request=operation=='load'?gateway.load(binding):operation=='commit'?gateway.commit(binding,settings(db),plan()):gateway.advance(binding);
        await expectLater(request,throwsA(isA<FirebaseException>())); expect(db.writes,isEmpty);
      });
    }
  }
  for (final mode in ['chapter_wise','saptah']) {
    test('$mode advance independent admin+1 only two fields no assignments retry CURRENT week', () async {
      db.documents[groupPath]!['mode']=mode;
      if(mode=='saptah')db.documents[groupPath]!['chaptersPerWeek']=53;
      db.attempts=2; db.beforeAttempt=(i){ if(i==1)db.documents[groupPath]!['currentWeek']=9; };
      expect(await gateway.advance(binding),10);
      expect(db.writes.single.data,{'currentWeek':10,'updatedAt':FieldValue.serverTimestamp()});
      expect(db.writes.single.path,groupPath);
      expect(db.reads,['users/a',groupPath,actorPath,groupPath,actorPath]);
    });
  }
  test('Saptah label commits the same weekly plan; widths above 48 still reject before SDK', () async {
    db.documents[groupPath]!['mode']='saptah';
    await gateway.commit(binding,settings(db),plan());
    expect(db.writes,isNotEmpty); expect(db.writes.every((write)=>write.transaction),isTrue);
    expect((await gateway.load(binding)).group.mode,'saptah');
    db.documents[groupPath]!['chaptersPerWeek']=53; db.reads.clear();
    await expectLater(gateway.commit(binding,settings(db),plan()),throwsFormatException); expect(db.reads,isEmpty);
  });
  for (final role in ['member']) {
    test('$role advance forbidden', () async {
      db.documents[actorPath]!['role']=role;
      await expectLater(gateway.advance(binding),throwsFormatException); expect(db.writes,isEmpty);
    });
  }
  test('group_lead advance allowed', () async {
    db.documents[actorPath]!['role']='group_lead'; expect(await gateway.advance(binding),isPositive);
  });
  for (final week in [0,10000,10001,'1']) {
    test('advance bound/type $week', () async {
      db.documents[groupPath]!['currentWeek']=week;
      await expectLater(gateway.advance(binding),throwsFormatException); expect(db.writes,isEmpty);
    });
  }
  test('advance allows final 9999→10000', () async {
    db.documents[groupPath]!['currentWeek']=9999; expect(await gateway.advance(binding),10000);
  });
  for (final changed in ['actor','missing','cache','pending','uid','overflow']) {
    test('advance retry $changed discards staged update', () async {
      db.attempts=2; db.beforeAttempt=(i){if(i==0)return;
        switch(changed){
          case 'actor': db.documents[actorPath]!['role']='member';
          case 'missing': db.documents.remove(groupPath);
          case 'cache': db.cached.add(groupPath);
          case 'pending': db.pending.add(actorPath);
          case 'uid': auth.currentUser=null;
          case 'overflow': db.documents[groupPath]!['currentWeek']=10000;
        }
      };
      await expectLater(gateway.advance(binding),['cache','pending','uid'].contains(changed)?throwsStateError:throwsFormatException);
      expect(db.writes,isEmpty);
    });
  }
  for (final advancing in [false,true]) {
    test('${advancing ? "advance" : "commit"} ACK account switch discards result not rollback', () async {
      db.gates['commit']=Completer();
      final request=expectLater(advancing?gateway.advance(binding):gateway.commit(binding,settings(db),plan()),throwsStateError);
      await chat.flush(); auth.currentUser=sdk.SdkUser('new'); db.gates['commit']!.complete(); await request;
      expect(db.writes.length,1);
    });
    test('${advancing ? "advance" : "commit"} simulated lostACK write can exist must not blindly retry', () async {
      db.loseAck=true;
      await expectLater(advancing?gateway.advance(binding):gateway.commit(binding,settings(db),plan()),throwsStateError);
      expect(db.writes.length,1); db.loseAck=false;
      if(!advancing) { await expectLater(gateway.commit(binding,settings(db),plan()),throwsFormatException); expect(db.writes.length,1); }
      else { expect(db.documents[groupPath]!['currentWeek'],2); }
    });
  }
  for (final path in ['users/a',groupPath,actorPath,'query']) {
    test('load UID switch boundary $path', () async {
      db.gates[path]=Completer(); final request=expectLater(gateway.load(binding),throwsStateError);
      await chat.flush(); auth.currentUser=null; db.gates[path]!.complete(); await request;
    });
    for (final kind in ['cache','pending']) {
      test('load $kind $path', () async {
        if(path=='query'){if(kind=='cache'){db.queryCached=true;}else{db.queryPending=true;}}
        else{(kind=='cache'?db.cached:db.pending).add(path);}
        await expectLater(gateway.load(binding),throwsStateError);
      });
    }
  }
  for (final kind in ['cache','pending','extra','uid','path','duplicate','unordered']) {
    test('entire roster rejected $kind', () async {
      if(kind=='cache')db.cached.add(targetPath);
      if(kind=='pending')db.pending.add(targetPath);
      if(kind=='extra')db.documents[targetPath]!['email']='private';
      if(kind=='uid')db.documents[targetPath]!['userId']='other';
      if(kind=='path')db.poisonPath='other/path';
      if(kind=='duplicate')db.forcedIds=['b','b'];
      if(kind=='unordered')db.forcedIds=['b','a'];
      await expectLater(gateway.load(binding),['cache','pending'].contains(kind)?throwsStateError:throwsFormatException);
    });
  }
  for(final size in [0,51]){
    test('load size$size before IO',()async{await expectLater(gateway.load(binding,pageSize:size),throwsFormatException);expect(db.reads,isEmpty);});
  }
  for(final bad in ['', '.', '..','x/y','__reserved__','é'*751]){
    test('invalid binding/cursor length${bad.length} before IO',()async{
      await expectLater(gateway.load((uid:'a',groupId:bad)),throwsFormatException);
      await expectLater(gateway.load(binding,cursor:bad),throwsFormatException);
      await expectLater(gateway.advance((uid:bad,groupId:'g')),throwsFormatException);
      expect(db.reads,isEmpty);
    });
  }
  test('SDK mismatch before IO even a syntactically valid binding',()async{
    auth.currentUser=sdk.SdkUser('new');
    await expectLater(gateway.load(binding),throwsStateError);
    await expectLater(gateway.commit(binding,settings(db),plan()),throwsStateError);
    await expectLater(gateway.advance(binding),throwsStateError); expect(db.reads,isEmpty);
  });
  test('advance UID changes during group/actor reads prevents staged update',()async{
    db.gates[actorPath]=Completer();final request=expectLater(gateway.advance(binding),throwsStateError);
    await chat.flush();auth.currentUser=null;db.gates[actorPath]!.complete();await request;expect(db.writes,isEmpty);
  });
}