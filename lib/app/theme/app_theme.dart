import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';

/// Finance Suit's Material 3 implementation of the shared Suit design system.
class AppTheme {
  const AppTheme._();

  static ThemeData light({Locale? locale}) =>
      _build(Brightness.light, locale: locale);
  static ThemeData dark({Locale? locale}) =>
      _build(Brightness.dark, locale: locale);

  static ThemeData _build(Brightness brightness, {Locale? locale}) {
    final isDark = brightness == Brightness.dark;
    final isArabic = locale?.languageCode == 'ar';
    final background = isDark
        ? FinanceSuitBrand.midnightBackground
        : FinanceSuitBrand.pearlWhite;
    final surface = isDark ? FinanceSuitBrand.navySurface : Colors.white;
    final surfaceMuted = isDark
        ? FinanceSuitBrand.deepStructureNavy
        : FinanceSuitBrand.softSilver;
    final surfaceRaised = isDark
        ? FinanceSuitBrand.navySurfaceRaised
        : Colors.white;
    final text = isDark
        ? FinanceSuitBrand.pearlWhite
        : FinanceSuitBrand.graphiteText;
    final textMuted = isDark
        ? FinanceSuitBrand.skySteel
        : FinanceSuitBrand.slateGray;
    final border = isDark
        ? FinanceSuitBrand.steelBorder
        : FinanceSuitBrand.cloudGray;
    final primary = isDark
        ? FinanceSuitBrand.premiumGold
        : FinanceSuitBrand.buildingNavy;
    final onPrimary = isDark
        ? FinanceSuitBrand.deepStructureNavy
        : FinanceSuitBrand.pearlWhite;
    final accent = isDark
        ? FinanceSuitBrand.highlightGold
        : FinanceSuitBrand.premiumGold;
    final interactionAccent = isDark
        ? FinanceSuitBrand.highlightGold
        : FinanceSuitBrand.gold700;
    final error = isDark
        ? FinanceSuitBrand.errorDark
        : FinanceSuitBrand.errorForeground;
    final errorContainer = isDark
        ? FinanceSuitBrand.errorBackgroundDark
        : FinanceSuitBrand.errorBackground;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          primaryContainer: isDark
              ? FinanceSuitBrand.premiumGold
              : FinanceSuitBrand.paleSky,
          onPrimaryContainer: FinanceSuitBrand.deepStructureNavy,
          secondary: accent,
          onSecondary: FinanceSuitBrand.deepStructureNavy,
          secondaryContainer: isDark
              ? FinanceSuitBrand.navySurfaceRaised
              : FinanceSuitBrand.paleSky,
          onSecondaryContainer: isDark
              ? FinanceSuitBrand.pearlWhite
              : FinanceSuitBrand.deepStructureNavy,
          tertiary: isDark
              ? FinanceSuitBrand.skySteel
              : FinanceSuitBrand.slateBlue,
          onTertiary: isDark
              ? FinanceSuitBrand.deepStructureNavy
              : FinanceSuitBrand.pearlWhite,
          tertiaryContainer: isDark
              ? FinanceSuitBrand.infoBackgroundDark
              : FinanceSuitBrand.infoBackground,
          onTertiaryContainer: text,
          error: error,
          onError: isDark ? FinanceSuitBrand.deepStructureNavy : Colors.white,
          errorContainer: errorContainer,
          onErrorContainer: isDark
              ? FinanceSuitBrand.pearlWhite
              : FinanceSuitBrand.graphiteText,
          surface: surface,
          onSurface: text,
          surfaceDim: isDark
              ? FinanceSuitBrand.midnightBackground
              : FinanceSuitBrand.softSilver,
          surfaceBright: surfaceRaised,
          surfaceContainerLowest: isDark
              ? FinanceSuitBrand.midnightBackground
              : Colors.white,
          surfaceContainerLow: isDark
              ? FinanceSuitBrand.deepStructureNavy
              : FinanceSuitBrand.pearlWhite,
          surfaceContainer: surface,
          surfaceContainerHigh: surfaceRaised,
          surfaceContainerHighest: isDark
              ? FinanceSuitBrand.steelBorder
              : FinanceSuitBrand.softSilver,
          onSurfaceVariant: textMuted,
          outline: border,
          outlineVariant: isDark
              ? FinanceSuitBrand.steelBorder
              : FinanceSuitBrand.softSilver,
          shadow: FinanceSuitBrand.deepStructureNavy,
          scrim: isDark ? Colors.black : FinanceSuitBrand.deepStructureNavy,
          inverseSurface: isDark
              ? FinanceSuitBrand.pearlWhite
              : FinanceSuitBrand.deepStructureNavy,
          onInverseSurface: isDark
              ? FinanceSuitBrand.graphiteText
              : FinanceSuitBrand.pearlWhite,
          inversePrimary: accent,
          surfaceTint: Colors.transparent,
        );

