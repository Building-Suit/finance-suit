import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create (accountId == null) or edit an account.
///
/// Asset accounts keep the original fields. Selecting a Credit Card or
/// BNPL type swaps in the facility fields (credit limit, opening amount
/// owed, due day, reminders) and saves through the atomic facility RPC.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _dueDayController = TextEditingController(text: '1');
  final _statementDayController = TextEditingController();
  final _lastFourController = TextEditingController();
  final _reminderDaysController = TextEditingController(text: '3');

  AccountType _accountType = AccountType.current;
  bool _allowNegative = false;
  AppFailure? _failure;
  bool _busy = false;
  bool _loaded = false;
  Account? _existing;

  bool get _isEdit => widget.accountId != null;
  bool get _isLiability => _accountType.isLiability;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadExisting();
    } else {
      _loaded = true;
    }
  }

  Future<void> _loadExisting() async {
    final repo = ref.read(financeRepositoryProvider);
    final result = await repo.fetchAccount(widget.accountId!);
    if (!mounted) return;
    final account = result.valueOrNull;
    if (account == null) {
      setState(() {
        _failure = result.failureOrNull;
        _loaded = true;
      });
      return;
    }
    CreditFacilitySummary? facility;
    if (account.accountType.isLiability) {
      final facilities = await repo.fetchCreditFacilities(
        includeArchived: true,
      );
      if (!mounted) return;
      facility = facilities.valueOrNull
          ?.where((f) => f.accountId == account.id)
          .firstOrNull;
    }
    _existing = account;
    _nameController.text = account.name;
    _balanceController.text =
        (account.openingBalanceMinor / Money.minorUnitsPerMajor)
            .toStringAsFixed(2);
    _notesController.text = account.notes ?? '';
    if (facility != null) {
      _creditLimitController.text =
          (facility.creditLimitMinor / Money.minorUnitsPerMajor)
              .toStringAsFixed(2);
      _dueDayController.text = '${facility.defaultDueDay}';
      _statementDayController.text = facility.statementDay == null
          ? ''
          : '${facility.statementDay}';
      _lastFourController.text = facility.lastFourDigits ?? '';
      _reminderDaysController.text = '${facility.reminderLeadDays}';
    }
    setState(() {
      _accountType = account.accountType;
      _allowNegative = account.allowNegativeBalance;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    _creditLimitController.dispose();
    _dueDayController.dispose();
    _statementDayController.dispose();
    _lastFourController.dispose();
    _reminderDaysController.dispose();
    super.dispose();
  }

  String get _currencyCode {
    return _existing?.currencyCode ??
        ref.read(preferencesProvider).value?.currencyCode ??
        'EGP';
  }

  String? _optionalDayError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final e = Validators.dayOfMonth(int.tryParse(text));
    return e == null ? null : validationMessage(context, e);
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final opening = Money.tryParse(
      _balanceController.text,
      currencyCode: _currencyCode,
    )!;
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final repo = ref.read(financeRepositoryProvider);
    final Result<void> result;
    if (_isLiability) {
      final limit = Money.tryParse(
        _creditLimitController.text,
        currencyCode: _currencyCode,
      )!;
      final statementDay = _statementDayController.text.trim();
      final lastFour = _lastFourController.text.trim();
      result = await repo.saveCreditFacility(
        CreditFacilityDraft(
          name: _nameController.text.trim(),
          accountType: _accountType,
          currencyCode: _currencyCode,
          openingOwedMinor: opening.minor,
          creditLimitMinor: limit.minor,
          defaultDueDay: int.parse(_dueDayController.text.trim()),
          statementDay:
              _accountType == AccountType.creditCard && statementDay.isNotEmpty
              ? int.parse(statementDay)
              : null,
          lastFourDigits:
              _accountType == AccountType.creditCard && lastFour.isNotEmpty
              ? lastFour
              : null,
          reminderLeadDays: int.parse(_reminderDaysController.text.trim()),
          notes: notes.isEmpty ? null : notes,
          accountId: widget.accountId,
        ),
      );
    } else {
      result = _isEdit
          ? await repo.updateAccount(
              id: widget.accountId!,
              name: _nameController.text.trim(),
              accountType: _accountType,
              openingBalanceMinor: opening.minor,
              allowNegativeBalance: _allowNegative,
              notes: notes.isEmpty ? null : notes,
            )
          : await repo.createAccount(
              name: _nameController.text.trim(),
              accountType: _accountType,
              currencyCode: _currencyCode,
              openingBalanceMinor: opening.minor,
              allowNegativeBalance: _allowNegative,
              notes: notes.isEmpty ? null : notes,
            );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit ? l10n.moneyEditAccount : l10n.moneyNewAccount,
      ),
      body: FinanceSuitFocusedBody(
        title: _isEdit ? l10n.moneyEditAccount : l10n.moneyNewAccount,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _existing == null && _isEdit
            ? ErrorRetryView(
                failure: _failure ?? const NotFoundFailure(),
                onRetry: _loadExisting,
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(labelText: l10n.accName),
                        validator: (v) {
                          final e = Validators.requiredText(v, maxLength: 80);
                          return e == null
                              ? null
                              : validationMessage(context, e);
                        },
                      ),
                      const SizedBox(height: 16),
                      AppSelectionField<AccountType>(
                        key: ValueKey('account-type-$_accountType'),
                        initialValue: _accountType,
                        decoration: InputDecoration(labelText: l10n.accType),
                        items: [
                          for (final type in AccountType.values)
                            DropdownMenuItem(
                              value: type,
                              child: Text(accountTypeLabel(l10n, type)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _accountType = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      AppTextFormField(
                        controller: _balanceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _isLiability
                              ? l10n.accOpeningOwed
                              : l10n.accOpeningBalance,
                          helperText: _isLiability
                              ? l10n.accOpeningOwedHelp
                              : null,
                          helperMaxLines: 3,
                          suffixText: _currencyCode,
                        ),
                        validator: (v) {
                          final e = Validators.nonNegativeAmount(
                            v,
                            currencyCode: _currencyCode,
                          );
                          return e == null
                              ? null
                              : validationMessage(context, e);
                        },
                      ),
                      if (_isLiability) ...[
                        const SizedBox(height: 16),
                        AppTextFormField(
                          key: const Key('facility-credit-limit'),
                          controller: _creditLimitController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.facilityCreditLimit,
                            suffixText: _currencyCode,
                          ),
                          validator: (v) {
                            final e = Validators.positiveAmount(
                              v,
                              currencyCode: _currencyCode,
                            );
                            return e == null
                                ? null
                                : validationMessage(context, e);
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextFormField(
                          key: const Key('facility-due-day'),
                          controller: _dueDayController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.facilityDefaultDueDay,
                          ),
                          validator: (v) {
                            final e = Validators.dayOfMonth(
                              int.tryParse(v?.trim() ?? ''),
                            );
                            return e == null
                                ? null
                                : validationMessage(context, e);
                          },
                        ),
                        if (_accountType == AccountType.creditCard) ...[
                          const SizedBox(height: 16),
                          AppTextFormField(
                            key: const Key('facility-statement-day'),
                            controller: _statementDayController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n.facilityStatementDay} '
                                  '(${l10n.commonOptional})',
                            ),
                            validator: _optionalDayError,
                          ),
                          const SizedBox(height: 16),
                          AppTextFormField(
                            key: const Key('facility-last-four'),
                            controller: _lastFourController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n.facilityLastFour} '
                                  '(${l10n.commonOptional})',
                              counterText: '',
                            ),
                            validator: (v) {
                              final text = v?.trim() ?? '';
                              if (text.isEmpty) return null;
                              return RegExp(r'^[0-9]{4}$').hasMatch(text)
                                  ? null
                                  : l10n.valFacilityLastFour;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        AppTextFormField(
                          key: const Key('facility-reminder-days'),
                          controller: _reminderDaysController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.facilityReminderDays,
                          ),
                          validator: (v) {
                            final value = int.tryParse(v?.trim() ?? '');
                            return value == null || value < 0 || value > 31
                                ? l10n.valFacilityReminderDays
                                : null;
                          },
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.accAllowNegative),
                          value: _allowNegative,
                          onChanged: (v) => setState(() => _allowNegative = v),
                        ),
                      ],
                      const SizedBox(height: 8),
                      AppTextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText:
                              '${l10n.commonNotes} (${l10n.commonOptional})',
                        ),
                        validator: (v) {
                          final e = Validators.optionalText(v);
                          return e == null
                              ? null
                              : validationMessage(context, e);
                        },
                      ),
                      const SizedBox(height: 16),
                      AuthErrorBanner(failure: _failure),
                      AuthSubmitButton(
                        label: l10n.commonSave,
                        busy: _busy,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
