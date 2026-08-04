import 'dart:math' as math;

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
    this.facilityStatus = FacilityStatus.active,
    this.minPaymentMethod = MinPaymentMethod.full,
    this.minPaymentFixedMinor,
    this.minPaymentBasisPoints,
    this.statementRemainingMinor = 0,
    this.nextStatementDueOn,
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
      facilityStatus: FacilityStatus.fromDb(
        json['facility_status'] as String? ?? 'active',
      ),
      minPaymentMethod: MinPaymentMethod.fromDb(
        json['min_payment_method'] as String? ?? 'full',
      ),
      minPaymentFixedMinor: (json['min_payment_fixed_minor'] as num?)?.toInt(),
      minPaymentBasisPoints: (json['min_payment_basis_points'] as num?)
          ?.toInt(),
      statementRemainingMinor:
          (json['statement_remaining_minor'] as num?)?.toInt() ?? 0,
      nextStatementDueOn: json['next_statement_due_on'] == null
          ? null
          : PlainDate.parse(json['next_statement_due_on'] as String),
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
  final FacilityStatus facilityStatus;
  final MinPaymentMethod minPaymentMethod;
  final int? minPaymentFixedMinor;
  final int? minPaymentBasisPoints;
  final int statementRemainingMinor;
  final PlainDate? nextStatementDueOn;
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

  /// New purchases require an active facility on an unarchived account.
  bool get canFundPurchases =>
      !isArchived && facilityStatus == FacilityStatus.active;

  /// A facility disappears completely only when it never carried history;
  /// everything else archives. Whether history exists is decided server
  /// side, so the delete action is always offered and may fail politely.
  bool get hasDebt => outstandingMinor > 0;

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
    this.pricingMethod = PlanPricingMethod.manualFees,
    this.interestRateBasisPoints = 0,
    this.interestRatePeriod = InterestRatePeriod.monthly,
    this.interestMethod = InterestMethod.flat,
    this.interestMinor = 0,
    this.origin = PlanOrigin.app,
    this.revision = 1,
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
      pricingMethod: PlanPricingMethod.fromDb(
        json['pricing_method'] as String? ?? 'manual_fees',
      ),
      interestRateBasisPoints:
          (json['interest_rate_basis_points'] as num?)?.toInt() ?? 0,
      interestRatePeriod: InterestRatePeriod.fromDb(
        json['interest_rate_period'] as String? ?? 'monthly',
      ),
      interestMethod: InterestMethod.fromDb(
        json['interest_method'] as String? ?? 'flat',
      ),
      interestMinor: (json['interest_minor'] as num?)?.toInt() ?? 0,
      origin: PlanOrigin.fromDb(json['origin'] as String? ?? 'app'),
      revision: (json['revision'] as num?)?.toInt() ?? 1,
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
  final PlanPricingMethod pricingMethod;
  final int interestRateBasisPoints;
  final InterestRatePeriod interestRatePeriod;
  final InterestMethod interestMethod;
  final int interestMinor;
  final PlanOrigin origin;
  final int revision;
  final PlainDate? nextDueOn;
  final int? nextDueAmountMinor;
  final String? notes;

  /// Whether the plan still accepts edits or restructures at all. Which of
  /// the two applies depends on recorded payments, which the server checks
  /// authoritatively when the RPC runs.
  bool get isEditable => status == InstallmentPlanStatus.active;

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
    this.isPresettled = false,
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
      isPresettled: json['is_presettled'] as bool? ?? false,
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

  /// Paid before Finance Suit tracking began (imported running plan).
  final bool isPresettled;

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
///
/// There is deliberately no opening-owed input anymore: new facilities
/// always start at zero debt and existing imported debt is preserved
/// server-side.
@immutable
class CreditFacilityDraft {
  const CreditFacilityDraft({
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.creditLimitMinor,
    required this.defaultDueDay,
    this.statementDay,
    this.lastFourDigits,
    this.reminderLeadDays = 3,
    this.notes,
    this.accountId,
    this.facilityStatus = FacilityStatus.active,
    this.minPaymentMethod = MinPaymentMethod.full,
    this.minPaymentFixedMinor,
    this.minPaymentBasisPoints,
  });

  final String name;
  final AccountType accountType;
  final String currencyCode;
  final int creditLimitMinor;
  final int defaultDueDay;
  final int? statementDay;
  final String? lastFourDigits;
  final int reminderLeadDays;
  final String? notes;
  final String? accountId;
  final FacilityStatus facilityStatus;
  final MinPaymentMethod minPaymentMethod;
  final int? minPaymentFixedMinor;
  final int? minPaymentBasisPoints;

