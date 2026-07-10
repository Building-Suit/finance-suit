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
  custom('custom');

  const AccountType(this.dbValue);
  final String dbValue;

  static AccountType fromDb(String value) =>
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
