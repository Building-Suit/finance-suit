import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/routing/app_shell.dart';
import 'package:work_tracker/app/routing/global_add_sheet.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

Future<void> pumpSheet(
  WidgetTester tester, {
  List<TransactionMacro> macros = const [],
  ValueChanged<Object?>? onSelected,
  VoidCallback? onRetryMacros,
  AsyncValue<List<TransactionMacro>>? macrosState,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      locale: locale,
      theme: AppTheme.light(locale: locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final selected = await showModalBottomSheet<Object>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (context) => FractionallySizedBox(
                    heightFactor: 0.85,
                    child: GlobalAddSheet(
                      macros:
                          macrosState ??
                          AsyncData<List<TransactionMacro>>(macros),
                      onRetryMacros: onRetryMacros ?? () {},
                    ),
                  ),
                );
                onSelected?.call(selected);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> scrollSheetTo(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isNotEmpty) return;
  await tester.dragUntilVisible(
    target,
    find.byKey(const Key('global-add-list')),
    const Offset(0, -120),
    maxIteration: 40,
  );
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsAtLeastNWidgets(1));
}

Future<void> expandSection(WidgetTester tester, String label) async {
  final target = find.text(label);
  await scrollSheetTo(tester, target);
  await tester.tap(target.hitTestable().first);
  await tester.pumpAndSettle();
}

