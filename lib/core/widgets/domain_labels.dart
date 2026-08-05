import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Localized labels for database enums shared across features.
String accountTypeLabel(AppLocalizations l10n, AccountType type) {
  return switch (type) {
    AccountType.current => l10n.accTypeCurrent,
    AccountType.savings => l10n.accTypeSavings,
    AccountType.cash => l10n.accTypeCash,
    AccountType.bank => l10n.accTypeBank,
    AccountType.wallet => l10n.accTypeWallet,
    AccountType.emergency => l10n.accTypeEmergency,
    AccountType.vacation => l10n.accTypeVacation,
    AccountType.custom => l10n.accTypeCustom,
    AccountType.creditCard => l10n.accTypeCreditCard,
    AccountType.bnpl => l10n.accTypeBnpl,
  };
}

String installmentDueStatusLabel(
  AppLocalizations l10n,
  InstallmentDueStatus status,
) {
  return switch (status) {
    InstallmentDueStatus.upcoming => l10n.dueStatusUpcoming,
    InstallmentDueStatus.dueToday => l10n.dueStatusDueToday,
    InstallmentDueStatus.overdue => l10n.dueStatusOverdue,
    InstallmentDueStatus.partiallyPaid => l10n.dueStatusPartiallyPaid,
    InstallmentDueStatus.paid => l10n.dueStatusPaid,
    InstallmentDueStatus.cancelled => l10n.dueStatusCancelled,
  };
}

String installmentPlanStatusLabel(
  AppLocalizations l10n,
  InstallmentPlanStatus status,
) {
  return switch (status) {
    InstallmentPlanStatus.active => l10n.planStatusActive,
    InstallmentPlanStatus.completed => l10n.planStatusCompleted,
    InstallmentPlanStatus.cancelled => l10n.planStatusCancelled,
  };
}

String facilityStatusLabel(AppLocalizations l10n, FacilityStatus status) {
  return switch (status) {
    FacilityStatus.active => l10n.facilityStatusActive,
    FacilityStatus.frozen => l10n.facilityStatusFrozen,
    FacilityStatus.closed => l10n.facilityStatusClosed,
  };
}

String planPricingMethodLabel(AppLocalizations l10n, PlanPricingMethod m) {
  return switch (m) {
    PlanPricingMethod.manualFees => l10n.pricingMethodManualFees,
    PlanPricingMethod.monthlyAmount => l10n.pricingMethodMonthlyAmount,
    PlanPricingMethod.totalPayable => l10n.pricingMethodTotalPayable,
    PlanPricingMethod.interestRate => l10n.pricingMethodInterestRate,
  };
}

String recurringRuleKindLabel(AppLocalizations l10n, RecurringRuleKind kind) {
  return switch (kind) {
    RecurringRuleKind.expense => l10n.recurringKindExpense,
    RecurringRuleKind.transfer => l10n.recurringKindTransfer,
  };
}

String recurringFrequencyLabel(
  AppLocalizations l10n,
  RecurringFrequency frequency,
) {
  return switch (frequency) {
    RecurringFrequency.weekly => l10n.recurringFrequencyWeekly,
    RecurringFrequency.monthly => l10n.recurringFrequencyMonthly,
    RecurringFrequency.quarterly => l10n.recurringFrequencyQuarterly,
    RecurringFrequency.annually => l10n.recurringFrequencyAnnually,
  };
}

/// One-line schedule summary such as "Monthly · day 5".
String recurringScheduleLabel(
  AppLocalizations l10n,
  RecurringFrequency frequency,
  int paymentDay,
) {
  final base = recurringFrequencyLabel(l10n, frequency);
  if (frequency == RecurringFrequency.weekly) return base;
  return l10n.recurringScheduleOnDay(base, paymentDay);
}

String minPaymentMethodLabel(AppLocalizations l10n, MinPaymentMethod method) {
  return switch (method) {
    MinPaymentMethod.full => l10n.minPaymentFull,
    MinPaymentMethod.fixed => l10n.minPaymentFixed,
    MinPaymentMethod.percent => l10n.minPaymentPercent,
    MinPaymentMethod.greaterOf => l10n.minPaymentGreaterOf,
  };
}

String cardFeeTypeLabel(AppLocalizations l10n, CardFeeType type) {
  return switch (type) {
    CardFeeType.annualMembership => l10n.feeTypeAnnualMembership,
    CardFeeType.insurance => l10n.feeTypeInsurance,
    CardFeeType.administration => l10n.feeTypeAdministration,
    CardFeeType.stampTax => l10n.feeTypeStampTax,
    CardFeeType.foreignTransaction => l10n.feeTypeForeignTransaction,
    CardFeeType.cashAdvance => l10n.feeTypeCashAdvance,
    CardFeeType.latePayment => l10n.feeTypeLatePayment,
    CardFeeType.overLimit => l10n.feeTypeOverLimit,
    CardFeeType.installmentConversion => l10n.feeTypeInstallmentConversion,
    CardFeeType.other => l10n.feeTypeOther,
  };
}

String feeFrequencyLabel(AppLocalizations l10n, FeeFrequency frequency) {
  return switch (frequency) {
    FeeFrequency.once => l10n.feeFrequencyOnce,
    FeeFrequency.monthly => l10n.feeFrequencyMonthly,
    FeeFrequency.quarterly => l10n.feeFrequencyQuarterly,
    FeeFrequency.annually => l10n.feeFrequencyAnnually,
  };
}

String feePercentBasisLabel(AppLocalizations l10n, FeePercentBasis basis) {
  return switch (basis) {
    FeePercentBasis.statementBalance => l10n.feeBasisStatementBalance,
    FeePercentBasis.outstandingBalance => l10n.feeBasisOutstandingBalance,
    FeePercentBasis.creditLimit => l10n.feeBasisCreditLimit,
  };
}

String statementCycleStatusLabel(
  AppLocalizations l10n,
  StatementCycleStatus status,
) {
  return switch (status) {
    StatementCycleStatus.open => l10n.statementStatusOpen,
    StatementCycleStatus.upcoming => l10n.dueStatusUpcoming,
    StatementCycleStatus.dueToday => l10n.dueStatusDueToday,
    StatementCycleStatus.overdue => l10n.dueStatusOverdue,
    StatementCycleStatus.partiallyPaid => l10n.dueStatusPartiallyPaid,
    StatementCycleStatus.paid => l10n.dueStatusPaid,
  };
}

String transactionKindLabel(AppLocalizations l10n, TransactionKind kind) {
  return switch (kind) {
    TransactionKind.expense => l10n.txExpense,
    TransactionKind.allowanceGiven => l10n.txAllowance,
    TransactionKind.customIncome => l10n.txCustomIncome,
    TransactionKind.freelanceIncome => l10n.txFreelanceIncome,
    TransactionKind.salaryIncome => l10n.txSalaryIncome,
    TransactionKind.transfer => l10n.txTransfer,
  };
}

String categoryKindLabel(AppLocalizations l10n, CategoryKind kind) {
  return switch (kind) {
    CategoryKind.expense => l10n.catKindExpense,
    CategoryKind.allowance => l10n.catKindAllowance,
    CategoryKind.income => l10n.catKindIncome,
  };
}

String workEntryTypeLabel(AppLocalizations l10n, WorkEntryType type) {
  return switch (type) {
    WorkEntryType.regular => l10n.workEntryRegular,
    WorkEntryType.overtime => l10n.workEntryOvertime,
    WorkEntryType.extraDay => l10n.workEntryExtraDay,
    WorkEntryType.holidayWorked => l10n.workEntryHoliday,
  };
}
