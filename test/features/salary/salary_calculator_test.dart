import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/salary/domain/salary_calculator.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';

void main() {
  // 12,000 EGP base, 26 paid days, 8h days.
  final settings = SalarySettings.defaults.copyWith(
    baseSalaryMinor: 1200000,
    standardPaidDaysPerPeriod: 26,
    standardMinutesPerDay: 480,
    extraDayMultiplierPct: 100,
    officialHolidayMultiplierPct: 200,
    overtimeMultiplierPct: 150,
  );

  group('rates', () {
    test('derived day rate divides base by paid days with rounding', () {
      // 1,200,000 / 26 = 46,153.846 -> 46,154
      expect(SalaryCalculator.dayRate(settings).minor, 46154);
    });

    test('derived hour rate divides day rate by standard hours', () {
      // 46,154 * 60 / 480 = 5,769.25 -> 5,769
      expect(SalaryCalculator.hourRate(settings).minor, 5769);
    });

    test('manual rates override derivation', () {
      final manual = settings.copyWith(
        dayRateMode: RateMode.manual,
        manualDayRateMinor: () => 50000,
        hourRateMode: RateMode.manual,
        manualHourRateMinor: () => 7000,
      );
      expect(SalaryCalculator.dayRate(manual).minor, 50000);
      expect(SalaryCalculator.hourRate(manual).minor, 7000);
    });

    test('manual day rate feeds derived hour rate', () {
      final mixed = settings.copyWith(
        dayRateMode: RateMode.manual,
        manualDayRateMinor: () => 48000,
      );
      // 48,000 * 60 / 480 = 6,000
      expect(SalaryCalculator.hourRate(mixed).minor, 6000);
    });
  });

  group('entryAmount', () {
    test('regular day adds nothing on top of base', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.regular,
        durationMinutes: 480,
      );
      expect(calc.amount.minor, 0);
    });

    test('overtime pays hour rate x hours x multiplier', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.overtime,
        durationMinutes: 120,
      );
      // 5,769 * 120 * 150 / 6000 = 17,307
      expect(calc.amount.minor, 17307);
      expect(calc.snapshot['multiplier_pct'], 150);
    });

    test('overtime multiplier override', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.overtime,
        durationMinutes: 60,
        multiplierPctOverride: 200,
      );
      // 5,769 * 60 * 200 / 6000 = 11,538
      expect(calc.amount.minor, 11538);
    });

    test('overtime custom hour rate override', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.overtime,
        durationMinutes: 60,
        customRateMinor: 10000,
      );
      // 10,000 * 60 * 150 / 6000 = 15,000
      expect(calc.amount.minor, 15000);
    });

    test('extra day pays day rate x units x multiplier', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.extraDay,
        dayUnitsHundredths: 100,
      );
      // 46,154 * 100 * 100 / 10000 = 46,154
      expect(calc.amount.minor, 46154);
    });

    test('half extra day', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.extraDay,
        dayUnitsHundredths: 50,
      );
      // 46,154 * 50 * 100 / 10000 = 23,077
      expect(calc.amount.minor, 23077);
    });

    test('holiday additional_pay semantics: multiplier is all extra', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.holidayWorked,
        dayUnitsHundredths: 100,
      );
      // additional_pay 200% -> 46,154 * 2 = 92,308
      expect(calc.amount.minor, 92308);
      expect(calc.snapshot['effective_pct'], 200);
    });

    test('holiday total_including_base semantics subtracts the base day', () {
      final total = settings.copyWith(
        holidaySemantics: HolidayMultiplierSemantics.totalIncludingBase,
      );
      final calc = SalaryCalculator.entryAmount(
        total,
        entryType: WorkEntryType.holidayWorked,
        dayUnitsHundredths: 100,
      );
      // 200% total including base -> extra 100% -> 46,154
      expect(calc.amount.minor, 46154);
      expect(calc.snapshot['effective_pct'], 100);
    });

    test('holiday total_including_base never goes negative', () {
      final total = settings.copyWith(
        holidaySemantics: HolidayMultiplierSemantics.totalIncludingBase,
        officialHolidayMultiplierPct: 80,
      );
      final calc = SalaryCalculator.entryAmount(
        total,
        entryType: WorkEntryType.holidayWorked,
        dayUnitsHundredths: 100,
      );
      expect(calc.amount.minor, 0);
    });

    test('holiday minutes fall back when day units missing', () {
      final calc = SalaryCalculator.entryAmount(
        settings,
        entryType: WorkEntryType.holidayWorked,
        durationMinutes: 240,
      );
      // Half a day at 200% -> 46,154 * 240 * 200 / 48000 = 46,154
      expect(calc.amount.minor, 46154);
    });
  });

  group('sessionMinutes', () {
    test('same-day session minus break', () {
      expect(
        SalaryCalculator.sessionMinutes(
          startMinuteOfDay: 9 * 60,
          endMinuteOfDay: 17 * 60,
          breakMinutes: 60,
        ),
        420,
      );
    });

    test('overnight session wraps past midnight', () {
      expect(
        SalaryCalculator.sessionMinutes(
          startMinuteOfDay: 22 * 60,
          endMinuteOfDay: 6 * 60,
        ),
        480,
      );
    });
  });
}
