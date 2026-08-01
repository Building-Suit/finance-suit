import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The Finance Suit navigation side menu.
///
/// Behavior, geometry, and motion follow the approved Building Suit shell
/// recipe: the panel occupies about 67.5% of the viewport, opens from the
/// logical start edge, enters with the emphasized curve over 320ms from a
/// small offset-and-fade starting state, and closes with the quick exit
/// curve over 180ms. The scrim fades within the standard 240ms. Reduced
/// motion replaces structural travel with a short fade.
abstract final class FinanceSuitMenu {
  /// Fraction of the viewport width occupied by the open menu panel.
  static const double panelWidthFraction = 0.675;

  /// Emphasized enter: 320ms, cubic-bezier(0.16, 1, 0.3, 1).
  static const Duration openDuration = Duration(milliseconds: 320);
  static const Cubic openCurve = Cubic(0.16, 1, 0.3, 1);

  /// Quick exit: 180ms, cubic-bezier(0.4, 0, 1, 1).
  static const Duration closeDuration = Duration(milliseconds: 180);
  static const Cubic closeCurve = Cubic(0.4, 0, 1, 1);

  /// The scrim completes within the standard 240ms of the 320ms open.
  static const Duration scrimDuration = Duration(milliseconds: 240);

  /// Reduced motion replaces structural travel with a 0-120ms fade.
  static const Duration reducedMotionDuration = Duration(milliseconds: 120);

  /// Initial travel toward the opening edge (within the approved 8-24px).
  static const double entryOffset = 16;

  static _FinanceSuitMenuRoute? _activeRoute;

  /// Whether a menu overlay is currently open (or animating).
  ///
  /// Exposed so tests can await the settled state instead of wall-clock
  /// animation timing, and to guarantee two overlays can never stack. The
  /// flag clears when the route is disposed, so an exit animation still
  /// counts as open and repeated activations share one state machine.
  static bool get isOpen => _activeRoute != null;

  /// Opens the menu over the root navigator and navigates to the selected
  /// destination after the close animation has been initiated.
  static Future<void> open(BuildContext context) async {
    if (isOpen) return;
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final theme = Theme.of(context);
    final scrimBase = theme.colorScheme.scrim;
    // Building Suit modal scrim strength: 48% in light, 64% in dark.
    final scrim = scrimBase.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.64 : 0.48,
    );
    final route = _FinanceSuitMenuRoute(
      reduceMotion: MediaQuery.of(context).disableAnimations,
      scrim: scrim,
      menuLabel: l10n.menuNavigationLabel,
      dismissLabel: l10n.menuCloseTooltip,
      onDisposed: () => _activeRoute = null,
    );
    _activeRoute = route;
    final selectedRoute = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<String>(route);
    if (selectedRoute == null) return;
    if (_currentTopLocation(router) == selectedRoute) return;
    unawaited(router.push(selectedRoute));
  }

  /// The location of the topmost route, including imperative pushes, so an
  /// already-active destination is never pushed twice.
  static String _currentTopLocation(GoRouter router) {
    final configuration = router.routerDelegate.currentConfiguration;
    final top = configuration.matches.lastOrNull;
    if (top is ImperativeRouteMatch) return top.matches.uri.path;
    return configuration.uri.path;
  }
}

class _FinanceSuitMenuRoute extends PopupRoute<String> {
  _FinanceSuitMenuRoute({
    required this.reduceMotion,
    required this.scrim,
    required this.menuLabel,
    required this.dismissLabel,
    required this.onDisposed,
  });

  final bool reduceMotion;
  final Color scrim;
  final String menuLabel;
  final String dismissLabel;
  final VoidCallback onDisposed;

  @override
  void dispose() {
    onDisposed();
    super.dispose();
  }

  @override
  Color? get barrierColor => scrim;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => dismissLabel;

  @override
  Duration get transitionDuration => reduceMotion
      ? FinanceSuitMenu.reducedMotionDuration
      : FinanceSuitMenu.openDuration;

