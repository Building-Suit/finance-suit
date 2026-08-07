import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/transactions_section.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

const _wallet = AccountBalance(
  accountId: 'asset-1',
  name: 'Main Wallet',
  accountType: AccountType.cash,
  currencyCode: 'EGP',
  isDefault: true,
  isArchived: false,
  allowNegativeBalance: false,
  openingBalanceMinor: 0,
  balanceMinor: 100000,
  totalIncomingMinor: 100000,
  totalOutgoingMinor: 0,
);

const _category = TransactionCategory(
  id: 'cat-1',
  name: 'Shopping',
  kind: CategoryKind.expense,
  icon: 'category',
  sortOrder: 0,
  isArchived: false,
);

FinancialTransaction _tx(int index, {TransactionKind? kind}) =>
    FinancialTransaction(
      id: 'tx-$index',
      kind: kind ?? TransactionKind.expense,
      occurredOn: PlainDate.parse('2026-08-01'),
      amountMinor: 1000 + index,
      currencyCode: 'EGP',
      sourceAccountId: 'asset-1',
      categoryId: 'cat-1',
      title: 'Item $index',
      sortAt: DateTime.utc(2026, 8, 1, 12, 0, index),
    );

/// Serves pages from a synthetic ledger so paging and filtering can be
/// exercised without a network. Every page — the first and each one
/// scrolled in — arrives through the same provider the screen uses.
class _FakeLedger {
  _FakeLedger({required this.pageSize, required this.total});

  final int pageSize;
  final int total;
  final List<TransactionQuery> queries = [];
  final List<TransactionQuery> countQueries = [];

  TransactionPage page(TransactionQuery input) {
    queries.add(input);
    final startIndex = input.cursor == null
        ? 0
        : int.parse(input.cursor!.id.split('-').last) + 1;
    final end = (startIndex + pageSize).clamp(0, total);
    return TransactionPage(
      items: [
        for (var i = startIndex; i < end; i++)
          _tx(i, kind: input.kind.kinds.firstOrNull ?? TransactionKind.expense),
      ],
      hasMore: end < total,
    );
  }

  /// A count that visibly differs once any non-date filter is active, so
  /// tests can prove the sheet's live preview actually reacts.
  int count(TransactionQuery input) {
    countQueries.add(input);
    return input.hasActiveFilters ? 7 : total;
  }
}

/// Pumps a fixed number of frames instead of settling: while more pages
/// exist the footer shows a progress indicator, which never settles.
Future<void> _frames(WidgetTester tester, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Drags until the list stops asking for pages. The trailing spinner is a
/// lazy list item and is not built while off screen, so the request count is
/// the reliable signal that paging has finished.
Future<void> _scrollToEnd(WidgetTester tester, _FakeLedger ledger) async {
  var previous = -1;
  var rounds = 0;
  while (ledger.queries.length != previous && rounds < 10) {
    previous = ledger.queries.length;
    rounds++;
    await tester.drag(
      find.byKey(const Key('transactions-list')),
      const Offset(0, -2000),
    );
    await _frames(tester);
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  _FakeLedger ledger, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('user-1'),
        transactionsPageProvider.overrideWith(
          (ref, query) async => ledger.page(query),
        ),
        transactionsCountProvider.overrideWith(
          (ref, query) async => ledger.count(query),
        ),
        allAccountBalancesProvider.overrideWith((ref) async => const [_wallet]),
        allCategoriesProvider.overrideWith((ref) async => const [_category]),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TransactionsSection(onOpenTransaction: (_) {})),
      ),
    ),
  );
  await _frames(tester);
}

