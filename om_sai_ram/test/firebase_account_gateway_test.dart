// SDK-shaped doubles only; not live SDK transport, security rules or delivery.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_account_gateway.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_account_models.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;
import 'firestore_reminders_gateway_test.dart' as reminders;

final created = Timestamp(1700000000, 123456789);
final updated = Timestamp(1700000001, 987654321);
sdk.Data profileData([String name = 'Private']) => {
  'displayName': name, 'createdAt': created, 'updatedAt': updated,
};

class AccountAuth extends sdk.SdkAuth {
  final emails = <String>[];
  Object? resetError;
  Completer<void>? resetGate;
  int streamCalls = 0;
  @override
  Future<void> sendPasswordResetEmail({required String email, ActionCodeSettings? actionCodeSettings}) async {
    expect(actionCodeSettings, isNull);
    emails.add(email);
    await resetGate?.future;
    if (resetError != null) throw resetError!;
  }
}
class AccountDb extends reminders.ReminderDb {
  int attempts = 1;
  void Function(int)? onAttempt;
  Completer<void>? commitGate;
  Object? commitError;
  final events = <String>[];
  @override
  Future<chat.ChatSnapshot> read(String path, GetOptions? options) {
    events.add('read:$path');
    return super.read(path, options);
  }
  @override
  Future<T> runTransaction<T>(Future<T> Function(Transaction) transactionHandler,
      {Duration timeout = const Duration(seconds: 30), int maxAttempts = 5}) async {
    transactions++;
    late T result;
    for (var i = 0; i < attempts; i++) {
      onAttempt?.call(i);
      final transaction = AccountTransaction(this);
      result = await transactionHandler(transaction);
      if (i == attempts - 1) {
        await commitGate?.future;
        if (commitError != null) throw commitError!;
        for (final write in transaction.staged) {
          writes.add(write);
          documents[write.path]!.addAll(write.data.map((key, value) =>
            MapEntry(key, value is FieldValue ? updated : value)));
        }
      }
    }
    return result;
  }
}
class AccountTransaction extends sdk.SdkTransaction {
  final staged = <({String path, sdk.Data data, bool transaction})>[];
  AccountTransaction(AccountDb super.db);
  @override
  Transaction update(DocumentReference reference, Map<Object, Object?> data) {
    (db as AccountDb).events.add('update:${reference.path}');
    staged.add((path: reference.path,
      data: data.map((key, value) => MapEntry(key as String, value)), transaction: true));
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountAuth auth;
  late AccountDb db;
  late SdkFirebaseAccountGateway gateway;
  setUp(() {
    auth = AccountAuth(); db = AccountDb();
    db.documents['users/a'] = profileData();
    gateway = SdkFirebaseAccountGateway(auth, db);
  });
  test('strict immutable profile retains exact SDK Timestamp objects/nanoseconds', () {
    final raw = profileData(); final model = FirebasePrivateProfile.parse('a', raw);
    raw['displayName'] = 'Tampered';
    expect(model.displayName, 'Private'); expect(model.uid, 'a');
    expect(identical(model.createdAt, created), isTrue);
    expect(identical(model.updatedAt, updated), isTrue);
    expect(model.createdAt.nanoseconds, 123456789);
    expect(model.updatedAt.nanoseconds, 987654321);
  });
  for (final field in ['displayName', 'createdAt', 'updatedAt']) {
    test('missing $field fails model/read/update without creating profile', () async {
      db.documents['users/a']!.remove(field);
      expect(() => FirebasePrivateProfile.parse('a', db.documents['users/a']), throwsFormatException);
      await expectLater(gateway.read(), throwsFormatException);
      await expectLater(gateway.updateName('New'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final field in ['email', 'uid', 'userId', 'role', 'phone', 'extra']) {
    test('extra $field fails closed without writes', () async {
      db.documents['users/a']![field] = 'secret';
      await expectLater(gateway.read(), throwsFormatException);
      await expectLater(gateway.updateName('New'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final name in <Object?>[null, 42, true, {}, [], '', ' ', ' name', 'name ', 'x' * 101]) {
    test('malformed stored name ${name.runtimeType} $name rejected', () async {
      db.documents['users/a']!['displayName'] = name;
      await expectLater(gateway.read(), throwsFormatException);
      await expectLater(gateway.updateName('New'), throwsFormatException);
      expect(db.writes, isEmpty);
    });
  }
  for (final field in ['createdAt', 'updatedAt']) {
    for (final time in <Object?>[null, 1, 'now', true, DateTime.utc(2026), FieldValue.serverTimestamp(),
      reminders.InvalidTimestamp(-62135596801, 0), reminders.InvalidTimestamp(253402300800, 0),
      reminders.InvalidTimestamp(0, -1), reminders.InvalidTimestamp(0, 1000000000)]) {
      test('$field invalid timestamp $time rejected without coercion', () async {
        db.documents['users/a']![field] = time;
        await expectLater(gateway.read(), throwsFormatException);
        await expectLater(gateway.updateName('New'), throwsFormatException);
        expect(db.writes, isEmpty);
      });
    }
  }
  test('Timestamp and name exact boundaries accepted', () {
    for (final time in [Timestamp(-62135596800, 0), Timestamp(253402300799, 999999999)]) {
      final model = FirebasePrivateProfile.parse('a', {
        'displayName': 'x' * 100, 'createdAt': time, 'updatedAt': time});
      expect(identical(model.createdAt, time), isTrue);
    }
    expect(FirebasePrivateProfile.parse('a', profileData('x')).displayName, 'x');
  });
  for (final uid in ['', '.', '..', 'x/y', '__reserved__', 'é' * 751]) {
    test('invalid SDK UID length ${uid.length} rejects model/read/write before IO', () async {
      auth.currentUser = sdk.SdkUser(uid);
      expect(() => FirebasePrivateProfile.parse(uid, profileData()), throwsFormatException);
      await expectLater(gateway.read(), throwsFormatException);
      await expectLater(gateway.updateName('New'), throwsFormatException);
      expect(db.reads, isEmpty); expect(db.transactions, 0);
    });
  }
  test('signed out has no profile IO', () async {
    auth.currentUser = null;
    await expectLater(gateway.read(), throwsFormatException);
    await expectLater(gateway.updateName('New'), throwsFormatException);
    expect(db.reads, isEmpty); expect(db.transactions, 0);
  });
  test('server-only exact SDK self path; no other private/public/Auth reads', () async {
    final result = await gateway.read();
    expect(result.uid, 'a'); expect(db.reads, ['users/a']);
    expect(db.sources, [Source.server]); expect(db.writes, isEmpty);
    auth.currentUser = sdk.SdkUser('b'); db.documents['users/b'] = profileData('B');
    expect((await gateway.read()).uid, 'b'); expect(db.reads.last, 'users/b');
  });
  test('missing profile rejected and transaction cannot create it', () async {
    db.documents.clear();
    await expectLater(gateway.read(), throwsFormatException);
    await expectLater(gateway.updateName('New'), throwsFormatException);
    expect(db.documents, isEmpty); expect(db.writes, isEmpty);
  });
  test('transaction reads before two-field update and preserves exact createdAt nanos', () async {
    await gateway.updateName('  New private  ');
    expect(db.events, ['read:users/a', 'update:users/a']);
    expect(db.writes.single.path, 'users/a');
    expect(db.writes.single.transaction, isTrue);
    expect(db.writes.single.data, {
      'displayName': 'New private', 'updatedAt': FieldValue.serverTimestamp()});
    expect(identical(db.documents['users/a']!['createdAt'], created), isTrue);
    expect(db.documents['users/a']!.keys.toSet(), {'displayName', 'createdAt', 'updatedAt'});
    expect(db.sets, 0); expect(db.reads, ['users/a']); // No hidden reload after ACK.
  });
  for (final name in ['', ' ', 'x' * 101]) {
    test('invalid draft length ${name.length} no IO', () async {
      await expectLater(gateway.updateName(name), throwsFormatException);
      expect(db.reads, isEmpty); expect(db.transactions, 0);
    });
  }
  for (final missing in [false, true]) {
    for (final kind in ['cache', 'pending', 'path', 'id']) {
      test('$kind ${missing ? 'missing' : 'existing'} snapshot rejects read and transaction', () async {
        if (missing) db.documents.clear();
        if (kind == 'cache') db.cached.add('users/a');
        if (kind == 'pending') db.pending.add('users/a');
        if (kind == 'path') db.poisonPath = 'groups/g/memberProfiles/a';
        if (kind == 'id') db.poisonPath = 'users/b';
        final matcher = kind == 'cache' || kind == 'pending' ? throwsStateError : throwsFormatException;
        await expectLater(gateway.read(), matcher);
        await expectLater(gateway.updateName('New'), matcher);
        expect(db.writes, isEmpty);
      });
    }
  }
  for (final operation in ['read', 'update']) {
    test('$operation rechecks SDK UID before dispatch after reference creation', () async {
      db.onReference = () => auth.currentUser = sdk.SdkUser('b');
      await expectLater(operation == 'read' ? gateway.read() : gateway.updateName('New'), throwsStateError);
      expect(db.reads, isEmpty); expect(db.transactions, 0);
    });
    for (final end in ['switch', 'signout']) {
      for (final failure in [false, true]) {
        test('$operation pending read $end ${failure ? 'failed' : 'successful'} future discarded', () async {
          db.gates['users/a'] = Completer();
          if (failure) db.errors['users/a'] = StateError('old transport');
          final request = expectLater(operation == 'read' ? gateway.read() : gateway.updateName('New'), throwsStateError);
          await chat.flush(); auth.currentUser = end == 'switch' ? sdk.SdkUser('b') : null;
          db.gates['users/a']!.complete(); await request;
          expect(db.writes, isEmpty);
        });
      }
    }
    test('$operation account changes during data parsing rejects old value', () async {
      db.onData = () => auth.currentUser = sdk.SdkUser('b');
      await expectLater(operation == 'read' ? gateway.read() : gateway.updateName('New'), throwsStateError);
      expect(db.writes, isEmpty);
    });
  }
  test('transaction retry rereads and preserves concurrently changed createdAt', () async {
    final newer = Timestamp(1700000002, 111222333);
    db.attempts = 2;
    db.onAttempt = (attempt) { if (attempt == 1) db.documents['users/a']!['createdAt'] = newer; };
    await gateway.updateName('New');
    expect(db.reads, ['users/a', 'users/a']); expect(db.writes.length, 1);
    expect(identical(db.documents['users/a']!['createdAt'], newer), isTrue);
  });
  for (final change in ['uid', 'missing', 'malformed']) {
    test('transaction retry rechecks $change before writing', () async {
      db.attempts = 2;
      db.onAttempt = (attempt) {
        if (attempt != 1) return;
        if (change == 'uid') auth.currentUser = sdk.SdkUser('b');
        if (change == 'missing') db.documents.clear();
        if (change == 'malformed') db.documents['users/a']!['email'] = 'no';
      };
      await expectLater(gateway.updateName('New'), change == 'uid' ? throwsStateError : throwsFormatException);
      expect(db.writes, isEmpty); expect(db.reads.length, change == 'uid' ? 1 : 2);
    });
  }
  for (final failure in [false, true]) {
    test('account changes while transaction commit ${failure ? 'fails' : 'ACKs'} result discarded', () async {
      db.commitGate = Completer(); if (failure) db.commitError = StateError('old commit');
      final request = expectLater(gateway.updateName('New'), throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('b');
      db.commitGate!.complete(); await request;
      expect(db.writes.length, failure ? 0 : 1); // Already-dispatched write cannot be undone.
      if (!failure) expect(db.writes.single.path, 'users/a');
    });
  }
  for (final code in ['permission-denied', 'unavailable']) {
    test('$code read and commit failures never auto retry or create profile', () async {
      db.errors['users/a'] = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.read(), throwsA(isA<FirebaseException>()));
      db.errors.clear(); db.commitError = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(gateway.updateName('New'), throwsA(isA<FirebaseException>()));
      expect(db.transactions, 1); expect(db.writes, isEmpty);
    });
  }
  for (final email in ['', ' ', 'a', 'a@b', '@b.com', 'a@@b.com', 'a b@b.com', 'a@b. com', '${'a' * 250}@b.com']) {
    test('invalid reset email $email rejected before SDK or Firestore', () async {
      auth.currentUser = null;
      await expectLater(gateway.requestPasswordReset(email), throwsFormatException);
      expect(auth.emails, isEmpty); expect(db.reads, isEmpty); expect(db.transactions, 0);
    });
  }
  for (final code in <String?>[null, 'user-not-found']) {
    test('reset ${code ?? 'SDK ACK'} same void result, trimmed email defaults only no auth mutation/storage', () async {
      auth.currentUser = null;
      if (code != null) auth.resetError = FirebaseAuthException(code: code, message: 'SECRET SDK DETAIL');
      await gateway.requestPasswordReset('  Person@example.com  ');
      expect(auth.emails, ['Person@example.com']); expect(auth.currentUser, isNull);
      expect(db.reads, isEmpty); expect(db.writes, isEmpty); expect(db.transactions, 0);
    });
  }
  test('signed in reset rejected without SDK or storage', () async {
    await expectLater(gateway.requestPasswordReset('a@b.com'), throwsStateError);
    expect(auth.emails, isEmpty); expect(db.reads, isEmpty);
  });
  for (final code in ['invalid-email', 'too-many-requests', 'network-request-failed', 'internal-error', 'user-disabled']) {
    test('reset $code safe mapped message no raw detail and no retry', () async {
      auth.currentUser = null;
      auth.resetError = FirebaseAuthException(code: code, message: 'SECRET SDK DETAIL token=secret');
      Object? caught;
      try { await gateway.requestPasswordReset('a@b.com'); } catch (error) { caught = error; }
      expect(caught, isA<FirebaseAuthException>()); expect(accountError(caught!), isNot(contains('SECRET')));
      expect(accountError(caught), isNot(contains('token')));
      expect(auth.emails.length, 1); expect(db.reads, isEmpty); expect(db.writes, isEmpty);
    });
  }
  for (final failure in [false, true]) {
    test('public reset delayed ${failure ? 'failure' : 'ACK'} after sign in is discarded', () async {
      auth.currentUser = null; auth.resetGate = Completer();
      if (failure) auth.resetError = FirebaseAuthException(code: 'user-not-found');
      final request = expectLater(gateway.requestPasswordReset('a@b.com'), throwsStateError);
      await chat.flush(); auth.currentUser = sdk.SdkUser('b');
      auth.resetGate!.complete(); await request;
      expect(auth.emails.length, 1); expect(auth.currentUser!.uid, 'b'); expect(db.reads, isEmpty);
    });
  }
}