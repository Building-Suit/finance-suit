import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class HistoryItemTile extends StatelessWidget {
  const HistoryItemTile({
    super.key,
    required this.item,
    this.accountNames = const {},
    this.onTap,
  });

  final HistoryItem item;
  final Map<String, String> accountNames;
  final VoidCallback? onTap;

  FinanceSuitGlyph get _icon {
    final transactionKind = item.transactionKind;
    if (transactionKind != null) return transactionKindIcon(transactionKind);
    final workType = item.workEntryType;
    if (workType != null) {
      return switch (workType) {
        WorkEntryType.regular => FinanceSuitIcons.work,
        WorkEntryType.overtime => FinanceSuitIcons.moreTime,
        WorkEntryType.extraDay => FinanceSuitIcons.eventAvailable,
        WorkEntryType.holidayWorked => FinanceSuitIcons.celebration,
      };
    }
    return FinanceSuitIcons.tune;
  }

  String _title(AppLocalizations l10n) {
    final transactionKind = item.transactionKind;
    if (transactionKind != null) {
      return item.title?.isNotEmpty == true
          ? item.title!
          : transactionKindLabel(l10n, transactionKind);
    }
    final workType = item.workEntryType;
    if (workType != null) return workEntryTypeLabel(l10n, workType);
    return item.recordType == 'deduction'
        ? l10n.salAdjDeduction
        : l10n.salAdjBonus;
  }

  String _subtitle(BuildContext context, AppLocalizations l10n) {
    final parts = <String>[item.recordDate.toIso()];
    final source = item.sourceAccountId == null
        ? null
        : accountNames[item.sourceAccountId];
    final destination = item.destinationAccountId == null
        ? null
        : accountNames[item.destinationAccountId];
    if (source != null && destination != null) {
      final arrow = Directionality.of(context) == TextDirection.rtl ? '←' : '→';
      parts.add('$source $arrow $destination');
    } else if (source != null) {
      parts.add(source);
    } else if (destination != null) {
      parts.add(destination);
    }
    final counterparty = item.counterparty;
    if (counterparty != null && counterparty.isNotEmpty) {
      parts.add(counterparty);
    }
    if (item.group == HistoryItemGroup.salaryAdjustment) {
      parts.add(l10n.historyFilterSalaryAdjustment);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final amount = item.amount;
    final isNeutral = item.recordType == TransactionKind.transfer.dbValue;
    final Color amountColor = amount == null || isNeutral
        ? scheme.onSurfaceVariant
        : item.isOutgoing
        ? scheme.error
        : AppTheme.incomeColor(context);
    final String? amountText = amount == null
        ? null
        : isNeutral
        ? amount.format()
        : item.isOutgoing
        ? Money(
            minor: -amount.minor.abs(),
            currencyCode: amount.currencyCode,
          ).formatSigned()
        : amount.formatSigned();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: FinanceSuitIcon(_icon, color: scheme.onSurface),
      ),
      title: Text(_title(l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _subtitle(context, l10n),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: amountText == null
          ? null
          : ProtectedMoneyText(
              amountText,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: amountColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
      onTap: onTap,
    );
  }
}
