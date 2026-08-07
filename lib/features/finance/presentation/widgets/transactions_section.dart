import 'dart:async';

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
    super.dispose();
  }

  DateRange? get _range =>
      _preset == null ? null : rangeForPreset(_preset!, PlainDate.today());

  TransactionQuery get _query => TransactionQuery(
    range: _range,
    kind: _kind,
    accountId: _accountId,
    categoryId: _categoryId,
    keyword: _keyword,
    minAmountMinor: _minAmountMinor,
    maxAmountMinor: _maxAmountMinor,
    limit: _pageSize,
  );

  /// Whether any filter besides the date range is active, so the trigger
  /// button can show the user it is hiding something.
  bool get _hasDrawerFilters =>
      _kind != TransactionFilterKind.all ||
      _accountId != null ||
      _categoryId != null ||
      (_keyword?.trim().isNotEmpty ?? false) ||
      _minAmountMinor != null ||
      _maxAmountMinor != null;

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

  Future<void> _openFilterSheet() async {
    final draft = await showModalBottomSheet<_FilterDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _FilterSheet(
        baseRange: _range,
        initial: _FilterDraft(
          kind: _kind,
          accountId: _accountId,
          categoryId: _categoryId,
          keyword: _keyword,
          minAmountMinor: _minAmountMinor,
          maxAmountMinor: _maxAmountMinor,
        ),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _kind = draft.kind;
      _accountId = draft.accountId;
      _categoryId = draft.categoryId;
      _keyword = draft.keyword;
      _minAmountMinor = draft.minAmountMinor;
      _maxAmountMinor = draft.maxAmountMinor;
    });
    _resetPaging();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query;
    final firstPageAsync = ref.watch(transactionsPageProvider(query));
    final accounts =
        ref.watch(allAccountBalancesProvider).value ?? const <AccountBalance>[];
    final accountNames = {
      for (final account in accounts) account.accountId: account.name,
    };

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
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final preset in _rangePresets)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            key: Key('tx-range-${preset?.name ?? 'all'}'),
                            label: Text(_rangeLabel(l10n, preset)),
                            selected: _preset == preset,
                            onSelected: (_) {
                              setState(() => _preset = preset);
                              _resetPaging();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(
                active: _hasDrawerFilters,
                onPressed: _openFilterSheet,
              ),
            ],
          ),
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

