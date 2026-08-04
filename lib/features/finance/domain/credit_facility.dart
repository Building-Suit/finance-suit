import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from the `app_finance.credit_facility_summaries` view: a liability
/// account (credit card or BNPL provider) plus its derived debt figures.
@immutable
class CreditFacilitySummary {
  const CreditFacilitySummary({
    required this.accountId,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.isArchived,
    required this.openingOwedMinor,
    required this.creditLimitMinor,
    required this.defaultDueDay,
    required this.reminderLeadDays,
    required this.outstandingMinor,
    required this.availableCreditMinor,
    required this.utilizationBasisPoints,
    required this.dueNowMinor,
    required this.overdueMinor,
    required this.activePlanCount,
    this.statementDay,
    this.lastFourDigits,
    this.nextDueOn,
    this.nextDueAmountMinor,
    this.notes,
  });

  factory CreditFacilitySummary.fromJson(Map<String, dynamic> json) {
    return CreditFacilitySummary(
      accountId: json['account_id'] as String,
      name: json['name'] as String,
      accountType: AccountType.fromDb(json['account_type'] as String),
      currencyCode: json['currency_code'] as String,
      isArchived: json['is_archived'] as bool,
      openingOwedMinor: (json['opening_owed_minor'] as num).toInt(),
      creditLimitMinor: (json['credit_limit_minor'] as num).toInt(),
      defaultDueDay: (json['default_due_day'] as num).toInt(),
      reminderLeadDays: (json['reminder_lead_days'] as num).toInt(),
      outstandingMinor: (json['outstanding_minor'] as num).toInt(),
      availableCreditMinor: (json['available_credit_minor'] as num).toInt(),
      utilizationBasisPoints: (json['utilization_basis_points'] as num).toInt(),
      dueNowMinor: (json['due_now_minor'] as num).toInt(),
      overdueMinor: (json['overdue_minor'] as num).toInt(),
      activePlanCount: (json['active_plan_count'] as num).toInt(),
      statementDay: (json['statement_day'] as num?)?.toInt(),
      lastFourDigits: json['last_four_digits'] as String?,
      nextDueOn: json['next_due_on'] == null
          ? null
          : PlainDate.parse(json['next_due_on'] as String),
      nextDueAmountMinor: (json['next_due_amount_minor'] as num?)?.toInt(),
      notes: json['notes'] as String?,
    );
  }

  final String accountId;
  final String name;
  final AccountType accountType;
  final String currencyCode;
  final bool isArchived;
  final int openingOwedMinor;
  final int creditLimitMinor;
  final int defaultDueDay;
  final int reminderLeadDays;
  final int outstandingMinor;
  final int availableCreditMinor;
  final int utilizationBasisPoints;
  final int dueNowMinor;
  final int overdueMinor;
  final int activePlanCount;
  final int? statementDay;
  final String? lastFourDigits;
  final PlainDate? nextDueOn;
  final int? nextDueAmountMinor;
  final String? notes;

  Money get outstanding =>
      Money(minor: outstandingMinor, currencyCode: currencyCode);
  Money get availableCredit =>
      Money(minor: availableCreditMinor, currencyCode: currencyCode);
  Money get creditLimit =>
      Money(minor: creditLimitMinor, currencyCode: currencyCode);
  Money get dueNow => Money(minor: dueNowMinor, currencyCode: currencyCode);
  Money get overdue => Money(minor: overdueMinor, currencyCode: currencyCode);
  Money? get nextDueAmount => nextDueAmountMinor == null
      ? null
      : Money(minor: nextDueAmountMinor!, currencyCode: currencyCode);

  bool get hasOverdue => overdueMinor > 0;

  /// Utilization as a 0..1 fraction for progress indicators.
  double get utilizationFraction =>
      (utilizationBasisPoints.clamp(0, 10000)) / 10000;
}

/// A row from `app_finance.installment_plan_summaries`.
@immutable
class InstallmentPlan {
  const InstallmentPlan({
    required this.id,
    required this.accountId,
    required this.title,
    required this.categoryId,
    required this.purchasedOn,
    required this.firstDueOn,
    required this.installmentCount,
    required this.purchasePriceMinor,
    required this.downPaymentMinor,
    required this.financedPrincipalMinor,
    required this.financingFeesMinor,
    required this.totalPayableMinor,
    required this.currencyCode,
    required this.status,
    required this.paidMinor,
    required this.remainingMinor,
    this.nextDueOn,
    this.nextDueAmountMinor,
    this.notes,
  });

