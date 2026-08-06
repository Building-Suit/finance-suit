import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// An account marked hide-from-home must vanish from the Home balance
/// section — name and amount both — while other accounts stay.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  const visible = AccountBalance(
    accountId: 'wallet',
    name: 'Wallet',
    accountType: AccountType.cash,
    currencyCode: 'EGP',
    isDefault: true,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 150000,
    totalIncomingMinor: 150000,
    totalOutgoingMinor: 0,
  );
  const hidden = AccountBalance(
    accountId: 'deposit-box',
    name: 'Deposit Box',
    accountType: AccountType.savings,
    currencyCode: 'EGP',
    isDefault: false,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 9000000,
    totalIncomingMinor: 9000000,
    totalOutgoingMinor: 0,
    hideFromHome: true,
  );

  testWidgets('a hidden account leaves the Home balance section', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          accountBalancesProvider.overrideWith(
            (ref) async => const [visible, hidden],
          ),
          allAccountBalancesProvider.overrideWith(
            (ref) async => const [visible, hidden],
          ),
          pendingIncomeProvider.overrideWith(
            (ref) async => const <PendingIncome>[],
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

    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Deposit Box'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('rows without the column parse as visible accounts', () {
    final json = {
      'account_id': 'a1',
      'name': 'Old Row',
      'account_type': 'cash',
      'currency_code': 'EGP',
      'is_default': false,
      'is_archived': false,
      'allow_negative_balance': false,
      'opening_balance_minor': 0,
      'balance_minor': 0,
      'total_incoming_minor': 0,
      'total_outgoing_minor': 0,
    };
    expect(AccountBalance.fromJson(json).hideFromHome, isFalse);
    expect(
      AccountBalance.fromJson({...json, 'hide_from_home': true}).hideFromHome,
      isTrue,
    );
  });
}
