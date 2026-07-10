import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';

/// Pure salary math. No I/O, no time reads: everything comes in as
/// arguments so the engine is deterministic and unit-testable.
///
/// All amounts are integer minor units. Multipliers are integer percent
/// (150 == 1.5x). Day units are hundredths (100 == one full day).
abstract final class SalaryCalculator {
  static MoneyRounding rounding(RoundingMode mode) => switch (mode) {
    RoundingMode.halfUp => MoneyRounding.halfUp,
    RoundingMode.halfEven => MoneyRounding.halfEven,
  };

  /// Day rate: manual override, else base salary / standard paid days.
  static Money dayRate(SalarySettings s) {
    if (s.dayRateMode == RateMode.manual && s.manualDayRateMinor != null) {
      return Money(minor: s.manualDayRateMinor!, currencyCode: s.currencyCode);
    }
    return Money(
      minor: s.baseSalaryMinor,
      currencyCode: s.currencyCode,
    ).divideBy(s.standardPaidDaysPerPeriod, rounding: rounding(s.roundingMode));
  }

  /// Hour rate: manual override, else day rate / standard hours per day.
  static Money hourRate(SalarySettings s) {
    if (s.hourRateMode == RateMode.manual && s.manualHourRateMinor != null) {
      return Money(minor: s.manualHourRateMinor!, currencyCode: s.currencyCode);
    }
    return dayRate(s).timesRational(
      60,
      s.standardMinutesPerDay,
      rounding: rounding(s.roundingMode),
    );
  }

  /// Extra pay earned by one work entry on top of base salary.
  ///
  /// - regular: no extra pay (covered by base salary).
  /// - overtime: hourRate x hours x overtime multiplier.
  /// - extra_day: dayRate x day units x extra-day multiplier.
  /// - holiday_worked: dayRate x day units (or minutes / standard day)
  ///   x effective holiday multiplier. With `additional_pay` semantics the
  ///   configured multiplier is all extra; with `total_including_base` the
  ///   base day is already paid, so the extra part is (multiplier - 100).
  ///
  /// [multiplierPctOverride] replaces the settings multiplier for this entry.
  /// [customRateMinor] replaces the hour rate (overtime) or day rate
  /// (extra_day / holiday_worked) for this entry.
  static EntryCalc entryAmount(
    SalarySettings s, {
    required WorkEntryType entryType,
    int? durationMinutes,
    int? dayUnitsHundredths,
    int? multiplierPctOverride,
    int? customRateMinor,
  }) {
    final mode = rounding(s.roundingMode);
    switch (entryType) {
      case WorkEntryType.regular:
        return EntryCalc(
          amount: Money.zero(s.currencyCode),
          snapshot: {
            'entry_type': entryType.dbValue,
            'duration_minutes': durationMinutes,
            'note': 'regular_day_included_in_base',
          },
        );
      case WorkEntryType.overtime:
        final minutes = durationMinutes!;
        final pct = multiplierPctOverride ?? s.overtimeMultiplierPct;
        final rate = customRateMinor != null
            ? Money(minor: customRateMinor, currencyCode: s.currencyCode)
            : hourRate(s);
        final amount = rate.timesRational(
          minutes * pct,
          60 * 100,
          rounding: mode,
        );
        return EntryCalc(
          amount: amount,
          snapshot: {
            'entry_type': entryType.dbValue,
            'duration_minutes': minutes,
            'multiplier_pct': pct,
            'hour_rate_minor': rate.minor,
            'rounding_mode': s.roundingMode.dbValue,
          },
        );
      case WorkEntryType.extraDay:
        final units = dayUnitsHundredths!;
        final pct = multiplierPctOverride ?? s.extraDayMultiplierPct;
        final rate = customRateMinor != null
            ? Money(minor: customRateMinor, currencyCode: s.currencyCode)
            : dayRate(s);
        final amount = rate.timesRational(
          units * pct,
          100 * 100,
          rounding: mode,
        );
        return EntryCalc(
          amount: amount,
          snapshot: {
            'entry_type': entryType.dbValue,
            'day_units_hundredths': units,
            'multiplier_pct': pct,
            'day_rate_minor': rate.minor,
            'rounding_mode': s.roundingMode.dbValue,
          },
        );
      case WorkEntryType.holidayWorked:
        final pct = multiplierPctOverride ?? s.officialHolidayMultiplierPct;
        final effectivePct = switch (s.holidaySemantics) {
          HolidayMultiplierSemantics.additionalPay => pct,
          HolidayMultiplierSemantics.totalIncludingBase =>
            pct > 100 ? pct - 100 : 0,
        };
        final rate = customRateMinor != null
            ? Money(minor: customRateMinor, currencyCode: s.currencyCode)
            : dayRate(s);
        // Day units win; otherwise derive units from worked minutes.
        final Money amount;
        final int? units = dayUnitsHundredths;
        if (units != null) {
          amount = rate.timesRational(
            units * effectivePct,
            100 * 100,
            rounding: mode,
          );
        } else {
          final minutes = durationMinutes!;
          amount = rate.timesRational(
            minutes * effectivePct,
            s.standardMinutesPerDay * 100,
            rounding: mode,
          );
        }
        return EntryCalc(
          amount: amount,
          snapshot: {
            'entry_type': entryType.dbValue,
            'day_units_hundredths': units,
            'duration_minutes': durationMinutes,
            'multiplier_pct': pct,
            'effective_pct': effectivePct,
            'semantics': s.holidaySemantics.dbValue,
            'day_rate_minor': rate.minor,
            'rounding_mode': s.roundingMode.dbValue,
          },
        );
    }
  }

  /// Duration in minutes from a start/end time-of-day pair minus break.
  /// End at or before start means the session crosses midnight.
  static int sessionMinutes({
    required int startMinuteOfDay,
    required int endMinuteOfDay,
    int breakMinutes = 0,
  }) {
    var span = endMinuteOfDay - startMinuteOfDay;
    if (span <= 0) span += 24 * 60;
    return span - breakMinutes;
  }
}

@immutable
class EntryCalc {
  const EntryCalc({required this.amount, required this.snapshot});

  final Money amount;

  /// Inputs used for the calculation, persisted as `calc_snapshot` so a
  /// stored amount can always be explained even after settings change.
  final Map<String, dynamic> snapshot;
}
