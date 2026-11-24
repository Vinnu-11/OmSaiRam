// SDK-shaped doubles only: not live Auth transport or emulator verification.
// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:om_sai_ram/features/firebase_account/data/firebase_password_gateway.dart';

class PasswordProviderInfo extends Fake implements UserInfo {
  @override
  final String providerId;
  PasswordProviderInfo(this.providerId);
}

class PasswordCredential extends Fake implements UserCredential {
  @override
  final User? user;
  PasswordCredential(this.user);
}

class PasswordUser extends Fake implements User {
  @override
  final String uid;
  @override
  String? email = 'sdk-current@example.com';
  @override
  bool isAnonymous = false;
  @override
  List<UserInfo> providerData = [PasswordProviderInfo('password')];
  final events = <String>[];
  Completer<void>? reauthGate, updateGate;
  Object? reauthError, updateError;
  UserCredential? returned;
  void Function()? duringReauth, duringUpdate;
  PasswordUser([this.uid = 'a']);
  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential credential) async {
    events.add('reauth');
    expect(credential, isA<EmailAuthCredential>());
    final passwordCredential = credential as EmailAuthCredential;
    expect(passwordCredential.providerId, 'password');
    expect(passwordCredential.email, email);
    // Boolean assertions avoid printing credentials/passwords on failure.
    expect(passwordCredential.password == ' current ', isTrue);
    duringReauth?.call();
    await reauthGate?.future;
    if (reauthError != null) throw reauthError!;
    return returned ?? PasswordCredential(this);
  }
  @override
  Future<void> updatePassword(String newPassword) async {
    events.add('update');
    expect(newPassword == ' next password ', isTrue);
    duringUpdate?.call();
    await updateGate?.future;
    if (updateError != null) throw updateError!;
    events.add('ack');
  }
}

class PasswordAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast(sync: true);
  void Function()? onListen;
  PasswordAuth(this.currentUser);
  void emit(User? user) { currentUser = user; changes.add(user); }
  @override
  Stream<User?> authStateChanges() {
    onListen?.call();
    return changes.stream;
  }
}

