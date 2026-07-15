import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';

/// A flat, mask-safe Finance Suit ledger monogram.
///
/// This is deliberately independent from the building-shaped mark used by
/// another Suit product. It shares only the approved palette and geometry.
class FinanceSuitMark extends StatelessWidget {
  const FinanceSuitMark({
    super.key,
    this.size = 64,
    this.withBackground = true,
    this.semanticLabel = FinanceSuitBrand.name,
  });

  final double size;
  final bool withBackground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final artwork = ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FinanceSuitMarkPainter(withBackground: withBackground),
        ),
      ),
    );
    if (semanticLabel == null) return artwork;
    return Semantics(image: true, label: semanticLabel, child: artwork);
  }
}

class _FinanceSuitMarkPainter extends CustomPainter {
  const _FinanceSuitMarkPainter({required this.withBackground});

  final bool withBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 108;
    canvas.save();
    canvas.scale(scale, scale);

    if (withBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 108, 108),
          const Radius.circular(24),
        ),
        Paint()..color = FinanceSuitBrand.buildingNavy,
      );
    }

    final body = Path()
      ..moveTo(30, 22)
      ..lineTo(76, 22)
      ..quadraticBezierTo(80, 22, 80, 26)
      ..lineTo(80, 32)
      ..quadraticBezierTo(80, 36, 76, 36)
      ..lineTo(42, 36)
      ..lineTo(42, 46)
      ..lineTo(64, 46)
      ..quadraticBezierTo(68, 46, 68, 50)
      ..lineTo(68, 56)
      ..quadraticBezierTo(68, 60, 64, 60)
      ..lineTo(42, 60)
      ..lineTo(42, 82)
      ..quadraticBezierTo(42, 86, 38, 86)
      ..lineTo(30, 86)
      ..quadraticBezierTo(26, 86, 26, 82)
      ..lineTo(26, 26)
      ..quadraticBezierTo(26, 22, 30, 22)
      ..close();
    canvas.drawPath(body, Paint()..color = FinanceSuitBrand.pearlWhite);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(70, 46, 12, 14),
        const Radius.circular(3),
      ),
      Paint()..color = FinanceSuitBrand.premiumGold,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FinanceSuitMarkPainter oldDelegate) =>
      oldDelegate.withBackground != withBackground;
}
