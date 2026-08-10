import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/providers/commercial_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/features/history/presentation/providers/history_providers.dart';
import 'package:work_tracker/features/history/presentation/widgets/history_item_tile.dart';
import 'package:work_tracker/features/reports/domain/report_models.dart';
import 'package:work_tracker/features/reports/presentation/providers/report_providers.dart';
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
  static const _solidHeaderThreshold = 12.0;
  static const _floatingHeaderThreshold = 4.0;

  final _scrollController = ScrollController();
  late ReportRangeSelection _range = ReportRangeSelection.currentMonth(
    PlainDate.today(),
  );
  var _isHeaderSolid = false;

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
    _scrollController.addListener(_updateHeaderState);
    Future<void>.microtask(_restoreRange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHeaderState());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateHeaderState)
      ..dispose();
    super.dispose();
  }

  void _updateHeaderState() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.position.pixels;
    final shouldBeSolid = _isHeaderSolid
        ? offset >= _floatingHeaderThreshold
        : offset > _solidHeaderThreshold;
    if (shouldBeSolid == _isHeaderSolid || !mounted) return;
    setState(() => _isHeaderSolid = shouldBeSolid);
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
      ..invalidate(homeCashFlowSummaryProvider)
      ..invalidate(salarySettingsProvider);
    ref.invalidate(pendingIncomeProvider);
    ref.invalidate(pendingRecurringProvider);
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
    final summaryAsync = ref.watch(homeCashFlowSummaryProvider(_range.range));
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
      appBar: FinanceSuitHomeAppBar(
        semanticTitle: l10n.tabHome,
        isSolid: _isHeaderSolid,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const Key('home-dashboard-scroll'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (hasDashboardFailure) _HomeDataStatusCard(onRetry: _refresh),
            _HomeEntitlementIndicator(
              entitlement: ref.watch(effectiveEntitlementProvider),
            ),
            compactSection(
              pendingIncomeAsync,
              loading: const SizedBox.shrink(),
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : _PendingIncomeSection(
                      items: items,
                      today: PlainDate.today(),
                      onOpen: () =>
                          context.push('${AppRoutes.settings}/income-sources'),
                    ),
            ),
            compactSection(
              ref.watch(pendingRecurringProvider),
              loading: const SizedBox.shrink(),
              data: (items) => items.isEmpty
                  ? const SizedBox.shrink()
                  : _PendingRecurringSection(
                      items: items,
                      today: PlainDate.today(),
                      onOpen: () =>
                          context.push('${AppRoutes.settings}/recurring'),
                    ),
            ),
            _SectionHeader(title: l10n.homeBalance),
            compactSection(
              accountsAsync,
              loading: const _SectionLoader(),
              // Home is a summary, not an inventory: accounts the user opted
              // out of stay fully usable in Money, pickers, and reports.
              data: (accounts) => _BalanceSection(
                accounts: accounts
                    .where((account) => !account.hideFromHome)
                    .toList(),
              ),
            ),
            compactSection(
              ref.watch(creditFacilitiesProvider),
              loading: const SizedBox.shrink(),
              data: (facilities) {
                final cards = facilities
                    .where((f) => !f.isArchived)
                    .toList(growable: false);
                if (cards.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeader(
                      title: l10n.homeCardsTitle,
                      actionLabel: l10n.commonSeeAll,
                      onAction: () => context.push(AppRoutes.money),
                    ),
                    _CreditCardCarousel(facilities: cards),
                  ],
                );
              },
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

class _HomeEntitlementIndicator extends StatelessWidget {
  const _HomeEntitlementIndicator({required this.entitlement});
  final AsyncValue<EffectiveEntitlement> entitlement;

  @override
  Widget build(BuildContext context) => entitlement.when(
    loading: () => const SizedBox.shrink(),
    error: (_, _) => const SizedBox.shrink(),
    data: (value) => value.source == EntitlementSource.openEarlyAccess
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const FinanceSuitIcon(FinanceSuitIcons.star),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pro Early Access',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
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

/// The user's credit cards and BNPL facilities as a swipeable row of
/// card-shaped tiles: limit and available credit up front, what is owed in
/// small red text, and everything falling due over the next month — summed
/// across statements and installments, not just the earliest single due.
class _CreditCardCarousel extends StatelessWidget {
  const _CreditCardCarousel({required this.facilities});

  final List<CreditFacilitySummary> facilities;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        key: const Key('home-credit-card-carousel'),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: facilities.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) =>
            _CreditCardTile(facility: facilities[index]),
      ),
    );
  }
}

class _CreditCardTile extends StatelessWidget {
  const _CreditCardTile({required this.facility});

