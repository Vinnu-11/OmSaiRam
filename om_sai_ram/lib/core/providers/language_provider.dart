// Om Sai Ram
// Language state — app UI language and reader content language.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAppLangKey = 'app_language';
const _kReaderLangKey = 'reader_language';

/// Supported languages.
enum AppLanguage {
  english('en', 'English'),
  marathi('mr', 'मराठी'),
  telugu('te', 'తెలుగు'),
  hindi('hi', 'हिंदी'),
  tamil('ta', 'தமிழ்'),
  urdu('ur', 'اردو'),
  bengali('bn', 'বাংলা'),
  sindhi('sd', 'سنڌي'),
  spanish('es', 'Español'),
  gujarati('gu', 'ગુજરાતી'),
  malayalam('ml', 'മലയാളം'),
  oriya('or', 'ଓଡ଼ିଆ'),
  konkani('kok', 'कोंकणी'),
  nepali('ne', 'नेपाली'),
  punjabi('pa', 'ਪੰਜਾਬੀ'),
  kannada('kn', 'ಕನ್ನಡ'),
  deutsch('de', 'Deutsch'),
  french('fr', 'Français');

  const AppLanguage(this.code, this.label);
  final String code;
  final String label;

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
    final appCode = prefs.getString(_kAppLangKey) ?? 'en';
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

final languageProvider =
    StateNotifierProvider<LanguageNotifier, LanguageState>(
  (ref) => LanguageNotifier(),
);
