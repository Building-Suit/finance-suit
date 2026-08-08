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
    this.installmentDueDay,
    this.gracePeriodDays = 0,
    this.minPaymentPercentageBasis = MinPaymentPercentageBasis.statementTotal,
    this.minPaymentIncludeInstallmentDues = false,
    this.minPaymentIncludeBankFees = true,
    this.minPaymentIncludeOverdue = false,
    this.minPaymentFixedFloorMinor,
    this.statementRemainingMinor = 0,
    this.nextStatementDueOn,
    this.statementDay,
    this.lastFourDigits,
    this.nextDueOn,
    this.nextDueAmountMinor,
    this.upcomingDueMinor = 0,
    this.colorHex,
    this.fxMarkupBasisPoints,
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
      installmentDueDay: (json['installment_due_day'] as num?)?.toInt(),
      gracePeriodDays: (json['grace_period_days'] as num?)?.toInt() ?? 0,
      minPaymentPercentageBasis: MinPaymentPercentageBasis.fromDb(
        json['min_payment_percentage_basis'] as String? ?? 'statement_total',
      ),
      minPaymentIncludeInstallmentDues:
          json['min_payment_include_installment_dues'] as bool? ?? false,
      minPaymentIncludeBankFees:
          json['min_payment_include_bank_fees'] as bool? ?? true,
      minPaymentIncludeOverdue:
          json['min_payment_include_overdue'] as bool? ?? false,
      minPaymentFixedFloorMinor: (json['min_payment_fixed_floor_minor'] as num?)
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
      upcomingDueMinor: (json['upcoming_due_minor'] as num?)?.toInt() ?? 0,
      colorHex: json['color_hex'] as String?,
      fxMarkupBasisPoints: (json['fx_markup_basis_points'] as num?)?.toInt(),
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
  final int? installmentDueDay;
  final int gracePeriodDays;
  final MinPaymentPercentageBasis minPaymentPercentageBasis;
  final bool minPaymentIncludeInstallmentDues;
  final bool minPaymentIncludeBankFees;
  final bool minPaymentIncludeOverdue;
  final int? minPaymentFixedFloorMinor;
  final int statementRemainingMinor;
  final PlainDate? nextStatementDueOn;
  final int? statementDay;
  final String? lastFourDigits;
  final PlainDate? nextDueOn;
  final int? nextDueAmountMinor;

  /// Everything unpaid falling due between today and one month out —
  /// installments and statements together, not just the earliest one.
  final int upcomingDueMinor;

  /// The colour the user picked to match their physical card, `#RRGGBB`.
  /// Display only: no figure on this summary depends on it.
  final String? colorHex;

  /// Flat foreign-exchange markup rate in basis points (300 = 3%), applied
  /// by `charge_liability_account` when a charge is flagged foreign
  /// currency. Null means no flat markup is configured — independent of
  /// the fee-rules engine's own `foreign_transaction` trigger.
  final int? fxMarkupBasisPoints;
  final String? notes;

  /// [fxMarkupBasisPoints] as a display fraction, e.g. 300 -> 3.0.
  double? get fxMarkupPercent =>
      fxMarkupBasisPoints == null ? null : fxMarkupBasisPoints! / 100;

  Money get upcomingDue =>
      Money(minor: upcomingDueMinor, currencyCode: currencyCode);

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
    int remainingPrincipalMinor = -1,
    this.remainingScheduledPaymentsMinor = 0,
    this.remainingFutureInterestMinor = 0,
    this.accruedInterestRemainingMinor = 0,
    this.paidInstallments = 0,
    this.currentPostedInstallments = 0,
    this.futureInstallments = 0,
    this.totalUnpaidInstallments = 0,
    this.importAsOf,
    this.paidThroughOn,
    this.currentInstallmentPosted = false,
    this.bankReportedPrincipalMinor,
    this.reconciliationAsOf,
    this.reconciliationNotes,
    this.nextDueOn,
    this.nextDueAmountMinor,
    this.notes,
  }) : _remainingPrincipalMinor = remainingPrincipalMinor;

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
      remainingPrincipalMinor:
          (json['remaining_principal_minor'] as num?)?.toInt() ?? -1,
      remainingScheduledPaymentsMinor:
          (json['remaining_scheduled_payments_minor'] as num?)?.toInt() ?? 0,
      remainingFutureInterestMinor:
          (json['remaining_future_interest_minor'] as num?)?.toInt() ?? 0,
      accruedInterestRemainingMinor:
          (json['accrued_interest_remaining_minor'] as num?)?.toInt() ?? 0,
      paidInstallments: (json['paid_installments'] as num?)?.toInt() ?? 0,
      currentPostedInstallments:
          (json['current_posted_installments'] as num?)?.toInt() ?? 0,
      futureInstallments: (json['future_installments'] as num?)?.toInt() ?? 0,
      totalUnpaidInstallments:
          (json['total_unpaid_installments'] as num?)?.toInt() ?? 0,
      importAsOf: json['import_as_of'] == null
          ? null
          : PlainDate.parse(json['import_as_of'] as String),
      paidThroughOn: json['paid_through_on'] == null
          ? null
          : PlainDate.parse(json['paid_through_on'] as String),
      currentInstallmentPosted:
          json['current_installment_posted'] as bool? ?? false,
      bankReportedPrincipalMinor:
          (json['bank_reported_principal_minor'] as num?)?.toInt(),
      reconciliationAsOf: json['reconciliation_as_of'] == null
          ? null
          : PlainDate.parse(json['reconciliation_as_of'] as String),
      reconciliationNotes: json['reconciliation_notes'] as String?,
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
  final int _remainingPrincipalMinor;
  final int remainingScheduledPaymentsMinor;
  final int remainingFutureInterestMinor;
  final int accruedInterestRemainingMinor;
  final int paidInstallments;
  final int currentPostedInstallments;
  final int futureInstallments;
  final int totalUnpaidInstallments;
  final PlainDate? importAsOf;
  final PlainDate? paidThroughOn;
  final bool currentInstallmentPosted;
  final int? bankReportedPrincipalMinor;
  final PlainDate? reconciliationAsOf;
  final String? reconciliationNotes;
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

  /// Exact schedule-derived principal progress. For a reconciled historical
  /// plan this includes the explicit bank adjustment.
  int get remainingPrincipalMinor => _remainingPrincipalMinor >= 0
      ? _remainingPrincipalMinor
      : financedPrincipalMinor -
            (totalPayableMinor <= 0
                ? 0
                : (paidMinor * financedPrincipalMinor / totalPayableMinor)
                      .round());

  int get principalPaidMinor =>
      (financedPrincipalMinor - remainingPrincipalMinor).clamp(
        0,
        financedPrincipalMinor,
      );

  /// Interest and fees handed to the bank so far.
  int get bankCostPaidMinor =>
      (paidMinor - principalPaidMinor).clamp(0, paidMinor);

  /// Everything the bank charges on top of the item over the full plan.
  int get bankCostTotalMinor => totalPayableMinor - financedPrincipalMinor;

  Money get principalPaid =>
      Money(minor: principalPaidMinor, currencyCode: currencyCode);
  Money get financedPrincipal =>
      Money(minor: financedPrincipalMinor, currencyCode: currencyCode);
  Money get bankCostPaid =>
      Money(minor: bankCostPaidMinor, currencyCode: currencyCode);
  Money get bankCostTotal =>
      Money(minor: bankCostTotalMinor, currencyCode: currencyCode);
  Money get remainingPrincipal =>
      Money(minor: remainingPrincipalMinor, currencyCode: currencyCode);
  Money get remainingScheduledPayments =>
      Money(minor: remainingScheduledPaymentsMinor, currencyCode: currencyCode);
  Money get remainingFutureInterest =>
      Money(minor: remainingFutureInterestMinor, currencyCode: currencyCode);
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
    this.openingPrincipalMinor = 0,
    this.principalMinor = 0,
    this.interestMinor = 0,
    this.financingFeeMinor = 0,
    this.closingPrincipalMinor = 0,
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
      openingPrincipalMinor:
          (json['opening_principal_minor'] as num?)?.toInt() ?? 0,
      principalMinor: (json['principal_minor'] as num?)?.toInt() ?? 0,
      interestMinor: (json['interest_minor'] as num?)?.toInt() ?? 0,
      financingFeeMinor: (json['financing_fee_minor'] as num?)?.toInt() ?? 0,
      closingPrincipalMinor:
          (json['closing_principal_minor'] as num?)?.toInt() ?? 0,
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
  final int openingPrincipalMinor;
  final int principalMinor;
  final int interestMinor;
  final int financingFeeMinor;
  final int closingPrincipalMinor;

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
    this.colorHex,
    this.installmentDueDay,
    this.gracePeriodDays = 0,
    this.minPaymentPercentageBasis = MinPaymentPercentageBasis.statementTotal,
    this.minPaymentIncludeInstallmentDues = false,
    this.minPaymentIncludeBankFees = true,
    this.minPaymentIncludeOverdue = false,
    this.minPaymentFixedFloorMinor,
    this.fxMarkupBasisPoints,
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
  final String? colorHex;
  final int? installmentDueDay;
  final int gracePeriodDays;
  final MinPaymentPercentageBasis minPaymentPercentageBasis;
  final bool minPaymentIncludeInstallmentDues;
  final bool minPaymentIncludeBankFees;
  final bool minPaymentIncludeOverdue;
  final int? minPaymentFixedFloorMinor;

  /// Flat foreign-exchange markup rate in basis points; null disables it.
  /// Meaningful only on a credit card, but harmless to send for BNPL.
  final int? fxMarkupBasisPoints;

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
    'p_color_hex': colorHex,
    'p_installment_due_day': installmentDueDay,
    'p_grace_period_days': gracePeriodDays,
    'p_min_payment_percentage_basis': minPaymentPercentageBasis.dbValue,
    'p_min_payment_include_installment_dues': minPaymentIncludeInstallmentDues,
    'p_min_payment_include_bank_fees': minPaymentIncludeBankFees,
    'p_min_payment_include_overdue': minPaymentIncludeOverdue,
    'p_min_payment_fixed_floor_minor': minPaymentFixedFloorMinor,
    'p_fx_markup_basis_points': fxMarkupBasisPoints,
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
    this.importAsOf,
    this.paidThroughOn,
    this.currentInstallmentPosted = false,
    this.allowFuturePresettlement = false,
    this.bankReportedPrincipalMinor,
    this.reconciliationAsOf,
    this.reconciliationNotes,
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
  final PlainDate? importAsOf;
  final PlainDate? paidThroughOn;
  final bool currentInstallmentPosted;
  final bool allowFuturePresettlement;
  final int? bankReportedPrincipalMinor;
  final PlainDate? reconciliationAsOf;
  final String? reconciliationNotes;

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
    'p_import_as_of': importAsOf?.toIso(),
    'p_paid_through_on': paidThroughOn?.toIso(),
    'p_current_installment_posted': currentInstallmentPosted,
    'p_allow_future_presettlement': allowFuturePresettlement,
    'p_bank_reported_principal_minor': bankReportedPrincipalMinor,
    'p_reconciliation_as_of': reconciliationAsOf?.toIso(),
    'p_reconciliation_notes': reconciliationNotes,
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
    this.ordinaryStatementChargesMinor = 0,
    this.feeChargesMinor = 0,
    this.installmentDueMinor = 0,
    this.revolvingBaseMinor = 0,
    this.totalStatementDueMinor = 0,
    this.totalPaidMinor = 0,
    this.totalRemainingMinor = 0,
    this.obligationStatus = StatementCycleStatus.open,
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
      ordinaryStatementChargesMinor:
          (json['ordinary_statement_charges_minor'] as num?)?.toInt() ?? 0,
      feeChargesMinor: (json['fee_charges_minor'] as num?)?.toInt() ?? 0,
      installmentDueMinor:
          (json['installment_due_minor'] as num?)?.toInt() ?? 0,
      revolvingBaseMinor: (json['revolving_base_minor'] as num?)?.toInt() ?? 0,
      totalStatementDueMinor:
          (json['total_statement_due_minor'] as num?)?.toInt() ?? 0,
      totalPaidMinor: (json['total_paid_minor'] as num?)?.toInt() ?? 0,
      totalRemainingMinor:
          (json['total_remaining_minor'] as num?)?.toInt() ?? 0,
      obligationStatus: StatementCycleStatus.fromDb(
        json['obligation_status'] as String? ?? json['cycle_status'] as String,
      ),
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
  final int ordinaryStatementChargesMinor;
  final int feeChargesMinor;
  final int installmentDueMinor;
  final int revolvingBaseMinor;
  final int totalStatementDueMinor;
  final int totalPaidMinor;
  final int totalRemainingMinor;
  final StatementCycleStatus obligationStatus;

  Money get charges => Money(minor: chargesMinor, currencyCode: currencyCode);
  Money get remaining => Money(
    minor: totalRemainingMinor == 0 && totalStatementDueMinor == 0
        ? remainingMinor
        : totalRemainingMinor,
    currencyCode: currencyCode,
  );
  Money get installmentDue =>
      Money(minor: installmentDueMinor, currencyCode: currencyCode);
  Money get totalDue =>
      Money(minor: totalStatementDueMinor, currencyCode: currencyCode);
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
    case PlanPricingMethod.cardTenorDefault:
      // The resolved rate lives in the card's tenor table server-side;
      // there is nothing to preview locally until it is fetched.
      return null;
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

int previewReducingRemainingPrincipal({
  required int principalMinor,
  required int totalInterestMinor,
  required int installmentCount,
  required int paidInstallments,
  required int rateBasisPoints,
  required InterestRatePeriod ratePeriod,
}) {
  var balance = principalMinor;
  final total = principalMinor + totalInterestMinor;
  var rate = rateBasisPoints / 10000;
  if (ratePeriod == InterestRatePeriod.annual) rate /= 12;
  for (
    var sequence = 1;
    sequence <= paidInstallments.clamp(0, installmentCount);
    sequence++
  ) {
    final payment =
        total ~/ installmentCount +
        (sequence <= total % installmentCount ? 1 : 0);
    final interest = (balance * rate).round();
    balance = (balance - (payment - interest)).clamp(0, principalMinor);
  }
  return balance;
}
