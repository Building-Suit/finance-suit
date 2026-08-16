import 'package:flutter/material.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// The display groups of the Due Breakdown and the Pay checklist.
enum DueComponentGroup { installments, feesInterest, purchases, nextDue }

DueComponentGroup dueComponentGroup(FacilityPaymentComponent c) {
  if (c.scope == FacilityComponentScope.nextDue) {
    return DueComponentGroup.nextDue;
  }
  if (c.type == FacilityComponentType.installmentDue) {
    return DueComponentGroup.installments;
  }
  if (c.isFeeOrInterest) return DueComponentGroup.feesInterest;
  return DueComponentGroup.purchases;
}

String dueComponentGroupLabel(AppLocalizations l10n, DueComponentGroup group) {
  return switch (group) {
    DueComponentGroup.installments => l10n.paymentGroupInstallments,
    DueComponentGroup.feesInterest => l10n.paymentGroupFeesInterest,
    DueComponentGroup.purchases => l10n.paymentGroupPurchases,
    DueComponentGroup.nextDue => l10n.paymentGroupNextDue,
  };
}

/// Groups components for display, keeping the server's stable order inside
/// each group.
Map<DueComponentGroup, List<FacilityPaymentComponent>> groupDueComponents(
  List<FacilityPaymentComponent> components,
) {
  final groups = <DueComponentGroup, List<FacilityPaymentComponent>>{};
  for (final c in components) {
    groups.putIfAbsent(dueComponentGroup(c), () => []).add(c);
  }
  return groups;
}

/// Human title of a component: merchant/plan title when available, else the
/// canonical fee label — never a raw enum value.
String dueComponentTitle(AppLocalizations l10n, FacilityPaymentComponent c) {
  final title = c.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  if (c.feeType != null) {
    try {
      return cardFeeTypeLabel(l10n, CardFeeType.fromDb(c.feeType!));
    } on StateError {
      // Unknown fee type from a newer server: fall through to kind labels.
    }
  }
  return switch (c.activityKind) {
    'purchase_interest' => l10n.facilityActivityPurchaseInterest,
    'installment_interest' => l10n.facilityActivityInstallmentInterest,
    'fee_charge' => l10n.paymentGroupFeesInterest,
    _ => l10n.txExpense,
  };
}

String? dueComponentSubtitle(
  AppLocalizations l10n,
  FacilityPaymentComponent c,
) {
  if (c.type == FacilityComponentType.installmentDue) {
    final on = c.occurredOn?.toIso() ?? '';
    if (c.sequenceNumber != null && c.installmentCount != null) {
      return l10n.paymentInstallmentSubtitle(
        c.sequenceNumber!,
        c.installmentCount!,
        on,
      );
    }
    return on;
  }
  return c.occurredOn?.toIso();
}

/// The three authoritative totals of the persistent Due Breakdown.
class DueBreakdownTotals extends StatelessWidget {
  const DueBreakdownTotals({
    super.key,
    required this.totalDueMinor,
    required this.paidMinor,
    required this.remainingMinor,
    required this.currencyCode,
  });

  DueBreakdownTotals.fromBreakdown(FacilityDueBreakdown breakdown, {Key? key})
    : this(
        key: key,
        totalDueMinor: breakdown.totalDueMinor,
        paidMinor: breakdown.paidMinor,
        remainingMinor: breakdown.remainingMinor,
        currencyCode: breakdown.currencyCode,
      );

  final int totalDueMinor;
  final int paidMinor;
  final int remainingMinor;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget row(String label, int minor, {bool emphasize = false}) {
      final style = emphasize
          ? theme.textTheme.titleSmall
          : theme.textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ProtectedMoneyText(
              Money(minor: minor, currencyCode: currencyCode).format(),
              style: style,
              interactive: false,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(l10n.dueBreakdownTotalDue, totalDueMinor),
        row(l10n.dueBreakdownPaid, paidMinor),
        row(l10n.dueBreakdownLeftToPay, remainingMinor, emphasize: true),
      ],
    );
  }
}

/// One static Due Breakdown row. Paid rows stay visible: checked, muted and
/// struck through. Partial rows show paid/total and remaining and are never
/// struck through.
class DueBreakdownRow extends StatelessWidget {
  const DueBreakdownRow({
    super.key,
    required this.component,
    required this.currencyCode,
  });

  final FacilityPaymentComponent component;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    String money(int minor) =>
        Money(minor: minor, currencyCode: currencyCode).format();

    final paid = component.status == ComponentPaymentStatus.paid;
    final partial = component.status == ComponentPaymentStatus.partiallyPaid;
    final titleStyle = paid
        ? theme.textTheme.bodyMedium?.copyWith(
            color: muted,
            decoration: TextDecoration.lineThrough,
          )
        : theme.textTheme.bodyMedium;

    final subtitle = dueComponentSubtitle(l10n, component);
    final statusText = paid
        ? l10n.paymentRowPaid
        : partial
        ? '${l10n.paymentRowPartial(money(component.paidMinor), money(component.amountMinor))}\n'
              '${l10n.paymentRowRemaining(money(component.remainingMinor))}'
        : null;

    return Semantics(
      checked: paid,
      label: [
        dueComponentTitle(l10n, component),
        if (paid) l10n.paymentRowPaid,
        if (partial) l10n.dueBreakdownPartiallyPaid,
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Icon(
                paid
                    ? Icons.check_circle
                    : partial
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: paid ? muted : theme.colorScheme.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dueComponentTitle(l10n, component),
                    style: titleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  if (statusText != null)
                    ProtectedMoneyText(
                      statusText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: partial ? theme.colorScheme.primary : muted,
                      ),
                      interactive: false,
                    ),
                ],
              ),
            ),
            ProtectedMoneyText(
              money(component.amountMinor),
              style: paid
                  ? theme.textTheme.bodyMedium?.copyWith(color: muted)
                  : theme.textTheme.bodyMedium,
              interactive: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// The persistent Due Breakdown list: totals plus grouped component rows.
class DueBreakdownList extends StatelessWidget {
  const DueBreakdownList({
    super.key,
    required this.breakdown,
    this.showTotals = true,
    this.emptyMessage,
  });

  final FacilityDueBreakdown breakdown;

  /// The month carousel already shows Total due / Paid / Left to pay, so the
  /// detail below it opts out instead of repeating them.
  final bool showTotals;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (breakdown.components.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          emptyMessage ?? l10n.dueBreakdownEmpty,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final groups = groupDueComponents(breakdown.components);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTotals) DueBreakdownTotals.fromBreakdown(breakdown),
        for (final group in DueComponentGroup.values)
          if (groups[group] case final components?) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                dueComponentGroupLabel(l10n, group),
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final component in components)
              DueBreakdownRow(
                component: component,
                currencyCode: breakdown.currencyCode,
              ),
          ],
      ],
    );
  }
}
