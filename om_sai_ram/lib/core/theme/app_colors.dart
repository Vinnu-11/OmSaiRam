// Om Sai Ram
// App color palette — warm saffron tones inspired by spiritual traditions.

import 'package:flutter/material.dart';

/// Color constants used throughout the app.
///
/// The palette centers on saffron (sacred color in Hindu tradition)
/// with neutral whites and greys for a clean, minimalist feel.
class AppColors {
  AppColors._();

  // "Temple at dawn" palette used by the theme.
  /// Kumkum red: buttons and links. 9:1 against white.
  static const Color kumkum = Color(0xFF8C1D18);
  /// Kesari (saffron) accent for icons and highlights; pair with dark text.
  static const Color kesari = Color(0xFFD9620F);
  /// Marigold: the diya flame and small decorative marks only.
  static const Color marigold = Color(0xFFF2A900);
  /// Sandalwood page background and its border tone.
  static const Color sandal = Color(0xFFFBF3E4);
  static const Color sandalOutline = Color(0xFFD9C4A5);
  /// Text colours on light surfaces.
  static const Color ink = Color(0xFF2B1A12);
  static const Color inkMuted = Color(0xFF5C4A3F);

  // Primary colors
  static const Color saffron = Color(0xFFFF7722);
  static const Color deepOrange = Color(0xFFE65100);
  static const Color lightSaffron = Color(0xFFFFAB66);

  // Backgrounds
  static const Color white = Color(0xFFFFFFFF);
  static const Color cream = Color(0xFFFFF8F0);
  static const Color lightGrey = Color(0xFFE8E8E8);

  // Text colors
  static const Color darkText = Color(0xFF1A1A2E);
  static const Color mediumText = Color(0xFF4A4A5A);
  static const Color lightText = Color(0xFF9A9AAA);

  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);

  // Progress colors
  static const Color progressComplete = Color(0xFF4CAF50);
  static const Color progressInProgress = Color(0xFFFF7722);
  static const Color progressNotStarted = Color(0xFFE0E0E0);
}
