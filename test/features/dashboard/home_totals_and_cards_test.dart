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
  final homeDues = HomeDueSummary([
    HomeDueObligation(
      id: 'statement-1',
      kind: HomeDueObligationKind.cardStatement,
      sourceAccountId: 'card-1',
      sourceName: 'Everyday Card',
      maskedIdentifier: '4242',
      relatedId: 'statement-1',
      dueOn: PlainDate.today().addDays(2),
      currencyCode: 'EGP',
      remainingMinor: 100000,
      minimumDueMinor: 25000,
      paidMinor: 0,
      status: 'upcoming',
      title: 'Everyday Card — Statement due',
      sortRank: 2,
      details: const {
        'items': [
          {
            'title': 'Groceries',
            'occurred_on': '2026-08-01',
            'amount_minor': 100000,
          },
        ],
      },
    ),
    HomeDueObligation(
      id: 'recurring-1',
      kind: HomeDueObligationKind.recurringExpense,
      sourceAccountId: 'wallet',
      sourceName: 'Internet',
      relatedId: 'rule-1',
      dueOn: PlainDate.today().addDays(4),
      currencyCode: 'EGP',
      remainingMinor: 50000,
      minimumDueMinor: 50000,
      paidMinor: 0,
      status: 'upcoming',
      title: 'Internet — Recurring payment',
      sortRank: 2,
      details: const {'frequency': 'monthly'},
    ),
  ]);

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
          pendingIncomeProvider.overrideWith(
            (ref) async => const <PendingIncome>[],
          ),
          pendingRecurringProvider.overrideWith(
            (ref) async => const <PendingRecurring>[],
          ),
          homeCurrentMonthObligationsProvider.overrideWith(
            (ref) async => homeDues,
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

  Future<void> revealCards(WidgetTester tester) => tester.dragUntilVisible(
    find.byKey(const Key('home-credit-card-carousel')),
    find.byKey(const Key('home-dashboard-scroll')),
    const Offset(0, -180),
  );

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
    await revealCards(tester);

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
    expect(find.textContaining(earliestOnly.format()), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Next due sits between the balance and cards', (tester) async {
    await pumpHome(tester);

    // The card appears after the Balance/Next due content in the scroll flow.
    expect(find.text('Next due').first, findsOneWidget);
    await revealCards(tester);
    expect(find.text('Cards'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calculate opens the itemized Due impact bottom sheet', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('home-next-due-calculate')));
    await tester.pumpAndSettle();

    expect(find.text('Due impact'), findsOneWidget);
    expect(find.text('Everyday Card — Statement due'), findsWidgets);
    expect(find.text('Internet — Recurring payment'), findsWidgets);
    expect(find.byKey(const Key('home-due-pay-from-account')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-due-detail-statement-1')));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
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
    await revealCards(tester);

    expect(homeCardColor(tester), chosen);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card without a colour keeps the brand surface', (
    tester,
  ) async {
    await pumpHome(tester);
    await revealCards(tester);

    expect(homeCardColor(tester), isNot(FacilitySwatches.values[5]));
    expect(tester.takeException(), isNull);
  });
}
