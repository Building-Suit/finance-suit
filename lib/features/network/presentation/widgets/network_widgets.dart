import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Status pill for the exact Pending / Accepted / Rejected states, using the
/// semantic warning / success / error tones plus the label so the state never
/// relies on color alone.
class NetworkStatusChip extends StatelessWidget {
  const NetworkStatusChip({super.key, required this.status});

  final NetworkTransferStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final (label, tone) = switch (status) {
      NetworkTransferStatus.pending => (
        l10n.networkStatusPending,
        colors.warning,
      ),
      NetworkTransferStatus.accepted => (
        l10n.networkStatusAccepted,
        colors.success,
      ),
      NetworkTransferStatus.rejected => (
        l10n.networkStatusRejected,
        colors.error,
      ),
      // Withdrawn by the sender: a closed request, not a refusal, so it does
      // not carry the error tone that rejection does.
      NetworkTransferStatus.cancelled => (
        l10n.networkStatusCancelled,
        colors.info,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: tone.text),
      ),
    );
  }
}

/// Bottom sheet asking for the caller's private alias for a person. Returns
/// the trimmed alias, or null when dismissed.
Future<String?> showNetworkAliasSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? initialValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _NetworkAliasSheet(
        title: title,
        subtitle: subtitle,
        initialValue: initialValue,
      ),
    ),
  );
}

class _NetworkAliasSheet extends StatefulWidget {
  const _NetworkAliasSheet({
    required this.title,
    this.subtitle,
    this.initialValue,
  });

  final String title;
  final String? subtitle;
  final String? initialValue;

  @override
  State<_NetworkAliasSheet> createState() => _NetworkAliasSheetState();
}

class _NetworkAliasSheetState extends State<_NetworkAliasSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('network-alias-field'),
              controller: _controller,
              autofocus: true,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.networkAliasLabel,
                helperText: l10n.networkAliasHelper,
                helperMaxLines: 3,
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? l10n.errNetworkAlias
                  : null,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('network-alias-save'),
              onPressed: _submit,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// Receiver-side acceptance: pick one of the receiver's own active,
