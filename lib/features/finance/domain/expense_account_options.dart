import 'package:meta/meta.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';

/// Why an offered account cannot take a charge yet. The option stays in the
/// list — hiding it reads as "this account cannot take expenses at all" —
/// and the form explains what is missing instead.
enum ExpenseAccountBlock { cardNotConfigured }

/// Presentation grouping of the expense Account picker.
enum ExpenseAccountGroup { cash, credit }

/// One entry of the canonical expense Account picker.
@immutable
class ExpenseAccountOption {
  const ExpenseAccountOption({
    required this.accountId,
    required this.name,
    required this.accountType,
    required this.currencyCode,
    this.isCurrent = false,
    this.block,
  });

  final String accountId;
  final String name;
  final AccountType accountType;
  final String currencyCode;

  /// The account the edited transaction already sits on. It is offered even
  /// when it could no longer fund a new expense, so historical records on an
  /// archived, frozen, or closed account stay correctable.
  final bool isCurrent;

  final ExpenseAccountBlock? block;

  bool get isLiability => accountType.isLiability;

  ExpenseAccountGroup get group =>
      isLiability ? ExpenseAccountGroup.credit : ExpenseAccountGroup.cash;
}

/// The single source of truth for which accounts may fund an expense, shared
/// by Add Expense, Edit Expense, and every other expense entry point.
///
/// The rule is role- and capability-based, never a hardcoded account-type
/// exception, so credit cards and BNPL facilities are always treated alike:
///
/// - Asset accounts: active (not archived) and matching [currencyCode].
/// - Liability accounts ([AccountRole.liability], so credit card *and*
///   BNPL): a configured facility that is not archived, whose status is
///   active, and whose currency matches. A credit card without a statement
///   closing day is still listed and carries
///   [ExpenseAccountBlock.cardNotConfigured].
/// - [currentAccountId]: always listed and marked [ExpenseAccountOption
///   .isCurrent], even when archived, frozen, or closed, so an existing
///   transaction keeps showing the account it belongs to. Such an account is
///   never offered to *other* transactions.
///
/// Income, transfers, salary, held money, down payments, and facility
/// repayments keep their own asset-only rules and must not use this list.
List<ExpenseAccountOption> expenseSourceAccounts({
  required Iterable<AccountBalance> accounts,
  required Iterable<CreditFacilitySummary> facilities,
  String? currencyCode,
  String? currentAccountId,
}) {
  bool currencyMatches(String code) =>
      currencyCode == null || code == currencyCode;

  final options = <ExpenseAccountOption>[];

  for (final account in accounts) {
    if (account.isLiability) continue;
    final isCurrent = account.accountId == currentAccountId;
    if (!isCurrent &&
        (account.isArchived || !currencyMatches(account.currencyCode))) {
      continue;
    }
    options.add(
      ExpenseAccountOption(
        accountId: account.accountId,
        name: account.name,
        accountType: account.accountType,
        currencyCode: account.currencyCode,
        isCurrent: isCurrent,
      ),
    );
  }

  for (final facility in facilities) {
    final isCurrent = facility.accountId == currentAccountId;
    if (!isCurrent &&
        (!facility.canFundPurchases ||
            !currencyMatches(facility.currencyCode))) {
      continue;
    }
    options.add(
      ExpenseAccountOption(
        accountId: facility.accountId,
        name: facility.name,
        accountType: facility.accountType,
        currencyCode: facility.currencyCode,
        isCurrent: isCurrent,
        block:
            facility.accountType == AccountType.creditCard &&
                facility.statementDay == null
            ? ExpenseAccountBlock.cardNotConfigured
            : null,
      ),
    );
  }

  // Assets first, then credit, each alphabetically: the picker mirrors the
  // Money tab's "Cash & bank" / "Credit & installments" order.
  options.sort((left, right) {
    final group = left.group.index - right.group.index;
    if (group != 0) return group;
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return options;
}
