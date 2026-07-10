import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Create (accountId == null) or edit an account.
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

  AccountType _accountType = AccountType.current;
  bool _allowNegative = false;
  AppFailure? _failure;
  bool _busy = false;
  bool _loaded = false;
  Account? _existing;

  bool get _isEdit => widget.accountId != null;

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
    final result = await ref
        .read(financeRepositoryProvider)
        .fetchAccount(widget.accountId!);
    if (!mounted) return;
    result.when(
      ok: (account) {
        _existing = account;
        _nameController.text = account.name;
        _balanceController.text =
            (account.openingBalanceMinor / Money.minorUnitsPerMajor)
                .toStringAsFixed(2);
        _notesController.text = account.notes ?? '';
        setState(() {
          _accountType = account.accountType;
          _allowNegative = account.allowNegativeBalance;
          _loaded = true;
        });
      },
      err: (failure) => setState(() {
        _failure = failure;
        _loaded = true;
      }),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _currencyCode {
    return _existing?.currencyCode ??
        ref.read(preferencesProvider).value?.currencyCode ??
        'EGP';
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
    final result = _isEdit
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.moneyEditAccount : l10n.moneyNewAccount),
      ),
      body: !_loaded
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
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: l10n.accName),
                      validator: (v) {
                        final e = Validators.requiredText(v, maxLength: 80);
                        return e == null ? null : validationMessage(context, e);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<AccountType>(
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
                    TextFormField(
                      controller: _balanceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.accOpeningBalance,
                        suffixText: _currencyCode,
                      ),
                      validator: (v) {
                        final e = Validators.nonNegativeAmount(
                          v,
                          currencyCode: _currencyCode,
                        );
                        return e == null ? null : validationMessage(context, e);
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.accAllowNegative),
                      value: _allowNegative,
                      onChanged: (v) => setState(() => _allowNegative = v),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.commonNotes} (${l10n.commonOptional})',
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
