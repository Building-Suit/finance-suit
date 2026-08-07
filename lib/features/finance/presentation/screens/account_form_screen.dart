import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
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
/// BNPL type swaps in the facility fields (credit limit, due day,
/// reminders, lifecycle) and saves through the atomic facility RPC. New
/// facilities always start at zero debt — there is no opening-owed input.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

/// Choices for how many days before a due date the reminder fires.
const _reminderLeadChoices = [0, 1, 2, 3, 5, 7, 10, 14];

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _dueDayController = TextEditingController(text: '1');
  final _statementDayController = TextEditingController();
  final _lastFourController = TextEditingController();
  final _minFixedController = TextEditingController();
  final _minPercentController = TextEditingController();

  AccountType _accountType = AccountType.current;
  bool _allowNegative = false;
  bool _hideFromHome = false;
  int _reminderLeadDays = 3;
  FacilityStatus _facilityStatus = FacilityStatus.active;
  MinPaymentMethod _minPaymentMethod = MinPaymentMethod.full;
  String? _colorHex;
  AppFailure? _failure;
  bool _busy = false;
  bool _loaded = false;
  Account? _existing;
  CreditFacilitySummary? _existingFacility;

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
    _existingFacility = facility;
    _nameController.text = account.name;
    _balanceController.text = formatMinorForInput(account.openingBalanceMinor);
    _notesController.text = account.notes ?? '';
    if (facility != null) {
      _creditLimitController.text = formatMinorForInput(
        facility.creditLimitMinor,
      );
      _dueDayController.text = '${facility.defaultDueDay}';
      _statementDayController.text = facility.statementDay == null
          ? ''
          : '${facility.statementDay}';
      _lastFourController.text = facility.lastFourDigits ?? '';
      _reminderLeadDays = facility.reminderLeadDays;
      _facilityStatus = facility.facilityStatus;
      _minPaymentMethod = facility.minPaymentMethod;
      _colorHex = facility.colorHex;
      if (facility.minPaymentFixedMinor != null) {
        _minFixedController.text = formatMinorForInput(
          facility.minPaymentFixedMinor!,
        );
      }
      if (facility.minPaymentBasisPoints != null) {
        _minPercentController.text = (facility.minPaymentBasisPoints! / 100)
            .toStringAsFixed(2);
      }
    }
    setState(() {
      _accountType = account.accountType;
      _allowNegative = account.allowNegativeBalance;
      _hideFromHome = account.hideFromHome;
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
    _minFixedController.dispose();
    _minPercentController.dispose();
    super.dispose();
  }

  bool get _minPaymentUsesFixed =>
      _minPaymentMethod == MinPaymentMethod.fixed ||
      _minPaymentMethod == MinPaymentMethod.greaterOf;

  bool get _minPaymentUsesPercent =>
      _minPaymentMethod == MinPaymentMethod.percent ||
      _minPaymentMethod == MinPaymentMethod.greaterOf;

  int? get _minPaymentBasisPoints {
    final value = double.tryParse(_minPercentController.text.trim());
    if (value == null) return null;
    final basisPoints = (value * 100).round();
    return basisPoints < 1 || basisPoints > 10000 ? null : basisPoints;
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
      final facilityResult = await repo.saveCreditFacility(
        CreditFacilityDraft(
          name: _nameController.text.trim(),
          accountType: _accountType,
          currencyCode: _currencyCode,
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
          reminderLeadDays: _reminderLeadDays,
          notes: notes.isEmpty ? null : notes,
          accountId: widget.accountId,
          facilityStatus: _facilityStatus,
          minPaymentMethod: _accountType == AccountType.creditCard
              ? _minPaymentMethod
              : MinPaymentMethod.full,
          minPaymentFixedMinor:
              _accountType == AccountType.creditCard && _minPaymentUsesFixed
              ? Money.tryParse(
                  _minFixedController.text,
                  currencyCode: _currencyCode,
                )?.minor
              : null,
          minPaymentBasisPoints:
              _accountType == AccountType.creditCard && _minPaymentUsesPercent
              ? _minPaymentBasisPoints
              : null,
          colorHex: _colorHex,
        ),
      );
      // Home visibility rides along after the facility RPC, which owns
      // every other facility field.
      final accountId = facilityResult.valueOrNull;
      result = accountId == null
          ? facilityResult
          : await repo.setHideFromHome(accountId, hidden: _hideFromHome);
    } else {
      final opening = Money.tryParse(
        _balanceController.text,
        currencyCode: _currencyCode,
      )!;
      result = _isEdit
          ? await repo.updateAccount(
              id: widget.accountId!,
              name: _nameController.text.trim(),
              accountType: _accountType,
              openingBalanceMinor: opening.minor,
              allowNegativeBalance: _allowNegative,
              hideFromHome: _hideFromHome,
              notes: notes.isEmpty ? null : notes,
            )
          : await repo.createAccount(
              name: _nameController.text.trim(),
              accountType: _accountType,
              currencyCode: _currencyCode,
              openingBalanceMinor: opening.minor,
              allowNegativeBalance: _allowNegative,
              hideFromHome: _hideFromHome,
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

  Future<void> _setArchived(bool archived) async {
    setState(() {
      _failure = null;
      _busy = true;
    });
    final result = await ref
        .read(financeRepositoryProvider)
        .setArchived(widget.accountId!, archived: archived);
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

  Future<void> _deleteFacility() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.facilityDeleteConfirmTitle),
        content: Text(l10n.facilityDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _failure = null;
      _busy = true;
    });
    final result = await ref
        .read(financeRepositoryProvider)
        .deleteCreditFacility(widget.accountId!);
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
                      if (!_isLiability) ...[
                        const SizedBox(height: 16),
                        AppTextFormField(
                          controller: _balanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
                          decoration: InputDecoration(
                            labelText: l10n.accOpeningBalance,
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
                      ],
                      if (_isLiability) ...[
                        const SizedBox(height: 16),
                        AppTextFormField(
                          key: const Key('facility-credit-limit'),
                          controller: _creditLimitController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
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
                        const SizedBox(height: 16),
                        _ColorPicker(
                          selected: _colorHex,
                          onChanged: (value) =>
                              setState(() => _colorHex = value),
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
                          const SizedBox(height: 16),
                          AppSelectionField<MinPaymentMethod>(
                            key: ValueKey(
                              'facility-min-method-$_minPaymentMethod',
                            ),
                            initialValue: _minPaymentMethod,
                            decoration: InputDecoration(
                              labelText: l10n.minPaymentLabel,
                              helperText: l10n.minPaymentHelp,
                              helperMaxLines: 3,
                            ),
                            items: [
                              for (final method in MinPaymentMethod.values)
                                DropdownMenuItem(
                                  value: method,
                                  child: Text(
                                    minPaymentMethodLabel(l10n, method),
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(
                              () => _minPaymentMethod =
                                  v ?? MinPaymentMethod.full,
                            ),
                          ),
                          if (_minPaymentUsesFixed) ...[
                            const SizedBox(height: 16),
                            AppTextFormField(
                              key: const Key('facility-min-fixed'),
                              controller: _minFixedController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: moneyInputFormatters(),
                              decoration: InputDecoration(
                                labelText: l10n.minPaymentFixedAmount,
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
                          ],
                          if (_minPaymentUsesPercent) ...[
                            const SizedBox(height: 16),
                            AppTextFormField(
                              key: const Key('facility-min-percent'),
                              controller: _minPercentController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: l10n.minPaymentPercentAmount,
                                suffixText: '%',
                              ),
                              validator: (v) => _minPaymentBasisPoints == null
                                  ? l10n.valMinPaymentPercent
                                  : null,
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        AppSelectionField<int>(
                          key: ValueKey(
                            'facility-reminder-days-$_reminderLeadDays',
                          ),
                          initialValue:
                              _reminderLeadChoices.contains(_reminderLeadDays)
                              ? _reminderLeadDays
                              : 3,
                          decoration: InputDecoration(
                            labelText: l10n.facilityReminderDays,
                            helperText: l10n.facilityReminderDaysHelp,
                            helperMaxLines: 3,
                          ),
                          items: [
                            for (final days in _reminderLeadChoices)
                              DropdownMenuItem(
                                value: days,
                                child: Text(
                                  days == 0
                                      ? l10n.facilityReminderOnDueDay
                                      : l10n.facilityReminderDaysBefore(days),
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _reminderLeadDays = v ?? 3),
                        ),
                        if (_isEdit && _existingFacility != null) ...[
                          const SizedBox(height: 16),
                          AppSelectionField<FacilityStatus>(
                            key: ValueKey('facility-status-$_facilityStatus'),
                            initialValue: _facilityStatus,
                            decoration: InputDecoration(
                              labelText: l10n.facilityStatusLabel,
                              helperText: l10n.facilityStatusHelp,
                              helperMaxLines: 3,
                            ),
                            items: [
                              for (final status in FacilityStatus.values)
                                DropdownMenuItem(
                                  value: status,
                                  child: Text(
                                    facilityStatusLabel(l10n, status),
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(
                              () =>
                                  _facilityStatus = v ?? FacilityStatus.active,
                            ),
                          ),
                        ],
                      ] else ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.accAllowNegative),
                          value: _allowNegative,
                          onChanged: (v) => setState(() => _allowNegative = v),
                        ),
                      ],
                      SwitchListTile(
                        key: const Key('account-hide-from-home'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.accHideFromHome),
                        subtitle: Text(l10n.accHideFromHomeHelp),
                        value: _hideFromHome,
                        onChanged: (v) => setState(() => _hideFromHome = v),
                      ),
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
                      if (_isEdit && _isLiability) ...[
                        const SizedBox(height: 24),
                        Text(
                          l10n.facilityLifecycleTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.facilityLifecycleBody,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('facility-archive'),
                          onPressed: _busy
                              ? null
                              : () => _setArchived(!(_existing!.isArchived)),
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(
                            _existing?.isArchived == true
                                ? l10n.facilityUnarchiveAction
                                : l10n.facilityArchiveAction,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('facility-delete'),
                          onPressed: _busy ? null : _deleteFacility,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.facilityDeleteAction),
                        ),
                      ],
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

/// Picks the colour of a physical card. A fixed swatch set rather than a
/// free colour wheel: each option is dark enough for white text, so the card
/// tiles stay readable whatever the user chooses.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.accColorLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Swatch(
              key: const Key('facility-color-default'),
              color: theme.colorScheme.surfaceContainerHighest,
              semanticLabel: l10n.accColorDefault,
              selected: selected == null,
              checkColor: theme.colorScheme.onSurface,
              onTap: () => onChanged(null),
            ),
            for (final (index, color) in FacilitySwatches.values.indexed)
              _Swatch(
                key: Key('facility-color-${FacilitySwatches.hexOf(color)}'),
                color: color,
                semanticLabel: l10n.accColorSwatch(index + 1),
                selected:
                    selected?.toUpperCase() == FacilitySwatches.hexOf(color),
                checkColor: FacilitySwatches.foregroundOn(color),
                onTap: () => onChanged(FacilitySwatches.hexOf(color)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.semanticLabel,
    required this.selected,
    required this.checkColor,
    required this.onTap,
  });

  final Color color;
  final String semanticLabel;
  final bool selected;
  final Color checkColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: checkColor)
              : null,
        ),
      ),
    );
  }
}