/// matching-currency asset accounts, then book the transfer through the
/// canonical acceptance RPC. Returns true when the transfer was accepted.
Future<bool> acceptNetworkTransfer(
  BuildContext context,
  WidgetRef ref,
  NetworkTransfer transfer,
) async {
  final l10n = AppLocalizations.of(context);
  final List<AccountBalance> accounts;
  try {
    accounts = await ref.read(accountBalancesProvider.future);
  } on Object catch (error) {
    if (context.mounted) {
      AppToast.error(
        context,
        failureMessage(
          context,
          error is AppFailure ? error : UnknownFailure(debugDetails: '$error'),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  final eligible = accounts.assetAccounts
      .where(
        (account) =>
            !account.isArchived &&
            account.currencyCode == transfer.currencyCode,
      )
      .toList();
  if (eligible.isEmpty) {
    AppToast.warning(
      context,
      l10n.networkNoMatchingAccounts(transfer.currencyCode),
    );
    return false;
  }

  final accountId = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      final sheetL10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                sheetL10n.networkReceiveInto,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                sheetL10n.networkReceiveIntoHelper(transfer.currencyCode),
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final account in eligible)
                    ListTile(
                      key: Key('network-receive-${account.accountId}'),
                      leading: const FinanceSuitIcon(
                        FinanceSuitIcons.accountBalanceWallet,
                      ),
                      title: Text(account.name),
                      subtitle: ProtectedMoney(
                        interactive: false,
                        child: Text(account.balance.format()),
                      ),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(account.accountId),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (accountId == null || !context.mounted) return false;

  // Send back the amount this screen was showing. If the sender amended the
  // request in the meantime the server refuses, so a changed amount can never
  // be booked without the receiver having seen it.
  final result = await ref
      .read(networkRepositoryProvider)
      .acceptTransfer(
        transferId: transfer.id,
        destinationAccountId: accountId,
        expectedAmountMinor: transfer.amountMinor,
      );
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateNetworkData(ref);
      invalidateFinanceData(ref);
      AppToast.success(context, l10n.networkTransferAcceptedToast);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

/// Receiver-side rejection: closes the shared request, books nothing.
Future<bool> rejectNetworkTransfer(
  BuildContext context,
  WidgetRef ref,
  NetworkTransfer transfer,
) async {
  final l10n = AppLocalizations.of(context);
  final result = await ref
      .read(networkRepositoryProvider)
      .rejectTransfer(transfer.id);
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateNetworkData(ref);
      AppToast.success(context, l10n.networkTransferRejectedToast);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

/// Sender-side withdrawal of a request the receiver has not answered. Books
/// nothing — it only releases the hold and closes the shared request.
Future<bool> cancelNetworkTransfer(
  BuildContext context,
  WidgetRef ref,
  NetworkTransfer transfer,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.networkCancelConfirmTitle),
      content: Text(l10n.networkCancelConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('network-cancel-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.networkCancelTransfer),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final result = await ref
      .read(networkRepositoryProvider)
      .cancelTransfer(transfer.id);
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateNetworkData(ref);
      // The hold moves too, so the Accounts tab is stale until this runs.
      invalidateFinanceData(ref);
      AppToast.success(context, l10n.networkTransferCancelledToast);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

/// Sender-side amendment of a still-pending request: amount, source account,
/// date and shared note. The server performs no funds check, so this sheet
/// says so rather than implying the amount was validated.
Future<bool> amendNetworkTransfer(
  BuildContext context,
  WidgetRef ref,
  NetworkTransfer transfer,
) async {
  final l10n = AppLocalizations.of(context);
  final List<AccountBalance> accounts;
  try {
    accounts = await ref.read(accountBalancesProvider.future);
  } on Object catch (error) {
    if (context.mounted) {
      AppToast.error(
        context,
        failureMessage(
          context,
          error is AppFailure ? error : UnknownFailure(debugDetails: '$error'),
        ),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  final eligible = accounts.assetAccounts
      .where(
        (account) =>
            !account.isArchived &&
            account.currencyCode == transfer.currencyCode,
      )
      .toList();

  final draft = await showModalBottomSheet<_AmendDraft>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _AmendTransferSheet(transfer: transfer, accounts: eligible),
  );
  if (draft == null || !context.mounted) return false;

  final result = await ref
      .read(networkRepositoryProvider)
      .amendTransfer(
        transferId: transfer.id,
        amountMinor: draft.amountMinor,
        sourceAccountId: draft.sourceAccountId,
        requestedOn: draft.requestedOn,
        sharedNote: draft.sharedNote,
        clearSharedNote: draft.clearSharedNote,
      );
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateNetworkData(ref);
      invalidateFinanceData(ref);
      AppToast.success(context, l10n.networkAmendSaved);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

@immutable
class _AmendDraft {
  const _AmendDraft({
    required this.amountMinor,
    required this.sourceAccountId,
    required this.requestedOn,
    required this.sharedNote,
    required this.clearSharedNote,
  });

  final int amountMinor;
  final String? sourceAccountId;
  final PlainDate requestedOn;
  final String? sharedNote;
  final bool clearSharedNote;
}

class _AmendTransferSheet extends StatefulWidget {
  const _AmendTransferSheet({required this.transfer, required this.accounts});

  final NetworkTransfer transfer;
  final List<AccountBalance> accounts;

  @override
  State<_AmendTransferSheet> createState() => _AmendTransferSheetState();
}

class _AmendTransferSheetState extends State<_AmendTransferSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: (widget.transfer.amountMinor / Money.minorUnitsPerMajor)
        .toStringAsFixed(2),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.transfer.sharedNote ?? '',
  );
  late String? _accountId = widget.transfer.myAccountId;
  late PlainDate _requestedOn = widget.transfer.requestedOn;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(
      _amount.text,
      currencyCode: widget.transfer.currencyCode,
    )!;
    final note = _note.text.trim();
    Navigator.of(context).pop(
      _AmendDraft(
        amountMinor: amount.minor,
        sourceAccountId: _accountId,
        requestedOn: _requestedOn,
        sharedNote: note.isEmpty ? null : note,
        clearSharedNote: note.isEmpty && widget.transfer.sharedNote != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.networkAmendTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(l10n.networkAmendHelp, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                AppTextFormField(
                  key: const Key('network-amend-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyInputFormatters(),
                  decoration: InputDecoration(
                    labelText: l10n.networkAmendAmount,
                    suffixText: widget.transfer.currencyCode,
                  ),
                  validator: (v) {
                    final e = Validators.positiveAmount(
                      v,
                      currencyCode: widget.transfer.currencyCode,
                    );
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 12),
                if (widget.accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: const Key('network-amend-source'),
                    initialValue:
                        widget.accounts.any((a) => a.accountId == _accountId)
                        ? _accountId
                        : null,
                    decoration: InputDecoration(
                      labelText: l10n.networkAmendSource,
                    ),
                    items: [
                      for (final account in widget.accounts)
                        DropdownMenuItem(
                          value: account.accountId,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  ),
                const SizedBox(height: 12),
                ListTile(
                  key: const Key('network-amend-date'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.networkAmendDate),
                  subtitle: Text(_requestedOn.toIso()),
                  trailing: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _requestedOn.toDateTime(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(
                        () => _requestedOn = PlainDate.fromDateTime(picked),
                      );
                    }
                  },
                ),
                TextField(
                  key: const Key('network-amend-note'),
                  controller: _note,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: l10n.networkAmendNote),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('network-amend-submit'),
                  onPressed: _submit,
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
