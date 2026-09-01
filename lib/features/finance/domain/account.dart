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
    this.hideFromHome = false,
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
    hideFromHome: json['hide_from_home'] as bool? ?? false,
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
  final bool hideFromHome;
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
    this.hideFromHome = false,
    this.pendingTransferHoldMinor = 0,
    this.heldOutgoingMinor = 0,
    this.heldIncomingMinor = 0,
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
    hideFromHome: json['hide_from_home'] as bool? ?? false,
    // Default to zero rather than requiring the keys: a client can outrun the
    // migration that adds these columns, and an account with no reservations
    // is the correct reading of their absence.
    pendingTransferHoldMinor:
        (json['pending_transfer_hold_minor'] as num?)?.toInt() ?? 0,
    heldOutgoingMinor: (json['held_outgoing_minor'] as num?)?.toInt() ?? 0,
    heldIncomingMinor: (json['held_incoming_minor'] as num?)?.toInt() ?? 0,
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
  final bool hideFromHome;

  /// Pending outgoing network transfers sourced from this account. Promised,
  /// not yet booked: acceptance by the other side is what moves the money.
  final int pendingTransferHoldMinor;

  /// Unsettled `i_owe` held amounts recorded against this account.
  final int heldOutgoingMinor;

  /// Unsettled `owed_to_me` held amounts recorded against this account. Money
  /// expected in, so it never raises what is available to spend.
  final int heldIncomingMinor;

  Money get balance => Money(minor: balanceMinor, currencyCode: currencyCode);
  Money get totalIncoming =>
      Money(minor: totalIncomingMinor, currencyCode: currencyCode);
  Money get totalOutgoing =>
      Money(minor: totalOutgoingMinor, currencyCode: currencyCode);

  /// Everything committed out of this account but not yet booked.
  int get reservedMinor => pendingTransferHoldMinor + heldOutgoingMinor;

  /// What is left to spend. Deliberately allowed to go negative: reserving is
  /// not spending, and the app never blocks a transfer request on it.
  int get availableBalanceMinor => balanceMinor - reservedMinor;

  Money get pendingTransferHold =>
      Money(minor: pendingTransferHoldMinor, currencyCode: currencyCode);
  Money get heldOutgoing =>
      Money(minor: heldOutgoingMinor, currencyCode: currencyCode);
  Money get heldIncoming =>
      Money(minor: heldIncomingMinor, currencyCode: currencyCode);
  Money get reserved => Money(minor: reservedMinor, currencyCode: currencyCode);
  Money get availableBalance =>
      Money(minor: availableBalanceMinor, currencyCode: currencyCode);

  bool get hasReservedFunds => reservedMinor > 0;
  bool get hasIncomingHolds => heldIncomingMinor > 0;

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
