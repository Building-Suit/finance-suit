import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';

/// Inclusive calendar date range.
@immutable
class DateRange {
  const DateRange({required this.start, required this.end})
    : assert(start <= end, 'start must not be after end');

  final PlainDate start;
  final PlainDate end;

  bool contains(PlainDate date) => date >= start && date <= end;

  int get lengthInDays => end.differenceInDays(start) + 1;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '${start.toIso()}..${end.toIso()}';
}

/// Named presets used by dashboard, history, and reports.
enum DateRangePreset {
  today,
  last7Days,
  last30Days,
  currentMonth,
  previousMonth,
  last90Days,
  currentYear,
  custom,
}

DateRange rangeForPreset(DateRangePreset preset, PlainDate today) {
  switch (preset) {
    case DateRangePreset.today:
      return DateRange(start: today, end: today);
    case DateRangePreset.last7Days:
      return DateRange(start: today.addDays(-6), end: today);
    case DateRangePreset.last30Days:
      return DateRange(start: today.addDays(-29), end: today);
    case DateRangePreset.currentMonth:
      return DateRange(
        start: PlainDate(today.year, today.month, 1),
        end: PlainDate(
          today.year,
          today.month,
          PlainDate.daysInMonth(today.year, today.month),
        ),
      );
    case DateRangePreset.previousMonth:
      final firstOfThisMonth = PlainDate(today.year, today.month, 1);
      final lastOfPrev = firstOfThisMonth.addDays(-1);
      return DateRange(
        start: PlainDate(lastOfPrev.year, lastOfPrev.month, 1),
        end: lastOfPrev,
      );
    case DateRangePreset.last90Days:
      return DateRange(start: today.addDays(-89), end: today);
    case DateRangePreset.currentYear:
      return DateRange(
        start: PlainDate(today.year, 1, 1),
        end: PlainDate(today.year, 12, 31),
      );
    case DateRangePreset.custom:
      throw ArgumentError('custom preset requires explicit dates');
  }
}
