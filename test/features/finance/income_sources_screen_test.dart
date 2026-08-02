import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/income_sources_screen.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  const activeSalary = IncomeSource(
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
    allocations: [
      IncomeAllocation(
        destinationAccountId: 'saving-account',
        method: IncomeAllocationMethod.percentage,
        percentageBasisPoints: 3000,
      ),
    ],
  );
  const pausedAllowance = IncomeSource(
    id: 'allowance-source',
    name: 'Family allowance',
    kind: IncomeSourceKind.allowance,
    expectedAmountMinor: 500000,
    currencyCode: 'EGP',
    paymentDay: 10,
    startDate: PlainDate(2026, 1, 1),
    promptDaysBefore: 1,
    primaryAccountId: 'default-account',
    isActive: false,
    allocations: [],
  );
  const pendingSalary = PendingIncome(
    source: activeSalary,
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
  const accounts = [
    AccountBalance(
      accountId: 'default-account',
      name: 'Default',
      accountType: AccountType.current,
      currencyCode: 'EGP',
      isDefault: true,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 0,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 0,
    ),
    AccountBalance(
      accountId: 'saving-account',
      name: 'Saving',
      accountType: AccountType.savings,
      currencyCode: 'EGP',
      isDefault: false,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 0,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 0,
    ),
  ];

  testWidgets(
    'automation screen explains behavior, groups states, and has no FAB',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incomeSourcesProvider.overrideWith(
              (ref) async => const [activeSalary, pausedAllowance],
            ),
            pendingIncomeProvider.overrideWith(
              (ref) async => const [pendingSalary],
            ),
            pendingSalaryEstimateProvider.overrideWith(
              (ref, key) async => salaryEstimate,
            ),
            allAccountBalancesProvider.overrideWith((ref) async => accounts),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const IncomeSourcesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Income automations'), findsWidgets);
      expect(
        find.textContaining('Nothing changes your balance'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Add automation'),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.dragUntilVisible(
        find.text('Income to approve'),
        find.byType(ListView),
        const Offset(0, -160),
      );
      expect(find.text('Income to approve'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Base amount'),
        find.byType(ListView),
        const Offset(0, -160),
      );
      expect(find.text('Base amount'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Active automations'),
        find.byType(ListView),
        const Offset(0, -160),
      );
      expect(find.text('Active automations'), findsOneWidget);
      expect(find.text('Salary'), findsWidgets);

      await tester.dragUntilVisible(
        find.text('Paused automations'),
        find.byType(ListView),
        const Offset(0, -160),
      );
      expect(find.text('Paused automations'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Family allowance'),
        find.byType(ListView),
        const Offset(0, -160),
      );
      expect(find.text('Family allowance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
