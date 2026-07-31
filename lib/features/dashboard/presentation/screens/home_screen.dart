import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/top_message.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/finance/presentation/widgets/income_automation_actions.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/history/presentation/widgets/history_item_tile.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/presentation/providers/salary_providers.dart';
import 'package:work_tracker/features/salary/presentation/widgets/estimate_breakdown.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
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
      ..invalidate(cashFlowSummaryProvider)
      ..invalidate(salarySettingsProvider);
    ref.invalidate(pendingIncomeProvider);
  }

  Future<void> _acceptIncome(PendingIncome pending) async {
    final l10n = AppLocalizations.of(context);
    final accepted = await acceptPendingIncome(context, ref, pending);
    if (mounted && accepted) {
      TopMessage.success(context, l10n.incomeAcceptedMessage);
    }
  }

  Future<void> _skipIncome(PendingIncome pending) async {
    final l10n = AppLocalizations.of(context);
    final skipped = await skipPendingIncome(context, ref, pending);
    if (mounted && skipped) {
      TopMessage.success(context, l10n.incomeSkippedMessage);
    }
  }

  Future<void> _snoozeIncome(PendingIncome pending) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(financeRepositoryProvider)
        .snoozeIncomeOccurrence(
          occurrenceId: pending.occurrence.id,
          snoozedUntil: DateTime.now().toUtc().add(const Duration(hours: 24)),
        );
    if (!mounted) return;
    result.when(
      ok: (_) {
        invalidateIncomeAutomation(ref);
        TopMessage.success(context, l10n.incomeRemindLater);
      },
      err: (_) => TopMessage.error(context, l10n.incomeSnoozeFailed),
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountsAsync = ref.watch(accountBalancesProvider);
    final allAccountsAsync = ref.watch(allAccountBalancesProvider);
    final summaryAsync = ref.watch(cashFlowSummaryProvider(_range.range));
    final salarySettingsAsync = ref.watch(salarySettingsProvider);
    final salaryEnabled = salarySettingsAsync.value?.salaryEnabled == true;
    final estimateAsync = salaryEnabled
        ? ref.watch(currentEstimateProvider)
        : null;
    final pendingIncomeAsync = ref.watch(pendingIncomeProvider);
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
    final hasDashboardFailure = [
      pendingIncomeAsync,
      accountsAsync,
      allAccountsAsync,
      summaryAsync,
      salarySettingsAsync,
      ?estimateAsync,
      recentAsync,
    ].any((value) => value.hasError);

    Widget compactSection<T>(
      AsyncValue<T> value, {
      required Widget loading,
      required Widget Function(T data) data,
    }) => value.when(
      data: data,
      loading: () => loading,
      error: (_, _) => const SizedBox.shrink(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabHome),
        actions: [
          IconButton(
            onPressed: () =>
                context.push('${AppRoutes.settings}/income-sources'),
            tooltip: l10n.incomeAutomationCenter,
            icon: const FinanceSuitIcon(FinanceSuitIcons.tune),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.history),
            tooltip: l10n.historyTitle,
            icon: const FinanceSuitIcon(FinanceSuitIcons.history),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (hasDashboardFailure) _HomeDataStatusCard(onRetry: _refresh),
            compactSection(
              pendingIncomeAsync,
              loading: const SizedBox.shrink(),
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : _PendingIncomeSection(
                      items: items,
                      today: PlainDate.today(),
                      onAccept: _acceptIncome,
                      onSkip: _skipIncome,
                      onLater: _snoozeIncome,
                    ),
            ),
            _SectionHeader(title: l10n.homeBalance),
            compactSection(
              accountsAsync,
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
            compactSection(
              summaryAsync,
              loading: const _SectionLoader(),
              data: (summaries) => _CashFlowSection(summaries: summaries),
            ),
            if (salaryEnabled) ...[
              _SectionHeader(
                title: l10n.homeSalary,
                actionLabel: l10n.commonSeeAll,
                onAction: () => context.push('${AppRoutes.work}/periods'),
              ),
              compactSection(
                estimateAsync!,
                loading: const _SectionLoader(),
                data: (estimate) => EstimateBreakdownCard(estimate: estimate),
              ),
            ],
            _SectionHeader(
              title: l10n.homeRecentActivity,
              actionLabel: l10n.commonSeeAll,
              onAction: () => context.push(AppRoutes.history),
            ),
            compactSection(
              recentAsync,
              loading: const _SectionLoader(),
              data: (page) {
                if (page.items.isEmpty) {
                  return EmptyStateView(
                    icon: FinanceSuitIcons.history,
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

class _HomeDataStatusCard extends StatelessWidget {
  const _HomeDataStatusCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = context.suitColors.error;
    return Card(
      color: error.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FinanceSuitIcon(FinanceSuitIcons.error, color: error.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.homePartialDataError,
                style: TextStyle(color: error.text),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const FinanceSuitIcon(FinanceSuitIcons.refresh),
              label: Text(l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingIncomeSection extends ConsumerWidget {
  const _PendingIncomeSection({
    required this.items,
    required this.today,
    required this.onAccept,
    required this.onSkip,
    required this.onLater,
  });

  final List<PendingIncome> items;
  final PlainDate today;
  final ValueChanged<PendingIncome> onAccept;
  final ValueChanged<PendingIncome> onSkip;
  final ValueChanged<PendingIncome> onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final warning = context.suitColors.warning;
    return Card(
      color: warning.background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FinanceSuitIcon(FinanceSuitIcons.pending, color: warning.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.incomePendingTitle,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: warning.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in items) ...[
              _PendingIncomeItem(
                item: item,
                today: today,
                estimate: item.source.kind == IncomeSourceKind.salary
                    ? ref.watch(
                        pendingSalaryEstimateProvider((
                          occurrenceId: item.occurrence.id,
                          scheduledOn: item.occurrence.scheduledOn,
                        )),
                      )
                    : null,
                onAccept: () => onAccept(item),
                onSkip: () => onSkip(item),
                onLater: () => onLater(item),
              ),
              if (item != items.last) const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingIncomeItem extends StatelessWidget {
  const _PendingIncomeItem({
    required this.item,
    required this.today,
    required this.onAccept,
    required this.onSkip,
    required this.onLater,
    this.estimate,
  });

  final PendingIncome item;
  final PlainDate today;
  final AsyncValue<SalaryEstimate>? estimate;
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final salaryEstimate = estimate?.value;
    final amountMinor =
        salaryEstimate?.totalMinor ?? item.occurrence.expectedAmountMinor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                item.source.name,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              AppMoneyText(
                money: Money(
                  minor: amountMinor,
                  currencyCode: item.source.currencyCode,
                ),
                style: textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.isDueOn(today)
                ? l10n.incomeDue(item.occurrence.scheduledOn.toIso())
                : l10n.incomeUpcoming(item.occurrence.scheduledOn.toIso()),
            style: textTheme.bodySmall,
          ),
          if (salaryEstimate != null) ...[
            const SizedBox(height: 8),
            _SalaryPendingSummary(estimate: salaryEstimate),
          ],
          if (estimate?.hasError == true) ...[
            const SizedBox(height: 8),
            Text(l10n.homePartialDataError, style: textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(onPressed: onSkip, child: Text(l10n.incomeSkip)),
              TextButton(onPressed: onLater, child: Text(l10n.incomeLater)),
              FilledButton(onPressed: onAccept, child: Text(l10n.incomeAccept)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SalaryPendingSummary extends StatelessWidget {
  const _SalaryPendingSummary({required this.estimate});

  final SalaryEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <({String label, String value, int money})>[
      (
        label: l10n.salaryBaseAmount,
        value: '',
        money: estimate.baseSalaryMinor,
      ),
      (
        label: l10n.salaryExtraDays,
        value: (estimate.extraDayUnitsHundredths / 100).toStringAsFixed(2),
        money: estimate.extraDayAmountMinor,
      ),
      (
        label: l10n.salaryOvertimeDuration,
        value: l10n.durationHoursMinutes(
          estimate.overtimeMinutes ~/ 60,
          estimate.overtimeMinutes % 60,
        ),
        money: estimate.overtimeAmountMinor,
      ),
      if (estimate.holidayCount != 0)
        (
          label: l10n.salaryHolidayWorked,
          value: estimate.holidayCount.toString(),
          money: estimate.holidayAmountMinor,
        ),
      if (estimate.bonusesMinor != 0)
        (label: l10n.salAdjBonus, value: '', money: estimate.bonusesMinor),
      if (estimate.deductionsMinor != 0)
        (
          label: l10n.salAdjDeduction,
          value: '',
          money: -estimate.deductionsMinor,
        ),
      (label: l10n.salaryEstimatedTotal, value: '', money: estimate.totalMinor),
    ];
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  row.value.isEmpty ? row.label : '${row.label}: ${row.value}',
                  style: textTheme.bodySmall,
                ),
                AppMoneyText(
                  money: Money(
                    minor: row.money,
                    currencyCode: estimate.currencyCode,
                  ),
                  sign: row.money < 0
                      ? AppMoneySign.automatic
                      : AppMoneySign.never,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
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
      padding: EdgeInsets.symmetric(vertical: 8),
      child: LoadingSkeleton(),
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
        icon: FinanceSuitIcons.accountBalanceWallet,
        message: l10n.moneyNoAccounts,
      );
    }
    final totals = <String, int>{};
    for (final account in accounts) {
      totals[account.currencyCode] =
          (totals[account.currencyCode] ?? 0) + account.balanceMinor;
    }
    final visibleAccounts = accounts.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalBalanceCard(
          totals: [
            for (final entry in totals.entries)
              Money(minor: entry.value, currencyCode: entry.key),
          ],
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < visibleAccounts.length; index += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _HomeAccountCard(account: visibleAccounts[index]),
                ),
                if (index + 1 < visibleAccounts.length) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HomeAccountCard(
                      account: visibleAccounts[index + 1],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (index + 2 < visibleAccounts.length) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({required this.totals});

  final List<Money> totals;

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final l10n = AppLocalizations.of(context);
    return Card(
      color: colors.brandSurface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FinanceSuitIcon(
                  FinanceSuitIcons.accountBalanceWallet,
                  color: colors.onBrandSurface,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.moneyTotalBalance,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onBrandSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final total in totals)
              AppMoneyText(
                money: total,
                color: colors.onBrandSurface,
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeAccountCard extends StatelessWidget {
  const _HomeAccountCard({required this.account});

  final AccountBalance account;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            context.push('${AppRoutes.money}/accounts/${account.accountId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FinanceSuitIcon(accountTypeIcon(account.accountType)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      account.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const SizedBox(height: 8),
              BalanceText(money: account.balance),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashFlowSection extends StatelessWidget {
  const _CashFlowSection({required this.summaries});

  final List<CashFlowSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    if (summaries.isEmpty) {
      return EmptyStateView(
        icon: FinanceSuitIcons.barChart,
        message: l10n.homeNoRecentActivity,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Column(
          children: [
            for (final summary in summaries) ...[
              GridView.count(
                crossAxisCount: compact ? 2 : 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: compact ? 1.45 : 1.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricCard(
                    icon: FinanceSuitIcons.trendingUp,
                    label: l10n.reportIncome,
                    tone: colors.success,
                    money: Money(
                      minor: summary.incomeMinor,
                      currencyCode: summary.currencyCode,
                    ),
                  ),
                  _MetricCard(
                    icon: FinanceSuitIcons.shoppingCart,
                    label: l10n.reportExpenses,
                    tone: colors.error,
                    money: Money(
                      minor: summary.expensesMinor,
                      currencyCode: summary.currencyCode,
                    ),
                  ),
                  _MetricCard(
                    icon: FinanceSuitIcons.volunteerActivism,
                    label: l10n.reportAllowances,
                    tone: colors.warning,
                    money: Money(
                      minor: summary.allowancesMinor,
                      currencyCode: summary.currencyCode,
                    ),
                  ),
                  _MetricCard(
                    icon: FinanceSuitIcons.accountBalance,
                    label: l10n.reportNet,
                    tone: summary.netMinor > 0
                        ? colors.success
                        : summary.netMinor < 0
                        ? colors.error
                        : null,
                    money: Money(
                      minor: summary.netMinor,
                      currencyCode: summary.currencyCode,
                    ),
                    sign: AppMoneySign.explicit,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BalanceStrip(summary: summary),
              if (summary != summaries.last) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip({required this.summary});

  final CashFlowSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _StripAmount(
            label: l10n.reportStartingBalance,
            money: Money(
              minor: summary.startingBalanceMinor,
              currencyCode: summary.currencyCode,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StripAmount(
            label: l10n.reportEndingBalance,
            money: Money(
              minor: summary.endingBalanceMinor,
              currencyCode: summary.currencyCode,
            ),
          ),
        ),
      ],
    );
  }
}

class _StripAmount extends StatelessWidget {
  const _StripAmount({required this.label, required this.money});

  final String label;
  final Money money;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            AppMoneyText(
              money: money,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.money,
    this.tone,
    this.sign = AppMoneySign.never,
  });

  final FinanceSuitGlyph icon;
  final String label;
  final Money money;
  final FinanceSuitStatusColors? tone;
  final AppMoneySign sign;

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final labelColor = colors.textPrimary;
    final amountColor = tone?.text;
    final iconColor = tone?.icon;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FinanceSuitIcon(icon, color: iconColor),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: labelColor),
            ),
            const SizedBox(height: 4),
            AppMoneyText(
              money: money,
              sign: sign,
              color: amountColor,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
