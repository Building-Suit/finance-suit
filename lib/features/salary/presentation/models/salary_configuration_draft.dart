import 'package:flutter/widgets.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';

/// Mutable form state shared by onboarding and Salary Settings.
class SalaryConfigurationDraft {
  SalaryConfigurationDraft({
    required this.baseSalaryController,
    required this.periodStartDay,
    required this.paymentDay,
    required this.paymentMonthOffset,
    required this.paidDaysController,
    required this.hoursPerDayController,
    required this.dayRateMode,
    required this.manualDayRateController,
    required this.hourRateMode,
    required this.manualHourRateController,
    required this.extraDayPctController,
    required this.holidayPctController,
    required this.overtimePctController,
    required this.semantics,
    this.roundingMode = RoundingMode.halfUp,
  });

  factory SalaryConfigurationDraft.defaults() => SalaryConfigurationDraft(
    baseSalaryController: TextEditingController(),
    periodStartDay: 1,
    paymentDay: 1,
    paymentMonthOffset: 1,
    paidDaysController: TextEditingController(text: '22'),
    hoursPerDayController: TextEditingController(text: '8'),
    dayRateMode: RateMode.derived,
    manualDayRateController: TextEditingController(),
    hourRateMode: RateMode.derived,
    manualHourRateController: TextEditingController(),
    extraDayPctController: TextEditingController(text: '100'),
    holidayPctController: TextEditingController(text: '200'),
    overtimePctController: TextEditingController(text: '150'),
    semantics: HolidayMultiplierSemantics.additionalPay,
  );

  factory SalaryConfigurationDraft.fromSettings(SalarySettings settings) {
    String money(int? minor) => minor == null
        ? ''
        : (minor / Money.minorUnitsPerMajor).toStringAsFixed(2);
    return SalaryConfigurationDraft(
      baseSalaryController: TextEditingController(
        text: money(settings.baseSalaryMinor),
      ),
      periodStartDay: settings.salaryPeriodStartDay,
      paymentDay: settings.paymentDay,
      paymentMonthOffset: settings.paymentMonthOffset,
      paidDaysController: TextEditingController(
        text: '${settings.standardPaidDaysPerPeriod}',
      ),
      hoursPerDayController: TextEditingController(
        text: '${settings.standardMinutesPerDay ~/ 60}',
      ),
      dayRateMode: settings.dayRateMode,
      manualDayRateController: TextEditingController(
        text: money(settings.manualDayRateMinor),
      ),
      hourRateMode: settings.hourRateMode,
      manualHourRateController: TextEditingController(
        text: money(settings.manualHourRateMinor),
      ),
      extraDayPctController: TextEditingController(
        text: '${settings.extraDayMultiplierPct}',
      ),
      holidayPctController: TextEditingController(
        text: '${settings.officialHolidayMultiplierPct}',
      ),
      overtimePctController: TextEditingController(
        text: '${settings.overtimeMultiplierPct}',
      ),
      semantics: settings.holidaySemantics,
      roundingMode: settings.roundingMode,
    );
  }

  final TextEditingController baseSalaryController;
  int periodStartDay;
  int paymentDay;
  int paymentMonthOffset;
  final TextEditingController paidDaysController;
  final TextEditingController hoursPerDayController;
  RateMode dayRateMode;
  final TextEditingController manualDayRateController;
  RateMode hourRateMode;
  final TextEditingController manualHourRateController;
  final TextEditingController extraDayPctController;
  final TextEditingController holidayPctController;
  final TextEditingController overtimePctController;
  HolidayMultiplierSemantics semantics;
  RoundingMode roundingMode;

  Money? baseSalary(String currencyCode) =>
      Money.tryParse(baseSalaryController.text, currencyCode: currencyCode);

  Money? derivedDayRate(String currencyCode) {
    final base = baseSalary(currencyCode);
    final days = int.tryParse(paidDaysController.text);
    if (base == null || days == null || days < 1 || days > 31) return null;
    return base.divideBy(days);
  }

  Money? derivedHourRate(String currencyCode) {
    final dayRate = dayRateMode == RateMode.manual
        ? Money.tryParse(
            manualDayRateController.text,
            currencyCode: currencyCode,
          )
        : derivedDayRate(currencyCode);
    final hours = int.tryParse(hoursPerDayController.text);
    if (dayRate == null || hours == null || hours < 1 || hours > 24) {
      return null;
    }
    return dayRate.divideBy(hours);
  }

  SalarySettings toSettings({
    required bool salaryEnabled,
    required String currencyCode,
    required SalarySettings fallback,
  }) {
    final base = baseSalary(currencyCode)?.minor ?? fallback.baseSalaryMinor;
    return SalarySettings(
      salaryEnabled: salaryEnabled,
      baseSalaryMinor: base,
      currencyCode: currencyCode,
      salaryPeriodStartDay: periodStartDay,
      paymentDay: paymentDay,
      paymentMonthOffset: paymentMonthOffset,
      standardPaidDaysPerPeriod:
          int.tryParse(paidDaysController.text) ??
          fallback.standardPaidDaysPerPeriod,
      standardMinutesPerDay:
          (int.tryParse(hoursPerDayController.text) ??
              fallback.standardMinutesPerDay ~/ 60) *
          60,
      dayRateMode: dayRateMode,
      manualDayRateMinor: dayRateMode == RateMode.manual
          ? Money.tryParse(
              manualDayRateController.text,
              currencyCode: currencyCode,
            )?.minor
          : null,
      hourRateMode: hourRateMode,
      manualHourRateMinor: hourRateMode == RateMode.manual
          ? Money.tryParse(
              manualHourRateController.text,
              currencyCode: currencyCode,
            )?.minor
          : null,
      extraDayMultiplierPct:
          int.tryParse(extraDayPctController.text) ??
          fallback.extraDayMultiplierPct,
      officialHolidayMultiplierPct:
          int.tryParse(holidayPctController.text) ??
          fallback.officialHolidayMultiplierPct,
      overtimeMultiplierPct:
          int.tryParse(overtimePctController.text) ??
          fallback.overtimeMultiplierPct,
      holidaySemantics: semantics,
      roundingMode: roundingMode,
    );
  }

  void dispose() {
    for (final controller in [
      baseSalaryController,
      paidDaysController,
      hoursPerDayController,
      manualDayRateController,
      manualHourRateController,
      extraDayPctController,
      holidayPctController,
      overtimePctController,
    ]) {
      controller.dispose();
    }
  }
}
