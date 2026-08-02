import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/income_automation_actions.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Manage recurring income schedules, approvals, and account splits.
class IncomeSourcesScreen extends ConsumerWidget {
  const IncomeSourcesScreen({super.key});

  void _showFailure(BuildContext context, AppFailure failure) {
    AppToast.error(context, failureMessage(context, failure));
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    IncomeSource source,
    bool active,
  ) async {
    final result = await ref
        .read(financeRepositoryProvider)
        .setIncomeSourceActive(source.id, active: active);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateIncomeAutomation(ref),
      err: (failure) => _showFailure(context, failure),
    );
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    PendingIncome pending,
  ) async {
    final accepted = await acceptPendingIncome(context, ref, pending);
    if (context.mounted && accepted) {
      AppToast.success(
        context,
        AppLocalizations.of(context).incomeAcceptedMessage,
      );
    }
  }

  Future<void> _skip(
    BuildContext context,
    WidgetRef ref,
    PendingIncome pending,
  ) async {
    final skipped = await skipPendingIncome(context, ref, pending);
    if (context.mounted && skipped) {
      AppToast.success(
        context,
        AppLocalizations.of(context).incomeSkippedMessage,
      );
    }
  }

  Future<void> _snooze(
    BuildContext context,
    WidgetRef ref,
    PendingIncome pending,
  ) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(financeRepositoryProvider)
        .snoozeIncomeOccurrence(
          occurrenceId: pending.occurrence.id,
          snoozedUntil: DateTime.now().toUtc().add(const Duration(hours: 24)),
        );
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        invalidateIncomeAutomation(ref);
        AppToast.success(context, l10n.incomeRemindLater);
      },
      err: (_) => AppToast.error(context, l10n.incomeSnoozeFailed),
    );
  }

  String _kindLabel(AppLocalizations l10n, IncomeSourceKind kind) =>
      switch (kind) {
        IncomeSourceKind.salary => l10n.incomeKindSalary,
        IncomeSourceKind.allowance => l10n.incomeKindAllowance,
        IncomeSourceKind.freelance => l10n.incomeKindFreelance,
        IncomeSourceKind.other => l10n.incomeKindOther,
      };

  String _percentage(int basisPoints) =>
      (basisPoints / 100).toStringAsFixed(basisPoints % 100 == 0 ? 0 : 2);

  bool _hasOnlyOriginalPercentages(IncomeSource source) =>
      source.allocations.every(
        (allocation) =>
            allocation.method == IncomeAllocationMethod.percentage &&
            allocation.calculationBasis ==
                IncomeAllocationCalculationBasis.original,
      );

  Widget _sourceCard(
    BuildContext context,
    WidgetRef ref,
    IncomeSource source,
    Map<String, String> accountNames,
  ) {
    final l10n = AppLocalizations.of(context);
    final status = source.isActive ? context.suitColors.success : null;
    final primaryName = accountNames[source.primaryAccountId] ?? '—';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const FinanceSuitIcon(FinanceSuitIcons.payments),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${_kindLabel(l10n, source.kind)} · '
                        '${source.expectedAmount.format()}',
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: FinanceSuitIcon(
                    source.isActive
                        ? FinanceSuitIcons.checkCircle
                        : FinanceSuitIcons.pauseCircle,
                    color: status?.icon ?? context.suitColors.textMuted,
                  ),
                  backgroundColor:
                      status?.background ?? context.suitColors.surfaceMuted,
                  side: BorderSide(
                    color: status?.border ?? context.suitColors.borderSubtle,
                  ),
                  label: Text(
                    source.isActive ? l10n.incomeActive : l10n.incomePaused,
                    style: TextStyle(
                      color: status?.text ?? context.suitColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.incomeMonthlyOnDay(source.paymentDay)),
            Text(l10n.incomeDepositAccount(primaryName)),
            for (final allocation in source.allocations)
              Text(
                allocation.method == IncomeAllocationMethod.percentage
                    ? l10n.incomeSplitAccount(
                        _percentage(allocation.percentageBasisPoints ?? 0),
                        accountNames[allocation.destinationAccountId] ?? '-',
                      )
                    : l10n.incomeSplitFixedAccount(
                        Money(
                          minor: allocation.fixedAmountMinor ?? 0,
                          currencyCode: source.currencyCode,
                        ).format(
                          locale: Localizations.localeOf(
                            context,
                          ).toLanguageTag(),
                        ),
                        accountNames[allocation.destinationAccountId] ?? '-',
                      ),
              ),
            if (source.allocations.isNotEmpty &&
                _hasOnlyOriginalPercentages(source))
              Text(
                l10n.incomeRemainderSplit(
                  _percentage(source.remainderBasisPoints),
                  primaryName,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => context.push(
                    '${AppRoutes.settings}/income-sources/edit',
                    extra: source,
                  ),
                  child: Text(l10n.commonEdit),
                ),
                FilledButton.tonal(
                  onPressed: () =>
                      _toggle(context, ref, source, !source.isActive),
                  child: Text(
                    source.isActive ? l10n.incomePause : l10n.incomeResume,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(
    BuildContext context,
    WidgetRef ref,
    PendingIncome pending,
  ) {
    final l10n = AppLocalizations.of(context);
    final warning = context.suitColors.warning;
    final estimate = pending.source.kind == IncomeSourceKind.salary
        ? ref.watch(
            pendingSalaryEstimateProvider((
              occurrenceId: pending.occurrence.id,
              scheduledOn: pending.occurrence.scheduledOn,
            )),
          )
        : null;
    final salaryEstimate = estimate?.value;
    final amountMinor =
        salaryEstimate?.totalMinor ?? pending.occurrence.expectedAmountMinor;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  pending.source.name,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppMoneyText(
                  money: Money(
                    minor: amountMinor,
                    currencyCode: pending.source.currencyCode,
                  ),
                  style: textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FinanceSuitIcon(FinanceSuitIcons.moreTime, color: warning.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending.isDueOn(PlainDate.today())
                        ? l10n.incomeDue(pending.occurrence.scheduledOn.toIso())
                        : l10n.incomeUpcoming(
                            pending.occurrence.scheduledOn.toIso(),
                          ),
                    style: TextStyle(color: warning.text),
                  ),
                ),
              ],
            ),
            if (salaryEstimate != null) ...[
              const SizedBox(height: 8),
              _SalaryPendingSummary(estimate: salaryEstimate),
            ],
            if (estimate?.hasError == true) ...[
              const SizedBox(height: 8),
              Text(l10n.homePartialDataError, style: textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => _skip(context, ref, pending),
                  child: Text(l10n.incomeSkip),
                ),
                TextButton(
                  onPressed: () => _snooze(context, ref, pending),
                  child: Text(l10n.incomeLater),
                ),
                FilledButton(
                  onPressed: () => _accept(context, ref, pending),
                  child: Text(l10n.incomeAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: context.suitColors.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: context.suitColors.borderSubtle),
            ),
            child: Text('$count'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(incomeSourcesProvider);
    final pending = ref.watch(pendingIncomeProvider);
    final accounts = ref.watch(allAccountBalancesProvider);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.incomeSourcesTitle),
      body: FinanceSuitFocusedBody(
        title: l10n.incomeSourcesTitle,
        child: AsyncView<List<IncomeSource>>(
          value: sources,
          onRetry: () => ref.invalidate(incomeSourcesProvider),
          data: (items) {
            final pendingItems = pending.value ?? const <PendingIncome>[];
            final accountNames = {
              for (final account in accounts.value ?? const <AccountBalance>[])
                account.accountId: account.name,
            };
            final activeSources = items
                .where((source) => source.isActive)
                .toList(growable: false);
            final pausedSources = items
                .where((source) => !source.isActive)
                .toList(growable: false);
            return RefreshIndicator(
              onRefresh: () async {
                invalidateIncomeAutomation(ref);
                ref.invalidate(allAccountBalancesProvider);
                await ref.read(incomeSourcesProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FinanceSuitIcon(FinanceSuitIcons.info),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.incomeSourcesSubtitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(l10n.incomeAutomationOverview),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => context.push(
                              '${AppRoutes.settings}/income-sources/new',
                            ),
                            icon: const FinanceSuitIcon(
                              FinanceSuitIcons.addCircle,
                            ),
                            label: Text(l10n.addAutomation),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _sectionHeader(
                    context,
                    title: l10n.incomePendingTitle,
                    count: pendingItems.length,
                  ),
                  if (pending.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (pending.hasError)
                    Text(
                      failureMessage(
                        context,
                        pending.error is AppFailure
                            ? pending.error! as AppFailure
                            : const UnknownFailure(
                                debugDetails: 'pending income failed',
                              ),
                      ),
                    )
                  else if (pendingItems.isEmpty)
                    Text(l10n.incomeNoPending)
                  else
                    for (final item in pendingItems)
                      _pendingCard(context, ref, item),
                  if (items.isEmpty)
                    EmptyStateView(
                      icon: FinanceSuitIcons.payments,
                      message: l10n.incomeAddAutomationEmpty,
                    )
                  else ...[
                    if (activeSources.isNotEmpty) ...[
                      _sectionHeader(
                        context,
                        title: l10n.incomeActiveAutomations,
                        count: activeSources.length,
                      ),
                      for (final source in activeSources)
                        _sourceCard(context, ref, source, accountNames),
                    ],
                    if (pausedSources.isNotEmpty) ...[
                      _sectionHeader(
                        context,
                        title: l10n.incomePausedAutomations,
                        count: pausedSources.length,
                      ),
                      for (final source in pausedSources)
                        _sourceCard(context, ref, source, accountNames),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SalaryPendingSummary extends StatelessWidget {
  const _SalaryPendingSummary({required this.estimate});

  final SalaryEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <({String label, String value, int money})>[
      (
        label: l10n.salaryBaseAmount,
        value: '',
        money: estimate.baseSalaryMinor,
      ),
      (
        label: l10n.salaryExtraDays,
        value: (estimate.extraDayUnitsHundredths / 100).toStringAsFixed(2),
        money: estimate.extraDayAmountMinor,
      ),
      (
        label: l10n.salaryOvertimeDuration,
        value: l10n.durationHoursMinutes(
          estimate.overtimeMinutes ~/ 60,
          estimate.overtimeMinutes % 60,
        ),
        money: estimate.overtimeAmountMinor,
      ),
      if (estimate.holidayCount != 0)
        (
          label: l10n.salaryHolidayWorked,
          value: estimate.holidayCount.toString(),
          money: estimate.holidayAmountMinor,
        ),
      if (estimate.bonusesMinor != 0)
        (label: l10n.salAdjBonus, value: '', money: estimate.bonusesMinor),
      if (estimate.deductionsMinor != 0)
        (
          label: l10n.salAdjDeduction,
          value: '',
          money: -estimate.deductionsMinor,
        ),
      (label: l10n.salaryEstimatedTotal, value: '', money: estimate.totalMinor),
    ];
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  row.value.isEmpty ? row.label : '${row.label}: ${row.value}',
                  style: textTheme.bodySmall,
                ),
                AppMoneyText(
                  money: Money(
                    minor: row.money,
                    currencyCode: estimate.currencyCode,
                  ),
                  sign: row.money < 0
                      ? AppMoneySign.automatic
                      : AppMoneySign.never,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
