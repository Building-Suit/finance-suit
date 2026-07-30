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
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/history/presentation/widgets/history_item_tile.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
import 'package:work_tracker/features/salary/data/salary_repository.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
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
      ..invalidate(cashFlowSummaryProvider);
    ref.invalidate(pendingIncomeProvider);
  }

  void _showFailure(AppFailure failure) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
  }

  Future<void> _acceptIncome(PendingIncome pending) async {
    final l10n = AppLocalizations.of(context);
    SalaryEstimate? salaryEstimate;
    SalaryPeriod? salaryPeriod;
    if (pending.source.kind == IncomeSourceKind.salary) {
      final settings = await ref.read(salarySettingsProvider.future);
      final bounds = SalaryPeriods.boundsForExpectedPayment(
        settings,
        pending.occurrence.scheduledOn,
      );
      salaryEstimate = await ref.read(
        estimateForRangeProvider((start: bounds.start, end: bounds.end)).future,
      );
      final periodResult = await ref
          .read(salaryRepositoryProvider)
          .ensurePeriod(bounds);
      salaryPeriod = periodResult.when(
        ok: (period) => period,
        err: (failure) {
          _showFailure(failure);
          return null;
        },
      );
      if (salaryPeriod == null || !mounted) return;
      if (salaryPeriod.isPaid) {
        _showFailure(
          const ConstraintFailure(
            'salary_period_already_paid',
            debugDetails: 'automated salary period is already paid',
          ),
        );
        return;
      }
      if (salaryPeriod.isFinalized) {
        salaryEstimate = SalaryEstimate.fromSnapshot(salaryPeriod.snapshot!);
      }
    }

    final defaultMinor =
        salaryEstimate?.totalMinor ?? pending.occurrence.expectedAmountMinor;
    final amountController = TextEditingController(
      text: (defaultMinor / Money.minorUnitsPerMajor).toStringAsFixed(2),
    );
    final notesController = TextEditingController();
    var receivedOn = PlainDate.today();
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.incomeAcceptTitle(pending.source.name)),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.incomeAcceptHelp),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.salActualAmount,
                      suffixText: pending.source.currencyCode,
                    ),
                    validator: (value) {
                      final error = Validators.positiveAmount(
                        value,
                        currencyCode: pending.source.currencyCode,
                      );
                      return error == null
                          ? null
                          : validationMessage(dialogContext, error);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const FinanceSuitIcon(
                      FinanceSuitIcons.calendarToday,
                    ),
                    title: Text(l10n.salReceivedDate),
                    subtitle: Text(receivedOn.toIso()),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: receivedOn.toDateTime(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(
                          () => receivedOn = PlainDate.fromDateTime(picked),
                        );
                      }
                    },
                  ),
                  TextFormField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text(l10n.incomeAccept),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;

    if (salaryPeriod?.isOpen == true) {
      final finalizeResult = await ref
          .read(salaryRepositoryProvider)
          .finalizePeriod(salaryPeriod!.id, salaryEstimate!.toSnapshotJson());
      final failed = finalizeResult.when(
        ok: (_) => false,
        err: (failure) {
          _showFailure(failure);
          return true;
        },
      );
      if (failed || !mounted) return;
    }

    final amount = Money.tryParse(
      amountController.text,
      currencyCode: pending.source.currencyCode,
    )!;
    final notes = notesController.text.trim();
    final result = await ref
        .read(financeRepositoryProvider)
        .acceptIncomeOccurrence(
          occurrenceId: pending.occurrence.id,
          actualAmountMinor: amount.minor,
          receivedOn: receivedOn,
          notes: notes.isEmpty ? null : notes,
          salaryPeriodId: salaryPeriod?.id,
        );
    if (!mounted) return;
    result.when(
      ok: (_) {
        invalidateIncomeAutomation(ref);
        invalidateFinanceData(ref);
        invalidateSalaryData(ref);
        ref
          ..invalidate(historyPageProvider)
          ..invalidate(cashFlowSummaryProvider);
      },
      err: _showFailure,
    );
  }

  Future<void> _skipIncome(PendingIncome pending) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.incomeSkipTitle),
        content: Text(l10n.incomeSkipHelp(pending.source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.incomeSkip),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .skipIncomeOccurrence(pending.occurrence.id);
    if (!mounted) return;
    result.when(ok: (_) => invalidateIncomeAutomation(ref), err: _showFailure);
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
    final estimateAsync = ref.watch(currentEstimateProvider);
    final salaryEnabled =
        ref.watch(salarySettingsProvider).value?.salaryEnabled ?? true;
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
            AsyncView(
              value: pendingIncomeAsync,
              onRetry: () => ref.invalidate(pendingIncomeProvider),
              loading: const SizedBox.shrink(),
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : _PendingIncomeSection(
                      items: items,
                      today: PlainDate.today(),
                      onAccept: _acceptIncome,
                      onSkip: _skipIncome,
                    ),
            ),
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
            if (salaryEnabled) ...[
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
            ],
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

class _PendingIncomeSection extends StatelessWidget {
  const _PendingIncomeSection({
    required this.items,
    required this.today,
    required this.onAccept,
    required this.onSkip,
  });

  final List<PendingIncome> items;
  final PlainDate today;
  final ValueChanged<PendingIncome> onAccept;
  final ValueChanged<PendingIncome> onSkip;

  @override
  Widget build(BuildContext context) {
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.source.name),
                subtitle: Text(
                  item.isDueOn(today)
                      ? l10n.incomeDue(item.occurrence.scheduledOn.toIso())
                      : l10n.incomeUpcoming(
                          item.occurrence.scheduledOn.toIso(),
                        ),
                ),
                trailing: Text(
                  Money(
                    minor: item.occurrence.expectedAmountMinor,
                    currencyCode: item.source.currencyCode,
                  ).format(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => onSkip(item),
                    child: Text(l10n.incomeSkip),
                  ),
                  TextButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.incomeRemindLater)),
                    ),
                    child: Text(l10n.incomeLater),
                  ),
                  FilledButton(
                    onPressed: () => onAccept(item),
                    child: Text(l10n.incomeAccept),
                  ),
                ],
              ),
              if (item != items.last) const Divider(),
            ],
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
        SizedBox(
          width: double.infinity,
          child: _MetricCard(
            icon: FinanceSuitIcons.accountBalanceWallet,
            label: l10n.moneyTotalBalance,
            brand: true,
            value: totals.entries
                .map((e) => Money(minor: e.value, currencyCode: e.key).format())
                .join(' / '),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < visibleAccounts.length; index += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HomeAccountCard(account: visibleAccounts[index]),
              ),
              if (index + 1 < visibleAccounts.length) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _HomeAccountCard(account: visibleAccounts[index + 1]),
                ),
              ],
            ],
          ),
          if (index + 2 < visibleAccounts.length) const SizedBox(height: 8),
        ],
      ],
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
      child: ListTile(
        leading: FinanceSuitIcon(accountTypeIcon(account.accountType)),
        title: Text(account.name),
        subtitle: BalanceText(money: account.balance),
        onTap: () =>
            context.push('${AppRoutes.money}/accounts/${account.accountId}'),
      ),
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
              icon: FinanceSuitIcons.trendingUp,
              label: l10n.reportIncome,
              value: Money(
                minor: summary.incomeMinor,
                currencyCode: currencyCode,
              ).format(),
            ),
            _MetricCard(
              icon: FinanceSuitIcons.shoppingCart,
              label: l10n.reportExpenses,
              value: Money(
                minor: summary.expensesMinor,
                currencyCode: currencyCode,
              ).format(),
            ),
            _MetricCard(
              icon: FinanceSuitIcons.volunteerActivism,
              label: l10n.reportAllowances,
              value: Money(
                minor: summary.allowancesMinor,
                currencyCode: currencyCode,
              ).format(),
            ),
            _MetricCard(
              icon: FinanceSuitIcons.accountBalance,
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
    this.brand = false,
  });

  final FinanceSuitGlyph icon;
  final String label;
  final String value;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final foreground = brand ? colors.onBrandSurface : colors.textPrimary;
    return Card(
      color: brand ? colors.brandSurface : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FinanceSuitIcon(icon, color: foreground),
            const Spacer(),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: foreground),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: foreground,
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
