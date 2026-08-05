import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// After a partially received salary, the pending banner must offer only the
/// shortfall that is still owed — never the full amount that was expected.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  const salary = IncomeSource(
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
  final remainder = PendingIncome(
    source: salary,
    occurrence: IncomeOccurrence(
      id: 'remainder-occurrence',
      incomeSourceId: 'salary-source',
      scheduledOn: PlainDate.today(),
      expectedAmountMinor: 400000,
      status: IncomeOccurrenceStatus.pending,
      remainderOfOccurrenceId: 'salary-occurrence',
    ),
  );
  const fullEstimate = SalaryEstimate(
    periodStart: PlainDate(2026, 6, 1),
    periodEnd: PlainDate(2026, 6, 30),
    expectedPaymentDate: PlainDate(2026, 7, 5),
    currencyCode: 'EGP',
    baseSalaryMinor: 4000000,
    dayRateMinor: 133333,
    hourRateMinor: 16667,
    extraDayUnitsHundredths: 100,
    extraDayAmountMinor: 300000,
    holidayCount: 0,
    holidayAmountMinor: 0,
    overtimeMinutes: 240,
    overtimeAmountMinor: 100000,
    bonusesMinor: 0,
    deductionsMinor: 0,
    warnings: [],
  );

  testWidgets('the pending banner shows only the remaining amount', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
          pendingIncomeProvider.overrideWith((ref) async => [remainder]),
          pendingRecurringProvider.overrideWith(
            (ref) async => const <PendingRecurring>[],
          ),
          pendingSalaryEstimateProvider.overrideWith(
            (ref, key) async => fullEstimate,
          ),
          cashFlowSummaryProvider.overrideWith(
            (ref, range) async => const <CashFlowSummary>[],
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

    const remaining = Money(minor: 400000, currencyCode: 'EGP');
    const owedInFull = Money(minor: 4400000, currencyCode: 'EGP');
    expect(
      find.textContaining('Salary — remaining · ${remaining.format()}'),
      findsOneWidget,
    );
    expect(find.textContaining(owedInFull.format()), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
