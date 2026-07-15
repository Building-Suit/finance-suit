import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/global_add_sheet.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Bottom-navigation shell hosting the five main tabs.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.currentLocation,
  });

  final StatefulNavigationShell navigationShell;
  final String currentLocation;

  static const _settingsBranchIndex = 4;
  static const _formLocations = {
    '/work/entry/new',
    '/work/entry/edit',
    '/work/holidays/new',
    '/work/adjustments/new',
    '/money/tx/new',
    '/money/tx/edit',
    '/money/transfer',
    '/money/categories/new',
    '/money/macros/new',
    '/money/macros/edit',
    '/money/held/new',
    '/money/held/edit',
  };

  static bool shouldShowGlobalAdd({
    required int branchIndex,
    required String location,
  }) {
    if (branchIndex == _settingsBranchIndex) return false;
    if (location.startsWith('/money/accounts/')) return false;
    return !_formLocations.contains(location);
  }

  static String salaryAdjustmentRoute(String location) {
    const periodPrefix = '/work/periods/';
    if (!location.startsWith(periodPrefix)) return '/work/adjustments/new';
    final periodId = location.substring(periodPrefix.length);
    if (periodId.isEmpty || periodId.contains('/')) {
      return '/work/adjustments/new';
    }
    return '/work/adjustments/new?periodId=${Uri.encodeQueryComponent(periodId)}';
  }

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final selection = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Consumer(
            builder: (context, ref, _) => GlobalAddSheet(
              macros: ref.watch(macrosProvider),
              onRetryMacros: () => ref.invalidate(macrosProvider),
              salaryAdjustmentRoute: salaryAdjustmentRoute(currentLocation),
            ),
          ),
        );
      },
    );
    if (selection == null || !context.mounted) return;
    if (selection is String) {
      await context.push(selection);
      return;
    }
    if (selection is! MacroRunSelection) return;
    final run = selection;
    final result = await ref
        .read(financeRepositoryProvider)
        .applyMacro(
          macroId: run.macroId,
          occurredOn: PlainDate.today(),
          reverse: run.reverse,
        );
    if (!context.mounted) return;
    result.when(
      ok: (count) {
        invalidateFinanceData(ref);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.macroApplied(count))));
      },
      err: (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure)))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeInvalidationProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      floatingActionButton:
          shouldShowGlobalAdd(
            branchIndex: navigationShell.currentIndex,
            location: currentLocation,
          )
          ? FloatingActionButton(
              onPressed: () => _openAddSheet(context, ref),
              tooltip: l10n.commonAdd,
              child: const Icon(Icons.add),
            )
          : null,
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
