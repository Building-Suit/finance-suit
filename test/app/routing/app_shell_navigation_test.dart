import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/routing/app_shell.dart';
import 'package:work_tracker/app/routing/finance_suit_navigation_bar.dart';
import 'package:work_tracker/core/updates/app_update_service.dart';

import 'shell_test_harness.dart';

class _FakeUpdateService implements AppUpdateService {
  _FakeUpdateService({this.update});

  final PendingAppUpdate? update;
  var startCalls = 0;

  @override
  Future<PendingAppUpdate?> checkForUpdate() async => update;

  @override
  Future<void> startUpdate() async {
    startCalls++;
  }
}

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

  testWidgets('uses matched icon and label color without an active pill', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    final homeLabel = tester.widget<Text>(
      find.descendant(of: navBar(), matching: find.text('Home')),
    );
    final homeIconTheme = tester.widget<IconTheme>(
      find.descendant(of: navBar(), matching: find.byType(IconTheme)).first,
    );

    expect(homeLabel.style?.color, homeIconTheme.data.color);
    expect(
      find.descendant(
        of: navBar(),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration != null,
        ),
      ),
      findsNothing,
    );
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

  testWidgets('keeps the floating notch and Add action inside the app shell', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    final barRect = tester.getRect(navBar());
    final notchRect = tester.getRect(
      find.byKey(const Key('finance-suit-navigation-notch')),
    );
    final addRect = tester.getRect(find.byKey(addButton));
    final workRect = tester.getRect(
      find.descendant(of: navBar(), matching: find.text('Work')),
    );
    final moneyRect = tester.getRect(
      find.descendant(of: navBar(), matching: find.text('Money')),
    );

    expect(notchRect, barRect);
    expect(addRect.top, greaterThanOrEqualTo(barRect.top));
    expect(addRect.bottom, lessThanOrEqualTo(barRect.bottom));
    expect(addRect.width, FinanceSuitNavigationBar.centerButtonDiameter);
    expect(addRect.center.dx, closeTo(barRect.center.dx, 1));
    expect(workRect.right, lessThanOrEqualTo(addRect.left));
    expect(moneyRect.left, greaterThanOrEqualTo(addRect.right));
  });

  test('derives the approved wider shallow notch from the Add button', () {
    expect(FinanceSuitNavigationBar.centerButtonDiameter, 56);
    expect(FinanceSuitNavigationBar.notchWidthFactor, 1.5);
    expect(FinanceSuitNavigationBar.notchDepthFactor, 0.45);
    expect(
      FinanceSuitNavigationBar.notchWidth,
      FinanceSuitNavigationBar.centerButtonDiameter * 1.5,
    );
    expect(
      FinanceSuitNavigationBar.notchDepth,
      FinanceSuitNavigationBar.centerButtonDiameter * 0.45,
    );
  });

  test('painted notch remains open and centered at every phone width', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      final path = FinanceSuitNavigationBar.surfacePathFor(
        Size(width, FinanceSuitNavigationBar.assemblyHeight),
      );
      final center = width / 2;
      final top = FinanceSuitNavigationBar.surfaceTop;
      final bottomOfBowl = top + FinanceSuitNavigationBar.notchDepth;

      expect(path.contains(Offset(center, top + 1)), isFalse);
      expect(path.contains(Offset(center, bottomOfBowl - 1)), isFalse);
      expect(path.contains(Offset(center, bottomOfBowl + 1)), isTrue);
      expect(path.contains(Offset(center - 50, top + 1)), isTrue);
      expect(path.contains(Offset(center + 50, top + 1)), isTrue);
    }
  });

  testWidgets('lays page content behind the transparent navigation wrapper', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());

    final shellScaffold = tester
        .widgetList<Scaffold>(find.byType(Scaffold))
        .firstWhere(
          (scaffold) =>
              scaffold.bottomNavigationBar is FinanceSuitNavigationBar,
        );
    // The shell body now extends under the transparent wrapper. Only each
    // page's scroll padding reserves its final tappable item above the bar.
    expect(shellScaffold.extendBody, isTrue);
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

  testWidgets('system Back sends every non-Home tab root to Home', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Reports')),
    );
    await tester.pumpAndSettle();
    expect(find.text('reports-root'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('first system Back on Home arms the close hint', (tester) async {
    await pumpShellApp(tester, buildShellTestRouter());

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('back again to close the app'), findsOneWidget);
    expect(find.text('home-root'), findsOneWidget);
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

  testWidgets('Money nested tab scrolling drives the shared header motion', (
    tester,
  ) async {
    await pumpShellApp(tester, buildShellTestRouter());
    await tester.tap(
      find.descendant(of: navBar(), matching: find.text('Money')),
    );
    await tester.pumpAndSettle();

    final surface = find.byKey(const Key('finance-suit-app-bar-surface'));
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      const EdgeInsetsDirectional.symmetric(horizontal: 16),
    );

    await tester.drag(
      find.byKey(const Key('money-root-scroll-0')),
      const Offset(0, -160),
    );
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      EdgeInsetsDirectional.zero,
    );

    await tester.drag(
      find.byKey(const Key('money-root-scroll-0')),
      const Offset(0, 200),
    );
    await tester.pump(const Duration(milliseconds: 240));
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      const EdgeInsetsDirectional.symmetric(horizontal: 16),
    );
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

  testWidgets('offers the update drawer once with Later and Update', (
    tester,
  ) async {
    AppShell.updatePromptShown = false;
    addTearDown(() => AppShell.updatePromptShown = false);
    final service = _FakeUpdateService(
      update: const PendingAppUpdate(availableVersionCode: 12),
    );
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: [appUpdateServiceProvider.overrideWithValue(service)],
    );

    expect(find.byKey(const Key('app-update-sheet')), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-update-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-update-sheet')), findsNothing);
    expect(service.startCalls, 0);
    // Same session: never offered again.
    expect(AppShell.updatePromptShown, isTrue);
  });

  testWidgets('the Update action starts the platform update flow', (
    tester,
  ) async {
    AppShell.updatePromptShown = false;
    addTearDown(() => AppShell.updatePromptShown = false);
    final service = _FakeUpdateService(
      update: const PendingAppUpdate(availableVersionCode: 12),
    );
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: [appUpdateServiceProvider.overrideWithValue(service)],
    );
    await tester.tap(find.byKey(const Key('app-update-now')));
    await tester.pumpAndSettle();
    expect(service.startCalls, 1);
  });

  testWidgets('no drawer when the app is up to date', (tester) async {
    AppShell.updatePromptShown = false;
    addTearDown(() => AppShell.updatePromptShown = false);
    await pumpShellApp(
      tester,
      buildShellTestRouter(),
      extraOverrides: [
        appUpdateServiceProvider.overrideWithValue(_FakeUpdateService()),
      ],
    );
    expect(find.byKey(const Key('app-update-sheet')), findsNothing);
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

  testWidgets('keeps the complete navigation assembly contained responsively', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 390.0, 430.0, 768.0]) {
      await tester.binding.setSurfaceSize(Size(width, 600));
      await pumpShellApp(tester, buildShellTestRouter());

      final appRect = tester.getRect(find.byType(MaterialApp));
      final barRect = tester.getRect(navBar());
      final addRect = tester.getRect(find.byKey(addButton));
      expect(barRect.left, greaterThanOrEqualTo(appRect.left));
      expect(barRect.right, lessThanOrEqualTo(appRect.right));
      expect(addRect.left, greaterThanOrEqualTo(appRect.left));
      expect(addRect.right, lessThanOrEqualTo(appRect.right));
      expect(addRect.bottom, lessThanOrEqualTo(appRect.bottom));
      expect(tester.takeException(), isNull, reason: 'width: $width');
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
