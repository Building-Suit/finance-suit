import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

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
  ) async {
    final result = await ref
        .read(financeRepositoryProvider)
        .setIncomeSourceActive(source.id, active: !source.isActive);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateIncomeAutomation(ref),
      err: (failure) => _showFailure(context, failure),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(incomeSourcesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.incomeSourcesTitle)),
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
          if (items.isEmpty) {
            return EmptyStateView(
              icon: FinanceSuitIcons.payments,
              message: l10n.incomeNoSources,
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final source in items)
                ListTile(
                  leading: const FinanceSuitIcon(FinanceSuitIcons.payments),
                  title: Text(source.name),
                  subtitle: Text(
                    '${source.expectedAmount.format()} · '
                    '${l10n.incomeMonthlyOnDay(source.paymentDay)}'
                    '${source.isActive ? '' : ' · ${l10n.moneyArchivedLabel}'}',
                  ),
                  onTap: () => context.push(
                    '${AppRoutes.settings}/income-sources/edit',
                    extra: source,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') {
                        context.push(
                          '${AppRoutes.settings}/income-sources/edit',
                          extra: source,
                        );
                      } else {
                        _toggle(context, ref, source);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(l10n.commonEdit),
                      ),
                      PopupMenuItem(
                        value: 'active',
                        child: Text(
                          source.isActive
                              ? l10n.moneyArchive
                              : l10n.moneyUnarchive,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
