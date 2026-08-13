import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';

/// A canonical unpaid obligation returned by
/// `app_finance.home_current_month_obligations`.
///
/// The database contract already prevents overlap: card installments and
/// generated fees are represented by their card statement, while BNPL dues
/// and still-pending recurring expenses remain standalone obligations.
@immutable
class HomeDueObligation {
  const HomeDueObligation({
    required this.id,
    required this.kind,
    required this.dueOn,
    required this.currencyCode,
    required this.remainingMinor,
  });

  factory HomeDueObligation.fromJson(Map<String, dynamic> json) {
    return HomeDueObligation(
      id: json['obligation_id'] as String,
      kind: json['obligation_kind'] as String,
      dueOn: PlainDate.parse(json['due_on'] as String),
      currencyCode: json['currency_code'] as String,
      remainingMinor: (json['remaining_minor'] as num).toInt(),
    );
  }

  final String id;
  final String kind;
  final PlainDate dueOn;
  final String currencyCode;
  final int remainingMinor;
}

enum HomeDuePeriod { current, thisMonth, nextMonth }

@immutable
class HomeDuePeriodSummary {
  const HomeDuePeriodSummary({
    required this.period,
    required this.start,
    required this.end,
    required this.obligationCount,
    required this.totals,
  });

  final HomeDuePeriod period;
  final PlainDate? start;
  final PlainDate end;
  final int obligationCount;
  final List<Money> totals;
}

/// Home's compact, account-agnostic payable summary.
///
/// Amounts are grouped by when the user must pay them and by currency. The
/// "next" row deliberately means the complete next calendar month, not the
/// single earliest facility returned by `credit_facility_summaries`.
@immutable
class HomeDueSummary {
  HomeDueSummary({required this.today, required List<HomeDueObligation> items})
    : periods = _buildPeriods(today, items);

  final PlainDate today;
  final List<HomeDuePeriodSummary> periods;

  bool get isEmpty => periods.isEmpty;

  static List<HomeDuePeriodSummary> _buildPeriods(
    PlainDate today,
    List<HomeDueObligation> items,
  ) {
    final monthStart = PlainDate(today.year, today.month, 1);
    final nextMonthStart = monthStart.addMonths(1);
    final monthEnd = nextMonthStart.addDays(-1);
    final followingMonthStart = nextMonthStart.addMonths(1);
    final nextMonthEnd = followingMonthStart.addDays(-1);

    final current = items
        .where((item) => !item.dueOn.isAfter(today))
        .toList(growable: false);
    final thisMonth = items
        .where(
          (item) => item.dueOn.isAfter(today) && !item.dueOn.isAfter(monthEnd),
        )
        .toList(growable: false);
    final nextMonth = items
        .where(
          (item) =>
              !item.dueOn.isBefore(nextMonthStart) &&
              !item.dueOn.isAfter(nextMonthEnd),
        )
        .toList(growable: false);

    return [
      if (current.isNotEmpty)
        _period(HomeDuePeriod.current, current, start: null, end: today),
      if (thisMonth.isNotEmpty)
        _period(
          HomeDuePeriod.thisMonth,
          thisMonth,
          start: today.addDays(1),
          end: monthEnd,
        ),
      if (nextMonth.isNotEmpty)
        _period(
          HomeDuePeriod.nextMonth,
          nextMonth,
          start: nextMonthStart,
          end: nextMonthEnd,
        ),
    ];
  }

  static HomeDuePeriodSummary _period(
    HomeDuePeriod period,
    List<HomeDueObligation> items, {
    required PlainDate? start,
    required PlainDate end,
  }) {
    final byCurrency = <String, int>{};
    for (final item in items) {
      if (item.remainingMinor <= 0) continue;
      byCurrency[item.currencyCode] =
          (byCurrency[item.currencyCode] ?? 0) + item.remainingMinor;
    }
    final totals =
        byCurrency.entries
            .map((entry) => Money(minor: entry.value, currencyCode: entry.key))
            .toList(growable: false)
          ..sort(
            (left, right) => left.currencyCode.compareTo(right.currencyCode),
          );
    return HomeDuePeriodSummary(
      period: period,
      start: start,
      end: end,
      obligationCount: items.length,
      totals: totals,
    );
  }
}
