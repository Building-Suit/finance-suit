import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/facility_payment_screen.dart';
import 'package:work_tracker/features/finance/presentation/widgets/facility_due_breakdown_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _MockFinanceRepository extends Mock implements FinanceRepository {}

const _wallet = AccountBalance(
  accountId: 'asset-1',
  name: 'Main Wallet',
  accountType: AccountType.cash,
  currencyCode: 'EGP',
  isDefault: true,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 1000000,
  balanceMinor: 1000000,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 0,
);

const _valuBalanceRow = AccountBalance(
  accountId: 'bnpl-1',
  name: 'ValU',
  accountType: AccountType.bnpl,
  currencyCode: 'EGP',
  isDefault: false,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 0,
  balanceMinor: -275000,
  totalIncomingMinor: 0,
  totalOutgoingMinor: 275000,
);

/// A BNPL facility whose next due is the total owed on one date, exactly as
/// `credit_facility_summaries` reports it.
final _valu = CreditFacilitySummary.fromJson(const {
  'account_id': 'bnpl-1',
  'name': 'ValU',
  'account_type': 'bnpl',
  'currency_code': 'EGP',
  'is_archived': false,
  'notes': null,
  'opening_owed_minor': 0,
  'credit_limit_minor': 2000000,
  'statement_day': null,
  'default_due_day': 5,
  'last_four_digits': null,
  'reminder_lead_days': 3,
  'outstanding_minor': 275000,
  'available_credit_minor': 1725000,
  'utilization_basis_points': 1375,
  'due_now_minor': 0,
  'overdue_minor': 0,
  'next_due_on': '2026-09-05',
  'next_due_amount_minor': 275000,
  'active_plan_count': 1,
});

/// Two ordinary purchases and one installment all fall due on the same day,
/// plus a partially paid purchase — the shape "Pay next due" must handle.
final _bnplBreakdown = FacilityDueBreakdown.fromJson(const {
  'account_id': 'bnpl-1',
  'account_type': 'bnpl',
  'currency_code': 'EGP',
  'as_of': '2026-09-05',
  'outstanding_minor': 275000,
  'total_due_minor': 290000,
  'paid_minor': 15000,
  'remaining_minor': 275000,
  'additional_balance_minor': 0,
  'minimum_due_minor': null,
  'minimum_remaining_minor': null,
  'components': [
    {
      'component_type': 'installment_due',
      'component_id': 'due-1',
      'plan_id': 'plan-1',
      'title': 'Laptop',
      'activity_kind': 'installment_due',
      'sequence_number': 4,
      'installment_count': 12,
      'occurred_on': '2026-09-05',
      'due_on': '2026-09-05',
      'amount_minor': 75000,
      'paid_minor': 0,
      'remaining_minor': 75000,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'bnpl_purchase',
      'component_id': 'ob-1',
      'transaction_id': 'tx-1',
      'title': 'Noon order',
      'activity_kind': 'bnpl_purchase',
      'occurred_on': '2026-08-16',
      'due_on': '2026-09-05',
      'amount_minor': 125000,
      'paid_minor': 0,
      'remaining_minor': 125000,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'bnpl_purchase',
      'component_id': 'ob-2',
      'transaction_id': 'tx-2',
      'title': 'Grocery run',
      'activity_kind': 'bnpl_purchase',
      'occurred_on': '2026-08-20',
      'due_on': '2026-09-05',
      'amount_minor': 50000,
      'paid_minor': 0,
      'remaining_minor': 50000,
      'payment_status': 'unpaid',
      'scope': 'current',
    },
    {
      'component_type': 'bnpl_purchase',
      'component_id': 'ob-3',
      'transaction_id': 'tx-3',
      'title': 'Sneakers',
      'activity_kind': 'bnpl_purchase',
      'occurred_on': '2026-07-28',
      'due_on': '2026-09-05',
      'amount_minor': 40000,
      'paid_minor': 15000,
      'remaining_minor': 25000,
      'payment_status': 'partially_paid',
      'scope': 'current',
    },
  ],
});

final _repayment = FacilityActivityItem.fromJson(const {
  'transaction_id': 'pay-1',
  'account_id': 'bnpl-1',
  'activity_kind': 'facility_repayment',
  'transaction_kind': 'transfer',
  'occurred_on': '2026-09-05',
  'amount_minor': 175000,
  'currency_code': 'EGP',
  'is_settled': false,
  'title': 'Repayment',
});

