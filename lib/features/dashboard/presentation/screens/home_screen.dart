import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/history/presentation/widgets/history_item_tile.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/salary/presentation/widgets/estimate_breakdown.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late ReportRangeSelection _range = ReportRangeSelection.currentMonth(
    PlainDate.today(),
  );

  static const _presetOptions = [
    DateRangePreset.currentMonth,
    DateRangePreset.last30Days,
    DateRangePreset.previousMonth,
    DateRangePreset.last90Days,
    DateRangePreset.custom,
  ];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_restoreRange);
  }

  Future<void> _restoreRange() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'home.range.$userId';
    final presetName = prefs.getString('$prefix.preset');
    final preset = DateRangePreset.values
        .where((p) => p.name == presetName)
        .firstOrNull;
    if (!mounted || preset == null) return;
    if (preset == DateRangePreset.custom) {
      final start = prefs.getString('$prefix.start');
      final end = prefs.getString('$prefix.end');
      if (start == null || end == null) return;
      setState(() {
        _range = ReportRangeSelection(
          preset: preset,
          range: DateRange(
            start: PlainDate.parse(start),
            end: PlainDate.parse(end),
          ),
        );
      });
      return;
    }
    setState(() {
      _range = ReportRangeSelection(
        preset: preset,
        range: rangeForPreset(preset, PlainDate.today()),
      );
    });
  }

  Future<void> _saveRange() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'home.range.$userId';
    await prefs.setString('$prefix.preset', _range.preset.name);
    await prefs.setString('$prefix.start', _range.range.start.toIso());
    await prefs.setString('$prefix.end', _range.range.end.toIso());
  }

  Future<void> _selectPreset(DateRangePreset preset) async {
    if (preset == DateRangePreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(
          start: _range.range.start.toDateTime(),
          end: _range.range.end.toDateTime(),
        ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _range = ReportRangeSelection(
          preset: DateRangePreset.custom,
          range: DateRange(
            start: PlainDate.fromDateTime(picked.start),
            end: PlainDate.fromDateTime(picked.end),
          ),
        );
      });
      await _saveRange();
      return;
    }
    setState(() {
      _range = ReportRangeSelection(
        preset: preset,
        range: rangeForPreset(preset, PlainDate.today()),
      );
    });
    await _saveRange();
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(accountBalancesProvider)
      ..invalidate(allAccountBalancesProvider)
      ..invalidate(currentEstimateProvider)
      ..invalidate(historyPageProvider)
      ..invalidate(cashFlowSummaryProvider);
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

  void _openTransaction(TransactionKind kind) {
    context.push('${AppRoutes.money}/tx/new?kind=${kind.dbValue}');
  }

  void _openWork(WorkEntryType type) {
    final today = PlainDate.today();
    context.push(
      '${AppRoutes.work}/entry/new?date=${today.toIso()}&type=${type.dbValue}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountBalancesProvider);
    final allAccountsAsync = ref.watch(allAccountBalancesProvider);
    final summaryAsync = ref.watch(cashFlowSummaryProvider(_range.range));
    final estimateAsync = ref.watch(currentEstimateProvider);
    final recentAsync = ref.watch(
      historyPageProvider(
        HistoryQuery(
          range: rangeForPreset(DateRangePreset.last30Days, PlainDate.today()),
          limit: 8,
        ),
      ),
    );
    final accountNames = {
      for (final account in allAccountsAsync.value ?? <AccountBalance>[])
        account.accountId: account.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabHome),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.history),
            tooltip: l10n.historyTitle,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionHeader(title: l10n.homeBalance),
            AsyncView(
              value: accountsAsync,
              onRetry: () => ref.invalidate(accountBalancesProvider),
              loading: const _SectionLoader(),
              data: (accounts) => _BalanceSection(accounts: accounts),
            ),
            _SectionHeader(title: l10n.homeCashFlow),
            _RangeChips(
              presets: _presetOptions,
              selected: _range.preset,
              labelFor: (preset) => _rangeLabel(l10n, preset),
              onSelected: _selectPreset,
            ),
            AsyncView(
              value: summaryAsync,
              onRetry: () => ref.invalidate(cashFlowSummaryProvider),
              loading: const _SectionLoader(),
              data: (summary) => _CashFlowSection(
                summary: summary,
                currencyCode:
                    accountsAsync.value?.firstOrNull?.currencyCode ?? 'EGP',
              ),
            ),
            _SectionHeader(
              title: l10n.homeSalary,
              actionLabel: l10n.commonSeeAll,
              onAction: () => context.push('${AppRoutes.work}/periods'),
            ),
            AsyncView(
              value: estimateAsync,
              onRetry: () => ref.invalidate(currentEstimateProvider),
              loading: const _SectionLoader(),
              data: (estimate) => EstimateBreakdownCard(estimate: estimate),
            ),
            _SectionHeader(title: l10n.homeQuickActions),
            _QuickActions(
              onExpense: () => _openTransaction(TransactionKind.expense),
              onAllowance: () =>
                  _openTransaction(TransactionKind.allowanceGiven),
              onIncome: () => _openTransaction(TransactionKind.customIncome),
              onTransfer: () => context.push('${AppRoutes.money}/transfer'),
              onOvertime: () => _openWork(WorkEntryType.overtime),
              onExtraDay: () => _openWork(WorkEntryType.extraDay),
              onHoliday: () => _openWork(WorkEntryType.holidayWorked),
            ),
            _SectionHeader(
              title: l10n.homeRecentActivity,
              actionLabel: l10n.commonSeeAll,
              onAction: () => context.push(AppRoutes.history),
            ),
            AsyncView(
              value: recentAsync,
              onRetry: () => ref.invalidate(historyPageProvider),
              loading: const _SectionLoader(),
              data: (page) {
                if (page.items.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.history,
                    message: l10n.homeNoRecentActivity,
                  );
                }
                return Column(
                  children: [
                    for (final item in page.items)
                      HistoryItemTile(item: item, accountNames: accountNames),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({
    required this.presets,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final List<DateRangePreset> presets;
  final DateRangePreset selected;
  final String Function(DateRangePreset preset) labelFor;
  final Future<void> Function(DateRangePreset preset) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in presets)
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

class _BalanceSection extends StatelessWidget {
  const _BalanceSection({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (accounts.isEmpty) {
      return EmptyStateView(
        icon: Icons.account_balance_wallet_outlined,
        message: l10n.moneyNoAccounts,
        actionLabel: l10n.moneyNewAccount,
        onAction: () => context.push('${AppRoutes.money}/accounts/new'),
      );
    }
    final totals = <String, int>{};
    for (final account in accounts) {
      totals[account.currencyCode] =
          (totals[account.currencyCode] ?? 0) + account.balanceMinor;
    }
    final defaultAccount = accounts.where((a) => a.isDefault).firstOrNull;
    final savingsTotal = accounts
        .where((a) => a.accountType == AccountType.savings)
        .fold<int>(0, (sum, account) => sum + account.balanceMinor);
    final currency = accounts.first.currencyCode;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return GridView.count(
              crossAxisCount: compact ? 1 : 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: compact ? 3.2 : 1.65,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _MetricCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: l10n.moneyTotalBalance,
                  value: totals.entries
                      .map(
                        (e) =>
                            Money(minor: e.value, currencyCode: e.key).format(),
                      )
                      .join(' / '),
                ),
                _MetricCard(
                  icon: Icons.star_outline,
                  label: l10n.homeDefaultAccount,
                  value: defaultAccount == null
                      ? l10n.commonNone
                      : defaultAccount.balance.format(),
                ),
                _MetricCard(
                  icon: Icons.savings_outlined,
                  label: l10n.homeSavings,
                  value: Money(
                    minor: savingsTotal,
                    currencyCode: currency,
                  ).format(),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        for (final account in accounts.take(4))
          Card(
            child: ListTile(
              leading: Icon(accountTypeIcon(account.accountType)),
              title: Text(account.name),
              trailing: BalanceText(money: account.balance),
              onTap: () => context.push(
                '${AppRoutes.money}/accounts/${account.accountId}',
              ),
            ),
          ),
      ],
    );
  }
}

class _CashFlowSection extends StatelessWidget {
  const _CashFlowSection({required this.summary, required this.currencyCode});

  final CashFlowSummary summary;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return GridView.count(
          crossAxisCount: compact ? 2 : 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: compact ? 1.45 : 1.5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricCard(
              icon: Icons.trending_up,
              label: l10n.reportIncome,
              value: Money(
                minor: summary.incomeMinor,
                currencyCode: currencyCode,
              ).format(),
            ),
            _MetricCard(
              icon: Icons.shopping_cart_outlined,
              label: l10n.reportExpenses,
              value: Money(
                minor: summary.expensesMinor,
                currencyCode: currencyCode,
              ).format(),
            ),
            _MetricCard(
              icon: Icons.volunteer_activism_outlined,
              label: l10n.reportAllowances,
              value: Money(
                minor: summary.allowancesMinor,
                currencyCode: currencyCode,
              ).format(),
            ),
            _MetricCard(
              icon: Icons.account_balance,
              label: l10n.reportNet,
              value: Money(
                minor: summary.netMinor,
                currencyCode: currencyCode,
              ).formatSigned(),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onExpense,
    required this.onAllowance,
    required this.onIncome,
    required this.onTransfer,
    required this.onOvertime,
    required this.onExtraDay,
    required this.onHoliday,
  });

  final VoidCallback onExpense;
  final VoidCallback onAllowance;
  final VoidCallback onIncome;
  final VoidCallback onTransfer;
  final VoidCallback onOvertime;
  final VoidCallback onExtraDay;
  final VoidCallback onHoliday;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = [
      (Icons.shopping_cart_outlined, l10n.homeAddExpense, onExpense),
      (Icons.volunteer_activism_outlined, l10n.homeGiveAllowance, onAllowance),
      (Icons.add_card_outlined, l10n.homeAddIncome, onIncome),
      (Icons.swap_horiz, l10n.homeTransfer, onTransfer),
      (Icons.more_time, l10n.homeAddOvertime, onOvertime),
      (Icons.event_available_outlined, l10n.homeAddExtraDay, onExtraDay),
      (Icons.celebration_outlined, l10n.homeAddHoliday, onHoliday),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          ActionChip(
            avatar: Icon(action.$1, size: 18),
            label: Text(action.$2),
            onPressed: action.$3,
          ),
      ],
    );
  }
}