/// The button that opens the filter sheet. Filled once a non-date filter is
/// active, so the user can tell at a glance the list is narrowed.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final icon = FinanceSuitIcon(
      FinanceSuitIcons.tune,
      color: active ? Theme.of(context).colorScheme.onPrimary : null,
    );
    if (active) {
      return FilledButton.icon(
        key: const Key('tx-open-filters'),
        onPressed: onPressed,
        icon: icon,
        label: Text(l10n.txFilters),
      );
    }
    return OutlinedButton.icon(
      key: const Key('tx-open-filters'),
      onPressed: onPressed,
      icon: icon,
      label: Text(l10n.txFilters),
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

/// The committed set of non-date filters, passed into and out of
/// [_FilterSheet] as one unit so the parent applies them atomically.
@immutable
class _FilterDraft {
  const _FilterDraft({
    required this.kind,
    required this.accountId,
    required this.categoryId,
    required this.keyword,
    required this.minAmountMinor,
    required this.maxAmountMinor,
  });

  final TransactionFilterKind kind;
  final String? accountId;
  final String? categoryId;
  final String? keyword;
  final int? minAmountMinor;
  final int? maxAmountMinor;

  bool get isEmpty =>
      kind == TransactionFilterKind.all &&
      accountId == null &&
      categoryId == null &&
      (keyword?.trim().isEmpty ?? true) &&
      minAmountMinor == null &&
      maxAmountMinor == null;
}

/// The filter drawer: every non-date filter, plus a live match count on the
/// Apply button that updates as each field changes, before anything is
/// actually committed to the list behind it.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.baseRange, required this.initial});

  /// The date range already active outside the sheet — held fixed here so
  /// the live count previews the total Apply would actually produce.
  final DateRange? baseRange;
  final _FilterDraft initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final _keywordController = TextEditingController(
    text: widget.initial.keyword ?? '',
  );
  late final _minController = TextEditingController(
    text: widget.initial.minAmountMinor == null
        ? ''
        : formatMinorForInput(widget.initial.minAmountMinor!),
  );
  late final _maxController = TextEditingController(
    text: widget.initial.maxAmountMinor == null
        ? ''
        : formatMinorForInput(widget.initial.maxAmountMinor!),
  );

  late TransactionFilterKind _kind = widget.initial.kind;
  late String? _accountId = widget.initial.accountId;
  late String? _categoryId = widget.initial.categoryId;

  /// The text fields' committed values, debounced so the count preview
  /// settles after the user pauses rather than firing on every keystroke.
  /// [_draft] — what Apply and Clear actually act on — always reads the
  /// controllers directly instead, so a tap right after typing can never
  /// apply a value one debounce cycle stale.
  late String? _debouncedKeyword = widget.initial.keyword;
  late int? _debouncedMinAmountMinor = widget.initial.minAmountMinor;
  late int? _debouncedMaxAmountMinor = widget.initial.maxAmountMinor;

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _keywordController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  String get _currencyCode =>
      (ref.read(allAccountBalancesProvider).value ?? const <AccountBalance>[])
          .firstOrNull
          ?.currencyCode ??
      'EGP';

  int? _amountMinor(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    return Money.tryParse(text, currencyCode: _currencyCode)?.minor;
  }

  /// Debounces free-text input so the count preview settles after the user
  /// pauses, rather than issuing a request on every keystroke.
  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _debouncedKeyword = _keywordController.text.trim().isEmpty
            ? null
            : _keywordController.text.trim();
        _debouncedMinAmountMinor = _amountMinor(_minController.text);
        _debouncedMaxAmountMinor = _amountMinor(_maxController.text);
      });
    });
  }

  /// What Apply and Clear act on: the chip selections plus whatever is
  /// currently typed, read straight from the controllers so it is never
  /// behind the debounce that only paces the count preview below.
  _FilterDraft get _draft => _FilterDraft(
    kind: _kind,
    accountId: _accountId,
    categoryId: _categoryId,
    keyword: _keywordController.text.trim().isEmpty
        ? null
        : _keywordController.text.trim(),
    minAmountMinor: _amountMinor(_minController.text),
    maxAmountMinor: _amountMinor(_maxController.text),
  );

  TransactionQuery get _previewQuery => TransactionQuery(
    range: widget.baseRange,
    kind: _kind,
    accountId: _accountId,
    categoryId: _categoryId,
    keyword: _debouncedKeyword,
    minAmountMinor: _debouncedMinAmountMinor,
    maxAmountMinor: _debouncedMaxAmountMinor,
    // The preview only ever needs the count, but the query is also the
    // provider's cache key — reusing the list's own page size keeps this
    // request identical to (and cached alongside) an unfiltered first page.
    limit: 30,
  );

  void _clear() {
    _debounce?.cancel();
    _keywordController.clear();
    _minController.clear();
    _maxController.clear();
    setState(() {
      _kind = TransactionFilterKind.all;
      _accountId = null;
      _categoryId = null;
      _debouncedKeyword = null;
      _debouncedMinAmountMinor = null;
      _debouncedMaxAmountMinor = null;
    });
  }

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accounts =
        ref.watch(allAccountBalancesProvider).value ?? const <AccountBalance>[];
    final categories =
        ref.watch(allCategoriesProvider).value ?? const <TransactionCategory>[];
    final countAsync = ref.watch(transactionsCountProvider(_previewQuery));
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.txFilters,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in TransactionFilterKind.values)
                    FilterChip(
                      key: Key('tx-kind-${kind.name}'),
                      label: Text(_kindLabel(l10n, kind)),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppSelectionField<String?>(
                key: ValueKey('tx-filter-account-$_accountId'),
                initialValue: _accountId,
                decoration: InputDecoration(labelText: l10n.txAccount),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.commonAll)),
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.accountId,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
              const SizedBox(height: 12),
              AppSelectionField<String?>(
                key: ValueKey('tx-filter-category-$_categoryId'),
                initialValue: _categoryId,
                decoration: InputDecoration(labelText: l10n.txCategory),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.commonAll)),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('tx-filter-keyword'),
                controller: _keywordController,
                decoration: InputDecoration(
                  labelText: l10n.txTitleField,
                  prefixIcon: const FinanceSuitIcon(FinanceSuitIcons.search),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) => _onTextChanged(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('tx-filter-min'),
                      controller: _minController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: '${l10n.commonAmount} min',
                      ),
                      onChanged: (_) => _onTextChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('tx-filter-max'),
                      controller: _maxController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyInputFormatters(),
                      decoration: InputDecoration(
                        labelText: '${l10n.commonAmount} max',
                      ),
                      onChanged: (_) => _onTextChanged(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('tx-filter-clear'),
                      onPressed: _draft.isEmpty ? null : _clear,
                      child: Text(l10n.txClearFilters),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('tx-filter-apply'),
                      onPressed: () =>
                          Navigator.of(context).pop<_FilterDraft>(_draft),
                      child: countAsync.when(
                        data: (count) => Text(l10n.txApplyWithCount(count)),
                        loading: () => SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        error: (_, _) => Text(l10n.commonApply),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
