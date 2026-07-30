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
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create or edit money owed in either direction. A held amount may stand
/// alone or carry a linked transaction through [prefill].
class HeldAmountFormScreen extends ConsumerStatefulWidget {
  const HeldAmountFormScreen({super.key, this.existing, this.prefill});

  final HeldAmount? existing;
  final HeldAmountDraft? prefill;

  @override
  ConsumerState<HeldAmountFormScreen> createState() =>
      _HeldAmountFormScreenState();
}

class _HeldAmountFormScreenState extends ConsumerState<HeldAmountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  late PlainDate _date =
      widget.existing?.heldOn ?? widget.prefill?.heldOn ?? PlainDate.today();
  late HeldAmountDirection _direction =
      widget.existing?.direction ??
      widget.prefill?.direction ??
      HeldAmountDirection.iOwe;
  late final String? _transactionId =
      widget.existing?.transactionId ?? widget.prefill?.transactionId;
  String? _accountId;

  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final prefill = widget.prefill;
    final amountMinor = existing?.amountMinor ?? prefill?.amountMinor;
    if (amountMinor != null) {
      _amountController.text = (amountMinor / Money.minorUnitsPerMajor)
          .toStringAsFixed(2);
    }
    _counterpartyController.text =
        existing?.counterparty ?? prefill?.counterparty ?? '';
    _titleController.text = existing?.title ?? prefill?.title ?? '';
    _notesController.text = existing?.notes ?? prefill?.notes ?? '';
    _accountId = existing?.accountId;
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
      widget.prefill?.currencyCode ??
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
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    final draft = HeldAmountDraft(
      direction: _direction,
      amountMinor: amount.minor,
      currencyCode: _currencyCode,
      counterparty: _counterpartyController.text.trim(),
      heldOn: _date,
      transactionId: _transactionId,
      accountId: _accountId,
      title: title.isEmpty ? null : title,
      notes: notes.isEmpty ? null : notes,
    );
    setState(() => _busy = true);
    final repo = ref.read(financeRepositoryProvider);
    final result = _isEdit
        ? await repo.updateHeldAmount(widget.existing!.id, draft)
        : await repo.createHeldAmount(draft);
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
        title: Text(l10n.heldDeleteConfirmTitle),
        content: Text(l10n.heldDeleteConfirmBody),
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
        .deleteHeldAmount(widget.existing!.id);
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
    final accountList = accounts.value ?? <AccountBalance>[];
    final needsAccount =
        _transactionId == null || widget.existing?.managesTransaction == true;
    if (needsAccount && _accountId == null && accountList.isNotEmpty) {
      _accountId =
          (accountList.where((a) => a.isDefault).firstOrNull ??
                  accountList.first)
              .accountId;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.heldEditTitle : l10n.heldNew),
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
              if (_transactionId != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const FinanceSuitIcon(FinanceSuitIcons.link),
                  title: Text(l10n.heldLinkedTransaction),
                ),
                const SizedBox(height: 8),
              ],
              if (needsAccount) ...[
                AppSelectionField<String>(
                  initialValue:
                      accountList.any((a) => a.accountId == _accountId)
                      ? _accountId
                      : null,
                  decoration: InputDecoration(labelText: l10n.txAccount),
                  items: [
                    for (final account in accountList)
                      DropdownMenuItem(
                        value: account.accountId,
                        child: Text(
                          '${account.name} (${account.balance.format()})',
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _accountId = value),
                  validator: (value) => value == null
                      ? validationMessage(context, ValidationError.required)
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              Text(
                l10n.heldDirection,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SegmentedButton<HeldAmountDirection>(
                segments: [
                  ButtonSegment(
                    value: HeldAmountDirection.iOwe,
                    label: Text(l10n.heldDirectionIOwe),
                  ),
                  ButtonSegment(
                    value: HeldAmountDirection.owedToMe,
                    label: Text(l10n.heldDirectionOwedToMe),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (selection) {
                  setState(() => _direction = selection.first);
                },
              ),
              const SizedBox(height: 16),
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
              TextFormField(
                controller: _counterpartyController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _direction == HeldAmountDirection.iOwe
                      ? l10n.heldOwedTo
                      : l10n.heldOwedBy,
                ),
                validator: (v) {
                  final e = Validators.requiredText(v, maxLength: 120);
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const FinanceSuitIcon(FinanceSuitIcons.calendarToday),
                title: Text(l10n.commonDate),
                subtitle: Text(_date.toIso()),
                trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
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
