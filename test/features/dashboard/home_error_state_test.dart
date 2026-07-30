import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
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
              (ref, range) async => const CashFlowSummary(
                incomeMinor: 10000,
                expensesMinor: 2500,
                allowancesMinor: 500,
                netMinor: 7000,
              ),
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
}
