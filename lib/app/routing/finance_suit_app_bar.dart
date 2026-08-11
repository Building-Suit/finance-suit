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
       _showsMoneyVisibility = true;

  /// Header for pre-authentication and onboarding pages. It keeps the same
  /// Finance Suit chrome without exposing app navigation before setup ends.
  const FinanceSuitAppBar.standalone({
    super.key,
    required this.semanticTitle,
    this.bottom,
  }) : _isTopLevel = false,
       _hasLeadingControl = false,
       _showsMoneyVisibility = false,
       actions = null;

  final bool _isTopLevel;
  final bool _hasLeadingControl;
  final bool _showsMoneyVisibility;

  /// Accessible name of the current screen, announced as a header.
  final String semanticTitle;

  /// Contextual actions that belong to the focused screen itself.
  final List<Widget>? actions;

  final PreferredSizeWidget? bottom;

  static const double _logoSize = 32;
  static const double _horizontalInset = 16;
  static const double _cornerRadius = 16;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

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
    final headerScrollState = _isTopLevel
        ? FinanceSuitHeaderScrollScope.maybeOf(context)
        : null;

    Widget headerSurface(bool isSolid) => Stack(
      fit: StackFit.expand,
      children: [
        // This surface is deliberately not color-tweened. Interpolating from
        // transparent exposes and blends the page background, which was the
        // source of the gray flash during the floating-to-solid transition.
        if (isSolid) ColoredBox(color: surfaceColor),
        SafeArea(
          bottom: false,
          child: AnimatedPadding(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : FinanceSuitHomeAppBar.transitionDuration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: isSolid ? 0 : _horizontalInset,
            ),
            child: DecoratedBox(
              key: const Key('finance-suit-app-bar-surface'),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(
                  isSolid ? 0 : _cornerRadius,
                ),
                border: Border.all(
                  color: isSolid ? Colors.transparent : borderColor,
                ),
                boxShadow: isSolid
                    ? const []
                    : [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
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
          ? headerSurface(false)
          : ValueListenableBuilder<bool>(
              valueListenable: headerScrollState,
              builder: (context, isSolid, _) => headerSurface(isSolid),
            ),
      leading: !_hasLeadingControl
          ? null
          : _isTopLevel
          ? IconButton(
              key: const Key('finance-suit-menu-button'),
              tooltip: l10n.menuOpenTooltip,
              onPressed: () => FinanceSuitMenu.open(context),
              icon: const FinanceSuitIcon(FinanceSuitIcons.menu),
            )
          : IconButton(
              key: const Key('finance-suit-back-button'),
              tooltip: l10n.commonBack,
              onPressed: () {
                // Deep links can land here without history; fall back to the
                // primary Home destination so Back always has a target.
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.home);
                }
              },
              icon: const FinanceSuitIcon(FinanceSuitIcons.chevronLeft),
            ),
      title: Semantics(
        header: true,
        label: semanticTitle,
        child: const ExcludeSemantics(
          child: FinanceSuitMark(size: _logoSize, semanticLabel: null),
        ),
      ),
      actions: [
        if (_showsMoneyVisibility) const _MoneyVisibilityAction(),
        if (_showsMoneyVisibility)
          IconButton(
            key: const Key('finance-suit-notifications-button'),
            tooltip: l10n.setNotificationsSection,
            onPressed: () => NotificationCenter.open(context),
            icon: const FinanceSuitIcon(FinanceSuitIcons.notifications),
          ),
        ...?actions,
      ],
      bottom: bottom,
    );
  }
}

/// The scroll-aware Home header surface.
///
/// It intentionally keeps one stable widget tree while [isSolid] changes, so
/// the menu and privacy actions are never recreated as the outer surface
/// morphs between its floating and attached appearances.
class FinanceSuitHomeAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const FinanceSuitHomeAppBar({
    super.key,
    required this.semanticTitle,
    required this.isSolid,
    this.entitlement,
  });

  final String semanticTitle;
  final bool isSolid;
  final EffectiveEntitlement? entitlement;

  static const _toolbarHeight = kToolbarHeight;
  static const _stripOverlap = 8.0;
  static const _logoSize = 32.0;
  static const transitionDuration = Duration(milliseconds: 220);

  @override
  Size get preferredSize => Size.fromHeight(
    _toolbarHeight +
        (entitlement != null && !isSolid
            ? SubscriptionStatusStrip.height - _stripOverlap
            : 0),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final l10n = AppLocalizations.of(context);
    final isFloating = !isSolid;
    final strip = entitlement;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final shadowColor =
        (Theme.of(context).brightness == Brightness.dark
                ? colors.background
                : colors.inverseSurface)
            .withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.28
                  : 0.08,
            );

    // The full-width surface changes immediately; only the header geometry
    // animates. A transparent-to-surface color tween blended the underlying
    // page background into a visible gray band before the solid state won.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ColoredBox(
            key: const Key('finance-suit-home-header-safe-area-surface'),
            color: isSolid ? colors.surface : Colors.transparent,
          ),
        ),
        SafeArea(
          bottom: false,
          child: RepaintBoundary(
            child: SizedBox(
              height: preferredSize.height,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.topCenter,
                  children: [
                    if (strip != null)
                      Positioned(
                        top: _toolbarHeight - _stripOverlap,
                        left: 16,
                        right: 16,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth - 32,
                            ),
                            child: SubscriptionStatusStrip(
                              entitlement: strip,
                              visible: isFloating,
                              onUpgrade: () =>
                                  context.push(AppRoutes.subscription),
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      key: const Key('finance-suit-home-header-surface'),
                      duration: reducedMotion
                          ? Duration.zero
                          : transitionDuration,
                      curve: Curves.easeOutCubic,
                      width: double.infinity,
                      height: _toolbarHeight,
                      margin: EdgeInsetsDirectional.symmetric(
                        horizontal: isFloating ? 16 : 0,
                      ),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(
                          isFloating ? 16 : 0,
                        ),
                        border: Border.all(
                          color: isFloating
                              ? colors.borderSubtle
                              : Colors.transparent,
                        ),
                        boxShadow: isFloating
                            ? [
                                BoxShadow(
                                  color: shadowColor,
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : const [],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PositionedDirectional(
                              start: 0,
                              child: IconButton(
                                key: const Key('finance-suit-menu-button'),
                                tooltip: l10n.menuOpenTooltip,
                                onPressed: () => FinanceSuitMenu.open(context),
                                icon: const FinanceSuitIcon(
                                  FinanceSuitIcons.menu,
                                ),
                              ),
                            ),
                            Semantics(
                              header: true,
                              label: semanticTitle,
                              child: const ExcludeSemantics(
                                child: FinanceSuitMark(size: _logoSize),
                              ),
                            ),
                            PositionedDirectional(
                              end: 0,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _MoneyVisibilityAction(),
                                  IconButton(
                                    key: const Key(
                                      'finance-suit-notifications-button',
                                    ),
                                    tooltip: l10n.setNotificationsSection,
                                    onPressed: () =>
                                        NotificationCenter.open(context),
                                    icon: const FinanceSuitIcon(
                                      FinanceSuitIcons.notifications,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
