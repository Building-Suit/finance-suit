import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The Money tab's transaction list: filterable and endless.
///
/// The first page comes from [transactionsPageProvider], so any edit,
/// realtime event, or refresh rebuilds the list from the top on its own.
/// Further pages are pulled in as the user approaches the end of the list
/// and are dropped whenever the filters or the first page change.
class TransactionsSection extends ConsumerStatefulWidget {
  const TransactionsSection({super.key, required this.onOpenTransaction});

  final void Function(FinancialTransaction transaction) onOpenTransaction;

  @override
  ConsumerState<TransactionsSection> createState() =>
      _TransactionsSectionState();
}

class _TransactionsSectionState extends ConsumerState<TransactionsSection> {
  static const _pageSize = 30;

  final _scrollController = ScrollController();
  final _keywordController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  /// Null preset means every date — the list opens complete and a range is
  /// an explicit narrowing, never a default that quietly hides rows.
  DateRangePreset? _preset;
  TransactionFilterKind _kind = TransactionFilterKind.all;
  String? _accountId;
  String? _categoryId;
  String? _keyword;
  int? _minAmountMinor;
  int? _maxAmountMinor;

  /// Pages beyond the first, in order.
  final List<FinancialTransaction> _more = [];

  /// The first page the tail was appended to. A newly loaded first page is a
  /// different instance, which is what makes the tail stale.
  TransactionPage? _pagedFrom;
  bool _loadingMore = false;
  bool _moreExhausted = false;
  AppFailure? _moreFailure;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _keywordController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  TransactionQuery get _query => TransactionQuery(
    range: _preset == null ? null : rangeForPreset(_preset!, PlainDate.today()),
    kind: _kind,
    accountId: _accountId,
    categoryId: _categoryId,
    keyword: _keyword,
    minAmountMinor: _minAmountMinor,
    maxAmountMinor: _maxAmountMinor,
    limit: _pageSize,
  );

  /// Any filter change invalidates the accumulated tail.
  void _resetPaging() {
    setState(_clearTail);
  }

