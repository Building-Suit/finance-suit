import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/utils/client_uuid.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/data/installment_responsibility_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Owner-side status line for a plan's live responsibility link.
String responsibilityStatusLabel(
  AppLocalizations l10n,
  InstallmentResponsibilitySummary summary,
) {
  return switch (summary.status) {
    ResponsibilityLinkStatus.accepted => l10n.respLinkedTo(summary.displayName),
    ResponsibilityLinkStatus.pending => l10n.respWaitingForAcceptance(
      summary.displayName,
    ),
    ResponsibilityLinkStatus.rejected => l10n.respRejectedLink(
      summary.displayName,
    ),
  };
}

/// Status pill for the responsibility link states.
class ResponsibilityStatusChip extends StatelessWidget {
  const ResponsibilityStatusChip({super.key, required this.status});

  final ResponsibilityLinkStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final (label, tone) = switch (status) {
      ResponsibilityLinkStatus.pending => (
        l10n.networkStatusPending,
        colors.warning,
      ),
      ResponsibilityLinkStatus.accepted => (
        l10n.networkStatusAccepted,
        colors.success,
      ),
      ResponsibilityLinkStatus.rejected => (
        l10n.networkStatusRejected,
        colors.error,
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

/// The person a responsibility link points at: a private custom name or an
/// accepted network contact. Shared by the purchase form and the link sheet.
sealed class ResponsibilityTarget {
  const ResponsibilityTarget();
}

class CustomResponsibilityTarget extends ResponsibilityTarget {
  const CustomResponsibilityTarget({required this.name, this.note});

  final String name;
  final String? note;
}

class NetworkResponsibilityTarget extends ResponsibilityTarget {
  const NetworkResponsibilityTarget({required this.connectionId, this.note});

  final String connectionId;
  final String? note;
}

/// Creates the link for an already existing plan and reports the outcome
/// with a toast. Returns true when the link/request was created.
Future<bool> createResponsibilityLink(
  BuildContext context,
  WidgetRef ref, {
  required String planId,
  required ResponsibilityTarget target,
}) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(installmentResponsibilityRepositoryProvider);
  final result = switch (target) {
    CustomResponsibilityTarget(:final name, :final note) =>
      await repo.linkToCustomPerson(
        planId: planId,
        customName: name,
        sharedNote: note,
      ),
    NetworkResponsibilityTarget(:final connectionId, :final note) =>
      await repo.requestResponsibility(
        planId: planId,
        connectionId: connectionId,
        sharedNote: note,
      ),
  };
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateResponsibilityData(ref);
      AppToast.success(
        context,
        target is NetworkResponsibilityTarget
            ? l10n.respLinkRequestSentToast
            : l10n.respLinkedToast,
      );
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

/// Bottom sheet for linking an existing (possibly ongoing) plan to a custom
/// person or a network contact. Returns true when a link was created.
Future<bool> showResponsibilityLinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required String planId,
}) async {
  final target = await showModalBottomSheet<ResponsibilityTarget>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: ResponsibilityTargetSheet(
        contacts:
            ref.read(networkContactsProvider).value ?? const <NetworkContact>[],
        showOngoingScopeNote: true,
      ),
    ),
  );
  if (target == null || !context.mounted) return false;
  return createResponsibilityLink(context, ref, planId: planId, target: target);
}

/// Sheet body choosing between a custom person and a network contact.
class ResponsibilityTargetSheet extends StatefulWidget {
  const ResponsibilityTargetSheet({
    super.key,
    required this.contacts,
    this.showOngoingScopeNote = false,
  });

  final List<NetworkContact> contacts;
  final bool showOngoingScopeNote;

  @override
  State<ResponsibilityTargetSheet> createState() =>
      _ResponsibilityTargetSheetState();
}