  factory InstallmentPlan.fromJson(Map<String, dynamic> json) {
    return InstallmentPlan(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      title: json['title'] as String,
      categoryId: json['category_id'] as String,
      purchasedOn: PlainDate.parse(json['purchased_on'] as String),
      firstDueOn: PlainDate.parse(json['first_due_on'] as String),
      installmentCount: (json['installment_count'] as num).toInt(),
      purchasePriceMinor: (json['purchase_price_minor'] as num).toInt(),
      downPaymentMinor: (json['down_payment_minor'] as num).toInt(),
      financedPrincipalMinor: (json['financed_principal_minor'] as num).toInt(),
      financingFeesMinor: (json['financing_fees_minor'] as num).toInt(),
      totalPayableMinor: (json['total_payable_minor'] as num).toInt(),
      currencyCode: json['currency_code'] as String,
      status: InstallmentPlanStatus.fromDb(json['status'] as String),
      paidMinor: (json['paid_minor'] as num).toInt(),
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      nextDueOn: json['next_due_on'] == null
          ? null
          : PlainDate.parse(json['next_due_on'] as String),
      nextDueAmountMinor: (json['next_due_amount_minor'] as num?)?.toInt(),
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String accountId;
  final String title;
  final String categoryId;
  final PlainDate purchasedOn;
  final PlainDate firstDueOn;
  final int installmentCount;
  final int purchasePriceMinor;
  final int downPaymentMinor;
  final int financedPrincipalMinor;
  final int financingFeesMinor;
  final int totalPayableMinor;
  final String currencyCode;
  final InstallmentPlanStatus status;
  final int paidMinor;
  final int remainingMinor;
  final PlainDate? nextDueOn;
  final int? nextDueAmountMinor;
  final String? notes;

  Money get totalPayable =>
      Money(minor: totalPayableMinor, currencyCode: currencyCode);
  Money get paid => Money(minor: paidMinor, currencyCode: currencyCode);
  Money get remaining =>
      Money(minor: remainingMinor, currencyCode: currencyCode);
  Money get purchasePrice =>
      Money(minor: purchasePriceMinor, currencyCode: currencyCode);
}

/// A row from `app_finance.installment_due_statuses`.
@immutable
class InstallmentDue {
  const InstallmentDue({
    required this.id,
    required this.planId,
    required this.accountId,
    required this.sequenceNumber,
    required this.dueOn,
    required this.amountMinor,
    required this.currencyCode,
    required this.planTitle,
    required this.planStatus,
    required this.paidMinor,
    required this.remainingMinor,
    required this.status,
  });

  factory InstallmentDue.fromJson(Map<String, dynamic> json) {
    return InstallmentDue(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      accountId: json['account_id'] as String,
      sequenceNumber: (json['sequence_number'] as num).toInt(),
      dueOn: PlainDate.parse(json['due_on'] as String),
      amountMinor: (json['amount_minor'] as num).toInt(),
      currencyCode: json['currency_code'] as String,
      planTitle: json['plan_title'] as String,
      planStatus: InstallmentPlanStatus.fromDb(json['plan_status'] as String),
      paidMinor: (json['paid_minor'] as num).toInt(),
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      status: InstallmentDueStatus.fromDb(json['due_status'] as String),
    );
  }

  final String id;
  final String planId;
  final String accountId;
  final int sequenceNumber;
  final PlainDate dueOn;
  final int amountMinor;
  final String currencyCode;
  final String planTitle;
  final InstallmentPlanStatus planStatus;
  final int paidMinor;
  final int remainingMinor;
  final InstallmentDueStatus status;

  Money get amount => Money(minor: amountMinor, currencyCode: currencyCode);
  Money get remaining =>
      Money(minor: remainingMinor, currencyCode: currencyCode);

  /// Recomputes the status against the device's business date so a stale
  /// server projection (UTC midnight skew) never mislabels a due.
  InstallmentDueStatus statusFor(PlainDate today) {
    if (planStatus == InstallmentPlanStatus.cancelled) {
      return InstallmentDueStatus.cancelled;
    }
    if (remainingMinor <= 0) return InstallmentDueStatus.paid;
    if (dueOn.isBefore(today)) return InstallmentDueStatus.overdue;
    if (dueOn == today) return InstallmentDueStatus.dueToday;
    if (paidMinor > 0) return InstallmentDueStatus.partiallyPaid;
    return InstallmentDueStatus.upcoming;
  }
}

/// Payload for `app_finance.save_credit_facility`.
@immutable
class CreditFacilityDraft {
  const CreditFacilityDraft({
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.openingOwedMinor,
    required this.creditLimitMinor,
    required this.defaultDueDay,
    this.statementDay,
    this.lastFourDigits,
    this.reminderLeadDays = 3,
    this.notes,
    this.accountId,
  });

  final String name;
  final AccountType accountType;
  final String currencyCode;
  final int openingOwedMinor;
  final int creditLimitMinor;
  final int defaultDueDay;
  final int? statementDay;
  final String? lastFourDigits;
  final int reminderLeadDays;
  final String? notes;
  final String? accountId;

  Map<String, dynamic> toJson() => {
    'p_name': name,
    'p_account_type': accountType.dbValue,
    'p_currency_code': currencyCode,
    'p_opening_owed_minor': openingOwedMinor,
    'p_credit_limit_minor': creditLimitMinor,
    'p_default_due_day': defaultDueDay,
    'p_statement_day': statementDay,
    'p_last_four_digits': lastFourDigits,
    'p_reminder_lead_days': reminderLeadDays,
    'p_notes': notes,
    'p_account_id': accountId,
  };
}

/// Payload for `app_finance.create_installment_plan`.
///
/// Exactly one of [financingFeesMinor] or [totalPayableMinor] may be sent;
/// sending both requires them to agree, and sending neither means no fees.
@immutable
class InstallmentPlanDraft {
  const InstallmentPlanDraft({
    required this.accountId,
    required this.title,
    required this.categoryId,
    required this.purchasedOn,
    required this.purchasePriceMinor,
    required this.installmentCount,
    required this.firstDueOn,
    this.downPaymentMinor = 0,
    this.downPaymentAccountId,
    this.financingFeesMinor,
    this.totalPayableMinor,
    this.notes,
    this.planId,
  });

  final String accountId;
  final String title;
  final String categoryId;
  final PlainDate purchasedOn;
  final int purchasePriceMinor;
  final int installmentCount;
  final PlainDate firstDueOn;
  final int downPaymentMinor;
  final String? downPaymentAccountId;
  final int? financingFeesMinor;
  final int? totalPayableMinor;
  final String? notes;

  /// Client-generated id makes retries idempotent server-side.
  final String? planId;

  Map<String, dynamic> toJson() => {
    'p_account_id': accountId,
    'p_title': title,
    'p_category_id': categoryId,
    'p_purchased_on': purchasedOn.toIso(),
    'p_purchase_price_minor': purchasePriceMinor,
    'p_installment_count': installmentCount,
    'p_first_due_on': firstDueOn.toIso(),
    'p_down_payment_minor': downPaymentMinor,
    'p_down_payment_account_id': downPaymentAccountId,
    'p_financing_fees_minor': financingFeesMinor,
    'p_total_payable_minor': totalPayableMinor,
    'p_notes': notes,
    'p_plan_id': planId,
  };
}

/// Payload for `app_finance.pay_credit_facility`.
@immutable
class FacilityPaymentDraft {
  const FacilityPaymentDraft({
    required this.accountId,
    required this.sourceAccountId,
    required this.amountMinor,
    required this.paidOn,
    this.allocations,
    this.notes,
    this.paymentId,
  });

  final String accountId;
  final String sourceAccountId;
  final int amountMinor;
  final PlainDate paidOn;

  /// Explicit `{due_id, amount_minor}` allocations; null auto-allocates
  /// oldest due first.
  final List<({String dueId, int amountMinor})>? allocations;
  final String? notes;

  /// Client-generated id makes retries idempotent server-side.
  final String? paymentId;

  Map<String, dynamic> toJson() => {
    'p_account_id': accountId,
    'p_source_account_id': sourceAccountId,
    'p_amount_minor': amountMinor,
    'p_paid_on': paidOn.toIso(),
    'p_allocations': allocations
        ?.map((a) => {'due_id': a.dueId, 'amount_minor': a.amountMinor})
        .toList(),
    'p_notes': notes,
    'p_payment_id': paymentId,
  };
}

/// Pure schedule preview used by the purchase form; must mirror the SQL
/// rounding exactly: the first `total mod count` installments carry one
/// extra minor unit and every generated date clamps to shorter months.
List<({int sequence, PlainDate dueOn, int amountMinor})>
previewInstallmentSchedule({
  required int totalPayableMinor,
  required int installmentCount,
  required PlainDate firstDueOn,
}) {
  assert(installmentCount >= 1);
  final base = totalPayableMinor ~/ installmentCount;
  final remainder = totalPayableMinor % installmentCount;
  return [
    for (var i = 1; i <= installmentCount; i++)
      (
        sequence: i,
        dueOn: firstDueOn.addMonths(i - 1),
        amountMinor: base + (i <= remainder ? 1 : 0),
      ),
  ];
}
