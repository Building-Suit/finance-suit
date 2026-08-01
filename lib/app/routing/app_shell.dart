import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';
import 'package:work_tracker/app/routing/global_add_sheet.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Bottom-navigation shell hosting the four primary destinations plus the
/// centered global Add action: Home | Work | + | Money | Reports.
///
/// Shell-chrome visibility is a structural routing policy, not a location
/// check: only the four primary branch roots live inside this shell, while
/// every other authenticated route is declared on the root navigator in
/// `app_router.dart` and therefore covers the shell entirely. No route can
/// show the bottom navigation unless it is one of the four primary roots.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.currentLocation,
  });

  final StatefulNavigationShell navigationShell;
  final String currentLocation;

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
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: AnimatedBuilder(
        animation: FinanceSuitMenu.shellProgress,
        builder: (context, child) {
          final progress = FinanceSuitMenu.shellProgress.value;
          final width = MediaQuery.sizeOf(context).width;
          final direction = Directionality.of(context) == TextDirection.rtl
              ? -1.0
              : 1.0;
          return Transform.translate(
            offset: Offset(width * 0.60 * progress * direction, 0),
            child: Transform.scale(
              scale: 1 - (0.15 * progress),
              child: DecoratedBox(
                key: const Key('finance-suit-shell-surface'),
                decoration: BoxDecoration(
                  boxShadow: [
                    if (progress > 0)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.32 * progress),
                        blurRadius: 50 * progress,
                        offset: Offset(-20 * direction * progress, 0),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40 * progress),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: Scaffold(
          body: navigationShell,
          bottomNavigationBar: FinanceSuitNavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
            onAddPressed: () => _openAddSheet(context, ref),
            addLabel: l10n.globalAddLabel,
            destinations: [
              FinanceSuitNavDestination(
                icon: FinanceSuitIcons.home,
                label: l10n.tabHome,
              ),
              FinanceSuitNavDestination(
                icon: FinanceSuitIcons.work,
                label: l10n.tabWork,
              ),
              FinanceSuitNavDestination(
                icon: FinanceSuitIcons.accountBalanceWallet,
                label: l10n.tabMoney,
              ),
              FinanceSuitNavDestination(
                icon: FinanceSuitIcons.barChart,
                label: l10n.tabReports,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
