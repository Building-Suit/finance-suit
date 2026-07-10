import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

/// A row from `public.salary_periods`.
@immutable
class SalaryPeriod {
  const SalaryPeriod({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.expectedPaymentDate,
    required this.status,
    this.snapshot,
    this.finalizedAt,
    this.actualAmountMinor,
    this.receivedDate,
    this.destinationAccountId,
    this.paidTransactionId,
    this.notes,
  });

  factory SalaryPeriod.fromJson(Map<String, dynamic> json) => SalaryPeriod(
    id: json['id'] as String,
    periodStart: PlainDate.parse(json['period_start'] as String),
    periodEnd: PlainDate.parse(json['period_end'] as String),
    expectedPaymentDate: PlainDate.parse(
      json['expected_payment_date'] as String,
    ),
    status: SalaryPeriodStatus.fromDb(json['status'] as String),
    snapshot: json['snapshot'] as Map<String, dynamic>?,
    finalizedAt: json['finalized_at'] == null
        ? null
        : DateTime.parse(json['finalized_at'] as String),
    actualAmountMinor: (json['actual_amount_minor'] as num?)?.toInt(),
    receivedDate: json['received_date'] == null
        ? null
        : PlainDate.parse(json['received_date'] as String),
    destinationAccountId: json['destination_account_id'] as String?,
    paidTransactionId: json['paid_transaction_id'] as String?,
    notes: json['notes'] as String?,
  );

  final String id;
  final PlainDate periodStart;
  final PlainDate periodEnd;
  final PlainDate expectedPaymentDate;
  final SalaryPeriodStatus status;
  final Map<String, dynamic>? snapshot;
  final DateTime? finalizedAt;
  final int? actualAmountMinor;
  final PlainDate? receivedDate;
  final String? destinationAccountId;
  final String? paidTransactionId;
  final String? notes;

  bool get isOpen => status == SalaryPeriodStatus.open;
  bool get isFinalized => status == SalaryPeriodStatus.finalized;
  bool get isPaid => status == SalaryPeriodStatus.paid;

  /// Estimated total stored in the finalize snapshot, when present.
  int? get snapshotTotalMinor => (snapshot?['total_minor'] as num?)?.toInt();
}
