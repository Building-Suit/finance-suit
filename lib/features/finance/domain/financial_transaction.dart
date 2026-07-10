import 'package:meta/meta.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `app_finance.financial_transactions`.
@immutable
class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.kind,
    required this.occurredOn,
    required this.amountMinor,
    required this.currencyCode,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
    this.counterparty,
    this.title,
    this.notes,
    this.salaryPeriodId,
  });

  factory FinancialTransaction.fromJson(Map<String, dynamic> json) =>
      FinancialTransaction(
        id: json['id'] as String,
        kind: TransactionKind.fromDb(json['transaction_kind'] as String),
        occurredOn: PlainDate.parse(json['occurred_on'] as String),
        amountMinor: (json['amount_minor'] as num).toInt(),
        currencyCode: json['currency_code'] as String,
        sourceAccountId: json['source_account_id'] as String?,
        destinationAccountId: json['destination_account_id'] as String?,
        categoryId: json['category_id'] as String?,
        counterparty: json['counterparty'] as String?,
        title: json['title'] as String?,
        notes: json['notes'] as String?,
        salaryPeriodId: json['salary_period_id'] as String?,
      );

  final String id;
  final TransactionKind kind;
  final PlainDate occurredOn;
  final int amountMinor;
  final String currencyCode;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? counterparty;
  final String? title;
  final String? notes;
  final String? salaryPeriodId;

  Money get amount => Money(minor: amountMinor, currencyCode: currencyCode);

  bool get isIncome =>
      kind == TransactionKind.customIncome ||
      kind == TransactionKind.freelanceIncome ||
      kind == TransactionKind.salaryIncome;

  bool get isTransfer => kind == TransactionKind.transfer;

  /// Salary payments are created only through the payment RPC and stay
  /// immutable from the transaction editor.
  bool get isSalaryPayment => kind == TransactionKind.salaryIncome;

  /// Signed amount from the whole-user cash-flow perspective:
  /// income positive, expense/allowance negative, transfer neutral.
  Money get signedAmount {
    if (isIncome) return amount;
    if (isTransfer) return Money.zero(currencyCode);
    return -amount;
  }
}

/// Payload for inserting or updating a non-transfer transaction.
/// Transfers go through the `create_transfer` RPC instead.
@immutable
class TransactionDraft {
  const TransactionDraft({
    required this.kind,
    required this.occurredOn,
    required this.amountMinor,
    required this.currencyCode,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
    this.counterparty,
    this.title,
    this.notes,
  });

  final TransactionKind kind;
  final PlainDate occurredOn;
  final int amountMinor;
  final String currencyCode;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? counterparty;
  final String? title;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'transaction_kind': kind.dbValue,
    'occurred_on': occurredOn.toIso(),
    'amount_minor': amountMinor,
    'currency_code': currencyCode,
    'source_account_id': sourceAccountId,
    'destination_account_id': destinationAccountId,
    'category_id': categoryId,
    'counterparty': counterparty,
    'title': title,
    'notes': notes,
  };
}