/// Opens the filter sheet and settles the frame that mounts it.
Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tx-open-filters')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the filter bar', () {
    testWidgets(
      'shows only the date range row plus a Filters button, no kind chips',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final ledger = _FakeLedger(pageSize: 30, total: 10);
        await _pump(tester, ledger);

        expect(find.byKey(const Key('tx-range-all')), findsOneWidget);
        expect(find.byKey(const Key('tx-range-last30Days')), findsOneWidget);
        expect(find.byKey(const Key('tx-open-filters')), findsOneWidget);
        // The kind chips used to sit in a second row of the bar; they now
        // live inside the sheet and are absent until it opens.
        expect(find.byKey(const Key('tx-kind-expense')), findsNothing);
        expect(find.byKey(const Key('tx-filter-account-null')), findsNothing);
      },
    );
  });

  group('endless scroll', () {
    testWidgets('the list loads the next page as it is scrolled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 75);
      await _pump(tester, ledger);

      expect(find.text('Item 0'), findsOneWidget);
      expect(ledger.queries.where((q) => q.cursor != null), isEmpty);

      await _scrollToEnd(tester, ledger);

      final paged = ledger.queries.where((q) => q.cursor != null).toList();
      expect(paged, isNotEmpty);
      expect(paged.first.cursor!.id, 'tx-29');
      expect(paged.length, 2);
      expect(find.text('Item 74'), findsOneWidget);
    });

    testWidgets('the end of the list stops requesting pages', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 10, total: 12);
      await _pump(tester, ledger);

      await _scrollToEnd(tester, ledger);
      final requestsAfterEnd = ledger.queries.length;

      await _scrollToEnd(tester, ledger);

      expect(ledger.queries.length, requestsAfterEnd);
      expect(find.byKey(const Key('transactions-loading-more')), findsNothing);
    });
  });

  group('date range', () {
    testWidgets('a date range chip reaches the query directly', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 30);
      await _pump(tester, ledger);

      // The list opens unfiltered: every date, every kind.
      expect(ledger.queries.first.range, isNull);
      expect(ledger.queries.first.hasActiveFilters, isFalse);

      await tester.ensureVisible(find.byKey(const Key('tx-range-last30Days')));
      await tester.tap(find.byKey(const Key('tx-range-last30Days')));
      await _frames(tester);

      expect(ledger.queries.last.range, isNotNull);
      expect(ledger.queries.last.hasActiveFilters, isTrue);
    });
  });

  group('filter sheet', () {
    testWidgets('opens on demand with the kind chips and every field', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 30);
      await _pump(tester, ledger);

      await _openFilters(tester);

      expect(find.byKey(const Key('tx-kind-all')), findsOneWidget);
      expect(find.byKey(const Key('tx-kind-expense')), findsOneWidget);
      expect(find.byKey(const Key('tx-kind-transfer')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-account-null')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-category-null')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-keyword')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-min')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-max')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-apply')), findsOneWidget);
      expect(find.byKey(const Key('tx-filter-clear')), findsOneWidget);
    });

    testWidgets('selecting a kind chip narrows the query and resets paging', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 75);
      await _pump(tester, ledger);

      await _scrollToEnd(tester, ledger);
      expect(find.text('Item 74'), findsOneWidget);

      await _openFilters(tester);
      await tester.tap(find.byKey(const Key('tx-kind-transfer')));
      await _frames(tester);
      await tester.tap(find.byKey(const Key('tx-filter-apply')));
      await _frames(tester);

      final last = ledger.queries.last;
      expect(last.kind, TransactionFilterKind.transfer);
      // The tail scrolled in under the old filter is gone.
      expect(last.cursor, isNull);
      expect(find.text('Item 74'), findsNothing);
    });

    testWidgets('the Apply button shows a live match count as filters change', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 42);
      await _pump(tester, ledger);

      await _openFilters(tester);
      // Nothing changed yet: the preview matches the parent's own filters.
      expect(find.text('Apply (42)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tx-kind-expense')));
      await _frames(tester);
      // Chip selections are not debounced.
      expect(find.text('Apply (7)'), findsOneWidget);
    });

    testWidgets(
      'typed keyword and amount debounce before the count reacts, but '
      'Apply always uses exactly what was typed',
      (tester) async {
        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final ledger = _FakeLedger(pageSize: 30, total: 42);
        await _pump(tester, ledger);

        await _openFilters(tester);
        await tester.enterText(
          find.byKey(const Key('tx-filter-keyword')),
          'taxi',
        );
        await tester.pump(const Duration(milliseconds: 100));
        // Still mid-debounce: the preview has not moved yet.
        expect(find.text('Apply (42)'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 300));
        // One more frame lets the now-resolved count Future notify and
        // rebuild the sheet.
        await tester.pump();
        // The debounce settled: the preview now reflects the typed filter.
        expect(find.text('Apply (7)'), findsOneWidget);

        // Tapping Apply immediately after more typing — inside one
        // debounce window — must still carry exactly what was typed, not
        // whatever the last-settled preview happened to be.
        await tester.enterText(find.byKey(const Key('tx-filter-min')), '10');
        await tester.tap(find.byKey(const Key('tx-filter-apply')));
        await _frames(tester);

        expect(ledger.queries.last.keyword, 'taxi');
        expect(ledger.queries.last.minAmountMinor, 1000);
      },
    );

    testWidgets('keyword and amount filters apply together', (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 30);
      await _pump(tester, ledger);

      await _openFilters(tester);
      await tester.enterText(
        find.byKey(const Key('tx-filter-keyword')),
        'taxi',
      );
      await tester.enterText(find.byKey(const Key('tx-filter-min')), '10');
      await tester.enterText(find.byKey(const Key('tx-filter-max')), '250');
      await tester.tap(find.byKey(const Key('tx-filter-apply')));
      await _frames(tester);

      final last = ledger.queries.last;
      expect(last.keyword, 'taxi');
      expect(last.minAmountMinor, 1000);
      expect(last.maxAmountMinor, 25000);

      // Reopening the sheet carries the committed filters forward as its
      // starting point, and Clear resets just this session's selections.
      await _openFilters(tester);
      await tester.tap(find.byKey(const Key('tx-filter-clear')));
      await _frames(tester);
      await tester.tap(find.byKey(const Key('tx-filter-apply')));
      await _frames(tester);

      expect(ledger.queries.last.hasActiveFilters, isFalse);
    });

    testWidgets('dismissing the sheet without applying keeps the list as-is', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 30);
      await _pump(tester, ledger);
      final requestsBefore = ledger.queries.length;

      await _openFilters(tester);
      await tester.tap(find.byKey(const Key('tx-kind-transfer')));
      await _frames(tester);
      // Back out (tap the barrier) instead of applying.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tx-kind-transfer')), findsNothing);
      expect(ledger.queries.length, requestsBefore);
    });
  });

  group('empty states', () {
    testWidgets('an empty filtered result says so', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 30, total: 0);
      await _pump(tester, ledger);

      expect(find.text('No transactions yet.'), findsOneWidget);

      await _openFilters(tester);
      await tester.tap(find.byKey(const Key('tx-kind-expense')));
      await _frames(tester);
      await tester.tap(find.byKey(const Key('tx-filter-apply')));
      await _frames(tester);

      expect(find.text('No transactions match these filters.'), findsOneWidget);
    });
  });

  group('right-to-left', () {
    testWidgets('the filter bar and sheet fit a small Arabic viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ledger = _FakeLedger(pageSize: 10, total: 10);
      await _pump(tester, ledger, locale: const Locale('ar'));

      expect(find.byKey(const Key('transactions-list')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _openFilters(tester);
      expect(find.byKey(const Key('tx-filter-apply')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
