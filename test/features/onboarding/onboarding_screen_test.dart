import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Pumps the onboarding screen with the REAL app theme. A theme-level
/// button bug (infinite minimumSize width) once made the wizard footer
/// vanish only on devices because tests used the default theme.
Future<void> pumpOnboarding(WidgetTester tester, {ThemeData? theme}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('step 1 shows a visible Next button on a phone viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpOnboarding(tester);

    final next = find.widgetWithText(FilledButton, 'Next');
    expect(next, findsOneWidget);

    final rect = tester.getRect(next);
    expect(rect.bottom, lessThanOrEqualTo(915));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('Next button visible with the light app theme too', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpOnboarding(tester, theme: AppTheme.light());

    expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
  });

  testWidgets('Next button is reachable by scrolling on a tiny viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpOnboarding(tester);

    final next = find.widgetWithText(FilledButton, 'Next');
    await tester.dragUntilVisible(
      next,
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(next, findsOneWidget);
    final rect = tester.getRect(next);
    expect(rect.bottom, lessThanOrEqualTo(480));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('Enter key advances to the next step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpOnboarding(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Tareq Abdelwhap');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4'), findsOneWidget);
  });
}
