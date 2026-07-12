import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Bottom-navigation shell hosting the five main tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _settingsBranchIndex = 4;

  Future<void> _openAddSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final route = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        final options = <(IconData, String, String)>[
          for (final kind in const [
            TransactionKind.expense,
            TransactionKind.allowanceGiven,
            TransactionKind.customIncome,
            TransactionKind.freelanceIncome,
          ])
            (
              transactionKindIcon(kind),
              transactionKindLabel(l10n, kind),
              '${AppRoutes.money}/tx/new?kind=${kind.dbValue}',
            ),
          (
            transactionKindIcon(TransactionKind.transfer),
            transactionKindLabel(l10n, TransactionKind.transfer),
            '${AppRoutes.money}/transfer',
          ),
          (
            Icons.work_outline,
            l10n.workAddEntry,
            '${AppRoutes.work}/entry/new',
          ),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (icon, label, route) in options)
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () => Navigator.of(sheetContext).pop(route),
                ),
            ],
          ),
        );
      },
    );
    if (route == null || !context.mounted) return;
    await context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeInvalidationProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      floatingActionButton: navigationShell.currentIndex == _settingsBranchIndex
          ? null
          : FloatingActionButton(
              onPressed: () => _openAddSheet(context),
              tooltip: l10n.commonAdd,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.work_outline),
            selectedIcon: const Icon(Icons.work),
            label: l10n.tabWork,
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l10n.tabMoney,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: l10n.tabReports,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.tabSettings,
          ),
        ],
      ),
    );
  }
}
