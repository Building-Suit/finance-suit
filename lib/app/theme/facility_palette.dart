import 'package:flutter/material.dart';
import 'package:work_tracker/app/theme/building_suit_colors.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';

/// The colours a credit card or BNPL facility may be painted with.
///
/// A fixed set drawn from the canonical palette rather than a free colour
/// wheel: each entry is a design-system role dark enough to carry white
/// text, so a user-chosen colour can never make a card's figures
/// unreadable, and the set still spans the colours physical cards come in.
///
/// The chosen colour is persisted as `#RRGGBB`, which keeps the stored value
/// readable and stable even if this list is later reordered.
abstract final class FacilitySwatches {
  static const values = <Color>[
    BuildingSuitColors.brandBuildingNavy,
    BuildingSuitColors.secondarySlateBlue,
    BuildingSuitColors.functionalLightInfoText,
    BuildingSuitColors.functionalLightSuccessText,
    BuildingSuitColors.functionalLightWarningText,
    BuildingSuitColors.functionalLightErrorText,
    BuildingSuitColors.neutralGraphite,
    BuildingSuitColors.neutral950,
  ];

  /// White or near-black, whichever reads on [swatch].
  static Color foregroundOn(Color swatch) =>
      ThemeData.estimateBrightnessForColor(swatch) == Brightness.dark
      ? BuildingSuitColors.neutral0
      : BuildingSuitColors.neutralGraphite;

  /// The `#RRGGBB` form stored for [color].
  static String hexOf(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  /// Parses a stored value; null for absent or malformed input, so a bad row
  /// degrades to the default look instead of crashing.
  static Color? parse(String? hex) {
    final value = hex?.trim().toUpperCase();
    if (value == null || !RegExp(r'^#[0-9A-F]{6}$').hasMatch(value)) {
      return null;
    }
    return Color(int.parse(value.substring(1), radix: 16) + 0xFF000000);
  }
}

/// The readable foreground for anything painted directly on [swatch].
Color onFacilitySwatch(Color swatch) => FacilitySwatches.foregroundOn(swatch);

/// The resolved colours one facility renders with.
@immutable
class FacilityPalette {
  const FacilityPalette({
    required this.surface,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.isCustom,
  });

  final Color surface;
  final Color onSurface;

  /// Secondary text on [surface] — same hue, reduced emphasis.
  final Color onSurfaceMuted;

  /// Whether the user picked this colour, as opposed to the brand default.
  final bool isCustom;
}

/// Resolves the palette for a facility colour. Without a colour the result is
/// the brand surface the cards have always used, so existing cards are
/// untouched. With one, the foreground flips to white or near-black by the
/// colour's luminance so text stays legible on any swatch, in either theme.
FacilityPalette facilityPalette(BuildContext context, String? colorHex) {
  final colors = context.suitColors;
  final custom = FacilitySwatches.parse(colorHex);
  if (custom == null) {
    return FacilityPalette(
      surface: colors.brandSurface,
      onSurface: colors.onBrandSurface,
      onSurfaceMuted: colors.onBrandSurface.withValues(alpha: 0.75),
      isCustom: false,
    );
  }
  final onSurface = FacilitySwatches.foregroundOn(custom);
  return FacilityPalette(
    surface: custom,
    onSurface: onSurface,
    onSurfaceMuted: onSurface.withValues(alpha: 0.75),
    isCustom: true,
  );
}
