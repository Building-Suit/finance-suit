import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/splash_screen.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
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

    expect(theme.scaffoldBackgroundColor, FinanceSuitBrand.pearlWhite);
    expect(theme.colorScheme.surface, Colors.white);
    expect(theme.colorScheme.onSurface, FinanceSuitBrand.graphiteText);
    expect(theme.colorScheme.primary, FinanceSuitBrand.buildingNavy);
    expect(theme.colorScheme.onPrimary, FinanceSuitBrand.pearlWhite);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains('IBM Plex Sans Arabic'),
    );
  });

  test('dark theme flips primary actions to gold', () {
    final theme = AppTheme.dark();

    expect(theme.scaffoldBackgroundColor, FinanceSuitBrand.midnightBackground);
    expect(theme.colorScheme.surface, FinanceSuitBrand.navySurface);
    expect(theme.colorScheme.onSurface, FinanceSuitBrand.pearlWhite);
    expect(theme.colorScheme.primary, FinanceSuitBrand.premiumGold);
    expect(theme.colorScheme.onPrimary, FinanceSuitBrand.deepStructureNavy);
    expect(theme.colorScheme.primaryContainer, FinanceSuitBrand.premiumGold);
    expect(
      theme.colorScheme.onPrimaryContainer,
      FinanceSuitBrand.deepStructureNavy,
    );
    expect(
      _contrastRatio(
        theme.colorScheme.primaryContainer,
        theme.colorScheme.onPrimaryContainer,
      ),
      greaterThanOrEqualTo(4.5),
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

  test('light semantic foregrounds keep text contrast', () {
    final foregrounds = [
      FinanceSuitBrand.successForeground,
      FinanceSuitBrand.warningForeground,
      FinanceSuitBrand.errorForeground,
      FinanceSuitBrand.infoForeground,
    ];

    for (final foreground in foregrounds) {
      expect(
        _contrastRatio(foreground, Colors.white),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      _contrastRatio(FinanceSuitBrand.gold700, Colors.white),
      greaterThanOrEqualTo(3),
    );
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
