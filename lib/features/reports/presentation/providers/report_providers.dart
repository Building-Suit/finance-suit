import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/reports/data/report_repository.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';

typedef ReportSeriesKey = ({DateRange range, ReportBucket bucket});
typedef AccountBalanceHistoryKey = ({String accountId, DateRange range});
typedef CategoryTotalsKey = ({DateRange range, String transactionKind});

final debtSummaryProvider = FutureProvider.family<List<DebtSummary>, DateRange>(
  (ref, range) async {
    ref.watch(currentUserIdProvider);
    final result = await ref
        .watch(reportRepositoryProvider)
        .fetchDebtSummary(range);
    return result.when(ok: (rows) => rows, err: (failure) => throw failure);
  },
);

final cashFlowSummaryProvider =
    FutureProvider.family<List<CashFlowSummary>, DateRange>((ref, range) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchCashFlowSummary(range);
      return result.when(
        ok: (summary) => summary,
        err: (failure) => throw failure,
      );
    });

/// Home's copy of the cash flow: accounts hidden from Home are left out of
/// the totals as well as the balance list, so the section adds up to what
/// the screen actually shows.
final homeCashFlowSummaryProvider =
    FutureProvider.family<List<CashFlowSummary>, DateRange>((ref, range) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchCashFlowSummary(range, excludeHidden: true);
      return result.when(
        ok: (summary) => summary,
        err: (failure) => throw failure,
      );
    });

final financeSeriesProvider =
    FutureProvider.family<List<FinanceSeriesPoint>, ReportSeriesKey>((
      ref,
      key,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchFinanceSeries(range: key.range, bucket: key.bucket);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final expenseCategoryTotalsProvider =
    FutureProvider.family<List<CategoryTotal>, DateRange>((ref, range) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchCategoryTotals(range: range, kind: TransactionKind.expense);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final allowanceCategoryTotalsProvider =
    FutureProvider.family<List<CategoryTotal>, DateRange>((ref, range) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchCategoryTotals(
            range: range,
            kind: TransactionKind.allowanceGiven,
          );
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final incomeCategoryTotalsProvider =
    FutureProvider.family<List<CategoryTotal>, DateRange>((ref, range) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchIncomeCategoryTotals(range: range);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final accountBalanceHistoryProvider =
    FutureProvider.family<List<AccountBalancePoint>, AccountBalanceHistoryKey>((
      ref,
      key,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchAccountBalanceHistory(
            accountId: key.accountId,
            range: key.range,
          );
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final workSummaryProvider =
    FutureProvider.family<List<WorkSummaryRow>, DateRange>((ref, range) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchWorkSummary(range);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final workMinutesSeriesProvider =
    FutureProvider.family<List<WorkMinutesPoint>, ReportSeriesKey>((
      ref,
      key,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchWorkMinutesSeries(range: key.range, bucket: key.bucket);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final salaryComparisonProvider =
    FutureProvider.family<List<SalaryComparisonPoint>, DateRange>((
      ref,
      range,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchSalaryComparison(range);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

final salaryWorkPeriodsProvider =
    FutureProvider.family<List<SalaryWorkPeriodPoint>, DateRange>((
      ref,
      range,
    ) async {
      ref.watch(currentUserIdProvider);
      final result = await ref
          .watch(reportRepositoryProvider)
          .fetchSalaryWorkPeriods(range);
      return result.when(ok: (rows) => rows, err: (failure) => throw failure);
    });

void invalidateReportData(WidgetRef ref) {
  ref
    ..invalidate(debtSummaryProvider)
    ..invalidate(cashFlowSummaryProvider)
    ..invalidate(financeSeriesProvider)
    ..invalidate(expenseCategoryTotalsProvider)
    ..invalidate(allowanceCategoryTotalsProvider)
    ..invalidate(incomeCategoryTotalsProvider)
    ..invalidate(accountBalanceHistoryProvider)
    ..invalidate(workSummaryProvider)
    ..invalidate(workMinutesSeriesProvider)
    ..invalidate(salaryComparisonProvider)
    ..invalidate(salaryWorkPeriodsProvider);
}
