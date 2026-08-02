import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/data/salary_repository.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void _showFailure(BuildContext context, AppFailure failure) {
  AppToast.error(context, failureMessage(context, failure));
}

/// Confirms a scheduled income, then creates its real transaction and splits.
Future<bool> acceptPendingIncome(
  BuildContext context,
  WidgetRef ref,
  PendingIncome pending,
) async {
  final l10n = AppLocalizations.of(context);
  SalaryEstimate? salaryEstimate;
  SalaryPeriod? salaryPeriod;
  if (pending.source.kind == IncomeSourceKind.salary) {
    // A failing salary provider must surface as a message, not an
    // unhandled exception that leaves the pending card unresponsive.
    final PeriodBounds bounds;
    try {
      final settings = await ref.read(salarySettingsProvider.future);
      bounds = SalaryPeriods.boundsForExpectedPayment(
        settings,
        pending.occurrence.scheduledOn,
      );
      salaryEstimate = await ref.read(
        estimateForRangeProvider((start: bounds.start, end: bounds.end)).future,
      );
    } on Object catch (error) {
      if (context.mounted) {
        _showFailure(
          context,
          error is AppFailure ? error : const UnknownFailure(),
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    final periodResult = await ref
        .read(salaryRepositoryProvider)
        .ensurePeriod(bounds);
    salaryPeriod = periodResult.when(
      ok: (period) => period,
      err: (failure) {
        if (context.mounted) _showFailure(context, failure);
        return null;
      },
    );
    if (salaryPeriod == null || !context.mounted) return false;
    if (salaryPeriod.isPaid) {
      _showFailure(
        context,
        const ConstraintFailure(
          'salary_period_already_paid',
          debugDetails: 'automated salary period is already paid',
        ),
      );
      return false;
    }
    if (salaryPeriod.isFinalized) {
      salaryEstimate = SalaryEstimate.fromSnapshot(salaryPeriod.snapshot!);
    }
  }

  final defaultMinor =
      salaryEstimate?.totalMinor ?? pending.occurrence.expectedAmountMinor;
  final amountController = TextEditingController(
    text: (defaultMinor / Money.minorUnitsPerMajor).toStringAsFixed(2),
  );
  final notesController = TextEditingController();
  var receivedOn = PlainDate.today();
  final formKey = GlobalKey<FormState>();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.incomeAcceptTitle(pending.source.name)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.incomeAcceptHelp),
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.salActualAmount,
                    suffixText: pending.source.currencyCode,
                  ),
                  validator: (value) {
                    final error = Validators.positiveAmount(
                      value,
                      currencyCode: pending.source.currencyCode,
                    );
                    return error == null
                        ? null
                        : validationMessage(dialogContext, error);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const FinanceSuitIcon(
                    FinanceSuitIcons.calendarToday,
                  ),
                  title: Text(l10n.salReceivedDate),
                  subtitle: Text(receivedOn.toIso()),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: receivedOn.toDateTime(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(
                        () => receivedOn = PlainDate.fromDateTime(picked),
                      );
                    }
                  },
                ),
                AppTextFormField(
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
            child: Text(l10n.incomeAccept),
          ),
        ],
      ),
    ),
  );
  if (accepted != true || !context.mounted) return false;

  if (salaryPeriod?.isOpen == true) {
    final finalizeResult = await ref
        .read(salaryRepositoryProvider)
        .finalizePeriod(salaryPeriod!.id, salaryEstimate!.toSnapshotJson());
    final failed = finalizeResult.when(
      ok: (_) => false,
      err: (failure) {
        _showFailure(context, failure);
        return true;
      },
    );
    if (failed || !context.mounted) return false;
  }

  final amount = Money.tryParse(
    amountController.text,
    currencyCode: pending.source.currencyCode,
  )!;
  final notes = notesController.text.trim();
  final result = await ref
      .read(financeRepositoryProvider)
      .acceptIncomeOccurrence(
        occurrenceId: pending.occurrence.id,
        actualAmountMinor: amount.minor,
        receivedOn: receivedOn,
        notes: notes.isEmpty ? null : notes,
        salaryPeriodId: salaryPeriod?.id,
      );
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateIncomeAutomation(ref);
      invalidateFinanceData(ref);
      invalidateSalaryData(ref);
      ref
        ..invalidate(historyPageProvider)
        ..invalidate(cashFlowSummaryProvider);
      return true;
    },
    err: (failure) {
      _showFailure(context, failure);
      return false;
    },
  );
}

Future<bool> skipPendingIncome(
  BuildContext context,
  WidgetRef ref,
  PendingIncome pending,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.incomeSkipTitle),
      content: Text(l10n.incomeSkipHelp(pending.source.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.incomeSkip),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final result = await ref
      .read(financeRepositoryProvider)
      .skipIncomeOccurrence(pending.occurrence.id);
  if (!context.mounted) return false;
  return result.when(
    ok: (_) {
      invalidateIncomeAutomation(ref);
      return true;
    },
    err: (failure) {
      _showFailure(context, failure);
      return false;
    },
  );
}
