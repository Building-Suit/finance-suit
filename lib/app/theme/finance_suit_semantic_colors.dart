import 'package:flutter/material.dart';
import 'package:work_tracker/app/theme/building_suit_colors.dart';

@immutable
class FinanceSuitStatusColors {
  const FinanceSuitStatusColors({
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
    required this.text,
    required this.textOnSolid,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final Color icon;
  final Color text;
  final Color textOnSolid;

  FinanceSuitStatusColors lerp(FinanceSuitStatusColors other, double t) =>
      FinanceSuitStatusColors(
        foreground: Color.lerp(foreground, other.foreground, t)!,
        background: Color.lerp(background, other.background, t)!,
        border: Color.lerp(border, other.border, t)!,
        icon: Color.lerp(icon, other.icon, t)!,
        text: Color.lerp(text, other.text, t)!,
        textOnSolid: Color.lerp(textOnSolid, other.textOnSolid, t)!,
      );
}

/// Finance Suit's semantic adapter over the canonical Building Suit snapshot.
///
/// Widgets consume this extension for roles Material's [ColorScheme] does not
/// name explicitly, such as focus, interaction, status, chart, and skeleton
/// colors. Raw palette tokens remain confined to the theme layer.
@immutable
class FinanceSuitSemanticColors
    extends ThemeExtension<FinanceSuitSemanticColors> {
  const FinanceSuitSemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.overlay,
    required this.inverseSurface,
    required this.textPrimary,
    required this.textMuted,
    required this.textSubtle,
    required this.textDisabled,
    required this.borderSubtle,
    required this.borderStrong,
    required this.divider,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.link,
    required this.focusRing,
    required this.focusGlow,
    required this.brandSurface,
    required this.onBrandSurface,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.selectedOverlay,
    required this.disabledOverlay,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.chartSeries,
    required this.chartGrid,
    required this.chartAxis,
    required this.chartLabel,
    required this.chartTooltipBackground,
    required this.chartTooltipText,
    required this.chartPositive,
    required this.chartNegative,
    required this.chartNeutral,
    required this.chartSelection,
  });

