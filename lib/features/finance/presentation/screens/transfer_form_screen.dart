import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Same-currency transfer between two of the user's accounts, executed by
/// the `create_transfer` database RPC (validates ownership and overdraft).
class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});

  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  PlainDate _date = PlainDate.today();
  String? _sourceId;
  String? _destinationId;
  AppFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _currencyCode =>
      ref.read(preferencesProvider).value?.currencyCode ?? 'EGP';

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
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .createTransfer(
          sourceAccountId: _sourceId!,
          destinationAccountId: _destinationId!,
          amountMinor: amount.minor,
          occurredOn: _date,
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
    final accounts = ref.watch(accountBalancesProvider);
    final items = [
      for (final account in accounts.value ?? <AccountBalance>[])
        DropdownMenuItem(
          value: account.accountId,
          child: Text('${account.name} (${account.balance.format()})'),
        ),
    ];

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.txTransfer),
      body: FinanceSuitFocusedBody(
        title: l10n.txTransfer,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSelectionField<String>(
                  initialValue: _sourceId,
                  decoration: InputDecoration(labelText: l10n.txFromAccount),
                  items: items,
                  onChanged: (v) => setState(() => _sourceId = v),
                  validator: (v) {
                    final e = Validators.differentAccounts(v, _destinationId);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                AppSelectionField<String>(
                  initialValue: _destinationId,
                  decoration: InputDecoration(labelText: l10n.txToAccount),
                  items: items,
                  onChanged: (v) => setState(() => _destinationId = v),
                  validator: (v) {
                    final e = Validators.differentAccounts(_sourceId, v);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                AppTextFormField(
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
