import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class IncomeSourceFormScreen extends ConsumerStatefulWidget {
  const IncomeSourceFormScreen({super.key, this.existing});

  final IncomeSource? existing;

  @override
  ConsumerState<IncomeSourceFormScreen> createState() =>
      _IncomeSourceFormScreenState();
}

class _IncomeSourceFormScreenState
    extends ConsumerState<IncomeSourceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.expectedAmountMinor / Money.minorUnitsPerMajor)
              .toStringAsFixed(2),
  );
  late final _notesController = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  final Map<String, TextEditingController> _allocationControllers = {};

  late IncomeSourceKind _kind =
      widget.existing?.kind ?? IncomeSourceKind.salary;
  late int _paymentDay = widget.existing?.paymentDay ?? 1;
  late int _promptDays = widget.existing?.promptDaysBefore ?? 7;
  late PlainDate _startDate = widget.existing?.startDate ?? PlainDate.today();
  late bool _isActive = widget.existing?.isActive ?? true;
  String? _primaryAccountId;
  String? _categoryId;
  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _primaryAccountId = widget.existing?.primaryAccountId;
    _categoryId = widget.existing?.categoryId;
    for (final allocation
        in widget.existing?.allocations ?? const <IncomeAllocation>[]) {
      _allocationControllers[allocation.destinationAccountId] =
          TextEditingController(
            text: (allocation.percentageBasisPoints / 100).toStringAsFixed(2),
          );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    for (final controller in _allocationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _kindLabel(AppLocalizations l10n, IncomeSourceKind kind) =>
      switch (kind) {
        IncomeSourceKind.salary => l10n.incomeKindSalary,
        IncomeSourceKind.allowance => l10n.incomeKindAllowance,
        IncomeSourceKind.freelance => l10n.incomeKindFreelance,
        IncomeSourceKind.other => l10n.incomeKindOther,
      };

  int? _basisPoints(String text) {
    final value = num.tryParse(text.trim());
    if (value == null) return null;
    return (value * 100).round();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startDate = PlainDate.fromDateTime(picked));
    }
  }

  Future<void> _save(List<AccountBalance> accounts) async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final allocations = <IncomeAllocation>[];
    var totalBasisPoints = 0;
    for (final account in accounts) {
      if (account.accountId == _primaryAccountId) continue;
      final basisPoints = _basisPoints(
        _allocationControllers[account.accountId]?.text ?? '',
      );
      if (basisPoints == null || basisPoints == 0) continue;
      totalBasisPoints += basisPoints;
      allocations.add(
        IncomeAllocation(
          destinationAccountId: account.accountId,
          percentageBasisPoints: basisPoints,
        ),
      );
    }
    if (totalBasisPoints > 10000) {
      setState(
        () => _failure = const ValidationFailure(
          'invalid income allocation',
          debugDetails: 'allocation total exceeds 100%',
        ),
      );
      return;
    }
    final primary = accounts
        .where((account) => account.accountId == _primaryAccountId)
        .first;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: primary.currencyCode,
    )!;
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .saveIncomeSource(
          name: _nameController.text.trim(),
          kind: _kind,
          expectedAmountMinor: amount.minor,
          currencyCode: primary.currencyCode,
          paymentDay: _paymentDay,
          startDate: _startDate,
          promptDaysBefore: _promptDays,
          primaryAccountId: primary.accountId,
          categoryId: _kind == IncomeSourceKind.salary ? null : _categoryId,
          allocations: allocations,
          notes: notes.isEmpty ? null : notes,
          sourceId: widget.existing?.id,
          isActive: _isActive,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateIncomeAutomation(ref);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts =
        ref.watch(accountBalancesProvider).value ?? <AccountBalance>[];
    final categories =
        ref.watch(categoriesProvider(CategoryKind.income)).value ??
        <TransactionCategory>[];
    final existingSalary = ref
        .watch(incomeSourcesProvider)
        .value
        ?.where((source) => source.kind == IncomeSourceKind.salary)
        .firstOrNull;
    final salaryConflict =
        !_isEdit && _kind == IncomeSourceKind.salary && existingSalary != null;
    if (_primaryAccountId == null && accounts.isNotEmpty) {
      _primaryAccountId =
          (accounts.where((account) => account.isDefault).firstOrNull ??
                  accounts.first)
              .accountId;
    }
    for (final account in accounts) {
      _allocationControllers.putIfAbsent(
        account.accountId,
        TextEditingController.new,
      );
    }
    final primary = accounts
        .where((account) => account.accountId == _primaryAccountId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.incomeEditSource : l10n.incomeAddSource),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSelectionField<IncomeSourceKind>(
                initialValue: _kind,
                enabled: !_isEdit,
                decoration: InputDecoration(
                  labelText: l10n.incomeSourceType,
                  helperText: _isEdit ? l10n.incomeTypeLockedOnEdit : null,
                ),
                items: [
                  for (final kind in IncomeSourceKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(_kindLabel(l10n, kind)),
                    ),
                ],
                onChanged: _isEdit
                    ? null
                    : (kind) => setState(() {
                        _kind = kind ?? IncomeSourceKind.other;
                        if (_kind == IncomeSourceKind.salary) {
                          _categoryId = null;
                        }
                      }),
              ),
              if (salaryConflict) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const FinanceSuitIcon(FinanceSuitIcons.info),
                    title: Text(l10n.incomeSalaryAlreadyExists),
                    trailing: TextButton(
                      onPressed: () => context.pushReplacement(
                        '/settings/income-sources/edit',
                        extra: existingSalary,
                      ),
                      child: Text(l10n.commonEdit),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.incomeAutomationEnabled),
                subtitle: Text(l10n.incomeAutomationEnabledHelp),
                value: _isActive,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.incomeSourceName),
                validator: (value) {
                  final error = Validators.requiredText(value, maxLength: 80);
                  return error == null
                      ? null
                      : validationMessage(context, error);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.incomeExpectedAmount,
                  suffixText: primary?.currencyCode,
                ),
                validator: (value) {
                  final error = Validators.positiveAmount(
                    value,
                    currencyCode: primary?.currencyCode ?? 'EGP',
                  );
                  return error == null
                      ? null
                      : validationMessage(context, error);
                },
              ),
              const SizedBox(height: 16),
              AppSelectionField<String>(
                key: ValueKey(_primaryAccountId),
                initialValue: _primaryAccountId,
                decoration: InputDecoration(
                  labelText: l10n.incomeRemainderAccount,
                ),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.accountId,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) => setState(() => _primaryAccountId = value),
                validator: (value) => value == null
                    ? validationMessage(context, ValidationError.required)
                    : null,
              ),
              if (_kind != IncomeSourceKind.salary) ...[
                const SizedBox(height: 16),
                CategorySelector(
                  categories: categories,
                  selectedCategoryId: _categoryId,
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppSelectionField<int>(
                      initialValue: _paymentDay,
                      decoration: InputDecoration(
                        labelText: l10n.salPaymentDay,
                      ),
                      items: [
                        for (var day = 1; day <= 28; day++)
                          DropdownMenuItem(value: day, child: Text('$day')),
                      ],
                      onChanged: (day) =>
                          setState(() => _paymentDay = day ?? 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppSelectionField<int>(
                      initialValue: _promptDays,
                      decoration: InputDecoration(
                        labelText: l10n.incomePromptBefore,
                      ),
                      items: [
                        for (final days in const [0, 1, 3, 5, 7, 14, 21, 31])
                          DropdownMenuItem(value: days, child: Text('$days')),
                      ],
                      onChanged: (days) =>
                          setState(() => _promptDays = days ?? 7),
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const FinanceSuitIcon(FinanceSuitIcons.calendarToday),
                title: Text(l10n.incomeStartDate),
                subtitle: Text(_startDate.toIso()),
                onTap: _pickStartDate,
              ),
              const Divider(height: 32),
              Text(
                l10n.incomeSplitTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(l10n.incomeSplitHelp),
              const SizedBox(height: 12),
              for (final account in accounts)
                if (account.accountId != _primaryAccountId)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _allocationControllers[account.accountId],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: account.name,
                        suffixText: '%',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final basisPoints = _basisPoints(value);
                        if (basisPoints == null ||
                            basisPoints < 0 ||
                            basisPoints > 10000) {
                          return l10n.incomeInvalidPercentage;
                        }
                        return null;
                      },
                    ),
                  ),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              AuthErrorBanner(failure: _failure),
              AuthSubmitButton(
                label: l10n.commonSave,
                busy: _busy,
                onPressed: accounts.isEmpty || salaryConflict
                    ? null
                    : () => _save(accounts),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
