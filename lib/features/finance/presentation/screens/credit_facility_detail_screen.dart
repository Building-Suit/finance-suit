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
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';
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

  Future<void> _restructurePlan(
    BuildContext context,
    WidgetRef ref,
    InstallmentPlan plan,
  ) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _RestructureDialog(plan: plan, ref: ref),
    );
    if (submitted == true && context.mounted) {
      invalidateFinanceData(ref);
      AppToast.success(context, AppLocalizations.of(context).setSaved);
    }
  }

  Future<void> _showRevisions(
    BuildContext context,
    WidgetRef ref,
    InstallmentPlan plan,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _RevisionsSheet(plan: plan),
    );
  }

  Future<void> _editFeeRule(
    BuildContext context,
    WidgetRef ref,
    CreditFacilitySummary summary, {
    CardFeeRule? existing,
  }) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _FeeRuleDialog(summary: summary, existing: existing, ref: ref),
    );
    if (submitted == true && context.mounted) {
      ref.invalidate(feeRulesProvider(summary.accountId));
      invalidateFinanceData(ref);
      AppToast.success(context, AppLocalizations.of(context).setSaved);
    }
  }

  Future<void> _toggleFeeRule(
    BuildContext context,
    WidgetRef ref,
    CardFeeRule rule,
  ) async {
    final result = await ref
        .read(financeRepositoryProvider)
        .setFeeRuleActive(rule.id, active: !rule.isActive);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        ref.invalidate(feeRulesProvider(rule.accountId));
        AppToast.success(context, AppLocalizations.of(context).setSaved);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _deleteFeeRule(
    BuildContext context,
    WidgetRef ref,
    CardFeeRule rule,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.feeRuleDeleteConfirmTitle),
        content: Text(l10n.feeRuleDeleteConfirmBody),
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
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .deleteFeeRule(rule.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        ref.invalidate(feeRulesProvider(rule.accountId));
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
              onEditPlan: (plan) =>
                  context.push('/money/facilities/purchase?planId=${plan.id}'),
              onRestructurePlan: (plan) => _restructurePlan(context, ref, plan),
              onShowRevisions: (plan) => _showRevisions(context, ref, plan),
              onReversePayment: (tx) => _reversePayment(context, ref, tx),
              onAddFeeRule: () => _editFeeRule(context, ref, summary),
              onEditFeeRule: (rule) =>
                  _editFeeRule(context, ref, summary, existing: rule),
              onToggleFeeRule: (rule) => _toggleFeeRule(context, ref, rule),
              onDeleteFeeRule: (rule) => _deleteFeeRule(context, ref, rule),
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
    required this.onEditPlan,
    required this.onRestructurePlan,
    required this.onShowRevisions,
    required this.onReversePayment,
    required this.onAddFeeRule,
    required this.onEditFeeRule,
    required this.onToggleFeeRule,
    required this.onDeleteFeeRule,
  });

  final CreditFacilitySummary summary;
  final ValueChanged<InstallmentPlan> onCancelPlan;
  final ValueChanged<InstallmentPlan> onEditPlan;
  final ValueChanged<InstallmentPlan> onRestructurePlan;
  final ValueChanged<InstallmentPlan> onShowRevisions;
  final ValueChanged<FinancialTransaction> onReversePayment;
  final VoidCallback onAddFeeRule;
  final ValueChanged<CardFeeRule> onEditFeeRule;
  final ValueChanged<CardFeeRule> onToggleFeeRule;
  final ValueChanged<CardFeeRule> onDeleteFeeRule;

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
                  onPressed: !summary.canFundPurchases
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
                  // Payments stay possible on archived and frozen cards
                  // until the debt reaches zero.
                  onPressed: summary.outstandingMinor <= 0
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
          if (summary.accountType == AccountType.creditCard &&
              summary.statementDay != null) ...[
            const SizedBox(height: 16),
            Text(
              l10n.facilityStatementsSection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            AsyncView<List<CardStatementSummary>>(
              value: ref.watch(statementSummariesProvider(summary.accountId)),
              onRetry: () =>
                  ref.invalidate(statementSummariesProvider(summary.accountId)),
              data: (statements) {
                if (statements.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.facilityNoStatements),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: [
                      for (final statement in statements.take(6))
                        _StatementTile(statement: statement),
                    ],
                  ),
                );
              },
            ),
          ],
          if (summary.accountType == AccountType.creditCard) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.feeRulesSection,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('fee-rule-add'),
                  onPressed: onAddFeeRule,
                  icon: const FinanceSuitIcon(FinanceSuitIcons.addCircle),
                  label: Text(l10n.feeRuleAdd),
                ),
              ],
            ),
            AsyncView<List<CardFeeRule>>(
              value: ref.watch(feeRulesProvider(summary.accountId)),
              onRetry: () =>
                  ref.invalidate(feeRulesProvider(summary.accountId)),
              data: (rules) {
                if (rules.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.feeRulesEmpty),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: [
                      for (final rule in rules)
                        _FeeRuleTile(
                          rule: rule,
                          currencyCode: summary.currencyCode,
                          onEdit: () => onEditFeeRule(rule),
                          onToggle: () => onToggleFeeRule(rule),
                          onDelete: () => onDeleteFeeRule(rule),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
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
                      onEdit: plan.isEditable ? () => onEditPlan(plan) : null,
                      onRestructure: plan.isEditable && plan.paidMinor > 0
                          ? () => onRestructurePlan(plan)
                          : null,
                      onShowRevisions: plan.revision > 1
                          ? () => onShowRevisions(plan)
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
  const _PlanCard({
    required this.plan,
    this.onCancel,
    this.onEdit,
    this.onRestructure,
    this.onShowRevisions,
  });

  final InstallmentPlan plan;
  final VoidCallback? onCancel;
  final VoidCallback? onEdit;
  final VoidCallback? onRestructure;
  final VoidCallback? onShowRevisions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = plan.totalPayableMinor == 0
        ? 0.0
        : plan.paidMinor / plan.totalPayableMinor;
    final hasActions =
        onCancel != null ||
        onEdit != null ||
        onRestructure != null ||
        onShowRevisions != null;
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
                if (hasActions)
                  PopupMenuButton<VoidCallback>(
                    key: Key('plan-actions-${plan.id}'),
                    tooltip: l10n.planActionsTooltip,
                    onSelected: (action) => action(),
                    itemBuilder: (menuContext) => [
                      if (onEdit != null)
                        PopupMenuItem(
                          key: Key('plan-edit-${plan.id}'),
                          value: onEdit!,
                          child: Text(l10n.planEditAction),
                        ),
                      if (onRestructure != null)
                        PopupMenuItem(
                          key: Key('plan-restructure-${plan.id}'),
                          value: onRestructure!,
                          child: Text(l10n.planRestructureAction),
                        ),
                      if (onShowRevisions != null)
                        PopupMenuItem(
                          key: Key('plan-revisions-${plan.id}'),
                          value: onShowRevisions!,
                          child: Text(l10n.planRevisionsAction),
                        ),
                      if (onCancel != null)
                        PopupMenuItem(
                          key: Key('plan-cancel-${plan.id}'),
                          value: onCancel!,
                          child: Text(l10n.planCancel),
                        ),
                    ],
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

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.statement});

  final CardStatementSummary statement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final theme = Theme.of(context);
    final tone = switch (statement.status) {
      StatementCycleStatus.overdue => colors.error,
      StatementCycleStatus.dueToday => colors.warning,
      _ => colors.info,
    };
    return ListTile(
      dense: true,
      title: Text(
        l10n.statementCycleTitle(statement.cycleClose.toIso()),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${l10n.statementDueOn(statement.dueOn.toIso())} · '
        '${statementCycleStatusLabel(l10n, statement.status)}'
        '${statement.minimumDueMinor < statement.remainingMinor && statement.remainingMinor > 0 ? '\n${l10n.statementMinimumDue}: ${statement.minimumDue.format()}' : ''}',
      ),
      isThreeLine:
          statement.minimumDueMinor < statement.remainingMinor &&
          statement.remainingMinor > 0,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AppMoneyText(
            money: statement.remaining,
            style: theme.textTheme.titleSmall,
            sign: AppMoneySign.never,
          ),
          if (statement.status == StatementCycleStatus.overdue ||
              statement.status == StatementCycleStatus.dueToday)
            Text(
              statementCycleStatusLabel(l10n, statement.status),
              style: theme.textTheme.labelSmall?.copyWith(color: tone.text),
            ),
        ],
      ),
    );
  }
}