class _ResponsibilityTargetSheetState extends State<ResponsibilityTargetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  ResponsibilityLinkType _type = ResponsibilityLinkType.custom;
  String? _connectionId;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    final target = switch (_type) {
      ResponsibilityLinkType.custom => CustomResponsibilityTarget(
        name: _nameController.text.trim(),
        note: note,
      ),
      ResponsibilityLinkType.network => NetworkResponsibilityTarget(
        connectionId: _connectionId!,
        note: note,
      ),
    };
    Navigator.of(context).pop(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.respLinkAction, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.respExplainerGeneric, style: theme.textTheme.bodySmall),
            if (widget.showOngoingScopeNote) ...[
              const SizedBox(height: 4),
              Text(
                l10n.respLinkOngoingScope,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<ResponsibilityLinkType>(
              key: const Key('resp-link-type'),
              segments: [
                ButtonSegment(
                  value: ResponsibilityLinkType.custom,
                  label: Text(l10n.respCustomPerson),
                ),
                ButtonSegment(
                  value: ResponsibilityLinkType.network,
                  label: Text(l10n.respNetworkContact),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
            if (_type == ResponsibilityLinkType.custom)
              TextFormField(
                key: const Key('resp-custom-name'),
                controller: _nameController,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.respCustomNameLabel,
                  helperText: l10n.respCustomNameHelper,
                  helperMaxLines: 3,
                ),
                validator: (value) =>
                    _type == ResponsibilityLinkType.custom &&
                        (value == null || value.trim().isEmpty)
                    ? l10n.errResponsibilityName
                    : null,
              )
            else if (widget.contacts.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.respNoContacts, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('resp-manage-network'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/money/network');
                    },
                    child: Text(l10n.respManageNetwork),
                  ),
                ],
              )
            else
              AppSelectionField<String>(
                key: const Key('resp-network-contact'),
                initialValue: _connectionId,
                decoration: InputDecoration(
                  labelText: l10n.respNetworkContactLabel,
                ),
                items: [
                  for (final contact in widget.contacts)
                    DropdownMenuItem(
                      value: contact.connectionId,
                      child: Text(
                        contact.localAlias,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _connectionId = v),
                validator: (v) =>
                    _type == ResponsibilityLinkType.network && v == null
                    ? l10n.valRequired
                    : null,
              ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('resp-shared-note'),
              controller: _noteController,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: l10n.respSharedNoteLabel,
                helperText: _type == ResponsibilityLinkType.network
                    ? l10n.respSharedNoteHelper
                    : null,
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('resp-link-save'),
              onPressed:
                  _type == ResponsibilityLinkType.network &&
                      widget.contacts.isEmpty
                  ? null
                  : _submit,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owner-side confirmation and unlink call.
Future<bool> unlinkResponsibility(
  BuildContext context,
  WidgetRef ref, {
  required String linkId,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.respUnlinkConfirmTitle),
      content: Text(l10n.respUnlinkConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('resp-unlink-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.respUnlink),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final result = await ref
      .read(installmentResponsibilityRepositoryProvider)
      .removeResponsibility(linkId);
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateResponsibilityData(ref);
      AppToast.success(context, l10n.respUnlinkedToast);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

/// Amount + account + note sheet shared by both reimbursement directions.
/// Returns the submitted values, or null when dismissed.
class ReimbursementInput {
  const ReimbursementInput({
    required this.amountMinor,
    required this.accountId,
    required this.receivedOn,
    this.note,
  });

  final int amountMinor;
  final String accountId;
  final PlainDate receivedOn;
  final String? note;
}

Future<ReimbursementInput?> _showReimbursementSheet(
  BuildContext context, {
  required String title,
  required String accountLabel,
  required List<AccountBalance> accounts,
  required String currencyCode,
  required int maxAmountMinor,
  required bool askReceivedDate,
}) {
  return showModalBottomSheet<ReimbursementInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _ReimbursementSheet(
        title: title,
        accountLabel: accountLabel,
        accounts: accounts,
        currencyCode: currencyCode,
        maxAmountMinor: maxAmountMinor,
        askReceivedDate: askReceivedDate,
      ),
    ),
  );
}

class _ReimbursementSheet extends StatefulWidget {
  const _ReimbursementSheet({
    required this.title,
    required this.accountLabel,
    required this.accounts,
    required this.currencyCode,
    required this.maxAmountMinor,
    required this.askReceivedDate,
  });

  final String title;
  final String accountLabel;
  final List<AccountBalance> accounts;
  final String currencyCode;
  final int maxAmountMinor;
  final bool askReceivedDate;

  @override
  State<_ReimbursementSheet> createState() => _ReimbursementSheetState();
}

class _ReimbursementSheetState extends State<_ReimbursementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amountController = TextEditingController(
    text: formatMinorForInput(widget.maxAmountMinor),
  );
  final _noteController = TextEditingController();
  String? _accountId;
  PlainDate _receivedOn = PlainDate.today();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedOn.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: PlainDate.today().toDateTime(),
    );
    if (picked != null) {
      setState(() => _receivedOn = PlainDate.fromDateTime(picked));
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: widget.currencyCode,
    )!;
    Navigator.of(context).pop(
      ReimbursementInput(
        amountMinor: amount.minor,
        accountId: _accountId!,
        receivedOn: _receivedOn,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('resp-reimb-amount'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: moneyInputFormatters(),
              decoration: InputDecoration(
                labelText: l10n.respAmountLabel,
                suffixText: widget.currencyCode,
              ),
              validator: (v) {
                final parsed = v == null
                    ? null
                    : Money.tryParse(v, currencyCode: widget.currencyCode);
                if (parsed == null || parsed.minor <= 0) {
                  return l10n.valAmountNotPositive;
                }
                if (parsed.minor > widget.maxAmountMinor) {
                  return l10n.errReimbursementExceedsDue;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            AppSelectionField<String>(
              key: const Key('resp-reimb-account'),
              initialValue: _accountId,
              decoration: InputDecoration(labelText: widget.accountLabel),
              items: [
                for (final account in widget.accounts)
                  DropdownMenuItem(
                    value: account.accountId,
                    child: ProtectedMoney(
                      interactive: false,
                      child: Text(
                        '${account.name} (${account.balance.format()})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _accountId = v),
              validator: (v) => v == null ? l10n.valRequired : null,
            ),
            if (widget.askReceivedDate) ...[
              const SizedBox(height: 8),
              ListTile(
                key: const Key('resp-reimb-date'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.respReceivedOnLabel),
                subtitle: Text(_receivedOn.toIso()),
                onTap: _pickDate,
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('resp-reimb-note'),
              controller: _noteController,
              maxLength: 500,
              decoration: InputDecoration(labelText: l10n.respNoteLabel),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('resp-reimb-save'),
              onPressed: _submit,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owner: record a custom-person reimbursement for one due into one of
/// their own matching-currency asset accounts.
Future<bool> recordCustomReimbursement(
  BuildContext context,
  WidgetRef ref, {
  required SharedInstallmentLinkDetails details,
  required ResponsibilityDueEntry due,
}) async {
  final l10n = AppLocalizations.of(context);
  final accounts = await _eligibleAssetAccounts(
    context,
    ref,
    currencyCode: details.current.currencyCode,
  );
  if (accounts == null || !context.mounted) return false;
  if (accounts.isEmpty) {
    AppToast.warning(
      context,
      l10n.networkNoMatchingAccounts(details.current.currencyCode),
    );
    return false;
  }
  final input = await _showReimbursementSheet(
    context,
    title: l10n.respRecordReimbursement,
    accountLabel: l10n.respReceiveIntoLabel,
    accounts: accounts,
    currencyCode: details.current.currencyCode,
    maxAmountMinor: due.remainingMinor,
    askReceivedDate: true,
  );
  if (input == null || !context.mounted) return false;
  final result = await ref
      .read(installmentResponsibilityRepositoryProvider)
      .recordCustomReimbursement(
        linkId: details.linkId,
        dueId: due.dueId,
        amountMinor: input.amountMinor,
        receivedOn: input.receivedOn,
        destinationAccountId: input.accountId,
        note: input.note,
        reimbursementId: newClientUuid(),
      );
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateResponsibilityData(ref);
      invalidateFinanceData(ref);
      AppToast.success(context, l10n.respReimbursementRecordedToast);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}

/// Responsible user: send a reimbursement for one due from one of their
/// own matching-currency asset accounts, through the network transfer rail.
/// Loads the caller's active asset accounts in the given currency; null
/// when the balances themselves failed to load (already toasted).
Future<List<AccountBalance>?> _eligibleAssetAccounts(
  BuildContext context,
  WidgetRef ref, {
  required String currencyCode,
}) async {
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
    return null;
  }
  return accounts.assetAccounts
      .where((a) => !a.isArchived && a.currencyCode == currencyCode)
      .toList();
}

Future<bool> sendNetworkReimbursement(
  BuildContext context,
  WidgetRef ref, {
  required SharedInstallmentLinkDetails details,
  required ResponsibilityDueEntry due,
}) async {
  final l10n = AppLocalizations.of(context);
  final accounts = await _eligibleAssetAccounts(
    context,
    ref,
    currencyCode: details.current.currencyCode,
  );
  if (accounts == null || !context.mounted) return false;
  if (accounts.isEmpty) {
    AppToast.warning(
      context,
      l10n.networkNoMatchingAccounts(details.current.currencyCode),
    );
    return false;
  }
  final input = await _showReimbursementSheet(
    context,
    title: l10n.respSendReimbursement,
    accountLabel: l10n.respPayFromLabel,
    accounts: accounts,
    currencyCode: details.current.currencyCode,
    maxAmountMinor: due.remainingMinor,
    askReceivedDate: false,
  );
  if (input == null || !context.mounted) return false;
  final result = await ref
      .read(installmentResponsibilityRepositoryProvider)
      .createNetworkReimbursement(
        linkId: details.linkId,
        dueId: due.dueId,
        amountMinor: input.amountMinor,
        sourceAccountId: input.accountId,
        note: input.note,
        reimbursementId: newClientUuid(),
      );
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateResponsibilityData(ref);
      invalidateNetworkData(ref);
      AppToast.success(context, l10n.respReimbursementSentToast);
      return true;
    },
    err: (failure) {
      AppToast.error(context, failureMessage(context, failure));
      return false;
    },
  );
}
