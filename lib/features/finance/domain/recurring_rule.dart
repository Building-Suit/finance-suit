import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `app_finance.recurring_rules`: a scheduled expense (from
/// cash or a credit card) or transfer that materializes into pending
/// occurrences the user accepts, skips, or snoozes — the outflow twin of
/// [IncomeSource] automation.
@immutable
class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.name,
    required this.kind,
    required this.amountMinor,
    required this.currencyCode,
    required this.frequency,
    required this.paymentDay,
    required this.startDate,
    required this.promptDaysBefore,
    required this.sourceAccountId,
    required this.isActive,
    this.isForeignCurrency = false,
    this.destinationAccountId,
    this.categoryId,
    this.notes,
  });

  factory RecurringRule.fromJson(Map<String, dynamic> json) {
    return RecurringRule(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: RecurringRuleKind.fromDb(json['rule_kind'] as String),
      amountMinor: (json['amount_minor'] as num).toInt(),
      currencyCode: json['currency_code'] as String,
      frequency: RecurringFrequency.fromDb(json['frequency'] as String),
      paymentDay: (json['payment_day'] as num).toInt(),
      startDate: PlainDate.parse(json['start_date'] as String),
      promptDaysBefore: (json['prompt_days_before'] as num).toInt(),
      sourceAccountId: json['source_account_id'] as String,
      isActive: json['is_active'] as bool,
      isForeignCurrency: json['is_foreign_currency'] as bool? ?? false,
      destinationAccountId: json['destination_account_id'] as String?,
      categoryId: json['category_id'] as String?,
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String name;
  final RecurringRuleKind kind;
  final int amountMinor;
  final String currencyCode;
  final RecurringFrequency frequency;

  /// Day of month (1..28) for monthly/quarterly/annual rules; ISO weekday
  /// (1 = Monday .. 7 = Sunday) for weekly rules.
  final int paymentDay;
  final PlainDate startDate;
  final int promptDaysBefore;
  final String sourceAccountId;
  final bool isActive;
  final bool isForeignCurrency;
  final String? destinationAccountId;
  final String? categoryId;
  final String? notes;

  Money get amount => Money(minor: amountMinor, currencyCode: currencyCode);
}

/// A row from `app_finance.recurring_occurrences`.
@immutable
class RecurringOccurrence {
  const RecurringOccurrence({
    required this.id,
    required this.ruleId,
    required this.scheduledOn,
    required this.expectedAmountMinor,
    required this.status,
    this.actualAmountMinor,
    this.paidOn,
    this.transactionId,
    this.snoozedUntil,
    this.notes,
  });

  factory RecurringOccurrence.fromJson(Map<String, dynamic> json) {
    return RecurringOccurrence(
      id: json['id'] as String,
      ruleId: json['rule_id'] as String,
      scheduledOn: PlainDate.parse(json['scheduled_on'] as String),
      expectedAmountMinor: (json['expected_amount_minor'] as num).toInt(),
      status: IncomeOccurrenceStatus.fromDb(json['status'] as String),
      actualAmountMinor: (json['actual_amount_minor'] as num?)?.toInt(),
      paidOn: json['paid_on'] == null
          ? null
          : PlainDate.parse(json['paid_on'] as String),
      transactionId: json['transaction_id'] as String?,
      snoozedUntil: switch (json['snoozed_until']) {
        null => null,
        final String raw => DateTime.tryParse(raw),
        _ => null,
      },
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String ruleId;
  final PlainDate scheduledOn;
  final int expectedAmountMinor;
  final IncomeOccurrenceStatus status;
  final int? actualAmountMinor;
  final PlainDate? paidOn;
  final String? transactionId;
  final DateTime? snoozedUntil;
  final String? notes;
}

/// A pending occurrence joined with its rule, ready for the decision UI.
@immutable
class PendingRecurring {
  const PendingRecurring({required this.occurrence, required this.rule});

  final RecurringOccurrence occurrence;
  final RecurringRule rule;

  bool isDueOn(PlainDate today) => !occurrence.scheduledOn.isAfter(today);

  Money get expectedAmount => Money(
    minor: occurrence.expectedAmountMinor,
    currencyCode: rule.currencyCode,
  );
}
