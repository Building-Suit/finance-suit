import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

/// A row from `public.salary_adjustments` (salary-only bonus or deduction).
@immutable
class SalaryAdjustment {
  const SalaryAdjustment({
    required this.id,
    required this.effectiveDate,
    required this.adjustmentType,
    required this.amountMinor,
    this.title,
    this.notes,
  });

  factory SalaryAdjustment.fromJson(Map<String, dynamic> json) =>
      SalaryAdjustment(
        id: json['id'] as String,
        effectiveDate: PlainDate.parse(json['effective_date'] as String),
        adjustmentType: AdjustmentType.fromDb(
          json['adjustment_type'] as String,
        ),
        amountMinor: (json['amount_minor'] as num).toInt(),
        title: json['title'] as String?,
        notes: json['notes'] as String?,
      );

  final String id;
  final PlainDate effectiveDate;
  final AdjustmentType adjustmentType;
  final int amountMinor;
  final String? title;
  final String? notes;
}

/// Insert/update payload for a salary adjustment.
@immutable
class SalaryAdjustmentDraft {
  const SalaryAdjustmentDraft({
    required this.effectiveDate,
    required this.adjustmentType,
    required this.amountMinor,
    this.title,
    this.notes,
  });

  final PlainDate effectiveDate;
  final AdjustmentType adjustmentType;
  final int amountMinor;
  final String? title;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'effective_date': effectiveDate.toIso(),
    'adjustment_type': adjustmentType.dbValue,
    'amount_minor': amountMinor,
    'title': title,
    'notes': notes,
  };
}
