import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';

import 'shell_test_harness.dart';

void main() {
  const menuButton = Key('finance-suit-menu-button');
  const panelKey = Key('finance-suit-menu-panel');
  const addButton = Key('global-add-button');

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(menuButton).first);
    await tester.pumpAndSettle();
  }

  testWidgets('opens from the start edge at 67.5% width in LTR', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await openMenu(tester);

    final screen = tester.getSize(find.byType(MaterialApp));
    final panel = tester.getRect(find.byKey(panelKey));
    expect(panel.width, closeTo(screen.width * 0.675, 1.0));
    expect(panel.left, closeTo(0, 1.0));
    expect(panel.top, closeTo(0, 1.0));
    expect(panel.bottom, closeTo(screen.height, 1.0));

    // Compact mode: destination rows keep the accessible 48dp floor
    // without the default taller tile padding.
    expect(
      tester.getSize(find.byKey(const Key('menu-item-/settings'))).height,
      48,
    );
  });

  testWidgets('opens from the right edge in Arabic RTL', (tester) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      locale: const Locale('ar'),
    );
    await openMenu(tester);

    final screen = tester.getSize(find.byType(MaterialApp));
    final panel = tester.getRect(find.byKey(panelKey));
    expect(panel.width, closeTo(screen.width * 0.675, 1.0));
    expect(panel.right, closeTo(screen.width, 1.0));
  });

  testWidgets('uses the 320ms emphasized open and 240ms scrim', (tester) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await tester.tap(find.byKey(menuButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    // Mid-open: the panel exists but has not settled to full opacity.
    Opacity panelOpacity() => tester.widget<Opacity>(
      find
          .ancestor(of: find.byKey(panelKey), matching: find.byType(Opacity))
          .first,
    );
    expect(find.byKey(panelKey), findsOneWidget);
    expect(panelOpacity().opacity, lessThan(1.0));

    // Settled shortly after 320ms.
    await tester.pump(const Duration(milliseconds: 200));
    expect(panelOpacity().opacity, moreOrLessEquals(1.0, epsilon: 0.001));
    await tester.pumpAndSettle();
  });

  testWidgets('closes with the 180ms quick exit via backdrop tap', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await openMenu(tester);

    final screen = tester.getSize(find.byType(MaterialApp));
    await tester.tapAt(Offset(screen.width * 0.9, screen.height / 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    // Still animating out at 90ms.
    expect(find.byKey(panelKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('blocks background content, bottom bar, and the center add', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await openMenu(tester);

    // The background counter button is under the scrim: not hit-testable.
    expect(
      find.byKey(const Key('home-root-counter')).hitTestable(),
      findsNothing,
    );
    expect(find.byKey(addButton).hitTestable(), findsNothing);
    expect(
      find
          .descendant(
            of: find.byType(FinanceSuitNavigationBar),
            matching: find.text('Work'),
          )
          .hitTestable(),
      findsNothing,
    );

    // Tapping where the add button sits must not open the Global Add sheet.
    await tester.tap(find.byKey(addButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('global-add-list')), findsNothing);
  });

  testWidgets('system Back closes the menu before leaving the route', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await openMenu(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('Escape closes the menu', (tester) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await openMenu(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
  });

  testWidgets('never stacks two menu overlays', (tester) async {
    await pumpShellApp(tester, buildShellTestRouter());

    final context = tester.element(find.byKey(menuButton).first);
    final first = FinanceSuitMenu.open(context);
    final second = FinanceSuitMenu.open(context);
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsOneWidget);
    expect(FinanceSuitMenu.isOpen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await first;
    await second;
    expect(FinanceSuitMenu.isOpen, isFalse);
    expect(find.byKey(panelKey), findsNothing);
  });

  testWidgets('interrupted open reverses without restarting', (tester) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await tester.tap(find.byKey(menuButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // Reverse mid-open via system Back.
    await tester.binding.handlePopRoute();
    await tester.pump();
    // Panel still present while reversing from current progress.
    expect(find.byKey(panelKey), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion swaps travel for a short fade', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await pumpShellApp(tester, buildShellTestRouter());

    await tester.tap(find.byKey(menuButton).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    expect(find.byKey(panelKey), findsOneWidget);
    // No structural travel under reduced motion.
    expect(
      find.ancestor(
        of: find.byKey(panelKey),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('lists every destination and navigates to exact routes', (
    tester,
  ) async {
    final routesToLabels = {
      '/settings': 'settings-root',
      '/history': 'history-screen',
      '/settings/income-sources': 'automation-center',
      '/work/periods': 'salary-periods-screen',
      '/work/holidays': 'holidays-screen',
      '/money/categories': 'categories-screen',
      '/money/macros': 'macros-screen',
    };
    final router = buildShellTestRouter();
    await pumpShellApp(tester, router);

    for (final entry in routesToLabels.entries) {
      await openMenu(tester);
      final item = find.byKey(Key('menu-item-${entry.key}'));
      await tester.dragUntilVisible(
        item,
        find.byKey(const Key('finance-suit-menu-list')),
        const Offset(0, -40),
      );
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      // The bottom navigation stays hidden on every menu destination.
      expect(find.byType(FinanceSuitNavigationBar), findsNothing);

      router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('does not push a duplicate when the route is already active', (
    tester,
  ) async {
    final router = buildShellTestRouter();
    await pumpShellApp(tester, router);

    await openMenu(tester);
    await tester.tap(find.byKey(const Key('menu-item-/settings')));
    await tester.pumpAndSettle();
    expect(find.text('settings-root'), findsOneWidget);

    // Open the menu from the focused screen's context and pick Settings
    // again: no second Settings entry may be pushed.
    final context = tester.element(find.text('settings-root'));
    final opened = FinanceSuitMenu.open(context);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-item-/settings')));
    await tester.pumpAndSettle();
    await opened;
    expect(find.text('settings-root'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    // A single pop lands straight back on the originating tab.
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('focus enters the menu and returns to the trigger', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    // Focus the hamburger with the keyboard and activate it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final trigger = FocusManager.instance.primaryFocus;
    expect(trigger, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsOneWidget);

    // Focus moved inside the menu (the first destination autofocuses).
    final focused = FocusManager.instance.primaryFocus!;
    expect(
      focused.context,
      isNotNull,
      reason: 'menu should hold keyboard focus',
    );
    expect(
      find
          .ancestor(
            of: find.byWidget(focused.context!.widget),
            matching: find.byKey(const Key('menu-item-/settings')),
          )
          .evaluate(),
      isNotEmpty,
      reason: 'first menu item receives focus when the menu opens',
    );

    // Keyboard traversal stays trapped inside the modal menu.
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final node = FocusManager.instance.primaryFocus;
      final inMenu = find
          .ancestor(
            of: find.byWidget(node!.context!.widget),
            matching: find.byKey(panelKey),
          )
          .evaluate()
          .isNotEmpty;
      expect(inMenu, isTrue, reason: 'tab press $i escaped the menu');
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(panelKey), findsNothing);
    expect(
      FocusManager.instance.primaryFocus,
      same(trigger),
      reason: 'focus returns to the hamburger trigger on close',
    );
  });

  testWidgets('menu remains usable at 320x480 and scrolls internally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      locale: const Locale('ar'),
    );
    await openMenu(tester);

    final panel = tester.getRect(find.byKey(panelKey));
    expect(panel.width, closeTo(320 * 0.675, 1.0));
    // Long content scrolls inside the panel without errors.
    await tester.drag(
      find.byKey(const Key('finance-suit-menu-list')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
