import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_calculator.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';

/// Start/end of an earning period plus the date the salary is expected.
typedef PeriodBounds = ({
  PlainDate start,
  PlainDate end,
  PlainDate expectedPaymentDate,
});

/// Pure period-boundary math derived from salary settings.
abstract final class SalaryPeriods {
  /// The earning period containing [date]. Periods start on
  /// `salaryPeriodStartDay` (1..28) of every month.
  static PeriodBounds boundsFor(SalarySettings s, PlainDate date) {
    final start = date.day >= s.salaryPeriodStartDay
        ? date.withDay(s.salaryPeriodStartDay)
        : date.addMonths(-1).withDay(s.salaryPeriodStartDay);
    final end = start.addMonths(1).addDays(-1);
    final expected = PlainDate(
      start.year,
      start.month,
      1,
    ).addMonths(s.paymentMonthOffset).withDay(s.paymentDay);
    return (start: start, end: end, expectedPaymentDate: expected);
  }

  /// The earning period paid by a scheduled salary occurrence. This keeps an
  /// early or delayed acceptance attached to its original period instead of
  /// whichever period happens to contain the day the user taps Accept.
  static PeriodBounds boundsForExpectedPayment(
    SalarySettings s,
    PlainDate expectedPaymentDate,
  ) {
    final earningMonth = PlainDate(
      expectedPaymentDate.year,
      expectedPaymentDate.month,
      1,
    ).addMonths(-s.paymentMonthOffset);
    final start = earningMonth.withDay(s.salaryPeriodStartDay);
    final end = start.addMonths(1).addDays(-1);
    final expected = PlainDate(
      start.year,
      start.month,
      1,
    ).addMonths(s.paymentMonthOffset).withDay(s.paymentDay);
    return (start: start, end: end, expectedPaymentDate: expected);
  }
}

/// Warning codes surfaced with an estimate; screens localize them.
enum SalaryEstimateWarning { baseSalaryZero, entriesMissingAmounts }

/// Itemized salary estimate for one earning period. All amounts are
/// integer minor units; the breakdown must always be shown, never only
/// the total.
@immutable
class SalaryEstimate {
  const SalaryEstimate({
    required this.periodStart,
    required this.periodEnd,
    required this.expectedPaymentDate,
    required this.currencyCode,
    required this.baseSalaryMinor,
    required this.dayRateMinor,
    required this.hourRateMinor,
    required this.extraDayUnitsHundredths,
    required this.extraDayAmountMinor,
    required this.holidayCount,
    required this.holidayAmountMinor,
    required this.overtimeMinutes,
    required this.overtimeAmountMinor,
    required this.bonusesMinor,
    required this.deductionsMinor,
    required this.warnings,
  });

  /// Builds the estimate from settings, the period's work entries, and
  /// the period's salary adjustments. Uses the amounts persisted with
  /// each entry (their own calc snapshots) so stored history stays
  /// authoritative.
  factory SalaryEstimate.compute(
    SalarySettings settings, {
    required PeriodBounds bounds,
    required List<WorkEntry> entries,
    required List<SalaryAdjustment> adjustments,
  }) {
    var extraUnits = 0;
    var extraAmount = 0;
    var holidayCount = 0;
    var holidayAmount = 0;
    var overtimeMinutes = 0;
    var overtimeAmount = 0;
    var missingAmounts = false;
    for (final entry in entries) {
      final amount = entry.computedAmountMinor;
      if (amount == null && entry.entryType != WorkEntryType.regular) {
        missingAmounts = true;
      }
      switch (entry.entryType) {
        case WorkEntryType.regular:
          break;
        case WorkEntryType.overtime:
          overtimeMinutes += entry.durationMinutes ?? 0;
          overtimeAmount += amount ?? 0;
        case WorkEntryType.extraDay:
          extraUnits += entry.dayUnitsHundredths ?? 0;
          extraAmount += amount ?? 0;
        case WorkEntryType.holidayWorked:
          holidayCount += 1;
          holidayAmount += amount ?? 0;
      }
    }
    var bonuses = 0;
    var deductions = 0;
    for (final adjustment in adjustments) {
      switch (adjustment.adjustmentType) {
        case AdjustmentType.bonus:
          bonuses += adjustment.amountMinor;
        case AdjustmentType.deduction:
          deductions += adjustment.amountMinor;
      }
    }
    return SalaryEstimate(
      periodStart: bounds.start,
      periodEnd: bounds.end,
      expectedPaymentDate: bounds.expectedPaymentDate,
      currencyCode: settings.currencyCode,
      baseSalaryMinor: settings.baseSalaryMinor,
      dayRateMinor: SalaryCalculator.dayRate(settings).minor,
      hourRateMinor: SalaryCalculator.hourRate(settings).minor,
      extraDayUnitsHundredths: extraUnits,
      extraDayAmountMinor: extraAmount,
      holidayCount: holidayCount,
      holidayAmountMinor: holidayAmount,
      overtimeMinutes: overtimeMinutes,
      overtimeAmountMinor: overtimeAmount,
      bonusesMinor: bonuses,
      deductionsMinor: deductions,
      warnings: [
        if (settings.baseSalaryMinor == 0) SalaryEstimateWarning.baseSalaryZero,
        if (missingAmounts) SalaryEstimateWarning.entriesMissingAmounts,
      ],
    );
  }

