import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/onboarding/data/onboarding_repository.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';
import 'package:work_tracker/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Weekday label for ISO weekday 1 (Mon) .. 7 (Sun) in the current locale.
String weekdayName(BuildContext context, int isoWeekday) {
  // 2024-01-01 is a Monday.
  final date = DateTime(2024, 1, isoWeekday);
  return DateFormat.EEEE(
    Localizations.localeOf(context).toString(),
  ).format(date);
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;
  int _step = 0;
  bool _busy = false;
  AppFailure? _failure;

  // Step keys let each step validate independently.
  final _profileFormKey = GlobalKey<FormState>();
  final _salaryFormKey = GlobalKey<FormState>();
  final _accountFormKey = GlobalKey<FormState>();

  // Step 1: profile
  final _displayNameController = TextEditingController();
  final _currencyController = TextEditingController(text: 'EGP');
  String _locale = 'en';
  int _weekStartsOn = 6; // Saturday
  final Set<int> _weekendDays = {5, 6}; // Fri, Sat

  // Step 2: salary
  final _baseSalaryController = TextEditingController();
  int _periodStartDay = 1;
  int _paymentDay = 1;
  int _paymentMonthOffset = 1;
  final _paidDaysController = TextEditingController(text: '22');
  final _hoursPerDayController = TextEditingController(text: '8');
  RateMode _dayRateMode = RateMode.derived;
  final _manualDayRateController = TextEditingController();
  RateMode _hourRateMode = RateMode.derived;
  final _manualHourRateController = TextEditingController();
  final _extraDayPctController = TextEditingController(text: '100');
  final _holidayPctController = TextEditingController(text: '200');
  final _overtimePctController = TextEditingController(text: '150');
  HolidayMultiplierSemantics _semantics =
      HolidayMultiplierSemantics.additionalPay;

  // Step 3: account
  final _accountNameController = TextEditingController();
  AccountType _accountType = AccountType.current;
  final _openingBalanceController = TextEditingController(text: '0');
  bool _allowNegative = false;

  @override
  void initState() {
    super.initState();
    _locale = ref.read(appLocaleProvider)?.languageCode ?? 'en';
  }

  @override
  void dispose() {
    for (final c in [
      _displayNameController,
      _currencyController,
      _baseSalaryController,
      _paidDaysController,
      _hoursPerDayController,
      _manualDayRateController,
      _manualHourRateController,
      _extraDayPctController,
      _holidayPctController,
      _overtimePctController,
      _accountNameController,
      _openingBalanceController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _currency => _currencyController.text.trim().toUpperCase();

  Money? get _baseSalary =>
      Money.tryParse(_baseSalaryController.text, currencyCode: _currency);

  /// Live derived day-rate preview: base / standard paid days.
  Money? get _derivedDayRate {
    final base = _baseSalary;
    final days = int.tryParse(_paidDaysController.text);
    if (base == null || days == null || days < 1 || days > 31) return null;
    return base.divideBy(days);
  }

  /// Live derived hourly-rate preview: day rate / standard hours.
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

  bool _validateStep(int step) {
    return switch (step) {
      0 => _profileFormKey.currentState!.validate(),
      1 => _salaryFormKey.currentState!.validate(),
      2 => _accountFormKey.currentState!.validate(),
      _ => true,
    };
  }

  void _next() {
    if (!_validateStep(_step)) return;
    setState(() => _step++);
  }

  void _back() => setState(() => _step--);

  Future<void> _finish() async {
    setState(() {
      _failure = null;
      _busy = true;
    });
    final submission = OnboardingSubmission(
      displayName: _displayNameController.text.trim(),
      currencyCode: _currency,
      // Not user-facing; the app operates on the spec's default timezone.
      timezone: 'Africa/Cairo',
      locale: _locale,
      weekStartsOn: _weekStartsOn,
      weekendDays: _weekendDays.toList()..sort(),
      baseSalaryMinor: _baseSalary!.minor,
      salaryPeriodStartDay: _periodStartDay,
      paymentDay: _paymentDay,
      paymentMonthOffset: _paymentMonthOffset,
      standardPaidDays: int.parse(_paidDaysController.text),
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
      accountName: _accountNameController.text.trim(),
      accountType: _accountType,
      openingBalanceMinor: Money.tryParse(
        _openingBalanceController.text,
        currencyCode: _currency,
      )!.minor,
      allowNegativeBalance: _allowNegative,
    );
    final result = await ref
        .read(onboardingRepositoryProvider)
        .completeOnboarding(submission);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        // Persist the chosen locale locally, then let the router move on.
        ref.read(appLocaleProvider.notifier).setLocale(Locale(_locale));
        ref.read(onboardingStatusProvider.notifier).markComplete();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stepTitles = [
      l10n.onbStepProfile,
      l10n.onbStepSalary,
      l10n.onbStepAccount,
      l10n.onbStepReview,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.onbWelcome),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.onbStepProgress(_step + 1, _stepCount),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (_step + 1) / _stepCount,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stepTitles[_step],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            Expanded(
              // LayoutBuilder measures the space this screen actually has on
              // the device. The step actions live inside the scroll view and
              // are pushed to the bottom of that measured space, so they are
              // always either visible or reachable by scrolling — they never
              // depend on Scaffold slots or system-inset reporting.
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: switch (_step) {
                              0 => _buildProfileStep(l10n),
                              1 => _buildSalaryStep(l10n),
                              2 => _buildAccountStep(l10n),
                              _ => _buildReviewStep(l10n),
                            },
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              children: [
                                if (_step > 0)
                                  OutlinedButton(
                                    onPressed: _busy ? null : _back,
                                    child: Text(l10n.commonBack),
                                  ),
                                const Spacer(),
                                if (_step < _stepCount - 1)
                                  FilledButton(
                                    onPressed: _next,
                                    child: Text(l10n.commonNext),
                                  )
                                else
                                  AuthSubmitButton(
                                    label: l10n.onbFinish,
                                    busy: _busy,
                                    onPressed: _finish,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStep(AppLocalizations l10n) {
    return Form(
      key: _profileFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _displayNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.authFullName),
            validator: (v) {
              final e = Validators.requiredText(v, maxLength: 120);
              return e == null ? null : validationMessage(context, e);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _locale,
            decoration: InputDecoration(labelText: l10n.onbLanguage),
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _locale = v);
              ref.read(appLocaleProvider.notifier).setLocale(Locale(v));
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _currencyController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 3,
            decoration: InputDecoration(
              labelText: l10n.onbCurrency,
              counterText: '',
            ),
            validator: (v) {
              if (v == null || !RegExp(r'^[A-Za-z]{3}$').hasMatch(v.trim())) {
                return validationMessage(context, ValidationError.required);
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _weekStartsOn,
            decoration: InputDecoration(labelText: l10n.onbWeekStart),
            items: [
              for (var d = 1; d <= 7; d++)
                DropdownMenuItem(
                  value: d,
                  child: Text(weekdayName(context, d)),
                ),
            ],
            onChanged: (v) => setState(() => _weekStartsOn = v ?? 6),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l10n.onbWeekendDays,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayName(context, d)),
                  selected: _weekendDays.contains(d),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        if (_weekendDays.length < 3) _weekendDays.add(d);
                      } else {
                        if (_weekendDays.length > 1) _weekendDays.remove(d);
                      }
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryStep(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Form(
      key: _salaryFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _baseSalaryController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.salBaseSalary,
              suffixText: _currency,
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
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
            decoration: InputDecoration(labelText: l10n.salPaymentMonthOffset),
            items: [
              DropdownMenuItem(value: 0, child: Text(l10n.salOffsetSameMonth)),
              DropdownMenuItem(value: 1, child: Text(l10n.salOffsetNextMonth)),
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
                  decoration: InputDecoration(labelText: l10n.salStandardHours),
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
          _rateModeSection(
            l10n: l10n,
            label: l10n.salDayRate,
            mode: _dayRateMode,
            onModeChanged: (m) => setState(() => _dayRateMode = m),
            manualController: _manualDayRateController,
            manualLabel: l10n.salManualDayRate,
            derivedPreview: _derivedDayRate == null
                ? null
                : l10n.salDerivedDayRate(
                    _derivedDayRate!.format(
                      locale: Localizations.localeOf(context).toString(),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          _rateModeSection(
            l10n: l10n,
            label: l10n.salHourRate,
            mode: _hourRateMode,
            onModeChanged: (m) => setState(() => _hourRateMode = m),
            manualController: _manualHourRateController,
            manualLabel: l10n.salManualHourRate,
            derivedPreview: _derivedHourRate == null
                ? null
                : l10n.salDerivedHourRate(
                    _derivedHourRate!.format(
                      locale: Localizations.localeOf(context).toString(),
                    ),
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
              () => _semantics = v ?? HolidayMultiplierSemantics.additionalPay,
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
        ],
      ),
    );
  }

  Widget _rateModeSection({
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
              color: Theme.of(context).colorScheme.primary,
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

  Widget _buildAccountStep(AppLocalizations l10n) {
    return Form(
      key: _accountFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _accountNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.accName),
            validator: (v) {
              final e = Validators.requiredText(v, maxLength: 80);
              return e == null ? null : validationMessage(context, e);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<AccountType>(
            initialValue: _accountType,
            decoration: InputDecoration(labelText: l10n.accType),
            items: [
              for (final type in AccountType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(accountTypeLabel(l10n, type)),
                ),
            ],
            onChanged: (v) =>
                setState(() => _accountType = v ?? AccountType.current),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _openingBalanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.accOpeningBalance,
              suffixText: _currency,
            ),
            validator: (v) {
              final e = Validators.nonNegativeAmount(
                v,
                currencyCode: _currency,
              );
              return e == null ? null : validationMessage(context, e);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.accAllowNegative),
            value: _allowNegative,
            onChanged: (v) => setState(() => _allowNegative = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep(AppLocalizations l10n) {
    final locale = Localizations.localeOf(context).toString();
    final base = _baseSalary;
    String money(Money? m) => m?.format(locale: locale) ?? '—';

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                row(l10n.authFullName, _displayNameController.text.trim()),
                row(l10n.onbCurrency, _currency),
                row(l10n.onbWeekStart, weekdayName(context, _weekStartsOn)),
                row(
                  l10n.onbWeekendDays,
                  (_weekendDays.toList()..sort())
                      .map((d) => weekdayName(context, d))
                      .join('، '),
                ),
                const Divider(),
                row(l10n.salBaseSalary, money(base)),
                row(l10n.salPeriodStartDay, '$_periodStartDay'),
                row(l10n.salPaymentDay, '$_paymentDay'),
                row(l10n.salPaymentMonthOffset, switch (_paymentMonthOffset) {
                  0 => l10n.salOffsetSameMonth,
                  1 => l10n.salOffsetNextMonth,
                  _ => l10n.salOffsetSecondMonth,
                }),
                row(l10n.salStandardPaidDays, _paidDaysController.text),
                row(l10n.salStandardHours, _hoursPerDayController.text),
                row(
                  l10n.salDayRate,
                  _dayRateMode == RateMode.manual
                      ? money(
                          Money.tryParse(
                            _manualDayRateController.text,
                            currencyCode: _currency,
                          ),
                        )
                      : money(_derivedDayRate),
                ),
                row(
                  l10n.salHourRate,
                  _hourRateMode == RateMode.manual
                      ? money(
                          Money.tryParse(
                            _manualHourRateController.text,
                            currencyCode: _currency,
                          ),
                        )
                      : money(_derivedHourRate),
                ),
                row(
                  l10n.salExtraDayMultiplier,
                  '${_extraDayPctController.text}%',
                ),
                row(
                  l10n.salHolidayMultiplier,
                  '${_holidayPctController.text}%',
                ),
                row(
                  l10n.salOvertimeMultiplier,
                  '${_overtimePctController.text}%',
                ),
                row(
                  l10n.salHolidaySemantics,
                  _semantics == HolidayMultiplierSemantics.additionalPay
                      ? l10n.salSemanticsAdditional
                      : l10n.salSemanticsTotal,
                ),
                const Divider(),
                row(l10n.accName, _accountNameController.text.trim()),
                row(l10n.accType, accountTypeLabel(l10n, _accountType)),
                row(
                  l10n.accOpeningBalance,
                  money(
                    Money.tryParse(
                      _openingBalanceController.text,
                      currencyCode: _currency,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AuthErrorBanner(failure: _failure),
      ],
    );
  }
}
