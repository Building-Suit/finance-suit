import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
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
      actions: actions,
      bottom: bottom,
    );
  }
}
