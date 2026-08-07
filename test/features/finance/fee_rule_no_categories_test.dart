import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// A card fee books an expense and requires an expense category. A user
/// with zero active expense categories must never be handed a required
/// dropdown with nothing in it and no way out — see the bug where "Add
/// fee" showed a permanent "This field is required" with an empty
/// category picker.
const _visa = CreditFacilitySummary(
  accountId: 'facility-1',
  name: 'CIB Gold Card',
  accountType: AccountType.creditCard,
  currencyCode: 'EGP',
  isArchived: false,
  openingOwedMinor: 0,
  creditLimitMinor: 500000,
  defaultDueDay: 10,
  reminderLeadDays: 3,
  outstandingMinor: 0,
  availableCreditMinor: 500000,
  utilizationBasisPoints: 0,
  dueNowMinor: 0,
  overdueMinor: 0,
  activePlanCount: 0,
  statementDay: 5,
);

List<dynamic> _overrides({
  List<TransactionCategory> expenseCategories = const [],
}) => [
  allCreditFacilitiesProvider.overrideWith((ref) async => const [_visa]),
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
  categoriesProvider.overrideWith(
    (ref, kind) async =>
        kind == CategoryKind.expense ? expenseCategories : const [],
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<dynamic> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/money/facilities/facility-1',
    routes: [
      GoRoute(
        path: '/money/facilities/facility-1',
        builder: (context, state) =>
            const CreditFacilityDetailScreen(accountId: 'facility-1'),
      ),
      GoRoute(
        path: '/money/categories/new',
        builder: (context, state) =>
            const Scaffold(body: Text('category form stub')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'adding a fee with no expense categories offers a way to create one',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, overrides: _overrides());

      await tester.scrollUntilVisible(
        find.byKey(const Key('fee-rule-add')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('fee-rule-add')));
      await tester.pumpAndSettle();

      // No dead-end required dropdown with nothing in it.
      expect(find.byKey(const Key('fee-rule-no-categories')), findsOneWidget);
      expect(find.textContaining('expense category'), findsWidgets);

      // Save cannot silently no-op: it is genuinely disabled.
      final saveButton = tester.widget<FilledButton>(
        find.byKey(const Key('fee-rule-submit')),
      );
      expect(saveButton.onPressed, isNull);

      // The way out actually navigates to category creation.
      await tester.tap(find.byKey(const Key('fee-rule-add-category')));
      await tester.pumpAndSettle();
      expect(find.text('category form stub'), findsOneWidget);
    },
  );

  testWidgets('a category still means an ordinary, working fee dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      overrides: _overrides(
        expenseCategories: const [
          TransactionCategory(
            id: 'cat-1',
            name: 'Shopping',
            kind: CategoryKind.expense,
            icon: 'category',
            sortOrder: 0,
            isArchived: false,
          ),
        ],
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('fee-rule-add')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('fee-rule-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fee-rule-no-categories')), findsNothing);
    expect(find.byKey(const Key('fee-rule-category-cat-1')), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('fee-rule-submit')),
    );
    expect(saveButton.onPressed, isNotNull);
  });
}
