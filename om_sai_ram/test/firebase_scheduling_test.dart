import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firebase_group_models.dart';
import 'package:om_sai_ram/features/firebase_groups/data/firestore_groups_gateway.dart';
import 'package:om_sai_ram/features/firebase_groups/presentation/firebase_groups_screen.dart';
import 'package:om_sai_ram/features/firebase_groups/providers/firebase_groups_provider.dart';
import 'package:om_sai_ram/features/firebase_assignments/providers/firebase_assignments_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/providers/firebase_tasks_provider.dart';
import 'package:om_sai_ram/features/firebase_tasks/data/firebase_task_models.dart';
import 'package:om_sai_ram/features/firebase_scheduling/data/firebase_schedule_models.dart';
import 'package:om_sai_ram/features/firebase_scheduling/data/firestore_scheduling_gateway.dart';
import 'package:om_sai_ram/features/firebase_scheduling/providers/firebase_scheduling_provider.dart';
import 'package:om_sai_ram/features/firebase_scheduling/presentation/firebase_scheduling_screen.dart';
import 'package:om_sai_ram/shared/widgets/utc_schedule_date_field.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firebase_groups_test.dart' as groups;
import 'firestore_chat_gateway_test.dart' as chat;
import 'group_home_overrides.dart';

const binding = (uid:'a',groupId:'g');
class FakeScheduling implements FirebaseSchedulingGateway {
  FirebaseGroupRole role = FirebaseGroupRole.admin;
  Map<String,dynamic> raw = groups.groupData();
  final cursors = <String?>[];
  final commits = <({FirebaseScheduleBinding binding, FirebaseScheduleSettings settings, FirebaseSchedulePlan plan})>[];
  int advances = 0;
  Completer<void>? loadGate, writeGate;
  Object? loadError, writeError;
  bool wrongGroup = false, wrongActor = false, reloadFailsAfterWrite = false;
  @override
  Future<FirebaseScheduleHead> load(FirebaseScheduleBinding binding, {int pageSize=20,String? cursor}) async {
    cursors.add(cursor);
    if(loadGate!=null)await loadGate!.future;
    if(loadError!=null)throw loadError!;
    if(binding.uid!='a')throw StateError('New user has no group');
    requireScheduler(FirebaseMembership(binding.uid,role,groups.now));
    return FirebaseScheduleHead(FirebaseGroup.parse(wrongGroup?'other':binding.groupId,raw),
      FirebaseMembership(wrongActor?'other':binding.uid,role,groups.now),
      FirebasePage(cursor==null?[FirebaseMembership('a',role,groups.now),FirebaseMembership('b',FirebaseGroupRole.member,groups.now)]
        :[FirebaseMembership('c',FirebaseGroupRole.member,groups.now)],cursor:cursor==null?'b':'c',hasMore:cursor==null));
  }
  Future<void> _write() async {
    if(writeGate!=null)await writeGate!.future;
    if(writeError!=null)throw writeError!;
    if(reloadFailsAfterWrite)loadError=StateError('ACK reload offline');
  }
  @override
  Future<void> commit(FirebaseScheduleBinding binding,FirebaseScheduleSettings settings,FirebaseSchedulePlan plan)async{
    commits.add((binding:binding,settings:settings,plan:plan));await _write();
  }
  @override
  Future<int> advance(FirebaseScheduleBinding binding)async{
    advances++;await _write();raw['currentWeek']=(raw['currentWeek'] as int)+1;return raw['currentWeek'] as int;
  }
}
FirebaseSchedulingController controller(FakeScheduling gateway,{bool Function()? current,
  void Function()? invalidate,Future<String?> Function()? reload})=>FirebaseSchedulingController(binding,()=>gateway,
    current??()=>true,invalidate??(){},reload??()async=>null);
