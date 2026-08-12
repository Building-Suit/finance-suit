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
  @visibleForTesting
  // The action is intentionally seated into the bowl rather than floating
  // above it. The values below keep a 4dp contour gap at the bowl's lowest
  // point while leaving the button fully inside the navigation assembly.
  static const double centerButtonTop = 4;

  /// The approved bowl is wider than the action so its shoulders remain
  /// visible instead of disappearing behind the circle.
  @visibleForTesting
  static const double notchWidthFactor = 1.6;
  @visibleForTesting
  static const double notchDepthFactor = 0.5;
  @visibleForTesting
  static const double notchWidth = centerButtonDiameter * notchWidthFactor;
  @visibleForTesting
  static const double notchDepth = centerButtonDiameter * notchDepthFactor;
  static const double _contentClearanceAboveSurface = 76;
  static const double _centerGap = 80;
  static const double _indicatorMaxWidth = 64;
  static const double _indicatorHeight = 32;

  /// The exact painted navigation contour, exposed for geometry regressions.
  @visibleForTesting
  static Path surfacePathFor(Size size) =>
      _NavigationSurfacePainter.surfacePathFor(size);

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
                    top: centerButtonTop,
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

  static const _shape = _CenterActionNotchedShape();

  static Path surfacePathFor(Size size) {
    const left = FinanceSuitNavigationBar.horizontalInset;
    const top = FinanceSuitNavigationBar.surfaceTop;
    const height = FinanceSuitNavigationBar.surfaceHeight;
    final host = Rect.fromLTWH(left, top, size.width - (left * 2), height);
    final guest = Rect.fromLTWH(
      (size.width - FinanceSuitNavigationBar.centerButtonDiameter) / 2,
      FinanceSuitNavigationBar.centerButtonTop,
      FinanceSuitNavigationBar.centerButtonDiameter,
      FinanceSuitNavigationBar.centerButtonDiameter,
    );
    return _shape.getOuterPath(host, guest);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = surfacePathFor(size);

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

/// A responsive, symmetric bowl around the measured center action.
///
/// Flutter's [CircularNotchedRectangle] follows the entire circular guest and
/// produces a deep crater for this compact floating surface. The approved
/// contour is deliberately wider and shallower, so its cubic shoulders begin
/// and end tangent to the bar's top edge while leaving the four destination
/// slots undisturbed.
class _CenterActionNotchedShape extends NotchedShape {
  const _CenterActionNotchedShape();

  static const _cornerRadius = 20.0;

  @override
  Path getOuterPath(Rect host, Rect? guest) {
    final center = guest?.center.dx ?? host.center.dx;
    final diameter =
        guest?.width ?? FinanceSuitNavigationBar.centerButtonDiameter;
    final halfWidth = diameter * FinanceSuitNavigationBar.notchWidthFactor / 2;
    final depth = diameter * FinanceSuitNavigationBar.notchDepthFactor;
    final start = center - halfWidth;
    final end = center + halfWidth;
    final shoulderControl = halfWidth * 0.3;
    final bowlControl = halfWidth * 0.52;

    return Path()
      ..moveTo(host.left + _cornerRadius, host.top)
      ..lineTo(start, host.top)
      ..cubicTo(
        start + shoulderControl,
        host.top,
        center - bowlControl,
        host.top + depth,
        center,
        host.top + depth,
      )
      ..cubicTo(
        center + bowlControl,
        host.top + depth,
        end - shoulderControl,
        host.top,
        end,
        host.top,
      )
      ..lineTo(host.right - _cornerRadius, host.top)
      ..quadraticBezierTo(
        host.right,
        host.top,
        host.right,
        host.top + _cornerRadius,
      )
      ..lineTo(host.right, host.bottom - _cornerRadius)
      ..quadraticBezierTo(
        host.right,
        host.bottom,
        host.right - _cornerRadius,
        host.bottom,
      )
      ..lineTo(host.left + _cornerRadius, host.bottom)
      ..quadraticBezierTo(
        host.left,
        host.bottom,
        host.left,
        host.bottom - _cornerRadius,
      )
      ..lineTo(host.left, host.top + _cornerRadius)
      ..quadraticBezierTo(
        host.left,
        host.top,
        host.left + _cornerRadius,
        host.top,
      )
      ..close();
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
