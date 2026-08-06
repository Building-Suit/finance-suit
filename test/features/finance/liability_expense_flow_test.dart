import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/transaction_form_screen.dart';
import 'package:work_tracker/features/settings/domain/user_profile.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
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

const _archivedWallet = AccountBalance(
  accountId: 'asset-old',
  name: 'Old Wallet',
  accountType: AccountType.cash,
  currencyCode: 'EGP',
  isDefault: false,
  isArchived: true,
  allowNegativeBalance: false,
  openingBalanceMinor: 0,
  balanceMinor: 0,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 0,
);

const _visa = CreditFacilitySummary(
  accountId: 'card-1',
  name: 'Visa Card',
  accountType: AccountType.creditCard,
  currencyCode: 'EGP',
  isArchived: false,
  openingOwedMinor: 0,
  creditLimitMinor: 500000,
  defaultDueDay: 10,
  reminderLeadDays: 3,
  outstandingMinor: 100000,
  availableCreditMinor: 400000,
  utilizationBasisPoints: 2000,
  dueNowMinor: 0,
  overdueMinor: 0,
  activePlanCount: 0,
  statementDay: 5,
);

const _valu = CreditFacilitySummary(
  accountId: 'bnpl-1',
  name: 'Valu',
  accountType: AccountType.bnpl,
  currencyCode: 'EGP',
  isArchived: false,
  openingOwedMinor: 0,
  creditLimitMinor: 300000,
  defaultDueDay: 12,
  reminderLeadDays: 3,
  outstandingMinor: 0,
  availableCreditMinor: 300000,
  utilizationBasisPoints: 0,
  dueNowMinor: 0,
  overdueMinor: 0,
  activePlanCount: 0,
);

const _expenseCategory = TransactionCategory(
  id: 'cat-1',
  name: 'Shopping',
  kind: CategoryKind.expense,
  icon: 'category',
  sortOrder: 0,
  isArchived: false,
);

const _prefs = UserPreferences(
  currencyCode: 'EGP',
  timezone: 'Africa/Cairo',
  locale: 'en',
  weekStartsOn: 6,
  weekendDays: [5, 6],
  defaultHistoryDays: 30,
  onboardingCompleted: true,
);

FacilityActivityItem _activity(
  String id,
  String kind, {
  String accountId = 'card-1',
  bool settled = false,
  String? planId,
  String transactionKind = 'expense',
  String title = 'Groceries',
}) => FacilityActivityItem.fromJson({
  'transaction_id': id,
  'account_id': accountId,
  'activity_kind': kind,
  'transaction_kind': transactionKind,
  'occurred_on': '2026-08-01',
  'amount_minor': 25000,
  'currency_code': 'EGP',
  'is_settled': settled,
  'plan_id': planId,
  'category_id': 'cat-1',
  'title': title,
  'notes': null,
  'counterparty': null,
});

