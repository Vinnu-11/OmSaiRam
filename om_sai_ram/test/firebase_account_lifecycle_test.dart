// SDK-shaped doubles only; not live SDK transport or security rules. The
// emulator rule contract is covered by firebase/tests/account-lifecycle.test.mjs.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/core/config/backend_config.dart';
import 'package:om_sai_ram/core/services/api_client.dart';
import 'package:om_sai_ram/core/services/router_service.dart';
import 'package:om_sai_ram/features/auth/providers/auth_provider.dart';
import 'package:om_sai_ram/features/firebase_auth/data/firebase_auth_repository.dart';
import 'package:om_sai_ram/features/firebase_auth/presentation/firebase_auth_screen.dart';
import 'package:om_sai_ram/features/firebase_auth/providers/firebase_session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_auth_mode_test.dart' as authentication;
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;

class LifecycleDb extends chat.ChatDb {
  int pages = 0;
  final events = <String>[];
  @override
  WriteBatch batch() => LifecycleBatch(this);
  @override
  CollectionReference<sdk.Data> collection(String path) => LifecycleCollection(this, path);
  @override
  Future<T> runTransaction<T>(Future<T> Function(Transaction) transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) {
    transactions++;
    return transactionHandler(LifecycleTransaction(this));
  }
}
class LifecycleBatch extends Fake implements WriteBatch {
  final LifecycleDb db;
  final paths = <String>[];
  LifecycleBatch(this.db);
  @override
  void delete(DocumentReference document) => paths.add(document.path);
  @override
  Future<void> commit() async {
    if (db.errors['batch'] != null) throw db.errors['batch']!;
    for (final path in paths) { db.events.add('delete:$path'); db.documents.remove(path); }
  }
}
class LifecycleUser extends sdk.SdkUser {
  final LifecycleDb db;
  DateTime? signedIn = DateTime.now();
  Object? deleteError;
  LifecycleUser(this.db, super.uid);
  @override
  UserMetadata get metadata => UserMetadata(null, signedIn?.millisecondsSinceEpoch);
  @override
  Future<void> delete() async {
    db.events.add('auth-delete');
    if (deleteError != null) throw deleteError!;
  }
}
class LifecycleTransaction extends sdk.SdkTransaction {
  LifecycleTransaction(super.db);
  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    db.writes.add((path: reference.path,
      data: data.map((key, value) => MapEntry(key as String, value)), transaction: true));
    return this;
  }
}
class LifecycleCollection extends chat.ChatCollection {
  LifecycleCollection(LifecycleDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) =>
      LifecycleDocument(db as LifecycleDb, '${this.path}/$path');
  @override
  Query<sdk.Data> orderBy(Object field, {bool descending = false}) {
    expect(field, FieldPath.documentId);
    return IdQuery(db as LifecycleDb, path);
  }
}
class LifecycleDocument extends chat.ChatDocument {
  LifecycleDocument(LifecycleDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String collectionPath) =>
      LifecycleCollection(db as LifecycleDb, '$path/$collectionPath');
}
class IdQuery extends Fake implements Query<sdk.Data> {
  final LifecycleDb db;
  final String path;
  final int? size;
  final String? after;
  IdQuery(this.db, this.path, {this.size, this.after});
  @override
  Query<sdk.Data> limit(int limit) => IdQuery(db, path, size: limit, after: after);
  @override
  Query<sdk.Data> startAfter(Iterable<Object?> values) =>
      IdQuery(db, path, size: size, after: values.single as String);
  @override
  Future<QuerySnapshot<sdk.Data>> get([GetOptions? options]) async {
    db.pages++;
    db.sources.add(options?.source);
    final ids = db.documents.keys.where((key) =>
        key.startsWith('$path/') && !key.substring(path.length + 1).contains('/'))
      .map((key) => key.split('/').last)
      .where((id) => after == null || id.compareTo(after!) > 0).toList()..sort();
    return sdk.QueryResult(ids.take(size!).map((id) => chat.ChatQueryDocument(
        db, '$path/$id', db.documents['$path/$id'], db.metadata('$path/$id'))).toList(),
      sdk.Metadata(isFromCache: db.queryCached));
  }
}

