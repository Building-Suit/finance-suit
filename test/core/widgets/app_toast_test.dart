import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';

void main() {
  Future<void> dismissToast(WidgetTester tester) async {
    AppToast.dismiss();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('success is a colored floating top toast', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return FilledButton(
                onPressed: () => AppToast.success(context, 'Saved safely'),
                child: const Text('Show'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    final toast = find.byKey(const ValueKey('app-toast'));
    expect(toast, findsOneWidget);
    expect(find.text('Saved safely'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(tester.getTopLeft(toast).dy, 12);
    expect(tester.getTopLeft(toast).dx, greaterThanOrEqualTo(16));
    expect(tester.getTopRight(toast).dx, lessThanOrEqualTo(396));
    expect(
      tester.widget<Material>(toast).color,
      pageContext.suitColors.success.background,
    );

    await dismissToast(tester);
  });

  testWidgets('a new tone replaces the current toast with its own color', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return Column(
                children: [
                  FilledButton(
                    onPressed: () => AppToast.success(context, 'First'),
                    child: const Text('Success'),
                  ),
                  FilledButton(
                    onPressed: () => AppToast.error(context, 'Second'),
                    child: const Text('Error'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Success'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error'));
    await tester.pumpAndSettle();

    final toast = find.byKey(const ValueKey('app-toast'));
    expect(toast, findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(
      tester.widget<Material>(toast).color,
      pageContext.suitColors.error.background,
    );

    await dismissToast(tester);
  });

  testWidgets('toast action runs once and dismisses the toast', (tester) async {
    var actionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppToast.show(
                context,
                message: 'Could not refresh',
                tone: AppToastTone.error,
                action: AppToastAction(
                  label: 'Retry',
                  onPressed: () => actionCount++,
                ),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(actionCount, 1);
    expect(find.byKey(const ValueKey('app-toast')), findsNothing);
  });

  testWidgets('close control dismisses the toast', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppToast.info(context, 'Information'),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-toast')), findsNothing);
  });

  testWidgets('toast dismisses itself after its duration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppToast.show(
                context,
                message: 'Temporary',
                duration: const Duration(seconds: 2),
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-toast')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-toast')), findsNothing);
  });

  testWidgets('save toast survives closing the form route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: FilledButton(
                      onPressed: () {
                        AppToast.success(context, 'Saved after pop');
                        Navigator.of(context).pop();
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Open form'), findsOneWidget);
    expect(find.text('Saved after pop'), findsOneWidget);

    await dismissToast(tester);
  });

  testWidgets('long RTL message fits a small phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => AppToast.warning(
                context,
                'تعذر إكمال العملية الآن، يرجى المحاولة مرة أخرى بعد قليل.',
              ),
              child: const Text('اعرض'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('اعرض'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-toast')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await dismissToast(tester);
  });

  test('product code cannot bypass the app toast system', () {
    final violations = <String>[];
    final forbidden = <RegExp>[
      RegExp(r'\.showSnackBar\s*\('),
      RegExp(r'\.showMaterialBanner\s*\('),
      RegExp(r'\bSnackBar\s*\('),
      RegExp(r'\bSnackBarThemeData\s*\('),
      RegExp(r'\bsnackBarTheme\s*:'),
      RegExp(r'\bMaterialBanner\s*\('),
    ];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      if (forbidden.any((pattern) => pattern.hasMatch(contents))) {
        violations.add(entity.path);
      }
    }

    expect(violations, isEmpty);
  });
}
