import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Current-month payable obligations and their read-only cash-impact preview.
class HomeDueSection extends StatelessWidget {
  const HomeDueSection({
    super.key,
    required this.summary,
    required this.accounts,
  });
  final HomeDueSummary summary;
  final List<AccountBalance> accounts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    if (summary.isEmpty) {
      return Card(
        key: const Key('home-next-due-empty'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              FinanceSuitIcon(
                FinanceSuitIcons.checkCircle,
                color: colors.success.icon,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.homeNothingDueThisMonth)),
            ],
          ),
        ),
      );
    }
    final urgency = summary.earliest!;
    final urgencyText = summary.hasOverdue
        ? l10n.homeLate
        : urgency.isDueToday
        ? l10n.dueStatusDueToday
        : l10n.homeNextDue(urgency.dueOn.toIso());
    final urgencyColor = summary.hasOverdue
        ? colors.error.text
        : urgency.isDueToday
        ? colors.warning.text
        : colors.textMuted;
    return Card(
      key: const Key('home-next-due-section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: (summary.hasOverdue ? colors.error : colors.warning)
                        .background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: FinanceSuitIcon(
                      FinanceSuitIcons.calendarToday,
                      color:
                          (summary.hasOverdue ? colors.error : colors.warning)
                              .icon,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.homeNextDueTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        summary.count == 1
                            ? urgencyText
                            : '$urgencyText · ${l10n.homeDueCount(summary.count)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: urgencyColor),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  key: const Key('home-next-due-calculate'),
                  onPressed: () => _openImpact(context),
                  icon: const FinanceSuitIcon(FinanceSuitIcons.calculate),
                  label: Text(l10n.homeCalculate),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final total in summary.totals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppMoneyText(
                  money: total.total,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  color: colors.textPrimary,
                ),
              ),
            const Divider(),
            for (final obligation in summary.obligations)
              _ObligationRow(obligation: obligation),
          ],
        ),
      ),
    );
  }

  void _openImpact(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DueImpactSheet(summary: summary, accounts: accounts),
  );
}

class _DueImpactSheet extends StatefulWidget {
  const _DueImpactSheet({required this.summary, required this.accounts});
  final HomeDueSummary summary;
  final List<AccountBalance> accounts;
  @override
  State<_DueImpactSheet> createState() => _DueImpactSheetState();
}

class _DueImpactSheetState extends State<_DueImpactSheet> {
  String? _selectedAccountId;

  List<AccountBalance> _eligible(String currency) => widget.accounts
      .where(
        (account) =>
            !account.isArchived &&
            !account.isLiability &&
            account.currencyCode == currency,
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final eligible = _eligible(widget.summary.totals.first.currencyCode);
    _selectedAccountId =
        eligible.where((account) => account.isDefault).firstOrNull?.accountId ??
        eligible.firstOrNull?.accountId;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final total = widget.summary.totals.first;
    final eligible = _eligible(total.currencyCode);
    final selected = eligible
        .where((account) => account.accountId == _selectedAccountId)
        .firstOrNull;
    final remaining = selected == null
        ? null
        : selected.balanceMinor - total.totalMinor;
    final shortfall = remaining == null || remaining >= 0 ? null : -remaining;
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.homeDueImpact,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('home-due-impact-close'),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const FinanceSuitIcon(FinanceSuitIcons.close),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  key: const Key('home-due-impact-list'),
                  children: [
                    _SummaryCard(summary: widget.summary),
                    const SizedBox(height: 16),
                    Text(
                      l10n.homeWhatYouPayFor,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final obligation in widget.summary.obligations)
                      _ObligationDetail(obligation: obligation),
                    const SizedBox(height: 16),
                    _PaymentImpact(
                      currencyTotal: total,
                      selected: selected,
                      eligible: eligible,
                      selectedId: _selectedAccountId,
                      remainingMinor: remaining,
                      shortfallMinor: shortfall,
                      onChanged: (id) =>
                          setState(() => _selectedAccountId = id),
                    ),
                    if (widget.summary.totals.length > 1) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.homeMultipleCurrencies,
                          style: TextStyle(color: colors.warning.text),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final HomeDueSummary summary;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    return Card(
      color: colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeDueCount(summary.count),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: 8),
            for (final total in summary.totals) ...[
              _Metric(label: l10n.homeMinimumDue, money: total.minimum),
              _Metric(label: l10n.homeTotalDue, money: total.total),
            ],
            _Metric(
              label: l10n.homeLateAfter,
              text: summary.hasOverdue
                  ? l10n.homeLate
                  : summary.earliest?.dueOn.toIso(),
              color: summary.hasOverdue ? colors.error.text : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, this.money, this.text, this.color});
  final String label;
  final Money? money;
  final String? text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.suitColors.textMuted),
          ),
        ),
        if (money != null)
          AppMoneyText(
            money: money!,
            color: color,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        if (text != null) Text(text!, style: TextStyle(color: color)),
      ],
    ),
  );
}

