// SDK-shaped doubles only: not live transport, security-rules or E2E coverage.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firebase_reminder_models.dart';
import 'package:om_sai_ram/features/firebase_reminders/data/firestore_reminders_gateway.dart';
import 'firestore_assignments_gateway_test.dart' as sdk;
import 'firestore_chat_gateway_test.dart' as chat;

const path = 'users/a/settings/reminders';
final instant = Timestamp(1700000000, 123456789);
sdk.Data data() => {...FirebaseReminderPreferences.defaults.toData(), 'updatedAt': instant};

class ReminderDb extends chat.ChatDb {
  void Function()? onReference, onData;
  SetOptions? setOptions;
  int sets = 0;
  @override
  CollectionReference<sdk.Data> collection(String path) {
    onReference?.call();
    return ReminderCollection(this, path);
  }
  @override
  Future<chat.ChatSnapshot> read(String path, GetOptions? options) async {
    final snapshot = await super.read(path, options);
    return ReminderSnapshot(this, poisonPath ?? path, snapshot.raw, snapshot.metadata);
  }
}
class ReminderSnapshot extends chat.ChatSnapshot {
  final ReminderDb store;
  ReminderSnapshot(this.store, String path, sdk.Data? raw, SnapshotMetadata metadata)
      : super(store, path, raw, metadata);
  @override
  sdk.Data? data() { store.onData?.call(); return super.data(); }
}
class ReminderCollection extends chat.ChatCollection {
  ReminderCollection(ReminderDb super.db, super.path);
  @override
  DocumentReference<sdk.Data> doc([String? path]) => ReminderDocument(db as ReminderDb, '${this.path}/$path');
}
class ReminderDocument extends chat.ChatDocument {
  ReminderDocument(ReminderDb super.db, super.path);
  @override
  CollectionReference<sdk.Data> collection(String collectionPath) => ReminderCollection(db as ReminderDb, '${this.path}/$collectionPath');
  @override
  Future<void> set(sdk.Data data, [SetOptions? options]) async {
    final store = db as ReminderDb;
    store.sets++; store.setOptions = options;
    await super.set(data, options);
    store.documents[this.path] = data.map((key, value) => MapEntry(key, value is FieldValue ? instant : value));
  }
}
class InvalidTimestamp extends Fake implements Timestamp {
  @override
  final int seconds;
  @override
  final int nanoseconds;
  InvalidTimestamp(this.seconds, this.nanoseconds);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReminderDb db;
  late sdk.SdkAuth auth;
  late FirestoreRemindersGateway gateway;
  setUp(() { db = ReminderDb(); auth = sdk.SdkAuth(); gateway = FirestoreRemindersGateway(auth, db); });

