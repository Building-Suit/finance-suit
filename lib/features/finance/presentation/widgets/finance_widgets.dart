import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

FinanceSuitGlyph transactionKindIcon(TransactionKind kind) {
  return switch (kind) {
    TransactionKind.expense => FinanceSuitIcons.shoppingCart,
    TransactionKind.allowanceGiven => FinanceSuitIcons.volunteerActivism,
    TransactionKind.customIncome => FinanceSuitIcons.attachMoney,
    TransactionKind.freelanceIncome => FinanceSuitIcons.work,
    TransactionKind.salaryIncome => FinanceSuitIcons.payments,
    TransactionKind.transfer => FinanceSuitIcons.swapHoriz,
  };
}

FinanceSuitGlyph accountTypeIcon(AccountType type) {
  return switch (type) {
    AccountType.current => FinanceSuitIcons.accountBalanceWallet,
    AccountType.savings => FinanceSuitIcons.savings,
    AccountType.cash => FinanceSuitIcons.money,
    AccountType.bank => FinanceSuitIcons.accountBalance,
    AccountType.wallet => FinanceSuitIcons.wallet,
    AccountType.emergency => FinanceSuitIcons.medicalServices,
    AccountType.vacation => FinanceSuitIcons.beachAccess,
    AccountType.custom => FinanceSuitIcons.category,
  };
}

/// List tile for a transaction. Amount is colored by direction:
/// income success, outgoing error, transfer neutral.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.accountNames,
    this.onTap,
    this.trailingMenu,
  });

  final FinancialTransaction transaction;
  final Map<String, String> accountNames;
  final VoidCallback? onTap;
  final Widget? trailingMenu;

  String _accountLine(BuildContext context) {
    final source = transaction.sourceAccountId == null
        ? null
        : accountNames[transaction.sourceAccountId];
    final destination = transaction.destinationAccountId == null
        ? null
        : accountNames[transaction.destinationAccountId];
    if (source != null && destination != null) {
      final arrow = Directionality.of(context) == TextDirection.rtl ? '←' : '→';
      return '$source $arrow $destination';
    }
    return source ?? destination ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tx = transaction;

    final Color amountColor;
    final AppMoneySign amountSign;
    if (tx.isTransfer) {
      amountColor = scheme.onSurfaceVariant;
      amountSign = AppMoneySign.never;
    } else if (tx.isIncome) {
      amountColor = AppTheme.incomeColor(context);
      amountSign = AppMoneySign.explicit;
    } else {
      amountColor = scheme.error;
      amountSign = AppMoneySign.explicit;
    }

    final title = tx.title?.isNotEmpty == true
        ? tx.title!
        : transactionKindLabel(l10n, tx.kind);
    final subtitleParts = [
      tx.occurredOn.toIso(),
      _accountLine(context),
      if (tx.kind == TransactionKind.allowanceGiven &&
          (tx.counterparty?.isNotEmpty ?? false))
        tx.counterparty!,
    ].where((p) => p.isNotEmpty);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: FinanceSuitIcon(
          transactionKindIcon(tx.kind),
          color: scheme.onSurface,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppMoneyText(
            money: tx.isIncome || tx.isTransfer ? tx.amount : -tx.amount,
            sign: amountSign,
            color: amountColor,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ?trailingMenu,
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Money amount text with direction-aware coloring for balances.
class BalanceText extends StatelessWidget {
  const BalanceText({super.key, required this.money, this.style});

  final Money money;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppMoneyText(
      money: money,
      color: money.isNegative ? scheme.error : null,
      style: style ?? Theme.of(context).textTheme.titleMedium,
    );
  }
}