  /// Rebuilds a finalized period's estimate from its immutable snapshot,
  /// so history never silently recalculates after settings change.
  factory SalaryEstimate.fromSnapshot(Map<String, dynamic> json) =>
      SalaryEstimate(
        periodStart: PlainDate.parse(json['period_start'] as String),
        periodEnd: PlainDate.parse(json['period_end'] as String),
        expectedPaymentDate: PlainDate.parse(
          json['expected_payment_date'] as String,
        ),
        currencyCode: json['currency_code'] as String,
        baseSalaryMinor: (json['base_salary_minor'] as num).toInt(),
        dayRateMinor: (json['day_rate_minor'] as num).toInt(),
        hourRateMinor: (json['hour_rate_minor'] as num).toInt(),
        extraDayUnitsHundredths: (json['extra_day_units_hundredths'] as num)
            .toInt(),
        extraDayAmountMinor: (json['extra_day_amount_minor'] as num).toInt(),
        holidayCount: (json['holiday_count'] as num).toInt(),
        holidayAmountMinor: (json['holiday_amount_minor'] as num).toInt(),
        overtimeMinutes: (json['overtime_minutes'] as num).toInt(),
        overtimeAmountMinor: (json['overtime_amount_minor'] as num).toInt(),
        bonusesMinor: (json['bonuses_minor'] as num).toInt(),
        deductionsMinor: (json['deductions_minor'] as num).toInt(),
        warnings: const [],
      );

  final PlainDate periodStart;
  final PlainDate periodEnd;
  final PlainDate expectedPaymentDate;
  final String currencyCode;
  final int baseSalaryMinor;
  final int dayRateMinor;
  final int hourRateMinor;
  final int extraDayUnitsHundredths;
  final int extraDayAmountMinor;
  final int holidayCount;
  final int holidayAmountMinor;
  final int overtimeMinutes;
  final int overtimeAmountMinor;
  final int bonusesMinor;
  final int deductionsMinor;
  final List<SalaryEstimateWarning> warnings;

  int get totalMinor =>
      baseSalaryMinor +
      extraDayAmountMinor +
      holidayAmountMinor +
      overtimeAmountMinor +
      bonusesMinor -
      deductionsMinor;

  /// Immutable snapshot persisted when a period is finalized.
  Map<String, dynamic> toSnapshotJson() => {
    'period_start': periodStart.toIso(),
    'period_end': periodEnd.toIso(),
    'expected_payment_date': expectedPaymentDate.toIso(),
    'currency_code': currencyCode,
    'base_salary_minor': baseSalaryMinor,
    'day_rate_minor': dayRateMinor,
    'hour_rate_minor': hourRateMinor,
    'extra_day_units_hundredths': extraDayUnitsHundredths,
    'extra_day_amount_minor': extraDayAmountMinor,
    'holiday_count': holidayCount,
    'holiday_amount_minor': holidayAmountMinor,
    'overtime_minutes': overtimeMinutes,
    'overtime_amount_minor': overtimeAmountMinor,
    'bonuses_minor': bonusesMinor,
    'deductions_minor': deductionsMinor,
    'total_minor': totalMinor,
  };
}
