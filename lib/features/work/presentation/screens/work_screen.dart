import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';
import 'package:work_tracker/features/work/presentation/providers/work_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Month calendar of work entries with per-day markers, a selectable day
/// filter, and the month's total extra pay.
class WorkScreen extends ConsumerStatefulWidget {
  const WorkScreen({super.key});

  @override
  ConsumerState<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends ConsumerState<WorkScreen> {
  late WorkMonth _month;
  PlainDate? _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = PlainDate.today();
    _month = (year: today.year, month: today.month);
  }

  void _shiftMonth(int delta) {
    final shifted = PlainDate(_month.year, _month.month, 1).addMonths(delta);
    setState(() {
      _month = (year: shifted.year, month: shifted.month);
      _selectedDay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(workEntriesForMonthProvider(_month));
    final currency =
        ref.watch(salarySettingsProvider).value?.currencyCode ?? 'EGP';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabWork),
        actions: [
          IconButton(
            icon: const Icon(Icons.request_quote_outlined),
            tooltip: l10n.salPeriodsTitle,
            onPressed: () => context.push('${AppRoutes.work}/periods'),
          ),
          IconButton(
            icon: const Icon(Icons.event_outlined),
            tooltip: l10n.workHolidays,
            onPressed: () => context.push('${AppRoutes.work}/holidays'),
          ),
        ],
      ),
      body: AsyncView(
        value: entriesAsync,
        onRetry: () => ref.invalidate(workEntriesForMonthProvider(_month)),
        data: (entries) {
          final visible = _selectedDay == null
              ? entries
              : entries.where((e) => e.workDate == _selectedDay).toList();
          final totalMinor = entries.fold<int>(
            0,
            (sum, e) => sum + (e.computedAmountMinor ?? 0),
          );
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(workEntriesForMonthProvider(_month)),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                _MonthNavigator(month: _month, onShift: _shiftMonth),
                _CalendarGrid(
                  month: _month,
                  entries: entries,
                  selectedDay: _selectedDay,
                  onDayTap: (day) => setState(
                    () => _selectedDay = _selectedDay == day ? null : day,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: Text(l10n.workMonthTotal),
                      trailing: Text(
                        Money(
                          minor: totalMinor,
                          currencyCode: currency,
                        ).format(),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: EmptyStateView(
                      icon: Icons.work_outline,
                      message: _selectedDay == null
                          ? l10n.workNoEntries
                          : l10n.workNoEntriesForDay,
                    ),
                  )
                else
                  for (final entry in visible)
                    _WorkEntryTile(entry: entry, currencyCode: currency),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({required this.month, required this.onShift});

  final WorkMonth month;
  final void Function(int delta) onShift;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final label = DateFormat.yMMMM(
      locale,
    ).format(DateTime(month.year, month.month));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onShift(-1),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onShift(1),
          ),
        ],
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.entries,
    required this.selectedDay,
    required this.onDayTap,
  });

  final WorkMonth month;
  final List<WorkEntry> entries;
  final PlainDate? selectedDay;
  final void Function(PlainDate day) onDayTap;

  Color _markerColor(BuildContext context, WorkEntryType type) {
    final scheme = Theme.of(context).colorScheme;
    return switch (type) {
      WorkEntryType.regular => scheme.outline,
      WorkEntryType.overtime => scheme.primary,
      WorkEntryType.extraDay => scheme.tertiary,
      WorkEntryType.holidayWorked => scheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    // 0 == Sunday in MaterialLocalizations' convention.
    final firstDayIndex = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final daysInMonth = PlainDate.daysInMonth(month.year, month.month);
    final firstOfMonth = PlainDate(month.year, month.month, 1);
    // DateTime.weekday: Mon=1..Sun=7 -> Sunday-based index 0..6.
    final firstWeekdayIndex = firstOfMonth.weekday % 7;
    final leadingBlanks = (firstWeekdayIndex - firstDayIndex + 7) % 7;
    final today = PlainDate.today();

    final entriesByDay = <int, List<WorkEntryType>>{};
    for (final entry in entries) {
      entriesByDay
          .putIfAbsent(entry.workDate.day, () => [])
          .add(entry.entryType);
    }

    final weekdayFormat = DateFormat.E(locale);
    // 2023-01-01 was a Sunday; offset by the locale's first day of week.
    final headerLabels = [
      for (var i = 0; i < 7; i++)
        weekdayFormat.format(DateTime(2023, 1, 1 + (firstDayIndex + i) % 7)),
    ];

    final cells = <Widget>[
      for (final label in headerLabels)
        Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          date: PlainDate(month.year, month.month, day),
          isToday: today == PlainDate(month.year, month.month, day),
          isSelected: selectedDay == PlainDate(month.year, month.month, day),
          markers: [
            for (final type in entriesByDay[day] ?? const <WorkEntryType>[])
              _markerColor(context, type),
          ],
          onTap: onDayTap,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cells,
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.markers,
    required this.onTap,
  });

  final PlainDate date;
  final bool isToday;
  final bool isSelected;
  final List<Color> markers;
  final void Function(PlainDate day) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onTap(date),
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? scheme.primaryContainer : null,
          border: isToday ? Border.all(color: scheme.primary) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSelected ? scheme.onPrimaryContainer : null,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in markers.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: CircleAvatar(radius: 2.5, backgroundColor: color),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkEntryTile extends ConsumerWidget {
  const _WorkEntryTile({required this.entry, required this.currencyCode});

  final WorkEntry entry;
  final String currencyCode;

  IconData get _icon => switch (entry.entryType) {
    WorkEntryType.regular => Icons.work_outline,
    WorkEntryType.overtime => Icons.more_time,
    WorkEntryType.extraDay => Icons.event_available_outlined,
    WorkEntryType.holidayWorked => Icons.celebration_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[entry.workDate.toIso()];
    final duration = entry.durationMinutes;
    if (duration != null) {
      parts.add(l10n.workDurationHm(duration ~/ 60, duration % 60));
    }
    final units = entry.dayUnitsHundredths;
    if (units != null) {
      parts.add('${(units / 100).toStringAsFixed(2)}d');
    }
    final amount = entry.amount(currencyCode);
    return ListTile(
      leading: Icon(_icon),
      title: Text(workEntryTypeLabel(l10n, entry.entryType)),
      subtitle: Text(parts.join(' · ')),
      trailing: amount == null || amount.isZero
          ? null
          : Text(
              amount.format(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
      onTap: () => context.push('${AppRoutes.work}/entry/edit', extra: entry),
    );
  }
}
