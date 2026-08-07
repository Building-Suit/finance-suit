import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';

typedef PendingIncomeEstimateKey = ({
  String occurrenceId,
  PlainDate scheduledOn,
});

/// Active (non-archived) accounts with derived balances.
final accountBalancesProvider = FutureProvider<List<AccountBalance>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchAccountBalances();
  return result.when(ok: (a) => a, err: (f) => throw f);
});

/// All accounts including archived, for the account management list.
final allAccountBalancesProvider = FutureProvider<List<AccountBalance>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchAccountBalances(includeArchived: true);
  return result.when(ok: (a) => a, err: (f) => throw f);
});

/// Active categories of one kind, for pickers.
final categoriesProvider = FutureProvider.family
    .autoDispose<List<TransactionCategory>, CategoryKind>((ref, kind) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchCategories(kind: kind);
      return result.when(ok: (c) => c, err: (f) => throw f);
    });

/// All categories including archived, for the management screen.
final allCategoriesProvider = FutureProvider<List<TransactionCategory>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchCategories(includeArchived: true);
  return result.when(ok: (c) => c, err: (f) => throw f);
});

/// The first page of the Money tab's transaction list for one filter set.
///
/// Later pages are fetched imperatively through the repository as the user
/// scrolls; keeping page one in a provider means every invalidation — an
/// edit, a realtime event, a pull to refresh — rebuilds the list from the
/// top without the screen having to subscribe to anything else.
final transactionsPageProvider = FutureProvider.family
    .autoDispose<TransactionPage, TransactionQuery>((ref, query) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchTransactions(query);
      return result.when(ok: (page) => page, err: (failure) => throw failure);
    });

/// Exact match count for one draft filter set, powering the filter sheet's
/// live "Apply (N)" preview. Keyed on the query like [transactionsPageProvider]
/// so the same draft never issues the count request twice.
final transactionsCountProvider = FutureProvider.family
    .autoDispose<int, TransactionQuery>((ref, query) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchTransactionCount(query);
      return result.when(ok: (count) => count, err: (failure) => throw failure);
    });

/// Saved macros with their items, for the macros screen and the add sheet.
final macrosProvider = FutureProvider<List<TransactionMacro>>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(financeRepositoryProvider).fetchMacros();
  return result.when(ok: (m) => m, err: (f) => throw f);
});

/// All held amounts, newest first; settled entries are filtered in the UI.
final heldAmountsProvider = FutureProvider<List<HeldAmount>>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(financeRepositoryProvider).fetchHeldAmounts();
  return result.when(ok: (h) => h, err: (f) => throw f);
});

final incomeSourcesProvider = FutureProvider<List<IncomeSource>>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchIncomeSources();
  return result.when(ok: (sources) => sources, err: (failure) => throw failure);
});

final pendingIncomeProvider = FutureProvider<List<PendingIncome>>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchPendingIncome(PlainDate.today());
  return result.when(ok: (items) => items, err: (failure) => throw failure);
});

final pendingSalaryEstimateProvider =
    FutureProvider.family<SalaryEstimate, PendingIncomeEstimateKey>((
      ref,
      key,
    ) async {
      final settings = await ref.watch(salarySettingsProvider.future);
      final bounds = SalaryPeriods.boundsForExpectedPayment(
        settings,
        key.scheduledOn,
      );
      return ref.watch(
        estimateForRangeProvider((start: bounds.start, end: bounds.end)).future,
      );
    });

/// Active credit-card and BNPL facilities with their derived debt figures.
///
/// Loading facilities first settles any card fees that have fallen due —
/// the generator is idempotent server-side, so refresh spam cannot
/// double-charge, and a generation hiccup never blocks the list itself.
final creditFacilitiesProvider = FutureProvider<List<CreditFacilitySummary>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final repository = ref.watch(financeRepositoryProvider);
  final applied = await repository.applyCreditCardFees();
  final result = await repository.fetchCreditFacilities();
  final facilities = result.when(ok: (f) => f, err: (failure) => throw failure);
  if ((applied.valueOrNull ?? 0) > 0) {
    // Newly booked fees changed balances and statements elsewhere too.
    ref.invalidate(transactionsPageProvider);
    ref.invalidate(statementSummariesProvider);
  }
  return facilities;
});

