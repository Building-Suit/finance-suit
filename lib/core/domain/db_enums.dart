/// Dart mirrors of the PostgreSQL enums. `dbValue` matches the wire format
/// exactly; parsing is strict so schema drift fails fast in development.
library;

enum WorkEntryType {
  regular('regular'),
  overtime('overtime'),
  extraDay('extra_day'),
  holidayWorked('holiday_worked');

  const WorkEntryType(this.dbValue);
  final String dbValue;

  static WorkEntryType fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum RateMode {
  derived('derived'),
  manual('manual');

  const RateMode(this.dbValue);
  final String dbValue;

  static RateMode fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum HolidayMultiplierSemantics {
  additionalPay('additional_pay'),
  totalIncludingBase('total_including_base');

  const HolidayMultiplierSemantics(this.dbValue);
  final String dbValue;

  static HolidayMultiplierSemantics fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum RoundingMode {
  halfUp('half_up'),
  halfEven('half_even');

  const RoundingMode(this.dbValue);
  final String dbValue;

  static RoundingMode fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum SalaryPeriodStatus {
  open('open'),
  finalized('finalized'),
  paid('paid');

  const SalaryPeriodStatus(this.dbValue);
  final String dbValue;

  static SalaryPeriodStatus fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum AdjustmentType {
  bonus('bonus'),
  deduction('deduction');

  const AdjustmentType(this.dbValue);
  final String dbValue;

  static AdjustmentType fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum AccountType {
  current('current'),
  savings('savings'),
  cash('cash'),
  bank('bank'),
  wallet('wallet'),
  emergency('emergency'),
  vacation('vacation'),
  custom('custom'),
  creditCard('credit_card'),
  bnpl('bnpl');

  const AccountType(this.dbValue);
  final String dbValue;

  static AccountType fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);

  /// Dart mirror of `app_finance.account_role`: credit cards and BNPL
  /// facilities are liabilities, everything else is an asset.
  AccountRole get role => switch (this) {
    AccountType.creditCard || AccountType.bnpl => AccountRole.liability,
    _ => AccountRole.asset,
  };

  bool get isLiability => role == AccountRole.liability;
}

/// Whether an account holds the user's money (asset) or money the user
/// owes (liability). Mirrors `app_finance.account_role` in SQL.
enum AccountRole { asset, liability }

enum InstallmentPlanStatus {
  active('active'),
  completed('completed'),
  cancelled('cancelled');

  const InstallmentPlanStatus(this.dbValue);
  final String dbValue;

  static InstallmentPlanStatus fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum InstallmentDueStatus {
  upcoming('upcoming'),
  dueToday('due_today'),
  overdue('overdue'),
  partiallyPaid('partially_paid'),
  paid('paid'),
  cancelled('cancelled');

  const InstallmentDueStatus(this.dbValue);
  final String dbValue;

  static InstallmentDueStatus fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum CategoryKind {
  expense('expense'),
  allowance('allowance'),
  income('income');

  const CategoryKind(this.dbValue);
  final String dbValue;

  static CategoryKind fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum TransactionKind {
  expense('expense'),
  allowanceGiven('allowance_given'),
  customIncome('custom_income'),
  freelanceIncome('freelance_income'),
  salaryIncome('salary_income'),
  transfer('transfer');

  const TransactionKind(this.dbValue);
  final String dbValue;

  static TransactionKind fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum HeldAmountDirection {
  iOwe('i_owe'),
  owedToMe('owed_to_me');

  const HeldAmountDirection(this.dbValue);
  final String dbValue;

  static HeldAmountDirection fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum IncomeSourceKind {
  salary('salary'),
  allowance('allowance'),
  freelance('freelance'),
  other('other');

  const IncomeSourceKind(this.dbValue);
  final String dbValue;

  static IncomeSourceKind fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum IncomeAllocationMethod {
  percentage('percentage'),
  fixed('fixed');

  const IncomeAllocationMethod(this.dbValue);
  final String dbValue;

  static IncomeAllocationMethod fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum IncomeAllocationCalculationBasis {
  original('original'),
  remaining('remaining');

  const IncomeAllocationCalculationBasis(this.dbValue);
  final String dbValue;

  static IncomeAllocationCalculationBasis fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}

enum IncomeOccurrenceStatus {
  pending('pending'),
  accepted('accepted'),
  skipped('skipped');

  const IncomeOccurrenceStatus(this.dbValue);
  final String dbValue;

  static IncomeOccurrenceStatus fromDb(String value) =>
      values.firstWhere((e) => e.dbValue == value);
}
