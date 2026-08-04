import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/data/history_repository.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/settings/domain/user_profile.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/features/work/domain/official_holiday.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _FakeAuthNotifier extends AuthStateNotifier {
  @override
  AuthStateData build() =>
      const AuthStateData(phase: AuthPhase.signedIn, userId: 'user-1');
}

class _FakeOnboardingNotifier extends OnboardingStatusNotifier {
  @override
  OnboardingStatus build() => OnboardingStatus.complete;
}

class _FakeHistoryRepository implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #fetchHistory) {
      return Future<Result<HistoryPage>>.value(
        const Ok(HistoryPage(items: [], hasMore: false)),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

/// End-to-end sweep over the REAL router and REAL screens.
///
/// Every data provider is overridden with immediately-completing values, so
/// any screen that crashes, overflows, or keeps a spinner alive forever
/// (pumpAndSettle timeout) fails this test. This is the regression net for
/// "screen breaks when reached through the redesigned shell".
void main() {
  final bounds = SalaryPeriods.boundsFor(
    SalarySettings.defaults,
    PlainDate.today(),
  );

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      realtimeInvalidationProvider.overrideWith((ref) {}),
      currentUserIdProvider.overrideWithValue('user-1'),
      authStateProvider.overrideWith(_FakeAuthNotifier.new),
      onboardingStatusProvider.overrideWith(_FakeOnboardingNotifier.new),
      // Finance.
      accountBalancesProvider.overrideWith(
        (ref) async => const <AccountBalance>[],
      ),
      allAccountBalancesProvider.overrideWith(
        (ref) async => const <AccountBalance>[],
      ),
      recentTransactionsProvider.overrideWith(
        (ref) async => const <FinancialTransaction>[],
      ),
      heldAmountsProvider.overrideWith((ref) async => const <HeldAmount>[]),
      creditFacilitiesProvider.overrideWith(
        (ref) async => const <CreditFacilitySummary>[],
      ),
      installmentPlansProvider.overrideWith(
        (ref, accountId) async => const <InstallmentPlan>[],
      ),
      installmentDuesProvider.overrideWith(
        (ref, accountId) async => const <InstallmentDue>[],
      ),
      debtSummaryProvider.overrideWith(
        (ref, range) async => const <DebtSummary>[],
      ),
      macrosProvider.overrideWith((ref) async => const <TransactionMacro>[]),
      pendingIncomeProvider.overrideWith(
        (ref) async => const <PendingIncome>[],
      ),
      incomeSourcesProvider.overrideWith((ref) async => const <IncomeSource>[]),
      allCategoriesProvider.overrideWith(
        (ref) async => const <TransactionCategory>[],
      ),
      categoriesProvider.overrideWith(
        (ref, kind) async => const <TransactionCategory>[],
      ),
      // Reports.
      cashFlowSummaryProvider.overrideWith(
        (ref, range) async => const <CashFlowSummary>[],
      ),
      financeSeriesProvider.overrideWith(
        (ref, key) async => const <FinanceSeriesPoint>[],
      ),
      expenseCategoryTotalsProvider.overrideWith(
        (ref, range) async => const <CategoryTotal>[],
      ),
      allowanceCategoryTotalsProvider.overrideWith(
        (ref, range) async => const <CategoryTotal>[],
      ),
      incomeCategoryTotalsProvider.overrideWith(
        (ref, range) async => const <CategoryTotal>[],
      ),
      accountBalanceHistoryProvider.overrideWith(
        (ref, key) async => const <AccountBalancePoint>[],
      ),
      workSummaryProvider.overrideWith(
        (ref, range) async => const <WorkSummaryRow>[],
      ),
      workMinutesSeriesProvider.overrideWith(
        (ref, key) async => const <WorkMinutesPoint>[],
      ),
      salaryComparisonProvider.overrideWith(
        (ref, range) async => const <SalaryComparisonPoint>[],
      ),
      salaryWorkPeriodsProvider.overrideWith(
        (ref, range) async => const <SalaryWorkPeriodPoint>[],
      ),
      // Salary / work.
      salarySettingsProvider.overrideWith(
        (ref) async => SalarySettings.defaults.copyWith(salaryEnabled: false),
      ),
      currentPeriodBoundsProvider.overrideWith((ref) async => bounds),
      salaryPeriodsProvider.overrideWith((ref) async => const <SalaryPeriod>[]),
      adjustmentsForRangeProvider.overrideWith(
        (ref, range) async => const <SalaryAdjustment>[],
      ),
      workEntriesForMonthProvider.overrideWith(
        (ref, month) async => const <WorkEntry>[],
      ),
      holidaysProvider.overrideWith((ref) async => const <OfficialHoliday>[]),
      // History / settings.
      historyPageProvider.overrideWith(
        (ref, query) async => const HistoryPage(items: [], hasMore: false),
      ),
      historyRepositoryProvider.overrideWithValue(_FakeHistoryRepository()),
      profileProvider.overrideWith(
        (ref) async => const UserProfile(id: 'user-1', displayName: 'Aya'),
      ),
      preferencesProvider.overrideWith(
        (ref) async => const UserPreferences(
          currencyCode: 'EGP',
          timezone: 'Africa/Cairo',
          locale: 'en',
          weekStartsOn: 6,
          weekendDays: [5, 6],
          defaultHistoryDays: 30,
          onboardingCompleted: true,
        ),
      ),
    ],
  );

  late GoRouter router;

  Future<void> pumpRealApp(WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues(const {});
    final container = buildContainer();
    addTearDown(container.dispose);
    router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  Future<void> visit(
    WidgetTester tester,
    String location, {
    bool expectBottomBar = false,
  }) async {
    router.push(location).ignore();
    await settle(tester);
    expect(
      tester.takeException(),
      isNull,
      reason: 'exception while opening $location',
    );
    expect(
      find.byType(FinanceSuitNavigationBar).hitTestable(),
      expectBottomBar ? findsOneWidget : findsNothing,
      reason: 'bottom bar visibility wrong on $location',
    );
    // Every pushed route keeps a clear Back control.
    expect(
      find.byKey(const Key('finance-suit-back-button')),
      findsWidgets,
      reason: 'missing Back on $location',
    );
    router.pop();
    await settle(tester);
    expect(
      tester.takeException(),
      isNull,
      reason: 'exception while leaving $location',
    );
  }

  testWidgets('all four real tabs render and settle', (tester) async {
    await pumpRealApp(tester);
    expect(find.byType(FinanceSuitNavigationBar), findsOneWidget);

    for (final label in ['Work', 'Money', 'Reports', 'Home']) {
      await tester.tap(
        find.descendant(
          of: find.byType(FinanceSuitNavigationBar),
          matching: find.text(label),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'tab $label');
      expect(find.byType(FinanceSuitNavigationBar), findsOneWidget);
    }
  });

  testWidgets('every side-menu destination opens its real screen', (
    tester,
  ) async {
    await pumpRealApp(tester);
    for (final location in [
      '/settings',
      '/history',
      '/settings/income-sources',
      '/work/periods',
      '/work/holidays',
      '/money/categories',
      '/money/macros',
    ]) {
      await visit(tester, location);
      expect(find.text('Home'), findsOneWidget); // back on the Home tab
    }
  });

  testWidgets('every Global Add destination opens its real form', (
    tester,
  ) async {
    await pumpRealApp(tester);
    for (final location in [
      '/money/tx/new?kind=expense',
      '/money/tx/new?kind=allowance_given',
      '/money/tx/new?kind=custom_income',
      '/money/tx/new?kind=freelance_income',
      '/money/transfer',
      '/money/held/new',
      '/money/accounts/new',
      '/money/categories/new',
      '/work/entry/new',
      '/work/holidays/new',
      '/work/adjustments/new',
      '/settings/income-sources/new',
      '/money/macros/new',
    ]) {
      await visit(tester, location);
    }
  });

  testWidgets('every Settings child renders and returns', (tester) async {
    await pumpRealApp(tester);
    for (final location in [
      '/settings/salary',
      '/settings/password',
      '/settings/email',
      '/settings/delete-account',
    ]) {
      await visit(tester, location);
    }
  });
}
