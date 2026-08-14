import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

@immutable
class IncomeAllocation {
  const IncomeAllocation({
    required this.method,
    this.destinationAccountId,
    this.destinationNetworkConnectionId,
    this.id,
    this.calculationBasis = IncomeAllocationCalculationBasis.original,
    this.percentageBasisPoints,
    this.fixedAmountMinor,
    this.sortOrder = 0,
  });

  factory IncomeAllocation.fromJson(Map<String, dynamic> json) =>
      IncomeAllocation(
        id: json['id'] as String?,
        destinationAccountId: json['destination_account_id'] as String?,
        destinationNetworkConnectionId:
            json['destination_network_connection_id'] as String?,
        method: IncomeAllocationMethod.fromDb(
          json['allocation_method'] as String? ?? 'percentage',
        ),
        calculationBasis: IncomeAllocationCalculationBasis.fromDb(
          json['calculation_basis'] as String? ?? 'original',
        ),
        percentageBasisPoints: (json['percentage_basis_points'] as num?)
            ?.toInt(),
        fixedAmountMinor: (json['fixed_amount_minor'] as num?)?.toInt(),
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  final String? id;

  /// Exactly one of [destinationAccountId] and
  /// [destinationNetworkConnectionId] is set: a split lands either in an own
  /// account or, as a pending network transfer, with a connected person.
  final String? destinationAccountId;
  final String? destinationNetworkConnectionId;
  final IncomeAllocationMethod method;
  final IncomeAllocationCalculationBasis calculationBasis;
  final int? percentageBasisPoints;
  final int? fixedAmountMinor;
  final int sortOrder;

  double get percentage => (percentageBasisPoints ?? 0) / 100;

  bool get isNetworkDestination => destinationNetworkConnectionId != null;

  /// Stable display/lookup key regardless of the destination shape.
  String get destinationKey =>
      destinationAccountId ?? destinationNetworkConnectionId ?? '';

  Map<String, dynamic> toPayload() => {
    'destination_account_id': destinationAccountId,
    'destination_network_connection_id': destinationNetworkConnectionId,
    'allocation_method': method.dbValue,
    'calculation_basis': calculationBasis.dbValue,
    'percentage_basis_points': percentageBasisPoints,
    'fixed_amount_minor': fixedAmountMinor,
  };
}

@immutable
class IncomeSource {
  const IncomeSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.expectedAmountMinor,
    required this.currencyCode,
    required this.paymentDay,
    required this.startDate,
    required this.promptDaysBefore,
    required this.primaryAccountId,
    required this.isActive,
    required this.allocations,
    this.includeExtraWorkInPercentage = true,
    this.extraWorkDestinationAccountId,
    this.extraWorkDestinationNetworkConnectionId,
    this.rolloverBalanceEnabled = false,
    this.rolloverDestinationAccountId,
    this.categoryId,
    this.notes,
  });

  factory IncomeSource.fromJson(Map<String, dynamic> json) {
    final allocations =
        (json['income_source_allocations'] as List<dynamic>? ?? const [])
            .map(
              (row) => IncomeAllocation.fromJson(row as Map<String, dynamic>),
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return IncomeSource(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: IncomeSourceKind.fromDb(json['source_kind'] as String),
      expectedAmountMinor: (json['expected_amount_minor'] as num).toInt(),
      currencyCode: json['currency_code'] as String,
      paymentDay: (json['payment_day'] as num).toInt(),
      startDate: PlainDate.parse(json['start_date'] as String),
      promptDaysBefore: (json['prompt_days_before'] as num).toInt(),
      primaryAccountId: json['primary_account_id'] as String,
      categoryId: json['category_id'] as String?,
      isActive: json['is_active'] as bool,
      allocations: allocations,
      includeExtraWorkInPercentage:
          json['include_extra_work_in_percentage'] as bool? ?? true,
      extraWorkDestinationAccountId:
          json['extra_work_destination_account_id'] as String?,
      extraWorkDestinationNetworkConnectionId:
          json['extra_work_destination_network_connection_id'] as String?,
      rolloverBalanceEnabled:
          json['rollover_balance_enabled'] as bool? ?? false,
      rolloverDestinationAccountId:
          json['rollover_destination_account_id'] as String?,
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String name;
  final IncomeSourceKind kind;
  final int expectedAmountMinor;
  final String currencyCode;
  final int paymentDay;
  final PlainDate startDate;
  final int promptDaysBefore;
  final String primaryAccountId;
  final String? categoryId;
  final bool isActive;
  final List<IncomeAllocation> allocations;
  final bool includeExtraWorkInPercentage;
  final String? extraWorkDestinationAccountId;

  /// Set instead of [extraWorkDestinationAccountId] when the protected
  /// extra-work pay routes to a network contact as a pending transfer.
  final String? extraWorkDestinationNetworkConnectionId;
  final bool rolloverBalanceEnabled;
  final String? rolloverDestinationAccountId;
  final String? notes;

  Money get expectedAmount =>
      Money(minor: expectedAmountMinor, currencyCode: currencyCode);

  int get allocatedBasisPoints => allocations.fold(
    0,
    (total, allocation) =>
        total +
        (allocation.method == IncomeAllocationMethod.percentage
            ? allocation.percentageBasisPoints ?? 0
            : 0),
  );

  int get remainderBasisPoints => 10000 - allocatedBasisPoints;
}

@immutable
class IncomeOccurrence {
  const IncomeOccurrence({
    required this.id,
    required this.incomeSourceId,
    required this.scheduledOn,
    required this.expectedAmountMinor,
    required this.status,
    this.actualAmountMinor,
    this.receivedOn,
    this.primaryTransactionId,
    this.salaryPeriodId,
    this.snoozedUntil,
    this.notes,
    this.remainderOfOccurrenceId,
  });

  factory IncomeOccurrence.fromJson(Map<String, dynamic> json) =>
      IncomeOccurrence(
        id: json['id'] as String,
        incomeSourceId: json['income_source_id'] as String,
        scheduledOn: PlainDate.parse(json['scheduled_on'] as String),
        expectedAmountMinor: (json['expected_amount_minor'] as num).toInt(),
        status: IncomeOccurrenceStatus.fromDb(json['status'] as String),
        actualAmountMinor: (json['actual_amount_minor'] as num?)?.toInt(),
        receivedOn: json['received_on'] == null
            ? null
            : PlainDate.parse(json['received_on'] as String),
        primaryTransactionId: json['primary_transaction_id'] as String?,
        salaryPeriodId: json['salary_period_id'] as String?,
        snoozedUntil: switch (json['snoozed_until']) {
          final String value => DateTime.parse(value).toUtc(),
          null => null,
          final DateTime value => value.toUtc(),
          _ => null,
        },
        notes: json['notes'] as String?,
        remainderOfOccurrenceId: json['remainder_of_occurrence_id'] as String?,
      );

  final String id;
  final String incomeSourceId;
  final PlainDate scheduledOn;
  final int expectedAmountMinor;
  final IncomeOccurrenceStatus status;
  final int? actualAmountMinor;
  final PlainDate? receivedOn;
  final String? primaryTransactionId;
  final String? salaryPeriodId;
  final DateTime? snoozedUntil;
  final String? notes;

  /// Set when this row tracks the unpaid part of a partially accepted
  /// occurrence: accepting it books the late money plainly, without a
  /// second salary period or split pass.
  final String? remainderOfOccurrenceId;

  bool get isRemainder => remainderOfOccurrenceId != null;
}

@immutable
class PendingIncome {
  const PendingIncome({required this.occurrence, required this.source});

  final IncomeOccurrence occurrence;
  final IncomeSource source;

  bool isDueOn(PlainDate today) => occurrence.scheduledOn <= today;
}

/// Reduces every pending occurrence to the list worth prompting about.
///
/// A source is collapsed to its earliest scheduled occurrence so a paused
/// month does not stack up months of cards. Remainders are exempt: they are
/// money owed from a payment that already happened, so one must never be
/// hidden behind the next scheduled salary — which is exactly what happens
/// when a partial acceptance lands on the day the next month is scheduled.
List<PendingIncome> collapsePendingIncome(
  List<PendingIncome> items,
  PlainDate today,
) {
  final collapsed = <String, PendingIncome>{};
  for (final item in items) {
    final key = item.occurrence.isRemainder
        ? 'remainder:${item.occurrence.id}'
        : 'schedule:${item.source.id}';
    collapsed.putIfAbsent(key, () => item);
  }
  final grouped = collapsed.values.toList();
  grouped.sort((left, right) {
    final leftDue = left.occurrence.scheduledOn <= today;
    final rightDue = right.occurrence.scheduledOn <= today;
    if (leftDue != rightDue) return leftDue ? -1 : 1;
    final date = left.occurrence.scheduledOn.compareTo(
      right.occurrence.scheduledOn,
    );
    if (date != 0) return date;
    // Older money first: a remainder came from a payment that predates the
    // occurrence it shares a date with.
    if (left.occurrence.isRemainder != right.occurrence.isRemainder) {
      return left.occurrence.isRemainder ? -1 : 1;
    }
    final name = left.source.name.toLowerCase().compareTo(
      right.source.name.toLowerCase(),
    );
    if (name != 0) return name;
    return left.occurrence.id.compareTo(right.occurrence.id);
  });
  return grouped;
}
