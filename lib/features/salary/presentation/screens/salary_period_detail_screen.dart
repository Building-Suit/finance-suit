import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/salary/data/salary_repository.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/salary/presentation/widgets/estimate_breakdown.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// One salary period: itemized calculation, adjustments, and the
/// finalize / reopen / mark-paid lifecycle.
class SalaryPeriodDetailScreen extends ConsumerWidget {
  const SalaryPeriodDetailScreen({super.key, required this.periodId});

  final String periodId;

  void _showFailure(BuildContext context, AppFailure failure) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _finalize(
    BuildContext context,
    WidgetRef ref,
    SalaryEstimate estimate,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      context,
      title: l10n.salFinalizeConfirmTitle,
      body: l10n.salFinalizeConfirmBody,
      action: l10n.salFinalize,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(salaryRepositoryProvider)
        .finalizePeriod(periodId, estimate.toSnapshotJson());
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateSalaryData(ref),
      err: (failure) => _showFailure(context, failure),
    );
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      context,
      title: l10n.salReopenConfirmTitle,
      body: l10n.salReopenConfirmBody,
      action: l10n.salReopen,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(salaryRepositoryProvider)
        .reopenPeriod(periodId);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateSalaryData(ref),
      err: (failure) => _showFailure(context, failure),
    );
  }

  Future<void> _markPaid(
    BuildContext context,
    WidgetRef ref,
    SalaryPeriod period,
    SalaryEstimate estimate,
  ) async {
    final l10n = AppLocalizations.of(context);
    final accounts =
        ref.read(accountBalancesProvider).value ?? <AccountBalance>[];
    final amountController = TextEditingController(
      text: (estimate.totalMinor / Money.minorUnitsPerMajor).toStringAsFixed(2),
    );
    final notesController = TextEditingController();
    var receivedDate = PlainDate.today();
    String? accountId = accounts
        .where((a) => a.isDefault)
        .map((a) => a.accountId)
        .firstOrNull;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.salMarkPaid),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.salActualAmount,
                      suffixText: estimate.currencyCode,
                    ),
                    validator: (v) {
                      final e = Validators.positiveAmount(
                        v,
                        currencyCode: estimate.currencyCode,
                      );
                      return e == null
                          ? null
                          : validationMessage(dialogContext, e);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: accountId,
                    decoration: InputDecoration(
                      labelText: l10n.salDestinationAccount,
                    ),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(
                          value: account.accountId,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => accountId = v),
                    validator: (v) => v == null
                        ? validationMessage(
                            dialogContext,
                            ValidationError.required,
                          )
                        : null,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const FinanceSuitIcon(
                      FinanceSuitIcons.calendarToday,
                    ),
                    title: Text(l10n.salReceivedDate),
                    subtitle: Text(receivedDate.toIso()),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: receivedDate.toDateTime(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(
                          () => receivedDate = PlainDate.fromDateTime(picked),
                        );
                      }
                    },
                  ),
                  TextFormField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final amount = Money.tryParse(
      amountController.text,
      currencyCode: estimate.currencyCode,
    )!;
    final notes = notesController.text.trim();
    final result = await ref
        .read(salaryRepositoryProvider)
        .recordPayment(
          periodId: period.id,
          actualAmountMinor: amount.minor,
          destinationAccountId: accountId!,
          receivedDate: receivedDate,
          notes: notes.isEmpty ? null : notes,
        );
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateSalaryData(ref);
        invalidateFinanceData(ref);
      },
      err: (failure) => _showFailure(context, failure),
    );
  }

  Future<void> _editAdjustment(
    BuildContext context,
    WidgetRef ref,
    SalaryPeriod period,
    String currencyCode,
    SalaryAdjustment existing,
  ) async {
    final l10n = AppLocalizations.of(context);
    final amountController = TextEditingController(
      text: (existing.amountMinor / Money.minorUnitsPerMajor).toStringAsFixed(
        2,
      ),
    );
    final titleController = TextEditingController(text: existing.title ?? '');
    final notesController = TextEditingController(text: existing.notes ?? '');
    var type = existing.adjustmentType;
    var date = existing.effectiveDate;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.salEditAdjustment),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<AdjustmentType>(
                    segments: [
                      ButtonSegment(
                        value: AdjustmentType.bonus,
                        label: Text(l10n.salAdjBonus),
                      ),
                      ButtonSegment(
                        value: AdjustmentType.deduction,
                        label: Text(l10n.salAdjDeduction),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (selection) =>
                        setDialogState(() => type = selection.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.commonAmount,
                      suffixText: currencyCode,
                    ),
                    validator: (v) {
                      final e = Validators.positiveAmount(
                        v,
                        currencyCode: currencyCode,
                      );
                      return e == null
                          ? null
                          : validationMessage(dialogContext, e);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const FinanceSuitIcon(
                      FinanceSuitIcons.calendarToday,
                    ),
                    title: Text(l10n.salEffectiveDate),
                    subtitle: Text(date.toIso()),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: date.toDateTime(),
                        firstDate: period.periodStart.toDateTime(),
                        lastDate: period.periodEnd.toDateTime(),
                      );
                      if (picked != null) {
                        setDialogState(
                          () => date = PlainDate.fromDateTime(picked),
                        );
                      }
                    },
                  ),
                  TextFormField(
                    controller: titleController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText:
                          '${l10n.txTitleField} (${l10n.commonOptional})',
                    ),
                    validator: (value) {
                      final error = Validators.optionalText(
                        value,
                        maxLength: 120,
                      );
                      return error == null
                          ? null
                          : validationMessage(dialogContext, error);
                    },
                  ),
                  TextFormField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                    ),
                    validator: (value) {
                      final error = Validators.optionalText(value);
                      return error == null
                          ? null
                          : validationMessage(dialogContext, error);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final amount = Money.tryParse(
      amountController.text,
      currencyCode: currencyCode,
    )!;
    final title = titleController.text.trim();
    final notes = notesController.text.trim();
    final draft = SalaryAdjustmentDraft(
      effectiveDate: date,
      adjustmentType: type,
      amountMinor: amount.minor,
      title: title.isEmpty ? null : title,
      notes: notes.isEmpty ? null : notes,
    );
    final result = await ref
        .read(salaryRepositoryProvider)
        .updateAdjustment(existing.id, draft);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateSalaryData(ref),
      err: (failure) => _showFailure(context, failure),
    );
  }

  Future<void> _deleteAdjustment(
    BuildContext context,
    WidgetRef ref,
    SalaryAdjustment adjustment,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      context,
      title: l10n.salDeleteAdjTitle,
      body: l10n.salDeleteAdjBody,
      action: l10n.commonDelete,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(salaryRepositoryProvider)
        .deleteAdjustment(adjustment.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateSalaryData(ref),
      err: (failure) => _showFailure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final periodAsync = ref.watch(salaryPeriodProvider(periodId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.salPeriodsTitle)),
      body: AsyncView(
        value: periodAsync,
        onRetry: () => ref.invalidate(salaryPeriodProvider(periodId)),
        data: (period) => _PeriodBody(
          period: period,
          onFinalize: (estimate) => _finalize(context, ref, estimate),
          onReopen: () => _reopen(context, ref),
          onMarkPaid: (estimate) => _markPaid(context, ref, period, estimate),
          onEditAdjustment: (currency, adjustment) =>
              _editAdjustment(context, ref, period, currency, adjustment),
          onDeleteAdjustment: (adjustment) =>
              _deleteAdjustment(context, ref, adjustment),
        ),
      ),
    );
  }
}

