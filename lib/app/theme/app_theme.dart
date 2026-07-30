import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';

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
    final colors = isDark
        ? FinanceSuitSemanticColors.dark()
        : FinanceSuitSemanticColors.light();

    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: brightness,
        ).copyWith(
          primary: colors.primary,
          onPrimary: colors.onPrimary,
          primaryContainer: colors.surfaceContainer,
          onPrimaryContainer: colors.textPrimary,
          secondary: colors.accent,
          onSecondary: colors.onAccent,
          secondaryContainer: colors.selectedOverlay,
          onSecondaryContainer: colors.textPrimary,
          tertiary: colors.link,
          onTertiary: colors.onPrimary,
          tertiaryContainer: colors.info.background,
          onTertiaryContainer: colors.info.text,
          error: colors.error.foreground,
          onError: colors.error.textOnSolid,
          errorContainer: colors.error.background,
          onErrorContainer: colors.error.text,
          surface: colors.surface,
          onSurface: colors.textPrimary,
          surfaceDim: colors.background,
          surfaceBright: colors.surfaceRaised,
          surfaceContainerLowest: colors.background,
          surfaceContainerLow: colors.surface,
          surfaceContainer: colors.surfaceContainer,
          surfaceContainerHigh: colors.surfaceRaised,
          surfaceContainerHighest: colors.surfaceMuted,
          onSurfaceVariant: colors.textMuted,
          outline: colors.borderStrong,
          outlineVariant: colors.borderSubtle,
          shadow: colors.background,
          scrim: isDark ? colors.background : colors.inverseSurface,
          inverseSurface: colors.inverseSurface,
          onInverseSurface: isDark ? colors.background : colors.onBrandSurface,
          inversePrimary: colors.accent,
          surfaceTint: Colors.transparent,
        );

    final textTheme = _textTheme(
      text: colors.textPrimary,
      textMuted: colors.textMuted,
      isArabic: isArabic,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      fontFamily: isArabic
          ? FinanceSuitBrand.arabicFontFamily
          : FinanceSuitBrand.latinFontFamily,
      textTheme: textTheme,
      extensions: [colors],
      focusColor: colors.focusGlow,
      hoverColor: colors.hoverOverlay,
      splashColor: colors.pressedOverlay,
      highlightColor: colors.pressedOverlay,
      disabledColor: colors.textDisabled,
    );
    final radius12 = BorderRadius.circular(12);
    final radius16 = BorderRadius.circular(16);
    final radius24 = BorderRadius.circular(24);
    final defaultBorder = OutlineInputBorder(
      borderRadius: radius12,
      borderSide: BorderSide(color: colors.borderStrong),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: radius12,
      borderSide: BorderSide(color: colors.focusRing, width: 2),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: radius12,
      borderSide: BorderSide(color: colors.error.border),
    );
    final cardShadow = (isDark ? colors.background : colors.inverseSurface)
        .withValues(alpha: isDark ? 0.32 : 0.08);
    Color? interactionOverlay(Set<WidgetState> states) {
      if (states.contains(WidgetState.pressed)) return colors.pressedOverlay;
      if (states.contains(WidgetState.hovered)) return colors.hoverOverlay;
      if (states.contains(WidgetState.focused)) return colors.focusGlow;
      return null;
    }

    BorderSide focusSide(Set<WidgetState> states, {Color? restingColor}) =>
        states.contains(WidgetState.focused)
        ? BorderSide(color: colors.focusRing, width: 2)
        : BorderSide(color: restingColor ?? Colors.transparent);

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: cardShadow,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: cardShadow,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: radius16,
          side: BorderSide(color: colors.borderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
        helperStyle: textTheme.bodySmall?.copyWith(color: colors.textMuted),
        errorStyle: textTheme.bodySmall?.copyWith(color: colors.error.text),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder.copyWith(
          borderSide: BorderSide(color: colors.error.border, width: 2),
        ),
        disabledBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: colors.surfaceMuted,
              disabledForegroundColor: colors.textDisabled,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: radius12),
              textStyle: textTheme.labelLarge,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
              side: WidgetStateProperty.resolveWith(focusSide),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: radius12),
              textStyle: textTheme.labelLarge,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
              side: WidgetStateProperty.resolveWith(
                (states) =>
                    focusSide(states, restingColor: colors.borderStrong),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: colors.link,
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(borderRadius: radius12),
              textStyle: textTheme.labelLarge,
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
              side: WidgetStateProperty.resolveWith(focusSide),
            ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style:
            IconButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(borderRadius: radius12),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
              side: WidgetStateProperty.resolveWith(focusSide),
            ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colors.surface,
        indicatorColor: colors.selectedOverlay,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.focusRing : colors.textMuted,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall!.copyWith(
            color: selected ? colors.textPrimary : colors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colors.focusRing,
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textMuted,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        dividerColor: colors.divider,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainer,
        selectedColor: colors.selectedOverlay,
        disabledColor: colors.surfaceMuted,
        side: BorderSide(color: colors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: textTheme.bodySmall!.copyWith(color: colors.textPrimary),
        secondaryLabelStyle: textTheme.bodySmall!.copyWith(
          color: colors.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.textDisabled
                : colors.textPrimary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.selectedOverlay
                : colors.surface,
          ),
          overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
          side: WidgetStateProperty.resolveWith(
            (states) => focusSide(states, restingColor: colors.borderStrong),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.overlay,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: cardShadow,
        shape: RoundedRectangleBorder(borderRadius: radius24),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.overlay,
        modalBackgroundColor: colors.overlay,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: (isDark ? colors.background : colors.inverseSurface)
            .withValues(alpha: isDark ? 0.72 : 0.48),
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? colors.overlay : colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? colors.textPrimary : colors.onBrandSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.chartTooltipBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colors.chartTooltipText,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.overlay,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: radius12,
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.skeletonBase,
        circularTrackColor: colors.skeletonBase,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.focusRing,
        selectionColor: colors.selectedOverlay,
        selectionHandleColor: colors.focusRing,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surface,
        ),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
        side: BorderSide(color: colors.borderStrong),
        overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.borderStrong,
        ),
        overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? colors.focusRing
              : colors.borderStrong,
        ),
        overlayColor: WidgetStateProperty.resolveWith(interactionOverlay),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textMuted,
        textColor: colors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: radius12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerColor: colors.divider,
      iconTheme: IconThemeData(color: colors.textPrimary),
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
      context.suitColors.success.text;

  static Color expenseColor(BuildContext context) =>
      context.suitColors.error.text;

  static Color allowanceColor(BuildContext context) =>
      context.suitColors.warning.text;

  static Color transferColor(BuildContext context) =>
      context.suitColors.info.text;

  static Color infoColor(BuildContext context) => context.suitColors.info.text;
}
