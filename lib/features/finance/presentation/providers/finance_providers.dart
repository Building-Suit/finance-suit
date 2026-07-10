import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';

/// Active (non-archived) accounts with derived balances.
final accountBalancesProvider = FutureProvider<List<AccountBalance>>((
  ref,
) async {
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchAccountBalances();
  return result.when(ok: (a) => a, err: (f) => throw f);
});

/// All accounts including archived, for the account management list.
final allAccountBalancesProvider = FutureProvider<List<AccountBalance>>((
  ref,
) async {
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchAccountBalances(includeArchived: true);
  return result.when(ok: (a) => a, err: (f) => throw f);
});

/// Active categories of one kind, for pickers.
final categoriesProvider = FutureProvider.family
    .autoDispose<List<TransactionCategory>, CategoryKind>((ref, kind) async {
      final result = await ref
          .watch(financeRepositoryProvider)
          .fetchCategories(kind: kind);
      return result.when(ok: (c) => c, err: (f) => throw f);
    });

/// All categories including archived, for the management screen.
final allCategoriesProvider = FutureProvider<List<TransactionCategory>>((
  ref,
) async {
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchCategories(includeArchived: true);
  return result.when(ok: (c) => c, err: (f) => throw f);
});

/// Latest transactions for the Money tab list.
final recentTransactionsProvider = FutureProvider<List<FinancialTransaction>>((
  ref,
) async {
  final result = await ref
      .watch(financeRepositoryProvider)
      .fetchRecentTransactions();
  return result.when(ok: (t) => t, err: (f) => throw f);
});

/// Invalidate everything that depends on transaction or account rows.
void invalidateFinanceData(WidgetRef ref) {
  ref.invalidate(accountBalancesProvider);
  ref.invalidate(allAccountBalancesProvider);
  ref.invalidate(recentTransactionsProvider);
}