class _ObligationRow extends StatelessWidget {
  const _ObligationRow({required this.obligation});
  final HomeDueObligation obligation;
  @override
  Widget build(BuildContext context) {
    final colors = context.suitColors;
    final tone = obligation.isOverdue
        ? colors.error
        : obligation.isDueToday
        ? colors.warning
        : colors.info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSuitIcon(
            _iconFor(obligation.kind),
            color: tone.icon,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obligation.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusText(context, obligation),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tone.text),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppMoneyText(
            money: obligation.remaining,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _ObligationDetail extends StatelessWidget {
  const _ObligationDetail({required this.obligation});
  final HomeDueObligation obligation;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = (obligation.details['items'] as List?) ?? const [];
    final installments =
        (obligation.details['installments'] as List?) ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: Key('home-due-detail-${obligation.id}'),
        leading: FinanceSuitIcon(_iconFor(obligation.kind)),
        title: Text(
          obligation.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(_statusText(context, obligation)),
        trailing: AppMoneyText(
          money: obligation.remaining,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Metric(
                  label: l10n.homeMinimumDue,
                  money: obligation.minimumDue,
                ),
                _Metric(label: l10n.homeTotalDue, money: obligation.remaining),
                if (obligation.paidMinor > 0)
                  _Metric(label: l10n.dueStatusPaid, money: obligation.paid),
                if (obligation.kind ==
                    HomeDueObligationKind.installmentDue) ...[
                  Text(
                    l10n.homeInstallmentOf(
                      _int(obligation.details['sequence_number']),
                      _int(obligation.details['installment_count']),
                    ),
                  ),
                  Text(
                    '${l10n.homePurchaseDate}: ${obligation.details['purchase_date'] ?? ''}',
                  ),
                  _Metric(
                    label: l10n.homePlanRemaining,
                    money: Money(
                      minor: _int(obligation.details['plan_remaining_minor']),
                      currencyCode: obligation.currencyCode,
                    ),
                  ),
                ],
                if (obligation.kind ==
                    HomeDueObligationKind.recurringExpense) ...[
                  Text(l10n.homeScheduled(obligation.dueOn.toIso())),
                  Text(
                    '${obligation.details['frequency'] ?? ''} · ${obligation.details['category'] ?? ''}',
                  ),
                ],
                for (final item in [...items, ...installments])
                  _DetailItem(
                    item: Map<String, dynamic>.from(item as Map),
                    currencyCode: obligation.currencyCode,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.item, required this.currencyCode});
  final Map<String, dynamic> item;
  final String currencyCode;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text((item['title'] ?? 'Charge') as String),
    subtitle: Text(
      '${item['occurred_on'] ?? item['due_on'] ?? ''}${item['category'] == null ? '' : ' · ${item['category']}'}',
    ),
    trailing: AppMoneyText(
      money: Money(
        minor: _int(item['remaining_minor'] ?? item['amount_minor']),
        currencyCode: currencyCode,
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

class _PaymentImpact extends StatelessWidget {
  const _PaymentImpact({
    required this.currencyTotal,
    required this.selected,
    required this.eligible,
    required this.selectedId,
    required this.remainingMinor,
    required this.shortfallMinor,
    required this.onChanged,
  });
  final HomeDueCurrencyTotal currencyTotal;
  final AccountBalance? selected;
  final List<AccountBalance> eligible;
  final String? selectedId;
  final int? remainingMinor;
  final int? shortfallMinor;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSelectionField<String>(
              key: const Key('home-due-pay-from-account'),
              initialValue: selectedId,
              sheetTitle: l10n.homePayFromAccount,
              decoration: InputDecoration(labelText: l10n.homePayFromAccount),
              items: eligible
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.accountId,
                      child: Text(account.name),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
            if (selected == null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.homeNoMatchingAccount,
                style: TextStyle(color: colors.warning.text),
              ),
            ] else ...[
              const SizedBox(height: 12),
              _Metric(label: l10n.homeCurrentBalance, money: selected!.balance),
              _Metric(
                label: l10n.homeAmountDeducted,
                money: currencyTotal.total,
              ),
              _Metric(
                label: l10n.homeRemainingBalance,
                money: Money(
                  minor: remainingMinor!,
                  currencyCode: currencyTotal.currencyCode,
                ),
              ),
              if (shortfallMinor != null)
                Text(
                  l10n.homeInsufficientFunds(
                    Money(
                      minor: shortfallMinor!,
                      currencyCode: currencyTotal.currencyCode,
                    ).format(),
                  ),
                  style: TextStyle(color: colors.error.text),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

FinanceSuitGlyph _iconFor(HomeDueObligationKind kind) => switch (kind) {
  HomeDueObligationKind.cardStatement => FinanceSuitIcons.creditCard,
  HomeDueObligationKind.installmentDue => FinanceSuitIcons.payments,
  HomeDueObligationKind.recurringExpense => FinanceSuitIcons.eventRepeat,
};

String _statusText(BuildContext context, HomeDueObligation obligation) {
  final l10n = AppLocalizations.of(context);
  if (obligation.isOverdue) return l10n.homeLate;
  if (obligation.isDueToday) return l10n.dueStatusDueToday;
  return l10n.homeNextDue(obligation.dueOn.toIso());
}

int _int(dynamic value) => value is num ? value.toInt() : 0;