class _PeriodBody extends ConsumerWidget {
  const _PeriodBody({
    required this.period,
    required this.onFinalize,
    required this.onReopen,
    required this.onMarkPaid,
    required this.onEditAdjustment,
    required this.onDeleteAdjustment,
  });

  final SalaryPeriod period;
  final void Function(SalaryEstimate estimate) onFinalize;
  final VoidCallback onReopen;
  final void Function(SalaryEstimate estimate) onMarkPaid;
  final void Function(String currencyCode, SalaryAdjustment adjustment)
  onEditAdjustment;
  final void Function(SalaryAdjustment adjustment) onDeleteAdjustment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final range = (start: period.periodStart, end: period.periodEnd);
    // Open periods calculate live; finalized/paid render the immutable
    // snapshot so history never silently changes.
    final AsyncValue<SalaryEstimate> estimateAsync = period.isOpen
        ? ref.watch(estimateForRangeProvider(range))
        : AsyncValue.data(SalaryEstimate.fromSnapshot(period.snapshot!));
    final adjustmentsAsync = ref.watch(adjustmentsForRangeProvider(range));

    return AsyncView(
      value: estimateAsync,
      onRetry: () => ref.invalidate(estimateForRangeProvider(range)),
      data: (estimate) {
        final currency = estimate.currencyCode;
        final accounts =
            ref.watch(allAccountBalancesProvider).value ?? <AccountBalance>[];
        final accountName = accounts
            .where((a) => a.accountId == period.destinationAccountId)
            .map((a) => a.name)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${period.periodStart.toIso()} → ${period.periodEnd.toIso()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                l10n.salExpectedPayment(period.expectedPaymentDate.toIso()),
              ),
              trailing: Chip(
                label: Text(periodStatusLabel(l10n, period.status)),
              ),
            ),
            EstimateBreakdownCard(estimate: estimate),
            if (period.isPaid) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _kv(
                        context,
                        l10n.salActualReceived,
                        Money(
                          minor: period.actualAmountMinor!,
                          currencyCode: currency,
                        ).format(),
                      ),
                      _kv(
                        context,
                        l10n.salDifference,
                        Money(
                          minor:
                              period.actualAmountMinor! - estimate.totalMinor,
                          currencyCode: currency,
                        ).formatSigned(),
                      ),
                      _kv(
                        context,
                        l10n.salReceivedDate,
                        period.receivedDate!.toIso(),
                      ),
                      if (accountName != null)
                        _kv(context, l10n.salDestinationAccount, accountName),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.salAdjustments,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            AsyncView(
              value: adjustmentsAsync,
              onRetry: () => ref.invalidate(adjustmentsForRangeProvider(range)),
              data: (adjustments) {
                if (adjustments.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.salNoAdjustments),
                  );
                }
                return Column(
                  children: [
                    for (final adjustment in adjustments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: FinanceSuitIcon(
                          adjustment.adjustmentType == AdjustmentType.bonus
                              ? FinanceSuitIcons.addCircle
                              : FinanceSuitIcons.removeCircle,
                        ),
                        title: Text(
                          adjustment.title ??
                              (adjustment.adjustmentType == AdjustmentType.bonus
                                  ? l10n.salAdjBonus
                                  : l10n.salAdjDeduction),
                        ),
                        subtitle: Text(adjustment.effectiveDate.toIso()),
                        trailing: Text(
                          Money(
                            minor:
                                adjustment.adjustmentType ==
                                    AdjustmentType.bonus
                                ? adjustment.amountMinor
                                : -adjustment.amountMinor,
                            currencyCode: currency,
                          ).formatSigned(),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        onTap: period.isOpen
                            ? () => onEditAdjustment(currency, adjustment)
                            : null,
                        onLongPress: period.isOpen
                            ? () => onDeleteAdjustment(adjustment)
                            : null,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (period.isOpen)
              FilledButton.icon(
                onPressed: () => onFinalize(estimate),
                icon: const FinanceSuitIcon(FinanceSuitIcons.lock),
                label: Text(l10n.salFinalize),
              ),
            if (period.isFinalized) ...[
              FilledButton.icon(
                onPressed: () => onMarkPaid(estimate),
                icon: const FinanceSuitIcon(FinanceSuitIcons.payments),
                label: Text(l10n.salMarkPaid),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onReopen,
                icon: const FinanceSuitIcon(FinanceSuitIcons.lockOpen),
                label: Text(l10n.salReopen),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _kv(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
