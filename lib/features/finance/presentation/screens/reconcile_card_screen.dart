import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../data/finance_repository.dart';
import '../../domain/credit_card_reconciliation.dart';
import '../../domain/credit_facility.dart';
import '../providers/finance_providers.dart';

class ReconcileCardScreen extends ConsumerStatefulWidget {
  const ReconcileCardScreen({
    super.key,
    required this.summary,
  });

  final CreditFacilitySummary summary;

  @override
  ConsumerState<ReconcileCardScreen> createState() => _ReconcileCardScreenState();
}

class _ReconcileCardScreenState extends ConsumerState<ReconcileCardScreen> {
  final _descController = TextEditingController();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  bool _isSavingLine = false;
  bool _isApplyingRepair = false;
  bool _isCatchingUp = false;

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _addBankLine() async {
    final desc = _descController.text.trim();
    final amountText = _amountController.text.trim();
    if (desc.isEmpty || amountText.isEmpty) return;

    final amountDouble = double.tryParse(amountText);
    if (amountDouble == null || amountDouble <= 0) return;

    final amountMinor = (amountDouble * 100).round();

    setState(() => _isSavingLine = true);
    final result = await ref.read(financeRepositoryProvider).saveBankStatementLine(
          accountId: widget.summary.accountId,
          lineDate: PlainDate.today(),
          postingDate: PlainDate.today(),
          amountMinor: amountMinor,
          currencyCode: widget.summary.currencyCode,
          description: desc,
          referenceNumber: _refController.text.trim().isEmpty ? null : _refController.text.trim(),
        );

    if (!mounted) return;
    setState(() => _isSavingLine = false);

    result.when(
      ok: (_) {
        _descController.clear();
        _amountController.clear();
        _refController.clear();
        ref.invalidate(bankStatementLinesProvider(widget.summary.accountId));
        AppToast.success(context, AppLocalizations.of(context).setSaved);
      },
      err: (failure) {
        AppToast.error(context, failureMessage(context, failure));
      },
    );
  }

  Future<void> _applyRepair(RepairManifest manifest) async {
    setState(() => _isApplyingRepair = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .applyReconciliationRepairPlan(manifest);

    if (!mounted) return;
    setState(() => _isApplyingRepair = false);

    result.when(
      ok: (_) {
        ref.invalidate(cibRepairPreviewProvider(widget.summary.accountId));
        invalidateFinanceData(ref);
        AppToast.success(context, 'Repair plan applied successfully');
      },
      err: (failure) {
        AppToast.error(context, failureMessage(context, failure));
      },
    );
  }

  Future<void> _runCatchUp() async {
    setState(() => _isCatchingUp = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .catchUpCreditCardProcessing(accountId: widget.summary.accountId);

    if (!mounted) return;
    setState(() => _isCatchingUp = false);

    result.when(
      ok: (data) {
        invalidateFinanceData(ref);
        AppToast.success(
          context,
          'Catch-up completed: ${data['posted_count'] ?? 0} interest charges posted',
        );
      },
      err: (failure) {
        AppToast.error(context, failureMessage(context, failure));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final linesAsync = ref.watch(bankStatementLinesProvider(widget.summary.accountId));
    final previewAsync = ref.watch(cibRepairPreviewProvider(widget.summary.accountId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Reconcile - ${widget.summary.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Run Catch-up Automation',
            onPressed: _isCatchingUp ? null : _runCatchUp,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Account balance summary card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Card Overview',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Outstanding Balance:', style: theme.textTheme.bodyMedium),
                        AppMoneyText(
                          money: Money(
                            widget.summary.outstandingMinor,
                            widget.summary.currencyCode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Credit Limit:', style: theme.textTheme.bodyMedium),
                        AppMoneyText(
                          money: Money(
                            widget.summary.creditLimitMinor,
                            widget.summary.currencyCode,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Manual Bank Statement Entry Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Bank Line / Charge',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'e.g. Interest Charge or Merchant Purchase',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount (${widget.summary.currencyCode})',
                        hintText: '0.00',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _refController,
                      decoration: const InputDecoration(
                        labelText: 'Reference Number (Optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isSavingLine ? null : _addBankLine,
                      icon: const Icon(Icons.add),
                      label: const Text('Save Bank Line'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Bank Statement Lines List
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Imported / Entered Bank Lines',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    linesAsync.when(
                      data: (lines) {
                        if (lines.isEmpty) {
                          return Text(
                            'No bank lines entered yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.outline),
                          );
                        }
                        return Column(
                          children: lines.map((line) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(line.description),
                              subtitle: Text('Date: ${PlainDate.fromDateTime(line.postingDate)}'),
                              trailing: AppMoneyText(
                                money: Money(line.amountMinor, line.currencyCode),
                              ),
                            );
                          }).toList(),
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Text('Error loading lines: $err'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // CIB Repair Preview Manifest
            previewAsync.when(
              data: (manifest) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Historical Repair Preview',
                              style: theme.textTheme.titleMedium,
                            ),
                            Chip(
                              label: Text(manifest.status),
                              backgroundColor: colors.primary.withValues(alpha: 0.1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Reassignments (${manifest.reassignments.length}):',
                          style: theme.textTheme.labelLarge,
                        ),
                        ...manifest.reassignments.map((r) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text('• ${r['item']} (${r['date']}): ${r['original_cycle']} -> ${r['target_cycle']}'),
                            )),
                        const SizedBox(height: 8),
                        Text(
                          'Interest Links (${manifest.interestLinks.length}):',
                          style: theme.textTheme.labelLarge,
                        ),
                        ...manifest.interestLinks.map((i) => Padding(
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text('• ${i['installment']}: Paid ${i['payment_date']} (${i['status']})'),
                            )),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isApplyingRepair ? null : () => _applyRepair(manifest),
                          icon: const Icon(Icons.build),
                          label: const Text('Apply Repair Plan'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, _) => Text('Error loading repair preview: $err'),
            ),
          ],
        ),
      ),
    );
  }
}
