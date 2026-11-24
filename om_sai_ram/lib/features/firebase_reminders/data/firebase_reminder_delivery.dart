import 'dart:convert';
import 'firebase_reminder_planner.dart';

abstract class FirebaseNotificationDriver {
  Future<bool> requestPermission();
  Future<bool> permissionGranted();
  Future<List<int>> pendingIds();
  Future<void> cancel(int id);
  Future<void> schedule(FirebaseReminderItem item);
}

abstract class FirebaseNotificationJournal {
  Future<String?> read();
  Future<void> write(String value);
}

class FirebaseReminderDelivery {
  final FirebaseNotificationDriver driver;
  final FirebaseNotificationJournal journal;
  final String? Function() currentUid;
  Future<void> _tail = Future.value();
  int _generation = 0;
  FirebaseReminderDelivery(this.driver, this.journal, this.currentUid);

  bool _owned(int id) => id >= 0x40000000 && id <= 0x7fffffff;
  void _current(String uid, int generation) {
    if (_generation != generation || currentUid() != uid) {
      throw StateError('Notification account/session changed.');
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  List<int> _journalIds(String? raw) {
    if (raw == null) return [];
    final value = jsonDecode(raw);
    if (value is! Map ||
        value.length != 3 ||
        value['version'] != 1 ||
        value['uid'] is! String ||
        value['ids'] is! List ||
        (value['ids'] as List).length > 128) {
      throw const FormatException('Invalid notification journal.');
    }
    final ids = value['ids'] as List;
    if (ids.any((id) => id is! int || !_owned(id)) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid journal notification IDs.');
    }
    return ids.cast<int>();
  }

  Future<void> _write(String uid, Iterable<int> ids) => journal
      .write(jsonEncode({'version': 1, 'uid': uid, 'ids': ids.toList()}));
  Future<void> _clear() async {
    final pending = await driver.pendingIds();
    List<int> recorded;
    try {
      recorded = _journalIds(await journal.read());
    } on FormatException {
      recorded = [];
    }
    final ids = {...recorded, ...pending.where(_owned)};
    for (final id in ids) {
      await driver.cancel(id);
    }
    await _write('', []);
  }

  Future<void> invalidate() {
    ++_generation;
    return _serial(_clear);
  }

  Future<void> apply(String uid, FirebaseReminderPlan plan,
      {required bool requestPermission}) {
    final generation = _generation;
    return _serial(() async {
      _current(uid, generation);
      if (plan.items.length > firebaseReminderQueueLimit ||
          plan.items.any((item) => item.uid != uid)) {
        throw const FormatException(
            'Only a bounded own-account plan may be delivered.');
      }
      try {
        if (!(requestPermission
            ? await driver.requestPermission()
            : await driver.permissionGranted())) {
          throw StateError('Notification permission was not granted.');
        }
        _current(uid, generation);
        await _clear();
        _current(uid, generation);
        await _write(uid, plan.items.map((item) => item.id));
        _current(uid, generation);
        for (final item in plan.items) {
          _current(uid, generation);
          await driver.schedule(item);
          _current(uid, generation);
        }
      } catch (_) {
        await _clear();
        rethrow;
      }
    });
  }
}
