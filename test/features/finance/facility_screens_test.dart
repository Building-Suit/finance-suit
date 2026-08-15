import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/account_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/facility_payment_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/installment_purchase_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/money_screen.dart';
import 'package:work_tracker/features/finance/presentation/widgets/facility_due_breakdown_widgets.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

const _wallet = AccountBalance(
  accountId: 'asset-1',
  name: 'Main Wallet',
  accountType: AccountType.cash,
  currencyCode: 'EGP',
  isDefault: true,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 1000000,
  balanceMinor: 947000,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 53000,
);

const _dollarWallet = AccountBalance(
  accountId: 'asset-2',
  name: 'Dollar Wallet',
  accountType: AccountType.cash,
  currencyCode: 'USD',
  isDefault: false,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 100000,
  balanceMinor: 100000,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 0,
);

const _visaBalanceRow = AccountBalance(
  accountId: 'facility-1',
  name: 'Visa Card',
  accountType: AccountType.creditCard,
  currencyCode: 'EGP',
  isDefault: false,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 0,
  balanceMinor: -238000,
  totalIncomingMinor: 33000,
  totalOutgoingMinor: 271000,
);

final _visa = CreditFacilitySummary.fromJson(const {
  'account_id': 'facility-1',
  'name': 'Visa Card',
  'account_type': 'credit_card',
  'currency_code': 'EGP',
  'is_archived': false,
  'notes': null,
  'opening_owed_minor': 0,
  'credit_limit_minor': 500000,
  'statement_day': 5,
  'default_due_day': 10,
  'last_four_digits': '1234',
  'reminder_lead_days': 3,
  'outstanding_minor': 238000,
  'available_credit_minor': 262000,
  'utilization_basis_points': 4760,
  'due_now_minor': 18000,
  'overdue_minor': 10000,
  'next_due_on': '2026-08-10',
  'next_due_amount_minor': 10000,
  'active_plan_count': 2,
});

final _fridgePlan = InstallmentPlan.fromJson(const {
  'id': 'plan-1',
  'account_id': 'facility-1',
  'title': 'Fridge',
  'category_id': 'cat-1',
  'purchased_on': '2026-07-01',
  'first_due_on': '2026-07-10',
  'installment_count': 12,
  'purchase_price_minor': 120000,
  'down_payment_minor': 0,
  'financed_principal_minor': 120000,
  'financing_fees_minor': 0,
  'total_payable_minor': 120000,
  'currency_code': 'EGP',
  'status': 'active',
  'paid_minor': 10000,
  'remaining_minor': 110000,
  'next_due_on': '2026-08-10',
  'next_due_amount_minor': 10000,
  'notes': null,
});

final _overdueDue = InstallmentDue.fromJson(const {
  'id': 'due-1',
  'plan_id': 'plan-1',
  'account_id': 'facility-1',
  'sequence_number': 2,
  'due_on': '2026-08-01',
  'amount_minor': 10000,
  'currency_code': 'EGP',
  'plan_title': 'Fridge',
  'plan_status': 'active',
  'paid_minor': 0,
  'remaining_minor': 10000,
  'due_status': 'overdue',
});

final _upcomingDue = InstallmentDue.fromJson(const {
  'id': 'due-2',
  'plan_id': 'plan-1',
  'account_id': 'facility-1',
  'sequence_number': 3,
  'due_on': '2026-09-10',
  'amount_minor': 10000,
  'currency_code': 'EGP',
  'plan_title': 'Fridge',
  'plan_status': 'active',
  'paid_minor': 0,
  'remaining_minor': 10000,
  'due_status': 'upcoming',
});

final _breakdown = FacilityDueBreakdown.fromJson(const {
  'account_id': 'facility-1',
  'account_type': 'credit_card',
  'currency_code': 'EGP',
  'as_of': '2026-08-10',
  'outstanding_minor': 238000,
  'total_due_minor': 23000,
  'paid_minor': 7500,
  'remaining_minor': 15500,
  'additional_balance_minor': 222500,
  'minimum_due_minor': 5000,
  'minimum_remaining_minor': 2500,
  'components': [
    {
      'component_type': 'installment_due',
      'component_id': 'due-1',
      'plan_id': 'plan-1',
      'title': 'Fridge',
      'activity_kind': 'installment_due',
      'sequence_number': 2,
      'installment_count': 12,
      'occurred_on': '2026-08-01',
      'amount_minor': 10000,
      'paid_minor': 0,
      'remaining_minor': 10000,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-1',
      'cycle_id': 'cycle-1',
      'transaction_id': 'tx-1',
      'title': 'OpenAI',
      'activity_kind': 'ordinary_expense',
      'occurred_on': '2026-07-20',
      'amount_minor': 5000,
      'paid_minor': 0,
      'remaining_minor': 5000,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-2',
      'cycle_id': 'cycle-1',
      'transaction_id': 'tx-2',
      'title': 'Solidarity insurance',
      'activity_kind': 'fee_charge',
      'fee_type': 'insurance',
      'occurred_on': '2026-07-21',
      'amount_minor': 3000,
      'paid_minor': 2500,
      'remaining_minor': 500,
      'payment_status': 'partially_paid',
      'scope': 'current',
    },
    {
      'component_type': 'statement_item',
      'component_id': 'item-3',
      'cycle_id': 'cycle-1',
      'transaction_id': 'tx-3',
      'title': 'Netflix',
      'activity_kind': 'ordinary_expense',
      'occurred_on': '2026-07-22',
      'amount_minor': 5000,
      'paid_minor': 5000,
      'remaining_minor': 0,
      'payment_status': 'paid',
      'scope': 'current',
    },
  ],
});