  factory FinanceSuitSemanticColors.light() => const FinanceSuitSemanticColors(
    background: BuildingSuitColors.roleLightBackground,
    surface: BuildingSuitColors.roleLightSurface,
    surfaceContainer: BuildingSuitColors.roleLightSurfaceContainer,
    surfaceMuted: BuildingSuitColors.roleLightSurfaceMuted,
    surfaceRaised: BuildingSuitColors.roleLightSurfaceRaised,
    overlay: BuildingSuitColors.roleLightSurfaceOverlay,
    inverseSurface: BuildingSuitColors.roleLightSurfaceInverse,
    textPrimary: BuildingSuitColors.roleLightText,
    textMuted: BuildingSuitColors.roleLightTextMuted,
    textSubtle: BuildingSuitColors.roleLightTextSubtle,
    textDisabled: BuildingSuitColors.roleLightTextDisabled,
    borderSubtle: BuildingSuitColors.roleLightBorder,
    borderStrong: BuildingSuitColors.roleLightBorderStrong,
    divider: BuildingSuitColors.roleLightDivider,
    primary: BuildingSuitColors.roleLightPrimary,
    onPrimary: BuildingSuitColors.roleLightTextOnPrimary,
    accent: BuildingSuitColors.roleLightAccent,
    onAccent: BuildingSuitColors.roleLightTextOnAccent,
    link: BuildingSuitColors.roleLightLink,
    focusRing: BuildingSuitColors.roleLightFocusRing,
    focusGlow: BuildingSuitColors.roleLightFocusGlow,
    brandSurface: BuildingSuitColors.roleLightBrandSurface,
    onBrandSurface: BuildingSuitColors.brandContextOnSurface,
    hoverOverlay: BuildingSuitColors.roleLightHoverOverlay,
    pressedOverlay: BuildingSuitColors.roleLightPressedOverlay,
    selectedOverlay: BuildingSuitColors.roleLightSelectedOverlay,
    disabledOverlay: BuildingSuitColors.roleLightDisabledOverlay,
    skeletonBase: BuildingSuitColors.roleLightSkeletonBase,
    skeletonHighlight: BuildingSuitColors.roleLightSkeletonHighlight,
    success: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalLightSuccessForeground,
      background: BuildingSuitColors.functionalLightSuccessBackground,
      border: BuildingSuitColors.functionalLightSuccessBorder,
      icon: BuildingSuitColors.functionalLightSuccessIcon,
      text: BuildingSuitColors.functionalLightSuccessText,
      textOnSolid: BuildingSuitColors.functionalLightSuccessTextOnSolid,
    ),
    warning: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalLightWarningForeground,
      background: BuildingSuitColors.functionalLightWarningBackground,
      border: BuildingSuitColors.functionalLightWarningBorder,
      icon: BuildingSuitColors.functionalLightWarningIcon,
      text: BuildingSuitColors.functionalLightWarningText,
      textOnSolid: BuildingSuitColors.functionalLightWarningTextOnSolid,
    ),
    error: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalLightErrorForeground,
      background: BuildingSuitColors.functionalLightErrorBackground,
      border: BuildingSuitColors.functionalLightErrorBorder,
      icon: BuildingSuitColors.functionalLightErrorIcon,
      text: BuildingSuitColors.functionalLightErrorText,
      textOnSolid: BuildingSuitColors.functionalLightErrorTextOnSolid,
    ),
    info: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalLightInfoForeground,
      background: BuildingSuitColors.functionalLightInfoBackground,
      border: BuildingSuitColors.functionalLightInfoBorder,
      icon: BuildingSuitColors.functionalLightInfoIcon,
      text: BuildingSuitColors.functionalLightInfoText,
      textOnSolid: BuildingSuitColors.functionalLightInfoTextOnSolid,
    ),
    chartSeries: [
      BuildingSuitColors.categoricalLight1,
      BuildingSuitColors.categoricalLight2,
      BuildingSuitColors.categoricalLight3,
      BuildingSuitColors.categoricalLight4,
      BuildingSuitColors.categoricalLight5,
      BuildingSuitColors.categoricalLight6,
    ],
    chartGrid: BuildingSuitColors.roleLightChartGrid,
    chartAxis: BuildingSuitColors.roleLightChartAxis,
    chartLabel: BuildingSuitColors.roleLightChartLabel,
    chartTooltipBackground: BuildingSuitColors.roleLightChartTooltipBackground,
    chartTooltipText: BuildingSuitColors.roleLightChartTooltipText,
    chartPositive: BuildingSuitColors.roleLightChartPositive,
    chartNegative: BuildingSuitColors.roleLightChartNegative,
    chartNeutral: BuildingSuitColors.roleLightChartNeutral,
    chartSelection: BuildingSuitColors.roleLightChartSelection,
  );

  factory FinanceSuitSemanticColors.dark() => const FinanceSuitSemanticColors(
    background: BuildingSuitColors.roleDarkBackground,
    surface: BuildingSuitColors.roleDarkSurface,
    surfaceContainer: BuildingSuitColors.roleDarkSurfaceContainer,
    surfaceMuted: BuildingSuitColors.roleDarkSurfaceMuted,
    surfaceRaised: BuildingSuitColors.roleDarkSurfaceRaised,
    overlay: BuildingSuitColors.roleDarkSurfaceOverlay,
    inverseSurface: BuildingSuitColors.roleDarkSurfaceInverse,
    textPrimary: BuildingSuitColors.roleDarkText,
    textMuted: BuildingSuitColors.roleDarkTextMuted,
    textSubtle: BuildingSuitColors.roleDarkTextSubtle,
    textDisabled: BuildingSuitColors.roleDarkTextDisabled,
    borderSubtle: BuildingSuitColors.roleDarkBorder,
    borderStrong: BuildingSuitColors.roleDarkBorderStrong,
    divider: BuildingSuitColors.roleDarkDivider,
    primary: BuildingSuitColors.roleDarkPrimary,
    onPrimary: BuildingSuitColors.roleDarkTextOnPrimary,
    accent: BuildingSuitColors.roleDarkAccent,
    onAccent: BuildingSuitColors.roleDarkTextOnAccent,
    link: BuildingSuitColors.roleDarkLink,
    focusRing: BuildingSuitColors.roleDarkFocusRing,
    focusGlow: BuildingSuitColors.roleDarkFocusGlow,
    brandSurface: BuildingSuitColors.roleDarkBrandSurface,
    onBrandSurface: BuildingSuitColors.brandContextOnSurface,
    hoverOverlay: BuildingSuitColors.roleDarkHoverOverlay,
    pressedOverlay: BuildingSuitColors.roleDarkPressedOverlay,
    selectedOverlay: BuildingSuitColors.roleDarkSelectedOverlay,
    disabledOverlay: BuildingSuitColors.roleDarkDisabledOverlay,
    skeletonBase: BuildingSuitColors.roleDarkSkeletonBase,
    skeletonHighlight: BuildingSuitColors.roleDarkSkeletonHighlight,
    success: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalDarkSuccessForeground,
      background: BuildingSuitColors.functionalDarkSuccessBackground,
      border: BuildingSuitColors.functionalDarkSuccessBorder,
      icon: BuildingSuitColors.functionalDarkSuccessIcon,
      text: BuildingSuitColors.functionalDarkSuccessText,
      textOnSolid: BuildingSuitColors.functionalDarkSuccessTextOnSolid,
    ),
    warning: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalDarkWarningForeground,
      background: BuildingSuitColors.functionalDarkWarningBackground,
      border: BuildingSuitColors.functionalDarkWarningBorder,
      icon: BuildingSuitColors.functionalDarkWarningIcon,
      text: BuildingSuitColors.functionalDarkWarningText,
      textOnSolid: BuildingSuitColors.functionalDarkWarningTextOnSolid,
    ),
    error: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalDarkErrorForeground,
      background: BuildingSuitColors.functionalDarkErrorBackground,
      border: BuildingSuitColors.functionalDarkErrorBorder,
      icon: BuildingSuitColors.functionalDarkErrorIcon,
      text: BuildingSuitColors.functionalDarkErrorText,
      textOnSolid: BuildingSuitColors.functionalDarkErrorTextOnSolid,
    ),
    info: FinanceSuitStatusColors(
      foreground: BuildingSuitColors.functionalDarkInfoForeground,
      background: BuildingSuitColors.functionalDarkInfoBackground,
      border: BuildingSuitColors.functionalDarkInfoBorder,
      icon: BuildingSuitColors.functionalDarkInfoIcon,
      text: BuildingSuitColors.functionalDarkInfoText,
      textOnSolid: BuildingSuitColors.functionalDarkInfoTextOnSolid,
    ),
    chartSeries: [
      BuildingSuitColors.categoricalDark1,
      BuildingSuitColors.categoricalDark2,
      BuildingSuitColors.categoricalDark3,
      BuildingSuitColors.categoricalDark4,
      BuildingSuitColors.categoricalDark5,
      BuildingSuitColors.categoricalDark6,
    ],
    chartGrid: BuildingSuitColors.roleDarkChartGrid,
    chartAxis: BuildingSuitColors.roleDarkChartAxis,
    chartLabel: BuildingSuitColors.roleDarkChartLabel,
    chartTooltipBackground: BuildingSuitColors.roleDarkChartTooltipBackground,
    chartTooltipText: BuildingSuitColors.roleDarkChartTooltipText,
    chartPositive: BuildingSuitColors.roleDarkChartPositive,
    chartNegative: BuildingSuitColors.roleDarkChartNegative,
    chartNeutral: BuildingSuitColors.roleDarkChartNeutral,
    chartSelection: BuildingSuitColors.roleDarkChartSelection,
  );

  final Color background;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color overlay;
  final Color inverseSurface;
  final Color textPrimary;
  final Color textMuted;
  final Color textSubtle;
  final Color textDisabled;
  final Color borderSubtle;
  final Color borderStrong;
  final Color divider;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color onAccent;
  final Color link;
  final Color focusRing;
  final Color focusGlow;
  final Color brandSurface;
  final Color onBrandSurface;
  final Color hoverOverlay;
  final Color pressedOverlay;
  final Color selectedOverlay;
  final Color disabledOverlay;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final FinanceSuitStatusColors success;
  final FinanceSuitStatusColors warning;
  final FinanceSuitStatusColors error;
  final FinanceSuitStatusColors info;
  final List<Color> chartSeries;
  final Color chartGrid;
  final Color chartAxis;
  final Color chartLabel;
  final Color chartTooltipBackground;
  final Color chartTooltipText;
  final Color chartPositive;
  final Color chartNegative;
  final Color chartNeutral;
  final Color chartSelection;

  @override
  FinanceSuitSemanticColors copyWith() => this;

  @override
  FinanceSuitSemanticColors lerp(
    covariant FinanceSuitSemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    Color blend(Color first, Color second) => Color.lerp(first, second, t)!;
    return FinanceSuitSemanticColors(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      surfaceContainer: blend(surfaceContainer, other.surfaceContainer),
      surfaceMuted: blend(surfaceMuted, other.surfaceMuted),
      surfaceRaised: blend(surfaceRaised, other.surfaceRaised),
      overlay: blend(overlay, other.overlay),
      inverseSurface: blend(inverseSurface, other.inverseSurface),
      textPrimary: blend(textPrimary, other.textPrimary),
      textMuted: blend(textMuted, other.textMuted),
      textSubtle: blend(textSubtle, other.textSubtle),
      textDisabled: blend(textDisabled, other.textDisabled),
      borderSubtle: blend(borderSubtle, other.borderSubtle),
      borderStrong: blend(borderStrong, other.borderStrong),
      divider: blend(divider, other.divider),
      primary: blend(primary, other.primary),
      onPrimary: blend(onPrimary, other.onPrimary),
      accent: blend(accent, other.accent),
      onAccent: blend(onAccent, other.onAccent),
      link: blend(link, other.link),
      focusRing: blend(focusRing, other.focusRing),
      focusGlow: blend(focusGlow, other.focusGlow),
      brandSurface: blend(brandSurface, other.brandSurface),
      onBrandSurface: blend(onBrandSurface, other.onBrandSurface),
      hoverOverlay: blend(hoverOverlay, other.hoverOverlay),
      pressedOverlay: blend(pressedOverlay, other.pressedOverlay),
      selectedOverlay: blend(selectedOverlay, other.selectedOverlay),
      disabledOverlay: blend(disabledOverlay, other.disabledOverlay),
      skeletonBase: blend(skeletonBase, other.skeletonBase),
      skeletonHighlight: blend(skeletonHighlight, other.skeletonHighlight),
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      error: error.lerp(other.error, t),
      info: info.lerp(other.info, t),
      chartSeries: [
        for (var index = 0; index < chartSeries.length; index++)
          blend(chartSeries[index], other.chartSeries[index]),
      ],
      chartGrid: blend(chartGrid, other.chartGrid),
      chartAxis: blend(chartAxis, other.chartAxis),
      chartLabel: blend(chartLabel, other.chartLabel),
      chartTooltipBackground: blend(
        chartTooltipBackground,
        other.chartTooltipBackground,
      ),
      chartTooltipText: blend(chartTooltipText, other.chartTooltipText),
      chartPositive: blend(chartPositive, other.chartPositive),
      chartNegative: blend(chartNegative, other.chartNegative),
      chartNeutral: blend(chartNeutral, other.chartNeutral),
      chartSelection: blend(chartSelection, other.chartSelection),
    );
  }
}

extension FinanceSuitThemeColors on BuildContext {
  FinanceSuitSemanticColors get suitColors =>
      Theme.of(this).extension<FinanceSuitSemanticColors>()!;
}
