import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';

/// One primary destination in [FinanceSuitNavigationBar].
class FinanceSuitNavDestination {
  const FinanceSuitNavDestination({required this.icon, required this.label});

  final FinanceSuitGlyph icon;
  final String label;
}

/// The canonical Finance Suit bottom navigation bar.
///
/// The navigation assembly is fully sized by the shell's
/// [Scaffold.bottomNavigationBar] slot. Its surface floats within that slot,
/// while a painted, centered concave notch makes room for the independent
/// global Add action: Home | Work | + | Money | Reports.
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

  @visibleForTesting
  static const double assemblyHeight = 96;
  @visibleForTesting
  static const double horizontalInset = 16;
  @visibleForTesting
  static const double surfaceTop = 28;
  @visibleForTesting
  static const double surfaceHeight = 60;
  @visibleForTesting
  static const double centerButtonDiameter = 56;
  static const double _contentClearanceAboveSurface = 76;
  static const double _centerGap = 64;
  static const double _indicatorMaxWidth = 64;
  static const double _indicatorHeight = 32;

  /// Space a scrolling page needs below its final interactive item when this
  /// overlay navigation is present. The visual wrapper stays transparent;
  /// only scroll content reserves this clearance.
  static double contentClearance(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + _contentClearanceAboveSurface;

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: assemblyHeight,
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) => Material(
              color: Colors.transparent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: CustomPaint(
                      key: const Key('finance-suit-navigation-notch'),
                      painter: _NavigationSurfacePainter(
                        surfaceColor: colors.surface,
                        borderColor: colors.borderSubtle,
                        shadowColor: colors.background.withValues(alpha: 0.24),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: surfaceTop,
                    start: horizontalInset,
                    end: horizontalInset,
                    height: surfaceHeight,
                    child: Row(
                      children: [
                        _destination(0),
                        _destination(1),
                        const SizedBox(width: _centerGap),
                        _destination(2),
                        _destination(3),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: addLabel,
                        child: SizedBox.square(
                          dimension: centerButtonDiameter,
                          child: IconButton.filled(
                            key: const Key('global-add-button'),
                            tooltip: addLabel,
                            onPressed: onAddPressed,
                            style: IconButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
                              minimumSize: const Size.square(
                                centerButtonDiameter,
                              ),
                              maximumSize: const Size.square(
                                centerButtonDiameter,
                              ),
                              elevation: 3,
                              shape: const CircleBorder(),
                            ),
                            icon: const FinanceSuitIcon(FinanceSuitIcons.add),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

class _NavigationSurfacePainter extends CustomPainter {
  const _NavigationSurfacePainter({
    required this.surfaceColor,
    required this.borderColor,
    required this.shadowColor,
  });

  final Color surfaceColor;
  final Color borderColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = FinanceSuitNavigationBar.horizontalInset;
    const top = FinanceSuitNavigationBar.surfaceTop;
    const height = FinanceSuitNavigationBar.surfaceHeight;
    const cornerRadius = 20.0;
    // The concave surface is intentionally wider than the 56dp action, so
    // the button reads as seated in a real, continuous cutout rather than
    // overlaid on a rectangular bar.
    const notchRadius = 34.0;
    const notchDepth = 36.0;
    final right = size.width - left;
    final bottom = top + height;
    final center = size.width / 2;
    final path = Path()
      ..moveTo(left + cornerRadius, top)
      ..lineTo(center - notchRadius, top)
      ..cubicTo(
        center - notchRadius * 0.52,
        top,
        center - notchRadius * 0.62,
        top + notchDepth,
        center,
        top + notchDepth,
      )
      ..cubicTo(
        center + notchRadius * 0.62,
        top + notchDepth,
        center + notchRadius * 0.52,
        top,
        center + notchRadius,
        top,
      )
      ..lineTo(right - cornerRadius, top)
      ..quadraticBezierTo(right, top, right, top + cornerRadius)
      ..lineTo(right, bottom - cornerRadius)
      ..quadraticBezierTo(right, bottom, right - cornerRadius, bottom)
      ..lineTo(left + cornerRadius, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - cornerRadius)
      ..lineTo(left, top + cornerRadius)
      ..quadraticBezierTo(left, top, left + cornerRadius, top)
      ..close();

    canvas.drawShadow(path, shadowColor, 8, false);
    canvas.drawPath(path, Paint()..color = surfaceColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_NavigationSurfacePainter oldDelegate) =>
      surfaceColor != oldDelegate.surfaceColor ||
      borderColor != oldDelegate.borderColor ||
      shadowColor != oldDelegate.shadowColor;
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
    final states = {if (selected) WidgetState.selected};
    final iconTheme = navTheme.iconTheme?.resolve(states);
    final labelStyle = navTheme.labelTextStyle?.resolve(states);
    final labelColor = selected ? iconTheme?.color : labelStyle?.color;
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: math.min<double>(
                  FinanceSuitNavigationBar._indicatorMaxWidth,
                  constraints.maxWidth,
                ),
                height: FinanceSuitNavigationBar._indicatorHeight,
                child: Align(
                  alignment: Alignment.center,
                  child: IconTheme.merge(
                    data: iconTheme ?? const IconThemeData(),
                    child: FinanceSuitIcon(destination.icon),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                style: labelStyle?.copyWith(color: labelColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
