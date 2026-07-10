import 'package:meta/meta.dart';

/// Calendar date without time or timezone. Business dates (work_date,
/// occurred_on, effective_date) use this type so they never shift when the
/// device timezone changes.
@immutable
class PlainDate implements Comparable<PlainDate> {
  const PlainDate(this.year, this.month, this.day);

  factory PlainDate.fromDateTime(DateTime dt) =>
      PlainDate(dt.year, dt.month, dt.day);

  /// Parses `yyyy-MM-dd` (PostgreSQL `date` wire format).
  factory PlainDate.parse(String iso) {
    final parts = iso.split('T').first.split('-');
    return PlainDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  static PlainDate today({DateTime Function() clock = DateTime.now}) =>
      PlainDate.fromDateTime(clock());

  /// ISO string `yyyy-MM-dd` for database storage.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  DateTime toDateTime() => DateTime(year, month, day);

  PlainDate addDays(int days) =>
      PlainDate.fromDateTime(DateTime(year, month, day + days));

  /// Adds calendar months, clamping the day to the target month length
  /// (Jan 31 + 1 month -> Feb 28/29).
  PlainDate addMonths(int months) {
    final targetMonthStart = DateTime(year, month + months);
    final lastDay = daysInMonth(targetMonthStart.year, targetMonthStart.month);
    return PlainDate(
      targetMonthStart.year,
      targetMonthStart.month,
      day > lastDay ? lastDay : day,
    );
  }

  /// Same year/month with a specific day, clamped to month length.
  PlainDate withDay(int newDay) {
    final last = daysInMonth(year, month);
    return PlainDate(year, month, newDay > last ? last : newDay);
  }

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  int differenceInDays(PlainDate other) =>
      toDateTime().difference(other.toDateTime()).inDays;

  bool isBefore(PlainDate other) => compareTo(other) < 0;
  bool isAfter(PlainDate other) => compareTo(other) > 0;
  bool operator <=(PlainDate other) => compareTo(other) <= 0;
  bool operator >=(PlainDate other) => compareTo(other) >= 0;

  /// DateTime.monday..DateTime.sunday (1..7).
  int get weekday => toDateTime().weekday;

  @override
  int compareTo(PlainDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is PlainDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
