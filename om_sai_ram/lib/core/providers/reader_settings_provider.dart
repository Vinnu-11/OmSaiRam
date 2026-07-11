// Om Sai Ram
// Reader settings — font size and theme mode preferences.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFontSizeKey = 'reader_font_size';
const _kDarkModeKey = 'dark_mode';

const double minFontSize = 14.0;
const double maxFontSize = 26.0;
const double defaultFontSize = 17.0;

class ReaderSettings {
  final double fontSize;
  final bool darkMode;

  const ReaderSettings({
    this.fontSize = defaultFontSize,
    this.darkMode = false,
  });

  ReaderSettings copyWith({double? fontSize, bool? darkMode}) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      darkMode: darkMode ?? this.darkMode,
    );
  }
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier() : super(const ReaderSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReaderSettings(
      fontSize: prefs.getDouble(_kFontSizeKey) ?? defaultFontSize,
      darkMode: prefs.getBool(_kDarkModeKey) ?? false,
    );
  }

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(minFontSize, maxFontSize);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontSizeKey, clamped);
    state = state.copyWith(fontSize: clamped);
  }

  Future<void> increaseFontSize() => setFontSize(state.fontSize + 1);
  Future<void> decreaseFontSize() => setFontSize(state.fontSize - 1);

  Future<void> toggleDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final next = !state.darkMode;
    await prefs.setBool(_kDarkModeKey, next);
    state = state.copyWith(darkMode: next);
  }
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  (ref) => ReaderSettingsNotifier(),
);

/// Convenience provider for ThemeMode to wire into MaterialApp.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final dark = ref.watch(readerSettingsProvider).darkMode;
  return dark ? ThemeMode.dark : ThemeMode.light;
});
