import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';

void main() {
  testWidgets('directional glyph mirrors only in RTL', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FinanceSuitIcon(FinanceSuitIcons.chevronRight),
      ),
    );
    expect(find.byType(Transform), findsNothing);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: FinanceSuitIcon(FinanceSuitIcons.chevronRight),
      ),
    );
    expect(find.byType(Transform), findsOneWidget);
  });

  testWidgets('non-directional glyph keeps its geometry in RTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: FinanceSuitIcon(FinanceSuitIcons.home),
      ),
    );
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('glyph keeps its optical size inside a large control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.square(
          dimension: 48,
          child: FinanceSuitIcon(FinanceSuitIcons.home, size: 24),
        ),
      ),
    );

    expect(tester.getSize(find.byType(HugeIcon)), const Size.square(24));
  });

  testWidgets('explicit icon semantics are announced once', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FinanceSuitIcon(
          FinanceSuitIcons.info,
          semanticLabel: 'Information',
        ),
      ),
    );

    expect(find.bySemanticsLabel('Information'), findsOneWidget);
    semantics.dispose();
  });
}
