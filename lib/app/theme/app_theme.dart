import 'package:flutter/material.dart';

/// Material 3 light/dark themes with accessible contrast and
/// tabular figures for monetary values.
class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF00696D); // teal — finance-friendly, calm.

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Never Size.fromHeight here: its infinite minimum width makes
          // any FilledButton inside a Row fail layout and vanish.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
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

  /// Semantic colors for transaction directions. Color is never the only
  /// indicator — icons and sign prefixes accompany it.
  static Color incomeColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF7BD88F)
      : const Color(0xFF1B6E3C);

  static Color expenseColor(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  static Color allowanceColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFE2B96F)
      : const Color(0xFF8A5A00);

  static Color transferColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
}
