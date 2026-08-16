import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/facility_payment_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The facility detail screen shows this month and next month as a swipeable
/// carousel, and each month can be paid on its own — next month even while
/// this month is still unpaid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final months = FacilityDueMonth.payable();
  final currentMonth = months.first;
  final nextMonth = months.last;

  final wallet = AccountBalance.fromJson(const {
    'account_id': 'wallet-1',
    'name': 'Main Wallet',
    'account_type': 'cash',
    'currency_code': 'EGP',
    'is_default': true,
    'is_archived': false,
    'allow_negative_balance': false,
    'opening_balance_minor': 0,
    'balance_minor': 5000000,
    'total_incoming_minor': 5000000,
    'total_outgoing_minor': 0,
  });

  final facility = CreditFacilitySummary.fromJson({
    'account_id': 'facility-1',
    'name': 'CIB',
    'account_type': 'credit_card',
    'currency_code': 'EGP',
    'is_archived': false,
    'notes': null,
    'opening_owed_minor': 0,
    'credit_limit_minor': 5000000,
    'statement_day': 10,
    'default_due_day': 25,
    'last_four_digits': '4242',
    'reminder_lead_days': 3,
    'outstanding_minor': 421259,
    'available_credit_minor': 4578741,
    'utilization_basis_points': 842,
    'due_now_minor': 261078,
    'overdue_minor': 0,
    'next_due_on': currentMonth.start.addDays(24).toIso(),
    'next_due_amount_minor': 261078,
    'active_plan_count': 1,
  });

  Map<String, dynamic> component({
    required String id,
    required String title,
    required String type,
    required String dueOn,
    required int amount,
    int paid = 0,
    String kind = 'ordinary_expense',
  }) => {
    'component_type': type,
    'component_id': id,
    'title': title,
    'activity_kind': kind,
    'occurred_on': dueOn,
    'due_on': dueOn,
    'amount_minor': amount,
    'paid_minor': paid,
    'remaining_minor': amount - paid,
    'payment_status': paid == 0
        ? 'unpaid'
        : paid >= amount
        ? 'paid'
        : 'partially_paid',
    'scope': 'current',
  };

  FacilityDueBreakdown breakdownFor(
    FacilityDueMonth month, {
    required List<Map<String, dynamic>> components,
  }) {
    final total = components.fold<int>(
      0,
      (a, c) => a + (c['amount_minor']! as int),
    );
    final paid = components.fold<int>(
      0,
      (a, c) => a + (c['paid_minor']! as int),
    );
    return FacilityDueBreakdown.fromJson({
      'account_id': 'facility-1',
      'account_type': 'credit_card',
      'currency_code': 'EGP',
      'as_of': month.start.toIso(),
      'month_start': month.start.toIso(),
      'month_end': month.end.toIso(),
      'outstanding_minor': 421259,
      'total_due_minor': total,
      'paid_minor': paid,
      'remaining_minor': total - paid,
      'additional_balance_minor': 0,
      'minimum_due_minor': 21063,
      'minimum_remaining_minor': 21063,
      'components': components,
    });
  }

  final currentBreakdown = breakdownFor(
    currentMonth,
    components: [
      component(
        id: 'due-current',
        title: 'Samsung Monitor',
        type: 'installment_due',
        dueOn: currentMonth.start.addDays(24).toIso(),
        amount: 200000,
        kind: 'installment_due',
      ),
      component(
        id: 'item-current',
        title: 'August Groceries',
        type: 'statement_item',
        dueOn: currentMonth.start.addDays(24).toIso(),
        amount: 61078,
      ),
    ],
  );
  final nextBreakdown = breakdownFor(
    nextMonth,
    components: [
      component(
        id: 'due-next',
        title: 'September installment',
        type: 'installment_due',
        dueOn: nextMonth.start.addDays(24).toIso(),
        amount: 160181,
        kind: 'installment_due',
      ),
    ],
  );

  List<dynamic> overrides({
    FacilityDueBreakdown? current,
    FacilityDueBreakdown? next,
    bool failNextMonth = false,
  }) => [
    accountBalancesProvider.overrideWith((ref) async => [wallet]),
    allAccountBalancesProvider.overrideWith((ref) async => [wallet]),
    creditFacilitiesProvider.overrideWith((ref) async => [facility]),
    allCreditFacilitiesProvider.overrideWith((ref) async => [facility]),
    pendingRecurringProvider.overrideWith(
      (ref) async => const <PendingRecurring>[],
    ),
    installmentPlansProvider.overrideWith(
      (ref, accountId) async => const <InstallmentPlan>[],
    ),
    installmentDuesProvider.overrideWith(
      (ref, accountId) async => const <InstallmentDue>[],
    ),
    statementSummariesProvider.overrideWith(
      (ref, accountId) async => const <CardStatementSummary>[],
    ),
    facilityActivityProvider.overrideWith(
      (ref, accountId) async => const <FacilityActivityItem>[],
    ),
    feeRulesProvider.overrideWith(
      (ref, accountId) async => const <CardFeeRule>[],
    ),
    transactionsPageProvider.overrideWith(
      (ref, query) async => const TransactionPage(items: [], hasMore: false),
    ),
    heldAmountsProvider.overrideWith((ref) async => const <HeldAmount>[]),
    responsibilitySummariesProvider.overrideWith(
      (ref) async => const <String, InstallmentResponsibilitySummary>{},
    ),
    planResponsibilityLinksProvider.overrideWith(
      (ref, planId) async => const <OwnerResponsibilityLink>[],
    ),
    facilityMonthDueBreakdownProvider.overrideWith((ref, args) async {
      if (args.monthStartIso == nextMonth.key) {
        if (failNextMonth) throw Exception('next month unavailable');
        return next ?? nextBreakdown;
      }
      return current ?? currentBreakdown;
    }),
    facilityDueBreakdownProvider.overrideWith(
      (ref, args) async => currentBreakdown,
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    List<dynamic>? scopeOverrides,
    Locale locale = const Locale('en'),
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...(scopeOverrides ?? overrides()).cast()],
        child: MaterialApp(
          theme: AppTheme.light(locale: locale),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToCarousel(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.byKey(const Key('facility-due-carousel')),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
  }

  group('facility due month carousel', () {
    testWidgets('renders exactly the current and next month cards', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
      );
      await scrollToCarousel(tester);

      expect(find.byKey(const Key('facility-due-carousel')), findsOneWidget);
      expect(
        find.byKey(const Key('facility-due-card-current')),
        findsOneWidget,
      );
      // The next card peeks into the viewport beside the active one.
      expect(find.byKey(const Key('facility-due-card-next')), findsOneWidget);
      expect(
        find.byKey(const Key('facility-due-page-indicator')),
        findsOneWidget,
      );
      expect(find.text('Current month'), findsOneWidget);
      expect(find.text('Next month'), findsOneWidget);
    });

    testWidgets('the current month is active first and its dues show below', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
      );
      await scrollToCarousel(tester);

      expect(find.text('Samsung Monitor'), findsWidgets);
      expect(find.text('September installment'), findsNothing);
    });

    testWidgets('swiping to next month updates the breakdown below', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
      );
      await scrollToCarousel(tester);

      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('facility-due-breakdown-active-month')),
        find.byType(Scrollable).first,
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();

      expect(find.text('September installment'), findsWidgets);
      expect(find.text('Samsung Monitor'), findsNothing);
    });

    testWidgets('a month with no dues says so instead of showing zeros', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
        scopeOverrides: overrides(
          next: breakdownFor(nextMonth, components: const []),
        ),
      );
      await scrollToCarousel(tester);
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(find.text('No dues this month'), findsWidgets);
      // A month without dues must not offer a zero-value payment.
      expect(find.byKey(const Key('facility-due-card-pay-next')), findsNothing);
    });

    testWidgets('a fully paid month shows paid instead of a payment button', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
        scopeOverrides: overrides(
          next: breakdownFor(
            nextMonth,
            components: [
              component(
                id: 'due-next',
                title: 'September installment',
                type: 'installment_due',
                dueOn: nextMonth.start.addDays(24).toIso(),
                amount: 160181,
                paid: 160181,
                kind: 'installment_due',
              ),
            ],
          ),
        ),
      );
      await scrollToCarousel(tester);
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(find.text('Paid in full'), findsWidgets);
      expect(find.byKey(const Key('facility-due-card-pay-next')), findsNothing);
    });

    testWidgets('one failing month leaves the other month usable', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
        scopeOverrides: overrides(failNextMonth: true),
      );
      await scrollToCarousel(tester);

      // The current month still renders its totals and pay action.
      expect(
        find.byKey(const Key('facility-due-card-pay-current')),
        findsOneWidget,
      );
      expect(find.text('Total due'), findsWidgets);
    });

    testWidgets('renders in Arabic without losing month identity', (
      tester,
    ) async {
      await pump(
        tester,
        const CreditFacilityDetailScreen(accountId: 'facility-1'),
        locale: const Locale('ar'),
      );
      await scrollToCarousel(tester);

      expect(find.text('الشهر الحالي'), findsOneWidget);
      expect(find.text('الشهر القادم'), findsOneWidget);
      expect(
        find.byKey(const Key('facility-due-page-indicator')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('month-scoped payment screen', () {
    testWidgets('next month scope shows only next month components', (
      tester,
    ) async {
      await pump(
        tester,
        FacilityPaymentScreen(
          accountId: 'facility-1',
          monthStartIso: nextMonth.key,
        ),
      );

      expect(find.text('September installment'), findsWidgets);
      // Current-month dues are never selectable from the next-month screen,
      // even though they are still unpaid.
      expect(find.text('Samsung Monitor'), findsNothing);
    });

    testWidgets('the screen names the month being paid', (tester) async {
      await pump(
        tester,
        FacilityPaymentScreen(
          accountId: 'facility-1',
          monthStartIso: nextMonth.key,
        ),
      );
      expect(find.textContaining('dues'), findsWidgets);
    });

    testWidgets('current month scope shows current month components', (
      tester,
    ) async {
      await pump(
        tester,
        FacilityPaymentScreen(
          accountId: 'facility-1',
          monthStartIso: currentMonth.key,
        ),
      );

      expect(find.text('Samsung Monitor'), findsWidgets);
      expect(find.text('September installment'), findsNothing);
    });

    testWidgets('without a month scope the payable-now flow is unchanged', (
      tester,
    ) async {
      await pump(tester, const FacilityPaymentScreen(accountId: 'facility-1'));
      expect(find.text('Pay credit facility'), findsWidgets);
    });
  });

  group('FacilityDueMonth', () {
    test('uses calendar boundaries, not thirty-day arithmetic', () {
      final december = FacilityDueMonth.payable(
        today: const PlainDate(2026, 12, 14),
      );
      expect(december.first.start, const PlainDate(2026, 12, 1));
      expect(december.first.end, const PlainDate(2026, 12, 31));
      expect(december.last.start, const PlainDate(2027, 1, 1));
      expect(december.last.end, const PlainDate(2027, 1, 31));
    });

    test('handles February in leap and common years', () {
      expect(
        FacilityDueMonth.payable(today: const PlainDate(2028, 1, 31)).last.end,
        const PlainDate(2028, 2, 29),
      );
      expect(
        FacilityDueMonth.payable(today: const PlainDate(2027, 2, 3)).first.end,
        const PlainDate(2027, 2, 28),
      );
    });

    test('normalizes any day of the month to the same provider key', () {
      expect(
        FacilityDueMonth.payable(today: const PlainDate(2026, 8, 1)).first.key,
        FacilityDueMonth.payable(today: const PlainDate(2026, 8, 29)).first.key,
      );
    });
  });
}
