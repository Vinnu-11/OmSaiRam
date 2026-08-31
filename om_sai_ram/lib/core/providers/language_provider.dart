// Om Sai Ram
// Language state — app UI language and reader content language.

import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAppLangKey = 'app_language';
const _kReaderLangKey = 'reader_language';

/// Supported languages.
enum AppLanguage {
  english('en', 'English', 'English'),
  marathi('mr', 'मराठी', 'Marathi'),
  telugu('te', 'తెలుగు', 'Telugu'),
  hindi('hi', 'हिंदी', 'Hindi'),
  tamil('ta', 'தமிழ்', 'Tamil'),
  urdu('ur', 'اردو', 'Urdu'),
  bengali('bn', 'বাংলা', 'Bengali'),
  sindhi('sd', 'سنڌي', 'Sindhi'),
  spanish('es', 'Español', 'Spanish'),
  gujarati('gu', 'ગુજરાતી', 'Gujarati'),
  malayalam('ml', 'മലയാളം', 'Malayalam'),
  oriya('or', 'ଓଡ଼ିଆ', 'Odia'),
  konkani('kok', 'कोंकणी', 'Konkani'),
  nepali('ne', 'नेपाली', 'Nepali'),
  punjabi('pa', 'ਪੰਜਾਬੀ', 'Punjabi'),
  kannada('kn', 'ಕನ್ನಡ', 'Kannada'),
  deutsch('de', 'Deutsch', 'German'),
  french('fr', 'Français', 'French');

  const AppLanguage(this.code, this.label, this.englishLabel);
  final String code;
  final String label;
  final String englishLabel;

  /// Languages temporarily disabled due to unusable OCR content.
  static const Set<AppLanguage> _disabled = {urdu};

  /// Languages with incomplete or partially garbled OCR content.
  static const Set<AppLanguage> _beta = {
    kannada, malayalam, urdu, bengali, gujarati, oriya, punjabi, tamil,
  };

  /// Whether this language is marked as beta (incomplete content).
  bool get isBeta => _beta.contains(this);

  /// Languages available for selection (excludes disabled ones).
  static List<AppLanguage> get available =>
      values.where((l) => !_disabled.contains(l)).toList();

  static AppLanguage fromCode(String code) =>
      values.firstWhere((l) => l.code == code, orElse: () => english);
}

/// Global language state: app language and (independently) reader language.
class LanguageState {
  final AppLanguage appLanguage;
  final AppLanguage readerLanguage;

  const LanguageState({
    this.appLanguage = AppLanguage.english,
    this.readerLanguage = AppLanguage.english,
  });

  LanguageState copyWith({AppLanguage? appLanguage, AppLanguage? readerLanguage}) {
    return LanguageState(
      appLanguage: appLanguage ?? this.appLanguage,
      readerLanguage: readerLanguage ?? this.readerLanguage,
    );
  }
}

class LanguageNotifier extends StateNotifier<LanguageState> {
  LanguageNotifier() : super(const LanguageState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final appCode = prefs.getString(_kAppLangKey) ?? _deviceLanguageCode();
    final readerCode = prefs.getString(_kReaderLangKey) ?? appCode;
    state = LanguageState(
      appLanguage: AppLanguage.fromCode(appCode),
      readerLanguage: AppLanguage.fromCode(readerCode),
    );
  }

  /// Changes the app UI language and always syncs the reader language to match.
  /// Reader language can be changed independently afterwards via [setReaderLanguage].
  Future<void> setAppLanguage(AppLanguage lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAppLangKey, lang.code);
    await prefs.setString(_kReaderLangKey, lang.code);
    state = LanguageState(appLanguage: lang, readerLanguage: lang);
  }

  /// Changes only the reader content language, independently of app language.
  Future<void> setReaderLanguage(AppLanguage lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kReaderLangKey, lang.code);
    state = state.copyWith(readerLanguage: lang);
  }
}

/// Returns the device locale code if it matches a supported (available) language,
/// otherwise falls back to 'en'.
String _deviceLanguageCode() {
  final locale = ui.PlatformDispatcher.instance.locale;
  final code = locale.languageCode;
  final match = AppLanguage.available.where((l) => l.code == code);
  return match.isNotEmpty ? code : 'en';
}

final languageProvider =
    StateNotifierProvider<LanguageNotifier, LanguageState>(
  (ref) => LanguageNotifier(),
);
