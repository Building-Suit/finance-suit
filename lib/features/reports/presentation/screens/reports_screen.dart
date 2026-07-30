import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late ReportRangeSelection _selection = ReportRangeSelection.last30Days(
    PlainDate.today(),
  );
  String? _accountId;

  static const _rangePresets = [
    DateRangePreset.currentMonth,
    DateRangePreset.last30Days,
    DateRangePreset.previousMonth,
    DateRangePreset.last90Days,
    DateRangePreset.currentYear,
    DateRangePreset.custom,
  ];

  Future<void> _refresh() async {
    invalidateReportData(ref);
  }

  Future<void> _selectPreset(DateRangePreset preset) async {
    if (preset == DateRangePreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: DateTimeRange(
          start: _selection.range.start.toDateTime(),
          end: _selection.range.end.toDateTime(),
        ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _selection = _selection.copyWith(
          preset: preset,
          range: DateRange(
            start: PlainDate.fromDateTime(picked.start),
            end: PlainDate.fromDateTime(picked.end),
          ),
        );
      });
      return;
    }
    setState(() {
      _selection = _selection.copyWith(
        preset: preset,
        range: rangeForPreset(preset, PlainDate.today()),
      );
    });
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

  String _bucketLabel(AppLocalizations l10n, ReportBucket bucket) {
    return switch (bucket) {
      ReportBucket.day => l10n.reportsBucketDay,
      ReportBucket.week => l10n.reportsBucketWeek,
      ReportBucket.month => l10n.reportsBucketMonth,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final range = _selection.range;
    final bucket = _selection.bucket;
    final accountsAsync = ref.watch(allAccountBalancesProvider);
    final accounts = accountsAsync.value ?? <AccountBalance>[];
    final selectedAccountId = _accountId ?? accounts.firstOrNull?.accountId;
    final selectedAccount = accounts
        .where((account) => account.accountId == selectedAccountId)
        .firstOrNull;
    final currencyCode = selectedAccount?.currencyCode ?? 'EGP';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabReports),
        actions: [
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _RangeChips(
              presets: _rangePresets,
              selected: _selection.preset,
              labelFor: (preset) => _rangeLabel(l10n, preset),
              onSelected: _selectPreset,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ReportBucket>(
              segments: [
                for (final option in ReportBucket.values)
                  ButtonSegment(
                    value: option,
                    label: Text(_bucketLabel(l10n, option)),
                  ),
              ],
              selected: {bucket},
              onSelectionChanged: (selection) {
                setState(() {
                  _selection = _selection.copyWith(bucket: selection.first);
                });
              },
            ),
            const SizedBox(height: 16),
            _AsyncReportCard<CashFlowSummary>(
              title: l10n.reportsCashFlow,
              value: ref.watch(cashFlowSummaryProvider(range)),
              data: (summary) =>
                  _CashFlowChart(summary: summary, currencyCode: currencyCode),
            ),
            _AsyncReportCard<List<FinanceSeriesPoint>>(
              title: l10n.reportsNetOverTime,
              value: ref.watch(
                financeSeriesProvider((range: range, bucket: bucket)),
              ),
              data: (rows) => _LineAmountChart(
                label: l10n.reportsNetOverTime,
                values: [
                  for (final row in rows)
                    ChartValue(
                      label: row.bucketStart.toIso(),
                      valueMinor: row.netMinor,
                    ),
                ],
                currencyCode: currencyCode,
              ),
            ),
            _AsyncReportCard<List<CategoryTotal>>(
              title: l10n.reportsExpensesByCategory,
              value: ref.watch(expenseCategoryTotalsProvider(range)),
              data: (rows) =>
                  _CategoryTotalsList(rows: rows, currencyCode: currencyCode),
            ),
            _AsyncReportCard<List<CategoryTotal>>(
              title: l10n.reportsAllowancesByCategory,
              value: ref.watch(allowanceCategoryTotalsProvider(range)),
              data: (rows) =>
                  _CategoryTotalsList(rows: rows, currencyCode: currencyCode),
            ),
            _AsyncReportCard<List<CategoryTotal>>(
              title: l10n.reportsIncomeByCategory,
              value: ref.watch(incomeCategoryTotalsProvider(range)),
              data: (rows) =>
                  _CategoryTotalsList(rows: rows, currencyCode: currencyCode),
            ),
            _ReportCard(
              title: l10n.reportsAccountBalance,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSelectionField<String>(
                    initialValue: selectedAccountId,
                    decoration: InputDecoration(labelText: l10n.txAccount),
                    items: [
                      for (final account in accounts)
                        DropdownMenuItem(
                          value: account.accountId,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  ),
                  const SizedBox(height: 16),
                  if (selectedAccountId == null)
                    EmptyStateView(
                      icon: FinanceSuitIcons.accountBalanceWallet,
                      message: l10n.moneyNoAccounts,
                    )
                  else
                    AsyncView(
                      value: ref.watch(
                        accountBalanceHistoryProvider((
                          accountId: selectedAccountId,
                          range: range,
                        )),
                      ),
                      data: (rows) => _LineAmountChart(
                        label: l10n.reportsAccountBalance,
                        values: [
                          for (final row in rows)
                            ChartValue(
                              label: row.day.toIso(),
                              valueMinor: row.balanceMinor,
                            ),
                        ],
                        currencyCode: selectedAccount?.currencyCode ?? 'EGP',
                      ),
                    ),
                ],
              ),
            ),
            _AsyncReportCard<List<SalaryComparisonPoint>>(
              title: l10n.reportsSalaryComparison,
              value: ref.watch(salaryComparisonProvider(range)),
              data: (rows) => _SalaryComparisonChart(rows: rows),
            ),
            _AsyncReportCard<List<SalaryWorkPeriodPoint>>(
              title: l10n.reportsWorkCompensation,
              value: ref.watch(salaryWorkPeriodsProvider(range)),
              data: (rows) => _SalaryWorkList(rows: rows),
            ),
            _AsyncReportCard<List<WorkMinutesPoint>>(
              title: l10n.reportsWorkingHours,
              value: ref.watch(
                workMinutesSeriesProvider((range: range, bucket: bucket)),
              ),
              data: (rows) => _LineNumberChart(
                label: l10n.reportsWorkingHours,
                values: [
                  for (final row in rows)
                    ChartValue(
                      label: row.bucketStart.toIso(),
                      valueMinor: row.totalMinutes,
                    ),
                ],
                valueSuffix: l10n.reportHours,
                scale: 60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartValue {
  const ChartValue({required this.label, required this.valueMinor});

  final String label;
  final int valueMinor;
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

class _AsyncReportCard<T> extends StatelessWidget {
  const _AsyncReportCard({
    required this.title,
    required this.value,
    required this.data,
  });

  final String title;
  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      title: title,
      child: AsyncView(
        value: value,
        loading: const LoadingSkeleton(height: 180),
        data: data,
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.summary, required this.currencyCode});

  final CashFlowSummary summary;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final values = [
      ChartValue(label: l10n.reportIncome, valueMinor: summary.incomeMinor),
      ChartValue(label: l10n.reportExpenses, valueMinor: summary.expensesMinor),
      ChartValue(
        label: l10n.reportAllowances,
        valueMinor: summary.allowancesMinor,
      ),
      ChartValue(label: l10n.reportNet, valueMinor: summary.netMinor),
    ];
    return _BarAmountChart(
      label: l10n.reportsCashFlow,
      values: values,
      currencyCode: currencyCode,
      barColors: [
        AppTheme.incomeColor(context),
        AppTheme.expenseColor(context),
        AppTheme.allowanceColor(context),
        AppTheme.transferColor(context),
      ],
    );
  }
}

class _BarAmountChart extends StatelessWidget {
  const _BarAmountChart({
    required this.label,
    required this.values,
    required this.currencyCode,
    required this.barColors,
  }) : assert(barColors.length > 0);

  final String label;
  final List<ChartValue> values;
  final String currencyCode;
  final List<Color> barColors;

  @override
  Widget build(BuildContext context) {
    if (values.every((value) => value.valueMinor == 0)) {
      return _NoData();
    }
    final maxY = values
        .map((v) => v.valueMinor.abs() / Money.minorUnitsPerMajor)
        .fold<double>(1, math.max);
    final minValue = values
        .map((v) => v.valueMinor / Money.minorUnitsPerMajor)
        .fold<double>(0, math.min);
    final colors = context.suitColors;
    return Semantics(
      label: label,
      child: SizedBox(
        height: 220,
        child: Column(
          children: [
            Expanded(
              child: BarChart(
                BarChartData(
                  minY: minValue < 0 ? -maxY : 0,
                  maxY: maxY,
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(color: colors.chartAxis),
                      bottom: BorderSide(color: colors.chartAxis),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: colors.chartGrid, strokeWidth: 1),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => colors.chartTooltipBackground,
                      tooltipBorder: BorderSide(color: colors.chartSelection),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final value = values[groupIndex];
                        return BarTooltipItem(
                          '${value.label}\n'
                          '${value.valueMinor / Money.minorUnitsPerMajor} '
                          '$currencyCode',
                          Theme.of(context).textTheme.labelMedium!.copyWith(
                            color: colors.chartTooltipText,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < values.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY:
                                values[i].valueMinor / Money.minorUnitsPerMajor,
                            color: barColors[i % barColors.length],
                            width: 26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (var index = 0; index < values.length; index++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: barColors[index % barColors.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        values[index].label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineAmountChart extends StatelessWidget {
  const _LineAmountChart({
    required this.label,
    required this.values,
    required this.currencyCode,
  });

  final String label;
  final List<ChartValue> values;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return _LineNumberChart(
      label: label,
      values: values,
      valueSuffix: currencyCode,
      scale: Money.minorUnitsPerMajor,
    );
  }
}

class _LineNumberChart extends StatelessWidget {
  const _LineNumberChart({
    required this.label,
    required this.values,
    required this.valueSuffix,
    required this.scale,
  });

  final String label;
  final List<ChartValue> values;
  final String valueSuffix;
  final int scale;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || values.every((value) => value.valueMinor == 0)) {
      return _NoData();
    }
    final spots = [
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i].valueMinor / scale),
    ];
    final maxY = spots.map((s) => s.y).fold<double>(0, math.max);
    final minY = spots.map((s) => s.y).fold<double>(0, math.min);
    final colors = context.suitColors;
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: minY < 0 ? minY : 0,
                maxY: maxY == 0 ? 1 : maxY,
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: colors.chartAxis),
                    bottom: BorderSide(color: colors.chartAxis),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: colors.chartGrid, strokeWidth: 1),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => colors.chartTooltipBackground,
                    tooltipBorder: BorderSide(color: colors.chartSelection),
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${values[spot.x.toInt()].label}\n'
                          '${spot.y} $valueSuffix',
                          Theme.of(context).textTheme.labelMedium!.copyWith(
                            color: colors.chartTooltipText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: colors.chartSeries[2],
                    barWidth: 3,
                    dotData: FlDotData(show: spots.length <= 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${values.first.label} – ${values.last.label} · '
            '${values.last.valueMinor / scale} $valueSuffix',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CategoryTotalsList extends StatelessWidget {
  const _CategoryTotalsList({required this.rows, required this.currencyCode});

  final List<CategoryTotal> rows;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _NoData();
    final max = rows
        .map((row) => row.totalMinor)
        .fold<int>(1, math.max)
        .toDouble();
    final colors = context.suitColors;
    return Column(
      children: [
        for (final (index, row) in rows.take(8).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(row.categoryName)),
                    Text(
                      Money(
                        minor: row.totalMinor,
                        currencyCode: currencyCode,
                      ).format(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: row.totalMinor / max,
                  color: colors.chartSeries[index % colors.chartSeries.length],
                  backgroundColor: colors.chartGrid,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SalaryComparisonChart extends StatelessWidget {
  const _SalaryComparisonChart({required this.rows});

  final List<SalaryComparisonPoint> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _NoData();
    final l10n = AppLocalizations.of(context);
    final currency = rows.first.currencyCode;
    return Column(
      children: [
        _BarAmountChart(
          label: l10n.reportsSalaryComparison,
          values: [
            for (final row in rows)
              ChartValue(
                label: row.periodStart.toIso(),
                valueMinor: row.actualAmountMinor ?? row.estimatedMinor,
              ),
          ],
          currencyCode: currency,
          barColors: [context.suitColors.chartSeries.first],
        ),
        const SizedBox(height: 8),
        for (final row in rows.take(6))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${row.periodStart.toIso()} – ${row.periodEnd.toIso()}',
            ),
            subtitle: Text(row.status.dbValue),
            trailing: Text(
              [
                '${l10n.reportEstimated}: ${Money(minor: row.estimatedMinor, currencyCode: row.currencyCode).format()}',
                if (row.actualAmountMinor != null)
                  '${l10n.reportActual}: ${Money(minor: row.actualAmountMinor!, currencyCode: row.currencyCode).format()}',
              ].join('\n'),
              textAlign: TextAlign.end,
            ),
          ),
      ],
    );
  }
}

class _SalaryWorkList extends StatelessWidget {
  const _SalaryWorkList({required this.rows});

  final List<SalaryWorkPeriodPoint> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _NoData();
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final row in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${row.periodStart.toIso()} – ${row.periodEnd.toIso()}',
            ),
            subtitle: Text(
              '${l10n.reportOvertime}: ${row.overtimeMinutes ~/ 60}h '
              '${row.overtimeMinutes % 60}m · '
              '${l10n.reportExtraDays}: '
              '${(row.extraDayUnitsHundredths / 100).toStringAsFixed(2)} · '
              '${l10n.reportHolidays}: ${row.holidayCount}',
            ),
            trailing: Text(
              Money(
                minor:
                    row.overtimeAmountMinor +
                    row.extraDayAmountMinor +
                    row.holidayAmountMinor,
                currencyCode: row.currencyCode,
              ).format(),
            ),
          ),
      ],
    );
  }
}

class _NoData extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyStateView(
      icon: FinanceSuitIcons.barChart,
      message: l10n.reportsNoData,
    );
  }
}
