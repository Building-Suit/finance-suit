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
    'bnpl_purchase' => l10n.paymentPurchaseComponent,
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
  // An ordinary BNPL purchase is bought on one date and owed on another, so
  // the row names both instead of leaving the due date to be guessed.
  if (c.type == FacilityComponentType.bnplPurchase) {
    final purchased = c.occurredOn?.toIso();
    final due = c.dueOn?.toIso();
    if (purchased != null && due != null) {
      return l10n.paymentBnplSubtitle(purchased, due);
    }
    return purchased ?? due;
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
              flex: 2,
              child: Text(
                label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Expanded + end alignment keeps the money column flush at the
            // row end; the FittedBox only shrinks the figure when a large
            // text scale would otherwise overflow it.
            Expanded(
              flex: 3,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ProtectedMoneyText(
                    Money(minor: minor, currencyCode: currencyCode).format(),
                    style: style,
                    interactive: false,
                  ),
                ),
              ),
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
              flex: 3,
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
            // Merchant titles keep the larger share; the amount stays flush
            // at the row end and only shrinks under extreme text scales.
            Expanded(
              flex: 2,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ProtectedMoneyText(
                    money(component.amountMinor),
                    style: paid
                        ? theme.textTheme.bodyMedium?.copyWith(color: muted)
                        : theme.textTheme.bodyMedium,
                    interactive: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The persistent Due Breakdown list: totals plus grouped component rows.
///
/// [maxRows] bounds what is rendered inline. A heavy statement month can
/// carry hundreds of components; painted into one column they made the
/// screen minutes long and produced a single surface so tall the GPU could
/// not rasterize it — the page rendered as a giant flat gray rectangle.
/// Beyond the cap a "Show all" action opens [showDueComponentsSheet], which
/// builds rows lazily and never creates an oversized surface.
class DueBreakdownList extends StatelessWidget {
  const DueBreakdownList({
    super.key,
    required this.breakdown,
    this.showTotals = true,
    this.emptyMessage,
    this.maxRows,
    this.onShowAll,
  });

  final FacilityDueBreakdown breakdown;

  /// The month carousel already shows Total due / Paid / Left to pay, so the
  /// detail below it opts out instead of repeating them.
  final bool showTotals;
  final String? emptyMessage;

  /// Inline row budget; null renders everything (only safe for callers whose
  /// component count is inherently small).
  final int? maxRows;

  /// Invoked by the "Show all" action when [maxRows] truncated the list.
  final VoidCallback? onShowAll;

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
    final total = breakdown.components.length;
    final truncated = maxRows != null && total > maxRows!;
    // Visible rows per group, honoring the budget in display order.
    var budget = maxRows ?? total;
    final visible = <DueComponentGroup, List<FacilityPaymentComponent>>{};
    for (final group in DueComponentGroup.values) {
      final components = groups[group];
      if (components == null || budget <= 0) continue;
      visible[group] = components.take(budget).toList();
      budget -= components.length;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTotals) DueBreakdownTotals.fromBreakdown(breakdown),
        for (final MapEntry(key: group, value: components)
            in visible.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(
                dueComponentGroupLabel(l10n, group),
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          for (final component in components)
            DueBreakdownRow(
              component: component,
              currencyCode: breakdown.currencyCode,
            ),
        ],
        if (truncated)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('due-breakdown-show-all'),
              onPressed: onShowAll,
              child: Text(l10n.dueBreakdownShowAll(total)),
            ),
          ),
      ],
    );
  }
}

/// Opens the full component list as a modal sheet backed by a lazy
/// [ListView], so even a month with hundreds of components never paints one
/// oversized column.
Future<void> showDueComponentsSheet(
  BuildContext context, {
  required String title,
  required List<FacilityPaymentComponent> components,
  required String currencyCode,
}) {
  // Flattened up front: group headers and rows become one lazy list.
  final entries =
      <({DueComponentGroup? header, FacilityPaymentComponent? row})>[];
  final groups = groupDueComponents(components);
  for (final group in DueComponentGroup.values) {
    final components = groups[group];
    if (components == null) continue;
    entries.add((header: group, row: null));
    for (final component in components) {
      entries.add((header: null, row: component));
    }
  }
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Text(
                    l10n.dueBreakdownItemCount(components.length),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('due-breakdown-sheet-list'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry.header case final group?) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Semantics(
                        header: true,
                        child: Text(
                          dueComponentGroupLabel(
                            AppLocalizations.of(context),
                            group,
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    );
                  }
                  return DueBreakdownRow(
                    component: entry.row!,
                    currencyCode: currencyCode,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