List<dynamic> _overrides({
  List<AccountBalance> accounts = const [_wallet],
  List<CreditFacilitySummary> facilities = const [_visa, _valu],
  List<FacilityActivityItem> activity = const [],
}) => [
  currentUserIdProvider.overrideWithValue('user-1'),
  accountBalancesProvider.overrideWith(
    (ref) async => accounts.where((a) => !a.isArchived).toList(),
  ),
  allAccountBalancesProvider.overrideWith((ref) async => accounts),
  creditFacilitiesProvider.overrideWith(
    (ref) async => facilities.where((f) => f.canFundPurchases).toList(),
  ),
  allCreditFacilitiesProvider.overrideWith((ref) async => facilities),
  categoriesProvider.overrideWith(
    (ref, kind) async =>
        kind == CategoryKind.expense ? [_expenseCategory] : const [],
  ),
  preferencesProvider.overrideWith((ref) async => _prefs),
  installmentPlansProvider.overrideWith(
    (ref, accountId) async => const <InstallmentPlan>[],
  ),
  installmentDuesProvider.overrideWith(
    (ref, accountId) async => const <InstallmentDue>[],
  ),
  statementSummariesProvider.overrideWith(
    (ref, accountId) async => const <CardStatementSummary>[],
  ),
  feeRulesProvider.overrideWith(
    (ref, accountId) async => const <CardFeeRule>[],
  ),
  facilityActivityProvider.overrideWith((ref, accountId) async => activity),
];

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<dynamic>? overrides,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: (overrides ?? _overrides()).cast(),
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

  group('expense account picker', () {
    testWidgets('Add Expense offers both credit cards and BNPL accounts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        const TransactionFormScreen(kind: TransactionKind.expense),
      );

      await tester.tap(find.text('Main Wallet'));
      await tester.pumpAndSettle();

      expect(find.text('Cash & bank'), findsOneWidget);
      expect(find.text('Credit & installments'), findsOneWidget);
      expect(find.textContaining('Visa Card'), findsOneWidget);
      expect(find.textContaining('Valu'), findsOneWidget);
      expect(find.textContaining('BNPL'), findsOneWidget);
    });

    testWidgets('Edit Expense offers both and preselects the credit card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final existing = FinancialTransaction(
        id: 'tx-1',
        kind: TransactionKind.expense,
        occurredOn: PlainDate.parse('2026-08-01'),
        amountMinor: 25000,
        currencyCode: 'EGP',
        sourceAccountId: 'card-1',
        categoryId: 'cat-1',
        title: 'Groceries',
      );
      await _pump(
        tester,
        TransactionFormScreen(
          kind: TransactionKind.expense,
          existing: existing,
        ),
      );

      // The card the charge belongs to is the selected value, not the
      // default wallet.
      expect(find.textContaining('Visa Card'), findsOneWidget);
      await tester.tap(find.textContaining('Visa Card'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Valu'), findsOneWidget);
      expect(find.textContaining('Main Wallet'), findsOneWidget);
    });

    testWidgets('Edit Expense preselects a BNPL account too', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final existing = FinancialTransaction(
        id: 'tx-2',
        kind: TransactionKind.expense,
        occurredOn: PlainDate.parse('2026-08-01'),
        amountMinor: 25000,
        currencyCode: 'EGP',
        sourceAccountId: 'bnpl-1',
        categoryId: 'cat-1',
      );
      await _pump(
        tester,
        TransactionFormScreen(
          kind: TransactionKind.expense,
          existing: existing,
        ),
      );

      expect(find.textContaining('Valu'), findsOneWidget);
    });

    testWidgets('an archived current account stays visible while editing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final existing = FinancialTransaction(
        id: 'tx-3',
        kind: TransactionKind.expense,
        occurredOn: PlainDate.parse('2026-08-01'),
        amountMinor: 25000,
        currencyCode: 'EGP',
        sourceAccountId: 'asset-old',
        categoryId: 'cat-1',
      );
      await _pump(
        tester,
        TransactionFormScreen(
          kind: TransactionKind.expense,
          existing: existing,
        ),
        overrides: _overrides(accounts: const [_wallet, _archivedWallet]),
      );

      expect(find.textContaining('Old Wallet'), findsOneWidget);
      expect(find.textContaining('unavailable'), findsOneWidget);
    });

    testWidgets('income never offers a liability account', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        const TransactionFormScreen(kind: TransactionKind.customIncome),
      );

      await tester.tap(find.text('Main Wallet'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Visa Card'), findsNothing);
      expect(find.textContaining('Valu'), findsNothing);
    });
  });

  group('facility related activity', () {
    Widget routerHost(List<dynamic> overrides) {
      final router = GoRouter(
        initialLocation: '/money/facilities/card-1',
        routes: [
          GoRoute(
            path: '/money/facilities/card-1',
            builder: (context, state) =>
                const CreditFacilityDetailScreen(accountId: 'card-1'),
          ),
          GoRoute(
            path: '/money/tx/edit',
            builder: (context, state) => TransactionFormScreen(
              kind: (state.extra! as FinancialTransaction).kind,
              existing: state.extra! as FinancialTransaction,
            ),
          ),
          GoRoute(
            path: '/money/facilities/purchase',
            builder: (context, state) => Scaffold(
              body: Text('plan editor ${state.uri.queryParameters['planId']}'),
            ),
          ),
        ],
      );
      return ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
    }

    testWidgets('an ordinary expense exposes Edit and opens that expense', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        routerHost(
          _overrides(activity: [_activity('tx-1', 'ordinary_expense')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Related activity'), findsOneWidget);
      await tester.tap(find.byKey(const Key('activity-actions-tx-1')));
      await tester.pumpAndSettle();
      expect(find.text('Edit transaction'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activity-action-tx-1')));
      await tester.pumpAndSettle();

      // The canonical editor opened on that transaction with the card
      // preselected, over the facility detail so Save returns to it.
      expect(find.text('Edit transaction'), findsWidgets);
      expect(find.textContaining('Visa Card'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('an installment purchase routes to the plan editor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        routerHost(
          _overrides(
            activity: [
              _activity(
                'tx-9',
                'installment_purchase',
                planId: 'plan-7',
                title: 'Fridge',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('activity-actions-tx-9')));
      await tester.pumpAndSettle();
      expect(find.text('Edit plan'), findsOneWidget);

      await tester.tap(find.byKey(const Key('activity-action-tx-9')));
      await tester.pumpAndSettle();
      expect(find.text('plan editor plan-7'), findsOneWidget);
    });

    testWidgets('a repayment offers reversal, never the expense editor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        routerHost(
          _overrides(
            activity: [
              _activity(
                'tx-5',
                'facility_repayment',
                transactionKind: 'transfer',
                title: 'Payment',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('activity-actions-tx-5')));
      await tester.pumpAndSettle();
      expect(find.text('Reverse payment'), findsOneWidget);
      expect(find.text('Edit transaction'), findsNothing);
    });

    testWidgets('a settled charge explains itself instead of editing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        routerHost(
          _overrides(
            activity: [_activity('tx-8', 'ordinary_expense', settled: true)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('activity-actions-tx-8')));
      await tester.pumpAndSettle();
      expect(find.text('Edit transaction'), findsNothing);

      await tester.tap(find.byKey(const Key('activity-action-tx-8')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('already on a paid statement'),
        findsOneWidget,
      );
    });
  });

  group('right-to-left', () {
    testWidgets('the grouped account picker fits a small Arabic viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const TransactionFormScreen(kind: TransactionKind.expense),
        locale: const Locale('ar'),
      );

      await tester.tap(find.text('Main Wallet'));
      await tester.pumpAndSettle();

      expect(find.text('النقد والبنوك'), findsOneWidget);
      expect(find.text('الائتمان والأقساط'), findsOneWidget);
      expect(find.textContaining('Valu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
