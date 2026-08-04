import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Focused detail for one credit card or BNPL facility: debt summary,
/// installment plans, the due schedule, and related ledger activity.
class CreditFacilityDetailScreen extends ConsumerWidget {
  const CreditFacilityDetailScreen({super.key, required this.accountId});

  final String accountId;

  Future<void> _cancelPlan(
    BuildContext context,
    WidgetRef ref,
    InstallmentPlan plan,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.planCancelConfirmTitle),
        content: Text(l10n.planCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.planCancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .cancelInstallmentPlan(plan.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, l10n.setSaved);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _reversePayment(
    BuildContext context,
    WidgetRef ref,
    FinancialTransaction payment,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.paymentReverseConfirmTitle),
        content: Text(l10n.paymentReverseConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.paymentReverse),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .reverseFacilityPayment(payment.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateFinanceData(ref);
        AppToast.success(context, l10n.setSaved);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final facilities = ref.watch(creditFacilitiesProvider);
    final facility = facilities.value
        ?.where((f) => f.accountId == accountId)
        .firstOrNull;
    final title = facility?.name ?? l10n.facilityDetailTitle;
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: title,
        actions: [
          IconButton(
            key: const Key('facility-edit-button'),
            tooltip: l10n.commonEdit,
            onPressed: () => context.push('/money/accounts/$accountId'),
            icon: const FinanceSuitIcon(FinanceSuitIcons.edit),
          ),
        ],
      ),
      body: FinanceSuitFocusedBody(
        title: title,
        child: AsyncView<List<CreditFacilitySummary>>(
          value: facilities,
          onRetry: () => ref.invalidate(creditFacilitiesProvider),
          data: (all) {
            final summary = all
                .where((f) => f.accountId == accountId)
                .firstOrNull;
            if (summary == null) {
              return ErrorRetryView(
                failure: const NotFoundFailure(),
                onRetry: () => ref.invalidate(creditFacilitiesProvider),
              );
            }
            return _FacilityDetailBody(
              summary: summary,
              onCancelPlan: (plan) => _cancelPlan(context, ref, plan),
              onReversePayment: (tx) => _reversePayment(context, ref, tx),
            );
          },
        ),
      ),
    );
  }
}

class _FacilityDetailBody extends ConsumerWidget {
  const _FacilityDetailBody({
    required this.summary,
    required this.onCancelPlan,
    required this.onReversePayment,
  });