const _expenseCategory = TransactionCategory(
  id: 'cat-1',
  name: 'Shopping',
  kind: CategoryKind.expense,
  icon: 'category',
  sortOrder: 0,
  isArchived: false,
);

List<dynamic> _baseOverrides({
  List<CreditFacilitySummary>? facilities,
  List<AccountBalance>? accounts,
}) {
  final facilityList = facilities ?? [_visa];
  final accountList = accounts ?? [_wallet, _dollarWallet, _visaBalanceRow];
  return [
    accountBalancesProvider.overrideWith(
      (ref) async => accountList.where((a) => !a.isArchived).toList(),
    ),
    allAccountBalancesProvider.overrideWith((ref) async => accountList),
    creditFacilitiesProvider.overrideWith(
      (ref) async => facilityList.where((f) => !f.isArchived).toList(),
    ),
    allCreditFacilitiesProvider.overrideWith((ref) async => facilityList),
    pendingRecurringProvider.overrideWith(
      (ref) async => const <PendingRecurring>[],
    ),
    installmentPlansProvider.overrideWith(
      (ref, accountId) async => [_fridgePlan],
    ),
    installmentDuesProvider.overrideWith(
      (ref, accountId) async => [_overdueDue, _upcomingDue],
    ),
    transactionsPageProvider.overrideWith(
      (ref, query) async => const TransactionPage(items: [], hasMore: false),
    ),
    heldAmountsProvider.overrideWith((ref) async => const <HeldAmount>[]),
    categoriesProvider.overrideWith(
      (ref, kind) async =>
          kind == CategoryKind.expense ? [_expenseCategory] : const [],
    ),
    feeRulesProvider.overrideWith(
      (ref, accountId) async => const <CardFeeRule>[],
    ),
    facilityDueBreakdownProvider.overrideWith((ref, args) async => _breakdown),
    paymentAllocationsProvider.overrideWith(
      (ref, transactionId) async => const <FacilityPaymentAllocationDetail>[],
    ),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<CreditFacilitySummary>? facilities,
  List<AccountBalance>? accounts,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._baseOverrides(facilities: facilities, accounts: accounts).cast(),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('money screen', () {
    testWidgets('separates cash accounts from credit facilities', (
      tester,
    ) async {
      await _pump(tester, const MoneyScreen());

      expect(find.text('Cash & bank'), findsOneWidget);
      expect(find.text('Credit & installments'), findsOneWidget);
      final tile = find.byKey(const Key('facility-tile-facility-1'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('Amount owed')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Available credit'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Next due 2026-08-10'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('Overdue')),
        findsOneWidget,
      );
      // The liability never renders in the asset list as spendable cash.
      expect(find.text('Visa Card'), findsOneWidget);
    });
  });

  group('account form', () {
    testWidgets('selecting a liability type swaps in facility fields', (
      tester,
    ) async {
      await _pump(tester, const AccountFormScreen());

      expect(find.byKey(const Key('facility-credit-limit')), findsNothing);
      expect(find.text('Allow negative balance'), findsOneWidget);

      // Ten account types trigger the searchable sheet; filter to the
      // liability option instead of scrolling the lazy list.
      await tester.tap(find.text('Current balance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Credit Card');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit Card').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('facility-credit-limit')), findsOneWidget);
      expect(find.byKey(const Key('facility-due-day')), findsOneWidget);
      expect(
        find.byKey(const Key('facility-statement-close-mode')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('facility-statement-day')), findsNothing);
      expect(
        find.byKey(const Key('facility-installment-due-day')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('facility-grace-period-days')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('facility-interest-state-CardRuleState.unknown'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('facility-last-four')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('facility-reminder-days-3')),
        findsOneWidget,
      );
      // The opening-owed input is gone: new facilities start at zero debt.
      expect(find.text('Opening amount owed'), findsNothing);
      expect(find.text('Opening balance'), findsNothing);
      expect(find.text('Allow negative balance'), findsNothing);

      // BNPL hides the credit-card-only fields.
      await tester.tap(find.text('Credit Card').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'BNPL');
      await tester.pumpAndSettle();
      await tester.tap(find.text('BNPL / Finance Company').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('facility-statement-day')), findsNothing);
      expect(find.byKey(const Key('facility-last-four')), findsNothing);
    });

    testWidgets('credit cards expose the minimum payment method', (
      tester,
    ) async {
      await _pump(tester, const AccountFormScreen());

      await tester.tap(find.text('Current balance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Credit Card');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Credit Card').last);
      await tester.pumpAndSettle();

      final minMethod = find.byKey(
        const ValueKey('facility-min-method-MinPaymentMethod.full'),
      );
      expect(minMethod, findsOneWidget);
      expect(find.byKey(const Key('facility-min-fixed')), findsNothing);
      expect(find.byKey(const Key('facility-min-percent')), findsNothing);

      await tester.ensureVisible(minMethod);
      await tester.tap(minMethod);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Greater of fixed or percent').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('facility-min-fixed')), findsOneWidget);
      expect(find.byKey(const Key('facility-min-percent')), findsOneWidget);
      expect(
        find.byKey(const Key('facility-min-include-installments')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('facility-min-include-bank-fees')),
        findsOneWidget,
      );
    });
  });

  group('card fee rules', () {
    testWidgets('detail screen lists fees and opens the fee dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
      );

      // The fee section sits below the fold of the lazy detail list.
      await tester.scrollUntilVisible(
        find.byKey(const Key('fee-rule-add')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Card fees'), findsOneWidget);
      expect(find.textContaining('No fees configured'), findsOneWidget);

      await tester.tap(find.byKey(const Key('fee-rule-add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fee-rule-name')), findsOneWidget);
      expect(find.byKey(const Key('fee-rule-amount')), findsOneWidget);
      expect(find.byKey(const Key('fee-rule-percent')), findsNothing);

      // The percent mode swaps the fixed amount for a rate and its basis.
      await tester.tap(find.byKey(const Key('fee-rule-percent-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fee-rule-amount')), findsNothing);
      expect(find.byKey(const Key('fee-rule-percent')), findsOneWidget);

      // An empty name or percent blocks the save.
      await tester.tap(find.byKey(const Key('fee-rule-submit')));
      await tester.pumpAndSettle();
      expect(find.text('This field is required.'), findsWidgets);
    });
  });

  group('installment purchase form', () {
    testWidgets('shows the empty state when no facility exists', (
      tester,
    ) async {
      await _pump(
        tester,
        const InstallmentPurchaseScreen(),
        facilities: const <CreditFacilitySummary>[],
      );
      expect(find.text('No credit card or BNPL accounts yet'), findsOneWidget);
      expect(find.text('Add credit account'), findsOneWidget);
    });

    testWidgets('previews the exact schedule and blocks over-limit saves', (
      tester,
    ) async {
      await _pump(
        tester,
        const InstallmentPurchaseScreen(accountId: 'facility-1'),
      );

      await tester.enterText(
        find.byKey(const Key('purchase-merchant')),
        'Fridge',
      );
      await tester.enterText(find.byKey(const Key('purchase-price')), '1000');
      await tester.enterText(find.byKey(const Key('purchase-count')), '3');
      await tester.pumpAndSettle();

      final preview = find.byKey(const Key('purchase-preview'));
      expect(preview, findsOneWidget);
      // 1000.00 over 3 -> 333.34 + 333.33 + 333.33.
      expect(
        find.descendant(of: preview, matching: find.textContaining('333.34')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.textContaining('333.33')),
        findsNWidgets(2),
      );
      expect(find.byKey(const Key('purchase-over-limit')), findsNothing);

      final importToggle = find.byKey(const Key('purchase-import-toggle'));
      await tester.ensureVisible(importToggle);
      await tester.tap(importToggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('purchase-import-as-of')), findsOneWidget);
      expect(find.byKey(const Key('purchase-paid-through')), findsOneWidget);
      expect(find.byKey(const Key('purchase-current-posted')), findsOneWidget);
      expect(
        find.byKey(const Key('purchase-bank-outstanding')),
        findsOneWidget,
      );

      // Available credit is 2,620.00 — a 5,000.00 purchase must be blocked.
      await tester.enterText(find.byKey(const Key('purchase-price')), '5000');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('purchase-over-limit')), findsOneWidget);
    });
  });

  group('facility payment form', () {
    testWidgets(
      'filters sources to same-currency assets and shows the checklist',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          const FacilityPaymentScreen(accountId: 'facility-1'),
        );

        // The three presets and the selectable checklist are present; only
        // actual current components appear — no future installments.
        expect(find.byKey(const Key('payment-chip-next')), findsOneWidget);
        expect(find.byKey(const Key('payment-chip-minimum')), findsOneWidget);
        expect(find.byKey(const Key('payment-chip-full')), findsOneWidget);
        final checklist = find.byKey(const Key('payment-checklist'));
        expect(checklist, findsOneWidget);
        expect(
          find.byKey(const ValueKey('payment-row-installment_due:due-1')),
          findsOneWidget,
        );
        expect(find.textContaining('2026-09-10'), findsNothing);

        // Source picker: EGP asset yes, USD asset no, and the facility
        // itself appears only in the facility selector above.
        await tester.tap(find.text('Pay from'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Main Wallet'), findsWidgets);
        expect(find.textContaining('Dollar Wallet'), findsNothing);
        expect(find.textContaining('Visa Card ('), findsOneWidget);
      },
    );

    testWidgets('selection drives the Amount field', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const FacilityPaymentScreen(accountId: 'facility-1'));

      final amountField = find.byKey(const Key('payment-amount'));
      final dueRow = find.byKey(
        const ValueKey('payment-row-installment_due:due-1'),
      );
      final itemRow = find.byKey(
        const ValueKey('payment-row-statement_item:item-1'),
      );

      await tester.tap(dueRow);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(amountField).controller!.text,
        '100.00',
      );

      await tester.tap(itemRow);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(amountField).controller!.text,
        '150.00',
      );

      await tester.tap(dueRow);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(amountField).controller!.text,
        '50.00',
      );
    });

    testWidgets('minimum preset selects exactly the server minimum', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const FacilityPaymentScreen(accountId: 'facility-1'));

      await tester.tap(find.byKey(const Key('payment-chip-minimum')));
      await tester.pumpAndSettle();
      // minimum_remaining_minor = 2500 → 25.00, allocated as a visible
      // partial amount on the oldest installment due.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('payment-amount')))
            .controller!
            .text,
        '25.00',
      );
      expect(find.textContaining('Pay 25.00'), findsOneWidget);
    });

    testWidgets('full outstanding includes the explicit balance row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const FacilityPaymentScreen(accountId: 'facility-1'));

      await tester.tap(find.byKey(const Key('payment-chip-full')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('payment-amount')))
            .controller!
            .text,
        '2,380.00',
      );
      expect(
        find.byKey(const ValueKey('payment-row-facility-balance')),
        findsOneWidget,
      );
    });

    testWidgets('a fully paid item is not selectable again', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const FacilityPaymentScreen(accountId: 'facility-1'));

      // Netflix is paid: rendered as a static breakdown row, no checkbox.
      expect(
        find.byKey(const ValueKey('payment-row-statement_item:item-3')),
        findsNothing,
      );
      expect(find.text('Netflix'), findsOneWidget);
    });

    testWidgets('renders in Arabic at 320x480 without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const FacilityPaymentScreen(accountId: 'facility-1'),
        locale: const Locale('ar'),
      );
      expect(find.byKey(const Key('payment-checklist')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('due breakdown', () {
    testWidgets('shows totals with paid, partial, and unpaid states', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: DueBreakdownList(breakdown: _breakdown),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total due'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Left to pay'), findsOneWidget);

      // Fully paid rows stay visible, muted and struck through.
      final netflix = tester.widget<Text>(find.text('Netflix'));
      expect(netflix.style?.decoration, TextDecoration.lineThrough);

      // Partial rows show paid/total and remaining, never struck through.
      final insurance = tester.widget<Text>(find.text('Solidarity insurance'));
      expect(insurance.style?.decoration, isNot(TextDecoration.lineThrough));
      expect(find.textContaining('Paid 25.00'), findsOneWidget);
      expect(find.textContaining('left'), findsOneWidget);

      // Unpaid rows are plain.
      final openai = tester.widget<Text>(find.text('OpenAI'));
      expect(openai.style?.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('facility detail embeds the due breakdown card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
      );
      expect(find.byKey(const Key('facility-due-breakdown')), findsOneWidget);
    });
  });

  group('facility detail', () {
    testWidgets('shows summary figures, dues, and plans', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
      );

      expect(find.text('Amount owed'), findsOneWidget);
      expect(find.textContaining('Available credit'), findsWidgets);
      expect(find.byKey(const Key('facility-add-purchase')), findsOneWidget);
      expect(find.byKey(const Key('facility-make-payment')), findsOneWidget);
      expect(find.text('Upcoming installments'), findsOneWidget);
      expect(find.textContaining('Fridge'), findsWidgets);
      expect(find.text('Installment plans'), findsOneWidget);
    });
  });

  group('right-to-left', () {
    testWidgets('facility tile renders in Arabic without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const MoneyScreen(), locale: const Locale('ar'));
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.byType(FacilityTile), findsOneWidget);
      expect(find.text('المبلغ المستحق'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
