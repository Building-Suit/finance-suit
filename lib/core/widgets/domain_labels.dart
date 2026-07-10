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
