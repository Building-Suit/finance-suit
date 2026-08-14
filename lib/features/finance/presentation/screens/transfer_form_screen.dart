import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/utils/client_uuid.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/money_destination.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/destination_selection_field.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Moves money out of one of the user's own asset accounts. A local
/// destination books the atomic `create_transfer` RPC immediately; a network
/// contact instead opens a pending network transfer request that only moves
/// balances once the other person accepts it.
class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});

  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  /// Client-generated so a retried network request cannot duplicate.
  late final String _requestKey = newClientUuid();

  PlainDate _date = PlainDate.today();
  String? _sourceId;
  MoneyDestination? _destination;
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
    final destination = _destination;
    setState(() => _busy = true);
    final result = switch (destination) {
      OwnAccountDestination(:final accountId) =>
        await ref
            .read(financeRepositoryProvider)
            .createTransfer(
              sourceAccountId: _sourceId!,
              destinationAccountId: accountId,
              amountMinor: amount.minor,
              occurredOn: _date,
              notes: notes.isEmpty ? null : notes,
            ),
      NetworkContactDestination(:final connectionId) =>
        await ref
            .read(networkRepositoryProvider)
            .createTransferRequest(
              connectionId: connectionId,
              sourceAccountId: _sourceId!,
              amountMinor: amount.minor,
              requestedOn: _date,
              sharedNote: notes.isEmpty ? null : notes,
              idempotencyKey: _requestKey,
            ),
      _ => null,
    };
    if (!mounted || result == null) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        final l10n = AppLocalizations.of(context);
        invalidateFinanceData(ref);
        if (destination is NetworkContactDestination) {
          invalidateNetworkData(ref);
          AppToast.success(context, l10n.networkTransferRequestSentToast);
        } else {
          AppToast.success(context, l10n.setSaved);
        }
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountBalancesProvider);
    // Transfers move cash out of the user's own asset accounts; paying a
    // credit facility goes through the dedicated facility payment flow.
    final assetAccounts = (accounts.value ?? <AccountBalance>[]).assetAccounts;
    final items = [
      for (final account in assetAccounts)
        DropdownMenuItem(
          value: account.accountId,
          child: ProtectedMoney(
            interactive: false,
            child: Text('${account.name} (${account.balance.format()})'),
          ),
        ),
    ];
    // Connected people are destinations only — never funding sources.
    final contacts = ref.watch(networkContactsProvider).value ?? const [];

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
                    final e = switch (_destination) {
                      OwnAccountDestination(:final accountId) =>
                        Validators.differentAccounts(v, accountId),
                      _ => v == null ? ValidationError.required : null,
                    };
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                DestinationSelectionField(
                  initialValue: _destination,
                  decoration: InputDecoration(labelText: l10n.txToAccount),
                  accounts: assetAccounts,
                  contacts: contacts,
                  onChanged: (v) => setState(() => _destination = v),
                  validator: (v) {
                    final e = switch (v) {
                      OwnAccountDestination(:final accountId) =>
                        Validators.differentAccounts(_sourceId, accountId),
                      NetworkContactDestination() => null,
                      _ => ValidationError.required,
                    };
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                if (_destination is NetworkContactDestination)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: 8,
                      start: 4,
                      end: 4,
                    ),
                    child: Text(
                      l10n.networkLedgerDisclaimer,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