    final textTheme = _textTheme(
      text: text,
      textMuted: textMuted,
      isArabic: isArabic,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: isArabic
          ? FinanceSuitBrand.arabicFontFamily
          : FinanceSuitBrand.latinFontFamily,
      textTheme: textTheme,
    );
    final radius12 = BorderRadius.circular(12);
    final radius16 = BorderRadius.circular(16);
    final radius24 = BorderRadius.circular(24);
    final defaultBorder = OutlineInputBorder(
      borderRadius: radius12,
      borderSide: BorderSide(color: border),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: radius12,
      borderSide: BorderSide(color: interactionAccent, width: 2),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: radius12,
      borderSide: BorderSide(color: error),
    );
    final cardShadow = FinanceSuitBrand.deepStructureNavy.withValues(
      alpha: isDark ? 0.32 : 0.08,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: cardShadow,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: cardShadow,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: radius16,
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textMuted),
        helperStyle: textTheme.bodySmall?.copyWith(color: textMuted),
        errorStyle: textTheme.bodySmall?.copyWith(color: error),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder.copyWith(
          borderSide: BorderSide(color: error, width: 2),
        ),
        disabledBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: border.withValues(alpha: 0.6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: surfaceMuted,
          disabledForegroundColor: isDark
              ? const Color(0xFF4A5A6E)
              : FinanceSuitBrand.steelGray,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark
              ? FinanceSuitBrand.pearlWhite
              : FinanceSuitBrand.buildingNavy,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark
              ? FinanceSuitBrand.skySteel
              : FinanceSuitBrand.slateBlue,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: radius12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: isDark ? 0.18 : 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? interactionAccent : textMuted,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall!.copyWith(
            color: selected
                ? (isDark ? interactionAccent : FinanceSuitBrand.buildingNavy)
                : textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: interactionAccent,
        labelColor: isDark ? interactionAccent : FinanceSuitBrand.buildingNavy,
        unselectedLabelColor: textMuted,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor: border,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: accent.withValues(alpha: isDark ? 0.18 : 0.12),
        disabledColor: surfaceMuted.withValues(alpha: 0.6),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.bodySmall!.copyWith(color: text),
        secondaryLabelStyle: textTheme.bodySmall!.copyWith(color: text),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: cardShadow,
        shape: RoundedRectangleBorder(borderRadius: radius24),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceRaised,
        modalBackgroundColor: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor:
            (isDark ? Colors.black : FinanceSuitBrand.deepStructureNavy)
                .withValues(alpha: isDark ? 0.64 : 0.48),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? FinanceSuitBrand.navySurfaceRaised
            : FinanceSuitBrand.deepStructureNavy,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: FinanceSuitBrand.pearlWhite,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: surfaceMuted,
        circularTrackColor: surfaceMuted,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: interactionAccent,
        selectionColor: accent.withValues(alpha: 0.24),
        selectionHandleColor: interactionAccent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        textColor: text,
        shape: RoundedRectangleBorder(borderRadius: radius12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerColor: border,
      iconTheme: IconThemeData(color: text),
    );
  }

  static TextTheme _textTheme({
    required Color text,
    required Color textMuted,
    required bool isArabic,
  }) {
    TextStyle style({
      required double size,
      required double lineHeight,
      required FontWeight weight,
      Color? color,
    }) {
      final fontFamily = isArabic
          ? FinanceSuitBrand.arabicFontFamily
          : FinanceSuitBrand.latinFontFamily;
      final fontFallbacks = isArabic
          ? FinanceSuitBrand.arabicFontFallbacks
          : FinanceSuitBrand.latinFontFallbacks;
      final resolvedLineHeight = lineHeight * (isArabic ? 1.12 : 1);
      return TextStyle(
        color: color ?? text,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallbacks,
        fontSize: size,
        height: resolvedLineHeight / size,
        fontWeight: weight,
      );
    }

    return TextTheme(
      displaySmall: style(size: 32, lineHeight: 40, weight: FontWeight.w800),
      headlineLarge: style(size: 26, lineHeight: 34, weight: FontWeight.w700),
      headlineMedium: style(size: 22, lineHeight: 30, weight: FontWeight.w700),
      headlineSmall: style(size: 18, lineHeight: 26, weight: FontWeight.w600),
      titleLarge: style(size: 22, lineHeight: 30, weight: FontWeight.w700),
      titleMedium: style(size: 18, lineHeight: 26, weight: FontWeight.w600),
      titleSmall: style(size: 16, lineHeight: 24, weight: FontWeight.w600),
      bodyLarge: style(size: 16, lineHeight: 24, weight: FontWeight.w400),
      bodyMedium: style(size: 14, lineHeight: 22, weight: FontWeight.w400),
      bodySmall: style(
        size: 12,
        lineHeight: 18,
        weight: FontWeight.w500,
        color: textMuted,
      ),
      labelLarge: style(size: 15, lineHeight: 20, weight: FontWeight.w600),
      labelMedium: style(size: 12, lineHeight: 18, weight: FontWeight.w500),
      labelSmall: style(
        size: 11,
        lineHeight: 16,
        weight: FontWeight.w600,
        color: textMuted,
      ),
    );
  }

  /// Style for large balance figures. Tabular figures keep digits aligned.
  static TextStyle balanceStyle(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!.copyWith(
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Style for inline monetary amounts.
  static TextStyle amountStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Semantic money/status colors are intentionally separate from brand gold.
  static Color incomeColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? FinanceSuitBrand.successDark
      : FinanceSuitBrand.successForeground;

  static Color expenseColor(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  static Color allowanceColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? FinanceSuitBrand.warningDark
      : FinanceSuitBrand.warningForeground;

  static Color transferColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? FinanceSuitBrand.skySteel
      : FinanceSuitBrand.slateBlue;

  static Color infoColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? FinanceSuitBrand.infoDark
      : FinanceSuitBrand.infoForeground;
}
