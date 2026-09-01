import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
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
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
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
  final _sharedNoteController = TextEditingController();

  late PlainDate _date =
      widget.existing?.heldOn ?? widget.prefill?.heldOn ?? PlainDate.today();
  late TransactionKind _kind =
      widget.existing?.transactionKind ??
      widget.prefill?.transactionKind ??
      TransactionKind.expense;
  late final String? _transactionId =
      widget.existing?.transactionId ?? widget.prefill?.transactionId;
  String? _accountId;
  String? _categoryId;
  String? _networkConnectionId;

  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;
  bool get _isOutgoing =>
      _kind == TransactionKind.expense ||
      _kind == TransactionKind.allowanceGiven;

  CategoryKind get _categoryKind => switch (_kind) {
    TransactionKind.expense => CategoryKind.expense,
    TransactionKind.allowanceGiven => CategoryKind.allowance,
    _ => CategoryKind.income,
  };

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final prefill = widget.prefill;
    final amountMinor = existing?.amountMinor ?? prefill?.amountMinor;
    if (amountMinor != null) {
      _amountController.text = formatMinorForInput(amountMinor);
    }
    _counterpartyController.text =
        existing?.counterparty ?? prefill?.counterparty ?? '';
    _titleController.text = existing?.title ?? prefill?.title ?? '';
    _notesController.text = existing?.notes ?? prefill?.notes ?? '';
    _accountId = existing?.accountId ?? prefill?.accountId;
    _categoryId = existing?.categoryId ?? prefill?.categoryId;
    _networkConnectionId =
        existing?.networkConnectionId ?? prefill?.networkConnectionId;
    _sharedNoteController.text =
        existing?.sharedNote ?? prefill?.sharedNote ?? '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _counterpartyController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    _sharedNoteController.dispose();
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
    final sharedNote = _sharedNoteController.text.trim();
    final connectionId = (_networkConnectionId?.isEmpty ?? true)
        ? null
        : _networkConnectionId;
    final draft = HeldAmountDraft(
      transactionKind: _kind,
      amountMinor: amount.minor,
      currencyCode: _currencyCode,
      counterparty: _counterpartyController.text.trim(),
      heldOn: _date,
      categoryId: _categoryId,
      transactionId: _transactionId,
      accountId: _accountId,
      title: title.isEmpty ? null : title,
      notes: notes.isEmpty ? null : notes,
      // '' is the "network mode, nothing picked" sentinel and must never
      // reach the RPC as a connection id; the field validator blocks saving in
      // that state, so this is belt and braces.
      networkConnectionId: connectionId,
      sharedNote: connectionId == null || sharedNote.isEmpty
          ? null
          : sharedNote,
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
    final categories = ref.watch(categoriesProvider(_categoryKind));
    // Held amounts settle into the user's own cash, never a facility.
    final accountList = (accounts.value ?? <AccountBalance>[]).assetAccounts;
    const needsAccount = true;
    if (_accountId == null && accountList.isNotEmpty) {
      _accountId =
          (accountList.where((a) => a.isDefault).firstOrNull ??
                  accountList.first)
              .accountId;
    }
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit ? l10n.heldEditTitle : l10n.heldNew,
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
        title: _isEdit ? l10n.heldEditTitle : l10n.heldNew,
        child: SingleChildScrollView(
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
                    title: Text(l10n.heldLinkedTransactionReference),
                    subtitle: Text(l10n.heldSettlementTransactionHelp),
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
                          child: ProtectedMoney(
                            interactive: false,
                            child: Text(
                              '${account.name} (${account.balance.format()})',
                            ),
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
                AppSelectionField<TransactionKind>(
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: l10n.heldTypeLabel),
                  items: [
                    for (final kind in const [
                      TransactionKind.expense,
                      TransactionKind.allowanceGiven,
                      TransactionKind.customIncome,
                      TransactionKind.freelanceIncome,
                    ])
                      DropdownMenuItem(
                        value: kind,
                        child: Text(transactionKindLabel(l10n, kind)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null || value == _kind) return;
                          setState(() {
                            _kind = value;
                            // Categories are kind-specific; drop the stale one.
                            _categoryId = null;
                          });
                        },
                ),
                const SizedBox(height: 16),
                CategorySelector(
                  categories: categories.value ?? const <TransactionCategory>[],
                  selectedCategoryId: _categoryId,
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 16),
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
                SegmentedButton<bool>(
                  key: const Key('held-counterparty-mode'),
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(l10n.heldCounterpartyModeText),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(l10n.heldCounterpartyModeNetwork),
                    ),
                  ],
                  selected: {_networkConnectionId != null},
                  onSelectionChanged: (selection) => setState(() {
                    // Empty string means "network mode, no contact picked yet";
                    // null means plain free text.
                    _networkConnectionId = selection.first ? '' : null;
                    _counterpartyController.clear();
                  }),
                ),
                const SizedBox(height: 8),
                if (_networkConnectionId == null)
                  AppTextFormField(
                    controller: _counterpartyController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: _isOutgoing
                          ? l10n.heldOwedTo
                          : l10n.heldOwedBy,
                    ),
                    validator: (v) {
                      final e = Validators.requiredText(v, maxLength: 120);
                      return e == null ? null : validationMessage(context, e);
                    },
                  )
                else ...[
                  // The server resolves the label from the connection itself,
                  // so this stores an id and the free-text field goes unused.
                  _NetworkContactField(
                    connectionId: _networkConnectionId!.isEmpty
                        ? null
                        : _networkConnectionId,
                    onChanged: (id) =>
                        setState(() => _networkConnectionId = id ?? ''),
                  ),
                  const SizedBox(height: 8),
                  AppTextFormField(
                    key: const Key('held-shared-note'),
                    controller: _sharedNoteController,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: l10n.heldSharedNote,
                      helperText: l10n.heldSharedNoteHelper,
                      helperMaxLines: 2,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
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

/// Picks one of the user's network contacts for a held amount. The label the
/// hold ends up carrying is resolved server-side from the connection, so this
/// only ever hands back a connection id.
class _NetworkContactField extends ConsumerWidget {
  const _NetworkContactField({
    required this.connectionId,
    required this.onChanged,
  });

  final String? connectionId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final contacts = ref.watch(networkContactsProvider);
    final items = contacts.value ?? const <NetworkContact>[];
    return AppSelectionField<String>(
      key: const Key('held-network-contact'),
      initialValue: connectionId,
      decoration: InputDecoration(labelText: l10n.heldPickNetworkContact),
      sheetTitle: l10n.heldPickNetworkContact,
      items: [
        for (final contact in items)
          DropdownMenuItem(
            value: contact.connectionId,
            child: Text(contact.localAlias),
          ),
      ],
      onChanged: onChanged,
      validator: (value) => value == null || value.isEmpty
          ? validationMessage(context, ValidationError.required)
          : null,
    );
  }
}