  test('conservative exact defaults and immutable copies with no timestamp in preferences', () {
    const defaults = FirebaseReminderPreferences.defaults;
    expect(defaults.toData(), {'readingReminderEnabled': false, 'dailyVerseEnabled': false,
      'reminderHour': 9, 'reminderMinute': 0, 'timezone': 'Asia/Kolkata'});
    final changed = defaults.copyWith(readingReminderEnabled: true, dailyVerseEnabled: true, reminderHour: 23, reminderMinute: 59);
    expect(changed.timeLabel, '23:59'); expect(defaults.timeLabel, '09:00');
    changed.toData()['reminderHour'] = 1;
    expect(changed.reminderHour, 23); expect(defaults.readingReminderEnabled, isFalse);
  });
  test('strict record retains original Timestamp with all nanoseconds', () {
    final record = FirebaseReminderRecord.parse('a', data());
    expect(record.uid, 'a'); expect(identical(record.updatedAt, instant), isTrue);
    expect(record.updatedAt.nanoseconds, 123456789);
  });
  for (final field in {...FirebaseReminderPreferences.fields, 'updatedAt'}) {
    test('missing record $field fails closed including gateway', () async {
      final raw = data()..remove(field);
      expect(() => FirebaseReminderRecord.parse('a', raw), throwsFormatException);
      db.documents[path] = raw;
      await expectLater(gateway.read(), throwsFormatException); expect(db.writes, isEmpty);
    });
  }
  for (final field in FirebaseReminderPreferences.fields) {
    test('missing preference $field cannot be saved', () {
      expect(() => FirebaseReminderPreferences.parse(FirebaseReminderPreferences.defaults.toData()..remove(field)), throwsFormatException);
    });
  }
  for (final field in ['uid', 'userId', 'role', 'fcmToken', 'createdAt', 'deadlineHour', 'extra']) {
    test('extra $field rejected by record and preferences', () async {
      expect(() => FirebaseReminderPreferences.parse({...FirebaseReminderPreferences.defaults.toData(), field: true}), throwsFormatException);
      db.documents[path] = {...data(), field: true};
      await expectLater(gateway.read(), throwsFormatException); expect(db.writes, isEmpty);
    });
  }
  for (final field in ['readingReminderEnabled', 'dailyVerseEnabled']) {
    for (final bad in <Object?>['true', 'false', 0, 1, null, {}, []]) {
      test('$field strictly boolean rejects $bad', () {
        expect(() => FirebaseReminderRecord.parse('a', {...data(), field: bad}), throwsFormatException);
      });
    }
  }
  for (final field in ['reminderHour', 'reminderMinute']) {
    final max = field == 'reminderHour' ? 23 : 59;
    for (final bad in <Object?>[-1, max + 1, 0.5, 0.0, '0', null, false, true, {}, []]) {
      test('$field bounded integer rejects $bad (${bad.runtimeType})', () {
        expect(() => FirebaseReminderRecord.parse('a', {...data(), field: bad}), throwsFormatException);
      });
    }
  }
  for (final bad in <Object?>['UTC', 'Asia/Calcutta', '', ' Asia/Kolkata ', null, 1, {}]) {
    test('timezone rejects $bad', () {
      expect(() => FirebaseReminderRecord.parse('a', {...data(), 'timezone': bad}), throwsFormatException);
    });
  }
  for (final bad in <Object?>[null, 1, 'now', true, DateTime.utc(2026), FieldValue.serverTimestamp(),
    InvalidTimestamp(-62135596801, 0), InvalidTimestamp(253402300800, 0),
    InvalidTimestamp(0, -1), InvalidTimestamp(0, 1000000000)]) {
    test('invalid timestamp ${bad.runtimeType} ${bad is Timestamp ? '${bad.seconds}/${bad.nanoseconds}' : bad} rejected', () {
      expect(() => FirebaseReminderRecord.parse('a', {...data(), 'updatedAt': bad}), throwsFormatException);
    });
  }
  test('null model data fails as FormatException', () {
    expect(() => FirebaseReminderRecord.parse('a', null), throwsFormatException);
    expect(() => FirebaseReminderPreferences.parse(null), throwsFormatException);
  });
  test('time and timestamp exact minimum/maximum boundaries accepted', () {
    for (final pair in [(0, 0), (23, 59)]) {
      final preferences = FirebaseReminderPreferences.defaults.copyWith(reminderHour: pair.$1, reminderMinute: pair.$2);
      expect(preferences.reminderHour, pair.$1); expect(preferences.reminderMinute, pair.$2);
    }
    for (final time in [Timestamp(-62135596800, 0), Timestamp(253402300799, 999999999)]) {
      expect(identical(FirebaseReminderRecord.parse('a', {...data(), 'updatedAt': time}).updatedAt, time), isTrue);
    }
    expect(() => FirebaseReminderPreferences.defaults.copyWith(reminderHour: 24), throwsFormatException);
    expect(() => FirebaseReminderPreferences.defaults.copyWith(reminderMinute: 60), throwsFormatException);
  });
  test('missing server-only read returns null, never creates prefs or parent profile', () async {
    expect(await gateway.read(), isNull);
    expect(db.reads, [path]); expect(db.sources, [Source.server]);
    expect(db.documents, isEmpty); expect(db.writes, isEmpty); expect(db.sets, 0); expect(db.transactions, 0);
  });
  test('existing server values loaded without writes or unrelated reads', () async {
    db.documents[path] = {...data(), 'reminderHour': 23, 'reminderMinute': 59, 'dailyVerseEnabled': true};
    final result = await gateway.read(); expect(result!.preferences.timeLabel, '23:59');
    expect(result.preferences.dailyVerseEnabled, isTrue); expect(db.reads, [path]); expect(db.writes, isEmpty);
  });
  test('full replacement exact SDK path with server time, off defaults do not delete', () async {
    db.documents[path] = {...data(), 'stale': true};
    await gateway.save(FirebaseReminderPreferences.defaults);
    expect(db.writes.single.path, path); expect(db.writes.single.transaction, isFalse);
    expect(db.writes.single.data, {...FirebaseReminderPreferences.defaults.toData(), 'updatedAt': FieldValue.serverTimestamp()});
    expect(db.setOptions, isNull); expect(db.reads, isEmpty); expect(db.transactions, 0);
    expect(db.documents[path]!.keys.toSet(), {...FirebaseReminderPreferences.fields, 'updatedAt'});
    expect(db.documents.containsKey('users/a'), isFalse);
  });
  test('changed account uses only that current SDK account path', () async {
    auth.currentUser = sdk.SdkUser('b');
    await gateway.save(FirebaseReminderPreferences.defaults.copyWith(dailyVerseEnabled: true));
    expect(db.writes.single.path, 'users/b/settings/reminders');
    expect((await gateway.read())!.uid, 'b'); expect(db.reads, ['users/b/settings/reminders']);
    expect(db.documents.containsKey(path), isFalse);
  });
  for (final uid in ['', '.', '..', 'x/y', '__reserved__', 'é' * 751]) {
    test('invalid SDK UID length ${uid.length} no storage calls', () async {
      auth.currentUser = sdk.SdkUser(uid);
      await expectLater(gateway.read(), throwsFormatException);
      await expectLater(gateway.save(FirebaseReminderPreferences.defaults), throwsFormatException);
      expect(db.sources, isEmpty); expect(db.sets, 0);
    });
  }
  test('signed out no read/write calls', () async {
    auth.currentUser = null;
    await expectLater(gateway.read(), throwsFormatException);
    await expectLater(gateway.save(FirebaseReminderPreferences.defaults), throwsFormatException);
    expect(db.reads, isEmpty); expect(db.sets, 0);
  });
  for (final missing in [false, true]) {
    for (final kind in ['cache', 'pending', 'path']) {
      test('$kind ${missing ? 'missing' : 'existing'} snapshot denied', () async {
        if (!missing) db.documents[path] = data();
        if (kind == 'cache') db.cached.add(path);
        if (kind == 'pending') db.pending.add(path);
        if (kind == 'path') db.poisonPath = 'users/b/settings/reminders';
        await expectLater(gateway.read(), kind == 'path' ? throwsFormatException : throwsStateError);
        expect(db.writes, isEmpty);
      });
    }
  }
  for (final operation in ['read', 'save']) {
    for (final end in ['switch', 'signout']) {
      test('$operation account changes before storage call fails closed', () async {
        db.onReference = () { auth.currentUser = end == 'switch' ? sdk.SdkUser('b') : null; };
        await expectLater(operation == 'read' ? gateway.read() : gateway.save(FirebaseReminderPreferences.defaults), throwsStateError);
        expect(db.reads, isEmpty); expect(db.sets, 0);
      });
      for (final failure in [false, true]) {
        test('$operation delayed $end ${failure ? 'error' : 'success'} discards result', () async {
          db.documents[path] = data();
          final gate = operation == 'read' ? path : 'set';
          db.gates[gate] = Completer();
          if (failure) db.errors[gate] = StateError('old account transport');
          final request = expectLater(operation == 'read' ? gateway.read() : gateway.save(FirebaseReminderPreferences.defaults), throwsStateError);
          await chat.flush();
          auth.currentUser = end == 'switch' ? sdk.SdkUser('b') : null;
          db.gates[gate]!.complete(); await request;
          expect(db.writes.length, operation == 'save' && !failure ? 1 : 0);
          if (db.writes.isNotEmpty) expect(db.writes.single.path, path); // Cannot undo an already dispatched old-account write.
        });
      }
    }
  }
  test('switch during parsing after get cannot return old preferences', () async {
    db.documents[path] = data(); db.onData = () => auth.currentUser = sdk.SdkUser('b');
    await expectLater(gateway.read(), throwsStateError);
  });
  for (final code in ['permission-denied', 'unavailable']) {
    for (final operation in ['read', 'save']) {
      test('$operation $code no fallback or automatic retry', () async {
        db.documents[path] = data(); db.errors[operation == 'read' ? path : 'set'] = FirebaseException(plugin: 'cloud_firestore', code: code);
        await expectLater(operation == 'read' ? gateway.read() : gateway.save(FirebaseReminderPreferences.defaults), throwsA(isA<FirebaseException>()));
        expect(db.writes, isEmpty); expect(db.reads.length, operation == 'read' ? 1 : 0);
        expect(db.sets, operation == 'save' ? 1 : 0);
      });
    }
  }
}