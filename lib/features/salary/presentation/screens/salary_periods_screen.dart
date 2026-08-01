import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/salary/data/salary_repository.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/salary/presentation/widgets/estimate_breakdown.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Current-period estimate summary plus the history of salary periods.
class SalaryPeriodsScreen extends ConsumerWidget {
  const SalaryPeriodsScreen({super.key});

  Future<void> _openCurrentPeriod(BuildContext context, WidgetRef ref) async {
    // A failing bounds provider must surface as a message, not an
    // unhandled exception that leaves the tap without feedback.
    final PeriodBounds bounds;
    try {
      bounds = await ref.read(currentPeriodBoundsProvider.future);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failureMessage(
                context,
                error is AppFailure ? error : const UnknownFailure(),
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final result = await ref
        .read(salaryRepositoryProvider)
        .ensurePeriod(bounds);
    if (!context.mounted) return;
    result.when(
      ok: (period) {
        ref.invalidate(salaryPeriodsProvider);
        context.push('${AppRoutes.work}/periods/${period.id}');
      },
      err: (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure)))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final estimateAsync = ref.watch(currentEstimateProvider);
    final periodsAsync = ref.watch(salaryPeriodsProvider);

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.salPeriodsTitle),
      body: FinanceSuitFocusedBody(
        title: l10n.salPeriodsTitle,
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(currentEstimateProvider)
              ..invalidate(salaryPeriodsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              switch (estimateAsync) {
                AsyncValue(:final value?) => Card(
                  child: ListTile(
                    leading: const FinanceSuitIcon(FinanceSuitIcons.trendingUp),
                    title: Text(
                      l10n.salEstimatedFor(
                        DateFormat.yMMMM(
                          locale,
                        ).format(value.expectedPaymentDate.toDateTime()),
                      ),
                    ),
                    subtitle: Text(
                      '${l10n.salBasedOn(value.periodStart.toIso(), value.periodEnd.toIso())}\n'
                      '${l10n.salExpectedPayment(value.expectedPaymentDate.toIso())}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      Money(
                        minor: value.totalMinor,
                        currencyCode: value.currencyCode,
                      ).format(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => _openCurrentPeriod(context, ref),
                  ),
                ),
                AsyncValue(hasError: true, :final error) => ErrorRetryView(
                  failure: error is AppFailure ? error : UnknownFailure(),
                  onRetry: () => ref.invalidate(currentEstimateProvider),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
              const SizedBox(height: 16),
              AsyncView(
                value: periodsAsync,
                onRetry: () => ref.invalidate(salaryPeriodsProvider),
                loading: const SizedBox.shrink(),
                data: (periods) {
                  if (periods.isEmpty) {
                    return EmptyStateView(
                      icon: FinanceSuitIcons.history,
                      message: l10n.salNoPeriods,
                    );
                  }
                  return Column(
                    children: [
                      for (final period in periods) _PeriodTile(period: period),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodTile extends ConsumerWidget {
  const _PeriodTile({required this.period});

  final SalaryPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currency = period.snapshot?['currency_code'] as String? ?? 'EGP';
    final amountMinor = period.isPaid
        ? period.actualAmountMinor
        : period.snapshotTotalMinor;
    return ListTile(
      leading: FinanceSuitIcon(
        period.isPaid
            ? FinanceSuitIcons.checkCircle
            : period.isFinalized
            ? FinanceSuitIcons.lock
            : FinanceSuitIcons.pending,
      ),
      title: Text(
        '${period.periodStart.toIso()} → ${period.periodEnd.toIso()}',
      ),
      subtitle: Text(
        '${periodStatusLabel(l10n, period.status)} · '
        '${l10n.salExpectedPayment(period.expectedPaymentDate.toIso())}',
      ),
      trailing: amountMinor == null
          ? null
          : Text(
              Money(minor: amountMinor, currencyCode: currency).format(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
      onTap: () => context.push('${AppRoutes.work}/periods/${period.id}'),
    );
  }
}