final _appliedTo = [
  FacilityPaymentAllocationDetail.fromJson(const {
    'payment_transaction_id': 'pay-1',
    'component_type': 'bnpl_purchase',
    'component_id': 'ob-1',
    'title': 'Noon order',
    'activity_kind': 'bnpl_purchase',
    'detail_on': '2026-09-05',
    'amount_minor': 125000,
    'currency_code': 'EGP',
  }),
  FacilityPaymentAllocationDetail.fromJson(const {
    'payment_transaction_id': 'pay-1',
    'component_type': 'installment_due',
    'component_id': 'due-1',
    'title': 'Laptop',
    'activity_kind': 'installment_due',
    'sequence_number': 4,
    'detail_on': '2026-09-05',
    'amount_minor': 50000,
    'currency_code': 'EGP',
  }),
];

const _expenseCategory = TransactionCategory(
  id: 'cat-1',
  name: 'Shopping',
  kind: CategoryKind.expense,
  icon: 'category',
  sortOrder: 0,
  isArchived: false,
);

List<dynamic> _overrides({FinanceRepository? repository}) => [
  if (repository != null)
    financeRepositoryProvider.overrideWithValue(repository),
  accountBalancesProvider.overrideWith(
    (ref) async => const [_wallet, _valuBalanceRow],
  ),
  allAccountBalancesProvider.overrideWith(
    (ref) async => const [_wallet, _valuBalanceRow],
  ),
  creditFacilitiesProvider.overrideWith((ref) async => [_valu]),
  allCreditFacilitiesProvider.overrideWith((ref) async => [_valu]),
  pendingRecurringProvider.overrideWith(
    (ref) async => const <PendingRecurring>[],
  ),
  installmentPlansProvider.overrideWith(
    (ref, accountId) async => const <InstallmentPlan>[],
  ),
  installmentDuesProvider.overrideWith(
    (ref, accountId) async => const <InstallmentDue>[],
  ),
  facilityActivityProvider.overrideWith((ref, accountId) async => [_repayment]),
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
  facilityDueBreakdownProvider.overrideWith(
    (ref, args) async => _bnplBreakdown,
  ),
  facilityMonthDueBreakdownProvider.overrideWith(
    (ref, args) async => _bnplBreakdown,
  ),
  paymentAllocationsProvider.overrideWith(
    (ref, transactionId) async => _appliedTo,
  ),
];

