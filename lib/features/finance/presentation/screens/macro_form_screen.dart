import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/category_selector.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create or edit a macro: a named list of transaction actions that can be
/// applied in one go. Items flagged reversible are also applied when the
/// macro runs in reverse ("From `<name>`" instead of "To `<name>`").
class MacroFormScreen extends ConsumerStatefulWidget {
  const MacroFormScreen({super.key, this.existing});

  final TransactionMacro? existing;

  @override
  ConsumerState<MacroFormScreen> createState() => _MacroFormScreenState();
}

class _MacroFormScreenState extends ConsumerState<MacroFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final List<TransactionMacroItem> _items = [...?widget.existing?.items];

  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final item = await Navigator.of(context).push<TransactionMacroItem>(
      MaterialPageRoute(builder: (_) => const _MacroItemFormScreen()),
    );
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _editItem(int index) async {
    final item = await Navigator.of(context).push<TransactionMacroItem>(
      MaterialPageRoute(
        builder: (_) => _MacroItemFormScreen(initial: _items[index]),
      ),
    );
    if (item != null) setState(() => _items[index] = item);
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    if (_items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.macroNoActions)));
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .saveMacro(
          name: _nameController.text.trim(),
          items: _items,
          macroId: widget.existing?.id,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref.invalidate(macrosProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).setSaved)),
        );
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allAccounts =
        ref.watch(allAccountBalancesProvider).value ?? <AccountBalance>[];
    final accountNames = {
      for (final account in allAccounts) account.accountId: account.name,
    };
    final accountCurrencies = {
      for (final account in allAccounts)
        account.accountId: account.currencyCode,
    };

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: _isEdit ? l10n.macroEditTitle : l10n.macroNew,
      ),
      body: FinanceSuitFocusedBody(
        title: _isEdit ? l10n.macroEditTitle : l10n.macroNew,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l10n.macroName),
                  validator: (v) {
                    final e = Validators.requiredText(v, maxLength: 80);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.macroActions,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l10n.macroNoActions,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final (index, item) in _items.indexed)
                  _MacroItemTile(
                    item: item,
                    l10n: l10n,
                    accountNames: accountNames,
                    accountCurrencies: accountCurrencies,
                    onTap: () => _editItem(index),
                    onRemove: () => setState(() => _items.removeAt(index)),
                  ),
                OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const FinanceSuitIcon(FinanceSuitIcons.add),
                  label: Text(l10n.macroAddAction),
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

class _MacroItemTile extends StatelessWidget {
  const _MacroItemTile({
    required this.item,
    required this.l10n,
    required this.accountNames,
    required this.accountCurrencies,
    required this.onTap,
    required this.onRemove,
  });

