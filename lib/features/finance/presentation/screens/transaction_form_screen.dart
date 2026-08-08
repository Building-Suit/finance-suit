import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/expense_account_options.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create or edit an expense, allowance, or income transaction.
/// Transfers use [TransferFormScreen]; salary payments come from the
/// salary period flow and are not editable here.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, required this.kind, this.existing});

  final TransactionKind kind;
  final FinancialTransaction? existing;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  late TransactionKind _kind = widget.existing?.kind ?? widget.kind;
  late PlainDate _date = widget.existing?.occurredOn ?? PlainDate.today();
  String? _accountId;
  String? _categoryId;
  bool _isForeignCurrency = false;
  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;
  bool get _isIncome =>
      _kind == TransactionKind.customIncome ||
      _kind == TransactionKind.freelanceIncome;

  CategoryKind get _categoryKind => switch (_kind) {
    TransactionKind.expense => CategoryKind.expense,
    TransactionKind.allowanceGiven => CategoryKind.allowance,
    _ => CategoryKind.income,
  };

  /// Held amounts support only the four bookable kinds; anything else
  /// falls back to the plain kind for its direction.
  TransactionKind _heldKindFor(TransactionKind kind) => switch (kind) {
    TransactionKind.expense ||
    TransactionKind.allowanceGiven ||
    TransactionKind.customIncome ||
    TransactionKind.freelanceIncome => kind,
    TransactionKind.salaryIncome => TransactionKind.customIncome,
    TransactionKind.transfer => TransactionKind.expense,
  };

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = formatMinorForInput(existing.amountMinor);
      _counterpartyController.text = existing.counterparty ?? '';
      _titleController.text = existing.title ?? '';
      _notesController.text = existing.notes ?? '';
      _accountId = existing.sourceAccountId ?? existing.destinationAccountId;
      _categoryId = existing.categoryId;
      _loadExistingFxMarkup(existing.id);
    }
  }

  /// Preselects the switch from whatever the ledger already says, rather
  /// than always opening on "off": a foreign-currency expense edited later
  /// should show its markup as already on. Runs after the first frame so it
  /// never blocks the form from appearing; a brief default-off flicker on a
  /// slow connection is preferable to a loading gate on every edit.
  Future<void> _loadExistingFxMarkup(String transactionId) async {
    final hasMarkup = await ref.read(
      transactionHasFxMarkupProvider(transactionId).future,
    );
    if (!mounted) return;
    if (hasMarkup) setState(() => _isForeignCurrency = true);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _counterpartyController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _currencyCode =>
      widget.existing?.currencyCode ??
      ref.read(preferencesProvider).value?.currencyCode ??
      'EGP';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = PlainDate.fromDateTime(picked));
    }
  }

  /// The canonical eligibility list for the Account field. Expenses may be
  /// funded by assets and by both kinds of liability facility; every other
  /// kind keeps its own asset-only rule.
  List<ExpenseAccountOption> _accountOptions() {
    if (_kind != TransactionKind.expense) return const [];
    return expenseSourceAccounts(
      accounts: ref.read(allAccountBalancesProvider).value ?? const [],
      facilities: ref.read(allCreditFacilitiesProvider).value ?? const [],
      currencyCode: _currencyCode,
      currentAccountId: widget.existing == null
          ? null
          : widget.existing!.sourceAccountId ??
                widget.existing!.destinationAccountId,
    );
  }

  /// The liability facility selected as the expense source, if any.
  ExpenseAccountOption? get _selectedLiability => _accountOptions()
      .where((option) => option.isLiability && option.accountId == _accountId)
      .firstOrNull;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: _currencyCode,
    )!;
    final counterparty = _counterpartyController.text.trim();
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();

    // A new expense on a credit card or BNPL facility is a liability-backed
    // charge, not a cash expense; editing an existing one goes through the
    // canonical role-aware RPC below, which handles every account role.
    final facility = _isEdit ? null : _selectedLiability;
    if (facility != null) {
      // Fail with the same coded messages the server would raise, so the
      // banner and the save error always agree on what is missing.
      if (facility.block == ExpenseAccountBlock.cardNotConfigured) {
        setState(
          () => _failure = const ValidationFailure(
            'card_not_configured: set a statement closing day first',
          ),
        );
        return;
      }
      if (_categoryId == null) {
        setState(
          () => _failure = const ValidationFailure(
            'invalid_category: expense category required',
          ),
        );
        return;
      }
      setState(() => _busy = true);
      // A credit card with a configured FX markup rate adds a second
      // expense for it atomically when flagged foreign currency; BNPL and
      // an unconfigured card silently ignore the flag.
      final chargeResult = await ref
          .read(financeRepositoryProvider)
          .chargeLiabilityAccount(
            accountId: facility.accountId,
            title: title.isEmpty ? facility.name : title,
            categoryId: _categoryId!,
            occurredOn: _date,
            amountMinor: amount.minor,
            notes: notes.isEmpty ? null : notes,
            isForeignCurrency:
                facility.accountType == AccountType.creditCard &&
                _isForeignCurrency,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      chargeResult.when(
        ok: (_) {
          invalidateFinanceData(ref);
          AppToast.success(context, AppLocalizations.of(context).setSaved);
          context.pop();
        },
        err: (failure) => setState(() => _failure = failure),
      );
      return;
    }

    final draft = TransactionDraft(
      kind: _kind,
      occurredOn: _date,
      amountMinor: amount.minor,
      currencyCode: _currencyCode,
      sourceAccountId: _isIncome ? null : _accountId,
      destinationAccountId: _isIncome ? _accountId : null,
      categoryId: _categoryId,
      counterparty:
          _kind == TransactionKind.allowanceGiven && counterparty.isNotEmpty
          ? counterparty
          : null,
      title: title.isEmpty ? null : title,
      notes: notes.isEmpty ? null : notes,
    );
    setState(() => _busy = true);
    final repo = ref.read(financeRepositoryProvider);
    final result = _isEdit
        ? await repo.updateTransaction(
            widget.existing!.id,
            draft,
            isForeignCurrency: _isForeignCurrency,
          )
        : await repo.createTransaction(draft);
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

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.txDeleteConfirmTitle),
        content: Text(l10n.txDeleteConfirmBody),
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
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .deleteTransaction(widget.existing!.id);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  /// Renders the eligible accounts as two labelled groups — cash and bank
  /// first, credit and installments after — matching the Money tab. The
  /// group headers are disabled entries, so they can never be selected.
  List<DropdownMenuItem<String>> _groupedAccountItems(
    AppLocalizations l10n,
    List<ExpenseAccountOption> options,
  ) {
    final items = <DropdownMenuItem<String>>[];
    for (final group in ExpenseAccountGroup.values) {
      final inGroup = options.where((o) => o.group == group).toList();
      if (inGroup.isEmpty) continue;
      if (options.any((o) => o.group != group)) {
        items.add(
          DropdownMenuItem(
            value: 'group:${group.name}',
            enabled: false,
            child: Text(
              group == ExpenseAccountGroup.cash
                  ? l10n.moneyAssetsSection
                  : l10n.moneyLiabilitiesSection,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        );
      }
      for (final option in inGroup) {
        items.add(
          DropdownMenuItem(
            value: option.accountId,
            child: Text(_accountOptionLabel(l10n, option)),
          ),
        );
      }
    }
    return items;
  }

  String _accountOptionLabel(
    AppLocalizations l10n,
    ExpenseAccountOption option,
  ) {
    final parts = <String>[option.name];
    if (option.isLiability) {
      parts.add(accountTypeLabel(l10n, option.accountType));
    }
    // An archived, frozen, or closed account survives in the list only as
    // the account this very transaction already uses; say so plainly.
    if (option.isCurrent && option.isLiability) {
      final facility = (ref.read(allCreditFacilitiesProvider).value ?? const [])
          .where((f) => f.accountId == option.accountId)
          .firstOrNull;
      if (facility != null && !facility.canFundPurchases) {
        parts.add(l10n.txAccountUnavailable);
      }
    } else if (option.isCurrent) {
      final account = (ref.read(allAccountBalancesProvider).value ?? const [])
          .where((a) => a.accountId == option.accountId)
          .firstOrNull;
      if (account != null && account.isArchived) {
        parts.add(l10n.txAccountUnavailable);
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider(_categoryKind));
    // Income, allowances, and every non-expense kind move the user's own
    // cash only. Expenses use the shared eligibility list, so Add Expense
    // and Edit Expense can never drift apart.
    final accounts = ref.watch(allAccountBalancesProvider);
    final facilities = ref.watch(allCreditFacilitiesProvider);
    final assetOnly = _kind != TransactionKind.expense;
    final accountList = assetOnly
        ? (accounts.value ?? <AccountBalance>[])
              .where((a) => !a.isArchived || a.accountId == _accountId)
              .assetAccounts
        : const <AccountBalance>[];
    // Cards that cannot charge yet stay listed — hiding them read as "the
    // feature does not exist", so instead the form says what is missing.
    final options = assetOnly
        ? const <ExpenseAccountOption>[]
        : expenseSourceAccounts(
            accounts: accounts.value ?? const [],
            facilities: facilities.value ?? const [],
            currencyCode: _currencyCode,
            currentAccountId: widget.existing == null
                ? null
                : widget.existing!.sourceAccountId ??
                      widget.existing!.destinationAccountId,
          );
    final selected = options
        .where((option) => option.accountId == _accountId)
        .firstOrNull;
    // The account a historical charge already sits on is never blocked; a
    // newly chosen one says what it is still missing.
    final blockReason =
        selected?.block == ExpenseAccountBlock.cardNotConfigured &&
            !selected!.isCurrent
        ? l10n.errCardNotConfigured
        : null;
    if (_accountId == null) {
      // Preselect the default account (or the first one) on new
      // transactions; an edit already carries its own account.
      if (assetOnly && accountList.isNotEmpty) {
        _accountId =
            (accountList.where((a) => a.isDefault).firstOrNull ??
                    accountList.first)
                .accountId;
      } else if (!assetOnly && options.isNotEmpty) {
        final defaultAsset = (accounts.value ?? const <AccountBalance>[])
            .where((a) => a.isDefault && !a.isLiability)
            .firstOrNull;
        _accountId =
            options
                .where((o) => o.accountId == defaultAsset?.accountId)
                .firstOrNull
                ?.accountId ??
            options.first.accountId;
      }
    }
    final groupedItems = _groupedAccountItems(l10n, options);

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit
            ? l10n.txEditTitle
            : transactionKindLabel(l10n, _kind),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const FinanceSuitIcon(FinanceSuitIcons.delete),
              tooltip: l10n.commonDelete,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: FinanceSuitFocusedBody(
        title: _isEdit ? l10n.txEditTitle : transactionKindLabel(l10n, _kind),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isIncome) ...[
                  SegmentedButton<TransactionKind>(
                    segments: [
                      ButtonSegment(
                        value: TransactionKind.customIncome,
                        label: Text(l10n.txCustomIncome),
                      ),
                      ButtonSegment(
                        value: TransactionKind.freelanceIncome,
                        label: Text(l10n.txFreelanceIncome),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (selection) =>
                        setState(() => _kind = selection.first),
                  ),
                  const SizedBox(height: 16),
                ],
                AppTextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyInputFormatters(),
                  decoration: InputDecoration(
                    labelText: l10n.commonAmount,
                    suffixText: _currencyCode,
                  ),
                  validator: (v) {
                    final e = Validators.positiveAmount(
                      v,
                      currencyCode: _currencyCode,
                    );
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  title: Text(l10n.commonDate),
                  subtitle: Text(_date.toIso()),
                  trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 8),
                AppSelectionField<String>(
                  // Recreate the field when the async preselection lands so the
                  // initial value is actually shown.
                  key: ValueKey('account-$_accountId'),
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: _isIncome ? l10n.txToAccount : l10n.txAccount,
                  ),
                  items: [
                    if (assetOnly)
                      for (final account in accountList)
                        DropdownMenuItem(
                          value: account.accountId,
                          child: Text(account.name),
                        )
                    else
                      ...groupedItems,
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) => v == null
                      ? validationMessage(context, ValidationError.required)
                      : null,
                ),
                if (selected?.accountType == AccountType.creditCard) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const Key('tx-is-foreign-currency'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.txIsForeignCurrency),
                    subtitle: Text(l10n.txIsForeignCurrencyHelp),
                    value: _isForeignCurrency,
                    onChanged: (v) => setState(() => _isForeignCurrency = v),
                  ),
                ],
                if (blockReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    blockReason,
                    key: const Key('card-charge-blocked'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => context.push(
                        '${AppRoutes.money}/accounts/${selected!.accountId}',
                      ),
                      child: Text(l10n.txCardOpenSettings),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                CategorySelector(
                  categories: categories.value ?? const <TransactionCategory>[],
                  selectedCategoryId: _categoryId,
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                if (_kind == TransactionKind.allowanceGiven) ...[
                  const SizedBox(height: 16),
                  AppTextFormField(
                    controller: _counterpartyController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: l10n.txCounterparty),
                    validator: (v) {
                      final e = Validators.requiredText(v, maxLength: 120);
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                AppTextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: '${l10n.txTitleField} (${l10n.commonOptional})',
                  ),
                  validator: (v) {
                    final e = Validators.optionalText(v, maxLength: 120);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                  ),
                  validator: (v) {
                    final e = Validators.optionalText(v);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 16),
                  // Carry the transaction's kind and category into the hold;
                  // the held-amount form lets the user change both.
                  OutlinedButton.icon(
                    onPressed: () {
                      final existing = widget.existing!;
                      context.push(
                        '${AppRoutes.money}/held/new',
                        extra: HeldAmountDraft(
                          transactionKind: _heldKindFor(existing.kind),
                          amountMinor: existing.amountMinor,
                          currencyCode: existing.currencyCode,
                          counterparty: '',
                          heldOn: existing.occurredOn,
                          categoryId: existing.categoryId,
                          transactionId: existing.id,
                          title: existing.title,
                        ),
                      );
                    },
                    icon: const FinanceSuitIcon(FinanceSuitIcons.pauseCircle),
                    label: Text(l10n.heldHoldForTransaction),
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
