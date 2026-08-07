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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the list loads the next page as it is scrolled', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = _FakeLedger(pageSize: 30, total: 75);
    await _pump(tester, ledger);

    // Page one only, and no request has carried a cursor yet.
    expect(find.text('Item 0'), findsOneWidget);
    expect(ledger.queries.where((q) => q.cursor != null), isEmpty);

    await _scrollToEnd(tester, ledger);

    // Scrolling asked for more, keyed on the last row rather than an offset,
    // and kept going until the final row was reachable.
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

  testWidgets('a kind filter narrows the query and resets paging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = _FakeLedger(pageSize: 30, total: 75);
    await _pump(tester, ledger);

    await _scrollToEnd(tester, ledger);
    expect(find.text('Item 74'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('tx-kind-transfer')));
    await tester.tap(find.byKey(const Key('tx-kind-transfer')));
    await _frames(tester);

    final last = ledger.queries.last;
    expect(last.kind, TransactionFilterKind.transfer);
    // The tail scrolled in under the old filter is gone.
    expect(last.cursor, isNull);
    expect(find.text('Item 74'), findsNothing);
  });

  testWidgets('a date range filter reaches the query', (tester) async {
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

  testWidgets('keyword and amount filters apply together', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = _FakeLedger(pageSize: 30, total: 30);
    await _pump(tester, ledger);

    await tester.tap(find.byKey(const Key('tx-advanced-filters')));
    await tester.pumpAndSettle();
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('tx-filter-keyword')), 'taxi');
    await tester.enterText(find.byKey(const Key('tx-filter-min')), '10');
    await tester.enterText(find.byKey(const Key('tx-filter-max')), '250');
    await tester.tap(find.byKey(const Key('tx-filter-apply')));
    await _frames(tester);

    final last = ledger.queries.last;
    expect(last.keyword, 'taxi');
    expect(last.minAmountMinor, 1000);
    expect(last.maxAmountMinor, 25000);

    await tester.tap(find.byKey(const Key('tx-filter-clear')));
    await _frames(tester);

    expect(ledger.queries.last.hasActiveFilters, isFalse);
  });

  testWidgets('an empty filtered result says so', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = _FakeLedger(pageSize: 30, total: 0);
    await _pump(tester, ledger);

    expect(find.text('No transactions yet.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('tx-kind-expense')));
    await tester.tap(find.byKey(const Key('tx-kind-expense')));
    await _frames(tester);

    expect(find.text('No transactions match these filters.'), findsOneWidget);
  });

  testWidgets('the filter bar fits a small Arabic viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ledger = _FakeLedger(pageSize: 10, total: 10);
    await _pump(tester, ledger, locale: const Locale('ar'));

    expect(find.byKey(const Key('transactions-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
