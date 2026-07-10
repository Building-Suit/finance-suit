import 'package:flutter/material.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Itemized salary estimate card. The spec forbids showing only a total,
/// so every consumer renders this full breakdown.
class EstimateBreakdownCard extends StatelessWidget {
  const EstimateBreakdownCard({super.key, required this.estimate});

  final SalaryEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = estimate.currencyCode;
    String money(int minor) =>
        Money(minor: minor, currencyCode: currency).format();

    Widget row(String label, String value, {String? detail}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(detail == null ? label : '$label ($detail)')),
          Text(
            value,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    final overtime = l10n.workDurationHm(
      estimate.overtimeMinutes ~/ 60,
      estimate.overtimeMinutes % 60,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.salBreakdown,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            row(l10n.salBaseSalary, money(estimate.baseSalaryMinor)),
            row(l10n.salDayRate, money(estimate.dayRateMinor)),
            row(l10n.salHourRate, money(estimate.hourRateMinor)),
            const Divider(),
            row(
              l10n.salItemExtraDays,
              money(estimate.extraDayAmountMinor),
              detail: (estimate.extraDayUnitsHundredths / 100).toStringAsFixed(
                2,
              ),
            ),
            row(
              l10n.salItemHolidays,
              money(estimate.holidayAmountMinor),
              detail: '${estimate.holidayCount}',
            ),
            row(
              l10n.salItemOvertime,
              money(estimate.overtimeAmountMinor),
              detail: overtime,
            ),
            row(l10n.salItemBonuses, money(estimate.bonusesMinor)),
            row(l10n.salItemDeductions, '-${money(estimate.deductionsMinor)}'),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.salEstimatedTotal,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    money(estimate.totalMinor),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            for (final warning in estimate.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(estimateWarningText(l10n, warning))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String estimateWarningText(
  AppLocalizations l10n,
  SalaryEstimateWarning warning,
) {
  return switch (warning) {
    SalaryEstimateWarning.baseSalaryZero => l10n.salWarnBaseZero,
    SalaryEstimateWarning.entriesMissingAmounts => l10n.salWarnMissingAmounts,
  };
}

String periodStatusLabel(AppLocalizations l10n, SalaryPeriodStatus status) {
  return switch (status) {
    SalaryPeriodStatus.open => l10n.salStatusOpen,
    SalaryPeriodStatus.finalized => l10n.salStatusFinalized,
    SalaryPeriodStatus.paid => l10n.salStatusPaid,
  };
}
