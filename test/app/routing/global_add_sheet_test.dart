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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
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

Future<void> expandSection(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label).first,
    200,
    scrollable: find.byType(ListView),
  );
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

Future<void> tapSheetItem(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label).last,
    200,
    scrollable: find.byType(ListView),
  );
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Money Control is expanded and other sections start collapsed', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('Money Control'), findsOneWidget);
    expect(find.text('Work Control'), findsOneWidget);
    expect(find.text('Macros'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('New account'), findsOneWidget);
    expect(find.text('New held amount'), findsOneWidget);
    expect(find.text('New category'), findsOneWidget);
    expect(find.text('Add work entry'), findsNothing);
    expect(find.text('New macro'), findsNothing);

    await expandSection(tester, 'Work Control');
    expect(find.text('Add work entry'), findsOneWidget);
    expect(find.text('New holiday'), findsOneWidget);
    expect(find.text('New adjustment'), findsOneWidget);

    await expandSection(tester, 'Macros');
    expect(find.text('New macro'), findsOneWidget);
    expect(find.text('Manage macros'), findsOneWidget);
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
    await tester.scrollUntilVisible(
      find.text('New adjustment'),
      200,
      scrollable: find.byType(ListView),
    );
    expect(find.text('New adjustment'), findsOneWidget);

    await expandSection(tester, 'Macros');
    await tester.scrollUntilVisible(
      find.text('Manage macros'),
      200,
      scrollable: find.byType(ListView),
    );
    expect(find.text('Manage macros'), findsOneWidget);
  });

  testWidgets('macro loading and retry states stay visible', (tester) async {
    var retried = false;
    await pumpSheet(
      tester,
      macrosState: const AsyncLoading<List<TransactionMacro>>(),
      onRetryMacros: () => retried = true,
    );
    await tester.scrollUntilVisible(
      find.text('Macros'),
      200,
      scrollable: find.byType(ListView),
    );
    await tester.tap(find.text('Macros'));
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
    await tester.scrollUntilVisible(
      find.byTooltip('Retry'),
      200,
      scrollable: find.byType(ListView),
    );
    await tester.tap(find.byTooltip('Retry'));
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
