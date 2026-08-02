import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/onboarding/data/onboarding_repository.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';
import 'package:work_tracker/features/salary/presentation/models/salary_configuration_draft.dart';
import 'package:work_tracker/features/salary/presentation/widgets/salary_configuration_fields.dart';
import 'package:work_tracker/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

enum _PrimaryIncomeChoice { salary, allowance, other, none }

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
  _PrimaryIncomeChoice _primaryIncome = _PrimaryIncomeChoice.salary;
  final _salaryDraft = SalaryConfigurationDraft.defaults();
  final _incomeNameController = TextEditingController();
  final _incomeAmountController = TextEditingController();
  int _promptDaysBefore = 7;

  int get _periodStartDay => _salaryDraft.periodStartDay;
  int get _paymentDay => _salaryDraft.paymentDay;
  set _paymentDay(int value) => _salaryDraft.paymentDay = value;
  int get _paymentMonthOffset => _salaryDraft.paymentMonthOffset;
  TextEditingController get _paidDaysController =>
      _salaryDraft.paidDaysController;
  TextEditingController get _hoursPerDayController =>
      _salaryDraft.hoursPerDayController;
  RateMode get _dayRateMode => _salaryDraft.dayRateMode;
  TextEditingController get _manualDayRateController =>
      _salaryDraft.manualDayRateController;
  RateMode get _hourRateMode => _salaryDraft.hourRateMode;
  TextEditingController get _manualHourRateController =>
      _salaryDraft.manualHourRateController;
  TextEditingController get _extraDayPctController =>
      _salaryDraft.extraDayPctController;
  TextEditingController get _holidayPctController =>
      _salaryDraft.holidayPctController;
  TextEditingController get _overtimePctController =>
      _salaryDraft.overtimePctController;
  HolidayMultiplierSemantics get _semantics => _salaryDraft.semantics;

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
      _incomeNameController,
      _incomeAmountController,
      _accountNameController,
      _openingBalanceController,
    ]) {
      c.dispose();
    }
    _salaryDraft.dispose();
    super.dispose();
  }

  String get _currency => _currencyController.text.trim().toUpperCase();

  Money? get _baseSalary => _salaryDraft.baseSalary(_currency);

  /// Live derived day-rate preview: base / standard paid days.
  Money? get _derivedDayRate {
    return _salaryDraft.derivedDayRate(_currency);
  }

  /// Live derived hourly-rate preview: day rate / standard hours.
  Money? get _derivedHourRate {
    return _salaryDraft.derivedHourRate(_currency);
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

  /// Enter key / keyboard submit: advance, or finish on the review step.
  void _submitCurrentStep() {
    if (_busy) return;
    if (_step < _stepCount - 1) {
      _next();
    } else {
      _finish();
    }
  }

  void _back() => setState(() => _step--);

  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _failure = null;
      _busy = true;
    });
    final isSalary = _primaryIncome == _PrimaryIncomeChoice.salary;
    final baseSalary = isSalary ? _baseSalary : null;
    final dayRateMode = isSalary ? _dayRateMode : RateMode.derived;
    final hourRateMode = isSalary ? _hourRateMode : RateMode.derived;
    final submission = OnboardingSubmission(
      displayName: _displayNameController.text.trim(),
      currencyCode: _currency,
      // Not user-facing; the app operates on the spec's default timezone.
      timezone: 'Africa/Cairo',
      locale: _locale,
      weekStartsOn: _weekStartsOn,
      weekendDays: _weekendDays.toList()..sort(),
      salaryEnabled: isSalary,
      baseSalaryMinor: baseSalary?.minor ?? 0,
      salaryPeriodStartDay: isSalary ? _periodStartDay : 1,
      paymentDay: _paymentDay,
      paymentMonthOffset: isSalary ? _paymentMonthOffset : 1,
      standardPaidDays: isSalary
          ? (int.tryParse(_paidDaysController.text) ?? 22)
          : 22,
      standardMinutesPerDay: isSalary
          ? (int.tryParse(_hoursPerDayController.text) ?? 8) * 60
          : 480,
      dayRateMode: dayRateMode,
      manualDayRateMinor: isSalary && dayRateMode == RateMode.manual
          ? Money.tryParse(
              _manualDayRateController.text,
              currencyCode: _currency,
            )?.minor
          : null,
      hourRateMode: hourRateMode,
      manualHourRateMinor: isSalary && hourRateMode == RateMode.manual
          ? Money.tryParse(
              _manualHourRateController.text,
              currencyCode: _currency,
            )?.minor
          : null,
      extraDayMultiplierPct: isSalary
          ? (int.tryParse(_extraDayPctController.text) ?? 100)
          : 100,
      officialHolidayMultiplierPct: isSalary
          ? (int.tryParse(_holidayPctController.text) ?? 200)
          : 200,
      overtimeMultiplierPct: isSalary
          ? (int.tryParse(_overtimePctController.text) ?? 150)
          : 150,
      holidaySemantics: isSalary
          ? _semantics
          : HolidayMultiplierSemantics.additionalPay,
      accountName: _accountNameController.text.trim(),
      accountType: _accountType,
      openingBalanceMinor: Money.tryParse(
        _openingBalanceController.text,
        currencyCode: _currency,
      )!.minor,
      allowNegativeBalance: _allowNegative,
      incomeSourceKind: switch (_primaryIncome) {
        _PrimaryIncomeChoice.salary => IncomeSourceKind.salary,
        _PrimaryIncomeChoice.allowance => IncomeSourceKind.allowance,
        _PrimaryIncomeChoice.other => IncomeSourceKind.other,
        _PrimaryIncomeChoice.none => null,
      },
      incomeSourceName: switch (_primaryIncome) {
        _PrimaryIncomeChoice.salary =>
          _incomeNameController.text.trim().isEmpty
              ? AppLocalizations.of(context).incomeKindSalary
              : _incomeNameController.text.trim(),
        _PrimaryIncomeChoice.allowance ||
        _PrimaryIncomeChoice.other => _incomeNameController.text.trim(),
        _PrimaryIncomeChoice.none => null,
      },
      expectedIncomeMinor: switch (_primaryIncome) {
        _PrimaryIncomeChoice.salary => baseSalary?.minor,
        _PrimaryIncomeChoice.allowance ||
        _PrimaryIncomeChoice.other => Money.tryParse(
          _incomeAmountController.text,
          currencyCode: _currency,
        )!.minor,
        _PrimaryIncomeChoice.none => null,
      },
      incomePaymentDay: _primaryIncome == _PrimaryIncomeChoice.none
          ? null
          : _paymentDay,
      promptDaysBefore: _promptDaysBefore,
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

    // Enter (hardware or numpad) advances the wizard like the Next button.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submitCurrentStep,
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            _submitCurrentStep,
      },
      child: Scaffold(
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
                // The step actions scroll with the content, directly after
                // it. No pinned slots, no viewport-height tricks: the buttons
                // are always laid out and always reachable by scrolling.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      switch (_step) {
                        0 => _buildProfileStep(l10n),
                        1 => _buildSalaryStep(l10n),
                        2 => _buildAccountStep(l10n),
                        _ => _buildReviewStep(l10n),
                      },
                      const SizedBox(height: 24),
                      Row(
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
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          AppTextFormField(
            onFieldSubmitted: (_) => _submitCurrentStep(),
            controller: _displayNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.authFullName),
            validator: (v) {
              final e = Validators.requiredText(v, maxLength: 120);
              return e == null ? null : validationMessage(context, e);
            },
          ),
          const SizedBox(height: 16),
          AppSelectionField<String>(
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
          AppTextFormField(
            onFieldSubmitted: (_) => _submitCurrentStep(),
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
          AppSelectionField<int>(
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
    return Form(
      key: _salaryFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSelectionField<_PrimaryIncomeChoice>(
            initialValue: _primaryIncome,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.incomePrimaryType),
            items: [
              DropdownMenuItem(
                value: _PrimaryIncomeChoice.salary,
                child: Text(l10n.incomeKindSalary),
              ),
              DropdownMenuItem(
                value: _PrimaryIncomeChoice.allowance,
                child: Text(l10n.incomeKindAllowance),
              ),
              DropdownMenuItem(
                value: _PrimaryIncomeChoice.other,
                child: Text(l10n.incomeKindOther),
              ),
              DropdownMenuItem(
                value: _PrimaryIncomeChoice.none,
                child: Text(l10n.incomeKindNone),
              ),
            ],
            onChanged: (choice) {
              if (choice == null) return;
              setState(() {
                _primaryIncome = choice;
                if (_incomeNameController.text.trim().isEmpty) {
                  _incomeNameController.text = switch (choice) {
                    _PrimaryIncomeChoice.salary => l10n.incomeKindSalary,
                    _PrimaryIncomeChoice.allowance => l10n.incomeKindAllowance,
                    _PrimaryIncomeChoice.other => '',
                    _PrimaryIncomeChoice.none => '',
                  };
                }
              });
            },
          ),
          const SizedBox(height: 16),
          if (_primaryIncome == _PrimaryIncomeChoice.none)
            Text(l10n.incomeNoPrimaryHelp),
          if (_primaryIncome == _PrimaryIncomeChoice.allowance ||
              _primaryIncome == _PrimaryIncomeChoice.other) ...[
            AppTextFormField(
              controller: _incomeNameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.incomeSourceName),
              validator: (value) {
                final error = Validators.requiredText(value, maxLength: 80);
                return error == null ? null : validationMessage(context, error);
              },
            ),
            const SizedBox(height: 16),
            AppTextFormField(
              controller: _incomeAmountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.incomeExpectedAmount,
                suffixText: _currency,
              ),
              validator: (value) {
                final error = Validators.positiveAmount(
                  value,
                  currencyCode: _currency,
                );
                return error == null ? null : validationMessage(context, error);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppSelectionField<int>(
                    initialValue: _paymentDay,
                    decoration: InputDecoration(labelText: l10n.salPaymentDay),
                    items: [
                      for (var day = 1; day <= 28; day++)
                        DropdownMenuItem(value: day, child: Text('$day')),
                    ],
                    onChanged: (day) => setState(() => _paymentDay = day ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSelectionField<int>(
                    initialValue: _promptDaysBefore,
                    decoration: InputDecoration(
                      labelText: l10n.incomePromptBefore,
                    ),
                    items: [
                      for (final days in const [0, 1, 3, 5, 7, 14])
                        DropdownMenuItem(value: days, child: Text('$days')),
                    ],
                    onChanged: (days) =>
                        setState(() => _promptDaysBefore = days ?? 7),
                  ),
                ),
              ],
            ),
          ],
          if (_primaryIncome == _PrimaryIncomeChoice.salary)
            SalaryConfigurationFields(
              draft: _salaryDraft,
              currencyCode: _currency,
              onChanged: () => setState(() {}),
              onFieldSubmitted: _submitCurrentStep,
            ),
        ],
      ),
    );
  }

  Widget _buildAccountStep(AppLocalizations l10n) {
    return Form(
      key: _accountFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextFormField(
            onFieldSubmitted: (_) => _submitCurrentStep(),
            controller: _accountNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.accName),
            validator: (v) {
              final e = Validators.requiredText(v, maxLength: 80);
              return e == null ? null : validationMessage(context, e);
            },
          ),
          const SizedBox(height: 16),
          AppSelectionField<AccountType>(
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
          AppTextFormField(
            onFieldSubmitted: (_) => _submitCurrentStep(),
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
                row(l10n.incomePrimaryType, switch (_primaryIncome) {
                  _PrimaryIncomeChoice.salary => l10n.incomeKindSalary,
                  _PrimaryIncomeChoice.allowance => l10n.incomeKindAllowance,
                  _PrimaryIncomeChoice.other => l10n.incomeKindOther,
                  _PrimaryIncomeChoice.none => l10n.incomeKindNone,
                }),
                if (_primaryIncome == _PrimaryIncomeChoice.salary) ...[
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
                ],
                if (_primaryIncome == _PrimaryIncomeChoice.allowance ||
                    _primaryIncome == _PrimaryIncomeChoice.other) ...[
                  row(l10n.incomeSourceName, _incomeNameController.text.trim()),
                  row(
                    l10n.incomeExpectedAmount,
                    money(
                      Money.tryParse(
                        _incomeAmountController.text,
                        currencyCode: _currency,
                      ),
                    ),
                  ),
                  row(l10n.salPaymentDay, '$_paymentDay'),
                ],
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
