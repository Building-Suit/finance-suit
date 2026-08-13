import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Home treats borrowed money as its own thing: credit cards get a carousel
/// of their own and never move the total balance.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  const wallet = AccountBalance(
    accountId: 'wallet',
    name: 'Wallet',
    accountType: AccountType.cash,
    currencyCode: 'EGP',
    isDefault: true,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 500000,
    totalIncomingMinor: 500000,
    totalOutgoingMinor: 0,
  );
  // A liability account carrying debt: it must not subtract from the total.
  const cardAccount = AccountBalance(
    accountId: 'card-1',
    name: 'Everyday Card',
    accountType: AccountType.creditCard,
    currencyCode: 'EGP',
    isDefault: false,
    isArchived: false,
    allowNegativeBalance: true,
    openingBalanceMinor: 0,
    balanceMinor: 300000,
    totalIncomingMinor: 0,
    totalOutgoingMinor: 300000,
  );
  CreditFacilitySummary buildCard({String? colorHex}) => CreditFacilitySummary(
    accountId: 'card-1',
    name: 'Everyday Card',
    accountType: AccountType.creditCard,
    currencyCode: 'EGP',
    isArchived: false,
    openingOwedMinor: 0,
    creditLimitMinor: 5000000,
    defaultDueDay: 10,
    reminderLeadDays: 3,
    outstandingMinor: 300000,
    availableCreditMinor: 4700000,
    utilizationBasisPoints: 600,
    dueNowMinor: 0,
    overdueMinor: 0,
    activePlanCount: 1,
    statementDay: 25,
    lastFourDigits: '4242',
    nextDueOn: PlainDate.today().addDays(6),
    nextDueAmountMinor: 100000,
    upcomingDueMinor: 250000,
    colorHex: colorHex,
  );
  final card = buildCard();

  Future<void> pumpHome(
    WidgetTester tester, {
    CreditFacilitySummary? facility,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          accountBalancesProvider.overrideWith(
            (ref) async => const [wallet, cardAccount],
          ),
          allAccountBalancesProvider.overrideWith(
            (ref) async => const [wallet, cardAccount],
          ),
          creditFacilitiesProvider.overrideWith(
            (ref) async => [facility ?? card],
          ),
          homeUpcomingObligationsProvider.overrideWith(
            (ref) async => HomeDueSummary(
              today: PlainDate.today(),
              items: [
                HomeDueObligation(
                  id: 'statement-1',
                  kind: 'card_statement',
                  dueOn: PlainDate.today().addDays(6),
                  currencyCode: 'EGP',
                  remainingMinor: 100000,
                ),
              ],
            ),
          ),
          pendingIncomeProvider.overrideWith(
            (ref) async => const <PendingIncome>[],
          ),
          pendingRecurringProvider.overrideWith(
            (ref) async => const <PendingRecurring>[],
          ),
          homeCashFlowSummaryProvider.overrideWith(
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
  }

  testWidgets('the total balance ignores credit facilities', (tester) async {
    await pumpHome(tester);

    // 5,000.00 of cash stands alone; adding the card's 3,000.00 of debt
    // would have produced 8,000.00, and subtracting it 2,000.00.
    expect(find.textContaining('5,000.00'), findsWidgets);
    expect(find.textContaining('8,000.00'), findsNothing);
    expect(find.textContaining('2,000.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards get their own carousel with limit, owed, and dues', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byKey(const Key('home-credit-card-carousel')), findsOneWidget);
    expect(find.byKey(const Key('home-card-card-1')), findsOneWidget);

    const available = Money(minor: 4700000, currencyCode: 'EGP');
    const limit = Money(minor: 5000000, currencyCode: 'EGP');
    expect(
      find.text('${available.format()} / ${limit.format()}'),
      findsOneWidget,
    );

    // The owed line and the accumulated upcoming due, not the single
    // earliest installment.
    const owed = Money(minor: 300000, currencyCode: 'EGP');
    const upcoming = Money(minor: 250000, currencyCode: 'EGP');
    const earliestOnly = Money(minor: 100000, currencyCode: 'EGP');
    expect(find.textContaining(owed.format()), findsOneWidget);
    expect(find.textContaining(upcoming.format()), findsOneWidget);
    // The card continues to show the accumulated month total, while the new
    // dues section shows the exact earliest payment the user must make.
    expect(find.textContaining(earliestOnly.format()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards sit between the balance and the cash flow', (
    tester,
  ) async {
    await pumpHome(tester);

    // Home reads money-I-have, the next actionable payment, the complete
    // borrowing inventory, then how money moved.
    expect(find.text('Balance'), findsOneWidget);
    expect(find.byKey(const Key('home-due-thisMonth')), findsOneWidget);
    expect(find.byKey(const Key('home-credit-card-carousel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dues are aggregated without naming an account', (tester) async {
    await pumpHome(tester);

    final dues = find.byKey(const Key('home-dues-card'));
    expect(
      find.descendant(of: dues, matching: find.text('Payments due')),
      findsNothing,
    );
    expect(
      find.descendant(of: dues, matching: find.text('Everyday Card')),
      findsNothing,
    );
    expect(
      find.descendant(of: dues, matching: find.textContaining('1,000.00')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  Color homeCardColor(WidgetTester tester) => tester
      .widget<Card>(
        find
            .ancestor(
              of: find.byKey(const Key('home-card-card-1')),
              matching: find.byType(Card),
            )
            .first,
      )
      .color!;

  testWidgets('a card wears the colour the user picked for it', (tester) async {
    // A swatch distinct from the brand surface, so "unchanged" cannot pass
    // by coincidence.
    final chosen = FacilitySwatches.values[5];
    await pumpHome(
      tester,
      facility: buildCard(colorHex: FacilitySwatches.hexOf(chosen)),
    );

    expect(homeCardColor(tester), chosen);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card without a colour keeps the brand surface', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(homeCardColor(tester), isNot(FacilitySwatches.values[5]));
    expect(tester.takeException(), isNull);
  });
}