Future<void> flushPassword() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const currentSecret = ' current ', nextSecret = ' next password ';
  late PasswordUser user;
  late PasswordAuth auth;
  late SdkFirebasePasswordGateway gateway;
  setUp(() {
    user = PasswordUser(); auth = PasswordAuth(user);
    gateway = SdkFirebasePasswordGateway(auth);
  });
  tearDown(() => auth.changes.close());
  Future<void> change() => gateway.change(' current ', ' next password ', ' next password ');
  final safeFailure = throwsA(isA<FirebasePasswordFailure>());

  test('SDK current-account metadata only; exact reauth then same captured user update then ACK', () async {
    expect(gateway.identity.uid, 'a'); expect(gateway.identity.eligible, isTrue);
    await change(); expect(user.events, ['reauth', 'update', 'ack']);
    expect(auth.currentUser, same(user));
  });
  for (final kind in ['signed-out', 'anonymous', 'email-null', 'email-blank', 'no-provider', 'other-provider', 'empty-uid']) {
    test('$kind is ineligible before any authentication mutation', () async {
      switch (kind) {
        case 'signed-out': auth.currentUser = null;
        case 'anonymous': user.isAnonymous = true;
        case 'email-null': user.email = null;
        case 'email-blank': user.email = '  ';
        case 'no-provider': user.providerData = [];
        case 'other-provider': user.providerData = [PasswordProviderInfo('google.com')];
        case 'empty-uid': auth.currentUser = PasswordUser('');
      }
      expect(gateway.identity.eligible, isFalse);
      expect(gateway.identity.unavailable, isNotEmpty);
      await expectLater(change(), safeFailure);
      expect(user.events, isEmpty);
    });
  }
  test('linked password provider works even when not first; exact SDK email not caller metadata', () async {
    user.providerData.insert(0, PasswordProviderInfo('google.com'));
    user.email = 'SDK-Case@example.com';
    await change(); expect(user.events, ['reauth', 'update', 'ack']);
  });
  for (final invalid in [('', '123456', '123456'), ('x', '12345', '12345'), ('x', '123456', 'different')]) {
    test('validation ${invalid.$1.length}/${invalid.$2.length}/${invalid.$3.length} before any I/O', () async {
      await expectLater(gateway.change(invalid.$1, invalid.$2, invalid.$3), safeFailure);
      expect(user.events, isEmpty);
    });
  }
  test('validation counts untrimmed characters and recommends, not mandates, different new password', () {
    expect(validatePasswordChange(' ', '      ', '      '), isNull);
    expect(validatePasswordChange('123456', '123456', '123456'), isNull);
  });
  test('switch before reauth dispatch rejected', () async {
    auth.onListen = () => auth.currentUser = PasswordUser('b');
    await expectLater(change(), safeFailure); expect(user.events, isEmpty);
  });
  test('reauth SDK replaces wrapper/platform user with same UID legitimately; captured user is updated', () async {
    final replacement = PasswordUser();
    user.duringReauth = () => auth.emit(replacement);
    user.returned = PasswordCredential(replacement);
    await change(); expect(user.events, ['reauth', 'update', 'ack']);
    expect(replacement.events, isEmpty);
  });
  for (final result in ['different-uid', 'null']) {
    test('returned credential $result cannot authorize an update', () async {
      user.returned = PasswordCredential(result == 'null' ? null : PasswordUser('b'));
      await expectLater(change(), safeFailure); expect(user.events, ['reauth']);
    });
  }
  for (final end in ['switch', 'signout', 'away-and-back']) {
    for (final failure in [false, true]) {
      test('pending reauth $end ${failure ? 'failure' : 'success'} rejects result before update', () async {
        user.reauthGate = Completer();
        if (failure) user.reauthError = FirebaseAuthException(code: 'wrong-password', message: 'sensitive SDK detail');
        final request = expectLater(change(), safeFailure);
        await flushPassword();
        auth.emit(end == 'signout' ? null : PasswordUser('b'));
        if (end == 'away-and-back') auth.emit(user);
        user.reauthGate!.complete(); await request;
        expect(user.events, ['reauth']);
      });
    }
  }
  test('credential result validation can switch account: check again between reauth and update', () async {
    user.returned = SwitchingCredential(user, () => auth.currentUser = PasswordUser('b'));
    await expectLater(change(), safeFailure); expect(user.events, ['reauth']);
  });
  for (final code in ['wrong-password', 'invalid-credential', 'weak-password', 'requires-recent-login', 'network-request-failed', 'too-many-requests', 'user-disabled', 'internal-error']) {
    test('reauth $code is safe known-no-update, with explicit retry possible', () async {
      user.reauthError = FirebaseAuthException(code: code, message: 'sensitive SDK detail: current=$currentSecret next=$nextSecret');
      FirebasePasswordFailure? failure;
      try { await change(); } on FirebasePasswordFailure catch (error) { failure = error; }
      expect(failure, isNotNull); expect(failure!.uncertain, isFalse);
      expect(failure.toString().contains('sensitive'), isFalse);
      expect(failure.message.contains(currentSecret) || failure.message.contains(nextSecret), isFalse);
      if (code == 'wrong-password' || code == 'invalid-credential') {
        expect(failure.message, 'Current password is incorrect.');
      }
      expect(user.events, ['reauth']);
      user.reauthError = null; await change();
      expect(user.events, ['reauth', 'reauth', 'update', 'ack']);
    });
  }
  for (final code in ['weak-password', 'requires-recent-login', 'network-request-failed', 'too-many-requests', 'user-disabled', 'internal-error', 'unknown']) {
    test('update $code after dispatch is uncertain and never auto retried', () async {
      user.updateError = code == 'unknown' ? StateError('sensitive SDK detail') :
          FirebaseAuthException(code: code, message: 'sensitive SDK detail: current=$currentSecret next=$nextSecret');
      FirebasePasswordFailure? failure;
      try { await change(); } on FirebasePasswordFailure catch (error) { failure = error; }
      expect(failure, isNotNull); expect(failure!.uncertain, isTrue);
      expect(failure.message, contains('Do not retry here'));
      expect(failure.toString().contains('sensitive'), isFalse);
      expect(failure.message.contains(currentSecret) || failure.message.contains(nextSecret), isFalse);
      expect(user.events, ['reauth', 'update']);
    });
  }
  for (final end in ['switch', 'signout']) {
    for (final failure in [false, true]) {
      test('update already dispatched $end ${failure ? 'error' : 'ACK'} discards success, cannot roll back', () async {
        user.updateGate = Completer();
        if (failure) user.updateError = StateError('sensitive SDK detail');
        final request = expectLater(change(), throwsA(isA<FirebasePasswordFailure>()
            .having((e) => e.uncertain, 'uncertain', isTrue)
            .having((e) => e.message, 'message', passwordAccountChanged)));
        await flushPassword(); auth.emit(end == 'switch' ? PasswordUser('b') : null);
        user.updateGate!.complete(); await request;
        expect(user.events, failure ? ['reauth', 'update'] : ['reauth', 'update', 'ack']);
      });
    }
  }
  test('separate injected Auth instances never use another account or default instance', () async {
    final other = PasswordUser('b'); final otherAuth = PasswordAuth(other);
    await SdkFirebasePasswordGateway(otherAuth).change(' current ', ' next password ', ' next password ');
    expect(user.events, isEmpty); expect(other.events, ['reauth', 'update', 'ack']);
    await otherAuth.changes.close();
  });
}

class SwitchingCredential extends Fake implements UserCredential {
  final User value;
  final void Function() switchAccount;
  SwitchingCredential(this.value, this.switchAccount);
  @override
  User get user { switchAccount(); return value; }
}