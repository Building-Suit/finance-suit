import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/notifications/notification_center.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
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

  /// Building Suit page-plane adapter: while the menu is open the current
  /// page translates 60% away from the opening edge, scales to 0.85, and
  /// gains 40px corners with a lateral shadow, moving as one coherent
  /// plane on the standard curve.
  static const double pagePlaneTravel = 0.6;
  static const double pagePlaneScale = 0.85;
  static const double pagePlaneRadius = 40;
  static const Cubic standardCurve = Cubic(0.2, 0, 0, 1);

  /// Progress of the page-plane transform (0 = resting, 1 = menu open).
  ///
  /// Driven by the menu route's animation; stays at 0 under reduced motion
  /// so structural travel is replaced by the panel's short fade only.
  static final ValueNotifier<double> pageProgress = ValueNotifier<double>(0);

  /// Sentinel result meaning the user chose Logout from the menu.
  static const String _logoutResult = '::logout';

  static _FinanceSuitMenuRoute? _activeRoute;

  /// Whether a menu overlay is currently open (or animating).
  ///
  /// Exposed so tests can await the settled state instead of wall-clock
  /// animation timing, and to guarantee two overlays can never stack. The
  /// flag clears when the route is disposed, so an exit animation still
  /// counts as open and repeated activations share one state machine.
  static bool get isOpen => _activeRoute != null;

  /// Dismisses the current menu route and waits for its exit animation.
  /// App-level drawers use this to remain mutually exclusive.
  static Future<void> close() async {
    final route = _activeRoute;
    if (route == null) return;
    route.navigator?.pop();
    await route.completed;
  }

  /// Opens the menu over the root navigator and navigates to the selected
  /// destination after the close animation has been initiated.
  static Future<void> open(BuildContext context) async {
    if (isOpen) return;
    if (NotificationCenter.isOpen) await NotificationCenter.close();
    if (!context.mounted) return;
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
    if (selectedRoute == _logoutResult) {
      if (context.mounted) await _confirmLogout(context);
      return;
    }
    if (_currentTopLocation(router) == selectedRoute) return;
    unawaited(router.push(selectedRoute));
  }

  /// Same confirmation flow as the Settings sign-out entry.
  static Future<void> _confirmLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.setSignOutConfirmTitle),
        content: Text(l10n.setSignOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.authLogout),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authActionProvider.notifier).signOut();
    }
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

  CurvedAnimation? _pagePlaneCurve;

  @override
  TickerFuture didPush() {
    if (!reduceMotion) {
      // The current page moves once as a coherent plane on the standard
      // curve while the panel enters/exits on its own curves.
      _pagePlaneCurve = CurvedAnimation(
        parent: animation!,
        curve: FinanceSuitMenu.standardCurve,
        reverseCurve: FinanceSuitMenu.standardCurve.flipped,
      );
      animation!.addListener(_syncPagePlane);
    }
    return super.didPush();
  }

  void _syncPagePlane() {
    final curve = _pagePlaneCurve;
    if (curve != null) {
      FinanceSuitMenu.pageProgress.value = curve.value.clamp(0.0, 1.0);
    }
  }

  @override
  void dispose() {
    animation?.removeListener(_syncPagePlane);
    _pagePlaneCurve?.dispose();
    FinanceSuitMenu.pageProgress.value = 0;
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final semanticColors = theme.extension<FinanceSuitSemanticColors>()!;
    // The transparent menu is always drawn over the darkened page scrim, so
    // its foreground must use the on-overlay roles even in light mode.
    final foreground = semanticColors.onBrandSurface;
    final mutedForeground = foreground.withValues(alpha: 0.76);
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
          (
            icon: FinanceSuitIcons.eventRepeat,
            label: l10n.recurringCenterTitle,
            route: '${AppRoutes.settings}/recurring',
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
          // Keep the menu content interactive without painting a separate
          // surface behind it. The route's scrim remains responsible for
          // separating the menu from the page underneath.
          type: MaterialType.transparency,
          child: SafeArea(
            // Compact mode: destination rows sit on the accessible 48dp
            // floor instead of inheriting the theme's taller tile padding.
            child: ListTileTheme.merge(
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              textColor: foreground,
              iconColor: mutedForeground,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      key: const Key('finance-suit-menu-list'),
                      // Keep the last destinations reachable above an open
                      // keyboard.
                      padding: EdgeInsets.only(
                        bottom: 8 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            16,
                            12,
                            16,
                            4,
                          ),
                          child: Row(
                            children: [
                              const FinanceSuitMark(
                                size: 28,
                                semanticLabel: null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  FinanceSuitBrand.name,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: foreground,
                                  ),
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
                            child: Text(
                              group.heading,
                              style: textTheme.labelLarge?.copyWith(
                                color: foreground,
                              ),
                            ),
                          ),
                          for (final item in group.items)
                            ListTile(
                              key: Key('menu-item-${item.route}'),
                              autofocus: item.route == firstRoute,
                              visualDensity: VisualDensity.compact,
                              leading: FinanceSuitIcon(item.icon),
                              title: Text(item.label),
                              onTap: () =>
                                  Navigator.of(context).pop(item.route),
                            ),
                        ],
                      ],
                    ),
                  ),
                  _MenuLogoutSeparator(color: mutedForeground),
                  ListTile(
                    key: const Key('menu-item-logout'),
                    iconColor: theme.colorScheme.error,
                    textColor: theme.colorScheme.error,
                    leading: const FinanceSuitIcon(FinanceSuitIcons.logout),
                    title: Text(l10n.authLogout),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(FinanceSuitMenu._logoutResult),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuLogoutSeparator extends StatelessWidget {
  const _MenuLogoutSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('finance-suit-menu-logout-separator'),
      height: 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [color.withValues(alpha: 0.24), Colors.transparent],
          ),
        ),
      ),
    );
  }
}

