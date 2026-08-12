import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Regression: the cash-flow metric grid overflowed by a few pixels on a
/// 320x480 phone because the compact grid cells were too short for the
/// icon + label + amount column.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          accountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          allAccountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          pendingIncomeProvider.overrideWith(
            (ref) async => const <PendingIncome>[],
          ),
          homeCurrentMonthObligationsProvider.overrideWith(
            (ref) async => HomeDueSummary(const []),
          ),
          homeCashFlowSummaryProvider.overrideWith(
            (ref, range) async => const [
              CashFlowSummary(
                currencyCode: 'EGP',
                startingBalanceMinor: 250000,
                incomeMinor: 1250000,
                expensesMinor: 480000,
                allowancesMinor: 120000,
                netMinor: 650000,
                endingBalanceMinor: 900000,
              ),
            ],
          ),
          salarySettingsProvider.overrideWith(
            (ref) => Completer<SalarySettings>().future,
          ),
          historyPageProvider.overrideWith(
            (ref, query) async => const HistoryPage(items: [], hasMore: false),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('cash-flow metric cards fit a 320x480 phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHome(tester);
    await tester.dragUntilVisible(
      find.byType(GridView),
      find.byKey(const Key('home-dashboard-scroll')),
      const Offset(0, -160),
    );
    expect(find.byType(GridView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash-flow metric cards fit a normal phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHome(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home header morphs after scrolling and restores at the top', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHome(tester);
    final surface = find.byKey(const Key('finance-suit-app-bar-surface'));
    final scrollView = find.byKey(const Key('home-dashboard-scroll'));
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      const EdgeInsetsDirectional.symmetric(horizontal: 16),
    );

    await tester.drag(scrollView, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      EdgeInsetsDirectional.zero,
    );

    await tester.drag(scrollView, const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      const EdgeInsetsDirectional.symmetric(horizontal: 16),
    );
    expect(tester.takeException(), isNull);
  });
}
