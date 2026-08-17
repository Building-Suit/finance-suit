import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_header_scroll_scope.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';
import 'package:work_tracker/app/routing/global_add_sheet.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/notifications/notification_feed.dart';
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

/// Authenticated back policy at each primary route boundary.
///
/// Popup routes remain above this scope, so drawers, sheets, dialogs, and the
/// keyboard keep normal first priority. Registering directly with the primary
/// route's [ModalRoute] also ensures Android can deliver the very first Back
/// gesture, before any navigation has occurred.
class AuthenticatedBackScope extends StatefulWidget {
  const AuthenticatedBackScope({
    super.key,
    required this.currentLocation,
    required this.child,
  });

  final String currentLocation;
  final Widget child;

  @override
  State<AuthenticatedBackScope> createState() => _AuthenticatedBackScopeState();
}

class _AuthenticatedBackScopeState extends State<AuthenticatedBackScope> {
  static const _homeRoute = '/home';
  Timer? _exitTimer;
  bool _exitArmed = false;

  void _resetExit() {
    _exitArmed = false;
    _exitTimer?.cancel();
    _exitTimer = null;
  }

  @override
  void didUpdateWidget(AuthenticatedBackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation != widget.currentLocation) _resetExit();
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    if (widget.currentLocation != _homeRoute) {
      _resetExit();
      GoRouter.of(context).go(_homeRoute);
      return;
    }
    if (_exitArmed) {
      _resetExit();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        SystemNavigator.pop();
      }
      return;
    }
    _exitArmed = true;
    AppToast.warning(context, AppLocalizations.of(context).appBackAgainToClose);
    _exitTimer = Timer(const Duration(seconds: 2), _resetExit);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: widget.child,
    );
  }
}

class _AppShellState extends ConsumerState<AppShell> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;
  String get currentLocation => widget.currentLocation;
  final ValueNotifier<bool> _headerIsSolid = ValueNotifier(false);

  static const _solidHeaderThreshold = 12.0;
  static const _floatingHeaderThreshold = 4.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferUpdate());
  }

  @override
  void dispose() {
    _headerIsSolid.dispose();
    super.dispose();
  }

  /// The shell is the sole observer for top-level page scrolling. This keeps
  /// every tab on the same header state contract and prevents offstage tabs
  /// from owning stale header state.
  bool _onPageScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        (notification is! ScrollUpdateNotification &&
            notification is! ScrollEndNotification &&
            notification is! ScrollStartNotification &&
            notification is! ScrollMetricsNotification)) {
      return false;
    }

    final offset = notification.metrics.pixels;
    final shouldBeSolid = _headerIsSolid.value
        ? offset >= _floatingHeaderThreshold
        : offset > _solidHeaderThreshold;
    if (shouldBeSolid != _headerIsSolid.value) {
      _headerIsSolid.value = shouldBeSolid;
    }
    return false;
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
    // One notification subscription per signed-in session, owned by the
    // authenticated shell rather than by any individual screen.
    ref.watch(notificationRealtimeProvider);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      extendBody: true,
      body: FinanceSuitHeaderScrollScope(
        isSolid: _headerIsSolid,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onPageScroll,
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: FinanceSuitNavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          _headerIsSolid.value = false;
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
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
    );
  }
}
