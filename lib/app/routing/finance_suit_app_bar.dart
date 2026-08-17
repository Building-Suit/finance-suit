import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_header_scroll_scope.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/notifications/notification_center.dart';
import 'package:work_tracker/core/notifications/notification_feed.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/widgets/subscription_status_strip.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The canonical Finance Suit top header.
///
/// Top-level destinations show the side-menu trigger at the logical start
/// edge and the centered official brand mark; focused (pushed) destinations
/// show a Back control instead. The brand artwork itself never flips in RTL;
/// only control placement mirrors. The current screen keeps an accessible
/// name through [semanticTitle] even though no visible title is rendered.
class FinanceSuitAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Header for the four primary bottom-navigation destinations.
  const FinanceSuitAppBar.topLevel({
    super.key,
    required this.semanticTitle,
    this.bottom,
    this.entitlement,
    this.isSolid,
  }) : _isTopLevel = true,
       _hasLeadingControl = true,
       _showsMoneyVisibility = true,
       actions = null;

  /// Header for focused, pushed, form, detail, and utility destinations.
  const FinanceSuitAppBar.focused({
    super.key,
    required this.semanticTitle,
    this.actions,
    this.bottom,
  }) : _isTopLevel = false,
       _hasLeadingControl = true,
       _showsMoneyVisibility = true,
       entitlement = null,
       isSolid = null;

  /// Header for pre-authentication and onboarding pages. It keeps the same
  /// Finance Suit chrome without exposing app navigation before setup ends.
  const FinanceSuitAppBar.standalone({
    super.key,
    required this.semanticTitle,
    this.bottom,
  }) : _isTopLevel = false,
       _hasLeadingControl = false,
       _showsMoneyVisibility = false,
       entitlement = null,
       isSolid = null,
       actions = null;

  final bool _isTopLevel;
  final bool _hasLeadingControl;
  final bool _showsMoneyVisibility;

  /// Accessible name of the current screen, announced as a header.
  final String semanticTitle;

  /// Contextual actions that belong to the focused screen itself.
  final List<Widget>? actions;

  final PreferredSizeWidget? bottom;

  /// Optional shell-owned status strip. Home supplies it without creating a
  /// second header implementation.
  final EffectiveEntitlement? entitlement;

  /// Explicit state for isolated screens/tests. Authenticated tab roots use
  /// [FinanceSuitHeaderScrollScope] when this is null.
  final bool? isSolid;

  static const double _logoSize = 32;
  static const double _horizontalInset = 16;
  static const double _cornerRadius = 16;
  static const double _stripOverlap = 8;
  static const Duration transitionDuration = Duration(milliseconds: 220);

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight +
        (bottom?.preferredSize.height ?? 0) +
        (entitlement != null && isSolid != true
            ? SubscriptionStatusStrip.height - _stripOverlap
            : 0),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticColors = theme.extension<FinanceSuitSemanticColors>();
    // The app normally supplies FinanceSuitSemanticColors, but shared chrome
    // must also render in isolated previews and plain Material test harnesses.
    // Falling back to ColorScheme keeps the header functional instead of
    // crashing when that optional theme extension is absent.
    final surfaceColor = semanticColors?.surface ?? theme.colorScheme.surface;
    final borderColor =
        semanticColors?.borderSubtle ?? theme.colorScheme.outlineVariant;
    final backgroundColor =
        semanticColors?.background ?? theme.colorScheme.surface;
    final inverseSurfaceColor =
        semanticColors?.inverseSurface ?? theme.colorScheme.inverseSurface;
    final l10n = AppLocalizations.of(context);
    final shadowColor =
        (theme.brightness == Brightness.dark
                ? backgroundColor
                : inverseSurfaceColor)
            .withValues(
              alpha: theme.brightness == Brightness.dark ? 0.28 : 0.08,
            );
    final headerScrollState = _isTopLevel && isSolid == null
        ? FinanceSuitHeaderScrollScope.maybeOf(context)
        : null;

    Widget headerSurface(bool solid) => Stack(
      fit: StackFit.expand,
      children: [
        // This surface is deliberately not color-tweened. Interpolating from
        // transparent exposes and blends the page background, which was the
        // source of the gray flash during the floating-to-solid transition.
        ColoredBox(
          key: const Key('finance-suit-header-safe-area-surface'),
          color: solid ? surfaceColor : Colors.transparent,
        ),
        SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.topCenter,
              children: [
                if (entitlement != null)
                  Positioned(
                    top: kToolbarHeight - _stripOverlap,
                    left: _horizontalInset,
                    right: _horizontalInset,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              constraints.maxWidth - (_horizontalInset * 2),
                        ),
                        child: SubscriptionStatusStrip(
                          entitlement: entitlement!,
                          visible: !solid,
                          onUpgrade: () => context.push(AppRoutes.subscription),
                        ),
                      ),
                    ),
                  ),
                AnimatedContainer(
                  key: const Key('finance-suit-app-bar-surface'),
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : transitionDuration,
                  curve: Curves.easeOutCubic,
                  width: double.infinity,
                  height: kToolbarHeight + (bottom?.preferredSize.height ?? 0),
                  margin: EdgeInsetsDirectional.symmetric(
                    horizontal: solid ? 0 : _horizontalInset,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(
                      solid ? 0 : _cornerRadius,
                    ),
                    boxShadow: solid
                        ? const []
                        : [
                            BoxShadow(
                              color: shadowColor,
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      solid ? 0 : _cornerRadius,
                    ),
                    border: Border.all(
                      color: solid ? Colors.transparent : borderColor,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: kToolbarHeight,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_hasLeadingControl)
                                PositionedDirectional(
                                  start: 0,
                                  child: _isTopLevel
                                      ? IconButton(
                                          key: const Key(
                                            'finance-suit-menu-button',
                                          ),
                                          tooltip: l10n.menuOpenTooltip,
                                          onPressed: () =>
                                              FinanceSuitMenu.open(context),
                                          icon: const FinanceSuitIcon(
                                            FinanceSuitIcons.menu,
                                          ),
                                        )
                                      : IconButton(
                                          key: const Key(
                                            'finance-suit-back-button',
                                          ),
                                          tooltip: l10n.commonBack,
                                          onPressed: () {
                                            if (context.canPop()) {
                                              context.pop();
                                            } else {
                                              context.go(AppRoutes.home);
                                            }
                                          },
                                          icon: const FinanceSuitIcon(
                                            FinanceSuitIcons.chevronLeft,
                                          ),
                                        ),
                                ),
                              Semantics(
                                header: true,
                                label: semanticTitle,
                                child: const ExcludeSemantics(
                                  child: FinanceSuitMark(
                                    size: _logoSize,
                                    semanticLabel: null,
                                  ),
                                ),
                              ),
                              if (_showsMoneyVisibility || actions != null)
                                PositionedDirectional(
                                  end: 0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_showsMoneyVisibility)
                                        const _MoneyVisibilityAction(),
                                      if (_showsMoneyVisibility)
                                        const _NotificationBellAction(),
                                      ...?actions,
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        ?bottom,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: headerScrollState == null
          ? _isTopLevel || !_hasLeadingControl
                ? headerSurface(isSolid ?? false)
                : _FinanceSuitObservedHeaderSurface(builder: headerSurface)
          : ValueListenableBuilder<bool>(
              valueListenable: headerScrollState,
              builder: (context, isSolid, _) => headerSurface(isSolid),
            ),
      toolbarHeight: 0,
      leading: null,
      title: null,
      actions: null,
      bottom: null,
    );
  }
}

