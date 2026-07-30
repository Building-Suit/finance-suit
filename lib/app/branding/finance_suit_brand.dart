import 'package:work_tracker/app/theme/building_suit_colors.dart';

/// Finance Suit's local brand contract.
///
/// Product identity and immutable logo-artwork aliases.
///
/// Product UI colors belong to the semantic theme adapter, not this class.
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

  // These aliases preserve the official Finance Suit mark unchanged.
  static const buildingNavy = BuildingSuitColors.brandBuildingNavy;
  static const pearlWhite = BuildingSuitColors.roleLightBackground;
  static const premiumGold = BuildingSuitColors.brandPremiumGold;
}
