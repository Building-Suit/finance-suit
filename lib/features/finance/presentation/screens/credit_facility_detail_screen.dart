import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
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
import 'package:work_tracker/features/finance/domain/facility_activity.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/features/finance/domain/installment_responsibility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/providers/responsibility_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/facility_due_breakdown_widgets.dart';
import 'package:work_tracker/features/finance/presentation/widgets/facility_due_month_carousel.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/finance/presentation/widgets/responsibility_widgets.dart';
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
    final result = await showDialog<_FeeRuleDialogResult>(
      context: context,
      builder: (dialogContext) =>
          _FeeRuleDialog(summary: summary, existing: existing),
    );
    if (!context.mounted) return;
    switch (result) {
      case _FeeRuleDialogResult.saved:
        ref.invalidate(feeRulesProvider(summary.accountId));
        invalidateFinanceData(ref);
        AppToast.success(context, AppLocalizations.of(context).setSaved);
      case _FeeRuleDialogResult.addCategory:
        // A fee is booked as an expense and has nowhere to go without an
        // expense category, so send the user to create one and pick this
        // dialog back up right where they left off instead of dead-ending
        // on a required field with nothing to select.
        await context.push('${AppRoutes.money}/categories/new?kind=expense');
        if (!context.mounted) return;
        await _editFeeRule(context, ref, summary, existing: existing);
      case null:
        break;
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

  /// Opens the canonical editor for one Related activity row. Which editor
  /// that is comes from [resolveFacilityActivityAction], the single
  /// capability decision, so no row can offer an action it cannot perform.
  Future<void> _openActivity(
    BuildContext context,
    WidgetRef ref,
    FacilityActivityItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    switch (resolveFacilityActivityAction(item)) {
      case FacilityActivityAction.editTransaction:
        // Pushing keeps this facility detail underneath, so a successful
        // save returns straight back to it with refreshed totals.
        await context.push(
          '${AppRoutes.money}/tx/edit',
          extra: item.toTransaction(),
        );
        if (context.mounted) invalidateFinanceData(ref);
      case FacilityActivityAction.editPlan:
        if (item.planId == null) return;
        await context.push(
          '${AppRoutes.money}/facilities/purchase?planId=${item.planId}',
        );
        if (context.mounted) invalidateFinanceData(ref);
      case FacilityActivityAction.reversePayment:
        await _showPaymentDetail(context, ref, item);
      case FacilityActivityAction.explainSettled:
        AppToast.warning(context, l10n.facilityActivitySettled);
      case FacilityActivityAction.explainFee:
        AppToast.warning(context, l10n.facilityActivityFeeLocked);
      case FacilityActivityAction.explainSystem:
        AppToast.warning(context, l10n.facilityActivitySystemRecord);
    }
  }

  Future<void> _reversePayment(
    BuildContext context,
    WidgetRef ref,
    FacilityActivityItem payment,
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
        .reverseFacilityPayment(payment.transactionId);
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

  /// Payment detail sheet: the transfer plus the exact persisted
  /// Applied-to allocations — never a guess from the current due order.
  Future<void> _showPaymentDetail(
    BuildContext context,
    WidgetRef ref,
    FacilityActivityItem payment,
  ) async {
    final reverse = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext);
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.facilityRepaymentLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                    AppMoneyText(
                      money: payment.amount,
                      style: theme.textTheme.titleMedium,
                      sign: AppMoneySign.never,
                    ),
                  ],
                ),
                Text(
                  payment.occurredOn.toIso(),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text(l10n.paymentAppliedTo, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Flexible(
                  child: Consumer(
                    builder: (context, ref, _) =>
                        AsyncView<List<FacilityPaymentAllocationDetail>>(
                          value: ref.watch(
                            paymentAllocationsProvider(payment.transactionId),
                          ),
                          onRetry: () => ref.invalidate(
                            paymentAllocationsProvider(payment.transactionId),
                          ),
                          data: (allocations) => ListView(
                            shrinkWrap: true,
                            children: [
                              for (final allocation in allocations)
                                _AppliedToRow(allocation: allocation),
                            ],
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('payment-detail-reverse'),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(l10n.paymentReverse),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (reverse == true && context.mounted) {
      await _reversePayment(context, ref, payment);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final facilities = ref.watch(allCreditFacilitiesProvider);
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
          onRetry: () => ref.invalidate(allCreditFacilitiesProvider),
          data: (all) {
            final summary = all
                .where((f) => f.accountId == accountId)
                .firstOrNull;
            if (summary == null) {
              return ErrorRetryView(
                failure: const NotFoundFailure(),
                onRetry: () => ref.invalidate(allCreditFacilitiesProvider),
              );
            }
            return _FacilityDetailBody(
              summary: summary,
              onCancelPlan: (plan) => _cancelPlan(context, ref, plan),
              onEditPlan: (plan) =>
                  context.push('/money/facilities/purchase?planId=${plan.id}'),
              onRestructurePlan: (plan) => _restructurePlan(context, ref, plan),
              onShowRevisions: (plan) => _showRevisions(context, ref, plan),
              onOpenActivity: (item) => _openActivity(context, ref, item),
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
    required this.onOpenActivity,
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
  final ValueChanged<FacilityActivityItem> onOpenActivity;
  final VoidCallback onAddFeeRule;
  final ValueChanged<CardFeeRule> onEditFeeRule;
  final ValueChanged<CardFeeRule> onToggleFeeRule;
  final ValueChanged<CardFeeRule> onDeleteFeeRule;

  /// Inline plan-card budget. Each card is several times taller than a due
  /// row, so the cap is lower than the breakdown's ten to keep the single
  /// column surface comfortably inside the raster budget.
  static const _maxInlinePlans = 5;

  /// One plan card with its full action wiring, shared by the inline column
  /// and the show-all sheet so both stay in lockstep.
  Widget _planCard(
    BuildContext context,
    WidgetRef ref,
    InstallmentPlan plan,
    InstallmentResponsibilitySummary? responsibility,
  ) {
    return _PlanCard(
      plan: plan,
      responsibility: responsibility,
      onCancel:
          plan.status == InstallmentPlanStatus.active && plan.paidMinor == 0
          ? () => onCancelPlan(plan)
          : null,
      onEdit: plan.isEditable ? () => onEditPlan(plan) : null,
      onRestructure: plan.isEditable && plan.paidMinor > 0
          ? () => onRestructurePlan(plan)
          : null,
      onShowRevisions: plan.revision > 1 ? () => onShowRevisions(plan) : null,
      onLink:
          plan.status == InstallmentPlanStatus.active && responsibility == null
          ? () => showResponsibilityLinkSheet(context, ref, planId: plan.id)
          : null,
      onOpenResponsibility: responsibility == null
          ? null
          : () => context.push('/money/linked/${responsibility.linkId}'),
    );
  }

  /// Opens the complete plan list as a modal sheet backed by a lazy
  /// [ListView], so a facility with dozens of plans never paints one
  /// oversized column.
  Future<void> _showAllPlans(
    BuildContext context,
    WidgetRef ref, {
    required List<InstallmentPlan> plans,
    required Map<String, InstallmentResponsibilitySummary> respSummaries,
  }) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          l10n.facilityPlansSection,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Text(
                      l10n.facilityPlansCount(plans.length),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  key: const Key('facility-plans-sheet-list'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: plans.length,
                  itemBuilder: (_, index) {
                    final plan = plans[index];
                    // Actions run against the screen's context, exactly as
                    // they do from the inline column.
                    return _planCard(
                      context,
                      ref,
                      plan,
                      respSummaries[plan.id],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plansAsync = ref.watch(installmentPlansProvider(summary.accountId));
    final duesAsync = ref.watch(installmentDuesProvider(summary.accountId));
    final activityAsync = ref.watch(
      facilityActivityProvider(summary.accountId),
    );
    final related = activityAsync.value ?? const <FacilityActivityItem>[];
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
                      // A BNPL facility funds both an ordinary purchase and
                      // an installment plan, so it asks which one instead of
                      // assuming the installment flow. A card keeps its
                      // single existing route.
                      : summary.accountType == AccountType.bnpl
                      ? () => _showAddPurchaseSheet(context, summary)
                      : () => context.push(
                          '/money/facilities/purchase'
                          '?accountId=${summary.accountId}',
                        ),
                  icon: const FinanceSuitIcon(FinanceSuitIcons.addCircle),
                  label: Text(
                    summary.accountType == AccountType.bnpl
                        ? l10n.facilityAddPurchaseSheetTitle
                        : l10n.facilityAddPurchase,
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
          const SizedBox(height: 16),
          Text(
            l10n.dueBreakdownTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _FacilityDueMonthSection(accountId: summary.accountId),
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
              final respSummaries =
                  ref.watch(responsibilitySummariesProvider).value ??
                  const <String, InstallmentResponsibilitySummary>{};
              // Same defect class as the heavy statement month: this whole
              // column paints as one surface, so enough plans push it past
              // what the GPU will rasterize and the section renders as a
              // flat gray block. The first few plans stay inline; the full
              // list opens in a lazy sheet.
              return Column(
                key: const Key('facility-plans-column'),
                children: [
                  for (final plan in plans.take(_maxInlinePlans))
                    _planCard(context, ref, plan, respSummaries[plan.id]),
                  if (plans.length > _maxInlinePlans)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: const Key('facility-plans-show-all'),
                        onPressed: () => _showAllPlans(
                          context,
                          ref,
                          plans: plans,
                          respSummaries: respSummaries,
                        ),
                        child: Text(l10n.facilityPlansShowAll(plans.length)),
                      ),
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
                  for (final item in related.take(10))
                    _RelatedActivityTile(
                      item: item,
                      onAction: () => onOpenActivity(item),
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

/// BNPL funds two different products from one button. The sheet names them
/// instead of guessing: Normal opens the canonical expense form with the
/// facility preselected — there is no second ordinary-expense form — and
/// Installment opens the existing plan flow unchanged.
Future<void> _showAddPurchaseSheet(
  BuildContext context,
  CreditFacilitySummary summary,
) async {
  final l10n = AppLocalizations.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.facilityAddPurchaseSheetTitle,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const Key('facility-purchase-normal'),
            leading: const FinanceSuitIcon(FinanceSuitIcons.shoppingCart),
            title: Text(l10n.facilityPurchaseNormal),
            subtitle: Text(l10n.facilityPurchaseNormalHint),
            onTap: () => Navigator.of(sheetContext).pop('normal'),
          ),
          ListTile(
            key: const Key('facility-purchase-installment'),
            leading: const FinanceSuitIcon(FinanceSuitIcons.eventRepeat),
            title: Text(l10n.facilityPurchaseInstallment),
            subtitle: Text(l10n.facilityPurchaseInstallmentHint),
            onTap: () => Navigator.of(sheetContext).pop('installment'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  await context.push(
    choice == 'normal'
        ? '${AppRoutes.money}/tx/new?kind=expense'
              '&accountId=${summary.accountId}'
        : '/money/facilities/purchase?accountId=${summary.accountId}',
  );
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
    // The header wears the card's own colour; the figures below it keep the
    // neutral surface so amounts and statuses stay maximally readable.
    final swatch = FacilitySwatches.parse(summary.colorHex);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (swatch == null)
                  FinanceSuitIcon(
                    accountTypeIcon(summary.accountType),
                    color: tone.icon,
                  )
                else
                  Container(
                    key: const Key('facility-detail-swatch'),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: swatch,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FinanceSuitIcon(
                      accountTypeIcon(summary.accountType),
                      color: onFacilitySwatch(swatch),
                      size: 18,
                    ),
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
    this.responsibility,
    this.onCancel,
    this.onEdit,
    this.onRestructure,
    this.onShowRevisions,
    this.onLink,
    this.onOpenResponsibility,
  });

  final InstallmentPlan plan;
  final InstallmentResponsibilitySummary? responsibility;
  final VoidCallback? onCancel;
  final VoidCallback? onEdit;
  final VoidCallback? onRestructure;
  final VoidCallback? onShowRevisions;
  final VoidCallback? onLink;
  final VoidCallback? onOpenResponsibility;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Progress tracks the item, bank-style: each installment counts only
    // its principal share (original amount / count); interest and fees are
    // the bank's and are reported on their own line.
    final progress = plan.financedPrincipalMinor == 0
        ? 0.0
        : plan.principalPaidMinor / plan.financedPrincipalMinor;
    final hasActions =
        onCancel != null ||
        onEdit != null ||
        onRestructure != null ||
        onShowRevisions != null ||
        onLink != null ||
        onOpenResponsibility != null;
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
                      if (onLink != null)
                        PopupMenuItem(
                          key: Key('plan-link-${plan.id}'),
                          value: onLink!,
                          child: Text(l10n.respLinkAction),
                        ),
                      if (onOpenResponsibility != null)
                        PopupMenuItem(
                          key: Key('plan-responsibility-${plan.id}'),
                          value: onOpenResponsibility!,
                          child: Text(l10n.respOpenAction),
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
            if (responsibility != null) ...[
              const SizedBox(height: 4),
              InkWell(
                key: Key('plan-resp-chip-${plan.id}'),
                onTap: onOpenResponsibility,
                child: Text(
                  responsibilityStatusLabel(l10n, responsibility!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: responsibility!.isRejected
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            ProtectedMoneyText(
              l10n.planPaidOfTotal(
                plan.principalPaid.format(),
                plan.financedPrincipal.format(),
              ),
              style: theme.textTheme.bodySmall,
              interactive: false,
            ),
            const SizedBox(height: 4),
            ProtectedMoneyText(
              '${l10n.planOutstandingPrincipal}: '
              '${plan.remainingPrincipal.format()}',
              style: theme.textTheme.bodySmall,
              interactive: false,
            ),
            ProtectedMoneyText(
              '${l10n.planRemainingScheduledPayments}: '
              '${plan.remainingScheduledPayments.format()}',
              style: theme.textTheme.bodySmall,
              interactive: false,
            ),
            if (plan.remainingFutureInterestMinor > 0)
              ProtectedMoneyText(
                '${l10n.planRemainingFutureInterest}: '
                '${plan.remainingFutureInterest.format()}',
                style: theme.textTheme.bodySmall,
                interactive: false,
              ),
            Text(
              l10n.planInstallmentCounts(
                plan.paidInstallments,
                plan.currentPostedInstallments,
                plan.futureInstallments,
              ),
              style: theme.textTheme.bodySmall,
            ),
            if (plan.bankCostTotalMinor > 0) ...[
              const SizedBox(height: 2),
              ProtectedMoneyText(
                l10n.planBankCostPaid(
                  plan.bankCostPaid.format(),
                  plan.bankCostTotal.format(),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                interactive: false,
              ),
            ],
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

/// One Related activity row. Both the label and the offered action come from
/// the server-side classification, so an ordinary expense always exposes
/// Edit transaction while installment, fee, and repayment rows keep their
/// own specialized flows.
class _RelatedActivityTile extends StatelessWidget {
  const _RelatedActivityTile({required this.item, required this.onAction});

  final FacilityActivityItem item;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = resolveFacilityActivityAction(item);
    final label = switch (item.kind) {
      FacilityActivityKind.facilityRepayment => l10n.facilityRepaymentLabel,
      FacilityActivityKind.repaymentReversal => l10n.facilityReversalLabel,
      FacilityActivityKind.installmentPurchase =>
        l10n.facilityActivityInstallment,
      FacilityActivityKind.installmentDownPayment =>
        l10n.facilityActivityDownPayment,
      FacilityActivityKind.feeCharge => l10n.facilityActivityFee,
      FacilityActivityKind.purchaseInterest =>
        l10n.facilityActivityPurchaseInterest,
      FacilityActivityKind.installmentInterest =>
        l10n.facilityActivityInstallmentInterest,
      FacilityActivityKind.ordinaryExpense ||
      FacilityActivityKind.other => l10n.facilityPurchaseLabel,
    };
    final actionLabel = switch (action) {
      FacilityActivityAction.editTransaction => l10n.txEditTitle,
      FacilityActivityAction.editPlan => l10n.planEditAction,
      FacilityActivityAction.reversePayment => l10n.paymentReverse,
      _ => l10n.facilityActivityWhyLocked,
    };
    final icon = switch (item.kind) {
      FacilityActivityKind.facilityRepayment ||
      FacilityActivityKind.repaymentReversal => FinanceSuitIcons.payments,
      FacilityActivityKind.feeCharge ||
      FacilityActivityKind.purchaseInterest ||
      FacilityActivityKind.installmentInterest => FinanceSuitIcons.receiptLong,
      _ => FinanceSuitIcons.shoppingCart,
    };
    return ListTile(
      dense: true,
      leading: FinanceSuitIcon(icon),
      title: Text(
        item.title ?? label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${item.occurredOn.toIso()} · $label'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppMoneyText(
            money: item.amount,
            style: Theme.of(context).textTheme.titleSmall,
            sign: AppMoneySign.never,
          ),
          PopupMenuButton<VoidCallback>(
            key: Key('activity-actions-${item.transactionId}'),
            tooltip: l10n.planActionsTooltip,
            onSelected: (selected) => selected(),
            itemBuilder: (menuContext) => [
              PopupMenuItem(
                key: Key('activity-action-${item.transactionId}'),
                value: onAction,
                child: Text(actionLabel),
              ),
            ],
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
    final tone = switch (statement.obligationStatus) {
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
        '${statementCycleStatusLabel(l10n, statement.obligationStatus)}'
        '${statement.minimumDueMinor < statement.totalRemainingMinor && statement.totalRemainingMinor > 0 ? '\n${l10n.statementMinimumDue}: ${statement.minimumDue.format()}' : ''}',
      ),
      isThreeLine:
          statement.minimumDueMinor < statement.totalRemainingMinor &&
          statement.totalRemainingMinor > 0,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AppMoneyText(
            money: statement.remaining,
            style: theme.textTheme.titleSmall,
            sign: AppMoneySign.never,
          ),
          if (statement.obligationStatus == StatementCycleStatus.overdue ||
              statement.obligationStatus == StatementCycleStatus.dueToday)
            Text(
              statementCycleStatusLabel(l10n, statement.obligationStatus),
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
    // The trailing slot holds only a short value. A percent fee's basis
    // ("of Highest of recent statements") is a sentence, not an amount: left
    // in the trailing Row it claimed the whole width and squeezed the name
    // and schedule into a one-character-per-line column, so it belongs in
    // the subtitle where it can wrap.
    final amountText = rule.isPercent
        ? l10n.feeRulePercentRate((rule.percentValue ?? 0).toStringAsFixed(2))
        : rule.fixedAmount(currencyCode)!.format();
    final schedule = rule.isActive
        ? rule.nextChargeOn == null
              ? feeFrequencyLabel(l10n, rule.frequency)
              : l10n.feeRuleNextCharge(rule.nextChargeOn!.toIso())
        : l10n.feeRuleInactive;
    final basis = rule.isPercent
        ? ' · ${l10n.feeRuleOfBasis(feePercentBasisLabel(l10n, rule.percentBasis!))}'
        : '';
    return ListTile(
      key: Key('fee-rule-tile-${rule.id}'),
      dense: true,
      title: Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${cardFeeTypeLabel(l10n, rule.feeType)} · '
        '${feeFrequencyLabel(l10n, rule.frequency)}$basis\n$schedule',
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hard-capped so no future label can starve the title column
          // again, whatever the text scale or translation.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: rule.isPercent
                ? Text(
                    amountText,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : ProtectedMoneyText(
                    amountText,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    interactive: false,
                  ),
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

/// What the fee-rule dialog closed with: a saved rule, a detour to create
/// the expense category it has nowhere to go without, or (null) a cancel.
enum _FeeRuleDialogResult { saved, addCategory }

/// Creates or edits one recurring card fee rule. Fixed-amount fees take an
/// exact amount; percent fees take a rate and the balance it applies to.
///
/// Owns its own [ref] rather than taking one from the parent screen: this
/// dialog is shown via [showDialog], which mounts it outside the parent's
/// widget subtree (a separate Overlay entry), so a provider watched through
/// a borrowed ref never rebuilds this dialog when it resolves — the dialog
/// stays stuck on whatever it read on its very first frame. Categories load
/// asynchronously, so that first frame is reliably empty; a category
/// created for real would never appear until something else happened to
/// call setState.
class _FeeRuleDialog extends ConsumerStatefulWidget {
  const _FeeRuleDialog({required this.summary, this.existing});

  final CreditFacilitySummary summary;
  final CardFeeRule? existing;

  @override
  ConsumerState<_FeeRuleDialog> createState() => _FeeRuleDialogState();
}

// Percent bases that make sense for a recurring schedule rule (this dialog
// only creates schedule-triggered rules); transaction-amount and
// remaining-principal/outstanding bases belong to per-transaction and
// early-settlement rules configured elsewhere.
/// The percent bases that make sense for one trigger kind, mirroring what
/// the server-side materializer of that trigger actually reads.
List<FeePercentBasis> _feePercentBasesFor(CardRuleTrigger trigger) =>
    switch (trigger) {
      CardRuleTrigger.schedule => const [
        FeePercentBasis.statementBalance,
        FeePercentBasis.outstandingBalance,
        FeePercentBasis.creditLimit,
        FeePercentBasis.highestStatementDueLookback,
        FeePercentBasis.highestDailyBalanceLookback,
      ],
      CardRuleTrigger.foreignTransaction ||
      CardRuleTrigger.domesticCashAdvance ||
      CardRuleTrigger.internationalCashAdvance ||
      CardRuleTrigger.walletTransaction => const [
        FeePercentBasis.transactionAmount,
      ],
      CardRuleTrigger.latePaymentMissedMinimum => const [
        FeePercentBasis.statementBalance,
        FeePercentBasis.outstandingBalance,
        FeePercentBasis.creditLimit,
      ],
      CardRuleTrigger.overLimitEvent => const [
        FeePercentBasis.outstandingBalance,
        FeePercentBasis.creditLimit,
      ],
      CardRuleTrigger.earlySettlement => const [
        FeePercentBasis.remainingPrincipal,
        FeePercentBasis.remainingOutstanding,
      ],
      CardRuleTrigger.statementInterest => const [
        FeePercentBasis.statementBalance,
        FeePercentBasis.outstandingBalance,
      ],
      CardRuleTrigger.manual => const [FeePercentBasis.outstandingBalance],
    };

const _lookbackBases = [
  FeePercentBasis.highestStatementDueLookback,
  FeePercentBasis.highestDailyBalanceLookback,
];

class _FeeRuleDialogState extends ConsumerState<_FeeRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _percentController;
  late final TextEditingController _minimumController;
  late final TextEditingController _maximumController;
  late final TextEditingController _lookbackController;

  late CardFeeType _feeType;
  late FeeFrequency _frequency;
  late FeePercentBasis _percentBasis;
  late ForeignApplyWhen _applyWhen;
  late bool _isPercent;
  late PlainDate _startsOn;
  late CardRuleState _state;
  String? _categoryId;
  AppFailure? _failure;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  /// A rule's trigger follows its fee type; edits keep the stored one
  /// (identity edits never move a rule between materializers).
  CardRuleTrigger get _trigger =>
      widget.existing?.triggerKind ?? cardFeeTypeTrigger(_feeType);

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
    _minimumController = TextEditingController();
    _maximumController = TextEditingController();
    _lookbackController = TextEditingController();
    _feeType = existing?.feeType ?? CardFeeType.annualMembership;
    _frequency = existing?.frequency ?? FeeFrequency.annually;
    _percentBasis = existing?.percentBasis ?? FeePercentBasis.creditLimit;
    _applyWhen = ForeignApplyWhen.either;
    _isPercent = existing?.isPercent ?? false;
    _startsOn = existing?.startsOn ?? PlainDate.today();
    _state = existing?.state ?? CardRuleState.configured;
    _categoryId = existing?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _percentController.dispose();
    _minimumController.dispose();
    _maximumController.dispose();
    _lookbackController.dispose();
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

  int? _optionalMinorAmount(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return Money.tryParse(
      text,
      currencyCode: widget.summary.currencyCode,
    )?.minor;
  }

  int? get _lookbackCycles => int.tryParse(_lookbackController.text.trim());

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    final currency = widget.summary.currencyCode;
    final calculationType = _state != CardRuleState.configured
        ? CardRuleCalculationType.manual
        : _isPercent
        ? CardRuleCalculationType.percentage
        : CardRuleCalculationType.fixed;
    final trigger = _trigger;
    final draft = CardFeeRuleDraft(
      accountId: widget.summary.accountId,
      name: _nameController.text.trim(),
      feeType: _feeType,
      // Event- and transaction-triggered rules have no schedule of their
      // own: the trigger decides when they charge.
      frequency: trigger == CardRuleTrigger.schedule
          ? _frequency
          : FeeFrequency.perTransaction,
      startsOn: _startsOn,
      categoryId: _categoryId!,
      state: _state,
      triggerKind: trigger,
      applyWhen:
          trigger == CardRuleTrigger.foreignTransaction &&
              _state == CardRuleState.configured
          ? _applyWhen
          : null,
      calculationType: calculationType,
      fixedAmountMinor: calculationType == CardRuleCalculationType.fixed
          ? Money.tryParse(
              _amountController.text,
              currencyCode: currency,
            )!.minor
          : null,
      percentBasisPoints: calculationType == CardRuleCalculationType.percentage
          ? _percentBasisPoints
          : null,
      percentBasis: calculationType == CardRuleCalculationType.percentage
          ? _percentBasis
          : null,
      minimumMinor: calculationType == CardRuleCalculationType.percentage
          ? _optionalMinorAmount(_minimumController)
          : null,
      maximumMinor: calculationType == CardRuleCalculationType.percentage
          ? _optionalMinorAmount(_maximumController)
          : null,
      lookbackCycles:
          calculationType == CardRuleCalculationType.percentage &&
              _lookbackBases.contains(_percentBasis)
          ? _lookbackCycles
          : null,
    );
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .saveFeeRule(draft, ruleId: widget.existing?.id);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) => Navigator.of(context).pop(_FeeRuleDialogResult.saved),
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = widget.summary.currencyCode;
    final categories =
        ref.watch(categoriesProvider(CategoryKind.expense)).value ?? const [];
    if (_categoryId == null && categories.isNotEmpty) {
      _categoryId = categories.first.id;
    }
    final showCalculationFields =
        !_isEdit && _state == CardRuleState.configured;
    // A fee books an expense, so it needs a category to book it under. If
    // the user has none active yet, there is nothing this required field
    // could ever validly hold — offer the way out instead of a permanent
    // "this field is required".
    final needsCategory = categories.isEmpty && _categoryId == null;
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
              if (!_isEdit) ...[
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
                  onChanged: (v) => setState(() {
                    _feeType = v ?? CardFeeType.annualMembership;
                    // Keep the basis inside what the new trigger's
                    // materializer can actually compute.
                    final bases = _feePercentBasesFor(_trigger);
                    if (!bases.contains(_percentBasis)) {
                      _percentBasis = bases.first;
                    }
                  }),
                ),
                if (_trigger != CardRuleTrigger.schedule) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.feeRuleTriggerHint,
                    key: const Key('fee-rule-trigger-hint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
              ],
              AppSelectionField<CardRuleState>(
                key: ValueKey('fee-rule-state-$_state'),
                initialValue: _state,
                decoration: InputDecoration(labelText: l10n.feeRuleState),
                items: [
                  for (final state in CardRuleState.values)
                    // Editing can only mark a rule Unknown or Disabled, or
                    // keep it Configured if it already has a real rate —
                    // giving an unknown rule its first rate happens through
                    // "Add a rule", not by flipping this dropdown.
                    if (!_isEdit ||
                        state != CardRuleState.configured ||
                        widget.existing?.fixedAmountMinor != null ||
                        widget.existing?.percentBasisPoints != null)
                      DropdownMenuItem(
                        value: state,
                        child: Text(cardRuleStateLabel(l10n, state)),
                      ),
                ],
                onChanged: (v) =>
                    setState(() => _state = v ?? CardRuleState.configured),
              ),
              if (_state == CardRuleState.unknown) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.feeRuleUnknownHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              if (showCalculationFields) ...[
                if (_trigger == CardRuleTrigger.foreignTransaction) ...[
                  AppSelectionField<ForeignApplyWhen>(
                    key: ValueKey('fee-rule-apply-when-$_applyWhen'),
                    initialValue: _applyWhen,
                    decoration: InputDecoration(
                      labelText: l10n.feeRuleApplyWhen,
                    ),
                    items: [
                      for (final condition in ForeignApplyWhen.values)
                        DropdownMenuItem(
                          value: condition,
                          child: Text(foreignApplyWhenLabel(l10n, condition)),
                        ),
                    ],
                    onChanged: (v) => setState(
                      () => _applyWhen = v ?? ForeignApplyWhen.either,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SwitchListTile(
                  key: const Key('fee-rule-percent-toggle'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l10n.feeRulePercentToggle),
                  value: _isPercent,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _isPercent = v),
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
                      for (final basis in _feePercentBasesFor(_trigger))
                        DropdownMenuItem(
                          value: basis,
                          child: Text(feePercentBasisLabel(l10n, basis)),
                        ),
                    ],
                    onChanged: (v) => setState(
                      () => _percentBasis =
                          v ?? _feePercentBasesFor(_trigger).first,
                    ),
                  ),
                  if (_lookbackBases.contains(_percentBasis)) ...[
                    const SizedBox(height: 12),
                    AppTextFormField(
                      key: const Key('fee-rule-lookback'),
                      controller: _lookbackController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText:
                            _percentBasis ==
                                FeePercentBasis.highestDailyBalanceLookback
                            ? l10n.feeRuleLookbackMonths
                            : l10n.feeRuleLookbackCycles,
                      ),
                      validator: (v) {
                        final cycles = _lookbackCycles;
                        return cycles == null || cycles < 1 || cycles > 24
                            ? l10n.valFeeLookback
                            : null;
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextFormField(
                          key: const Key('fee-rule-minimum'),
                          controller: _minimumController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
                          decoration: InputDecoration(
                            labelText: l10n.feeRuleMinimum,
                            suffixText: currency,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextFormField(
                          key: const Key('fee-rule-maximum'),
                          controller: _maximumController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: moneyInputFormatters(),
                          decoration: InputDecoration(
                            labelText: l10n.feeRuleMaximum,
                            suffixText: currency,
                          ),
                        ),
                      ),
                    ],
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
                if (_trigger == CardRuleTrigger.schedule)
                  AppSelectionField<FeeFrequency>(
                    key: ValueKey('fee-rule-frequency-$_frequency'),
                    initialValue: _frequency,
                    decoration: InputDecoration(
                      labelText: l10n.feeRuleFrequency,
                    ),
                    items: [
                      for (final frequency in FeeFrequency.values)
                        if (frequency != FeeFrequency.perTransaction)
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
              ],
              if (needsCategory)
                _NoExpenseCategoriesNotice(
                  key: const Key('fee-rule-no-categories'),
                  onAddCategory: () => Navigator.of(
                    context,
                  ).pop(_FeeRuleDialogResult.addCategory),
                )
              else
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
              if (_isEdit) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.feeRuleEditRateHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('fee-rule-submit'),
          onPressed: _busy || needsCategory ? null : _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

/// Shown in place of the category field when the user has no active expense
/// category to book a fee under. Routes to creating one instead of leaving a
/// required field with nothing it could ever validly hold.
class _NoExpenseCategoriesNotice extends StatelessWidget {
  const _NoExpenseCategoriesNotice({super.key, required this.onAddCategory});

  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tone = context.suitColors.warning;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FinanceSuitIcon(FinanceSuitIcons.warning, color: tone.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.feeRuleNoCategoriesTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: tone.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.feeRuleNoCategoriesBody,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tone.text),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const Key('fee-rule-add-category'),
              onPressed: onAddCategory,
              icon: const FinanceSuitIcon(FinanceSuitIcons.addCircle),
              label: Text(l10n.feeRuleAddCategoryAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppliedToRow extends StatelessWidget {
  const _AppliedToRow({required this.allocation});

  final FacilityPaymentAllocationDetail allocation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    var title = allocation.title?.trim() ?? '';
    if (title.isEmpty) {
      title = switch (allocation.componentType) {
        'statement_cycle' => l10n.paymentAppliedToStatement,
        'bnpl_purchase' => l10n.paymentPurchaseComponent,
        _ => l10n.txExpense,
      };
    }
    final subtitle = [
      if (allocation.sequenceNumber != null) '${allocation.sequenceNumber}',
      if (allocation.detailOn != null) allocation.detailOn!.toIso(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          ProtectedMoneyText(
            Money(
              minor: allocation.amountMinor,
              currencyCode: allocation.currencyCode,
            ).format(),
            style: theme.textTheme.bodyMedium,
            interactive: false,
          ),
        ],
      ),
    );
  }
}

/// The month carousel plus the detailed breakdown of whichever month is
/// active. Each month is fetched by its own provider key, so they resolve —
/// and fail — independently.
class _FacilityDueMonthSection extends ConsumerStatefulWidget {
  const _FacilityDueMonthSection({required this.accountId});

  final String accountId;

  @override
  ConsumerState<_FacilityDueMonthSection> createState() =>
      _FacilityDueMonthSectionState();
}

class _FacilityDueMonthSectionState
    extends ConsumerState<_FacilityDueMonthSection> {
  final List<FacilityDueMonth> _months = FacilityDueMonth.payable();
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = _months[_activeIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FacilityDueMonthCarousel(
          accountId: widget.accountId,
          months: _months,
          activeIndex: _activeIndex,
          onMonthChanged: (index) => setState(() => _activeIndex = index),
          onPayMonth: (month) => context.push(
            '${AppRoutes.money}/facilities/pay'
            '?accountId=${widget.accountId}&month=${month.key}',
          ),
        ),
        const SizedBox(height: 8),
        AsyncView<FacilityDueBreakdown>(
          key: ValueKey('facility-due-breakdown-month-${active.key}'),
          value: ref.watch(
            facilityMonthDueBreakdownProvider((
              accountId: widget.accountId,
              monthStartIso: active.key,
            )),
          ),
          onRetry: () => ref.invalidate(facilityMonthDueBreakdownProvider),
          data: (breakdown) => Card(
            key: const Key('facility-due-breakdown-active-month'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DueBreakdownList(
                breakdown: breakdown,
                // The carousel card above already carries the three totals.
                showTotals: false,
                emptyMessage: l10n.dueMonthNoDues,
                // A heavy statement month carries every purchase as a
                // component; unbounded, the single card grew so tall the
                // GPU rendered it as a flat gray block and the page took
                // minutes to scroll. The rest opens in a lazy sheet.
                maxRows: 10,
                onShowAll: () => showDueComponentsSheet(
                  context,
                  title: l10n.dueBreakdownTitle,
                  components: breakdown.components,
                  currencyCode: breakdown.currencyCode,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
