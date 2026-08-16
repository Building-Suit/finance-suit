import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';

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
    this.sourceAccountId,
    this.sourceName = '',
    required this.dueOn,
    required this.currencyCode,
    required this.remainingMinor,
    this.paidMinor = 0,
    this.details = const <String, dynamic>{},
  });

  factory HomeDueObligation.fromJson(Map<String, dynamic> json) {
    return HomeDueObligation(
      id: json['obligation_id'] as String,
      kind: json['obligation_kind'] as String,
      sourceAccountId: json['source_account_id'] as String?,
      sourceName: json['source_name'] as String? ?? '',
      dueOn: PlainDate.parse(json['due_on'] as String),
      currencyCode: json['currency_code'] as String,
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      paidMinor: (json['paid_minor'] as num?)?.toInt() ?? 0,
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : const <String, dynamic>{},
    );
  }

  final String id;
  final String kind;
  final String? sourceAccountId;
  final String sourceName;
  final PlainDate dueOn;
  final String currencyCode;
  final int remainingMinor;

  /// Amount already paid toward this obligation (statement and installment
  /// obligations only; zero for recurring expenses).
  final int paidMinor;
  final Map<String, dynamic> details;

  int get totalDueMinor => paidMinor + remainingMinor;

  /// The obligation's item-level breakdown as typed components with their
  /// server-side paid state, mapped from the `details` payload so the Home
  /// sheet renders exactly like the facility Due Breakdown. Entries from
  /// servers that predate paid state default to unpaid.
  List<FacilityPaymentComponent> get components {
    FacilityPaymentComponent? fromMap(
      Map<String, dynamic> raw, {
      required bool isInstallment,
    }) {
      final amount =
          (raw['amount_minor'] as num?)?.toInt() ??
          (raw['remaining_minor'] as num?)?.toInt();
      final id = raw['id'] as String?;
      if (amount == null || id == null) return null;
      final paid = (raw['paid_minor'] as num?)?.toInt() ?? 0;
      final on = (raw['occurred_on'] ?? raw['due_on']) as String?;
      // An ordinary BNPL purchase is its own component type, so the Home
      // sheet labels and groups it as a purchase instead of borrowing the
      // card statement's identity.
      final isBnpl = !isInstallment && kind == 'bnpl_purchase';
      return FacilityPaymentComponent.fromJson({
        'component_type': isInstallment
            ? 'installment_due'
            : isBnpl
            ? 'bnpl_purchase'
            : 'statement_item',
        'component_id': id,
        'plan_id': raw['plan_id'],
        'title': raw['title'],
        'activity_kind': isInstallment
            ? 'installment_due'
            : isBnpl
            ? 'bnpl_purchase'
            : raw['kind'] == 'fee'
            ? 'fee_charge'
            : 'ordinary_expense',
        'sequence_number': raw['sequence_number'],
        'installment_count':
            raw['installment_count'] ?? details['installment_count'],
        'occurred_on': on,
        'due_on': raw['due_on'],
        'amount_minor': amount,
        'paid_minor': paid,
        'remaining_minor':
            (raw['remaining_minor'] as num?)?.toInt() ?? (amount - paid),
        'payment_status': raw['payment_status'] as String? ?? 'unpaid',
        'scope': 'current',
      });
    }

    List<Map<String, dynamic>> entries(String key) =>
        (details[key] as List? ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map(Map<String, dynamic>.from)
            .toList();

    return [
      for (final raw in entries('installments'))
        ?fromMap(raw, isInstallment: true),
      for (final raw in entries('items')) ?fromMap(raw, isInstallment: false),
    ];
  }
}

enum HomeDuePeriod { current, thisMonth, nextMonth }

@immutable
class HomeDuePeriodSummary {
  const HomeDuePeriodSummary({
    required this.period,
    required this.start,
    required this.end,
    required this.obligationCount,
    List<HomeDueObligation>? obligations,
    required this.totals,
  }) : _obligations = obligations;

  final HomeDuePeriod period;
  final PlainDate? start;
  final PlainDate end;
  final int obligationCount;
  final List<HomeDueObligation>? _obligations;

  /// Keeps hot-reloaded summaries safe when they were created before the
  /// audit breakdown field was introduced.
  List<HomeDueObligation> get obligations => _obligations ?? const [];
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
      obligations: List.unmodifiable(items),
      totals: totals,
    );
  }
}
