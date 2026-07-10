import 'package:flutter/material.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

IconData transactionKindIcon(TransactionKind kind) {
  return switch (kind) {
    TransactionKind.expense => Icons.shopping_cart_outlined,
    TransactionKind.allowanceGiven => Icons.volunteer_activism_outlined,
    TransactionKind.customIncome => Icons.attach_money,
    TransactionKind.freelanceIncome => Icons.work_outline,
    TransactionKind.salaryIncome => Icons.payments_outlined,
    TransactionKind.transfer => Icons.swap_horiz,
  };
}

IconData accountTypeIcon(AccountType type) {
  return switch (type) {
    AccountType.current => Icons.account_balance_wallet_outlined,
    AccountType.savings => Icons.savings_outlined,
    AccountType.cash => Icons.money_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.wallet => Icons.wallet_outlined,
    AccountType.emergency => Icons.medical_services_outlined,
    AccountType.vacation => Icons.beach_access_outlined,
    AccountType.custom => Icons.category_outlined,
  };
}

/// List tile for a transaction. Amount is colored by direction:
/// income green-ish (primary), outgoing error, transfer neutral.
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

  String _accountLine() {
    final source = transaction.sourceAccountId == null
        ? null
        : accountNames[transaction.sourceAccountId];
    final destination = transaction.destinationAccountId == null
        ? null
        : accountNames[transaction.destinationAccountId];
    if (source != null && destination != null) {
      return '$source → $destination';
    }
    return source ?? destination ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tx = transaction;

    final Color amountColor;
    final String amountText;
    if (tx.isTransfer) {
      amountColor = scheme.onSurfaceVariant;
      amountText = tx.amount.format();
    } else if (tx.isIncome) {
      amountColor = scheme.primary;
      amountText = '+${tx.amount.format()}';
    } else {
      amountColor = scheme.error;
      amountText = '-${tx.amount.format()}';
    }

    final title = tx.title?.isNotEmpty == true
        ? tx.title!
        : transactionKindLabel(l10n, tx.kind);
    final subtitleParts = [
      tx.occurredOn.toIso(),
      _accountLine(),
      if (tx.kind == TransactionKind.allowanceGiven &&
          (tx.counterparty?.isNotEmpty ?? false))
        tx.counterparty!,
    ].where((p) => p.isNotEmpty);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(transactionKindIcon(tx.kind), color: scheme.onSurface),
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
          Text(
            amountText,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: amountColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
    return Text(
      money.format(),
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: money.isNegative ? scheme.error : null,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