/// Installment plans of one facility, newest first.
final installmentPlansProvider = FutureProvider.family
    .autoDispose<List<InstallmentPlan>, String>((ref, accountId) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchInstallmentPlans(accountId: accountId);
      return result.when(ok: (p) => p, err: (failure) => throw failure);
    });

/// Dues of one facility ordered by due date.
final installmentDuesProvider = FutureProvider.family
    .autoDispose<List<InstallmentDue>, String>((ref, accountId) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchInstallmentDues(accountId: accountId);
      return result.when(ok: (d) => d, err: (failure) => throw failure);
    });

/// Classified Related-activity rows of one facility, newest first.
final facilityActivityProvider = FutureProvider.family
    .autoDispose<List<FacilityActivityItem>, String>((ref, accountId) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchFacilityActivity(accountId);
      return result.when(ok: (items) => items, err: (failure) => throw failure);
    });

/// Statement cycles of one credit card, newest first.
final statementSummariesProvider = FutureProvider.family
    .autoDispose<List<CardStatementSummary>, String>((ref, accountId) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchStatementSummaries(accountId);
      return result.when(ok: (s) => s, err: (failure) => throw failure);
    });

/// Every facility including archived ones, for the Money account list —
/// an archived card keeps its debt visible until it is settled.
final allCreditFacilitiesProvider = FutureProvider<List<CreditFacilitySummary>>(
  (ref) async {
    ref.watch(currentUserIdProvider);
    final result = await ref
        .watch(financeRepositoryProvider)
        .fetchCreditFacilities(includeArchived: true);
    return result.when(ok: (f) => f, err: (failure) => throw failure);
  },
);

/// Fee rules of one credit card, active first.
final feeRulesProvider = FutureProvider.family
    .autoDispose<List<CardFeeRule>, String>((ref, accountId) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchFeeRules(accountId);
      return result.when(ok: (r) => r, err: (failure) => throw failure);
    });

/// Restructure history of one installment plan.
final planRevisionsProvider = FutureProvider.family
    .autoDispose<List<InstallmentPlanRevision>, String>((ref, planId) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchPlanRevisions(planId);
      return result.when(ok: (r) => r, err: (failure) => throw failure);
    });

/// Invalidate everything that depends on transaction or account rows.
void invalidateFinanceData(WidgetRef ref) {
  ref.invalidate(accountBalancesProvider);
  ref.invalidate(allAccountBalancesProvider);
  ref.invalidate(transactionsPageProvider);
  ref.invalidate(heldAmountsProvider);
  ref.invalidate(pendingIncomeProvider);
  ref.invalidate(creditFacilitiesProvider);
  ref.invalidate(allCreditFacilitiesProvider);
  ref.invalidate(installmentPlansProvider);
  ref.invalidate(installmentDuesProvider);
  ref.invalidate(statementSummariesProvider);
  ref.invalidate(facilityActivityProvider);
  ref.invalidate(planRevisionsProvider);
  ref.invalidate(feeRulesProvider);
}

void invalidateIncomeAutomation(WidgetRef ref) {
  ref
    ..invalidate(incomeSourcesProvider)
    ..invalidate(pendingIncomeProvider);
}

/// Recurring expense/transfer rules, active first.
final recurringRulesProvider = FutureProvider<List<RecurringRule>>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchRecurringRules();
  return result.when(ok: (r) => r, err: (failure) => throw failure);
});

/// Pending recurring outflows awaiting an accept/skip decision.
final pendingRecurringProvider = FutureProvider<List<PendingRecurring>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchPendingRecurring(PlainDate.today());
  return result.when(ok: (items) => items, err: (failure) => throw failure);
});

void invalidateRecurringAutomation(WidgetRef ref) {
  ref
    ..invalidate(recurringRulesProvider)
    ..invalidate(pendingRecurringProvider);
}
