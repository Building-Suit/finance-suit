import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';

/// One primary destination in [FinanceSuitNavigationBar].
class FinanceSuitNavDestination {
  const FinanceSuitNavDestination({required this.icon, required this.label});

  final FinanceSuitGlyph icon;
  final String label;
}

/// The canonical Finance Suit bottom navigation bar.
///
/// Renders exactly four primary destinations with the global Add action in
/// an equal, stable center slot: Home | Work | + | Money | Reports. The Add
/// slot is a plain button, never a selectable destination, so it carries
/// button semantics instead of tab semantics — the reason this extends the
/// design system rather than reusing [NavigationBar] directly. All colors,
/// heights, and text styles come from the existing [NavigationBarThemeData]
/// roles.
class FinanceSuitNavigationBar extends StatelessWidget {
  const FinanceSuitNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onAddPressed,
    required this.addLabel,
  }) : assert(destinations.length == 4, 'exactly four primary destinations');

  final List<FinanceSuitNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onAddPressed;

  /// Localized tooltip and semantic label for the global Add action.
  final String addLabel;

  // Material 3 navigation-indicator pill dimensions.
  static const double _indicatorWidth = 64;
  static const double _indicatorHeight = 32;
  static const double _barHeight = 70;
  static const double _barRadius = 28;
  static const double _barHorizontalMargin = 12;
  static const double _barBottomMargin = 10;
  static const double _addButtonSize = 58;
  static const double _addIconSize = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavigationBarTheme.of(context);
    final colorScheme = theme.colorScheme;
    // The Add action inherits the roles the global-add FloatingActionButton
    // used before it moved into the bar.
    final fabTheme = theme.floatingActionButtonTheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        _barHorizontalMargin,
        0,
        _barHorizontalMargin,
        _barBottomMargin,
      ),
      child: Material(
        key: const Key('finance-suit-floating-nav-surface'),
        color: navTheme.backgroundColor ?? colorScheme.surface,
        elevation: switch (navTheme.elevation) {
          final elevation? when elevation > 0 => elevation,
          _ => 8,
        },
        shadowColor: colorScheme.shadow.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(_barRadius),
        clipBehavior: Clip.none,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              for (var i = 0; i < 2; i++) _destination(i),
              Expanded(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -10),
                    child: SizedBox.square(
                      dimension: _addButtonSize,
                      child: IconButton.filled(
                        key: const Key('global-add-button'),
                        tooltip: addLabel,
                        onPressed: onAddPressed,
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(_addButtonSize),
                          minimumSize: const Size.square(_addButtonSize),
                          iconSize: _addIconSize,
                          backgroundColor:
                              fabTheme.backgroundColor ?? colorScheme.primary,
                          foregroundColor:
                              fabTheme.foregroundColor ?? colorScheme.onPrimary,
                          elevation: fabTheme.elevation ?? 2,
                          shadowColor: colorScheme.shadow.withValues(
                            alpha: 0.28,
                          ),
                        ),
                        icon: const FinanceSuitIcon(
                          FinanceSuitIcons.add,
                          size: _addIconSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              for (var i = 2; i < 4; i++) _destination(i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destination(int index) {
    return Expanded(
      child: _FinanceSuitNavigationSlot(
        destination: destinations[index],
        selected: index == selectedIndex,
        onTap: () => onDestinationSelected(index),
      ),
    );
  }
}

class _FinanceSuitNavigationSlot extends StatelessWidget {
  const _FinanceSuitNavigationSlot({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final FinanceSuitNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final navTheme = NavigationBarTheme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final states = {if (selected) WidgetState.selected};
    final iconTheme = navTheme.iconTheme?.resolve(states);
    final labelStyle = navTheme.labelTextStyle?.resolve(states);
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: FinanceSuitNavigationBar._indicatorWidth,
              height: FinanceSuitNavigationBar._indicatorHeight,
              alignment: Alignment.center,
              decoration: selected
                  ? ShapeDecoration(
                      color:
                          navTheme.indicatorColor ??
                          colorScheme.secondaryContainer,
                      shape: navTheme.indicatorShape ?? const StadiumBorder(),
                    )
                  : null,
              child: IconTheme.merge(
                data: iconTheme ?? const IconThemeData(),
                child: FinanceSuitIcon(destination.icon),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
