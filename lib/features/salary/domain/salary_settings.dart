import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

/// Salary configuration used by the pure salary engine and the settings UI.
/// All money values are integer minor units; multipliers are integer percent
/// (150 == 1.5x).
@immutable
class SalarySettings {
  const SalarySettings({
    required this.salaryEnabled,
    required this.baseSalaryMinor,
    required this.currencyCode,
    required this.salaryPeriodStartDay,
    required this.paymentDay,
    required this.paymentMonthOffset,
    required this.standardPaidDaysPerPeriod,
    required this.standardMinutesPerDay,
    required this.dayRateMode,
    required this.manualDayRateMinor,
    required this.hourRateMode,
    required this.manualHourRateMinor,
    required this.extraDayMultiplierPct,
    required this.officialHolidayMultiplierPct,
    required this.overtimeMultiplierPct,
    required this.holidaySemantics,
    required this.roundingMode,
  });

  factory SalarySettings.fromJson(Map<String, dynamic> json) => SalarySettings(
    salaryEnabled: json['salary_enabled'] as bool? ?? true,
    baseSalaryMinor: json['base_salary_minor'] as int,
    currencyCode: json['currency_code'] as String,
    salaryPeriodStartDay: json['salary_period_start_day'] as int,
    paymentDay: json['payment_day'] as int,
    paymentMonthOffset: json['payment_month_offset'] as int,
    standardPaidDaysPerPeriod: json['standard_paid_days_per_period'] as int,
    standardMinutesPerDay: json['standard_minutes_per_day'] as int,
    dayRateMode: RateMode.fromDb(json['day_rate_mode'] as String),
    manualDayRateMinor: json['manual_day_rate_minor'] as int?,
    hourRateMode: RateMode.fromDb(json['hour_rate_mode'] as String),
    manualHourRateMinor: json['manual_hour_rate_minor'] as int?,
    extraDayMultiplierPct: json['extra_day_multiplier_pct'] as int,
    officialHolidayMultiplierPct:
        json['official_holiday_multiplier_pct'] as int,
    overtimeMultiplierPct: json['overtime_multiplier_pct'] as int,
    holidaySemantics: HolidayMultiplierSemantics.fromDb(
      json['official_holiday_multiplier_semantics'] as String,
    ),
    roundingMode: RoundingMode.fromDb(json['rounding_mode'] as String),
  );

  final bool salaryEnabled;
  final int baseSalaryMinor;
  final String currencyCode;
  final int salaryPeriodStartDay;
  final int paymentDay;
  final int paymentMonthOffset;
  final int standardPaidDaysPerPeriod;
  final int standardMinutesPerDay;
  final RateMode dayRateMode;
  final int? manualDayRateMinor;
  final RateMode hourRateMode;
  final int? manualHourRateMinor;
  final int extraDayMultiplierPct;
  final int officialHolidayMultiplierPct;
  final int overtimeMultiplierPct;
  final HolidayMultiplierSemantics holidaySemantics;
  final RoundingMode roundingMode;

  Map<String, dynamic> toUpdateJson() => {
    'salary_enabled': salaryEnabled,
    'base_salary_minor': baseSalaryMinor,
    'currency_code': currencyCode,
    'salary_period_start_day': salaryPeriodStartDay,
    'payment_day': paymentDay,
    'payment_month_offset': paymentMonthOffset,
    'standard_paid_days_per_period': standardPaidDaysPerPeriod,
    'standard_minutes_per_day': standardMinutesPerDay,
    'day_rate_mode': dayRateMode.dbValue,
    'manual_day_rate_minor': manualDayRateMinor,
    'hour_rate_mode': hourRateMode.dbValue,
    'manual_hour_rate_minor': manualHourRateMinor,
    'extra_day_multiplier_pct': extraDayMultiplierPct,
    'official_holiday_multiplier_pct': officialHolidayMultiplierPct,
    'overtime_multiplier_pct': overtimeMultiplierPct,
    'official_holiday_multiplier_semantics': holidaySemantics.dbValue,
    'rounding_mode': roundingMode.dbValue,
  };

  SalarySettings copyWith({
    bool? salaryEnabled,
    int? baseSalaryMinor,
    String? currencyCode,
    int? salaryPeriodStartDay,
    int? paymentDay,
    int? paymentMonthOffset,
    int? standardPaidDaysPerPeriod,
    int? standardMinutesPerDay,
    RateMode? dayRateMode,
    int? Function()? manualDayRateMinor,
    RateMode? hourRateMode,
    int? Function()? manualHourRateMinor,
    int? extraDayMultiplierPct,
    int? officialHolidayMultiplierPct,
    int? overtimeMultiplierPct,
    HolidayMultiplierSemantics? holidaySemantics,
    RoundingMode? roundingMode,
  }) {
    return SalarySettings(
      salaryEnabled: salaryEnabled ?? this.salaryEnabled,
      baseSalaryMinor: baseSalaryMinor ?? this.baseSalaryMinor,
      currencyCode: currencyCode ?? this.currencyCode,
      salaryPeriodStartDay: salaryPeriodStartDay ?? this.salaryPeriodStartDay,
      paymentDay: paymentDay ?? this.paymentDay,
      paymentMonthOffset: paymentMonthOffset ?? this.paymentMonthOffset,
      standardPaidDaysPerPeriod:
          standardPaidDaysPerPeriod ?? this.standardPaidDaysPerPeriod,
      standardMinutesPerDay:
          standardMinutesPerDay ?? this.standardMinutesPerDay,
      dayRateMode: dayRateMode ?? this.dayRateMode,
      manualDayRateMinor: manualDayRateMinor != null
          ? manualDayRateMinor()
          : this.manualDayRateMinor,
      hourRateMode: hourRateMode ?? this.hourRateMode,
      manualHourRateMinor: manualHourRateMinor != null
          ? manualHourRateMinor()
          : this.manualHourRateMinor,
      extraDayMultiplierPct:
          extraDayMultiplierPct ?? this.extraDayMultiplierPct,
      officialHolidayMultiplierPct:
          officialHolidayMultiplierPct ?? this.officialHolidayMultiplierPct,
      overtimeMultiplierPct:
          overtimeMultiplierPct ?? this.overtimeMultiplierPct,
      holidaySemantics: holidaySemantics ?? this.holidaySemantics,
      roundingMode: roundingMode ?? this.roundingMode,
    );
  }

  static const defaults = SalarySettings(
    salaryEnabled: true,
    baseSalaryMinor: 0,
    currencyCode: 'EGP',
    salaryPeriodStartDay: 1,
    paymentDay: 1,
    paymentMonthOffset: 1,
    standardPaidDaysPerPeriod: 22,
    standardMinutesPerDay: 480,
    dayRateMode: RateMode.derived,
    manualDayRateMinor: null,
    hourRateMode: RateMode.derived,
    manualHourRateMinor: null,
    extraDayMultiplierPct: 100,
    officialHolidayMultiplierPct: 200,
    overtimeMultiplierPct: 150,
    holidaySemantics: HolidayMultiplierSemantics.additionalPay,
    roundingMode: RoundingMode.halfUp,
  );
}