/// Gives focused routes the same motion contract without route-local
/// controllers. Every Material [Scaffold] owns one notification observer, so
/// this listener follows whichever vertical body scrollable is currently
/// active and is removed with the shared header.
class _FinanceSuitObservedHeaderSurface extends StatefulWidget {
  const _FinanceSuitObservedHeaderSurface({required this.builder});

  final Widget Function(bool isSolid) builder;

  @override
  State<_FinanceSuitObservedHeaderSurface> createState() =>
      _FinanceSuitObservedHeaderSurfaceState();
}

class _FinanceSuitObservedHeaderSurfaceState
    extends State<_FinanceSuitObservedHeaderSurface> {
  static const _solidThreshold = 12.0;
  static const _floatingThreshold = 4.0;

  ScrollNotificationObserverState? _observer;
  bool _isSolid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (identical(observer, _observer)) return;
    _observer?.removeListener(_handleScroll);
    _observer = observer?..addListener(_handleScroll);
  }

  void _handleScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return;
    final next = _isSolid
        ? notification.metrics.pixels >= _floatingThreshold
        : notification.metrics.pixels > _solidThreshold;
    if (next == _isSolid || !mounted) return;
    setState(() => _isSolid = next);
  }

  @override
  void dispose() {
    _observer?.removeListener(_handleScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_isSolid);
}

