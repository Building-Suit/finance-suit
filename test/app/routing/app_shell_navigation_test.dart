import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';

import 'shell_test_harness.dart';

void main() {
  const addButton = Key('global-add-button');
  const addSheetList = Key('global-add-list');

  Finder navBar() => find.byType(FinanceSuitNavigationBar);

  testWidgets('shows exactly four destinations without Settings', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    expect(navBar(), findsOneWidget);
    for (final label in ['Home', 'Work', 'Money', 'Reports']) {
      expect(
        find.descendant(of: navBar(), matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: navBar(), matching: find.text('Settings')),
      findsNothing,
    );
    expect(
      find.descendant(of: navBar(), matching: find.byKey(addButton)),
      findsOneWidget,
    );
    // The old floating action button is gone.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('centers the add action between Work and Money in LTR', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    final work = tester.getCenter(
      find.descendant(of: navBar(), matching: find.text('Work')),
    );
    final money = tester.getCenter(
      find.descendant(of: navBar(), matching: find.text('Money')),
    );
    final add = tester.getCenter(find.byKey(addButton));
    expect(work.dx, lessThan(add.dx));
    expect(add.dx, lessThan(money.dx));

    // Equal, stable center slot: the add action sits on the horizontal
    // middle of the screen.
    final width = tester.getSize(find.byType(MaterialApp)).width;
    expect(add.dx, closeTo(width / 2, 1.0));
  });

  testWidgets('centers the add action between Work and Money in RTL', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      locale: const Locale('ar'),
    );

    final work = tester.getCenter(
      find.descendant(of: navBar(), matching: find.text('العمل')),
    );
    final money = tester.getCenter(
      find.descendant(of: navBar(), matching: find.text('المال')),
    );
    final add = tester.getCenter(find.byKey(addButton));
    expect(money.dx, lessThan(add.dx));
    expect(add.dx, lessThan(work.dx));
    final width = tester.getSize(find.byType(MaterialApp)).width;
    expect(add.dx, closeTo(width / 2, 1.0));
  });

  testWidgets('add opens the Global Add sheet without changing the branch', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    expect(find.text('home-root'), findsOneWidget);

    await tester.tap(find.byKey(addButton));
    await tester.pumpAndSettle();
    expect(find.byKey(addSheetList), findsOneWidget);

    // Compact mode: destination rows sit on the accessible 48dp floor.
    expect(tester.getSize(find.widgetWithText(ListTile, 'Expense')).height, 48);

    // Dismissing keeps the selected branch unchanged.
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(addSheetList), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('selecting a Global Add item preserves its exact route', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    await tester.tap(find.byKey(addButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense').hitTestable());
    await tester.pumpAndSettle();

    // Route including the query parameter is preserved, and the bottom
    // navigation is gone on the pushed form.
    expect(find.text('tx-form-expense'), findsOneWidget);
    expect(navBar(), findsNothing);
    expect(find.byKey(addButton), findsNothing);
  });

  testWidgets('salary-adjustment context flows through the add sheet', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await tester.tap(find.byKey(addButton));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Work Control'),
      find.byKey(addSheetList),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work Control'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('New adjustment'),
      find.byKey(addSheetList),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New adjustment').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('salary-adjustment-form'), findsOneWidget);
    expect(navBar(), findsNothing);
  });

  testWidgets('hides the bar on pushed routes and restores branch state', (
    tester,
  ) async {
    final router = buildShellTestRouter();
    await pumpShellApp(tester, router);

    // Switch to Work and mutate its local state.
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Work')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-root-counter')));
    await tester.pump();
    expect(find.text('work-root-taps-1'), findsOneWidget);

    // Push a focused form: the entire bar (and center add) disappears.
    unawaited(router.push('/work/entry/new'));
    await tester.pumpAndSettle();
    expect(find.text('work-entry-form'), findsOneWidget);
    expect(navBar(), findsNothing);
    expect(find.byKey(addButton), findsNothing);

    // Back returns to the exact originating tab with its state intact.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('work-root-taps-1'), findsOneWidget);
    expect(navBar(), findsOneWidget);
  });

  testWidgets('preserves every branch state across tab switches', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    await tester.tap(find.byKey(const Key('home-root-counter')));
    await tester.pump();
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Work')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('work-root-counter')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('work-root-counter')));
    await tester.pump();
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Money')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Home')),
    );
    await tester.pumpAndSettle();
    expect(find.text('home-root-taps-1'), findsOneWidget);
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Work')),
    );
    await tester.pumpAndSettle();
    expect(find.text('work-root-taps-2'), findsOneWidget);

    // Reselecting the active destination keeps it stable.
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Work')),
    );
    await tester.pumpAndSettle();
    expect(find.text('work-root'), findsOneWidget);
  });

  testWidgets('hides the bar on pushed Settings and restores the tab', (
    tester,
  ) async {
    final router = buildShellTestRouter();
    await pumpShellApp(tester, router);
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Reports')),
    );
    await tester.pumpAndSettle();

    unawaited(router.push('/settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings-root'), findsOneWidget);
    expect(navBar(), findsNothing);

    // The focused header Back returns to the originating tab.
    await tester.tap(find.byKey(const Key('finance-suit-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('reports-root'), findsOneWidget);
    expect(navBar(), findsOneWidget);
  });

  testWidgets('deep link to Settings shows Back that leads Home', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(initialLocation: '/settings'),
    );
    expect(find.text('settings-root'), findsOneWidget);
    expect(navBar(), findsNothing);

    await tester.tap(find.byKey(const Key('finance-suit-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('home-root'), findsOneWidget);
    expect(navBar(), findsOneWidget);
  });

  testWidgets('deep link to a nested form keeps a valid Back path', (
    tester,
  ) async {
    await pumpShellApp(
      tester,
      buildShellTestRouter(initialLocation: '/money/categories/new'),
    );
    expect(find.text('category-form'), findsOneWidget);
    expect(navBar(), findsNothing);

    await tester.tap(find.byKey(const Key('finance-suit-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('categories-screen'), findsOneWidget);
    expect(navBar(), findsNothing);

    await tester.tap(find.byKey(const Key('finance-suit-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('money-root'), findsOneWidget);
    expect(navBar(), findsOneWidget);
  });

  testWidgets('fits a small phone in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      locale: const Locale('ar'),
    );
    expect(navBar(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
