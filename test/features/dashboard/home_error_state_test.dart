import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  const salarySource = IncomeSource(
    id: 'salary-source',
    name: 'Salary',
    kind: IncomeSourceKind.salary,
    expectedAmountMinor: 4000000,
    currencyCode: 'EGP',
    paymentDay: 5,
    startDate: PlainDate(2026, 1, 1),
    promptDaysBefore: 2,
    primaryAccountId: 'default-account',
    isActive: true,
    allocations: [],
  );
  const pendingSalary = PendingIncome(
    source: salarySource,
    occurrence: IncomeOccurrence(
      id: 'salary-occurrence',
      incomeSourceId: 'salary-source',
      scheduledOn: PlainDate(2026, 7, 5),
      expectedAmountMinor: 4000000,
      status: IncomeOccurrenceStatus.pending,
    ),
  );
  const salaryEstimate = SalaryEstimate(
    periodStart: PlainDate(2026, 6, 1),
    periodEnd: PlainDate(2026, 6, 30),
    expectedPaymentDate: PlainDate(2026, 7, 5),
    currencyCode: 'EGP',
    baseSalaryMinor: 4000000,
    dayRateMinor: 133333,
    hourRateMinor: 16667,
    extraDayUnitsHundredths: 100,
    extraDayAmountMinor: 133333,
    holidayCount: 1,
    holidayAmountMinor: 133333,
    overtimeMinutes: 240,
    overtimeAmountMinor: 133336,
    bonusesMinor: 0,
    deductionsMinor: 0,
    warnings: [],
  );

  testWidgets(
    'several provider failures render one status card and keep successes',
    (tester) async {
      var accountFetches = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue(null),
            accountBalancesProvider.overrideWith((ref) async {
              accountFetches++;
              throw const UnknownFailure(
                debugDetails: 'accounts provider trace',
              );
            }),
            allAccountBalancesProvider.overrideWith(
              (ref) async => const <AccountBalance>[],
            ),
            pendingIncomeProvider.overrideWith(
              (ref) async => const <PendingIncome>[],
            ),
            cashFlowSummaryProvider.overrideWith(
              (ref, range) async => const [
                CashFlowSummary(
                  currencyCode: 'EGP',
                  startingBalanceMinor: 0,
                  incomeMinor: 10000,
                  expensesMinor: 2500,
                  allowancesMinor: 500,
                  netMinor: 7000,
                  endingBalanceMinor: 7000,
                ),
              ],
            ),
            salarySettingsProvider.overrideWith(
              (ref) async =>
                  SalarySettings.defaults.copyWith(salaryEnabled: false),
            ),
            historyPageProvider.overrideWith(
              (ref, query) async =>
                  throw const ConfigurationFailure(debugDetails: 'PGRST205'),
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
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Some dashboard sections could not be loaded. Other available data is still shown.',
        ),
        findsOneWidget,
      );
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsNothing,
      );
      expect(find.text('Salary'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(accountFetches, greaterThan(1));
    },
  );

  test('unknown failure keeps developer details', () {
    const failure = UnknownFailure(debugDetails: 'provider=accounts\nstack');
    expect(failure.debugDetails, contains('provider=accounts'));
    expect(failure.toString(), contains('stack'));
  });

  testWidgets('pending income is a compact link to automation details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/settings/income-sources',
          builder: (_, _) => const Scaffold(body: Text('Automation details')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          accountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          allAccountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          pendingIncomeProvider.overrideWith(
            (ref) async => const [pendingSalary],
          ),
          pendingSalaryEstimateProvider.overrideWith(
            (ref, key) async => salaryEstimate,
          ),
          cashFlowSummaryProvider.overrideWith(
            (ref, range) async => const [
              CashFlowSummary(
                currencyCode: 'EGP',
                startingBalanceMinor: 0,
                incomeMinor: 0,
                expensesMinor: 0,
                allowancesMinor: 0,
                netMinor: 0,
                endingBalanceMinor: 0,
              ),
            ],
          ),
          salarySettingsProvider.overrideWith(
            (ref) async =>
                SalarySettings.defaults.copyWith(salaryEnabled: false),
          ),
          historyPageProvider.overrideWith(
            (ref, query) async => const HistoryPage(items: [], hasMore: false),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const Key('home-pending-income-summary'));
    expect(summary, findsOneWidget);
    expect(tester.getSize(summary).height, lessThan(120));
    expect(find.text('Income to approve'), findsOneWidget);
    expect(find.textContaining('Salary ·'), findsOneWidget);
    expect(find.text('Accept income'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Later'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(find.text('Automation details'), findsOneWidget);
  });
}
