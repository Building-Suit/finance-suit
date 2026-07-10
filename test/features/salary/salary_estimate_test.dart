import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';

void main() {
  final settings = SalarySettings.defaults.copyWith(
    baseSalaryMinor: 1200000, // EGP 12,000.00
    standardPaidDaysPerPeriod: 26,
    standardMinutesPerDay: 480,
    salaryPeriodStartDay: 1,
    paymentDay: 25,
    paymentMonthOffset: 1,
  );

  group('SalaryPeriods.boundsFor', () {
    test('date on/after start day falls in period starting that month', () {
      final bounds = SalaryPeriods.boundsFor(
        settings.copyWith(salaryPeriodStartDay: 10),
        const PlainDate(2026, 7, 15),
      );
      expect(bounds.start, const PlainDate(2026, 7, 10));
      expect(bounds.end, const PlainDate(2026, 8, 9));
    });

    test('date before start day falls in period starting previous month', () {
      final bounds = SalaryPeriods.boundsFor(
        settings.copyWith(salaryPeriodStartDay: 10),
        const PlainDate(2026, 7, 5),
      );
      expect(bounds.start, const PlainDate(2026, 6, 10));
      expect(bounds.end, const PlainDate(2026, 7, 9));
    });

    test('calendar-month period spans exactly one month', () {
      final bounds = SalaryPeriods.boundsFor(
        settings,
        const PlainDate(2026, 2, 14),
      );
      expect(bounds.start, const PlainDate(2026, 2, 1));
      expect(bounds.end, const PlainDate(2026, 2, 28));
    });

    test('payment date honors month offset and payment day', () {
      final bounds = SalaryPeriods.boundsFor(
        settings,
        const PlainDate(2026, 7, 10),
      );
      expect(bounds.expectedPaymentDate, const PlainDate(2026, 8, 25));
    });

    test('same-month payment offset', () {
      final bounds = SalaryPeriods.boundsFor(
        settings.copyWith(paymentMonthOffset: 0),
        const PlainDate(2026, 7, 10),
      );
      expect(bounds.expectedPaymentDate, const PlainDate(2026, 7, 25));
    });
  });

  group('SalaryEstimate.compute', () {
    WorkEntry entry(
      WorkEntryType type, {
      int? minutes,
      int? units,
      int? amount,
    }) => WorkEntry(
      id: 'e',
      workDate: const PlainDate(2026, 7, 5),
      entryType: type,
      breakMinutes: 0,
      durationMinutes: minutes,
      dayUnitsHundredths: units,
      computedAmountMinor: amount,
    );

    final bounds = SalaryPeriods.boundsFor(
      settings,
      const PlainDate(2026, 7, 10),
    );

    test('itemizes and totals base + work + adjustments', () {
      final estimate = SalaryEstimate.compute(
        settings,
        bounds: bounds,
        entries: [
          entry(WorkEntryType.regular, minutes: 480),
          entry(WorkEntryType.overtime, minutes: 120, amount: 17307),
          entry(WorkEntryType.extraDay, units: 100, amount: 46154),
          entry(WorkEntryType.holidayWorked, units: 100, amount: 92308),
        ],
        adjustments: [
          const SalaryAdjustment(
            id: 'a1',
            effectiveDate: PlainDate(2026, 7, 6),
            adjustmentType: AdjustmentType.bonus,
            amountMinor: 50000,
          ),
          const SalaryAdjustment(
            id: 'a2',
            effectiveDate: PlainDate(2026, 7, 7),
            adjustmentType: AdjustmentType.deduction,
            amountMinor: 20000,
          ),
        ],
      );
      expect(estimate.baseSalaryMinor, 1200000);
      expect(estimate.overtimeMinutes, 120);
      expect(estimate.overtimeAmountMinor, 17307);
      expect(estimate.extraDayUnitsHundredths, 100);
      expect(estimate.extraDayAmountMinor, 46154);
      expect(estimate.holidayCount, 1);
      expect(estimate.holidayAmountMinor, 92308);
      expect(estimate.bonusesMinor, 50000);
      expect(estimate.deductionsMinor, 20000);
      expect(
        estimate.totalMinor,
        1200000 + 17307 + 46154 + 92308 + 50000 - 20000,
      );
      expect(estimate.warnings, isEmpty);
    });

    test('regular entries never add pay', () {
      final estimate = SalaryEstimate.compute(
        settings,
        bounds: bounds,
        entries: [entry(WorkEntryType.regular, minutes: 480)],
        adjustments: const [],
      );
      expect(estimate.totalMinor, 1200000);
    });

    test('warns on unconfigured base salary', () {
      final estimate = SalaryEstimate.compute(
        SalarySettings.defaults,
        bounds: bounds,
        entries: const [],
        adjustments: const [],
      );
      expect(estimate.warnings, contains(SalaryEstimateWarning.baseSalaryZero));
    });

    test('warns when a paid entry is missing its stored amount', () {
      final estimate = SalaryEstimate.compute(
        settings,
        bounds: bounds,
        entries: [entry(WorkEntryType.overtime, minutes: 60)],
        adjustments: const [],
      );
      expect(
        estimate.warnings,
        contains(SalaryEstimateWarning.entriesMissingAmounts),
      );
    });

    test('snapshot round-trips through fromSnapshot', () {
      final estimate = SalaryEstimate.compute(
        settings,
        bounds: bounds,
        entries: [entry(WorkEntryType.overtime, minutes: 120, amount: 17307)],
        adjustments: const [],
      );
      final restored = SalaryEstimate.fromSnapshot(estimate.toSnapshotJson());
      expect(restored.totalMinor, estimate.totalMinor);
      expect(restored.periodStart, estimate.periodStart);
      expect(restored.periodEnd, estimate.periodEnd);
      expect(restored.expectedPaymentDate, estimate.expectedPaymentDate);
      expect(restored.overtimeAmountMinor, 17307);
      expect(restored.dayRateMinor, estimate.dayRateMinor);
    });
  });
}
