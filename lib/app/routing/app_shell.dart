import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';
import 'package:work_tracker/app/routing/global_add_sheet.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/core/updates/app_update_service.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
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
class AppShell extends ConsumerStatefulWidget {
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

  /// The update drawer shows once per app open, not on every shell rebuild.
  @visibleForTesting
  static bool updatePromptShown = false;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;
  String get currentLocation => widget.currentLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferUpdate());
  }

  Future<void> _maybeOfferUpdate() async {
    if (AppShell.updatePromptShown || !mounted) return;
    AppShell.updatePromptShown = true;
    final service = ref.read(appUpdateServiceProvider);
    final update = await service.checkForUpdate();
    if (update == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 16),
          child: Column(
            key: const Key('app-update-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.updateAvailableTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(l10n.updateAvailableBody),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('app-update-later'),
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text(l10n.updateLater),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('app-update-now'),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(l10n.updateNow),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true) {
      await service.startUpdate();
    }
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
              salaryAdjustmentRoute: AppShell.salaryAdjustmentRoute(
                currentLocation,
              ),
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
        AppToast.success(context, l10n.macroApplied(count));
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeInvalidationProvider);
    final l10n = AppLocalizations.of(context);
    return FinanceSuitMenuPagePlane(
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
    );
  }
}
