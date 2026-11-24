// Om Sai Sannidhi
// Application theme: "Temple at dawn". Built for readers aged 40 to 90:
// large type, strong contrast and generous touch targets everywhere.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        primary: AppColors.kumkum,
        onPrimary: AppColors.white,
        accent: AppColors.kesari,
        background: AppColors.sandal,
        surface: AppColors.white,
        text: AppColors.ink,
        muted: AppColors.inkMuted,
        outline: AppColors.sandalOutline,
      );

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        primary: const Color(0xFFFFC078),
        onPrimary: AppColors.ink,
        accent: AppColors.marigold,
        background: const Color(0xFF1A1208),
        surface: const Color(0xFF2A1F10),
        text: const Color(0xFFF6E7C8),
        muted: const Color(0xFFCDB894),
        outline: const Color(0xFF5A4526),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color accent,
    required Color background,
    required Color surface,
    required Color text,
    required Color muted,
    required Color outline,
  }) {
    // Mukta is drawn for Devanagari and Latin together, so Hindi and Marathi
    // sit at the same visual size as English.
    TextStyle type(double size, FontWeight weight, Color color, {double? height}) =>
        GoogleFonts.mukta(fontSize: size, fontWeight: weight, color: color, height: height);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonSize = Size(64, 56);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
    final buttonText = type(18, FontWeight.w700, primary);
    OutlineInputBorder field(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width));
    final scheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: AppColors.kumkum,
      primary: primary,
      onPrimary: onPrimary,
      secondary: accent,
      onSecondary: AppColors.ink,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: outline,
      error: brightness == Brightness.light ? const Color(0xFFB3261E) : const Color(0xFFFFB4AB),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        displayLarge: type(34, FontWeight.w800, text, height: 1.2),
        displayMedium: type(30, FontWeight.w700, text, height: 1.2),
        headlineMedium: type(26, FontWeight.w700, text, height: 1.25),
        headlineSmall: type(24, FontWeight.w700, text, height: 1.25),
        titleLarge: type(22, FontWeight.w700, text, height: 1.3),
        titleMedium: type(19, FontWeight.w600, text, height: 1.35),
        titleSmall: type(17, FontWeight.w600, muted, height: 1.35),
        bodyLarge: type(18, FontWeight.w400, text, height: 1.5),
        bodyMedium: type(17, FontWeight.w400, text, height: 1.5),
        bodySmall: type(16, FontWeight.w400, muted, height: 1.45),
        labelLarge: type(18, FontWeight.w700, text),
        labelMedium: type(16, FontWeight.w600, muted),
        labelSmall: type(15, FontWeight.w600, muted),
      ),
      iconTheme: IconThemeData(color: primary, size: 28),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        toolbarHeight: 64,
        iconTheme: IconThemeData(color: text, size: 28),
        titleTextStyle: type(22, FontWeight.w700, text),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: surface,
          side: BorderSide(color: primary, width: 1.5),
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: shape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: type(17, FontWeight.w700, primary),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48), iconSize: 28),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: field(outline, 1.5),
        enabledBorder: field(outline, 1.5),
        focusedBorder: field(primary, 2.5),
        errorBorder: field(scheme.error, 1.5),
        focusedErrorBorder: field(scheme.error, 2.5),
        labelStyle: type(17, FontWeight.w500, muted),
        floatingLabelStyle: type(17, FontWeight.w700, primary),
        hintStyle: type(17, FontWeight.w400, muted),
        helperStyle: type(15, FontWeight.w400, muted),
        errorStyle: type(15, FontWeight.w600, scheme.error),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: outline)),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        minVerticalPadding: 12,
        titleTextStyle: type(18, FontWeight.w600, text, height: 1.35),
        subtitleTextStyle: type(16, FontWeight.w400, muted, height: 1.4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: type(22, FontWeight.w700, text, height: 1.3),
        contentTextStyle: type(18, FontWeight.w400, text, height: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: type(17, FontWeight.w500, AppColors.white, height: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
          color: accent, linearTrackColor: outline, linearMinHeight: 6),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: type(14, FontWeight.w700, primary),
        unselectedLabelStyle: type(14, FontWeight.w500, muted),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 24),
    );
  }
}
