import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';

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

/// Latest transactions for the Money tab list.
final recentTransactionsProvider = FutureProvider<List<FinancialTransaction>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchRecentTransactions();
  return result.when(ok: (t) => t, err: (f) => throw f);
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

/// Invalidate everything that depends on transaction or account rows.
void invalidateFinanceData(WidgetRef ref) {
  ref.invalidate(accountBalancesProvider);
  ref.invalidate(allAccountBalancesProvider);
  ref.invalidate(recentTransactionsProvider);
  ref.invalidate(heldAmountsProvider);
  ref.invalidate(pendingIncomeProvider);
}

void invalidateIncomeAutomation(WidgetRef ref) {
  ref
    ..invalidate(incomeSourcesProvider)
    ..invalidate(pendingIncomeProvider);
}