/// Applies the Building Suit page-plane transform to the current page while
/// the side menu is open: 60% travel away from the opening edge, 0.85
/// scale, 40px corners, and a lateral shadow, all driven by the menu
/// route's animation. It wraps the authenticated navigation subtree so every
/// route with the shared header moves as one coherent surface.
class FinanceSuitMenuPagePlane extends StatelessWidget {
  const FinanceSuitMenuPagePlane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FinanceSuitMenu.pageProgress,
        NotificationCenter.pageProgress,
      ]),
      child: child,
      builder: (context, page) {
        final menuProgress = FinanceSuitMenu.pageProgress.value;
        final notificationProgress = NotificationCenter.pageProgress.value;
        final progress = math.max(menuProgress, notificationProgress);
        if (progress == 0) return page!;
        final size = MediaQuery.sizeOf(context);
        final awayFromOpeningEdge = notificationProgress > menuProgress
            ? NotificationCenter.pagePlaneDirection(context)
            : Directionality.of(context) == TextDirection.rtl
            ? -1.0
            : 1.0;
        final radius = Radius.circular(
          FinanceSuitMenu.pagePlaneRadius * progress,
        );
        // Lateral shadow strength follows the Building Suit elevation3
        // token (24px blur at 16% strength) on the theme's scrim role.
        final shadowColor = Theme.of(
          context,
        ).colorScheme.scrim.withValues(alpha: 0.16 * progress);
        return Transform.translate(
          offset: Offset(
            size.width *
                FinanceSuitMenu.pagePlaneTravel *
                progress *
                awayFromOpeningEdge,
            0,
          ),
          child: Transform.scale(
            scale: 1 - (1 - FinanceSuitMenu.pagePlaneScale) * progress,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(radius),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 24,
                    offset: Offset(-8 * awayFromOpeningEdge, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.all(radius),
                child: page,
              ),
            ),
          ),
        );
      },
    );
  }
}
