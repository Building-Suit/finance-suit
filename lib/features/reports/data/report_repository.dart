import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';

class ReportRepository {
  ReportRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.reports);

  Future<Result<List<CashFlowSummary>>> fetchCashFlowSummary(DateRange range) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'cash_flow_summary_v2',
        params: {'p_start': range.start.toIso(), 'p_end': range.end.toIso()},
      );
      return rows
          .map((row) => CashFlowSummary.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  /// Debt-repayment and upcoming-installment figures for credit facilities;
  /// repayments are transfers and never mix into income/expense totals.
  Future<Result<List<DebtSummary>>> fetchDebtSummary(DateRange range) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'debt_summary',
        params: {'p_start': range.start.toIso(), 'p_end': range.end.toIso()},
      );
      return rows
          .map((row) => DebtSummary.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<FinanceSeriesPoint>>> fetchFinanceSeries({
    required DateRange range,
    required ReportBucket bucket,
  }) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'finance_series',
        params: {
          'p_start': range.start.toIso(),
          'p_end': range.end.toIso(),
          'p_bucket': bucket.dbValue,
        },
      );
      return rows
          .map(
            (row) => FinanceSeriesPoint.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<Result<List<CategoryTotal>>> fetchCategoryTotals({
    required DateRange range,
    required TransactionKind kind,
  }) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'amounts_by_category',
        params: {
          'p_start': range.start.toIso(),
          'p_end': range.end.toIso(),
          'p_kind': kind.dbValue,
        },
      );
      return rows
          .map((row) => CategoryTotal.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<CategoryTotal>>> fetchIncomeCategoryTotals({
    required DateRange range,
  }) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'income_amounts_by_category',
        params: {'p_start': range.start.toIso(), 'p_end': range.end.toIso()},
      );
      return rows
          .map((row) => CategoryTotal.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<AccountBalancePoint>>> fetchAccountBalanceHistory({
    required String accountId,
    required DateRange range,
  }) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'account_balance_history',
        params: {
          'p_account_id': accountId,
          'p_start': range.start.toIso(),
          'p_end': range.end.toIso(),
        },
      );
      return rows
          .map(
            (row) => AccountBalancePoint.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<Result<List<WorkSummaryRow>>> fetchWorkSummary(DateRange range) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'work_summary',
        params: {'p_start': range.start.toIso(), 'p_end': range.end.toIso()},
      );
      return rows
          .map((row) => WorkSummaryRow.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<WorkMinutesPoint>>> fetchWorkMinutesSeries({
    required DateRange range,
    required ReportBucket bucket,
  }) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'work_minutes_series',
        params: {
          'p_start': range.start.toIso(),
          'p_end': range.end.toIso(),
          'p_bucket': bucket.dbValue,
        },
      );
      return rows
          .map((row) => WorkMinutesPoint.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Result<List<SalaryComparisonPoint>>> fetchSalaryComparison(
    DateRange range,
  ) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'salary_comparison_report',
        params: {'p_start': range.start.toIso(), 'p_end': range.end.toIso()},
      );
      return rows
          .map(
            (row) =>
                SalaryComparisonPoint.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<Result<List<SalaryWorkPeriodPoint>>> fetchSalaryWorkPeriods(
    DateRange range,
  ) {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'salary_period_work_report',
        params: {'p_start': range.start.toIso(), 'p_end': range.end.toIso()},
      );
      return rows
          .map(
            (row) =>
                SalaryWorkPeriodPoint.fromJson(row as Map<String, dynamic>),
          )
          .toList();
    });
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(supabaseClientProvider)),
);
