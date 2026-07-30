import 'package:flutter/material.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/salary/presentation/models/salary_configuration_draft.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Canonical salary form used by onboarding and Settings.
class SalaryConfigurationFields extends StatelessWidget {
  const SalaryConfigurationFields({
    super.key,
    required this.draft,
    required this.currencyCode,
    required this.onChanged,
    this.onFieldSubmitted,
  });

  final SalaryConfigurationDraft draft;
  final String currencyCode;
  final VoidCallback onChanged;
  final VoidCallback? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final dayRate = draft.derivedDayRate(currencyCode);
    final hourRate = draft.derivedHourRate(currencyCode);
    return Column(
      key: const Key('salary-configuration-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: draft.baseSalaryController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.salBaseSalary,
            suffixText: currencyCode,
          ),
          onChanged: (_) => onChanged(),
          onFieldSubmitted: (_) => onFieldSubmitted?.call(),
          validator: (value) => _amountValidation(context, value),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppSelectionField<int>(
                initialValue: draft.periodStartDay,
                decoration: InputDecoration(labelText: l10n.salPeriodStartDay),
                items: _days,
                onChanged: (value) {
                  draft.periodStartDay = value ?? 1;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppSelectionField<int>(
                initialValue: draft.paymentDay,
                decoration: InputDecoration(labelText: l10n.salPaymentDay),
                items: _days,
                onChanged: (value) {
                  draft.paymentDay = value ?? 1;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSelectionField<int>(
          initialValue: draft.paymentMonthOffset,
          decoration: InputDecoration(labelText: l10n.salPaymentMonthOffset),
          items: [
            DropdownMenuItem(value: 0, child: Text(l10n.salOffsetSameMonth)),
            DropdownMenuItem(value: 1, child: Text(l10n.salOffsetNextMonth)),
            DropdownMenuItem(value: 2, child: Text(l10n.salOffsetSecondMonth)),
          ],
          onChanged: (value) {
            draft.paymentMonthOffset = value ?? 1;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _durationField(
                context,
                controller: draft.paidDaysController,
                label: l10n.salStandardPaidDays,
                min: 1,
                max: 31,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _durationField(
                context,
                controller: draft.hoursPerDayController,
                label: l10n.salStandardHours,
                min: 1,
                max: 24,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _rateSection(
          context,
          label: l10n.salDayRate,
          mode: draft.dayRateMode,
          onModeChanged: (mode) {
            draft.dayRateMode = mode;
            onChanged();
          },
          controller: draft.manualDayRateController,
          manualLabel: l10n.salManualDayRate,
          preview: dayRate == null
              ? null
              : l10n.salDerivedDayRate(dayRate.format(locale: locale)),
        ),
        const SizedBox(height: 16),
        _rateSection(
          context,
          label: l10n.salHourRate,
          mode: draft.hourRateMode,
          onModeChanged: (mode) {
            draft.hourRateMode = mode;
            onChanged();
          },
          controller: draft.manualHourRateController,
          manualLabel: l10n.salManualHourRate,
          preview: hourRate == null
              ? null
              : l10n.salDerivedHourRate(hourRate.format(locale: locale)),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.salMultipliers,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              _percentageField(
                context,
                draft.extraDayPctController,
                l10n.salExtraDayMultiplier,
              ),
              _percentageField(
                context,
                draft.holidayPctController,
                l10n.salHolidayMultiplier,
              ),
              _percentageField(
                context,
                draft.overtimePctController,
                l10n.salOvertimeMultiplier,
              ),
            ];
            if (constraints.maxWidth < 520) {
              return Column(
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: field,
                    ),
                ],
              );
            }
            return Row(
              children: [
                for (var index = 0; index < fields.length; index++) ...[
                  Expanded(child: fields[index]),
                  if (index < fields.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          l10n.salHolidaySemantics,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        RadioGroup<HolidayMultiplierSemantics>(
          groupValue: draft.semantics,
          onChanged: (value) {
            draft.semantics = value ?? HolidayMultiplierSemantics.additionalPay;
            onChanged();
          },
          child: Column(
            children: [
              RadioListTile<HolidayMultiplierSemantics>(
                value: HolidayMultiplierSemantics.additionalPay,
                title: Text(l10n.salSemanticsAdditional),
              ),
              RadioListTile<HolidayMultiplierSemantics>(
                value: HolidayMultiplierSemantics.totalIncludingBase,
                title: Text(l10n.salSemanticsTotal),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<DropdownMenuItem<int>> get _days => [
    for (var day = 1; day <= 28; day++)
      DropdownMenuItem(value: day, child: Text('$day')),
  ];

  String? _amountValidation(BuildContext context, String? value) {
    final error = Validators.positiveAmount(value, currencyCode: currencyCode);
    return error == null ? null : validationMessage(context, error);
  }

  Widget _durationField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required int min,
    required int max,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => onChanged(),
    onFieldSubmitted: (_) => onFieldSubmitted?.call(),
    validator: (value) {
      final parsed = int.tryParse(value ?? '');
      if (parsed == null || parsed < min || parsed > max) {
        return validationMessage(context, ValidationError.invalidDuration);
      }
      return null;
    },
  );

  Widget _rateSection(
    BuildContext context, {
    required String label,
    required RateMode mode,
    required ValueChanged<RateMode> onModeChanged,
    required TextEditingController controller,
    required String manualLabel,
    required String? preview,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<RateMode>(
        segments: [
          ButtonSegment(
            value: RateMode.derived,
            label: Text(AppLocalizations.of(context).salRateDerived),
          ),
          ButtonSegment(
            value: RateMode.manual,
            label: Text(AppLocalizations.of(context).salRateManual),
          ),
        ],
        selected: {mode},
        onSelectionChanged: (selection) => onModeChanged(selection.first),
      ),
      if (mode == RateMode.manual) ...[
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: manualLabel,
            suffixText: currencyCode,
          ),
          onChanged: (_) => onChanged(),
          validator: (value) => _amountValidation(context, value),
        ),
      ] else if (preview != null) ...[
        const SizedBox(height: 8),
        Text(
          preview,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.infoColor(context)),
        ),
      ],
    ],
  );

  Widget _percentageField(
    BuildContext context,
    TextEditingController controller,
    String label,
  ) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => onChanged(),
    validator: (value) {
      final error = Validators.multiplierPct(int.tryParse(value ?? ''));
      return error == null ? null : validationMessage(context, error);
    },
  );
}
