import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
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

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _amountController.text = (existing.amountMinor / Money.minorUnitsPerMajor)
          .toStringAsFixed(2);
      _counterpartyController.text = existing.counterparty ?? '';
      _titleController.text = existing.title ?? '';
      _notesController.text = existing.notes ?? '';
      _accountId = existing.sourceAccountId ?? existing.destinationAccountId;
      _categoryId = existing.categoryId;
    }
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

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: _currencyCode,
    )!;
    final counterparty = _counterpartyController.text.trim();
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
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
        ? await repo.updateTransaction(widget.existing!.id, draft)
        : await repo.createTransaction(draft);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).setSaved)),
        );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountBalancesProvider);
    final categories = ref.watch(categoriesProvider(_categoryKind));
    final accountList = accounts.value ?? <AccountBalance>[];
    if (_accountId == null && accountList.isNotEmpty) {
      // Preselect the default account (or the first one) on new transactions.
      _accountId =
          (accountList.where((a) => a.isDefault).firstOrNull ??
                  accountList.first)
              .accountId;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? l10n.txEditTitle : transactionKindLabel(l10n, _kind),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const FinanceSuitIcon(FinanceSuitIcons.delete),
              tooltip: l10n.commonDelete,
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
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
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                leading: const FinanceSuitIcon(FinanceSuitIcons.calendarToday),
                title: Text(l10n.commonDate),
                subtitle: Text(_date.toIso()),
                trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // Recreate the field when the async preselection lands so the
                // initial value is actually shown.
                key: ValueKey('account-$_accountId'),
                initialValue: _accountId,
                decoration: InputDecoration(
                  labelText: _isIncome ? l10n.txToAccount : l10n.txAccount,
                ),
                items: [
                  for (final account in accountList)
                    DropdownMenuItem(
                      value: account.accountId,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (v) => setState(() => _accountId = v),
                validator: (v) => v == null
                    ? validationMessage(context, ValidationError.required)
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: InputDecoration(labelText: l10n.txCategory),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.txNoCategory),
                  ),
                  for (final category
                      in categories.value ?? <TransactionCategory>[])
                    DropdownMenuItem<String?>(
                      value: category.id,
                      child: Text(
                        category.displayName(
                          categories.value ?? <TransactionCategory>[],
                        ),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              if (_kind == TransactionKind.allowanceGiven) ...[
                const SizedBox(height: 16),
                TextFormField(
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
              TextFormField(
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
              TextFormField(
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
                // Preserve the original I-owe behavior for linked prefills;
                // the held-amount form lets the user change the direction.
                OutlinedButton.icon(
                  onPressed: () {
                    final existing = widget.existing!;
                    context.push(
                      '${AppRoutes.money}/held/new',
                      extra: HeldAmountDraft(
                        direction: HeldAmountDirection.iOwe,
                        amountMinor: existing.amountMinor,
                        currencyCode: existing.currencyCode,
                        counterparty: '',
                        heldOn: existing.occurredOn,
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
    );
  }
}