/// Routes the BNPL flows actually navigate to, so pushing from the Add
/// Purchase sheet is exercised instead of stubbed.
GoRouter _router({
  required Widget home,
  void Function(String location)? onPush,
}) {
  Widget probe(GoRouterState state) {
    onPush?.call(state.uri.toString());
    return Scaffold(body: Text('pushed ${state.uri}'));
  }

  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => home),
      GoRoute(path: '/money/tx/new', builder: (context, state) => probe(state)),
      GoRoute(
        path: '/money/facilities/purchase',
        builder: (context, state) => probe(state),
      ),
      GoRoute(
        path: '/money/facilities/pay',
        builder: (context, state) => probe(state),
      ),
      GoRoute(
        path: '/money/facilities/:id',
        builder: (context, state) => probe(state),
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  FinanceRepository? repository,
  void Function(String location)? onPush,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repository: repository).cast(),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _router(home: home, onPush: onPush),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      FacilityPaymentV2Draft(
        accountId: 'bnpl-1',
        sourceAccountId: 'asset-1',
        amountMinor: 0,
        paidOn: PlainDate(2026, 1, 1),
        allocations: const [],
      ),
    );
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('BNPL due breakdown', () {
    testWidgets('renders an ordinary purchase with its purchase and due date', (
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
                child: DueBreakdownList(breakdown: _bnplBreakdown),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Noon order'), findsOneWidget);
      expect(
        find.text('Purchased 2026-08-16 · Due 2026-09-05'),
        findsOneWidget,
      );
      // Ordinary purchases group under Purchases, never under fees.
      expect(find.text('Purchases'), findsOneWidget);

      // The partially paid purchase shows its exact paid and remaining
      // amounts and is never struck through.
      final sneakers = tester.widget<Text>(find.text('Sneakers'));
      expect(sneakers.style?.decoration, isNot(TextDecoration.lineThrough));
      expect(
        find.textContaining('Paid 150.00 EGP / 400.00 EGP'),
        findsOneWidget,
      );
      expect(find.textContaining('250.00 EGP left'), findsOneWidget);
    });
  });

  group('Pay next due', () {
    testWidgets('selects every component owed on the earliest date', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const FacilityPaymentScreen(accountId: 'bnpl-1'));

      await tester.tap(find.byKey(const Key('payment-chip-next')));
      await tester.pumpAndSettle();

      // 1,250 + 500 + 750 + 250 remaining = 2,750.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('payment-amount')))
            .controller!
            .text,
        '2,750.00',
      );
    });

    testWidgets('BNPL hides the minimum preset it has no concept of', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, const FacilityPaymentScreen(accountId: 'bnpl-1'));
      expect(find.byKey(const Key('payment-chip-next')), findsOneWidget);
      expect(find.byKey(const Key('payment-chip-minimum')), findsNothing);
      expect(find.text('Pay next due'), findsOneWidget);
    });

    testWidgets('sends bnpl_purchase allocations to the payment RPC', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _MockFinanceRepository();
      FacilityPaymentV2Draft? sent;
      when(() => repository.payCreditFacilityV2(any())).thenAnswer((
        invocation,
      ) async {
        sent = invocation.positionalArguments.first as FacilityPaymentV2Draft;
        return const Ok('pay-2');
      });

      await _pump(
        tester,
        const FacilityPaymentScreen(accountId: 'bnpl-1'),
        repository: repository,
      );

      await tester.tap(
        find.byKey(const ValueKey('payment-row-bnpl_purchase:ob-1')),
      );
      await tester.pumpAndSettle();
      final sourceField = find.byKey(const ValueKey('payment-source-null'));
      await tester.ensureVisible(sourceField);
      await tester.pumpAndSettle();
      await tester.tap(sourceField);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Main Wallet').last);
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Make payment');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!.allocations.single.type, 'bnpl_purchase');
      expect(sent!.allocations.single.id, 'ob-1');
      expect(sent!.allocations.single.amountMinor, 125000);
      expect(sent!.amountMinor, 125000);
    });
  });

  group('payment history', () {
    testWidgets('shows the exact persisted BNPL allocation', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'bnpl-1'),
      );

      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity-actions-pay-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('activity-action-pay-1')));
      await tester.pumpAndSettle();

      expect(find.text('Applied to'), findsOneWidget);
      expect(find.text('Noon order'), findsWidgets);
      expect(find.text('Laptop'), findsWidgets);
      expect(find.byKey(const Key('payment-detail-reverse')), findsOneWidget);
    });
  });

  group('Add purchase', () {
    testWidgets('BNPL offers normal and installment purchases', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pushed = <String>[];
      await _pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'bnpl-1'),
        onPush: pushed.add,
      );

      await tester.tap(find.byKey(const Key('facility-add-purchase')));
      await tester.pumpAndSettle();
      expect(find.text('Normal purchase'), findsOneWidget);
      expect(find.text('Installment purchase'), findsOneWidget);

      // Normal opens the canonical expense form with this facility already
      // selected — not a second ordinary-expense form.
      await tester.tap(find.byKey(const Key('facility-purchase-normal')));
      await tester.pumpAndSettle();
      expect(pushed.single, '/money/tx/new?kind=expense&accountId=bnpl-1');
    });

    testWidgets('installment keeps the existing plan route', (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pushed = <String>[];
      await _pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'bnpl-1'),
        onPush: pushed.add,
      );

      await tester.tap(find.byKey(const Key('facility-add-purchase')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('facility-purchase-installment')));
      await tester.pumpAndSettle();
      expect(pushed.single, '/money/facilities/purchase?accountId=bnpl-1');
    });
  });

  group('Home', () {
    test(
      'a BNPL obligation exposes purchase components, not statement items',
      () {
        final obligation = HomeDueObligation.fromJson(const {
          'obligation_id': 'ob-1',
          'obligation_kind': 'bnpl_purchase',
          'source_account_id': 'bnpl-1',
          'source_name': 'ValU',
          'due_on': '2026-09-05',
          'currency_code': 'EGP',
          'remaining_minor': 175000,
          'paid_minor': 0,
          'details': {
            'items': [
              {
                'id': 'ob-1',
                'kind': 'purchase',
                'title': 'Noon order',
                'occurred_on': '2026-08-16',
                'due_on': '2026-09-05',
                'amount_minor': 125000,
                'paid_minor': 0,
                'remaining_minor': 125000,
                'payment_status': 'unpaid',
              },
            ],
            'installments': <dynamic>[],
          },
        });
        final component = obligation.components.single;
        expect(component.type, FacilityComponentType.bnplPurchase);
        expect(component.occurredOn?.toIso(), '2026-08-16');
        expect(component.dueOn?.toIso(), '2026-09-05');
        expect(
          groupDueComponents([component]).keys.single,
          DueComponentGroup.purchases,
        );
      },
    );
  });

  group('right-to-left', () {
    testWidgets('the BNPL pay checklist renders in Arabic without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const FacilityPaymentScreen(accountId: 'bnpl-1'),
        locale: const Locale('ar'),
      );
      expect(find.byKey(const Key('payment-checklist')), findsOneWidget);
      expect(find.text('سداد الاستحقاق التالي'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment-row-bnpl_purchase:ob-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