  final TransactionMacroItem item;
  final AppLocalizations l10n;
  final Map<String, String> accountNames;
  final Map<String, String> accountCurrencies;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String _accountLine() {
    final source = accountNames[item.sourceAccountId];
    final destination = accountNames[item.destinationAccountId];
    if (source != null && destination != null) {
      return '$source → $destination';
    }
    return source ?? destination ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final title = item.title?.isNotEmpty == true
        ? item.title!
        : transactionKindLabel(l10n, item.kind);
    final subtitleParts = [
      _accountLine(),
      if (item.isReversible) l10n.macroReversibleBadge,
    ].where((p) => p.isNotEmpty);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: FinanceSuitIcon(
          transactionKindIcon(item.kind),
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Money(
              minor: item.amountMinor,
              // Currency follows the account the item touches.
              currencyCode:
                  accountCurrencies[item.sourceAccountId] ??
                  accountCurrencies[item.destinationAccountId] ??
                  'EGP',
            ).format(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            icon: const FinanceSuitIcon(FinanceSuitIcons.close),
            tooltip: l10n.commonDelete,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Full-screen editor for one macro action. Returns the edited item via
/// `Navigator.pop`; persistence happens when the whole macro is saved.
class _MacroItemFormScreen extends ConsumerStatefulWidget {
  const _MacroItemFormScreen({this.initial});

  final TransactionMacroItem? initial;

  @override
  ConsumerState<_MacroItemFormScreen> createState() =>
      _MacroItemFormScreenState();
}

class _MacroItemFormScreenState extends ConsumerState<_MacroItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  late TransactionKind _kind = widget.initial?.kind ?? TransactionKind.expense;
  String? _accountId;
  String? _destinationId;
  String? _categoryId;
  late bool _isReversible = widget.initial?.isReversible ?? false;

  bool get _isIncome =>
      _kind == TransactionKind.customIncome ||
      _kind == TransactionKind.freelanceIncome;
  bool get _isTransfer => _kind == TransactionKind.transfer;

  CategoryKind get _categoryKind => switch (_kind) {
    TransactionKind.expense => CategoryKind.expense,
    TransactionKind.allowanceGiven => CategoryKind.allowance,
    _ => CategoryKind.income,
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _amountController.text = (initial.amountMinor / Money.minorUnitsPerMajor)
          .toStringAsFixed(2);
      _counterpartyController.text = initial.counterparty ?? '';
      _titleController.text = initial.title ?? '';
      _notesController.text = initial.notes ?? '';
      if (initial.isTransfer) {
        _accountId = initial.sourceAccountId;
        _destinationId = initial.destinationAccountId;
      } else {
        _accountId = initial.sourceAccountId ?? initial.destinationAccountId;
      }
      _categoryId = initial.categoryId;
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

  String get _currencyCode {
    final accounts =
        ref.read(accountBalancesProvider).value ?? <AccountBalance>[];
    final selected = accounts
        .where((a) => a.accountId == _accountId)
        .firstOrNull;
    return selected?.currencyCode ??
        ref.read(preferencesProvider).value?.currencyCode ??
        'EGP';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: _currencyCode,
    )!;
    final counterparty = _counterpartyController.text.trim();
    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    Navigator.of(context).pop(
      TransactionMacroItem(
        kind: _kind,
        amountMinor: amount.minor,
        sourceAccountId: _isIncome ? null : _accountId,
        destinationAccountId: _isTransfer
            ? _destinationId
            : (_isIncome ? _accountId : null),
        categoryId: _isTransfer ? null : _categoryId,
        counterparty:
            _kind == TransactionKind.allowanceGiven && counterparty.isNotEmpty
            ? counterparty
            : null,
        title: title.isEmpty ? null : title,
        notes: notes.isEmpty ? null : notes,
        isReversible: _isReversible,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountBalancesProvider);
    final categories = ref.watch(categoriesProvider(_categoryKind));
    final accountList = accounts.value ?? <AccountBalance>[];
    if (_accountId == null && accountList.isNotEmpty) {
      _accountId =
          (accountList.where((a) => a.isDefault).firstOrNull ??
                  accountList.first)
              .accountId;
    }
    final accountItems = [
      for (final account in accountList)
        DropdownMenuItem(value: account.accountId, child: Text(account.name)),
    ];

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.macroAddAction),
      body: FinanceSuitFocusedBody(
        title: l10n.macroAddAction,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSelectionField<TransactionKind>(
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: l10n.workEntryType),
                  items: [
                    for (final kind in const [
                      TransactionKind.expense,
                      TransactionKind.allowanceGiven,
                      TransactionKind.customIncome,
                      TransactionKind.freelanceIncome,
                      TransactionKind.transfer,
                    ])
                      DropdownMenuItem(
                        value: kind,
                        child: Text(transactionKindLabel(l10n, kind)),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == null || v == _kind) return;
                    _kind = v;
                    // Category kinds differ per transaction kind.
                    _categoryId = null;
                  }),
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
                AppSelectionField<String>(
                  key: ValueKey('macro-account-$_accountId'),
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: _isTransfer
                        ? l10n.txFromAccount
                        : (_isIncome ? l10n.txToAccount : l10n.txAccount),
                  ),
                  items: accountItems,
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) {
                    if (_isTransfer) {
                      final e = Validators.differentAccounts(v, _destinationId);
                      return e == null ? null : validationMessage(context, e);
                    }
                    return v == null
                        ? validationMessage(context, ValidationError.required)
                        : null;
                  },
                ),
                if (_isTransfer) ...[
                  const SizedBox(height: 16),
                  AppSelectionField<String>(
                    initialValue: _destinationId,
                    decoration: InputDecoration(labelText: l10n.txToAccount),
                    items: accountItems,
                    onChanged: (v) => setState(() => _destinationId = v),
                    validator: (v) {
                      final e = Validators.differentAccounts(_accountId, v);
                      return e == null ? null : validationMessage(context, e);
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  CategorySelector(
                    key: ValueKey('macro-category-$_categoryKind'),
                    categories:
                        categories.value ?? const <TransactionCategory>[],
                    selectedCategoryId: _categoryId,
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                ],
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
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.macroReversible),
                  subtitle: Text(l10n.macroReversibleHint),
                  value: _isReversible,
                  onChanged: (v) => setState(() => _isReversible = v),
                ),
                const SizedBox(height: 16),
                AuthSubmitButton(
                  label: l10n.commonDone,
                  busy: false,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