Future<void> makePreview(FirebaseSchedulingController c)async{
  await c.load();c.select('b',true);
  await c.preview(weeksAhead:1,mode:'independent',remainder:'manual');
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dated preview keeps explicit UTC instant and advances by exactly seven days', () async {
    final gateway = FakeScheduling(); final c = controller(gateway);
    await c.load(); c.select('b', true);
    final date = DateTime.utc(2026, 3, 8, 18, 30, 1, 123, 456);
    await c.preview(weeksAhead: 3, mode: 'independent', remainder: 'manual', firstWeekDate: date);
    final normalized = DateTime.utc(2026, 3, 8, 18, 30, 1, 123);
    expect(c.state.preview!.assignments.first.scheduledDate, normalized);
    expect(c.state.preview!.assignments.last.scheduledDate, normalized.add(const Duration(days: 14)));
    final confirmation = c.confirmation()!;
    expect(await c.confirm(confirmation), isTrue);
    expect(gateway.commits.single.plan.firstWeekDate, normalized); c.dispose();
  });
  test('continue-each-person mode advances 7–8 to 9–10 next week', () async {
    final gateway = FakeScheduling()..raw['startChapter'] = 7..raw['chaptersPerWeek'] = 2;
    final c = controller(gateway);
    await c.load(); c.select('b', true);
    await c.preview(weeksAhead: 2, mode: 'rotating_window', remainder: 'manual');
    final readings = c.state.preview!.assignments;
    expect(readings.map((row) => row.unit.key), ['7', '8', '9', '10']);
    expect(readings.map((row) => row.weekNumber), [1, 1, 2, 2]);
    expect(readings.every((row) => row.userId == 'b'), isTrue);
    c.dispose();
  });
  test('dated hint suggestion preserves date and editing rejects previous confirmation', () async {
    final gateway = FakeScheduling(); final c = controller(gateway);
    await c.load(); c.select('a', true); c.select('b', true);
    final date = DateTime.utc(2026, 11, 1, 18, 30);
    await c.suggest(weeksAhead: 1, mode: 'independent', remainder: 'manual', firstWeekDate: date,
      hints: [const FirebaseScheduleHint(position: 0, chapterStart: 1), const FirebaseScheduleHint(position: 1, chapterStart: 3)]);
    expect(c.state.suggestion!.plan.firstWeekDate, date);
    final stale = c.confirmation()!; c.edit();
    expect(c.state.preview, isNull); expect(c.canConfirm(stale), isFalse);
    expect(await c.confirm(stale), isFalse); expect(gateway.commits, isEmpty); c.dispose();
  });
  for (final date in [DateTime(2026), DateTime.utc(0), DateTime.utc(10000), DateTime.utc(9999, 12, 31)]) {
    test('invalid/overflow date $date clears preview without sticky busy or writes', () async {
      final gateway = FakeScheduling(); final c = controller(gateway); await makePreview(c);
      await c.preview(weeksAhead: 2, mode: 'independent', remainder: 'manual', firstWeekDate: date);
      expect(c.state.preview, isNull); expect(c.state.error, isNotNull);
      expect(c.state.busy, isFalse); expect(gateway.commits, isEmpty); c.dispose();
    });
  }
  const pattern = [FirebaseScheduleHint(position:0,chapterStart:17),FirebaseScheduleHint(position:1,chapterStart:20)];
  Future<void> suggest(FirebaseSchedulingController c,{List<FirebaseScheduleHint> hints=pattern,int weeks=1}) =>
    c.suggest(weeksAhead:weeks,mode:'independent',remainder:'manual',hints:hints);
  Future<void> selectPair(FirebaseSchedulingController c)async{
    await c.load();c.select('b',true);c.select('a',true);
  }
  test('suggestion fresh head infers changed width/current week, captures hints before await and commits inferred plan only on confirmation',()async{
    final g=FakeScheduling();final c=controller(g);await selectPair(c);
    g.raw['chaptersPerWeek']=3;g.raw['currentWeek']=9;g.raw['startChapter']=53;
    g.loadGate=Completer();final hints=[pattern.first,const FirebaseScheduleHint(position:1,chapterStart:21)];final pending=suggest(c,hints:hints);
    hints.clear();c.edit();c.move('a',-1);c.select('b',false);
    expect(c.state.selected,['b','a']);expect(c.state.busy,isTrue);
    await suggest(c);expect(g.cursors.length,2);expect(g.commits,isEmpty);
    g.loadGate!.complete();await pending;
    final result=c.state.suggestion!;
    expect(result.detectedMode,'rotating_window');expect(result.detectedStep,3);expect(result.plan.startChapter,16);
    expect(result.preview.settings.currentWeek,9);expect(result.preview.settings.startChapter,53);
    expect(identical(result.preview,c.state.preview),isTrue);expect(g.commits,isEmpty);
    final canceled=c.confirmation()!;c.cancel(canceled);expect(await c.confirm(canceled),isFalse);
    expect(g.commits,isEmpty);expect(await c.confirm(c.confirmation()!),isTrue);
    expect(g.commits.single.settings.currentWeek,9);expect(g.commits.single.settings.chaptersPerWeek,3);
    expect(g.commits.single.plan.scheduleMode,'rotating_window');expect(g.commits.single.plan.startChapter,16);
    expect(g.commits.single.plan.memberUids,['b','a']);expect(c.state.suggestion,isNull);
    final reads=g.cursors.length;await suggest(c);expect(g.cursors.length,reads);c.dispose();
  });
  for(final action in ['edit','select','move','load','page','manual','suggest','reject']){
    test('suggestion $action invalidates metadata/confirmation without writes',()async{
      final g=FakeScheduling();final c=controller(g);await selectPair(c);await suggest(c);
      final token=c.confirmation()!;
      switch(action){
        case 'edit':c.edit();
        case 'select':c.select('b',false);
        case 'move':c.move('a',-1);
        case 'load':await c.load();
        case 'page':await c.load(cursor:'b');
        case 'manual':await c.preview(weeksAhead:1,mode:'synchronized',remainder:'cycle');
        case 'suggest':await suggest(c);
        case 'reject':c.rejectInput('invalid hint');
      }
      expect(await c.confirm(token),isFalse);expect(g.commits,isEmpty);expect(g.advances,0);
      if(action!='suggest')expect(c.state.suggestion,isNull);
      if(!['manual','suggest'].contains(action))expect(c.state.preview,isNull);
      c.dispose();
    });
  }
  for(final failure in ['read','denied','group','actor','hints','width','invalidPlan']){
    test('suggestion $failure clears stale preview and authority, explicit reload retry',()async{
      final g=FakeScheduling();final c=controller(g);await selectPair(c);await suggest(c);final token=c.confirmation()!;
      switch(failure){
        case 'read':g.loadError=StateError('offline');
        case 'denied':g.role=FirebaseGroupRole.member;
        case 'group':g.wrongGroup=true;
        case 'actor':g.wrongActor=true;
        case 'width':g.raw['chaptersPerWeek']=53;
      }
      await suggest(c,hints:failure=='hints'?const []:pattern,weeks:failure=='invalidPlan'?13:1);
      expect(c.state.error,isNotNull);expect(c.state.head,isNull);expect(c.state.preview,isNull);expect(c.state.suggestion,isNull);
      expect(await c.confirm(token),isFalse);expect(c.confirmation(advance:true),isNull);
      final reads=g.cursors.length;await suggest(c);expect(g.cursors.length,reads);expect(g.commits,isEmpty);
      g.loadError=null;g.role=FirebaseGroupRole.admin;g.wrongGroup=false;g.wrongActor=false;g.raw['chaptersPerWeek']=2;
      await c.load();await suggest(c);expect(c.state.suggestion,isNotNull);c.dispose();
    });
  }
  for(final end in ['account','dispose']){
    for(final failed in [false,true]){
      test('suggestion delayed $end ${failed?"error":"result"} discarded',()async{
        var current=true;final g=FakeScheduling();final c=controller(g,current:()=>current);await selectPair(c);
        g.loadGate=Completer();if(failed)g.loadError=StateError('old');final pending=suggest(c);
        if(end=='account'){current=false;}else{c.dispose();}
        g.loadGate!.complete();await pending;
        expect(g.commits,isEmpty);
        if(end=='account'){expect(c.state.suggestion,isNull);expect(c.state.head,isNull);expect(c.state.error,isNull);c.dispose();}
      });
    }
  }
  test('suggestion rechecks role after the awaited fresh-head boundary',()async{
    final g=FakeScheduling();final c=controller(g);await selectPair(c);g.loadGate=Completer();final pending=suggest(c);
    g.role=FirebaseGroupRole.member;g.loadGate!.complete();await pending;
    expect(c.state.head,isNull);expect(c.state.suggestion,isNull);expect(g.commits,isEmpty);c.dispose();
  });
  test('suggestion oversized allowed and uncertainty locks suggestions until explicit head reload',()async{
    final g=FakeScheduling()..raw['chaptersPerWeek']=48;final c=controller(g);await selectPair(c);
    const hints=[FirebaseScheduleHint(position:0,chapterStart:1),FirebaseScheduleHint(position:1,chapterStart:1)];
    await suggest(c,hints:hints);expect(c.state.preview!.assignments.length,96);expect(c.confirmation(),isNull);
    g.raw['chaptersPerWeek']=2;await suggest(c,hints:hints);g.writeError=StateError('lost ACK');
    expect(await c.confirm(c.confirmation()!),isFalse);expect(c.state.uncertain,isTrue);expect(c.state.suggestion,isNull);
    final reads=g.cursors.length;await suggest(c);expect(g.cursors.length,reads);expect(g.commits.length,1);
    await c.load();await suggest(c,hints:hints);expect(c.state.suggestion,isNotNull);expect(g.commits.length,1);c.dispose();
  });
  test('ordered selection retains explicit subset across replacement pages and reorders only explicitly',()async{
    final g=FakeScheduling();final ctrl=controller(g);
    await ctrl.load();ctrl.select('b',true);ctrl.select('a',true);ctrl.select('hidden',true);
    expect(ctrl.state.selected,['b','a']);
    await ctrl.load(cursor:'b');expect(ctrl.state.head!.members.items.single.uid,'c');expect(ctrl.state.selected,['b','a']);
    ctrl.select('c',true);ctrl.move('c',-1);expect(ctrl.state.selected,['b','c','a']);
    ctrl.select('b',false);expect(ctrl.state.selected,['c','a']);
    await ctrl.preview(weeksAhead:1,mode:'synchronized',remainder:'cycle');
    expect(ctrl.state.preview!.plan.memberUids,['c','a']);expect(g.cursors.last,isNull);
    expect(()=>ctrl.state.selected.add('x'),throwsUnsupportedError);ctrl.dispose();
  });
  for(final role in FirebaseGroupRole.values){
    test('actual ${role.name} controller preview/advance permissions',()async{
      final g=FakeScheduling()..role=role;final c=controller(g);await makePreview(c);
      expect(c.state.preview!=null,role!=FirebaseGroupRole.member);
      expect(c.confirmation(advance:true)!=null,isGroupLeader(role));
      if(role==FirebaseGroupRole.member)expect(c.state.head,isNull);
      c.dispose();
    });
  }
  for(final edit in ['edit','selection','move','load','next','preview']){
    test('$edit invalidates bound confirmation and old preview',()async{
      final g=FakeScheduling();final ctrl=controller(g);await makePreview(ctrl);
      final token=ctrl.confirmation()!;
      switch(edit){
        case 'edit':ctrl.edit();
        case 'selection':ctrl.select('a',true);
        case 'move':ctrl.select('a',true);ctrl.move('a',-1);
        case 'load':await ctrl.load();
        case 'next':await ctrl.load(cursor:'b');
        case 'preview':await ctrl.preview(weeksAhead:2,mode:'dense_window',remainder:'truncate');
      }
      expect(await ctrl.confirm(token),isFalse);expect(g.commits,isEmpty);
      if(edit!='preview')expect(ctrl.state.preview,isNull);ctrl.dispose();
    });
  }
  test('cancel and replaced tokens cannot write',()async{
    final g=FakeScheduling();final ctrl=controller(g);await makePreview(ctrl);
    final token=ctrl.confirmation()!;ctrl.cancel(token);expect(await ctrl.confirm(token),isFalse);
    final previous=ctrl.confirmation()!;final next=ctrl.confirmation(advance:true)!;
    expect(await ctrl.confirm(previous),isFalse);ctrl.cancel(next);expect(await ctrl.confirm(next),isFalse);expect(g.advances,0);ctrl.dispose();
  });
  for(final advancing in [false,true]){
    test('${advancing?"advance":"commit"} acknowledged reload failure distinct no repeat explicit head reset',()async{
      final g=FakeScheduling();var invalidates=0,reloads=0;
      final c=controller(g,invalidate:()=>invalidates++,reload:()async{reloads++;return 'offline';});await makePreview(c);
      final token=c.confirmation(advance:advancing)!;
      expect(await c.confirm(token),isTrue);expect(c.state.acknowledged,isTrue);expect(c.state.uncertain,isFalse);
      expect(c.state.error,contains('acknowledged'));expect(c.state.head,isNull);expect(c.state.preview,isNull);
      expect(c.confirmation(advance:advancing),isNull);expect(await c.confirm(token),isFalse);
      expect(invalidates,1);expect(reloads,1);
      g.loadError=StateError('server offline');await c.load();expect(c.state.acknowledged,isTrue);expect(c.confirmation(advance:true),isNull);
      g.loadError=null;await c.load();expect(c.state.acknowledged,isFalse);expect(c.state.preview,isNull);
      expect(c.confirmation(),isNull);expect(c.confirmation(advance:true),isNotNull);c.dispose();
    });
    test('${advancing?"advance":"commit"} ACK followup scheduling load failure retains acknowledgment',()async{
      final g=FakeScheduling()..reloadFailsAfterWrite=true;final c=controller(g);await makePreview(c);
      expect(await c.confirm(c.confirmation(advance:advancing)!),isTrue);
      expect(c.state.acknowledged,isTrue);expect(c.state.error,contains('server reload failed'));c.dispose();
    });
    for(final error in [const FormatException('stale'),StateError('transport')]){
      test('${advancing?"advance":"commit"} $error outcome unverified no blind retry reload/repreview mandatory',()async{
        final g=FakeScheduling()..writeError=error;final c=controller(g,invalidate:()=>fail('failure invalidates'),reload:()async{fail('failure reload');});
        await makePreview(c);final token=c.confirmation(advance:advancing)!;
        expect(await c.confirm(token),isFalse);expect(c.state.uncertain,isTrue);expect(c.state.head,isNull);
        expect(c.confirmation(advance:advancing),isNull);expect(await c.confirm(token),isFalse);
        g.loadError=StateError('failed verification');await c.load();expect(c.state.uncertain,isTrue);
        g.loadError=null;await c.load();expect(c.state.uncertain,isFalse);expect(c.state.preview,isNull);
        expect(await c.confirm(token),isFalse);expect(g.commits.length+g.advances,1);c.dispose();
      });
    }
    for(final end in ['account','dispose']){
      test('${advancing?"advance":"commit"} delayed $end suppress ACK error and double tap',()async{
        var current=true;final g=FakeScheduling()..writeGate=Completer();
        final c=controller(g,current:()=>current,invalidate:()=>fail('old invalidate'),reload:()async{fail('old reload');});await makePreview(c);
        final token=c.confirmation(advance:advancing)!;final request=c.confirm(token);
        expect(await c.confirm(token),isFalse);expect(c.state.head,isNull);
        if(end=='account'){current=false;}else{c.dispose();}
        g.writeGate!.complete();expect(await request,isFalse);expect(g.commits.length+g.advances,1);
        if(end=='account'){expect(c.state.busy,isFalse);expect(c.state.outcome,isNull);c.dispose();}
      });
    }
  }
  for(final action in ['load','preview']){
    for(final failed in [false,true]){
      test('$action delayed UID switch drops ${failed?"error":"result"}',()async{
        var current=true;final g=FakeScheduling();final c=controller(g,current:()=>current);
        if(action=='preview')await makePreview(c);g.loadGate=Completer();if(failed)g.loadError=StateError('old');
        final request=action=='load'?c.load():c.preview(weeksAhead:1,mode:'independent',remainder:'manual');
        current=false;g.loadGate!.complete();await request;expect(c.state.head,isNull);expect(c.state.error,isNull);expect(c.state.busy,isFalse);c.dispose();
      });
    }
    test('$action disposed during read cannot publish',()async{
      final g=FakeScheduling();final ctrl=controller(g);
      if(action=='preview')await makePreview(ctrl);g.loadGate=Completer();
      final request=action=='load'?ctrl.load():ctrl.preview(weeksAhead:1,mode:'independent',remainder:'manual');
      ctrl.dispose();g.loadGate!.complete();await request;
    });
  }
  for(final kind in ['wrongGroup','wrongActor','denied','failed']){
    test('head read $kind clears all stale authority/preview',()async{
      final g=FakeScheduling();final ctrl=controller(g);await makePreview(ctrl);
      if(kind=='wrongGroup')g.wrongGroup=true;if(kind=='wrongActor')g.wrongActor=true;
      if(kind=='denied')g.role=FirebaseGroupRole.member;if(kind=='failed')g.loadError=StateError('offline');
      await ctrl.load();expect(ctrl.state.head,isNull);expect(ctrl.state.preview,isNull);expect(ctrl.confirmation(advance:true),isNull);ctrl.dispose();
    });
  }
  test('preview freshly captures changed settings and role; no stale plan after later read',()async{
    final g=FakeScheduling();final ctrl=controller(g);await makePreview(ctrl);
    g.raw['currentWeek']=9;g.raw['startChapter']=53;
    await ctrl.preview(weeksAhead:1,mode:'independent',remainder:'manual');
    expect(ctrl.state.preview!.settings.currentWeek,9);expect(ctrl.state.preview!.unfilledCount,1);
    g.role=FirebaseGroupRole.member;await ctrl.preview(weeksAhead:1,mode:'independent',remainder:'manual');
    expect(ctrl.state.head,isNull);expect(ctrl.state.preview,isNull);ctrl.dispose();
  });
  test('oversize preview allowed but commit confirmation blocked, advance independent',()async{
    final g=FakeScheduling()..raw['chaptersPerWeek']=48;final c=controller(g);await c.load();c.select('b',true);
    await c.preview(weeksAhead:2,mode:'synchronized',remainder:'cycle');
    expect(c.state.preview!.assignments.length,96);expect(c.confirmation(),isNull);expect(c.confirmation(advance:true),isNotNull);c.dispose();
  });
  test('Saptah label previews weekly like chapter-wise; legacy width 53 rejects; cap disables advance',()async{
    final g=FakeScheduling()..raw['mode']='saptah';final c=controller(g);await c.load();expect(c.confirmation(advance:true),isNotNull);
    c.select('b',true);await c.preview(weeksAhead:1,mode:'independent',remainder:'manual');expect(c.state.preview,isNotNull);
    expect(c.state.preview!.settings.mode,'saptah');
    g.raw['chaptersPerWeek']=53;await c.load();c.select('b',true);
    await c.preview(weeksAhead:1,mode:'independent',remainder:'manual');expect(c.state.preview,isNull);g.raw['chaptersPerWeek']=2;
    await c.load();g.raw['currentWeek']=10000;await c.load();expect(c.confirmation(advance:true),isNull);c.dispose();
  });
  test('unready provider does not initialize scheduling/groups SDK',()async{
    final auth=authentication.FakeGateway()..readGate=Completer();
    final container=ProviderContainer(overrides:[firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWith((ref)=>throw StateError('groups initialized')),
      firebaseSchedulingGatewayProvider.overrideWith((ref)=>throw StateError('scheduling initialized'))]);
    container.listen(firebaseSessionProvider,(_,__){});auth.emit(const FirebaseIdentity('a',null));await chat.flush();
    container.listen(firebaseSchedulingProvider(binding),(_,__){});
    await container.read(firebaseSchedulingProvider(binding).notifier).load();expect(container.read(firebaseSchedulingProvider(binding)).head,isNull);
    container.dispose();auth.readGate!.complete('Private');await auth.changes.close();
  });
  test('ACK invalidates assignments/tasks/group index and explicitly reloads group detail head',()async{
    final auth=authentication.FakeGateway()..profile='Private',g=FakeScheduling(),groupGateway=groups.FakeGroups();
    final container=ProviderContainer(overrides:[firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseGroupsGatewayProvider.overrideWithValue(groupGateway),firebaseSchedulingGatewayProvider.overrideWithValue(g),
      firebaseAssignmentsProvider.overrideWith((ref,scope)=>FirebaseAssignmentsController(null,scope,()=>false)),
      firebaseTasksProvider.overrideWith((ref,scope)=>FirebaseTasksController(null,scope,()=>false))]);
    container.listen(firebaseSessionProvider,(_,__){});auth.emit(const FirebaseIdentity('a',null));await chat.flush();
    final assignments=firebaseAssignmentsProvider((uid:'a',groupId:'g',memberUid:'b',week:1));
    final tasks=firebaseTasksProvider((uid:'a',options:defaultTaskOptions));
    container.listen(assignments,(_,__){});container.listen(tasks,(_,__){});
    container.listen(firebaseGroupsProvider((uid:'a',groupId:null)),(_,__){});
    container.listen(firebaseSchedulingProvider(binding),(_,__){});
    final beforeAssignments=container.read(assignments.notifier),beforeTasks=container.read(tasks.notifier),
      beforeGroups=container.read(firebaseGroupsProvider((uid:'a',groupId:null)).notifier);
    final c=container.read(firebaseSchedulingProvider(binding).notifier);await makePreview(c);
    expect(await c.confirm(c.confirmation()!),isTrue);
    expect(identical(beforeAssignments,container.read(assignments.notifier)),isFalse);
    expect(identical(beforeTasks,container.read(tasks.notifier)),isFalse);
    expect(identical(beforeGroups,container.read(firebaseGroupsProvider((uid:'a',groupId:null)).notifier)),isFalse);
    expect(groupGateway.cursors.last,isNull);expect(container.read(firebaseGroupsProvider(binding)).detail,isNotNull);
    container.dispose();await auth.changes.close();
  });

  Future<({ProviderContainer container,authentication.FakeGateway auth,FakeScheduling schedule,groups.FakeGroups groups})> mount(
    WidgetTester tester,{FirebaseGroupRole role=FirebaseGroupRole.admin,bool routed=false,bool detail=false,bool pending=false,
    String groupId='g',String mode='chapter_wise',int width=2,int week=1,bool delayed=false})async{
    tester.view.physicalSize=const Size(1200,2600);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final auth=authentication.FakeGateway()..profile='Private';if(pending)auth.readGate=Completer();
    final schedule=FakeScheduling()..role=role..raw['mode']=mode..raw['chaptersPerWeek']=width..raw['currentWeek']=week;
    if(delayed)schedule.loadGate=Completer();final groupGateway=groups.FakeGroups()..role=role;
    final container=ProviderContainer(overrides:[backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth),firebaseSchedulingGatewayProvider.overrideWithValue(schedule),
      firebaseGroupsGatewayProvider.overrideWithValue(groupGateway),...groupHomeOverrides(),
      authStateProvider.overrideWith((ref)=>throw StateError('Legacy auth accessed')),
      apiClientProvider.overrideWith((ref)=>throw StateError('Legacy API accessed'))]);
    container.listen(firebaseSessionProvider,(_,__){});auth.emit(const FirebaseIdentity('a',null));await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container:container,child:routed?
      MaterialApp.router(routerConfig:container.read(routerProvider)):
      MaterialApp(home:detail?FirebaseGroupsScreen(groupId:groupId):FirebaseSchedulingScreen(groupId:groupId))));
    if(routed)container.read(routerProvider).go('/groups/${Uri.encodeComponent(groupId)}${detail?"/manage":"/scheduling"}');
    if(delayed||pending){await tester.pump();}else{await tester.pumpAndSettle();}
    addTearDown(()async{await tester.pumpWidget(const SizedBox());container.dispose();
      if(pending&&!auth.readGate!.isCompleted)auth.readGate!.complete('Private');
      if(schedule.loadGate!=null&&!schedule.loadGate!.isCompleted)schedule.loadGate!.complete();await auth.changes.close();});
    return(container:container,auth:auth,schedule:schedule,groups:groupGateway);
  }
  const suggestLabel='Plan from the chapters members are on', cycleLabel='At the end of the book: start again from chapter 1';
  String day(DateTime date)=>date.toIso8601String().substring(0,10);
  Future<void> generate(WidgetTester tester)async{
    await tester.tap(find.byKey(const ValueKey('schedule-member-b')));await tester.pumpAndSettle();
    await tester.tap(find.text('Show plan'));await tester.pumpAndSettle();
  }
  Future<void> enterHints(WidgetTester tester,{String first='17',String second='21'})async{
    await tester.tap(find.byKey(const ValueKey('schedule-member-b')));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-member-a')));await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('schedule-continue')));
    await tester.tap(find.byKey(const Key('schedule-continue')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('schedule-hint-b')),first);
    await tester.enterText(find.byKey(const ValueKey('schedule-hint-a')),second);await tester.pumpAndSettle();
  }
  Future<void> openDetails(WidgetTester tester)async{
    await tester.ensureVisible(find.text('More help'));await tester.tap(find.text('More help'));await tester.pumpAndSettle();
  }
  Future<void> tapSuggest(WidgetTester tester)async{
    await tester.ensureVisible(find.text(suggestLabel));await tester.tap(find.text(suggestLabel));await tester.pumpAndSettle();
  }
  testWidgets('hints display inference distinct from manual fields, review cancel then inferred commit',(tester)async{
    final env=await mount(tester);await enterHints(tester);await tapSuggest(tester);
    expect(find.byKey(const Key('schedule-suggestion')),findsNothing);
    expect(find.textContaining('Suggested plan: Members start one chapter apart, starting at chapter 16'),findsNothing);
    // Width 2 with a three-unit step is custom, not a supported inference.
    expect(env.container.read(firebaseSchedulingProvider(binding)).head,isNull);
    expect(env.schedule.commits,isEmpty);
    await tester.tap(find.text('Start over'));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('schedule-hint-a')),'20');await tapSuggest(tester);
    expect(find.textContaining('Suggested plan: Members take turns through the book, starting at chapter 16'),findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('schedule-start'))).controller!.text,isEmpty);
    await openDetails(tester);expect(find.textContaining('One week is not enough to tell turns'),findsOneWidget);
    await tester.ensureVisible(find.text('Save this plan'));await tester.tap(find.text('Save this plan'));await tester.pumpAndSettle();
    expect(find.textContaining('Starts at chapter 16'),findsWidgets);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(env.schedule.commits,isEmpty);
    await tester.tap(find.text('Save this plan'));await tester.pumpAndSettle();await tester.tap(find.text('Save plan'));await tester.pumpAndSettle();
    expect(env.schedule.commits.single.plan.scheduleMode,'rotating_window');expect(env.schedule.commits.single.plan.startChapter,16);
    expect(find.byKey(const Key('schedule-suggestion')),findsNothing);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,suggestLabel)).onPressed,isNull);
  });
  testWidgets('date edits invalidate displayed preview and open confirmation; commit uses newly reviewed date', (tester) async {
    final env = await mount(tester);
    final date = DateTime.utc(2026, 11, 1, 18, 30);
    UtcScheduleDateField field() => tester.widget<UtcScheduleDateField>(find.byKey(const Key('schedule-first-week-date')));
    field().onChanged(date); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('schedule-weeks')), '2'); await generate(tester);
    expect(env.container.read(firebaseSchedulingProvider(binding)).preview!.plan.firstWeekDate, date);
    expect(find.textContaining(day(date)), findsWidgets);
    await tester.tap(find.text('Save this plan')); await tester.pumpAndSettle();
    expect(find.text('Save plan'), findsOneWidget);
    field().onChanged(null); await tester.pumpAndSettle();
    expect(find.text('Save plan'), findsNothing); expect(find.text('Save this plan'), findsNothing);
    expect(env.schedule.commits, isEmpty);
    final next = date.add(const Duration(days: 1)); field().onChanged(next); await tester.pumpAndSettle();
    await tester.tap(find.text('Show plan')); await tester.pumpAndSettle();
    await tester.tap(find.text('Save this plan')); await tester.pumpAndSettle();
    expect(find.textContaining(day(next)), findsWidgets);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(env.schedule.commits, isEmpty);
    await tester.tap(find.text('Save this plan')); await tester.pumpAndSettle();
    await tester.tap(find.text('Save plan')); await tester.pumpAndSettle();
    expect(env.schedule.commits.single.plan.firstWeekDate, next);
    expect(env.schedule.commits.single.plan.weeksAhead, 2);
  });
  testWidgets('dated hint suggestion preserves explicitly chosen first-week date in commit review', (tester) async {
    final env = await mount(tester); await enterHints(tester, first: '1', second: '3');
    final date = DateTime.utc(2026, 3, 8, 1, 30);
    tester.widget<UtcScheduleDateField>(find.byKey(const Key('schedule-first-week-date'))).onChanged(date);
    await tester.pumpAndSettle(); await tapSuggest(tester);
    expect(env.container.read(firebaseSchedulingProvider(binding)).suggestion!.plan.firstWeekDate, date);
    await tester.tap(find.text('Save this plan')); await tester.pumpAndSettle();
    expect(find.textContaining(day(date)), findsWidgets);
    await tester.tap(find.text('Save plan')); await tester.pumpAndSettle();
    expect(env.schedule.commits.single.plan.firstWeekDate, date);
  });
  testWidgets('UID hints follow reordered subset; removing one drops only its draft and invalidates suggestion',(tester)async{
    final env=await mount(tester);await enterHints(tester,first:'1',second:'3');await tapSuggest(tester);
    expect(env.container.read(firebaseSchedulingProvider(binding)).suggestion,isNotNull);
    final row=find.byKey(const ValueKey('schedule-selected-a'));
    await tester.ensureVisible(row);await tester.tap(find.descendant(of:row,matching:find.byTooltip('Move up')));await tester.pumpAndSettle();
    expect(find.text('1. You'),findsOneWidget);expect(find.text('2. Member 2'),findsOneWidget);
    expect(env.container.read(firebaseSchedulingProvider(binding)).suggestion,isNull);
    String draft(String uid)=>tester.widget<EditableText>(find.descendant(of:find.byKey(ValueKey('schedule-hint-$uid')),matching:find.byType(EditableText))).controller.text;
    expect(draft('a'),'3');expect(draft('b'),'1');
    await tapSuggest(tester);expect(find.byKey(const Key('schedule-error')),findsOneWidget);expect(env.schedule.commits,isEmpty);
    await tester.tap(find.text('Start over'));await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:row,matching:find.byTooltip('Remove from list')));await tester.pumpAndSettle();
    expect(draft('b'),'1');await tester.tap(find.byKey(const ValueKey('schedule-member-a')));await tester.pumpAndSettle();
    expect(draft('a'),'');expect(draft('b'),'1');expect(tester.takeException(),isNull);
  });
  for(final kind in ['count','integer','chapter','read','denied']){
    testWidgets('suggestion $kind error clears authority no writes and explicit retry',(tester)async{
      final env=await mount(tester);await enterHints(tester,first:'1',second:'3');await tapSuggest(tester);
      if(kind=='count')await tester.enterText(find.byKey(const ValueKey('schedule-hint-a')),'');
      if(kind=='integer')await tester.enterText(find.byKey(const ValueKey('schedule-hint-a')),'1.5');
      if(kind=='chapter')await tester.enterText(find.byKey(const ValueKey('schedule-hint-a')),'54');
      if(kind=='read')env.schedule.loadError=StateError('offline');
      if(kind=='denied')env.schedule.role=FirebaseGroupRole.member;
      await tapSuggest(tester);
      expect(find.byKey(const Key('schedule-error')),findsOneWidget);expect(find.byKey(const Key('schedule-suggestion')),findsNothing);
      expect(find.text('Save this plan'),findsNothing);expect(find.text(suggestLabel),findsNothing);expect(env.schedule.commits,isEmpty);
    });
  }
  for(final edit in ['hint','weeks','start','mode','remainder','manual']){
    testWidgets('suggested preview invalidates on $edit and manual preview stays separate',(tester)async{
      final env=await mount(tester);await enterHints(tester,first:'1',second:'3');await tapSuggest(tester);
      if(edit=='hint')await tester.enterText(find.byKey(const ValueKey('schedule-hint-b')),'2');
      if(edit=='weeks')await tester.enterText(find.byKey(const Key('schedule-weeks')),'2');
      if(edit=='start')await tester.enterText(find.byKey(const Key('schedule-start')),'17');
      if(edit=='manual'){await tester.tap(find.text('Show plan'));}
      if(edit=='mode'||edit=='remainder'){
        final dropdown=find.byType(DropdownButtonFormField<String>);
        await tester.tap(edit=='mode'?dropdown.first:dropdown.last);await tester.pumpAndSettle();
        await tester.tap(find.text(edit=='mode'?'Everyone reads the same chapters':cycleLabel).last);
      }
      await tester.pumpAndSettle();expect(find.byKey(const Key('schedule-suggestion')),findsNothing);expect(env.schedule.commits,isEmpty);
      if(edit=='manual'){
        expect(env.container.read(firebaseSchedulingProvider(binding)).preview!.plan.scheduleMode,'independent');
      }else{
        expect(find.text('Save this plan'),findsNothing);
      }
    });
  }
  for(final replacement in [null,const FirebaseIdentity('new',null)]){
    testWidgets('suggestion delayed session replacement ${replacement?.uid} discards hints/results',(tester)async{
      final env=await mount(tester);await enterHints(tester,first:'1',second:'3');env.schedule.loadGate=Completer();
      await tester.tap(find.text(suggestLabel));await tester.pump();
      env.auth.emit(replacement);await tester.pump();env.schedule.loadGate!.complete();await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-suggestion')),findsNothing);expect(find.text(suggestLabel),findsNothing);expect(env.schedule.commits,isEmpty);expect(tester.takeException(),isNull);
    });
  }
  for(final role in FirebaseGroupRole.values){
    testWidgets('Suggest button actual ${role.name} role gate',(tester)async{
      await mount(tester,role:role);
      final shown=role==FirebaseGroupRole.member?findsNothing:findsOneWidget;
      expect(find.text(suggestLabel),findsNothing);expect(find.byKey(const Key('schedule-continue')),shown);
      if(role==FirebaseGroupRole.member)return;
      await tester.tap(find.byKey(const Key('schedule-continue')));await tester.pumpAndSettle();
      expect(find.text(suggestLabel),findsOneWidget);
    });
  }
  testWidgets('Suggest button absent while pending and present for Saptah-labelled workspaces',(tester)async{
    await mount(tester,pending:true);expect(find.byKey(const Key('schedule-continue')),findsNothing);
    await tester.pumpWidget(const SizedBox());
    await mount(tester,mode:'saptah');await tester.tap(find.byKey(const Key('schedule-continue')));await tester.pumpAndSettle();
    expect(find.text(suggestLabel),findsOneWidget);
  });
  testWidgets('select all ticks the page in roster order, then clears it',(tester)async{
    final env=await mount(tester);final all=find.byKey(const Key('schedule-select-all'));
    await tester.tap(find.byKey(const ValueKey('schedule-member-b')));await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(all).value,isNull);
    await tester.tap(all);await tester.pumpAndSettle();
    final ids=[for(final m in env.container.read(firebaseSchedulingProvider(binding)).head!.members.items)m.uid];
    expect(env.container.read(firebaseSchedulingProvider(binding)).selected,['b',...ids.where((id)=>id!='b')]);
    expect(tester.widget<CheckboxListTile>(all).value,isTrue);
    await tester.tap(all);await tester.pumpAndSettle();
    expect(env.container.read(firebaseSchedulingProvider(binding)).selected,isEmpty);
    expect(tester.widget<CheckboxListTile>(all).value,isFalse);
  });
  testWidgets('suggestion read busy locks hint/manual/selection controls and disposal drops result',(tester)async{
    final env=await mount(tester);await enterHints(tester,first:'1',second:'3');env.schedule.loadGate=Completer();
    await tester.tap(find.text(suggestLabel));await tester.pump();
    // Fresh-head reads clear authority, so all scheduling controls are hidden.
    expect(find.text(suggestLabel),findsNothing);
    expect(find.text('Show plan'),findsNothing);
    expect(find.byKey(const ValueKey('schedule-hint-b')),findsNothing);
    await tester.pumpWidget(const SizedBox());env.schedule.loadGate!.complete();await tester.pumpAndSettle();
    expect(env.schedule.commits,isEmpty);expect(tester.takeException(),isNull);
  });
  testWidgets('oversized suggestion shows inferred preview but atomic commit remains disabled',(tester)async{
    final env=await mount(tester,width:48);await enterHints(tester,first:'1',second:'1');await tapSuggest(tester);
    expect(env.container.read(firebaseSchedulingProvider(binding)).suggestion!.detectedMode,'synchronized');
    expect(env.container.read(firebaseSchedulingProvider(binding)).preview!.assignments.length,96);
    await tester.scrollUntilVisible(find.text('Save this plan'),500,scrollable:find.byType(Scrollable).first);await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Save this plan')).onPressed,isNull);
    expect(env.schedule.commits,isEmpty);
  });
  for(final end in ['account','pending']){
    testWidgets('suggested confirmation $end cancels without writes',(tester)async{
      final env=await mount(tester);await enterHints(tester,first:'1',second:'3');await tapSuggest(tester);
      await tester.ensureVisible(find.text('Save this plan'));await tester.tap(find.text('Save this plan'));await tester.pumpAndSettle();
      Future<void>? reload;
      if(end=='account'){env.auth.emit(const FirebaseIdentity('new',null));}
      else{env.auth.readGate=Completer();reload=env.container.read(firebaseSessionProvider.notifier).reloadProfile();}
      await tester.pumpAndSettle();expect(find.text('Save plan'),findsNothing);expect(env.schedule.commits,isEmpty);
      if(reload!=null){env.auth.readGate!.complete('Private');await reload;await tester.pumpAndSettle();}
    });
  }
  for(final role in FirebaseGroupRole.values){
    testWidgets('group home schedule actions for actual ${role.name} role',(tester)async{
      final env=await mount(tester,role:role,routed:true);
      env.container.read(routerProvider).go('/groups/g');await tester.pumpAndSettle();
      expect(find.byKey(const Key('group-my-schedule')),findsOneWidget);
      expect(find.byKey(const Key('group-plan-weeks')),isGroupLeader(role)?findsOneWidget:findsNothing);
    });
    testWidgets('guarded direct scheduling route actual ${role.name} no FastAPI', (tester)async{
      final env=await mount(tester,role:role,routed:true);
      expect(env.schedule.cursors.length,1);
      expect(find.text('Show plan'),role==FirebaseGroupRole.member?findsNothing:findsOneWidget);
      expect(find.text('Move to next week'),isGroupLeader(role)?findsOneWidget:findsNothing);
      expect(find.text('Private'),findsNothing);
    });
    testWidgets('group detail actual ${role.name} scheduling entry', (tester)async{
      await mount(tester,role:role,routed:true,detail:true);
      expect(find.byKey(const Key('manage-plan')),role==FirebaseGroupRole.member?findsNothing:findsOneWidget);
      if(role!=FirebaseGroupRole.member){await tester.tap(find.byKey(const Key('manage-plan')));await tester.pumpAndSettle();expect(find.text('Show plan'),findsOneWidget);}
    });
  }
  testWidgets('pending direct scheduling route redirects no gateway', (tester)async{
    final env=await mount(tester,routed:true,pending:true);expect(env.schedule.cursors,isEmpty);expect(find.text('Show plan'),findsNothing);
  });
  for(final bad in ['.','..','__reserved__','a/b']){
    testWidgets('invalid route $bad before gateway',(tester)async{
      final env=await mount(tester,routed:true,groupId:bad);expect(env.schedule.cursors,isEmpty);expect(find.text('Show plan'),findsNothing);
    });
  }
  testWidgets('preview details selected subset manual review and immutable confirmation cancellation',(tester)async{
    final env=await mount(tester);await tester.enterText(find.byKey(const Key('schedule-start')),'53');await generate(tester);
    expect(find.textContaining('1 could not be filled • please check the end of the book'),findsOneWidget);
    expect(find.textContaining('Not filled: Member 2'),findsOneWidget);
    await tester.tap(find.text('Save this plan'));await tester.pumpAndSettle();
    expect(find.textContaining('Only the members ticked get these readings'),findsOneWidget);
    expect(find.textContaining('Order: Member 2'),findsWidgets);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(env.schedule.commits,isEmpty);
    await tester.tap(find.text('Save this plan'));await tester.pumpAndSettle();
    await tester.tap(find.text('Save plan'));await tester.pumpAndSettle();
    expect(env.schedule.commits.single.plan.memberUids,['b']);expect(env.schedule.commits.single.plan.firstWeekDate,isNull);
    expect(find.textContaining('Schedule commit acknowledged: 1 assignments'),findsOneWidget);
    expect(find.byKey(const Key('schedule-modify-saved')), findsOneWidget);
  });
  testWidgets('editing invalidates preview before another confirmation',(tester)async{
    await mount(tester);await generate(tester);expect(find.text('Save this plan'),findsOneWidget);
    await tester.enterText(find.byKey(const Key('schedule-weeks')),'2');await tester.pumpAndSettle();expect(find.text('Save this plan'),findsNothing);
  });
  testWidgets('replacement roster page retains ordered selection subset',(tester)async{
    final env=await mount(tester);await tester.tap(find.byKey(const ValueKey('schedule-member-b')));await tester.pumpAndSettle();
    await tester.tap(find.text('More members'));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-member-a')),findsNothing);expect(find.text('1. Member 2'),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('schedule-member-c')));await tester.pumpAndSettle();
    await tester.tap(find.text('Show plan'));await tester.pumpAndSettle();
    expect(env.container.read(firebaseSchedulingProvider(binding)).preview!.plan.memberUids,['b','c']);
  });
  testWidgets('oversize preview retained commit disabled clear explanation',(tester)async{
    final env=await mount(tester,width:48);await tester.enterText(find.byKey(const Key('schedule-weeks')),'2');
    await tester.tap(find.byKey(const ValueKey('schedule-member-b')));await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);await tester.pumpAndSettle();
    await tester.tap(find.text(cycleLabel).last);await tester.pumpAndSettle();
    await tester.tap(find.text('Show plan'));await tester.pumpAndSettle();
    expect(env.container.read(firebaseSchedulingProvider(binding)).preview!.assignments.length,96);
    await tester.scrollUntilVisible(find.byKey(const Key('schedule-commit-block')),500,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('no automatic chunks or skips'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('Save this plan'),180,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Save this plan')).onPressed,isNull);
  });
  testWidgets('advance separate confirmation cancel then +1 acknowledged no schedule',(tester)async{
    final env=await mount(tester);await tester.tap(find.text('Move to next week'));await tester.pumpAndSettle();
    expect(find.textContaining('If someone else moved the week at the same time'),findsOneWidget);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(env.schedule.advances,0);
    await tester.tap(find.text('Move to next week'));await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, move to next week'));await tester.pumpAndSettle();
    expect(env.schedule.advances,1);expect(env.schedule.commits,isEmpty);expect(find.textContaining('current week 2. No assignments generated'),findsOneWidget);
  });
  testWidgets('Saptah label shows the same weekly scheduling controls and week advance',(tester)async{
    await mount(tester,mode:'saptah');await openDetails(tester);expect(find.textContaining('Saptah is a group label'),findsOneWidget);
    expect(find.text('Show plan'),findsOneWidget);expect(find.text('Move to next week'),findsOneWidget);
  });
  testWidgets('10000 admin week cap button disabled',(tester)async{
    await mount(tester,week:10000);expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Move to next week')).onPressed,isNull);
  });
  for(final advancing in [false,true]){
    for(final replacement in [null,const FirebaseIdentity('new',null)]){
      testWidgets('${advancing?"advance":"commit"} dialog crossUID ${replacement?.uid??"logout"} cancels',(tester)async{
        final env=await mount(tester);if(!advancing)await generate(tester);
        await tester.tap(find.text(advancing?'Move to next week':'Save this plan'));await tester.pumpAndSettle();
        env.auth.emit(replacement);await tester.pumpAndSettle();
        expect(find.text(advancing?'Yes, move to next week':'Save plan'),findsNothing);expect(env.schedule.advances,0);expect(env.schedule.commits,isEmpty);
      });
    }
    testWidgets('${advancing?"advance":"commit"} dialog pending session cancels',(tester)async{
      final env=await mount(tester);if(!advancing)await generate(tester);
      await tester.tap(find.text(advancing?'Move to next week':'Save this plan'));await tester.pumpAndSettle();
      env.auth.readGate=Completer();final reload=env.container.read(firebaseSessionProvider.notifier).reloadProfile();await tester.pumpAndSettle();
      expect(find.text(advancing?'Yes, move to next week':'Save plan'),findsNothing);
      env.auth.readGate!.complete('Private');await reload;await tester.pumpAndSettle();expect(env.schedule.advances,0);expect(env.schedule.commits,isEmpty);
    });
    testWidgets('${advancing?"advance":"commit"} write uncertainty hides authority explicit verification no old token',(tester)async{
      final env=await mount(tester);if(!advancing)await generate(tester);env.schedule.writeError=StateError('lost ACK');
      await tester.tap(find.text(advancing?'Move to next week':'Save this plan'));await tester.pumpAndSettle();
      await tester.tap(find.text(advancing?'Yes, move to next week':'Save plan'));await tester.pumpAndSettle();
      expect(find.byKey(const Key('schedule-uncertain')),findsOneWidget);expect(find.text('Show plan'),findsNothing);
      expect(find.textContaining('No blind retry'),findsOneWidget);
      await tester.tap(find.text('Start over'));await tester.pumpAndSettle();
      expect(find.text('Save this plan'),findsNothing);expect(env.schedule.advances+env.schedule.commits.length,1);
    });
    testWidgets('${advancing?"advance":"commit"} ACK reload failed not uncertain',(tester)async{
      final env=await mount(tester);if(!advancing)await generate(tester);env.schedule.reloadFailsAfterWrite=true;
      await tester.tap(find.text(advancing?'Move to next week':'Save this plan'));await tester.pumpAndSettle();
      await tester.tap(find.text(advancing?'Yes, move to next week':'Save plan'));await tester.pumpAndSettle();
      expect(find.textContaining('Write acknowledged; server reload failed'),findsOneWidget);
      expect(find.byKey(const Key('schedule-uncertain')),findsNothing);expect(find.text('Show plan'),findsNothing);
      expect(env.schedule.advances+env.schedule.commits.length,1);
    });
  }
  testWidgets('phone width controls preview and cancel without overflow',(tester)async{
    await mount(tester);tester.view.physicalSize=const Size(390,844);await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('schedule-member-b')),180,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-member-b')));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Show plan'),180,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show plan'));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save this plan'),180,scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this plan'));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(tester.takeException(),isNull);
  });
  testWidgets('delayed head/logout never reveals former group settings',(tester)async{
    final env=await mount(tester,delayed:true);env.auth.emit(null);await tester.pump();env.schedule.loadGate!.complete();await tester.pumpAndSettle();
    expect(find.text('Show plan'),findsNothing);expect(find.textContaining('Your role:'),findsNothing);
  });
}