  @override
  Duration get reverseTransitionDuration => reduceMotion
      ? FinanceSuitMenu.reducedMotionDuration
      : FinanceSuitMenu.closeDuration;

  @override
  Widget buildModalBarrier() {
    // The scrim must settle within the standard duration (240ms of the
    // 320ms open) instead of trailing the panel.
    final scrimEnd = reduceMotion
        ? 1.0
        : FinanceSuitMenu.scrimDuration.inMilliseconds /
              FinanceSuitMenu.openDuration.inMilliseconds;
    final color = animation!.drive(
      ColorTween(
        begin: scrim.withValues(alpha: 0),
        end: scrim,
      ).chain(CurveTween(curve: Interval(0, scrimEnd))),
    );
    return AnimatedModalBarrier(
      color: color,
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: menuLabel,
      child: const _FinanceSuitMenuPanel(),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: FinanceSuitMenu.openCurve,
      reverseCurve: FinanceSuitMenu.closeCurve,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, panel) {
        final progress = curved.value.clamp(0.0, 1.0);
        final towardStartEdge = Directionality.of(context) == TextDirection.rtl
            ? 1.0
            : -1.0;
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(
              (1 - progress) * FinanceSuitMenu.entryOffset * towardStartEdge,
              0,
            ),
            child: panel,
          ),
        );
      },
      child: child,
    );
  }
}

class _FinanceSuitMenuPanel extends StatelessWidget {
  const _FinanceSuitMenuPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final groups = [
      (
        heading: l10n.menuGroupGeneral,
        items: [
          (
            icon: FinanceSuitIcons.settings,
            label: l10n.tabSettings,
            route: AppRoutes.settings,
          ),
          (
            icon: FinanceSuitIcons.history,
            label: l10n.historyTitle,
            route: AppRoutes.history,
          ),
        ],
      ),
      (
        heading: l10n.menuGroupAutomation,
        items: [
          (
            icon: FinanceSuitIcons.tune,
            label: l10n.incomeAutomationCenter,
            route: '${AppRoutes.settings}/income-sources',
          ),
        ],
      ),
      (
        heading: l10n.tabWork,
        items: [
          (
            icon: FinanceSuitIcons.requestQuote,
            label: l10n.salPeriodsTitle,
            route: '${AppRoutes.work}/periods',
          ),
          (
            icon: FinanceSuitIcons.event,
            label: l10n.workHolidays,
            route: '${AppRoutes.work}/holidays',
          ),
        ],
      ),
      (
        heading: l10n.tabMoney,
        items: [
          (
            icon: FinanceSuitIcons.label,
            label: l10n.menuCategories,
            route: '${AppRoutes.money}/categories',
          ),
          (
            icon: FinanceSuitIcons.bolt,
            label: l10n.macrosTitle,
            route: '${AppRoutes.money}/macros',
          ),
        ],
      ),
    ];

    final firstRoute = groups.first.items.first.route;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: FinanceSuitMenu.panelWidthFraction,
        heightFactor: 1,
        child: Material(
          key: const Key('finance-suit-menu-panel'),
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: ListView(
              key: const Key('finance-suit-menu-list'),
              // Keep the last destinations reachable above an open keyboard.
              padding: EdgeInsets.only(
                bottom: 8 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const FinanceSuitMark(size: 28, semanticLabel: null),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          FinanceSuitBrand.name,
                          style: textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      12,
                      16,
                      0,
                    ),
                    child: Text(group.heading, style: textTheme.labelLarge),
                  ),
                  for (final item in group.items)
                    ListTile(
                      key: Key('menu-item-${item.route}'),
                      autofocus: item.route == firstRoute,
                      visualDensity: VisualDensity.compact,
                      leading: FinanceSuitIcon(item.icon),
                      title: Text(item.label),
                      onTap: () => Navigator.of(context).pop(item.route),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