  final CreditFacilitySummary summary;
  final ValueChanged<InstallmentPlan> onCancelPlan;
  final ValueChanged<FinancialTransaction> onReversePayment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plansAsync = ref.watch(installmentPlansProvider(summary.accountId));
    final duesAsync = ref.watch(installmentDuesProvider(summary.accountId));
    final transactions = ref.watch(recentTransactionsProvider).value;
    final related = (transactions ?? const <FinancialTransaction>[])
        .where(
          (t) =>
              t.sourceAccountId == summary.accountId ||
              t.destinationAccountId == summary.accountId,
        )
        .toList();
    final today = PlainDate.today();
    return RefreshIndicator(
      onRefresh: () async => invalidateFinanceData(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: [
          _FacilitySummaryCard(summary: summary),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('facility-add-purchase'),
                  onPressed: summary.isArchived
                      ? null
                      : () => context.push(
                          '/money/facilities/purchase'
                          '?accountId=${summary.accountId}',
                        ),
                  icon: const FinanceSuitIcon(FinanceSuitIcons.addCircle),
                  label: Text(
                    l10n.facilityAddPurchase,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('facility-make-payment'),
                  onPressed: summary.isArchived || summary.outstandingMinor <= 0
                      ? null
                      : () => context.push(
                          '/money/facilities/pay'
                          '?accountId=${summary.accountId}',
                        ),
                  icon: const FinanceSuitIcon(FinanceSuitIcons.payments),
                  label: Text(
                    l10n.facilityMakePayment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l10n.facilityDuesSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AsyncView<List<InstallmentDue>>(
            value: duesAsync,
            onRetry: () =>
                ref.invalidate(installmentDuesProvider(summary.accountId)),
            data: (dues) {
              final open = dues
                  .where(
                    (d) =>
                        d.planStatus == InstallmentPlanStatus.active &&
                        d.remainingMinor > 0,
                  )
                  .toList();
              if (open.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.facilityNoDues),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final due in open.take(12))
                      _DueTile(due: due, today: today),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            l10n.facilityPlansSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          AsyncView<List<InstallmentPlan>>(
            value: plansAsync,
            onRetry: () =>
                ref.invalidate(installmentPlansProvider(summary.accountId)),
            data: (plans) {
              if (plans.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.facilityNoPlans),
                  ),
                );
              }
              return Column(
                children: [
                  for (final plan in plans)
                    _PlanCard(
                      plan: plan,
                      onCancel:
                          plan.status == InstallmentPlanStatus.active &&
                              plan.paidMinor == 0
                          ? () => onCancelPlan(plan)
                          : null,
                    ),
                ],
              );
            },
          ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l10n.facilityHistorySection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final tx in related.take(10))
                    _RelatedActivityTile(
                      transaction: tx,
                      facilityAccountId: summary.accountId,
                      onReverse:
                          tx.isTransfer &&
                              tx.destinationAccountId == summary.accountId
                          ? () => onReversePayment(tx)
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FacilitySummaryCard extends StatelessWidget {
  const _FacilitySummaryCard({required this.summary});

  final CreditFacilitySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final theme = Theme.of(context);
    final utilization = summary.utilizationFraction;
    final tone = summary.hasOverdue
        ? colors.error
        : utilization >= 0.9
        ? colors.warning
        : colors.info;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FinanceSuitIcon(
                  accountTypeIcon(summary.accountType),
                  color: tone.icon,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      accountTypeLabel(l10n, summary.accountType),
                      if (summary.lastFourDigits != null)
                        '•••• ${summary.lastFourDigits}',
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (summary.hasOverdue)
                  _StatusChip(
                    label: l10n.facilityOverdueBadge,
                    tone: colors.error,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.facilityOwed, style: theme.textTheme.bodySmall),
            AppMoneyText(
              money: summary.outstanding,
              style: theme.textTheme.headlineSmall,
              sign: AppMoneySign.never,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: utilization,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: tone.icon,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    label: l10n.facilityAvailable,
                    money: summary.availableCredit,
                  ),
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: l10n.facilityCreditLimit,
                    money: summary.creditLimit,
                  ),
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: l10n.facilityUtilization,
                    text:
                        '${(summary.utilizationBasisPoints / 100).toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
            if (summary.dueNowMinor > 0 || summary.nextDueOn != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  if (summary.dueNowMinor > 0)
                    Expanded(
                      child: _SummaryMetric(
                        label: l10n.facilityDueNow,
                        money: summary.dueNow,
                      ),
                    ),
                  if (summary.nextDueOn != null)
                    Expanded(
                      child: _SummaryMetric(
                        label: l10n.facilityNextDue(summary.nextDueOn!.toIso()),
                        money: summary.nextDueAmount,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, this.money, this.text});

  final String label;
  final Money? money;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (money != null)
          AppMoneyText(
            money: money!,
            style: theme.textTheme.titleSmall,
            sign: AppMoneySign.never,
          )
        else
          Text(text ?? '', style: theme.textTheme.titleSmall),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final FinanceSuitStatusColors tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: tone.text),
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.due, required this.today});

  final InstallmentDue due;
  final PlainDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final status = due.statusFor(today);
    final tone = switch (status) {
      InstallmentDueStatus.overdue => colors.error,
      InstallmentDueStatus.dueToday => colors.warning,
      InstallmentDueStatus.partiallyPaid => colors.info,
      _ => colors.info,
    };
    return ListTile(
      dense: true,
      title: Text(
        '${due.planTitle} · ${due.sequenceNumber}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${due.dueOn.toIso()} · '
        '${installmentDueStatusLabel(l10n, status)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AppMoneyText(
            money: due.remaining,
            style: Theme.of(context).textTheme.titleSmall,
            sign: AppMoneySign.never,
          ),
          if (status == InstallmentDueStatus.overdue ||
              status == InstallmentDueStatus.dueToday)
            Text(
              installmentDueStatusLabel(l10n, status),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tone.text),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.onCancel});

  final InstallmentPlan plan;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = plan.totalPayableMinor == 0
        ? 0.0
        : plan.paidMinor / plan.totalPayableMinor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  installmentPlanStatusLabel(l10n, plan.status),
                  style: theme.textTheme.labelSmall,
                ),
                if (onCancel != null)
                  IconButton(
                    key: Key('plan-cancel-${plan.id}'),
                    tooltip: l10n.planCancel,
                    onPressed: onCancel,
                    icon: const FinanceSuitIcon(FinanceSuitIcons.delete),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ProtectedMoneyText(
              l10n.planPaidOfTotal(
                plan.paid.format(),
                plan.totalPayable.format(),
              ),
              style: theme.textTheme.bodySmall,
              interactive: false,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 4,
              ),
            ),
            if (plan.status == InstallmentPlanStatus.active &&
                plan.nextDueOn != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.facilityNextDue(plan.nextDueOn!.toIso()),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelatedActivityTile extends StatelessWidget {
  const _RelatedActivityTile({
    required this.transaction,
    required this.facilityAccountId,
    this.onReverse,
  });

  final FinancialTransaction transaction;
  final String facilityAccountId;
  final VoidCallback? onReverse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRepayment =
        transaction.isTransfer &&
        transaction.destinationAccountId == facilityAccountId;
    final isReversal =
        transaction.isTransfer &&
        transaction.sourceAccountId == facilityAccountId;
    final label = isRepayment
        ? l10n.facilityRepaymentLabel
        : isReversal
        ? l10n.facilityReversalLabel
        : l10n.facilityPurchaseLabel;
    return ListTile(
      dense: true,
      leading: FinanceSuitIcon(
        isRepayment || isReversal
            ? FinanceSuitIcons.payments
            : FinanceSuitIcons.shoppingCart,
      ),
      title: Text(
        transaction.title ?? label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${transaction.occurredOn.toIso()} · $label'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppMoneyText(
            money: transaction.amount,
            style: Theme.of(context).textTheme.titleSmall,
            sign: AppMoneySign.never,
          ),
          if (onReverse != null)
            IconButton(
              key: Key('payment-reverse-${transaction.id}'),
              tooltip: l10n.paymentReverse,
              onPressed: onReverse,
              icon: const FinanceSuitIcon(FinanceSuitIcons.undo),
            ),
        ],
      ),
    );
  }
}
