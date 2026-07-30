import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/income_automation_actions.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The control center for recurring income schedules, approvals, and splits.
class IncomeSourcesScreen extends ConsumerWidget {
  const IncomeSourcesScreen({super.key});

  void _showFailure(BuildContext context, AppFailure failure) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
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

  String _kindLabel(AppLocalizations l10n, IncomeSourceKind kind) =>
      switch (kind) {
        IncomeSourceKind.salary => l10n.incomeKindSalary,
        IncomeSourceKind.allowance => l10n.incomeKindAllowance,
        IncomeSourceKind.freelance => l10n.incomeKindFreelance,
        IncomeSourceKind.other => l10n.incomeKindOther,
      };

  String _percentage(int basisPoints) =>
      (basisPoints / 100).toStringAsFixed(basisPoints % 100 == 0 ? 0 : 2);

  Widget _sourceCard(
    BuildContext context,
    WidgetRef ref,
    IncomeSource source,
    Map<String, String> accountNames,
  ) {
    final l10n = AppLocalizations.of(context);
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
                  label: Text(
                    source.isActive ? l10n.incomeActive : l10n.incomePaused,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.incomeMonthlyOnDay(source.paymentDay)),
            Text(l10n.incomeDepositAccount(primaryName)),
            for (final allocation in source.allocations)
              Text(
                l10n.incomeSplitAccount(
                  _percentage(allocation.percentageBasisPoints),
                  accountNames[allocation.destinationAccountId] ?? '—',
                ),
              ),
            if (source.allocations.isNotEmpty)
              Text(
                l10n.incomeRemainderSplit(
                  _percentage(source.remainderBasisPoints),
                  primaryName,
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => context.push(
                    '${AppRoutes.settings}/income-sources/edit',
                    extra: source,
                  ),
                  child: Text(l10n.commonEdit),
                ),
                const SizedBox(width: 8),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pending.source.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              pending.isDueOn(PlainDate.today())
                  ? l10n.incomeDue(pending.occurrence.scheduledOn.toIso())
                  : l10n.incomeUpcoming(pending.occurrence.scheduledOn.toIso()),
            ),
            Text(pending.source.expectedAmount.format()),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => skipPendingIncome(context, ref, pending),
                  child: Text(l10n.incomeSkip),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => acceptPendingIncome(context, ref, pending),
                  child: Text(l10n.incomeAccept),
                ),
              ],
            ),
          ],
        ),
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
      appBar: AppBar(title: Text(l10n.incomeAutomationCenter)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('${AppRoutes.settings}/income-sources/new'),
        icon: const FinanceSuitIcon(FinanceSuitIcons.add),
        label: Text(l10n.incomeAddSource),
      ),
      body: AsyncView<List<IncomeSource>>(
        value: sources,
        onRetry: () => ref.invalidate(incomeSourcesProvider),
        data: (items) {
          final pendingItems = pending.value ?? const <PendingIncome>[];
          final accountNames = {
            for (final account in accounts.value ?? const <AccountBalance>[])
              account.accountId: account.name,
          };
          final activeCount = items.where((source) => source.isActive).length;
          return RefreshIndicator(
            onRefresh: () async {
              invalidateIncomeAutomation(ref);
              ref.invalidate(allAccountBalancesProvider);
              await ref.read(incomeSourcesProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.incomeAutomationOverview,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text(l10n.incomeActiveCount(activeCount)),
                            ),
                            Chip(
                              label: Text(
                                l10n.incomePausedCount(
                                  items.length - activeCount,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(
                                l10n.incomePendingCount(pendingItems.length),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.incomePendingTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 20),
                Text(
                  l10n.incomeSourcesTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  EmptyStateView(
                    icon: FinanceSuitIcons.payments,
                    message: l10n.incomeNoSources,
                  )
                else
                  for (final source in items)
                    _sourceCard(context, ref, source, accountNames),
              ],
            ),
          );
        },
      ),
    );
  }
}
