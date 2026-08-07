import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
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
    AccountType.creditCard => FinanceSuitIcons.creditCard,
    AccountType.bnpl => FinanceSuitIcons.requestQuote,
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

/// Compact card for one credit card or BNPL facility. Debt is shown as a
/// positive "amount owed" — never as spendable cash — with available
/// credit, the limit, a utilization bar, and the next due when present.
class FacilityTile extends StatelessWidget {
  const FacilityTile({super.key, required this.facility, this.onTap});

  final CreditFacilitySummary facility;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.suitColors;
    final tone = facility.hasOverdue
        ? colors.error
        : facility.utilizationFraction >= 0.9
        ? colors.warning
        : colors.info;
    // The row keeps the neutral surface so its figures stay readable; the
    // user's colour identifies the card through the leading swatch.
    final swatch = FacilitySwatches.parse(facility.colorHex);
    return Card(
      key: Key('facility-tile-${facility.accountId}'),
      margin: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (swatch == null)
                    FinanceSuitIcon(
                      accountTypeIcon(facility.accountType),
                      color: tone.icon,
                    )
                  else
                    Container(
                      key: Key('facility-swatch-${facility.accountId}'),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: swatch,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FinanceSuitIcon(
                        accountTypeIcon(facility.accountType),
                        color: onFacilitySwatch(swatch),
                        size: 18,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          facility.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          facility.isArchived
                              ? '${accountTypeLabel(l10n, facility.accountType)}'
                                    ' · ${l10n.moneyArchivedLabel}'
                              : accountTypeLabel(l10n, facility.accountType),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(l10n.facilityOwed, style: theme.textTheme.bodySmall),
                      AppMoneyText(
                        money: facility.outstanding,
                        style: theme.textTheme.titleSmall,
                        sign: AppMoneySign.never,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: facility.utilizationFraction,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: tone.icon,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  ProtectedMoneyText(
                    '${l10n.facilityAvailable}: '
                    '${facility.availableCredit.format()}',
                    style: theme.textTheme.bodySmall,
                    interactive: false,
                  ),
                  ProtectedMoneyText(
                    '${l10n.facilityCreditLimit}: '
                    '${facility.creditLimit.format()}',
                    style: theme.textTheme.bodySmall,
                    interactive: false,
                  ),
                  if (facility.nextDueOn != null)
                    Text(
                      l10n.facilityNextDue(facility.nextDueOn!.toIso()),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (facility.hasOverdue)
                    Text(
                      l10n.facilityOverdueBadge,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