/// Restructures the unpaid remainder of a partially paid plan: new total,
/// new count, and the next due date.
class _RestructureDialog extends StatefulWidget {
  const _RestructureDialog({required this.plan, required this.ref});

  final InstallmentPlan plan;
  final WidgetRef ref;

  @override
  State<_RestructureDialog> createState() => _RestructureDialogState();
}

class _RestructureDialogState extends State<_RestructureDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _totalController;
  late final TextEditingController _countController;
  final _noteController = TextEditingController();
  late PlainDate _nextDueOn;
  AppFailure? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(
      text: formatMinorForInput(widget.plan.remainingMinor),
    );
    _countController = TextEditingController();
    _nextDueOn = widget.plan.nextDueOn ?? PlainDate.today().addMonths(1);
  }

  @override
  void dispose() {
    _totalController.dispose();
    _countController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDueOn.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _nextDueOn = PlainDate.fromDateTime(picked));
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final currency = widget.plan.currencyCode;
    final total = Money.tryParse(
      _totalController.text,
      currencyCode: currency,
    )!;
    final count = int.parse(_countController.text.trim());
    final note = _noteController.text.trim();
    setState(() => _busy = true);
    final result = await widget.ref
        .read(financeRepositoryProvider)
        .restructureInstallmentPlan(
          planId: widget.plan.id,
          remainingTotalMinor: total.minor,
          remainingCount: count,
          nextDueOn: _nextDueOn,
          changeNote: note.isEmpty ? null : note,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) => Navigator.of(context).pop(true),
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = widget.plan.currencyCode;
    return AlertDialog(
      title: Text(l10n.planRestructureTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.planRestructureBody,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                key: const Key('restructure-total'),
                controller: _totalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: moneyInputFormatters(),
                decoration: InputDecoration(
                  labelText: l10n.planRestructureRemainingTotal,
                  suffixText: currency,
                ),
                validator: (v) {
                  final e = Validators.positiveAmount(
                    v,
                    currencyCode: currency,
                  );
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                key: const Key('restructure-count'),
                controller: _countController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.planRestructureRemainingCount,
                ),
                validator: (v) {
                  final value = int.tryParse(v?.trim() ?? '');
                  return value == null || value < 1 || value > 120
                      ? l10n.valInstallmentCount
                      : null;
                },
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.planRestructureNextDue),
                subtitle: Text(_nextDueOn.toIso()),
                trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                onTap: _busy ? null : _pickDate,
              ),
              AppTextFormField(
                key: const Key('restructure-note'),
                controller: _noteController,
                decoration: InputDecoration(
                  labelText:
                      '${l10n.planRestructureNote} (${l10n.commonOptional})',
                ),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 8),
                Text(
                  failureMessage(context, _failure!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('restructure-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// Read-only audit trail of a plan's restructures.
class _RevisionsSheet extends ConsumerWidget {
  const _RevisionsSheet({required this.plan});

  final InstallmentPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final revisionsAsync = ref.watch(planRevisionsProvider(plan.id));
    Money money(int minor) =>
        Money(minor: minor, currencyCode: plan.currencyCode);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.planRevisionsTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: AsyncView<List<InstallmentPlanRevision>>(
                value: revisionsAsync,
                onRetry: () => ref.invalidate(planRevisionsProvider(plan.id)),
                data: (revisions) {
                  if (revisions.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.planRevisionsEmpty),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final revision in revisions)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text('${revision.revision}'),
                          ),
                          title: Text(revision.changeSummary),
                          subtitle: ProtectedMoneyText(
                            '${money(revision.previousTotalPayableMinor).format()}'
                            ' → '
                            '${money(revision.newTotalPayableMinor).format()}',
                            interactive: false,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeRuleTile extends StatelessWidget {
  const _FeeRuleTile({
    required this.rule,
    required this.currencyCode,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final CardFeeRule rule;
  final String currencyCode;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final amountText = rule.isPercent
        ? l10n.feeRulePercentOfBasis(
            (rule.percentValue ?? 0).toStringAsFixed(2),
            feePercentBasisLabel(l10n, rule.percentBasis!),
          )
        : rule.fixedAmount(currencyCode)!.format();
    final schedule = rule.isActive
        ? rule.nextChargeOn == null
              ? feeFrequencyLabel(l10n, rule.frequency)
              : l10n.feeRuleNextCharge(rule.nextChargeOn!.toIso())
        : l10n.feeRuleInactive;
    return ListTile(
      dense: true,
      title: Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${cardFeeTypeLabel(l10n, rule.feeType)} · '
        '${feeFrequencyLabel(l10n, rule.frequency)}\n$schedule',
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rule.isPercent)
            Text(amountText, style: theme.textTheme.titleSmall)
          else
            ProtectedMoneyText(
              amountText,
              style: theme.textTheme.titleSmall,
              interactive: false,
            ),
          PopupMenuButton<VoidCallback>(
            key: Key('fee-rule-actions-${rule.id}'),
            tooltip: l10n.planActionsTooltip,
            onSelected: (action) => action(),
            itemBuilder: (menuContext) => [
              PopupMenuItem(value: onEdit, child: Text(l10n.commonEdit)),
              PopupMenuItem(
                value: onToggle,
                child: Text(
                  rule.isActive ? l10n.feeRuleDeactivate : l10n.feeRuleActivate,
                ),
              ),
              PopupMenuItem(value: onDelete, child: Text(l10n.commonDelete)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Creates or edits one recurring card fee rule. Fixed-amount fees take an
/// exact amount; percent fees take a rate and the balance it applies to.
class _FeeRuleDialog extends StatefulWidget {
  const _FeeRuleDialog({
    required this.summary,
    required this.ref,
    this.existing,
  });

  final CreditFacilitySummary summary;
  final CardFeeRule? existing;
  final WidgetRef ref;

  @override
  State<_FeeRuleDialog> createState() => _FeeRuleDialogState();
}

class _FeeRuleDialogState extends State<_FeeRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _percentController;

  late CardFeeType _feeType;
  late FeeFrequency _frequency;
  late FeePercentBasis _percentBasis;
  late bool _isPercent;
  late PlainDate _startsOn;
  String? _categoryId;
  AppFailure? _failure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _amountController = TextEditingController(
      text: existing?.fixedAmountMinor == null
          ? ''
          : formatMinorForInput(existing!.fixedAmountMinor!),
    );
    _percentController = TextEditingController(
      text: existing?.percentValue == null
          ? ''
          : existing!.percentValue!.toStringAsFixed(2),
    );
    _feeType = existing?.feeType ?? CardFeeType.annualMembership;
    _frequency = existing?.frequency ?? FeeFrequency.annually;
    _percentBasis = existing?.percentBasis ?? FeePercentBasis.creditLimit;
    _isPercent = existing?.isPercent ?? false;
    _startsOn = existing?.startsOn ?? PlainDate.today();
    _categoryId = existing?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _percentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _startsOn = PlainDate.fromDateTime(picked));
  }

  int? get _percentBasisPoints {
    final value = double.tryParse(_percentController.text.trim());
    if (value == null) return null;
    final basisPoints = (value * 100).round();
    return basisPoints < 1 || basisPoints > 100000 ? null : basisPoints;
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    final currency = widget.summary.currencyCode;
    final draft = CardFeeRuleDraft(
      accountId: widget.summary.accountId,
      name: _nameController.text.trim(),
      feeType: _feeType,
      frequency: _frequency,
      startsOn: _startsOn,
      categoryId: _categoryId!,
      fixedAmountMinor: _isPercent
          ? null
          : Money.tryParse(
              _amountController.text,
              currencyCode: currency,
            )!.minor,
      percentBasisPoints: _isPercent ? _percentBasisPoints : null,
      percentBasis: _isPercent ? _percentBasis : null,
    );
    setState(() => _busy = true);
    final result = await widget.ref
        .read(financeRepositoryProvider)
        .saveFeeRule(draft, ruleId: widget.existing?.id);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) => Navigator.of(context).pop(true),
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = widget.summary.currencyCode;
    final categories =
        widget.ref.watch(categoriesProvider(CategoryKind.expense)).value ??
        const [];
    if (_categoryId == null && categories.isNotEmpty) {
      _categoryId = categories.first.id;
    }
    return AlertDialog(
      title: Text(widget.existing == null ? l10n.feeRuleAdd : l10n.feeRuleEdit),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextFormField(
                key: const Key('fee-rule-name'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.feeRuleName),
                validator: (v) {
                  final e = Validators.requiredText(v, maxLength: 80);
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              const SizedBox(height: 12),
              AppSelectionField<CardFeeType>(
                key: ValueKey('fee-rule-type-$_feeType'),
                initialValue: _feeType,
                decoration: InputDecoration(labelText: l10n.feeRuleType),
                items: [
                  for (final type in CardFeeType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(cardFeeTypeLabel(l10n, type)),
                    ),
                ],
                onChanged: (v) => setState(
                  () => _feeType = v ?? CardFeeType.annualMembership,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const Key('fee-rule-percent-toggle'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.feeRulePercentToggle),
                value: _isPercent,
                onChanged: _busy ? null : (v) => setState(() => _isPercent = v),
              ),
              if (_isPercent) ...[
                AppTextFormField(
                  key: const Key('fee-rule-percent'),
                  controller: _percentController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.feeRulePercentLabel,
                    suffixText: '%',
                  ),
                  validator: (v) =>
                      _percentBasisPoints == null ? l10n.valFeePercent : null,
                ),
                const SizedBox(height: 12),
                AppSelectionField<FeePercentBasis>(
                  key: ValueKey('fee-rule-basis-$_percentBasis'),
                  initialValue: _percentBasis,
                  decoration: InputDecoration(
                    labelText: l10n.feeRulePercentBasis,
                  ),
                  items: [
                    for (final basis in FeePercentBasis.values)
                      DropdownMenuItem(
                        value: basis,
                        child: Text(feePercentBasisLabel(l10n, basis)),
                      ),
                  ],
                  onChanged: (v) => setState(
                    () => _percentBasis = v ?? FeePercentBasis.creditLimit,
                  ),
                ),
              ] else
                AppTextFormField(
                  key: const Key('fee-rule-amount'),
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyInputFormatters(),
                  decoration: InputDecoration(
                    labelText: l10n.feeRuleFixedAmount,
                    suffixText: currency,
                  ),
                  validator: (v) {
                    final e = Validators.positiveAmount(
                      v,
                      currencyCode: currency,
                    );
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
              const SizedBox(height: 12),
              AppSelectionField<FeeFrequency>(
                key: ValueKey('fee-rule-frequency-$_frequency'),
                initialValue: _frequency,
                decoration: InputDecoration(labelText: l10n.feeRuleFrequency),
                items: [
                  for (final frequency in FeeFrequency.values)
                    DropdownMenuItem(
                      value: frequency,
                      child: Text(feeFrequencyLabel(l10n, frequency)),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _frequency = v ?? FeeFrequency.annually),
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.feeRuleStartsOn),
                subtitle: Text(_startsOn.toIso()),
                trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                onTap: _busy ? null : _pickDate,
              ),
              AppSelectionField<String>(
                key: ValueKey('fee-rule-category-$_categoryId'),
                initialValue: _categoryId,
                decoration: InputDecoration(labelText: l10n.txCategory),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null
                    ? validationMessage(context, ValidationError.required)
                    : null,
              ),
              if (_failure != null) ...[
                const SizedBox(height: 8),
                Text(
                  failureMessage(context, _failure!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('fee-rule-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
