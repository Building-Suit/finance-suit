import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/splash_screen.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/app/theme/building_suit_colors.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';
import 'package:work_tracker/l10n/generated/app_localizations_ar.dart';
import 'package:work_tracker/l10n/generated/app_localizations_en.dart';

void main() {
  test('Finance Suit stays the product name in English and Arabic', () {
    expect(AppLocalizationsEn().appTitle, FinanceSuitBrand.name);
    expect(AppLocalizationsAr().appTitle, FinanceSuitBrand.name);
  });

  test('light theme uses the Finance Suit role contract', () {
    final theme = AppTheme.light();

    expect(
      theme.scaffoldBackgroundColor,
      BuildingSuitColors.roleLightBackground,
    );
    expect(theme.colorScheme.surface, BuildingSuitColors.roleLightSurface);
    expect(theme.colorScheme.onSurface, BuildingSuitColors.roleLightText);
    expect(theme.colorScheme.primary, BuildingSuitColors.roleLightPrimary);
    expect(
      theme.colorScheme.onPrimary,
      BuildingSuitColors.roleLightTextOnPrimary,
    );
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains('IBM Plex Sans Arabic'),
    );
  });

  test('dark theme is neutral charcoal with gold primary actions', () {
    final theme = AppTheme.dark();

    expect(
      theme.scaffoldBackgroundColor,
      BuildingSuitColors.roleDarkBackground,
    );
    expect(theme.colorScheme.surface, BuildingSuitColors.roleDarkSurface);
    expect(theme.colorScheme.onSurface, BuildingSuitColors.roleDarkText);
    expect(theme.colorScheme.primary, BuildingSuitColors.roleDarkPrimary);
    expect(
      theme.colorScheme.onPrimary,
      BuildingSuitColors.roleDarkTextOnPrimary,
    );
    expect(
      _contrastRatio(theme.colorScheme.primary, theme.colorScheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('focus and control boundaries use mode-specific semantic roles', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    final lightColors = light.extension<FinanceSuitSemanticColors>()!;
    final darkColors = dark.extension<FinanceSuitSemanticColors>()!;

    expect(lightColors.focusRing, BuildingSuitColors.roleLightFocusRing);
    expect(darkColors.focusRing, BuildingSuitColors.roleDarkFocusRing);
    expect(darkColors.focusRing, BuildingSuitColors.brandHighlightGold);

    final lightInput = light.inputDecorationTheme.enabledBorder!;
    final darkInput = dark.inputDecorationTheme.enabledBorder!;
    expect(
      (lightInput as OutlineInputBorder).borderSide.color,
      BuildingSuitColors.roleLightBorderStrong,
    );
    expect(
      (darkInput as OutlineInputBorder).borderSide.color,
      BuildingSuitColors.roleDarkBorderStrong,
    );
    expect(
      (dark.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
          .borderSide
          .color,
      BuildingSuitColors.roleDarkFocusRing,
    );
  });

  test('chart and skeleton roles use the canonical mode variants', () {
    final light = AppTheme.light().extension<FinanceSuitSemanticColors>()!;
    final dark = AppTheme.dark().extension<FinanceSuitSemanticColors>()!;

    expect(light.chartSeries.first, BuildingSuitColors.categoricalLight1);
    expect(dark.chartSeries.first, BuildingSuitColors.categoricalDark1);
    expect(light.skeletonBase, BuildingSuitColors.roleLightSkeletonBase);
    expect(dark.skeletonBase, BuildingSuitColors.roleDarkSkeletonBase);
    expect(
      dark.chartTooltipBackground,
      BuildingSuitColors.roleDarkChartTooltipBackground,
    );
  });

  test('Arabic theme uses IBM Plex Sans Arabic with extra line height', () {
    final latinTheme = AppTheme.light(locale: const Locale('en'));
    final arabicTheme = AppTheme.light(locale: const Locale('ar'));

    expect(
      arabicTheme.textTheme.bodyMedium?.fontFamily,
      FinanceSuitBrand.arabicFontFamily,
    );
    expect(
      arabicTheme.textTheme.bodyMedium?.fontFamilyFallback,
      contains(FinanceSuitBrand.latinFontFamily),
    );
    expect(
      arabicTheme.textTheme.bodyMedium!.height!,
      greaterThan(latinTheme.textTheme.bodyMedium!.height!),
    );
  });

  test('semantic text and focus roles meet their contrast targets', () {
    final light = AppTheme.light().extension<FinanceSuitSemanticColors>()!;
    final dark = AppTheme.dark().extension<FinanceSuitSemanticColors>()!;
    final lightForegrounds = [
      light.textPrimary,
      light.textMuted,
      light.success.text,
      light.warning.text,
      light.error.text,
      light.info.text,
    ];

    for (final foreground in lightForegrounds) {
      expect(
        _contrastRatio(foreground, light.surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      _contrastRatio(light.focusRing, light.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      _contrastRatio(dark.textPrimary, dark.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(dark.textMuted, dark.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(dark.focusRing, dark.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      _contrastRatio(light.borderStrong, light.surface),
      greaterThanOrEqualTo(3),
    );
    expect(
      _contrastRatio(dark.borderStrong, dark.surface),
      greaterThanOrEqualTo(3),
    );
    for (final status in [
      light.success,
      light.warning,
      light.error,
      light.info,
      dark.success,
      dark.warning,
      dark.error,
      dark.info,
    ]) {
      expect(
        _contrastRatio(status.text, status.background),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('official mark aliases remain the approved artwork colors', () {
    expect(FinanceSuitBrand.buildingNavy, BuildingSuitColors.brandBuildingNavy);
    expect(FinanceSuitBrand.premiumGold, BuildingSuitColors.brandPremiumGold);
    expect(FinanceSuitBrand.pearlWhite, BuildingSuitColors.roleLightBackground);
  });

  testWidgets('splash presents the Finance Suit mark and name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SplashScreen(),
      ),
    );

    expect(find.byType(FinanceSuitMark), findsOneWidget);
    expect(find.text(FinanceSuitBrand.name), findsOneWidget);
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
