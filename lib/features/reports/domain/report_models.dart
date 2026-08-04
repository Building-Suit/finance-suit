import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

enum ReportBucket {
  day('day'),
  week('week'),
  month('month');

  const ReportBucket(this.dbValue);
  final String dbValue;
}

@immutable
/// One `app_reports.debt_summary` row: per-currency credit-facility figures.
class DebtSummary {
  const DebtSummary({
    required this.currencyCode,
    required this.repaymentsMinor,
    required this.upcomingDuesMinor,
    required this.overdueMinor,
    required this.outstandingMinor,
  });

  factory DebtSummary.fromJson(Map<String, dynamic> json) => DebtSummary(
    currencyCode: json['currency_code'] as String? ?? 'EGP',
    repaymentsMinor: (json['repayments_minor'] as num).toInt(),
    upcomingDuesMinor: (json['upcoming_dues_minor'] as num).toInt(),
    overdueMinor: (json['overdue_minor'] as num).toInt(),
    outstandingMinor: (json['outstanding_minor'] as num).toInt(),
  );

  final String currencyCode;
  final int repaymentsMinor;
  final int upcomingDuesMinor;
  final int overdueMinor;
  final int outstandingMinor;
}

class CashFlowSummary {
  const CashFlowSummary({
    required this.currencyCode,
    required this.startingBalanceMinor,
    required this.incomeMinor,
    required this.expensesMinor,
    required this.allowancesMinor,
    required this.netMinor,
    required this.endingBalanceMinor,
  });

  factory CashFlowSummary.fromJson(Map<String, dynamic> json) =>
      CashFlowSummary(
        currencyCode: json['currency_code'] as String? ?? 'EGP',
        startingBalanceMinor: (json['starting_balance_minor'] as num? ?? 0)
            .toInt(),
        incomeMinor: (json['income_minor'] as num).toInt(),
        expensesMinor: (json['expenses_minor'] as num).toInt(),
        allowancesMinor: (json['allowances_minor'] as num).toInt(),
        netMinor: (json['net_minor'] as num).toInt(),
        endingBalanceMinor: (json['ending_balance_minor'] as num? ?? 0).toInt(),
      );

  final String currencyCode;
  final int startingBalanceMinor;
  final int incomeMinor;
  final int expensesMinor;
  final int allowancesMinor;
  final int netMinor;
  final int endingBalanceMinor;

  bool get isZero =>
      incomeMinor == 0 &&
      expensesMinor == 0 &&
      allowancesMinor == 0 &&
      netMinor == 0 &&
      startingBalanceMinor == 0 &&
      endingBalanceMinor == 0;
}

@immutable
class FinanceSeriesPoint {
  const FinanceSeriesPoint({
    required this.bucketStart,
    required this.incomeMinor,
    required this.expensesMinor,
    required this.allowancesMinor,
    required this.netMinor,
  });

  factory FinanceSeriesPoint.fromJson(Map<String, dynamic> json) =>
      FinanceSeriesPoint(
        bucketStart: PlainDate.parse(json['bucket_start'] as String),
        incomeMinor: (json['income_minor'] as num).toInt(),
        expensesMinor: (json['expenses_minor'] as num).toInt(),
        allowancesMinor: (json['allowances_minor'] as num).toInt(),
        netMinor: (json['net_minor'] as num).toInt(),
      );

  final PlainDate bucketStart;
  final int incomeMinor;
  final int expensesMinor;
  final int allowancesMinor;
  final int netMinor;
}

@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.categoryName,
    required this.totalMinor,
    required this.transactionCount,
    this.categoryId,
    this.categoryIcon,
  });

  factory CategoryTotal.fromJson(Map<String, dynamic> json) => CategoryTotal(
    categoryId: json['category_id'] as String?,
    categoryName: json['category_name'] as String,
    categoryIcon: json['category_icon'] as String?,
    totalMinor: (json['total_minor'] as num).toInt(),
    transactionCount: (json['tx_count'] as num).toInt(),
  );

  final String? categoryId;
  final String categoryName;
  final String? categoryIcon;
  final int totalMinor;
  final int transactionCount;
}

@immutable
class AccountBalancePoint {
  const AccountBalancePoint({required this.day, required this.balanceMinor});

  factory AccountBalancePoint.fromJson(Map<String, dynamic> json) =>
      AccountBalancePoint(
        day: PlainDate.parse(json['day'] as String),
        balanceMinor: (json['balance_minor'] as num).toInt(),
      );

  final PlainDate day;
  final int balanceMinor;
}

@immutable
class WorkSummaryRow {
  const WorkSummaryRow({
    required this.entryType,
    required this.entryCount,
    required this.totalMinutes,
    required this.totalDayUnitsHundredths,
    required this.totalAmountMinor,
  });

