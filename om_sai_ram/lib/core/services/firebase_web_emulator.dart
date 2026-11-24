import 'dart:js_interop';

@JS('window.location.hostname')
external JSString get _hostname;

@JS('window.sessionStorage.setItem')
external void _setSessionItem(JSString key, JSString value);

/// firebase_auth_web 6.3.0 awaits restored Auth during initializeApp, before
/// Dart can call useAuthEmulator. Its localhost/debug startup hook consumes
/// this endpoint-only key. Seed it first to prevent a restored user reaching
/// cloud Auth or being discarded before the emulator is attached.
/// No identity, password or token is read/written by this helper.
void prepareWebAuthEmulator(String appName, String host, int port) {
  if (_hostname.toDart != 'localhost') {
    throw const FormatException(
      'Open web Firebase debug mode at http://localhost (not 127.0.0.1 or a remote origin). The current FlutterFire web emulator restoration hook requires localhost. FIREBASE_EMULATOR_HOST can remain 127.0.0.1. Cloud fallback is not supported.',
    );
  }
  _setSessionItem(
      '$appName-firebaseEmulatorOrigin'.toJS, 'http://$host:$port'.toJS);
}
