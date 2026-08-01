import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
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
import 'package:work_tracker/features/finance/domain/income_split_preview.dart';
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
  final _rules = <_SplitRuleDraft>[];
  var _nextRuleId = 0;

  late IncomeSourceKind _kind =
      widget.existing?.kind ?? IncomeSourceKind.salary;
  late int _paymentDay = widget.existing?.paymentDay ?? 1;
  late int _promptDays = widget.existing?.promptDaysBefore ?? 7;
  late PlainDate _startDate = widget.existing?.startDate ?? PlainDate.today();
  late bool _isActive = widget.existing?.isActive ?? true;
  late bool _includeExtraWorkInPercentage =
      widget.existing?.includeExtraWorkInPercentage ?? true;
  bool _routeExtraWork = false;
  String? _extraWorkDestinationAccountId;
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
    _extraWorkDestinationAccountId =
        widget.existing?.extraWorkDestinationAccountId;
    _routeExtraWork = _extraWorkDestinationAccountId != null;
    for (final allocation
        in widget.existing?.allocations ?? const <IncomeAllocation>[]) {
      _rules.add(_SplitRuleDraft.fromAllocation(allocation, _newRuleId()));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    for (final rule in _rules) {
      rule.dispose();
    }
    super.dispose();
  }

  int _newRuleId() => _nextRuleId++;

  String _kindLabel(AppLocalizations l10n, IncomeSourceKind kind) =>
      switch (kind) {
        IncomeSourceKind.salary => l10n.incomeKindSalary,
        IncomeSourceKind.allowance => l10n.incomeKindAllowance,
        IncomeSourceKind.freelance => l10n.incomeKindFreelance,
        IncomeSourceKind.other => l10n.incomeKindOther,
      };

  String _methodLabel(AppLocalizations l10n, IncomeAllocationMethod method) =>
      switch (method) {
        IncomeAllocationMethod.percentage => l10n.incomeSplitMethodPercentage,
        IncomeAllocationMethod.fixed => l10n.incomeSplitMethodFixed,
      };

  String _basisLabel(
    AppLocalizations l10n,
    IncomeAllocationCalculationBasis basis,
  ) => switch (basis) {
    IncomeAllocationCalculationBasis.original => l10n.incomeSplitBasisOriginal,
    IncomeAllocationCalculationBasis.remaining =>
      l10n.incomeSplitBasisRemaining,
  };

  int? _basisPoints(String text) {
    final value = num.tryParse(text.trim());
    if (value == null) return null;
    return (value * 100).round();
  }

  List<AccountBalance> _eligibleSplitAccounts(List<AccountBalance> accounts) {
    final primary = accounts
        .where((account) => account.accountId == _primaryAccountId)
        .firstOrNull;
    return accounts
        .where(
          (account) =>
              account.accountId != _primaryAccountId &&
              !account.isArchived &&
              (primary == null || account.currencyCode == primary.currencyCode),
        )
        .toList();
  }

  void _addRule(List<AccountBalance> accounts) {
    final eligible = _eligibleSplitAccounts(accounts);
    setState(() {
      _rules.add(
        _SplitRuleDraft(
          id: _newRuleId(),
          destinationAccountId: eligible.firstOrNull?.accountId,
        ),
      );
    });
  }

  int? _amountMinor(String text, String currencyCode) =>
      Money.tryParse(text, currencyCode: currencyCode)?.minor;

  List<IncomeAllocation>? _buildAllocations(
    AppLocalizations l10n,
    AccountBalance primary,
    List<AccountBalance> accounts,
  ) {
    final eligibleIds = _eligibleSplitAccounts(
      accounts,
    ).map((account) => account.accountId).toSet();
    final allocations = <IncomeAllocation>[];
    var percentageIndex = 0;
    for (var index = 0; index < _rules.length; index++) {
      final rule = _rules[index];
      final destination = rule.destinationAccountId;
      if (destination == null || !eligibleIds.contains(destination)) {
        setState(
          () => _failure = ValidationFailure(
            l10n.incomeSplitInvalidAccount,
            debugDetails: 'invalid split destination',
          ),
        );
        return null;
      }
      final valueText = rule.valueController.text;
      switch (rule.method) {
        case IncomeAllocationMethod.percentage:
          percentageIndex += 1;
          final basisPoints = _basisPoints(valueText);
          if (basisPoints == null || basisPoints <= 0 || basisPoints > 10000) {
            setState(
              () => _failure = ValidationFailure(
                l10n.incomeInvalidPercentage,
                debugDetails: 'invalid percentage split',
              ),
            );
            return null;
          }
          allocations.add(
            IncomeAllocation(
              destinationAccountId: destination,
              method: IncomeAllocationMethod.percentage,
              calculationBasis: percentageIndex == 1
                  ? IncomeAllocationCalculationBasis.original
                  : rule.calculationBasis,
              percentageBasisPoints: basisPoints,
              sortOrder: index,
            ),
          );
        case IncomeAllocationMethod.fixed:
          final fixedAmount = _amountMinor(valueText, primary.currencyCode);
          if (fixedAmount == null || fixedAmount <= 0) {
            setState(
              () => _failure = ValidationFailure(
                l10n.errInvalidAmount,
                debugDetails: 'invalid fixed split amount',
              ),
            );
            return null;
          }
          allocations.add(
            IncomeAllocation(
              destinationAccountId: destination,
              method: IncomeAllocationMethod.fixed,
              fixedAmountMinor: fixedAmount,
              sortOrder: index,
            ),
          );
      }
    }
    return allocations;
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
    final primary = accounts
        .where((account) => account.accountId == _primaryAccountId)
        .first;
    final allocations = _buildAllocations(
      AppLocalizations.of(context),
      primary,
      accounts,
    );
    if (allocations == null) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: primary.currencyCode,
    )!;
    final notes = _notesController.text.trim();
    final extraDestination =
        _kind == IncomeSourceKind.salary &&
            !_includeExtraWorkInPercentage &&
            _routeExtraWork
        ? _extraWorkDestinationAccountId
        : null;
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
          includeExtraWorkInPercentage: _includeExtraWorkInPercentage,
          extraWorkDestinationAccountId: extraDestination,
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
        ?.where(
          (source) =>
              source.kind == IncomeSourceKind.salary &&
              source.id != widget.existing?.id &&
              source.isActive,
        )
        .firstOrNull;
    final salaryConflict =
        _kind == IncomeSourceKind.salary && _isActive && existingSalary != null;
    if (_primaryAccountId == null && accounts.isNotEmpty) {
      _primaryAccountId =
          (accounts.where((account) => account.isDefault).firstOrNull ??
                  accounts.first)
              .accountId;
    }
    final primary = accounts
        .where((account) => account.accountId == _primaryAccountId)
        .firstOrNull;
    final eligibleSplitAccounts = _eligibleSplitAccounts(accounts);
    if (!eligibleSplitAccounts.any(
          (account) => account.accountId == _extraWorkDestinationAccountId,
        ) &&
        _extraWorkDestinationAccountId != null) {
      _extraWorkDestinationAccountId = null;
    }
    final hasPercentageRules = _rules.any(
      (rule) => rule.method == IncomeAllocationMethod.percentage,
    );

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit ? l10n.incomeEditSource : l10n.incomeAddSource,
      ),
      body: FinanceSuitFocusedBody(
        title: _isEdit ? l10n.incomeEditSource : l10n.incomeAddSource,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSelectionField<IncomeSourceKind>(
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: l10n.incomeSourceType),
                  items: [
                    for (final kind in IncomeSourceKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(_kindLabel(l10n, kind)),
                      ),
                  ],
                  onChanged: (kind) => setState(() {
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
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                AppSelectionField<String>(
                  key: ValueKey(_primaryAccountId),
                  initialValue: _primaryAccountId,
                  decoration: InputDecoration(
                    labelText: l10n.incomeRemainderAccount,
                  ),
                  items: [
                    for (final account in accounts.where((a) => !a.isArchived))
                      DropdownMenuItem(
                        value: account.accountId,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _primaryAccountId = value),
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
                  leading: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  title: Text(l10n.incomeStartDate),
                  subtitle: Text(_startDate.toIso()),
                  onTap: _pickStartDate,
                ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.incomeSplitTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: l10n.incomeSplitAddRule,
                      onPressed: eligibleSplitAccounts.isEmpty
                          ? null
                          : () => _addRule(accounts),
                      icon: const FinanceSuitIcon(FinanceSuitIcons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(l10n.incomeSplitHelp),
                const SizedBox(height: 12),
                if (_rules.isEmpty)
                  Text(
                    l10n.incomeSplitNoRules,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                for (var index = 0; index < _rules.length; index++) ...[
                  _SplitRuleCard(
                    key: ValueKey(_rules[index].id),
                    index: index,
                    rule: _rules[index],
                    accounts: eligibleSplitAccounts,
                    currencyCode: primary?.currencyCode ?? 'EGP',
                    isFirstPercentage:
                        _rules
                            .take(index + 1)
                            .where(
                              (rule) =>
                                  rule.method ==
                                  IncomeAllocationMethod.percentage,
                            )
                            .length ==
                        1,
                    methodLabel: (method) => _methodLabel(l10n, method),
                    basisLabel: (basis) => _basisLabel(l10n, basis),
                    onChanged: () => setState(() {}),
                    onMoveUp: index == 0
                        ? null
                        : () => setState(() {
                            final rule = _rules.removeAt(index);
                            _rules.insert(index - 1, rule);
                          }),
                    onMoveDown: index == _rules.length - 1
                        ? null
                        : () => setState(() {
                            final rule = _rules.removeAt(index);
                            _rules.insert(index + 1, rule);
                          }),
                    onRemove: () => setState(() {
                      _rules.removeAt(index).dispose();
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_kind == IncomeSourceKind.salary && hasPercentageRules) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.incomeSplitIncludeExtraWork),
                    subtitle: Text(l10n.incomeSplitIncludeExtraWorkHelp),
                    value: _includeExtraWorkInPercentage,
                    onChanged: (value) => setState(() {
                      _includeExtraWorkInPercentage = value;
                      if (value) _routeExtraWork = false;
                    }),
                  ),
                  if (!_includeExtraWorkInPercentage) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.incomeSplitRouteExtraWork),
                      value: _routeExtraWork,
                      onChanged: (value) => setState(() {
                        _routeExtraWork = value ?? false;
                      }),
                    ),
                    if (_routeExtraWork)
                      AppSelectionField<String>(
                        key: ValueKey(_extraWorkDestinationAccountId),
                        initialValue: _extraWorkDestinationAccountId,
                        decoration: InputDecoration(
                          labelText: l10n.incomeSplitExtraWorkAccount,
                        ),
                        items: [
                          for (final account in eligibleSplitAccounts)
                            DropdownMenuItem(
                              value: account.accountId,
                              child: Text(account.name),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _extraWorkDestinationAccountId = value,
                        ),
                      ),
                  ],
                ],
                if (primary != null) ...[
                  const SizedBox(height: 12),
                  _SplitPreview(
                    sourceKind: _kind,
                    amountText: _amountController.text,
                    primary: primary,
                    accounts: accounts,
                    allocations: _draftPreviewAllocations(primary),
                    includeExtraWorkInPercentage: _includeExtraWorkInPercentage,
                    extraWorkDestinationAccountId: _routeExtraWork
                        ? _extraWorkDestinationAccountId
                        : null,
                  ),
                ],
                const SizedBox(height: 16),
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
      ),
    );
  }

  List<IncomeAllocation> _draftPreviewAllocations(AccountBalance primary) {
    var percentageIndex = 0;
    return [
      for (var index = 0; index < _rules.length; index++)
        if (_rules[index].destinationAccountId != null)
          IncomeAllocation(
            destinationAccountId: _rules[index].destinationAccountId!,
            method: _rules[index].method,
            calculationBasis:
                _rules[index].method == IncomeAllocationMethod.percentage &&
                    ++percentageIndex == 1
                ? IncomeAllocationCalculationBasis.original
                : _rules[index].calculationBasis,
            percentageBasisPoints:
                _basisPoints(_rules[index].valueController.text) ?? 0,
            fixedAmountMinor:
                _amountMinor(
                  _rules[index].valueController.text,
                  primary.currencyCode,
                ) ??
                0,
            sortOrder: index,
          ),
    ];
  }
}

class _SplitRuleDraft {
  _SplitRuleDraft({
    required this.id,
    this.destinationAccountId,
    this.method = IncomeAllocationMethod.percentage,
    this.calculationBasis = IncomeAllocationCalculationBasis.original,
    String valueText = '',
  }) : valueController = TextEditingController(text: valueText);

  factory _SplitRuleDraft.fromAllocation(IncomeAllocation allocation, int id) =>
      _SplitRuleDraft(
        id: id,
        destinationAccountId: allocation.destinationAccountId,
        method: allocation.method,
        calculationBasis: allocation.calculationBasis,
        valueText: allocation.method == IncomeAllocationMethod.percentage
            ? ((allocation.percentageBasisPoints ?? 0) / 100).toStringAsFixed(2)
            : ((allocation.fixedAmountMinor ?? 0) / Money.minorUnitsPerMajor)
                  .toStringAsFixed(2),
      );

  final int id;
  final TextEditingController valueController;
  String? destinationAccountId;
  IncomeAllocationMethod method;
  IncomeAllocationCalculationBasis calculationBasis;

  void dispose() => valueController.dispose();
}

class _SplitRuleCard extends StatelessWidget {
  const _SplitRuleCard({
    super.key,
    required this.index,
    required this.rule,
    required this.accounts,
    required this.currencyCode,
    required this.isFirstPercentage,
    required this.methodLabel,
    required this.basisLabel,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final int index;
  final _SplitRuleDraft rule;
  final List<AccountBalance> accounts;
  final String currencyCode;
  final bool isFirstPercentage;
  final String Function(IncomeAllocationMethod method) methodLabel;
  final String Function(IncomeAllocationCalculationBasis basis) basisLabel;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.incomeSplitRuleNumber(index + 1))),
                IconButton(
                  tooltip: l10n.incomeSplitMoveUp,
                  onPressed: onMoveUp,
                  icon: const FinanceSuitIcon(FinanceSuitIcons.chevronLeft),
                ),
                IconButton(
                  tooltip: l10n.incomeSplitMoveDown,
                  onPressed: onMoveDown,
                  icon: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
                ),
                IconButton(
                  tooltip: l10n.commonDelete,
                  onPressed: onRemove,
                  icon: const FinanceSuitIcon(FinanceSuitIcons.delete),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppSelectionField<String>(
              key: ValueKey('${rule.id}-${rule.destinationAccountId}'),
              initialValue: rule.destinationAccountId,
              decoration: InputDecoration(
                labelText: l10n.incomeSplitDestinationAccount,
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.accountId,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) {
                rule.destinationAccountId = value;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppSelectionField<IncomeAllocationMethod>(
                    key: ValueKey('${rule.id}-${rule.method}'),
                    initialValue: rule.method,
                    decoration: InputDecoration(
                      labelText: l10n.incomeSplitMethod,
                    ),
                    items: [
                      for (final method in IncomeAllocationMethod.values)
                        DropdownMenuItem(
                          value: method,
                          child: Text(methodLabel(method)),
                        ),
                    ],
                    onChanged: (method) {
                      rule.method = method ?? IncomeAllocationMethod.percentage;
                      if (rule.method == IncomeAllocationMethod.fixed) {
                        rule.calculationBasis =
                            IncomeAllocationCalculationBasis.original;
                      }
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: rule.valueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.commonAmount,
                      suffixText: rule.method == IncomeAllocationMethod.fixed
                          ? currencyCode
                          : '%',
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            if (rule.method == IncomeAllocationMethod.percentage) ...[
              const SizedBox(height: 12),
              AppSelectionField<IncomeAllocationCalculationBasis>(
                key: ValueKey('${rule.id}-${rule.calculationBasis}'),
                initialValue: isFirstPercentage
                    ? IncomeAllocationCalculationBasis.original
                    : rule.calculationBasis,
                enabled: !isFirstPercentage,
                decoration: InputDecoration(
                  labelText: l10n.incomeSplitCalculationBasis,
                ),
                items: [
                  for (final basis in IncomeAllocationCalculationBasis.values)
                    DropdownMenuItem(
                      value: basis,
                      child: Text(basisLabel(basis)),
                    ),
                ],
                onChanged: (basis) {
                  rule.calculationBasis =
                      basis ?? IncomeAllocationCalculationBasis.original;
                  onChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitPreview extends StatelessWidget {
  const _SplitPreview({
    required this.sourceKind,
    required this.amountText,
    required this.primary,
    required this.accounts,
    required this.allocations,
    required this.includeExtraWorkInPercentage,
    required this.extraWorkDestinationAccountId,
  });

  final IncomeSourceKind sourceKind;
  final String amountText;
  final AccountBalance primary;
  final List<AccountBalance> accounts;
  final List<IncomeAllocation> allocations;
  final bool includeExtraWorkInPercentage;
  final String? extraWorkDestinationAccountId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final amount = Money.tryParse(
      amountText,
      currencyCode: primary.currencyCode,
    );
    if (amount == null) return const SizedBox.shrink();
    final preview = IncomeSplitCalculator.preview(
      actualAmountMinor: amount.minor,
      kind: sourceKind,
      allocations: allocations,
      includeExtraWorkInPercentage: includeExtraWorkInPercentage,
      extraWorkDestinationAccountId: extraWorkDestinationAccountId,
    );
    final names = {
      for (final account in accounts) account.accountId: account.name,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.incomeSplitPreviewTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final row in preview.rows)
              Text(
                l10n.incomeSplitPreviewLine(
                  Money(
                    minor: row.amountMinor,
                    currencyCode: primary.currencyCode,
                  ).format(locale: locale),
                  names[row.destinationAccountId] ?? row.destinationAccountId,
                ),
              ),
            if (preview.extraWorkRoutedMinor > 0 &&
                preview.extraWorkDestinationAccountId != null)
              Text(
                l10n.incomeSplitPreviewLine(
                  Money(
                    minor: preview.extraWorkRoutedMinor,
                    currencyCode: primary.currencyCode,
                  ).format(locale: locale),
                  names[preview.extraWorkDestinationAccountId!] ??
                      preview.extraWorkDestinationAccountId!,
                ),
              ),
            Text(
              l10n.incomeSplitPreviewRemainder(
                Money(
                  minor: preview.primaryAmountMinor,
                  currencyCode: primary.currencyCode,
                ).format(locale: locale),
                primary.name,
              ),
            ),
            if (preview.hasError) ...[
              const SizedBox(height: 8),
              Text(
                l10n.incomeSplitPreviewError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