  Map<String, dynamic> toJson() => {
    'p_name': name,
    'p_account_type': accountType.dbValue,
    'p_currency_code': currencyCode,
    'p_credit_limit_minor': creditLimitMinor,
    'p_default_due_day': defaultDueDay,
    'p_statement_day': statementDay,
    'p_last_four_digits': lastFourDigits,
    'p_reminder_lead_days': reminderLeadDays,
    'p_notes': notes,
    'p_account_id': accountId,
    'p_facility_status': facilityStatus.dbValue,
    'p_min_payment_method': minPaymentMethod.dbValue,
    'p_min_payment_fixed_minor': minPaymentFixedMinor,
    'p_min_payment_basis_points': minPaymentBasisPoints,
  };
}

/// Payload for `app_finance.create_installment_plan` and
/// `app_finance.update_installment_plan`.
///
/// The financing inputs depend on [pricingMethod]:
/// - `manualFees`: [financingFeesMinor] (plus optional [financedFeesMinor]).
/// - `totalPayable`: [totalPayableMinor].
/// - `monthlyAmount`: [monthlyPaymentMinor].
/// - `interestRate`: [interestRateBasisPoints], [interestRatePeriod],
///   [interestMethod].
/// [upfrontFeesMinor] is paid in cash immediately; [financedFeesMinor] rides
/// on top of the schedule. [paidInstallments] imports a running plan by
/// marking that many leading dues as already settled outside the app.
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
    this.pricingMethod = PlanPricingMethod.manualFees,
    this.monthlyPaymentMinor,
    this.interestRateBasisPoints = 0,
    this.interestRatePeriod = InterestRatePeriod.monthly,
    this.interestMethod = InterestMethod.flat,
    this.financedFeesMinor = 0,
    this.upfrontFeesMinor = 0,
    this.downPaidOn,
    this.paidInstallments = 0,
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
  final PlanPricingMethod pricingMethod;
  final int? monthlyPaymentMinor;
  final int interestRateBasisPoints;
  final InterestRatePeriod interestRatePeriod;
  final InterestMethod interestMethod;
  final int financedFeesMinor;
  final int upfrontFeesMinor;
  final PlainDate? downPaidOn;
  final int paidInstallments;

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
    'p_pricing_method': pricingMethod.dbValue,
    'p_monthly_payment_minor': monthlyPaymentMinor,
    'p_interest_rate_basis_points': interestRateBasisPoints,
    'p_interest_rate_period': interestRatePeriod.dbValue,
    'p_interest_method': interestMethod.dbValue,
    'p_financed_fees_minor': financedFeesMinor,
    'p_upfront_fees_minor': upfrontFeesMinor,
    'p_down_paid_on': downPaidOn?.toIso(),
    'p_paid_installments': paidInstallments,
  };

  /// The update RPC keeps the same shape minus account, plan id, and
  /// upfront fees (already paid in cash and never rebooked by an edit).
  Map<String, dynamic> toUpdateJson(String planId) => {
    'p_plan_id': planId,
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
    'p_pricing_method': pricingMethod.dbValue,
    'p_monthly_payment_minor': monthlyPaymentMinor,
    'p_interest_rate_basis_points': interestRateBasisPoints,
    'p_interest_rate_period': interestRatePeriod.dbValue,
    'p_interest_method': interestMethod.dbValue,
    'p_financed_fees_minor': financedFeesMinor,
    'p_down_paid_on': downPaidOn?.toIso(),
    'p_paid_installments': paidInstallments,
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

/// A row from `app_finance.credit_card_statement_summaries`: one billing
/// cycle of a credit card with its charges, payments, and derived status.
@immutable
class CardStatementSummary {
  const CardStatementSummary({
    required this.id,
    required this.accountId,
    required this.currencyCode,
    required this.cycleStart,
    required this.cycleClose,
    required this.dueOn,
    required this.chargesMinor,
    required this.paidMinor,
    required this.remainingMinor,
    required this.minimumDueMinor,
    required this.status,
  });

  factory CardStatementSummary.fromJson(Map<String, dynamic> json) {
    return CardStatementSummary(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      currencyCode: json['currency_code'] as String,
      cycleStart: PlainDate.parse(json['cycle_start'] as String),
      cycleClose: PlainDate.parse(json['cycle_close'] as String),
      dueOn: PlainDate.parse(json['due_on'] as String),
      chargesMinor: (json['charges_minor'] as num).toInt(),
      paidMinor: (json['paid_minor'] as num).toInt(),
      remainingMinor: (json['remaining_minor'] as num).toInt(),
      minimumDueMinor: (json['minimum_due_minor'] as num).toInt(),
      status: StatementCycleStatus.fromDb(json['cycle_status'] as String),
    );
  }

  final String id;
  final String accountId;
  final String currencyCode;
  final PlainDate cycleStart;
  final PlainDate cycleClose;
  final PlainDate dueOn;
  final int chargesMinor;
  final int paidMinor;
  final int remainingMinor;
  final int minimumDueMinor;
  final StatementCycleStatus status;

  Money get charges => Money(minor: chargesMinor, currencyCode: currencyCode);
  Money get remaining =>
      Money(minor: remainingMinor, currencyCode: currencyCode);
  Money get minimumDue =>
      Money(minor: minimumDueMinor, currencyCode: currencyCode);
}

/// A row from `app_finance.installment_plan_revisions`: one restructure of
/// a running plan, kept for the audit trail.
@immutable
class InstallmentPlanRevision {
  const InstallmentPlanRevision({
    required this.id,
    required this.planId,
    required this.revision,
    required this.changeSummary,
    required this.previousTotalPayableMinor,
    required this.newTotalPayableMinor,
  });

  factory InstallmentPlanRevision.fromJson(Map<String, dynamic> json) {
    return InstallmentPlanRevision(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      revision: (json['revision'] as num).toInt(),
      changeSummary: json['change_summary'] as String,
      previousTotalPayableMinor: (json['previous_total_payable_minor'] as num)
          .toInt(),
      newTotalPayableMinor: (json['new_total_payable_minor'] as num).toInt(),
    );
  }

  final String id;
  final String planId;
  final int revision;
  final String changeSummary;
  final int previousTotalPayableMinor;
  final int newTotalPayableMinor;
}

/// Client-side preview of `app_finance.resolve_plan_financing`. The server
/// recomputes authoritatively on save; this only powers the live preview
/// card, so double-precision annuity math is acceptable here.
({int interestMinor, int feesMinor, int totalMinor})? previewPlanFinancing({
  required PlanPricingMethod pricingMethod,
  required int principalMinor,
  required int count,
  int? manualFeesMinor,
  int? totalPayableMinor,
  int? monthlyPaymentMinor,
  int rateBasisPoints = 0,
  InterestRatePeriod ratePeriod = InterestRatePeriod.monthly,
  InterestMethod interestMethod = InterestMethod.flat,
  int financedFeesMinor = 0,
}) {
  if (principalMinor <= 0 || count < 1 || financedFeesMinor < 0) return null;
  switch (pricingMethod) {
    case PlanPricingMethod.manualFees:
      final fees = (manualFeesMinor ?? 0) + financedFeesMinor;
      if (fees < 0) return null;
      return (
        interestMinor: 0,
        feesMinor: fees,
        totalMinor: principalMinor + fees,
      );
    case PlanPricingMethod.totalPayable:
      final total = totalPayableMinor;
      if (total == null || total < principalMinor) return null;
      final fees = total - principalMinor;
      final interest = fees - financedFeesMinor;
      if (interest < 0) return null;
      return (interestMinor: interest, feesMinor: fees, totalMinor: total);
    case PlanPricingMethod.monthlyAmount:
      final monthly = monthlyPaymentMinor;
      if (monthly == null || monthly <= 0) return null;
      if (monthly * count < principalMinor) return null;
      final interest = monthly * count - principalMinor;
      final fees = interest + financedFeesMinor;
      return (
        interestMinor: interest,
        feesMinor: fees,
        totalMinor: principalMinor + fees,
      );
    case PlanPricingMethod.interestRate:
      var rate = rateBasisPoints / 10000;
      if (ratePeriod == InterestRatePeriod.annual) rate /= 12;
      int interest;
      if (rate <= 0) {
        interest = 0;
      } else if (interestMethod == InterestMethod.flat) {
        interest = (principalMinor * rate * count).round();
      } else {
        final denominator = 1 - math.pow(1 + rate, -count).toDouble();
        final pmt = principalMinor * rate / denominator;
        interest = (pmt * count - principalMinor).round();
      }
      if (interest < 0) interest = 0;
      final fees = interest + financedFeesMinor;
      return (
        interestMinor: interest,
        feesMinor: fees,
        totalMinor: principalMinor + fees,
      );
  }
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
