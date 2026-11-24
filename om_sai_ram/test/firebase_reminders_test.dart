import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/data/auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firestore_reminders_gateway.dart';
import 'package:om_sai_ram/features/firebase_reminders/providers/firebase_reminders_provider.dart';
import 'package:om_sai_ram/features/firebase_reminders/presentation/firebase_reminders_screen.dart';
import 'firebase_auth_mode_test.dart' as authentication;

FirebaseReminderRecord record(String uid, FirebaseReminderPreferences preferences) =>
  FirebaseReminderRecord.parse(uid, {...preferences.toData(), 'updatedAt': Timestamp(1700000000, 123456789)});
class FakeReminders implements FirebaseRemindersGateway {
  final records = <String, FirebaseReminderRecord>{};
  final reads = <String>[], writes = <({String uid, FirebaseReminderPreferences preferences})>[];
  String uid = 'a';
  Object? readError, writeError;
  Completer<void>? readGate, writeGate;
  FirebaseReminderRecord? overrideRecord;
  bool missingAfterSave = false;
  @override
  Future<FirebaseReminderRecord?> read() async {
    final actor = uid;
    final result = overrideRecord ?? records[actor];
    reads.add(actor);
    await readGate?.future;
    if (readError != null) throw readError!;
    return result;
  }
  @override
  Future<void> save(FirebaseReminderPreferences preferences) async {
    final actor = uid;
    writes.add((uid: actor, preferences: preferences));
    await writeGate?.future;
    if (writeError != null) throw writeError!;
    if (!missingAfterSave) records[actor] = record(actor, preferences);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing defaults remain unsaved until explicit save then server reload', () async {
    final g = FakeReminders(); final c = FirebaseRemindersController('a', () => g, () => true);
    expect(await c.save(), isFalse); expect(g.reads, isEmpty);
    await c.load(); expect(c.state.loaded, isTrue); expect(c.state.record, isNull);
    expect(c.state.draft!.timeLabel, '09:00'); expect(g.writes, isEmpty);
    expect(await c.save(), isTrue); expect(c.state.acknowledged, isTrue);
    expect(c.state.record!.preferences.toData(), FirebaseReminderPreferences.defaults.toData());
    expect(g.reads, ['a', 'a']); expect(g.writes.length, 1); c.dispose();
  });
  test('existing values load and edit never writes until save', () async {
    final prefs = FirebaseReminderPreferences.defaults.copyWith(dailyVerseEnabled: true, reminderHour: 23, reminderMinute: 59);
    final g = FakeReminders()..records['a'] = record('a', prefs);
    final c = FirebaseRemindersController('a', () => g, () => true);
    await c.load(); expect(c.state.draft!.timeLabel, '23:59');
    c.edit(c.state.draft!.copyWith(readingReminderEnabled: true)); expect(g.writes, isEmpty);
    await c.save(); expect(g.writes.single.preferences.readingReminderEnabled, isTrue);
    expect(g.writes.single.preferences.dailyVerseEnabled, isTrue); c.dispose();
  });
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code read clears old values before await, explicit retry only', () async {
      final g = FakeReminders()..records['a'] = record('a', FirebaseReminderPreferences.defaults.copyWith(readingReminderEnabled: true));
      final c = FirebaseRemindersController('a', () => g, () => true); await c.load();
      g.readGate = Completer(); g.readError = FirebaseException(plugin: 'cloud_firestore', code: code);
      final pending = c.load(); expect(c.state.record, isNull); expect(c.state.draft, isNull);
      g.readGate!.complete(); await pending; expect(c.state.error, isNotNull); expect(c.state.canEdit, isFalse);
      expect(await c.save(), isFalse); expect(g.reads.length, 2); expect(g.writes, isEmpty);
      g.readError = null; await c.load(); expect(c.state.record, isNotNull); c.dispose();
    });
    test('$code uncertain write keeps draft but disables editing/saving until verified', () async {
      final g = FakeReminders()..writeError = FirebaseException(plugin: 'cloud_firestore', code: code);
      final c = FirebaseRemindersController('a', () => g, () => true); await c.load();
      final draft = c.state.draft!.copyWith(dailyVerseEnabled: true, reminderHour: 0);
      c.edit(draft); expect(await c.save(), isFalse); expect(c.state.acknowledged, isFalse);
      expect(c.state.draft, same(draft)); expect(c.state.record, isNull); expect(c.state.error, contains('uncertain'));
      c.edit(FirebaseReminderPreferences.defaults); expect(c.state.draft, same(draft));
      expect(await c.save(), isFalse); expect(g.writes.length, 1);
      g.readError = StateError('offline'); await c.load(); expect(c.state.draft, same(draft));
      g.readError = null; g.writeError = null; await c.load();
      expect(c.state.draft!.dailyVerseEnabled, isFalse); expect(c.state.record, isNull); c.dispose();
    });
  }
  for (final missing in [false, true]) {
    test('ACK ${missing ? 'missing' : 'failed'} reload distinct from failed save, explicit read recovers', () async {
      final g = FakeReminders()..missingAfterSave = missing;
      final c = FirebaseRemindersController('a', () => g, () => true); await c.load();
      c.edit(c.state.draft!.copyWith(readingReminderEnabled: true));
      if (!missing) g.readError = StateError('offline');
      expect(await c.save(), isTrue); expect(c.state.acknowledged, isTrue);
      expect(c.state.record, isNull); expect(c.state.error, contains('saved; server reload failed'));
      expect(await c.save(), isFalse); expect(g.writes.length, 1);
      g.readError = StateError('still offline'); await c.load();
      expect(c.state.acknowledged, isTrue); expect(c.state.draft!.readingReminderEnabled, isTrue);
      g.readError = null; await c.load(); expect(c.state.acknowledged, isFalse);
      expect(c.state.record == null, missing); expect(g.writes.length, 1); c.dispose();
    });
  }
  test('wrong UID response never shown even from injected gateway', () async {
    final g = FakeReminders()..overrideRecord = record('b', FirebaseReminderPreferences.defaults);
    final c = FirebaseRemindersController('a', () => g, () => true);
    await c.load(); expect(c.state.record, isNull); expect(c.state.draft, isNull);
    expect(c.state.error, contains('account mismatch')); c.dispose();
  });
  for (final stage in ['load', 'write', 'reload']) {
    for (final end in ['switch', 'signout', 'dispose']) {
      for (final failure in [false, true]) {
        test('$stage delayed $end ${failure ? 'error' : 'success'} cannot restore draft/ACK', () async {
          var current = true; final g = FakeReminders();
          final c = FirebaseRemindersController('a', () => g, () => current); await c.load();
          final gate = Completer<void>();
          if (stage == 'write') { g.writeGate = gate; if (failure) g.writeError = StateError('old write'); }
          else { g.readGate = gate; if (failure) g.readError = StateError('old read'); }
          final pending = stage == 'load' ? c.load() : c.save();
          await Future<void>.delayed(Duration.zero);
          if (end == 'dispose') { c.dispose(); } else { current = false; }
          gate.complete(); await pending;
          if (end != 'dispose') {
            expect(c.state.draft, isNull); expect(c.state.record, isNull); expect(c.state.error, isNull);
            expect(c.state.acknowledged, isFalse); expect(c.state.busy, isFalse); c.dispose();
          }
          if (stage == 'write') expect(g.reads.length, 1);
        });
      }
    }
  }
  test('account changed before controller actions clears drafts without constructing gateway', () async {
    var current = true; final g = FakeReminders();
    final c = FirebaseRemindersController('a', () => g, () => current); await c.load();
    current = false; c.edit(FirebaseReminderPreferences.defaults); await c.load();
    expect(await c.save(), isFalse); expect(c.state.draft, isNull); expect(g.reads.length, 1); expect(g.writes, isEmpty); c.dispose();
  });
  test('unready session guards every controller operation without gateway construction', () async {
    final auth = authentication.FakeGateway()..readGate = Completer();
    final container = ProviderContainer(overrides: [firebaseAuthGatewayProvider.overrideWithValue(auth),
      firebaseRemindersGatewayProvider.overrideWith((ref) => throw StateError('No SDK'))]);
    container.listen(firebaseSessionProvider, (_, __) {}); auth.emit(const FirebaseIdentity('a', null));
    await Future<void>.delayed(Duration.zero);
    container.listen(firebaseRemindersProvider('a'), (_, __) {});
    final c = container.read(firebaseRemindersProvider('a').notifier);
    await c.load(); c.edit(FirebaseReminderPreferences.defaults); expect(await c.save(), isFalse);
    expect(c.state.draft, isNull); container.dispose(); auth.readGate!.complete('Private'); await auth.changes.close();
  });

  Future<({ProviderContainer container, authentication.FakeGateway auth, FakeReminders gateway})> mount(
      WidgetTester tester, {FakeReminders? gateway, bool routed = false, bool home = false,
      bool ready = true, bool signedOut = false, bool profileError = false}) async {
    tester.view.physicalSize = const Size(1200, 1600); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final auth = authentication.FakeGateway()..profile = 'Private';
    if (!ready) auth.readGate = Completer();
    if (profileError) auth.profileError = StateError('not ready');
    final g = gateway ?? FakeReminders();
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(auth), firebaseRemindersGatewayProvider.overrideWithValue(g),
      authRepositoryProvider.overrideWith((ref) => throw StateError('No legacy auth')),
      apiClientProvider.overrideWith((ref) => throw StateError('No legacy API')),
    ]);
    container.listen(firebaseSessionProvider, (_, __) {});
    auth.emit(signedOut ? null : const FirebaseIdentity('a', null)); await tester.pump();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: routed
      ? MaterialApp.router(routerConfig: container.read(routerProvider))
      : const MaterialApp(home: FirebaseRemindersScreen())));
    if (routed && !home) container.read(routerProvider).go('/reminders');
    if (g.readGate != null || !ready) { await tester.pump(); } else { await tester.pumpAndSettle(); }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink()); container.dispose();
      if (auth.readGate != null && !auth.readGate!.isCompleted) auth.readGate!.complete('Private');
      if (g.readGate != null && !g.readGate!.isCompleted) g.readGate!.complete();
      if (g.writeGate != null && !g.writeGate!.isCompleted) g.writeGate!.complete();
      await auth.changes.close();
    });
    return (container: container, auth: auth, gateway: g);
  }
  testWidgets('missing UI prominent disclosure, off defaults clearly unsaved, no accidental writes', (tester) async {
    final f = await mount(tester);
    expect(find.text(reminderPreferencesDisclosure), findsOneWidget); expect(find.byKey(const Key('reminders-missing')), findsOneWidget);
    expect(find.textContaining('Asia/Kolkata'), findsOneWidget); expect(find.text('Shared India time: 09:00'), findsOneWidget);
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).every((w) => !w.value), isTrue);
    expect(f.gateway.writes, isEmpty); expect(f.gateway.reads, ['a']);
  });
  testWidgets('existing values populate switches and time selectors', (tester) async {
    final g = FakeReminders()..records['a'] = record('a', FirebaseReminderPreferences.defaults.copyWith(
      readingReminderEnabled: true, dailyVerseEnabled: true, reminderHour: 23, reminderMinute: 59));
    await mount(tester, gateway: g);
    expect(find.text('Shared India time: 23:59'), findsOneWidget);
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).every((w) => w.value), isTrue);
    expect(find.byKey(const Key('reminders-missing')), findsNothing); expect(g.writes, isEmpty);
  });
  testWidgets('toggles and time selectors edit draft only, explicit save then saved server state', (tester) async {
    final f = await mount(tester);
    await tester.tap(find.text('Reading reminder preference')); await tester.pump();
    await tester.tap(find.text('Daily verse preference')); await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<int>).first); await tester.pumpAndSettle();
    await tester.tap(find.text('10').last); await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last); await tester.pumpAndSettle();
    await tester.tap(find.text('01').last); await tester.pumpAndSettle();
    expect(find.text('Shared India time: 10:01'), findsOneWidget); expect(f.gateway.writes, isEmpty);
    await tester.tap(find.text('Save preferences')); await tester.pumpAndSettle();
    expect(f.gateway.writes.length, 1); expect(f.gateway.writes.single.preferences.timeLabel, '10:01');
    expect(f.gateway.writes.single.preferences.readingReminderEnabled, isTrue);
    expect(f.gateway.writes.single.preferences.dailyVerseEnabled, isTrue);
    expect(find.text('Preferences saved and reloaded from server.'), findsOneWidget);
  });
  testWidgets('both off defaults can be saved, no delete or reset UI', (tester) async {
    final f = await mount(tester); await tester.tap(find.text('Save preferences')); await tester.pumpAndSettle();
    expect(f.gateway.writes.single.preferences.toData(), FirebaseReminderPreferences.defaults.toData());
    expect(find.text('Delete'), findsNothing); expect(find.text('Reset'), findsNothing);
  });
  testWidgets('load error shows no stale form and explicit retry, never polls', (tester) async {
    final g = FakeReminders()..readError = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    final f = await mount(tester, gateway: g);
    expect(find.byType(SwitchListTile), findsNothing); expect(find.byKey(const Key('reminders-error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save preferences')).onPressed, isNull);
    await tester.pump(const Duration(seconds: 10)); expect(g.reads, ['a']);
    f.gateway.readError = null; await tester.tap(find.text('Retry server read')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminders-missing')), findsOneWidget); expect(g.writes, isEmpty);
  });
  testWidgets('refresh clears previously visible persisted values while waiting and on failure', (tester) async {
    final g = FakeReminders()..records['a'] = record('a', FirebaseReminderPreferences.defaults.copyWith(reminderHour: 23));
    await mount(tester, gateway: g); g.readGate = Completer(); g.readError = StateError('offline');
    await tester.tap(find.text('Reload from server')); await tester.pump();
    expect(find.text('Shared India time: 23:00'), findsNothing); expect(find.byType(SwitchListTile), findsNothing);
    g.readGate!.complete(); await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing); expect(g.reads.length, 2);
  });
  for (final acknowledged in [false, true]) {
    testWidgets('${acknowledged ? 'ACK reload' : 'uncertain save'} error retains disabled draft and read-only recovery', (tester) async {
      final f = await mount(tester);
      await tester.tap(find.text('Daily verse preference')); await tester.pump();
      if (acknowledged) { f.gateway.readError = StateError('offline'); } else { f.gateway.writeError = StateError('offline'); }
      await tester.tap(find.text('Save preferences')); await tester.pumpAndSettle();
      expect(find.byKey(const Key('reminders-saved')), acknowledged ? findsOneWidget : findsNothing);
      expect(find.textContaining(acknowledged ? 'saved; server reload failed' : 'Save not acknowledged'), findsOneWidget);
      final verse = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).last;
      expect(verse.value, isTrue); expect(verse.onChanged, isNull);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save preferences')).onPressed, isNull);
      expect(f.gateway.writes.length, 1);
      f.gateway.readError = null; f.gateway.writeError = null;
      await tester.tap(find.text('Retry server read')); await tester.pumpAndSettle();
      expect(f.gateway.writes.length, 1); expect(find.byKey(const Key('reminders-error')), findsNothing);
    });
  }
  testWidgets('pending save disables all controls and prevents repeat dispatch', (tester) async {
    final f = await mount(tester, gateway: FakeReminders()..writeGate = Completer());
    await tester.tap(find.text('Save preferences')); await tester.pump();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save preferences')).onPressed, isNull);
    expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).every((w) => w.onChanged == null), isTrue);
    f.gateway.writeGate!.complete(); await tester.pumpAndSettle(); expect(f.gateway.writes.length, 1);
  });
  for (final end in ['switch', 'signout']) {
    for (final stage in ['draft', 'load', 'write', 'reload']) {
      testWidgets('$end during $stage hides old account preferences/delayed results', (tester) async {
        final g = FakeReminders();
        if (stage == 'load') g.readGate = Completer();
        final f = await mount(tester, gateway: g);
        if (stage != 'load') {
          await tester.tap(find.text('Daily verse preference')); await tester.pump();
          if (stage == 'write') g.writeGate = Completer();
          if (stage == 'reload') g.readGate = Completer();
          if (stage == 'write' || stage == 'reload') { await tester.tap(find.text('Save preferences')); await tester.pump(); }
        }
        g.uid = 'b'; f.auth.emit(end == 'signout' ? null : const FirebaseIdentity('b', null)); await tester.pump();
        g.readGate?.complete(); g.writeGate?.complete(); await tester.pumpAndSettle();
        expect(find.byKey(const Key('reminders-saved')), findsNothing);
        if (end == 'signout') { expect(find.byType(SwitchListTile), findsNothing); }
        else {
          expect(tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).every((w) => !w.value), isTrue);
          expect(find.text('Shared India time: 09:00'), findsOneWidget);
        }
        expect(g.writes.every((w) => w.uid == 'a'), isTrue);
      });
    }
  }
  testWidgets('SDK current account change ahead of session stream blocks form callbacks', (tester) async {
    final f = await mount(tester); f.auth.currentUser = const FirebaseIdentity('b', null); f.gateway.uid = 'b';
    await tester.tap(find.text('Save preferences')); await tester.pump();
    expect(f.gateway.writes, isEmpty);
    f.auth.emit(const FirebaseIdentity('b', null)); await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminders-missing')), findsOneWidget);
  });
  testWidgets('ready Firebase route isolates legacy and navigates from accessible workspace entry lazily', (tester) async {
    final f = await mount(tester, routed: true, home: true);
    f.container.read(routerProvider).go('/me'); await tester.pumpAndSettle();
    expect(find.text('Reminders'), findsOneWidget); expect(f.gateway.reads, isEmpty);
    await tester.tap(find.text('Reminders')); await tester.pumpAndSettle();
    expect(find.byType(FirebaseRemindersScreen), findsOneWidget); expect(f.gateway.reads, ['a']);
    await tester.tap(find.byTooltip('Back to my account')); await tester.pumpAndSettle();
    expect(find.byType(FirebaseRemindersScreen), findsNothing);
    expect(f.container.read(routerProvider).routeInformationProvider.value.uri.path, '/me');
  });
  for (final reason in ['signedout', 'busy', 'profileError']) {
    testWidgets('$reason deep link redirects to workspace with zero reminder calls', (tester) async {
      final f = await mount(tester, routed: true, signedOut: reason == 'signedout',
        ready: reason != 'busy', profileError: reason == 'profileError');
      expect(find.byType(FirebaseRemindersScreen), findsNothing); expect(f.gateway.reads, isEmpty); expect(f.gateway.writes, isEmpty);
    });
  }
  testWidgets('ready route redirects immediately on signout without exposing old draft', (tester) async {
    final f = await mount(tester, routed: true);
    await tester.tap(find.text('Daily verse preference')); await tester.pump(); f.auth.emit(null); await tester.pumpAndSettle();
    expect(find.byType(FirebaseRemindersScreen), findsNothing); expect(f.gateway.writes, isEmpty);
  });
  testWidgets('dispose while read pending never updates removed screen', (tester) async {
    final g = FakeReminders()..readGate = Completer(); await mount(tester, gateway: g);
    await tester.pumpWidget(const SizedBox.shrink()); g.readGate!.complete(); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); expect(g.writes, isEmpty);
  });
}