import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

@immutable
class IncomeAllocation {
  const IncomeAllocation({
    required this.destinationAccountId,
    required this.percentageBasisPoints,
    this.id,
    this.sortOrder = 0,
  });

  factory IncomeAllocation.fromJson(Map<String, dynamic> json) =>
      IncomeAllocation(
        id: json['id'] as String?,
        destinationAccountId: json['destination_account_id'] as String,
        percentageBasisPoints: (json['percentage_basis_points'] as num).toInt(),
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  final String? id;
  final String destinationAccountId;
  final int percentageBasisPoints;
  final int sortOrder;

  double get percentage => percentageBasisPoints / 100;

  Map<String, dynamic> toPayload() => {
    'destination_account_id': destinationAccountId,
    'percentage_basis_points': percentageBasisPoints,
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
  final String? notes;

  Money get expectedAmount =>
      Money(minor: expectedAmountMinor, currencyCode: currencyCode);

  int get allocatedBasisPoints => allocations.fold(
    0,
    (total, allocation) => total + allocation.percentageBasisPoints,
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
    this.notes,
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
        notes: json['notes'] as String?,
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
  final String? notes;
}

@immutable
class PendingIncome {
  const PendingIncome({required this.occurrence, required this.source});

  final IncomeOccurrence occurrence;
  final IncomeSource source;

  bool isDueOn(PlainDate today) => occurrence.scheduledOn <= today;
}