  void _clearTail() {
    _more.clear();
    _pagedFrom = null;
    _loadingMore = false;
    _moreExhausted = false;
    _moreFailure = null;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Start the next page while roughly two screens remain, so the list
    // stays ahead of the user instead of stalling at the bottom.
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  /// Fetches the page after the last row on screen. Later pages go through
  /// the same provider as the first, keyed by a query that carries the
  /// cursor, so there is one loading path and one place to fake in tests.
  Future<void> _loadMore() async {
    if (_loadingMore || _moreExhausted) return;
    final firstPage = ref.read(transactionsPageProvider(_query)).value;
    if (firstPage == null) return;
    final last = _more.isNotEmpty ? _more.last : firstPage.items.lastOrNull;
    if (last == null) return;
    final cursor = TransactionCursor.after(last);
    if (cursor == null) {
      setState(() => _moreExhausted = true);
      return;
    }
    setState(() {
      _loadingMore = true;
      _moreFailure = null;
    });
    // The page provider auto-disposes, so hold a manual subscription for the
    // duration of the await; without one the provider is torn down before it
    // resolves and the future never completes.
    final pageProvider = transactionsPageProvider(
      _query.copyWith(cursor: () => cursor),
    );
    final subscription = ref.listenManual(pageProvider, (_, _) {});
    try {
      final page = await ref.read(pageProvider.future);
      if (!mounted) return;
      setState(() {
        _pagedFrom = firstPage;
        _more.addAll(page.items);
        _loadingMore = false;
        _moreExhausted = !page.hasMore;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailure = failure;
      });
    } finally {
      subscription.close();
    }
  }

  int? _amountMinor(String input, String currencyCode) {
    final text = input.trim();
    if (text.isEmpty) return null;
    return Money.tryParse(text, currencyCode: currencyCode)?.minor;
  }

  void _applyAdvanced(String currencyCode) {
    setState(() {
      _keyword = _keywordController.text.trim().isEmpty
          ? null
          : _keywordController.text.trim();
      _minAmountMinor = _amountMinor(_minController.text, currencyCode);
      _maxAmountMinor = _amountMinor(_maxController.text, currencyCode);
    });
    _resetPaging();
  }

  void _clearFilters() {
    _keywordController.clear();
    _minController.clear();
    _maxController.clear();
    setState(() {
      _preset = null;
      _kind = TransactionFilterKind.all;
      _accountId = null;
      _categoryId = null;
      _keyword = null;
      _minAmountMinor = null;
      _maxAmountMinor = null;
    });
    _resetPaging();
  }

  String _rangeLabel(AppLocalizations l10n, DateRangePreset? preset) =>
      switch (preset) {
        null => l10n.commonAll,
        DateRangePreset.today => l10n.rangeToday,
        DateRangePreset.last7Days => l10n.rangeLast7,
        DateRangePreset.last30Days => l10n.rangeLast30,
        DateRangePreset.currentMonth => l10n.rangeCurrentMonth,
        DateRangePreset.previousMonth => l10n.rangePreviousMonth,
        DateRangePreset.last90Days => l10n.rangeLast90,
        DateRangePreset.currentYear => l10n.rangeCurrentYear,
        DateRangePreset.custom => l10n.historyCustomRange,
      };

  String _kindLabel(AppLocalizations l10n, TransactionFilterKind kind) =>
      switch (kind) {
        TransactionFilterKind.all => l10n.commonAll,
        TransactionFilterKind.expense => transactionKindLabel(
          l10n,
          TransactionKind.expense,
        ),
        TransactionFilterKind.allowanceGiven => transactionKindLabel(
          l10n,
          TransactionKind.allowanceGiven,
        ),
        TransactionFilterKind.income => l10n.reportIncome,
        TransactionFilterKind.transfer => transactionKindLabel(
          l10n,
          TransactionKind.transfer,
        ),
      };

  static const _rangePresets = <DateRangePreset?>[
    null,
    DateRangePreset.today,
    DateRangePreset.last7Days,
    DateRangePreset.last30Days,
    DateRangePreset.currentMonth,
    DateRangePreset.previousMonth,
    DateRangePreset.last90Days,
    DateRangePreset.currentYear,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query;
    final firstPageAsync = ref.watch(transactionsPageProvider(query));
    final accounts =
        ref.watch(allAccountBalancesProvider).value ?? const <AccountBalance>[];
    final categories =
        ref.watch(allCategoriesProvider).value ?? const <TransactionCategory>[];
    final accountNames = {
      for (final account in accounts) account.accountId: account.name,
    };
    final currencyCode = accounts.firstOrNull?.currencyCode ?? 'EGP';

    // A reloaded first page — an edit, a realtime event, a refresh — is a
    // different instance, so whatever was scrolled in behind it is stale.
    // Cleared during build rather than through setState, because this only
    // drops a derived cache and must not schedule another frame.
    final loadedFirstPage = firstPageAsync.value;
    if (_more.isNotEmpty &&
        loadedFirstPage != null &&
        !identical(loadedFirstPage, _pagedFrom)) {
      _clearTail();
    }

    return Column(
      children: [
        _FilterBar(
          presets: _rangePresets,
          selectedPreset: _preset,
          presetLabel: (preset) => _rangeLabel(l10n, preset),
          onPresetSelected: (preset) {
            setState(() => _preset = preset);
            _resetPaging();
          },
          selectedKind: _kind,
          kindLabel: (kind) => _kindLabel(l10n, kind),
          onKindSelected: (kind) {
            setState(() => _kind = kind);
            _resetPaging();
          },
          accounts: accounts,
          categories: categories,
          accountId: _accountId,
          categoryId: _categoryId,
          keywordController: _keywordController,
          minController: _minController,
          maxController: _maxController,
          onAccountChanged: (value) {
            setState(() => _accountId = value);
            _resetPaging();
          },
          onCategoryChanged: (value) {
            setState(() => _categoryId = value);
            _resetPaging();
          },
          onApply: () => _applyAdvanced(currencyCode),
          onClear: query.hasActiveFilters ? _clearFilters : null,
        ),
        Expanded(
          child: AsyncView<TransactionPage>(
            value: firstPageAsync,
            onRetry: () => ref.invalidate(transactionsPageProvider(query)),
            data: (page) {
              final items = [...page.items, ..._more];
              if (items.isEmpty) {
                return EmptyStateView(
                  icon: FinanceSuitIcons.receiptLong,
                  message: query.hasActiveFilters
                      ? l10n.txFilterNoMatches
                      : l10n.moneyNoTransactions,
                );
              }
              final hasMore = _more.isEmpty ? page.hasMore : !_moreExhausted;
              return RefreshIndicator(
                onRefresh: () async {
                  _resetPaging();
                  ref.invalidate(transactionsPageProvider(query));
                },
                child: ListView.builder(
                  key: const Key('transactions-list'),
                  controller: _scrollController,
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      return _ListFooter(
                        hasMore: hasMore,
                        loading: _loadingMore,
                        failure: _moreFailure,
                        onRetry: _loadMore,
                      );
                    }
                    final transaction = items[index];
                    return TransactionTile(
                      transaction: transaction,
                      accountNames: accountNames,
                      onTap: () => widget.onOpenTransaction(transaction),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Bottom of the list: the endless-scroll spinner, a retry when a page
/// failed, or just the space the floating add button needs.
class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.hasMore,
    required this.loading,
    required this.failure,
    required this.onRetry,
  });

  final bool hasMore;
  final bool loading;
  final AppFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        child: OutlinedButton.icon(
          key: const Key('transactions-load-more-retry'),
          onPressed: onRetry,
          icon: const FinanceSuitIcon(FinanceSuitIcons.refresh),
          label: Text(l10n.commonRetry),
        ),
      );
    }
    if (!hasMore) return const SizedBox(height: 88);
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 88),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          key: Key('transactions-loading-more'),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.presets,
    required this.selectedPreset,
    required this.presetLabel,
    required this.onPresetSelected,
    required this.selectedKind,
    required this.kindLabel,
    required this.onKindSelected,
    required this.accounts,
    required this.categories,
    required this.accountId,
    required this.categoryId,
    required this.keywordController,
    required this.minController,
    required this.maxController,
    required this.onAccountChanged,
    required this.onCategoryChanged,
    required this.onApply,
    required this.onClear,
  });

  final List<DateRangePreset?> presets;
  final DateRangePreset? selectedPreset;
  final String Function(DateRangePreset? preset) presetLabel;
  final void Function(DateRangePreset? preset) onPresetSelected;
  final TransactionFilterKind selectedKind;
  final String Function(TransactionFilterKind kind) kindLabel;
  final void Function(TransactionFilterKind kind) onKindSelected;
  final List<AccountBalance> accounts;
  final List<TransactionCategory> categories;
  final String? accountId;
  final String? categoryId;
  final TextEditingController keywordController;
  final TextEditingController minController;
  final TextEditingController maxController;
  final void Function(String? value) onAccountChanged;
  final void Function(String? value) onCategoryChanged;
  final VoidCallback onApply;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in presets)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      key: Key('tx-range-${preset?.name ?? 'all'}'),
                      label: Text(presetLabel(preset)),
                      selected: selectedPreset == preset,
                      onSelected: (_) => onPresetSelected(preset),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final kind in TransactionFilterKind.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      key: Key('tx-kind-${kind.name}'),
                      label: Text(kindLabel(kind)),
                      selected: selectedKind == kind,
                      onSelected: (_) => onKindSelected(kind),
                    ),
                  ),
              ],
            ),
          ),
          ExpansionTile(
            key: const Key('tx-advanced-filters'),
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.txMoreFilters),
            children: [
              AppSelectionField<String?>(
                key: ValueKey('tx-filter-account-$accountId'),
                initialValue: accountId,
                decoration: InputDecoration(labelText: l10n.txAccount),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.commonAll)),
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.accountId,
                      child: Text(account.name),
                    ),
                ],
                onChanged: onAccountChanged,
              ),
              const SizedBox(height: 8),
              AppSelectionField<String?>(
                key: ValueKey('tx-filter-category-$categoryId'),
                initialValue: categoryId,
                decoration: InputDecoration(labelText: l10n.txCategory),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.commonAll)),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: onCategoryChanged,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('tx-filter-keyword'),
                controller: keywordController,
                decoration: InputDecoration(
                  labelText: l10n.txTitleField,
                  prefixIcon: const FinanceSuitIcon(FinanceSuitIcons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onApply(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('tx-filter-min'),
                      controller: minController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: '${l10n.commonAmount} min',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('tx-filter-max'),
                      controller: maxController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: '${l10n.commonAmount} max',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onClear != null)
                    TextButton(
                      key: const Key('tx-filter-clear'),
                      onPressed: onClear,
                      child: Text(l10n.txClearFilters),
                    ),
                  FilledButton.icon(
                    key: const Key('tx-filter-apply'),
                    onPressed: onApply,
                    icon: const FinanceSuitIcon(FinanceSuitIcons.check),
                    label: Text(l10n.commonApply),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
