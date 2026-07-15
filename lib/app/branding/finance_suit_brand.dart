import 'package:flutter/material.dart';

/// Finance Suit's local brand contract.
///
/// The values mirror the shared Suit visual language while keeping this app
/// independent from every other product and repository.
class FinanceSuitBrand {
  const FinanceSuitBrand._();

  static const name = 'Finance Suit';
  static const latinFontFamily = 'Manrope';
  static const arabicFontFamily = 'IBM Plex Sans Arabic';
  static const latinFontFallbacks = <String>[
    arabicFontFamily,
    'Inter',
    'Cairo',
    'Tajawal',
  ];
  static const arabicFontFallbacks = <String>[
    latinFontFamily,
    'Cairo',
    'Tajawal',
  ];

  // Navy family.
  static const buildingNavy = Color(0xFF16293B);
  static const deepStructureNavy = Color(0xFF0D1B28);
  static const midnightBackground = Color(0xFF0A111A);
  static const navySurface = Color(0xFF14233A);
  static const navySurfaceRaised = Color(0xFF1B2E47);
  static const steelBorder = Color(0xFF2E3F52);

  // Gold family. Gold remains a restrained action/focus accent.
  static const premiumGold = Color(0xFFD89B42);
  static const highlightGold = Color(0xFFEBB45A);
  static const gold700 = Color(0xFFA86C1C);

  // Light, neutral, and supporting colors.
  static const pearlWhite = Color(0xFFF7F8FA);
  static const softSilver = Color(0xFFE2E5EA);
  static const cloudGray = Color(0xFFCBD2DB);
  static const graphiteText = Color(0xFF232B33);
  static const slateGray = Color(0xFF5A6573);
  static const steelGray = Color(0xFF9AA6B4);
  static const slateBlue = Color(0xFF36506E);
  static const skySteel = Color(0xFF7E97B3);
  static const paleSky = Color(0xFFDCE6F1);

  // Semantic colors. Brand gold never communicates financial status.
  static const success = Color(0xFF2E9E6B);
  static const successBackground = Color(0xFFE4F4EC);
  static const warning = Color(0xFFE1841F);
  static const warningBackground = Color(0xFFFBEEDD);
  static const error = Color(0xFFD14B4B);
  static const errorBackground = Color(0xFFF8E3E3);
  static const info = Color(0xFF2F77C9);
  static const infoBackground = Color(0xFFDCE6F1);

  // Contrast-safe foreground variants for small text on light surfaces.
  static const successForeground = Color(0xFF1B6E3C);
  static const warningForeground = Color(0xFF8A5A00);
  static const errorForeground = Color(0xFFB73636);
  static const infoForeground = Color(0xFF245F9F);

  static const successDark = Color(0xFF46B383);
  static const successBackgroundDark = Color(0xFF18352A);
  static const warningDark = Color(0xFFF09A3C);
  static const warningBackgroundDark = Color(0xFF3A2A14);
  static const errorDark = Color(0xFFE26A6A);
  static const errorBackgroundDark = Color(0xFF3A1E1E);
  static const infoDark = Color(0xFF4F92DD);
  static const infoBackgroundDark = Color(0xFF15263A);
}
