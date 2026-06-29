// Om Sai Ram
// Main entry point for the Om Sai Ram application.
// This app helps devotees organize group readings of the Sai Baba Satcharita.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    // ProviderScope wraps the entire app to enable Riverpod state management.
    const ProviderScope(child: OmSaiRamApp()),
  );
}