/// The header bell and the app's single unread badge.
///
/// The count comes from [notificationUnreadCountProvider], the one
/// authoritative unread state, so the bell can never disagree with the
/// Notification Center or show a stale positive number. Feature-specific
/// counts (pending transfers, dues) are separate concepts and deliberately do
/// not feed this badge.
class _NotificationBellAction extends ConsumerWidget {
  const _NotificationBellAction();

  static const _maxDisplayed = 99;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Same fallback contract as the header surface above: shared chrome must
    // still render when the semantic-colour extension is absent.
    final semanticColors = theme.extension<FinanceSuitSemanticColors>();
    final badgeColor = semanticColors?.error.icon ?? theme.colorScheme.error;
    final badgeTextColor =
        semanticColors?.error.textOnSolid ?? theme.colorScheme.onError;
    final unread = ref.watch(notificationUnreadCountProvider);
    final bell = IconButton(
      key: const Key('finance-suit-notifications-button'),
      tooltip: l10n.setNotificationsSection,
      onPressed: () => NotificationCenter.open(context),
      icon: const FinanceSuitIcon(FinanceSuitIcons.notifications),
    );
    if (unread <= 0) return bell;
    final label = unread > _maxDisplayed ? '$_maxDisplayed+' : '$unread';
    return Semantics(
      label: l10n.notificationBadgeLabel(unread),
      button: true,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            bell,
            PositionedDirectional(
              top: 6,
              end: 4,
              child: DecoratedBox(
                key: const Key('finance-suit-notifications-badge'),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 10),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: badgeTextColor,
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyVisibilityAction extends ConsumerWidget {
  const _MoneyVisibilityAction();

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final privacy = ref.read(devicePrivacyProvider).value;
    if (privacy == null || privacy.authenticating) return;
    final controller = ref.read(devicePrivacyProvider.notifier);
    if (privacy.moneyRevealed) {
      controller.hideMoney();
      return;
    }

    final l10n = AppLocalizations.of(context);
    final outcome = await controller.revealMoney(
      reason: l10n.privacyRevealReason,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case DeviceAuthOutcome.authenticated:
      case DeviceAuthOutcome.canceled:
        return;
      case DeviceAuthOutcome.unavailable:
        AppToast.warning(context, l10n.privacyDeviceAuthUnavailable);
      case DeviceAuthOutcome.failed:
        AppToast.error(context, l10n.privacyDeviceAuthFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(devicePrivacyProvider).value;
    if (privacy?.moneyPrivacyEnabled != true) return const SizedBox.shrink();
    final revealed = privacy!.moneyRevealed;
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const Key('money-visibility-button'),
      tooltip: revealed
          ? l10n.privacyHideAmountsTooltip
          : l10n.privacyShowAmountsTooltip,
      onPressed: privacy.authenticating ? null : () => _toggle(context, ref),
      icon: FinanceSuitIcon(
        revealed ? FinanceSuitIcons.visibilityOff : FinanceSuitIcons.visibility,
      ),
    );
  }
}

/// Canonical body wrapper for focused destinations.
///
/// The focused header shows only Back and the brand mark, so the screen's
/// contextual title lives inside the page content, above the original body.
class FinanceSuitFocusedBody extends StatelessWidget {
  const FinanceSuitFocusedBody({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(child: child),
      ],
    );
  }
}
