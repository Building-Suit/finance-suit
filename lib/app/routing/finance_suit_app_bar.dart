import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
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
       actions = null;

  /// Header for focused, pushed, form, detail, and utility destinations.
  const FinanceSuitAppBar.focused({
    super.key,
    required this.semanticTitle,
    this.actions,
    this.bottom,
  }) : _isTopLevel = false;

  final bool _isTopLevel;

  /// Accessible name of the current screen, announced as a header.
  final String semanticTitle;

  /// Contextual actions that belong to the focused screen itself.
  final List<Widget>? actions;

  final PreferredSizeWidget? bottom;

  static const double _logoSize = 32;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: true,
      leading: _isTopLevel
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
      actions: [const _MoneyVisibilityAction(), ...?actions],
      bottom: bottom,
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
