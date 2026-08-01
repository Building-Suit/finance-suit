import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/history/data/history_repository.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/widgets/history_item_tile.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _keywordController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  late DateRangePreset _preset = DateRangePreset.last30Days;
  late DateRange _range = rangeForPreset(_preset, PlainDate.today());
  HistoryFilterType _type = HistoryFilterType.all;
  HistorySort _sort = HistorySort.recordDateDesc;
  String? _accountId;
  String? _categoryId;
  List<HistoryItem> _items = [];
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => _load(reset: true));
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failure = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final query = _query(
      cursor: reset || _items.isEmpty ? null : _items.last.cursor,
    );
    final result = await ref
        .read(historyRepositoryProvider)
        .fetchHistory(query);
    if (!mounted) return;
    result.when(
      ok: (page) {
        setState(() {
          _items = reset ? page.items : [..._items, ...page.items];
          _hasMore = page.hasMore;
          _loading = false;
          _loadingMore = false;
          _failure = null;
        });
      },
      err: (failure) {
        setState(() {
          _failure = failure;
          _loading = false;
          _loadingMore = false;
        });
      },
    );
  }

  HistoryQuery _query({HistoryCursor? cursor}) {
    return HistoryQuery(
      range: _range,
      type: _type,
      sort: _sort,
      accountId: _accountId,
      categoryId: _categoryId,
      minAmountMinor: _amountMinor(_minController.text),
      maxAmountMinor: _amountMinor(_maxController.text),
      keyword: _keywordController.text.trim().isEmpty
          ? null
          : _keywordController.text.trim(),
      cursor: cursor,
      limit: 30,
    );
  }

  int? _amountMinor(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    return Money.tryParse(text, currencyCode: 'EGP')?.minor;
  }

  Future<void> _selectPreset(DateRangePreset preset) async {
    if (preset == DateRangePreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(
          start: _range.start.toDateTime(),
          end: _range.end.toDateTime(),
        ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _preset = preset;
        _range = DateRange(
          start: PlainDate.fromDateTime(picked.start),
          end: PlainDate.fromDateTime(picked.end),
        );
      });
      await _load(reset: true);
      return;
    }
    setState(() {
      _preset = preset;
      _range = rangeForPreset(preset, PlainDate.today());
    });
    await _load(reset: true);
  }

  String _rangeLabel(AppLocalizations l10n, DateRangePreset preset) {
    return switch (preset) {
      DateRangePreset.today => l10n.rangeToday,
      DateRangePreset.last7Days => l10n.rangeLast7,
      DateRangePreset.last30Days => l10n.rangeLast30,
      DateRangePreset.currentMonth => l10n.rangeCurrentMonth,
      DateRangePreset.previousMonth => l10n.rangePreviousMonth,
      DateRangePreset.last90Days => l10n.rangeLast90,
      DateRangePreset.currentYear => l10n.rangeCurrentYear,
      DateRangePreset.custom => l10n.historyCustomRange,
    };
  }

  String _typeLabel(AppLocalizations l10n, HistoryFilterType type) {
    return switch (type) {
      HistoryFilterType.all => l10n.commonAll,
      HistoryFilterType.work => l10n.historyFilterWork,
      HistoryFilterType.regularWork => l10n.historyFilterRegularWork,
      HistoryFilterType.overtime => workEntryTypeLabel(
        l10n,
        WorkEntryType.overtime,
      ),
      HistoryFilterType.extraDay => workEntryTypeLabel(
        l10n,
        WorkEntryType.extraDay,
      ),
      HistoryFilterType.holidayWorked => workEntryTypeLabel(
        l10n,
        WorkEntryType.holidayWorked,
      ),
      HistoryFilterType.expense => transactionKindLabel(
        l10n,
        TransactionKind.expense,
      ),
      HistoryFilterType.allowanceGiven => transactionKindLabel(
        l10n,
        TransactionKind.allowanceGiven,
      ),
      HistoryFilterType.income => l10n.reportIncome,
      HistoryFilterType.freelanceIncome => transactionKindLabel(
        l10n,
        TransactionKind.freelanceIncome,
      ),
      HistoryFilterType.salaryIncome => transactionKindLabel(
        l10n,
        TransactionKind.salaryIncome,
      ),
      HistoryFilterType.transfer => transactionKindLabel(
        l10n,
        TransactionKind.transfer,
      ),
      HistoryFilterType.salaryAdjustment => l10n.historyFilterSalaryAdjustment,
    };
  }

  String _sortLabel(AppLocalizations l10n, HistorySort sort) {
    return switch (sort) {
      HistorySort.recordDateDesc => l10n.historySortRecordDesc,
      HistorySort.recordDateAsc => l10n.historySortRecordAsc,
      HistorySort.amountDesc => l10n.historySortAmountDesc,
      HistorySort.amountAsc => l10n.historySortAmountAsc,
      HistorySort.createdAtDesc => l10n.historySortCreatedDesc,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(allAccountBalancesProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final accountNames = {
      for (final account in accountsAsync.value ?? <AccountBalance>[])
        account.accountId: account.name,
    };
    final categories = categoriesAsync.value ?? <TransactionCategory>[];

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: l10n.historyTitle,
        actions: [
          PopupMenuButton<HistorySort>(
            tooltip: _sortLabel(l10n, _sort),
            initialValue: _sort,
            icon: const FinanceSuitIcon(FinanceSuitIcons.sort),
            onSelected: (sort) {
              setState(() => _sort = sort);
              _load(reset: true);
            },
            itemBuilder: (context) => [
              for (final sort in HistorySort.values)
                PopupMenuItem(value: sort, child: Text(_sortLabel(l10n, sort))),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _RangeFilter(
              selected: _preset,
              labelFor: (preset) => _rangeLabel(l10n, preset),
              onSelected: _selectPreset,
            ),
            const SizedBox(height: 8),
            _TypeFilter(
              selected: _type,
              labelFor: (type) => _typeLabel(l10n, type),
              onSelected: (type) {
                setState(() => _type = type);
                _load(reset: true);
              },
            ),
            const SizedBox(height: 8),
            _AdvancedFilters(
              accounts: accountsAsync.value ?? const <AccountBalance>[],
              categories: categories,
              accountId: _accountId,
              categoryId: _categoryId,
              keywordController: _keywordController,
              minController: _minController,
              maxController: _maxController,
              onAccountChanged: (value) => setState(() => _accountId = value),
              onCategoryChanged: (value) => setState(() => _categoryId = value),
              onApply: () => _load(reset: true),
            ),
            const SizedBox(height: 8),
            _ActiveFilters(
              chips: [
                _rangeLabel(l10n, _preset),
                _typeLabel(l10n, _type),
                _sortLabel(l10n, _sort),
                if (_accountId != null) accountNames[_accountId] ?? _accountId!,
                if (_categoryId != null)
                  categories
                          .where((c) => c.id == _categoryId)
                          .map((c) => c.name)
                          .firstOrNull ??
                      _categoryId!,
                if (_keywordController.text.trim().isNotEmpty)
                  _keywordController.text.trim(),
              ],
            ),
            const Divider(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failure != null)
              ErrorRetryView(
                failure: _failure!,
                onRetry: () => _load(reset: true),
              )
            else if (_items.isEmpty)
              EmptyStateView(
                icon: FinanceSuitIcons.manageSearch,
                message: l10n.historyNoItems,
              )
            else ...[
              for (final item in _items)
                HistoryItemTile(item: item, accountNames: accountNames),
              if (_hasMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: OutlinedButton.icon(
                    onPressed: _loadingMore ? null : () => _load(reset: false),
                    icon: _loadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const FinanceSuitIcon(FinanceSuitIcons.expandMore),
                    label: Text(l10n.historyLoadMore),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeFilter extends StatelessWidget {
  const _RangeFilter({
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final DateRangePreset selected;
  final String Function(DateRangePreset preset) labelFor;
  final Future<void> Function(DateRangePreset preset) onSelected;

  static const _presets = [
    DateRangePreset.today,
    DateRangePreset.last7Days,
    DateRangePreset.last30Days,
    DateRangePreset.currentMonth,
    DateRangePreset.previousMonth,
    DateRangePreset.last90Days,
    DateRangePreset.currentYear,
    DateRangePreset.custom,
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in _presets)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(labelFor(preset)),
                selected: selected == preset,
                onSelected: (_) => onSelected(preset),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypeFilter extends StatelessWidget {
  const _TypeFilter({
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final HistoryFilterType selected;
  final String Function(HistoryFilterType type) labelFor;
  final void Function(HistoryFilterType type) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final type in HistoryFilterType.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilterChip(
                label: Text(labelFor(type)),
                selected: selected == type,
                onSelected: (_) => onSelected(type),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdvancedFilters extends StatelessWidget {
  const _AdvancedFilters({
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
  });

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(l10n.historyActiveFilters),
      children: [
        AppSelectionField<String?>(
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
          initialValue: categoryId,
          decoration: InputDecoration(labelText: l10n.txCategory),
          items: [
            DropdownMenuItem(value: null, child: Text(l10n.commonAll)),
            for (final category in categories)
              DropdownMenuItem(value: category.id, child: Text(category.name)),
          ],
          onChanged: onCategoryChanged,
        ),
        const SizedBox(height: 8),
        TextField(
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
                controller: minController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${l10n.commonAmount} min',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: maxController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${l10n.commonAmount} max',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: onApply,
            icon: const FinanceSuitIcon(FinanceSuitIcons.check),
            label: Text(l10n.commonApply),
          ),
        ),
      ],
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.chips});

  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          Chip(visualDensity: VisualDensity.compact, label: Text(chip)),
      ],
    );
  }
}