const profilePath = 'users/a';
sdk.Data profileData({bool deactivated = false}) => {
  'displayName': 'Private', 'createdAt': chat.instant, 'updatedAt': chat.instant,
  if (deactivated) 'deactivatedAt': chat.instant,
};
void addGroup(LifecycleDb db, String id, {String createdBy = 'a', String? ownerUid, bool archived = false}) {
  db.documents['users/a/groups/$id'] = {'groupId': id, 'joinedAt': chat.instant};
  db.documents['groups/$id'] = {'name': 'Group $id', 'createdBy': createdBy,
    if (ownerUid != null) 'ownerUid': ownerUid, if (archived) 'archived': true};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SDK repository', () {
    late LifecycleDb db;
    late sdk.SdkAuth auth;
    late FirebaseAuthRepository repository;
    setUp(() {
      db = LifecycleDb(); auth = sdk.SdkAuth();
      db.documents[profilePath] = profileData();
      repository = FirebaseAuthRepository(auth, db);
    });
    test('an active profile reads its name; the deactivation marker is a typed refusal', () async {
      expect(await repository.readProfile('a'), 'Private');
      db.documents[profilePath] = profileData(deactivated: true);
      await expectLater(repository.readProfile('a'), throwsA(isA<FirebaseAccountDeactivated>()));
      await expectLater(repository.ensureProfile('a', 'Other'), throwsA(isA<FirebaseAccountDeactivated>()));
      expect(db.writes, isEmpty);
      expect(db.reads, everyElement(profilePath));
      db.documents.remove(profilePath);
      expect(await repository.readProfile('a'), isNull);
    });
    for (final bad in <sdk.Data>[
      {...profileData(), 'deactivatedAt': true},
      {...profileData(), 'deactivatedAt': null},
      {...profileData(deactivated: true), 'extra': true},
      {...profileData(), 'deactivated': true},
      {'displayName': 'Private', 'createdAt': chat.instant, 'deactivatedAt': chat.instant},
    ]) {
      test('malformed profile $bad fails closed for reads and writes', () async {
        db.documents[profilePath] = bad;
        await expectLater(repository.readProfile('a'), throwsStateError);
        await expectLater(repository.setAccountDeactivated('a', false), throwsStateError);
        expect(db.writes, isEmpty);
      });
    }
    test('deactivation adds the server-time marker only; repeats do not write', () async {
      addGroup(db, 'g1', createdBy: 'b');
      addGroup(db, 'g2', ownerUid: 'b');
      await repository.setAccountDeactivated('a', true);
      expect(db.writes.single.path, profilePath);
      expect(db.writes.single.transaction, isTrue);
      expect(db.writes.single.data, {'deactivatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp()});
      db.documents[profilePath] = profileData(deactivated: true);
      await repository.setAccountDeactivated('a', true);
      expect(db.writes.length, 1);
    });
    test('restoration removes the marker without an ownership scan; a missing profile is refused', () async {
      addGroup(db, 'owned');
      db.documents[profilePath] = profileData(deactivated: true);
      await repository.setAccountDeactivated('a', false);
      expect(db.pages, 0);
      expect(db.writes.single.data, {'deactivatedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp()});
      db.documents[profilePath] = profileData();
      await repository.setAccountDeactivated('a', false);
      expect(db.writes.length, 1);
      db.documents.remove(profilePath);
      await expectLater(repository.setAccountDeactivated('a', false), throwsStateError);
      expect(db.writes.length, 1);
    });
    test('created or transferred-in ownership blocks deactivation before any write', () async {
      addGroup(db, 'created');
      addGroup(db, 'received', createdBy: 'b', ownerUid: 'a');
      addGroup(db, 'handed-over', ownerUid: 'b');
      await expectLater(repository.setAccountDeactivated('a', true), throwsA(isA<FormatException>()
        .having((error) => error.message, 'message', allOf(contains('2 group(s)'),
          contains('Group created'), contains('Group received'), isNot(contains('handed-over'))))));
      expect(db.writes, isEmpty); expect(db.transactions, 0);
    });
    test('ownership scan pages through the whole index and fails closed', () async {
      for (var i = 0; i < 120; i++) { addGroup(db, 'g${i.toString().padLeft(3, '0')}', createdBy: 'b'); }
      addGroup(db, 'z-last');
      await expectLater(repository.setAccountDeactivated('a', true), throwsFormatException);
      expect(db.pages, 3); expect(db.writes, isEmpty);
      db.documents.remove('groups/g000');
      await expectLater(repository.setAccountDeactivated('a', true), throwsStateError);
      db.documents.removeWhere((key, _) => key.startsWith('groups/') || key.startsWith('users/a/groups/'));
      for (var i = 0; i < 500; i++) { addGroup(db, 'g${i.toString().padLeft(3, '0')}', createdBy: 'b'); }
      await expectLater(repository.setAccountDeactivated('a', true), throwsA(isA<FormatException>()
        .having((error) => error.message, 'message', contains('Too many groups'))));
      db.queryCached = true;
      await expectLater(repository.setAccountDeactivated('a', true), throwsStateError);
      expect(db.writes, isEmpty);
    });
    test('another signed-in account or signed-out SDK is refused before any IO', () async {
      auth.currentUser = sdk.SdkUser('b');
      await expectLater(repository.setAccountDeactivated('a', true), throwsStateError);
      await expectLater(repository.deleteAccount('a'), throwsStateError);
      auth.currentUser = null;
      await expectLater(repository.setAccountDeactivated('a', false), throwsStateError);
      await expectLater(repository.deleteAccount('a'), throwsStateError);
      expect(db.reads, isEmpty); expect(db.pages, 0); expect(db.writes, isEmpty);
    });

    group('permanent deletion', () {
      late LifecycleUser user;
      Object? leaveError;
      setUp(() {
        user = LifecycleUser(db, 'a'); auth.currentUser = user; leaveError = null;
        repository = FirebaseAuthRepository(auth, db, leaveGroup: (groupId) async {
          db.events.add('leave:$groupId');
          if (leaveError != null) throw leaveError!;
        });
      });
      test('leaves writable groups, keeps archived ones, deletes private data, then the Auth user', () async {
        addGroup(db, 'g1', createdBy: 'b');
        addGroup(db, 'g2', ownerUid: 'b', archived: true);
        addGroup(db, 'g3', createdBy: 'b');
        expect(await repository.deleteAccount('a'), 1);
        expect(db.events, ['leave:g1', 'leave:g3', 'delete:users/a/settings/reminders',
          'delete:users/a', 'auth-delete']);
      });
      test('a stale or unknown sign-in time refuses before any read or removal', () async {
        addGroup(db, 'g1', createdBy: 'b');
        for (final signedIn in [DateTime.now().subtract(const Duration(minutes: 6)), null]) {
          user.signedIn = signedIn;
          await expectLater(repository.deleteAccount('a'), throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('log in again'))));
        }
        expect(db.events, isEmpty); expect(db.pages, 0); expect(db.reads, isEmpty);
      });
      test('owned groups block deletion before leaving any other group', () async {
        addGroup(db, 'a-member', createdBy: 'b');
        addGroup(db, 'owned');
        await expectLater(repository.deleteAccount('a'), throwsA(isA<FormatException>()
          .having((error) => error.message, 'message', allOf(contains('before deleting the account'), contains('Group owned')))));
        expect(db.events, isEmpty);
      });
      test('a failed departure stops before private data and the Auth user are touched', () async {
        addGroup(db, 'g1', createdBy: 'b'); addGroup(db, 'g2', createdBy: 'b');
        leaveError = StateError('offline');
        await expectLater(repository.deleteAccount('a'), throwsStateError);
        expect(db.events, ['leave:g1']);
        db.events.clear();
        await expectLater(FirebaseAuthRepository(auth, db).deleteAccount('a'), throwsStateError);
        expect(db.events, isEmpty);
      });
      test('data and Auth failures propagate in order; a retry with nothing left still deletes the sign-in', () async {
        db.errors['batch'] = StateError('offline');
        await expectLater(repository.deleteAccount('a'), throwsStateError);
        expect(db.events, isEmpty);
        db.errors.clear();
        user.deleteError = FirebaseAuthException(code: 'requires-recent-login');
        await expectLater(repository.deleteAccount('a'), throwsA(isA<FirebaseAuthException>()));
        expect(db.events, ['delete:users/a/settings/reminders', 'delete:users/a', 'auth-delete']);
        user.deleteError = null; db.events.clear();
        expect(await repository.deleteAccount('a'), 0);
        expect(db.events.last, 'auth-delete');
      });
    });
  });

  group('session', () {
    late authentication.FakeGateway gateway;
    late ProviderContainer container;
    late FirebaseSessionController controller;
    FirebaseSession session() => container.read(firebaseSessionProvider);
    setUp(() async {
      gateway = authentication.FakeGateway()..profile = 'Sai';
      container = ProviderContainer(
          overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)]);
      container.listen(firebaseSessionProvider, (_, __) {});
      controller = container.read(firebaseSessionProvider.notifier);
      gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
      await Future<void>.delayed(Duration.zero);
    });
    tearDown(() async { container.dispose(); await gateway.changes.close(); });

    test('deactivate then restore follows server-confirmed state only', () async {
      expect(session().ready, isTrue);
      await controller.setAccountDeactivated(true);
      expect(session().deactivated, isTrue); expect(session().ready, isFalse);
      expect(session().user?.uid, 'a'); expect(session().error, isNull);
      expect(session().displayName, isNull);
      await controller.setAccountDeactivated(true);
      expect(gateway.lifecycle, [true]);
      await controller.setAccountDeactivated(false);
      expect(session().ready, isTrue); expect(session().displayName, 'Sai');
      await controller.setAccountDeactivated(false);
      expect(gateway.lifecycle, [true, false]);
    });
    test('ownership refusal keeps the session ready and shows the reason', () async {
      gateway.lifecycleError = const FormatException('Transfer ownership of 1 group(s) before deactivating: Satsang.');
      await controller.setAccountDeactivated(true);
      expect(session().ready, isTrue); expect(session().deactivated, isFalse);
      expect(session().notice, contains('Transfer ownership'));
    });
    for (final applied in [false, true]) {
      test('unconfirmed write (${applied ? 'applied' : 'not applied'}) hides SDK text and trusts the reload', () async {
        gateway.lifecycleError = StateError('secret transport detail');
        if (applied) gateway.deactivated = true;
        await controller.setAccountDeactivated(true);
        expect(session().deactivated, applied); expect(session().ready, !applied);
        expect(session().notice, contains('could not be confirmed'));
        expect(session().notice, isNot(contains('secret')));
      });
    }
    test('reload failure after the write is a visible, retryable error', () async {
      final reads = gateway.reads;
      gateway.profileError = StateError('offline');
      await controller.setAccountDeactivated(true);
      expect(gateway.lifecycle, [true]); expect(gateway.reads, reads + 1);
      expect(session().ready, isFalse); expect(session().error, isNotNull);
      gateway.profileError = null;
      await controller.reloadProfile();
      expect(session().deactivated, isTrue); expect(session().error, isNull);
    });
    test('sign-in to a deactivated account never becomes ready; logout clears it', () async {
      await controller.signOut();
      gateway.deactivated = true;
      await controller.signIn('a@example.com', 'secret');
      expect(session().deactivated, isTrue); expect(session().ready, isFalse);
      await controller.retryProfile('Other name');
      expect(session().deactivated, isTrue);
      await controller.signOut();
      expect(session().user, isNull); expect(session().deactivated, isFalse);
    });
    test('requests are ignored while busy, signed out or after an account switch', () async {
      gateway.currentUser = const FirebaseIdentity('b', 'b@example.com');
      await controller.setAccountDeactivated(true);
      await controller.deleteAccount();
      await controller.signOut();
      await controller.setAccountDeactivated(true);
      await controller.setAccountDeactivated(false);
      await controller.deleteAccount();
      expect(gateway.lifecycle, isEmpty); expect(gateway.deletions, 0);
    });
    test('deletion signs out with a plain result; archived memberships are disclosed', () async {
      await controller.deleteAccount();
      expect(session().user, isNull); expect(session().ready, isFalse);
      expect(session().notice, 'Your account was deleted.'); expect(gateway.deletions, 1);
      gateway.profile = 'Sai'; gateway.retained = 2;
      await controller.signIn('a@example.com', 'secret');
      await controller.deleteAccount();
      expect(session().user, isNull); expect(session().notice, contains('2 archived group(s)'));
    });
    test('a refusal keeps the ready session and explains why; deactivated accounts must restore first', () async {
      gateway.deleteError = const FormatException('Transfer ownership of 1 group(s) before deleting the account: Satsang.');
      await controller.deleteAccount();
      expect(session().ready, isTrue); expect(session().notice, contains('Transfer ownership'));
      gateway.deleteError = null;
      await controller.setAccountDeactivated(true);
      await controller.deleteAccount();
      expect(gateway.deletions, 1); expect(session().deactivated, isTrue);
    });
    test('a sign-in that survives data removal is reported with the way to finish', () async {
      gateway.deleteError = FirebaseAuthException(code: 'requires-recent-login', message: 'secret');
      gateway.profile = null;
      await controller.deleteAccount();
      expect(session().user?.uid, 'a'); expect(session().ready, isFalse);
      expect(session().notice, contains('fresh login')); expect(session().notice, isNot(contains('secret')));
      gateway.deleteError = StateError('secret transport'); gateway.profile = 'Sai';
      await controller.reloadProfile();
      await controller.deleteAccount();
      expect(session().ready, isTrue); expect(session().notice, contains('did not finish'));
      expect(session().notice, isNot(contains('secret')));
    });
  });

  testWidgets('workspace confirms deactivation, shows the retained-data notice and restores', (tester) async {
    final gateway = authentication.FakeGateway()..profile = 'Sai';
    await tester.pumpWidget(ProviderScope(
        overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: FirebaseAuthScreen())));
    gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
    await tester.pumpAndSettle();
    final deactivate = find.byKey(const Key('account-deactivate'));
    await tester.ensureVisible(deactivate); await tester.tap(deactivate); await tester.pumpAndSettle();
    expect(find.textContaining('not account deletion or data erasure'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(gateway.lifecycle, isEmpty);
    expect(find.byKey(const Key('firebase-ready')), findsOneWidget);
    await tester.ensureVisible(deactivate); await tester.tap(deactivate); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-deactivate-confirm'))); await tester.pumpAndSettle();
    expect(gateway.lifecycle, [true]);
    expect(find.byKey(const Key('account-deactivated')), findsOneWidget);
    expect(find.byKey(const Key('firebase-ready')), findsNothing);
    expect(find.text('My groups'), findsNothing);
    expect(find.text('One more step: tell us your name'), findsNothing);
    expect(find.text('Log out'), findsOneWidget);
    final restore = find.byKey(const Key('account-restore'));
    await tester.ensureVisible(restore); await tester.tap(restore); await tester.pumpAndSettle();
    expect(find.text('Signed in as Sai'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await gateway.changes.close();
  });

  testWidgets('a session change while the dialog is open cancels deactivation', (tester) async {
    final gateway = authentication.FakeGateway()..profile = 'Sai';
    await tester.pumpWidget(ProviderScope(
        overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: FirebaseAuthScreen())));
    gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
    await tester.pumpAndSettle();
    final deactivate = find.byKey(const Key('account-deactivate'));
    await tester.ensureVisible(deactivate); await tester.tap(deactivate); await tester.pumpAndSettle();
    gateway.emit(const FirebaseIdentity('b', 'b@example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-deactivate-confirm'))); await tester.pumpAndSettle();
    expect(gateway.lifecycle, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await gateway.changes.close();
  });

  testWidgets('account deletion needs explicit confirmation and ends signed out; pending profiles can delete too', (tester) async {
    final gateway = authentication.FakeGateway()..profile = 'Sai';
    await tester.pumpWidget(ProviderScope(
        overrides: [firebaseAuthGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: FirebaseAuthScreen())));
    gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('account-delete'));
    await tester.ensureVisible(delete); await tester.tap(delete); await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.textContaining('anonymous ID'), findsOneWidget);
    await tester.tap(find.text('Cancel')); await tester.pumpAndSettle();
    expect(gateway.deletions, 0); expect(find.byKey(const Key('firebase-ready')), findsOneWidget);
    await tester.ensureVisible(delete); await tester.tap(delete); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-delete-confirm'))); await tester.pumpAndSettle();
    expect(gateway.deletions, 1);
    expect(find.text('Your account was deleted.'), findsOneWidget);
    expect(find.byKey(const Key('firebase-ready')), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    gateway.emit(const FirebaseIdentity('b', 'b@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('One more step: tell us your name'), findsOneWidget);
    await tester.ensureVisible(delete); await tester.tap(delete); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-delete-confirm'))); await tester.pumpAndSettle();
    expect(gateway.deletions, 2); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await gateway.changes.close();
  });

  testWidgets('deactivated sessions are redirected away from protected routes', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    final gateway = authentication.FakeGateway()..profile = 'Sai'..deactivated = true;
    final container = ProviderContainer(overrides: [
      backendConfigProvider.overrideWithValue(authentication.config()),
      firebaseAuthGatewayProvider.overrideWithValue(gateway),
      authStateProvider.overrideWith((ref) => throw StateError('Legacy auth was accessed')),
      apiClientProvider.overrideWith((ref) => throw StateError('Legacy API was accessed')),
    ]);
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    gateway.emit(const FirebaseIdentity('a', 'a@example.com'));
    await tester.pumpAndSettle();
    for (final path in ['/groups', '/tasks', '/account', '/reminders', '/groups/g/chat']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-groups')), findsNothing);
      final finish = find.byKey(const Key('home-finish-setup'));
      await tester.scrollUntilVisible(finish, 200, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    }
    // Home leads to the account page, which offers restoration.
    await tester.tap(find.byKey(const Key('home-finish-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-deactivated')), findsOneWidget);
    expect(find.byKey(const Key('account-restore')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await gateway.changes.close();
  });
}
