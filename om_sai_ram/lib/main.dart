// Om Sai Ram
// Main entry point for the Om Sai Ram application.
// This app helps devotees organize group readings of the Sai Baba Satcharita.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'register_web_plugins_stub.dart'
    if (dart.library.html) 'register_web_plugins.dart' as web_plugins;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Manually register just_audio_web on web — the auto-generated plugin
  // registrant sometimes fails to take effect in release builds.
  if (kIsWeb) {
    web_plugins.registerJustAudioWeb();
  }
  runApp(
    // ProviderScope wraps the entire app to enable Riverpod state management.
    const ProviderScope(child: OmSaiRamApp()),
  );
}
