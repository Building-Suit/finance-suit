import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/money/money_input.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Automation center for recurring outflows: pending occurrences waiting
/// for a decision on top, the rules themselves below — the expense and
/// transfer twin of the income sources screen.
class RecurringRulesScreen extends ConsumerWidget {
  const RecurringRulesScreen({super.key});

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    PendingRecurring pending,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AcceptDialog(pending: pending, ref: ref),
    );
    if (accepted == true && context.mounted) {
      invalidateRecurringAutomation(ref);
      invalidateFinanceData(ref);
      AppToast.success(
        context,
        AppLocalizations.of(context).recurringAcceptedMessage,
      );
    }
  }

  Future<void> _skip(
    BuildContext context,
    WidgetRef ref,
    PendingRecurring pending,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.recurringSkipTitle),
        content: Text(l10n.recurringSkipHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.incomeSkip),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .skipRecurringOccurrence(pending.occurrence.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateRecurringAutomation(ref),
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _snooze(
    BuildContext context,
    WidgetRef ref,
    PendingRecurring pending,
  ) async {
    final result = await ref
        .read(financeRepositoryProvider)
        .snoozeRecurringOccurrence(
          occurrenceId: pending.occurrence.id,
          snoozedUntil: DateTime.now().add(const Duration(hours: 24)),
        );
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateRecurringAutomation(ref),
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    RecurringRule rule,
    bool active,
  ) async {
    final result = await ref
        .read(financeRepositoryProvider)
        .setRecurringRuleActive(rule.id, active: active);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateRecurringAutomation(ref),
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RecurringRule rule,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.recurringDeleteConfirmTitle),
        content: Text(l10n.recurringDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .deleteRecurringRule(rule.id);
    if (!context.mounted) return;
    result.when(
      ok: (_) => invalidateRecurringAutomation(ref),
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final rulesAsync = ref.watch(recurringRulesProvider);
    final pending =
        ref.watch(pendingRecurringProvider).value ?? const <PendingRecurring>[];
    final today = PlainDate.today();
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(
        semanticTitle: l10n.recurringCenterTitle,
      ),
      body: FinanceSuitFocusedBody(
        title: l10n.recurringCenterTitle,
        child: AsyncView<List<RecurringRule>>(
          value: rulesAsync,
          onRetry: () {
            ref.invalidate(recurringRulesProvider);
            ref.invalidate(pendingRecurringProvider);
          },
          data: (rules) {
            if (rules.isEmpty && pending.isEmpty) {
              return EmptyStateView(
                icon: FinanceSuitIcons.eventRepeat,
                message: l10n.recurringEmptyTitle,
                actionLabel: l10n.recurringAddRule,
                onAction: () =>
                    context.push('${AppRoutes.settings}/recurring/new'),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                invalidateRecurringAutomation(ref);
                invalidateFinanceData(ref);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (pending.isNotEmpty) ...[
                    Text(
                      l10n.recurringPendingTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final item in pending)
                      _PendingCard(
                        pending: item,
                        today: today,
                        onAccept: () => _accept(context, ref, item),
                        onSkip: () => _skip(context, ref, item),
                        onSnooze: () => _snooze(context, ref, item),
                      ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    l10n.recurringRulesTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final rule in rules)
                    _RuleCard(
                      rule: rule,
                      onEdit: () => context.push(
                        '${AppRoutes.settings}/recurring/edit',
                        extra: rule,
                      ),
                      onToggleActive: (active) =>
                          _setActive(context, ref, rule, active),
                      onDelete: () => _delete(context, ref, rule),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('recurring-add-rule'),
        onPressed: () => context.push('${AppRoutes.settings}/recurring/new'),
        icon: const FinanceSuitIcon(FinanceSuitIcons.add),
        label: Text(l10n.recurringAddRule),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.pending,
    required this.today,
    required this.onAccept,
    required this.onSkip,
    required this.onSnooze,
  });

  final PendingRecurring pending;
  final PlainDate today;
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final warning = context.suitColors.warning;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: Key('recurring-pending-${pending.occurrence.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  pending.rule.name,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppMoneyText(
                  money: pending.expectedAmount,
                  style: textTheme.titleMedium,
                  sign: AppMoneySign.never,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                FinanceSuitIcon(FinanceSuitIcons.moreTime, color: warning.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending.isDueOn(today)
                        ? l10n.incomeDue(pending.occurrence.scheduledOn.toIso())
                        : l10n.incomeUpcoming(
                            pending.occurrence.scheduledOn.toIso(),
                          ),
                    style: TextStyle(color: warning.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              recurringRuleKindLabel(l10n, pending.rule.kind),
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(onPressed: onSkip, child: Text(l10n.incomeSkip)),
                TextButton(onPressed: onSnooze, child: Text(l10n.incomeLater)),
                FilledButton(
                  key: Key('recurring-accept-${pending.occurrence.id}'),
                  onPressed: onAccept,
                  child: Text(l10n.recurringPayNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends ConsumerWidget {
  const _RuleCard({
    required this.rule,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final RecurringRule rule;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: Key('recurring-rule-${rule.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: FinanceSuitIcon(
          rule.kind == RecurringRuleKind.transfer
              ? FinanceSuitIcons.swapHoriz
              : FinanceSuitIcons.eventRepeat,
        ),
        title: Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${recurringScheduleLabel(l10n, rule.frequency, rule.paymentDay)}'
          ' · ${rule.amount.format()}'
          '${rule.isActive ? '' : '\n${l10n.recurringPaused}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: !rule.isActive,
        onTap: onEdit,
        trailing: PopupMenuButton<String>(
          key: Key('recurring-rule-actions-${rule.id}'),
          onSelected: (action) {
            switch (action) {
              case 'edit':
                onEdit();
              case 'toggle':
                onToggleActive(!rule.isActive);
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (menuContext) => [
            PopupMenuItem(value: 'edit', child: Text(l10n.commonEdit)),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                rule.isActive ? l10n.recurringPause : l10n.recurringResume,
              ),
            ),
            PopupMenuItem(value: 'delete', child: Text(l10n.commonDelete)),
          ],
        ),
      ),
    );
  }
}

/// Confirms the actual amount and date before booking the entry.
class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog({required this.pending, required this.ref});

  final PendingRecurring pending;
  final WidgetRef ref;

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _notesController = TextEditingController();
  late PlainDate _paidOn;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: formatMinorForInput(widget.pending.occurrence.expectedAmountMinor),
    );
    final today = PlainDate.today();
    final scheduled = widget.pending.occurrence.scheduledOn;
    _paidOn = scheduled.isAfter(today) ? today : scheduled;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _paidOn = PlainDate.fromDateTime(picked));
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final currency = widget.pending.rule.currencyCode;
    final amount = Money.tryParse(
      _amountController.text,
      currencyCode: currency,
    )!;
    final notes = _notesController.text.trim();
    setState(() => _busy = true);
    final result = await widget.ref
        .read(financeRepositoryProvider)
        .acceptRecurringOccurrence(
          occurrenceId: widget.pending.occurrence.id,
          actualAmountMinor: amount.minor,
          paidOn: _paidOn,
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) => Navigator.of(context).pop(true),
      err: (failure) =>
          setState(() => _error = failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = widget.pending.rule.currencyCode;
    return AlertDialog(
      title: Text(l10n.recurringAcceptTitle),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recurringAcceptHelp(widget.pending.rule.name),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                key: const Key('recurring-accept-amount'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: moneyInputFormatters(),
                decoration: InputDecoration(
                  labelText: l10n.salActualAmount,
                  suffixText: currency,
                ),
                validator: (v) {
                  final e = Validators.positiveAmount(
                    v,
                    currencyCode: currency,
                  );
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.recurringPaidOn),
                subtitle: Text(_paidOn.toIso()),
                trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                onTap: _busy ? null : _pickDate,
              ),
              AppTextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: '${l10n.commonNotes} (${l10n.commonOptional})',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('recurring-accept-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.recurringPayNow),
        ),
      ],
    );
  }
}
