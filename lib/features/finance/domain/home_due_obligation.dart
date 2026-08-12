import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';

/// One canonical, still-payable entry in Home's current-month obligation
/// window. It is deliberately a read model: opening the calculator never
/// creates transactions or allocates a payment.
enum HomeDueObligationKind {
  cardStatement('card_statement'),
  installmentDue('installment_due'),
  recurringExpense('recurring_expense');

  const HomeDueObligationKind(this.dbValue);
  final String dbValue;

  static HomeDueObligationKind fromDb(String value) =>
      values.firstWhere((kind) => kind.dbValue == value);
}

@immutable
class HomeDueObligation {
  const HomeDueObligation({
    required this.id,
    required this.kind,
    required this.sourceAccountId,
    required this.sourceName,
    required this.relatedId,
    required this.dueOn,
    required this.currencyCode,
    required this.remainingMinor,
    required this.minimumDueMinor,
    required this.paidMinor,
    required this.status,
    required this.title,
    required this.sortRank,
    required this.details,
    this.maskedIdentifier,
  });

  factory HomeDueObligation.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'];
    return HomeDueObligation(
      id: json['obligation_id'] as String,
      kind: HomeDueObligationKind.fromDb(json['obligation_kind'] as String),
      sourceAccountId: json['source_account_id'] as String,
      sourceName: json['source_name'] as String,
      maskedIdentifier: json['masked_identifier'] as String?,
      relatedId: json['related_id'] as String,
      dueOn: PlainDate.parse(json['due_on'] as String),
      currencyCode: json['currency_code'] as String,
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      minimumDueMinor: (json['minimum_due_minor'] as num).toInt(),
      paidMinor: (json['paid_minor'] as num).toInt(),
      status: json['obligation_status'] as String,
      title: json['title'] as String,
      sortRank: (json['sort_rank'] as num).toInt(),
      details: rawDetails is Map
          ? Map<String, dynamic>.from(rawDetails)
          : const <String, dynamic>{},
    );
  }

  final String id;
  final HomeDueObligationKind kind;
  final String sourceAccountId;
  final String sourceName;
  final String? maskedIdentifier;
  final String relatedId;
  final PlainDate dueOn;
  final String currencyCode;
  final int remainingMinor;
  final int minimumDueMinor;
  final int paidMinor;
  final String status;
  final String title;
  final int sortRank;
  final Map<String, dynamic> details;

  Money get remaining =>
      Money(minor: remainingMinor, currencyCode: currencyCode);
  Money get minimumDue =>
      Money(minor: minimumDueMinor, currencyCode: currencyCode);
  Money get paid => Money(minor: paidMinor, currencyCode: currencyCode);

  bool get isOverdue => status == 'overdue';
  bool get isDueToday => status == 'due_today';
}

@immutable
class HomeDueCurrencyTotal {
  const HomeDueCurrencyTotal({
    required this.currencyCode,
    required this.totalMinor,
    required this.minimumMinor,
  });

  final String currencyCode;
  final int totalMinor;
  final int minimumMinor;

  Money get total => Money(minor: totalMinor, currencyCode: currencyCode);
  Money get minimum => Money(minor: minimumMinor, currencyCode: currencyCode);
}

@immutable
class HomeDueSummary {
  HomeDueSummary(List<HomeDueObligation> obligations)
    : obligations = List.unmodifiable(obligations),
      totals = _totalsFor(obligations);

  final List<HomeDueObligation> obligations;
  final List<HomeDueCurrencyTotal> totals;

  bool get isEmpty => obligations.isEmpty;
  int get count => obligations.length;
  bool get hasOverdue => obligations.any((obligation) => obligation.isOverdue);
  HomeDueObligation? get earliest => obligations.isEmpty
      ? null
      : obligations.reduce(
          (left, right) =>
              left.sortRank < right.sortRank ||
                  (left.sortRank == right.sortRank &&
                      left.dueOn.compareTo(right.dueOn) <= 0)
              ? left
              : right,
        );

  static List<HomeDueCurrencyTotal> _totalsFor(
    List<HomeDueObligation> obligations,
  ) {
    final grouped = <String, ({int total, int minimum})>{};
    for (final obligation in obligations) {
      final prior = grouped[obligation.currencyCode] ?? (total: 0, minimum: 0);
      grouped[obligation.currencyCode] = (
        total: prior.total + obligation.remainingMinor,
        minimum: prior.minimum + obligation.minimumDueMinor,
      );
    }
    return grouped.entries
        .map(
          (entry) => HomeDueCurrencyTotal(
            currencyCode: entry.key,
            totalMinor: entry.value.total,
            minimumMinor: entry.value.minimum,
          ),
        )
        .toList()
      ..sort((left, right) => left.currencyCode.compareTo(right.currencyCode));
  }
}
