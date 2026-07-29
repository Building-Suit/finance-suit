import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/data/settings_repository.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class SalarySettingsScreen extends ConsumerWidget {
  const SalarySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(salarySettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setSalarySection)),
      body: AsyncView(
        value: settings,
        onRetry: () => ref.invalidate(salarySettingsProvider),
        data: (s) => _SalarySettingsForm(initial: s),
      ),
    );
  }
}

class _SalarySettingsForm extends ConsumerStatefulWidget {
  const _SalarySettingsForm({required this.initial});

  final SalarySettings initial;

  @override
  ConsumerState<_SalarySettingsForm> createState() =>
      _SalarySettingsFormState();
}

class _SalarySettingsFormState extends ConsumerState<_SalarySettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _salaryEnabled;
  late final TextEditingController _baseSalaryController;
  late int _periodStartDay;
  late int _paymentDay;
  late int _paymentMonthOffset;
  late final TextEditingController _paidDaysController;
  late final TextEditingController _hoursPerDayController;
  late RateMode _dayRateMode;
  late final TextEditingController _manualDayRateController;
  late RateMode _hourRateMode;
  late final TextEditingController _manualHourRateController;
  late final TextEditingController _extraDayPctController;
  late final TextEditingController _holidayPctController;
  late final TextEditingController _overtimePctController;
  late HolidayMultiplierSemantics _semantics;
  late RoundingMode _roundingMode;
  bool _busy = false;
  AppFailure? _failure;

  String get _currency => widget.initial.currencyCode;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _salaryEnabled = s.salaryEnabled;
    String moneyText(int? minor) => minor == null
        ? ''
        : (Money(minor: minor, currencyCode: s.currencyCode).minor / 100)
              .toStringAsFixed(2);
    _baseSalaryController = TextEditingController(
      text: moneyText(s.baseSalaryMinor),
    );
    _periodStartDay = s.salaryPeriodStartDay;
    _paymentDay = s.paymentDay;
    _paymentMonthOffset = s.paymentMonthOffset;
    _paidDaysController = TextEditingController(
      text: '${s.standardPaidDaysPerPeriod}',
    );
    _hoursPerDayController = TextEditingController(
      text: '${s.standardMinutesPerDay ~/ 60}',
    );
    _dayRateMode = s.dayRateMode;
    _manualDayRateController = TextEditingController(
      text: moneyText(s.manualDayRateMinor),
    );
    _hourRateMode = s.hourRateMode;
    _manualHourRateController = TextEditingController(
      text: moneyText(s.manualHourRateMinor),
    );
    _extraDayPctController = TextEditingController(
      text: '${s.extraDayMultiplierPct}',
    );
    _holidayPctController = TextEditingController(
      text: '${s.officialHolidayMultiplierPct}',
    );
    _overtimePctController = TextEditingController(
      text: '${s.overtimeMultiplierPct}',
    );
    _semantics = s.holidaySemantics;
    _roundingMode = s.roundingMode;
  }

  @override
  void dispose() {
    for (final c in [
      _baseSalaryController,
      _paidDaysController,
      _hoursPerDayController,
      _manualDayRateController,
      _manualHourRateController,
      _extraDayPctController,
      _holidayPctController,
      _overtimePctController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Money? get _baseSalary =>
      Money.tryParse(_baseSalaryController.text, currencyCode: _currency);

  Money? get _derivedDayRate {
    final base = _baseSalary;
    final days = int.tryParse(_paidDaysController.text);
    if (base == null || days == null || days < 1 || days > 31) return null;
    return base.divideBy(days);
  }

  Money? get _derivedHourRate {
    final dayRate = _dayRateMode == RateMode.manual
        ? Money.tryParse(_manualDayRateController.text, currencyCode: _currency)
        : _derivedDayRate;
    final hours = int.tryParse(_hoursPerDayController.text);
    if (dayRate == null || hours == null || hours < 1 || hours > 24) {
      return null;
    }
    return dayRate.divideBy(hours);
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final updated = SalarySettings(
      salaryEnabled: _salaryEnabled,
      baseSalaryMinor: _salaryEnabled ? _baseSalary!.minor : 0,
      currencyCode: _currency,
      salaryPeriodStartDay: _periodStartDay,
      paymentDay: _paymentDay,
      paymentMonthOffset: _paymentMonthOffset,
      standardPaidDaysPerPeriod: int.parse(_paidDaysController.text),
      standardMinutesPerDay: int.parse(_hoursPerDayController.text) * 60,
      dayRateMode: _dayRateMode,
      manualDayRateMinor: _dayRateMode == RateMode.manual
          ? Money.tryParse(
              _manualDayRateController.text,
              currencyCode: _currency,
            )?.minor
          : null,
      hourRateMode: _hourRateMode,
      manualHourRateMinor: _hourRateMode == RateMode.manual
          ? Money.tryParse(
              _manualHourRateController.text,
              currencyCode: _currency,
            )?.minor
          : null,
      extraDayMultiplierPct: int.parse(_extraDayPctController.text),
      officialHolidayMultiplierPct: int.parse(_holidayPctController.text),
      overtimeMultiplierPct: int.parse(_overtimePctController.text),
      holidaySemantics: _semantics,
      roundingMode: _roundingMode,
    );
    final result = await ref
        .read(settingsRepositoryProvider)
        .updateSalarySettings(updated);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref.invalidate(salarySettingsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).setSaved)),
        );
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.incomeHasSalary),
              subtitle: Text(l10n.incomeHasSalaryHelp),
              value: _salaryEnabled,
              onChanged: (value) => setState(() => _salaryEnabled = value),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _baseSalaryController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.salBaseSalary,
                suffixText: _currency,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (!_salaryEnabled) return null;
                final e = Validators.positiveAmount(v, currencyCode: _currency);
                return e == null ? null : validationMessage(context, e);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _periodStartDay,
                    decoration: InputDecoration(
                      labelText: l10n.salPeriodStartDay,
                    ),
                    items: [
                      for (var d = 1; d <= 28; d++)
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (v) => setState(() => _periodStartDay = v ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _paymentDay,
                    decoration: InputDecoration(labelText: l10n.salPaymentDay),
                    items: [
                      for (var d = 1; d <= 28; d++)
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: (v) => setState(() => _paymentDay = v ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _paymentMonthOffset,
              decoration: InputDecoration(
                labelText: l10n.salPaymentMonthOffset,
              ),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(l10n.salOffsetSameMonth),
                ),
                DropdownMenuItem(
                  value: 1,
                  child: Text(l10n.salOffsetNextMonth),
                ),
                DropdownMenuItem(
                  value: 2,
                  child: Text(l10n.salOffsetSecondMonth),
                ),
              ],
              onChanged: (v) => setState(() => _paymentMonthOffset = v ?? 1),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _paidDaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.salStandardPaidDays,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 31) {
                        return validationMessage(
                          context,
                          ValidationError.invalidDuration,
                        );
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _hoursPerDayController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.salStandardHours,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 24) {
                        return validationMessage(
                          context,
                          ValidationError.invalidDuration,
                        );
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _rateSection(
              l10n: l10n,
              label: l10n.salDayRate,
              mode: _dayRateMode,
              onModeChanged: (m) => setState(() => _dayRateMode = m),
              manualController: _manualDayRateController,
              manualLabel: l10n.salManualDayRate,
              derivedPreview: _derivedDayRate == null
                  ? null
                  : l10n.salDerivedDayRate(
                      _derivedDayRate!.format(locale: locale),
                    ),
            ),
            const SizedBox(height: 16),
            _rateSection(
              l10n: l10n,
              label: l10n.salHourRate,
              mode: _hourRateMode,
              onModeChanged: (m) => setState(() => _hourRateMode = m),
              manualController: _manualHourRateController,
              manualLabel: l10n.salManualHourRate,
              derivedPreview: _derivedHourRate == null
                  ? null
                  : l10n.salDerivedHourRate(
                      _derivedHourRate!.format(locale: locale),
                    ),
            ),
            const SizedBox(height: 24),
            Text(l10n.salMultipliers, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _pctField(
                    controller: _extraDayPctController,
                    label: l10n.salExtraDayMultiplier,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _pctField(
                    controller: _holidayPctController,
                    label: l10n.salHolidayMultiplier,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _pctField(
                    controller: _overtimePctController,
                    label: l10n.salOvertimeMultiplier,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.salHolidaySemantics, style: theme.textTheme.labelLarge),
            RadioGroup<HolidayMultiplierSemantics>(
              groupValue: _semantics,
              onChanged: (v) => setState(
                () =>
                    _semantics = v ?? HolidayMultiplierSemantics.additionalPay,
              ),
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
            const SizedBox(height: 16),
            AuthErrorBanner(failure: _failure),
            AuthSubmitButton(
              label: l10n.commonSave,
              busy: _busy,
              onPressed: _save,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _rateSection({
    required AppLocalizations l10n,
    required String label,
    required RateMode mode,
    required ValueChanged<RateMode> onModeChanged,
    required TextEditingController manualController,
    required String manualLabel,
    required String? derivedPreview,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<RateMode>(
          segments: [
            ButtonSegment(
              value: RateMode.derived,
              label: Text(l10n.salRateDerived),
            ),
            ButtonSegment(
              value: RateMode.manual,
              label: Text(l10n.salRateManual),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
        if (mode == RateMode.manual) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: manualController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: manualLabel,
              suffixText: _currency,
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final e = Validators.positiveAmount(v, currencyCode: _currency);
              return e == null ? null : validationMessage(context, e);
            },
          ),
        ] else if (derivedPreview != null) ...[
          const SizedBox(height: 8),
          Text(
            derivedPreview,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.infoColor(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pctField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final e = Validators.multiplierPct(int.tryParse(v ?? ''));
        return e == null ? null : validationMessage(context, e);
      },
    );
  }
}
