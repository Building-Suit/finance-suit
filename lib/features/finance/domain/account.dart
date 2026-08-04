import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A user account row from `app_finance.accounts`.
@immutable
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.openingBalanceMinor,
    required this.isDefault,
    required this.allowNegativeBalance,
    required this.isArchived,
    this.notes,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    accountType: AccountType.fromDb(json['account_type'] as String),
    currencyCode: json['currency_code'] as String,
    openingBalanceMinor: (json['opening_balance_minor'] as num).toInt(),
    isDefault: json['is_default'] as bool,
    allowNegativeBalance: json['allow_negative_balance'] as bool,
    isArchived: json['is_archived'] as bool,
    notes: json['notes'] as String?,
  );

  final String id;
  final String name;
  final AccountType accountType;
  final String currencyCode;
  final int openingBalanceMinor;
  final bool isDefault;
  final bool allowNegativeBalance;
  final bool isArchived;
  final String? notes;

  Money get openingBalance =>
      Money(minor: openingBalanceMinor, currencyCode: currencyCode);
}

/// A row from the `app_finance.account_balances` view: account metadata plus the
/// derived running balance and flow totals.
@immutable
class AccountBalance {
  const AccountBalance({
    required this.accountId,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    required this.isDefault,
    required this.isArchived,
    required this.allowNegativeBalance,
    required this.openingBalanceMinor,
    required this.balanceMinor,
    required this.totalIncomingMinor,
    required this.totalOutgoingMinor,
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) => AccountBalance(
    accountId: json['account_id'] as String,
    name: json['name'] as String,
    accountType: AccountType.fromDb(json['account_type'] as String),
    currencyCode: json['currency_code'] as String,
    isDefault: json['is_default'] as bool,
    isArchived: json['is_archived'] as bool,
    allowNegativeBalance: json['allow_negative_balance'] as bool,
    openingBalanceMinor: (json['opening_balance_minor'] as num).toInt(),
    balanceMinor: (json['balance_minor'] as num).toInt(),
    totalIncomingMinor: (json['total_incoming_minor'] as num).toInt(),
    totalOutgoingMinor: (json['total_outgoing_minor'] as num).toInt(),
  );

  final String accountId;
  final String name;
  final AccountType accountType;
  final String currencyCode;
  final bool isDefault;
  final bool isArchived;
  final bool allowNegativeBalance;
  final int openingBalanceMinor;
  final int balanceMinor;
  final int totalIncomingMinor;
  final int totalOutgoingMinor;

  Money get balance => Money(minor: balanceMinor, currencyCode: currencyCode);
  Money get totalIncoming =>
      Money(minor: totalIncomingMinor, currencyCode: currencyCode);
  Money get totalOutgoing =>
      Money(minor: totalOutgoingMinor, currencyCode: currencyCode);

  /// Credit cards and BNPL facilities owe money instead of holding it.
  bool get isLiability => accountType.isLiability;
}

/// Central picker eligibility: every flow that moves the user's own cash
/// (income destinations, expense/allowance sources, transfers, down
/// payments, facility repayments, defaults) selects from asset accounts
/// only. Liability accounts participate exclusively through the dedicated
/// facility flows, and the database enforces the same rule.
extension AccountBalanceEligibility on Iterable<AccountBalance> {
  List<AccountBalance> get assetAccounts =>
      where((account) => !account.isLiability).toList();
}