Future<void> tapSheetItem(WidgetTester tester, String label) async {
  final target = find.text(label);
  await scrollSheetTo(tester, target);
  await tester.tap(target.hitTestable().first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Money Control opens by default and only one section stays open',
    (tester) async {
      await pumpSheet(tester);

      expect(find.text('Money Control'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('New account'), findsOneWidget);
      expect(find.text('New held amount'), findsOneWidget);
      expect(find.text('New category'), findsOneWidget);
      expect(find.text('Add work entry'), findsNothing);
      expect(find.text('Add automation'), findsNothing);
      expect(find.text('New macro'), findsNothing);

      await expandSection(tester, 'Work Control');
      expect(find.text('Expense'), findsNothing);
      expect(find.text('Add work entry'), findsOneWidget);
      expect(find.text('New holiday'), findsOneWidget);
      expect(find.text('New adjustment'), findsOneWidget);

      await expandSection(tester, 'Automation Control');
      expect(find.text('Add work entry'), findsNothing);
      expect(find.text('Add automation'), findsOneWidget);
      expect(find.text('Manage automations'), findsOneWidget);

      await expandSection(tester, 'Macros');
      expect(find.text('Add work entry'), findsNothing);
      expect(find.text('New macro'), findsOneWidget);
      expect(find.text('Manage macros'), findsOneWidget);
    },
  );

  testWidgets('accordion content has a readable horizontal inset', (
    tester,
  ) async {
    await pumpSheet(tester);

    const expectedPadding = EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8);

    final moneyTile = tester.widget<ExpansionTile>(
      find.byKey(const Key('global-add-money-control')),
    );
    expect(moneyTile.childrenPadding, expectedPadding);

    final moneyRect = tester.getRect(
      find.byKey(const Key('global-add-money-control')),
    );
    final expenseTile = find.ancestor(
      of: find.text('Expense'),
      matching: find.byType(ListTile),
    );
    final expenseRect = tester.getRect(expenseTile.first);

    expect(expenseRect.left, greaterThanOrEqualTo(moneyRect.left + 16));
    expect(expenseRect.right, lessThanOrEqualTo(moneyRect.right - 16));

    await expandSection(tester, 'Work Control');
    final workTile = tester.widget<ExpansionTile>(
      find.byKey(const Key('global-add-work-control')),
    );
    expect(workTile.childrenPadding, expectedPadding);

    await expandSection(tester, 'Automation Control');
    final automationTile = tester.widget<ExpansionTile>(
      find.byKey(const Key('global-add-automation-control')),
    );
    expect(automationTile.childrenPadding, expectedPadding);

    await expandSection(tester, 'Macros');
    final macrosTile = tester.widget<ExpansionTile>(
      find.byKey(const Key('global-add-macros')),
    );
    expect(macrosTile.childrenPadding, expectedPadding);
  });

  testWidgets('every static Add action returns its exact route', (
    tester,
  ) async {
    const cases = [
      (section: '', label: 'Expense', route: '/money/tx/new?kind=expense'),
      (
        section: '',
        label: 'Allowance',
        route: '/money/tx/new?kind=allowance_given',
      ),
      (
        section: '',
        label: 'Other income',
        route: '/money/tx/new?kind=custom_income',
      ),
      (
        section: '',
        label: 'Freelance income',
        route: '/money/tx/new?kind=freelance_income',
      ),
      (section: '', label: 'Transfer', route: '/money/transfer'),
      (section: '', label: 'New held amount', route: '/money/held/new'),
      (section: '', label: 'New account', route: '/money/accounts/new'),
      (section: '', label: 'New category', route: '/money/categories/new'),
      (
        section: 'Work Control',
        label: 'Add work entry',
        route: '/work/entry/new',
      ),
      (
        section: 'Automation Control',
        label: 'Add automation',
        route: '/settings/income-sources/new',
      ),
      (
        section: 'Automation Control',
        label: 'Manage automations',
        route: '/settings/income-sources',
      ),
      (
        section: 'Work Control',
        label: 'New holiday',
        route: '/work/holidays/new',
      ),
      (
        section: 'Work Control',
        label: 'New adjustment',
        route: '/work/adjustments/new',
      ),
      (section: 'Macros', label: 'New macro', route: '/money/macros/new'),
      (section: 'Macros', label: 'Manage macros', route: '/money/macros'),
    ];

    for (final routeCase in cases) {
      Object? selection;
      await pumpSheet(tester, onSelected: (value) => selection = value);
      if (routeCase.section.isNotEmpty) {
        await expandSection(tester, routeCase.section);
      }
      await tapSheetItem(tester, routeCase.label);
      expect(selection, routeCase.route, reason: routeCase.label);
    }
  });

  testWidgets('reversible macro exposes both directions', (tester) async {
    Object? selection;
    const macro = TransactionMacro(
      id: 'macro-1',
      name: 'Work',
      items: [
        TransactionMacroItem(
          kind: TransactionKind.transfer,
          amountMinor: 100,
          isReversible: true,
        ),
      ],
    );
    await pumpSheet(
      tester,
      macros: const [macro],
      onSelected: (value) => selection = value,
    );

    await expandSection(tester, 'Macros');
    expect(find.text('To Work'), findsOneWidget);
    expect(find.text('From Work'), findsOneWidget);

    await tapSheetItem(tester, 'From Work');
    expect(selection, (macroId: 'macro-1', reverse: true));
  });

  testWidgets('all section actions remain reachable on a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpSheet(tester);

    await expandSection(tester, 'Work Control');
    await scrollSheetTo(tester, find.text('New adjustment'));
    expect(find.text('New adjustment'), findsOneWidget);

    await expandSection(tester, 'Automation Control');
    await scrollSheetTo(tester, find.text('Manage automations'));
    expect(find.text('Manage automations'), findsOneWidget);

    await expandSection(tester, 'Macros');
    await scrollSheetTo(tester, find.text('Manage macros'));
    expect(find.text('Manage macros'), findsOneWidget);
  });

  testWidgets(
    'automation accordion is reachable in Arabic RTL without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpSheet(tester, locale: const Locale('ar'));

      await expandSection(tester, 'التحكم في الأتمتة');
      await scrollSheetTo(tester, find.text('إدارة الأتمتة'));
      expect(find.text('إضافة أتمتة'), findsOneWidget);
      expect(find.text('إدارة الأتمتة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('macro loading and retry states stay visible', (tester) async {
    var retried = false;
    await pumpSheet(
      tester,
      macrosState: const AsyncLoading<List<TransactionMacro>>(),
      onRetryMacros: () => retried = true,
    );
    await scrollSheetTo(tester, find.text('Macros'));
    await tester.tap(find.text('Macros').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pumpSheet(
      tester,
      macrosState: AsyncError<List<TransactionMacro>>(
        Exception('failed'),
        StackTrace.empty,
      ),
      onRetryMacros: () => retried = true,
    );
    await expandSection(tester, 'Macros');
    await scrollSheetTo(tester, find.byTooltip('Retry'));
    await tester.tap(find.byTooltip('Retry').hitTestable());
    expect(retried, isTrue);
  });

  test('global Add is hidden on forms and preserves salary context', () {
    expect(
      AppShell.shouldShowGlobalAdd(branchIndex: 2, location: '/money'),
      isTrue,
    );
    expect(
      AppShell.shouldShowGlobalAdd(
        branchIndex: 2,
        location: '/money/categories/new',
      ),
      isFalse,
    );
    expect(
      AppShell.shouldShowGlobalAdd(
        branchIndex: 2,
        location: '/money/accounts/account-1',
      ),
      isFalse,
    );
    expect(
      AppShell.shouldShowGlobalAdd(branchIndex: 4, location: '/settings'),
      isFalse,
    );
    expect(
      AppShell.salaryAdjustmentRoute('/work/periods/period-1'),
      '/work/adjustments/new?periodId=period-1',
    );
  });
}