  final CreditFacilitySummary facility;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final textTheme = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final owed = facility.outstandingMinor > 0;
    // A user-chosen colour replaces the brand surface; its foreground is
    // derived from the colour itself, so figures stay legible on any card.
    final palette = facilityPalette(context, facility.colorHex);
    final dueTone = facility.hasOverdue ? colors.error : colors.warning;
    return SizedBox(
      width: (width * 0.78).clamp(260.0, 340.0),
      child: Card(
        margin: EdgeInsets.zero,
        color: palette.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('home-card-${facility.accountId}'),
          onTap: () => context.push(
            '${AppRoutes.money}/facilities/${facility.accountId}',
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FinanceSuitIcon(
                      FinanceSuitIcons.creditCard,
                      color: palette.onSurface,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        facility.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: palette.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (facility.lastFourDigits != null)
                      Text(
                        '•••• ${facility.lastFourDigits}',
                        style: textTheme.labelSmall?.copyWith(
                          color: palette.onSurface,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  l10n.facilityAvailable,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                ProtectedMoneyText(
                  '${facility.availableCredit.format()} / '
                  '${facility.creditLimit.format()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  interactive: false,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (owed)
                  ProtectedMoneyText(
                    l10n.homeCardOwed(facility.outstanding.format()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    interactive: false,
                    style: textTheme.labelSmall?.copyWith(
                      // On a coloured card the semantic error red may not
                      // read; the muted foreground always does.
                      color: palette.isCustom
                          ? palette.onSurfaceMuted
                          : colors.error.text,
                    ),
                  ),
                const Spacer(),
                if (facility.upcomingDueMinor > 0)
                  ProtectedMoneyText(
                    facility.nextDueOn == null
                        ? facility.upcomingDue.format()
                        : l10n.homeCardDueBy(
                            facility.upcomingDue.format(),
                            facility.nextDueOn!.toIso(),
                          ),
                    key: Key('home-card-due-${facility.accountId}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    interactive: false,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.isCustom
                          ? palette.onSurface
                          : dueTone.text,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Text(
                    l10n.homeCardNothingDue,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact summary of recurring expenses/transfers waiting for a decision;
/// tapping opens the recurring automation center.
class _PendingRecurringSection extends StatelessWidget {
  const _PendingRecurringSection({
    required this.items,
    required this.today,
    required this.onOpen,
  });

  final List<PendingRecurring> items;
  final PlainDate today;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final warning = context.suitColors.warning;
    final first = items.first;
    final amount = first.expectedAmount.format();
    return Card(
      color: warning.background,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: l10n.recurringPendingTitle,
        child: InkWell(
          key: const Key('home-pending-recurring-summary'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                FinanceSuitIcon(
                  FinanceSuitIcons.eventRepeat,
                  color: warning.icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.recurringPendingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: warning.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (items.length == 1)
                        ProtectedMoneyText(
                          '${first.rule.name} · $amount',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        Text(
                          '${l10n.recurringPendingCount(items.length)} · '
                          '${first.rule.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      Text(
                        first.isDueOn(today)
                            ? l10n.incomeDue(
                                first.occurrence.scheduledOn.toIso(),
                              )
                            : l10n.incomeUpcoming(
                                first.occurrence.scheduledOn.toIso(),
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.suitColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingIncomeSection extends ConsumerWidget {
  const _PendingIncomeSection({
    required this.items,
    required this.today,
    required this.onOpen,
  });

  final List<PendingIncome> items;
  final PlainDate today;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final warning = context.suitColors.warning;
    final first = items.first;
    final estimate =
        first.source.kind == IncomeSourceKind.salary &&
            !first.occurrence.isRemainder
        ? ref.watch(
            pendingSalaryEstimateProvider((
              occurrenceId: first.occurrence.id,
              scheduledOn: first.occurrence.scheduledOn,
            )),
          )
        : null;
    final firstName = first.occurrence.isRemainder
        ? l10n.incomeRemainderTitle(first.source.name)
        : first.source.name;
    final amount = Money(
      minor:
          estimate?.value?.totalMinor ?? first.occurrence.expectedAmountMinor,
      currencyCode: first.source.currencyCode,
    ).format();
    return Card(
      color: warning.background,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: l10n.incomePendingTitle,
        child: InkWell(
          key: const Key('home-pending-income-summary'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                FinanceSuitIcon(FinanceSuitIcons.pending, color: warning.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.incomePendingTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: warning.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // The amount belongs to the item shown, not to the
                      // whole list, so it stays visible when several are
                      // waiting — a tracked remainder is the first of them.
                      ProtectedMoneyText(
                        items.length == 1
                            ? '$firstName · $amount'
                            : '${l10n.incomePendingCount(items.length)} · '
                                  '$firstName · $amount',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        first.isDueOn(today)
                            ? l10n.incomeDue(
                                first.occurrence.scheduledOn.toIso(),
                              )
                            : l10n.incomeUpcoming(
                                first.occurrence.scheduledOn.toIso(),
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.suitColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FinanceSuitIcon(
                  FinanceSuitIcons.chevronRight,
                  color: warning.icon,
                ),
              ],
            ),
          ),
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
    // Credit cards and BNPL facilities are borrowed money, not the user's
    // own: they get their own section and never move the total balance.
    final assets = accounts.assetAccounts;
    final totals = <String, int>{};
    for (final account in assets) {
      totals[account.currencyCode] =
          (totals[account.currencyCode] ?? 0) + account.balanceMinor;
    }
    final visibleAccounts = assets.take(4).toList();
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
    final textTheme = Theme.of(context).textTheme;
    // One line: icon, label, amount. A second currency, if any, follows on
    // its own line rather than stretching the first one.
    return Card(
      color: colors.brandSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.onBrandSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (totals.isNotEmpty)
                  AppMoneyText(
                    money: totals.first,
                    color: colors.onBrandSurface,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            for (final total in totals.skip(1)) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppMoneyText(
                  money: total,
                  color: colors.onBrandSurface,
                  style: textTheme.titleSmall,
                ),
              ),
            ],
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
                // 1.45 clipped the metric text by a few pixels on 320px-wide
                // phones; compact cells need the extra height.
                childAspectRatio: compact ? 1.3 : 1.5,
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
    // Icon and label share the top line so the cell only needs room for two
    // rows instead of three.
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                FinanceSuitIcon(icon, color: iconColor, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: labelColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