  factory WorkSummaryRow.fromJson(Map<String, dynamic> json) => WorkSummaryRow(
    entryType: WorkEntryType.fromDb(json['entry_type'] as String),
    entryCount: (json['entry_count'] as num).toInt(),
    totalMinutes: (json['total_minutes'] as num).toInt(),
    totalDayUnitsHundredths: (json['total_day_units_hundredths'] as num)
        .toInt(),
    totalAmountMinor: (json['total_amount_minor'] as num).toInt(),
  );

  final WorkEntryType entryType;
  final int entryCount;
  final int totalMinutes;
  final int totalDayUnitsHundredths;
  final int totalAmountMinor;
}

@immutable
class WorkMinutesPoint {
  const WorkMinutesPoint({
    required this.bucketStart,
    required this.totalMinutes,
  });

  factory WorkMinutesPoint.fromJson(Map<String, dynamic> json) =>
      WorkMinutesPoint(
        bucketStart: PlainDate.parse(json['bucket_start'] as String),
        totalMinutes: (json['total_minutes'] as num).toInt(),
      );

  final PlainDate bucketStart;
  final int totalMinutes;
}

@immutable
class SalaryComparisonPoint {
  const SalaryComparisonPoint({
    required this.periodId,
    required this.periodStart,
    required this.periodEnd,
    required this.expectedPaymentDate,
    required this.status,
    required this.estimatedMinor,
    required this.currencyCode,
    this.actualAmountMinor,
    this.differenceMinor,
  });

  factory SalaryComparisonPoint.fromJson(Map<String, dynamic> json) =>
      SalaryComparisonPoint(
        periodId: json['period_id'] as String,
        periodStart: PlainDate.parse(json['period_start'] as String),
        periodEnd: PlainDate.parse(json['period_end'] as String),
        expectedPaymentDate: PlainDate.parse(
          json['expected_payment_date'] as String,
        ),
        status: SalaryPeriodStatus.fromDb(json['status'] as String),
        estimatedMinor: (json['estimated_minor'] as num).toInt(),
        actualAmountMinor: (json['actual_amount_minor'] as num?)?.toInt(),
        differenceMinor: (json['difference_minor'] as num?)?.toInt(),
        currencyCode: json['currency_code'] as String,
      );

  final String periodId;
  final PlainDate periodStart;
  final PlainDate periodEnd;
  final PlainDate expectedPaymentDate;
  final SalaryPeriodStatus status;
  final int estimatedMinor;
  final int? actualAmountMinor;
  final int? differenceMinor;
  final String currencyCode;
}

@immutable
class SalaryWorkPeriodPoint {
  const SalaryWorkPeriodPoint({
    required this.periodId,
    required this.periodStart,
    required this.periodEnd,
    required this.overtimeMinutes,
    required this.overtimeAmountMinor,
    required this.extraDayUnitsHundredths,
    required this.extraDayAmountMinor,
    required this.holidayCount,
    required this.holidayAmountMinor,
    required this.currencyCode,
  });

  factory SalaryWorkPeriodPoint.fromJson(Map<String, dynamic> json) =>
      SalaryWorkPeriodPoint(
        periodId: json['period_id'] as String,
        periodStart: PlainDate.parse(json['period_start'] as String),
        periodEnd: PlainDate.parse(json['period_end'] as String),
        overtimeMinutes: (json['overtime_minutes'] as num).toInt(),
        overtimeAmountMinor: (json['overtime_amount_minor'] as num).toInt(),
        extraDayUnitsHundredths: (json['extra_day_units_hundredths'] as num)
            .toInt(),
        extraDayAmountMinor: (json['extra_day_amount_minor'] as num).toInt(),
        holidayCount: (json['holiday_count'] as num).toInt(),
        holidayAmountMinor: (json['holiday_amount_minor'] as num).toInt(),
        currencyCode: json['currency_code'] as String,
      );

  final String periodId;
  final PlainDate periodStart;
  final PlainDate periodEnd;
  final int overtimeMinutes;
  final int overtimeAmountMinor;
  final int extraDayUnitsHundredths;
  final int extraDayAmountMinor;
  final int holidayCount;
  final int holidayAmountMinor;
  final String currencyCode;
}

@immutable
class ReportRangeSelection {
  const ReportRangeSelection({
    required this.preset,
    required this.range,
    this.bucket = ReportBucket.week,
  });

  factory ReportRangeSelection.currentMonth(PlainDate today) =>
      ReportRangeSelection(
        preset: DateRangePreset.currentMonth,
        range: rangeForPreset(DateRangePreset.currentMonth, today),
      );

  factory ReportRangeSelection.last30Days(PlainDate today) =>
      ReportRangeSelection(
        preset: DateRangePreset.last30Days,
        range: rangeForPreset(DateRangePreset.last30Days, today),
      );

  final DateRangePreset preset;
  final DateRange range;
  final ReportBucket bucket;

  ReportRangeSelection copyWith({
    DateRangePreset? preset,
    DateRange? range,
    ReportBucket? bucket,
  }) {
    return ReportRangeSelection(
      preset: preset ?? this.preset,
      range: range ?? this.range,
      bucket: bucket ?? this.bucket,
    );
  }
}
