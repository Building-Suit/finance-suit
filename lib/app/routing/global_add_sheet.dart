import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// A saved macro selected from the global Add sheet.
typedef MacroRunSelection = ({String macroId, bool reverse});

/// All top-level creation entry points live here so nested pages never compete
/// with the shell's global Add button.
class GlobalAddSheet extends StatelessWidget {
  const GlobalAddSheet({
    super.key,
    required this.macros,
    required this.onRetryMacros,
    this.salaryAdjustmentRoute = '/work/adjustments/new',
  });

  final AsyncValue<List<TransactionMacro>> macros;
  final VoidCallback onRetryMacros;
  final String salaryAdjustmentRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 4, 24, 8),
            child: Text(
              l10n.commonAdd,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ExpansionTile(
            key: const Key('global-add-money-control'),
            initiallyExpanded: true,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(l10n.addSectionMoneyControl),
            children: [
              for (final kind in const [
                TransactionKind.expense,
                TransactionKind.allowanceGiven,
                TransactionKind.customIncome,
                TransactionKind.freelanceIncome,
              ])
                _routeTile(
                  context,
                  icon: transactionKindIcon(kind),
                  label: transactionKindLabel(l10n, kind),
                  route: '/money/tx/new?kind=${kind.dbValue}',
                ),
              _routeTile(
                context,
                icon: transactionKindIcon(TransactionKind.transfer),
                label: transactionKindLabel(l10n, TransactionKind.transfer),
                route: '/money/transfer',
              ),
              _routeTile(
                context,
                icon: Icons.pause_circle_outline,
                label: l10n.heldNew,
                route: '/money/held/new',
              ),
              const Divider(indent: 16, endIndent: 16),
              _routeTile(
                context,
                icon: Icons.account_balance_wallet_outlined,
                label: l10n.moneyNewAccount,
                route: '/money/accounts/new',
              ),
              _routeTile(
                context,
                icon: Icons.label_outline,
                label: l10n.catNew,
                route: '/money/categories/new',
              ),
            ],
          ),
          ExpansionTile(
            key: const Key('global-add-work-control'),
            leading: const Icon(Icons.work_outline),
            title: Text(l10n.addSectionWorkControl),
            children: [
              _routeTile(
                context,
                icon: Icons.work_outline,
                label: l10n.workAddEntry,
                route: '/work/entry/new',
              ),
              _routeTile(
                context,
                icon: Icons.celebration_outlined,
                label: l10n.workNewHoliday,
                route: '/work/holidays/new',
              ),
              _routeTile(
                context,
                icon: Icons.price_change_outlined,
                label: l10n.salNewAdjustment,
                route: salaryAdjustmentRoute,
              ),
            ],
          ),
          ExpansionTile(
            key: const Key('global-add-macros'),
            leading: const Icon(Icons.bolt_outlined),
            title: Text(l10n.macrosTitle),
            children: [
              _routeTile(
                context,
                icon: Icons.add_circle_outline,
                label: l10n.macroNew,
                route: '/money/macros/new',
              ),
              ...switch (macros) {
                AsyncValue(:final value?) => [
                  if (value.isNotEmpty)
                    const Divider(indent: 16, endIndent: 16),
                  for (final macro in value) ...[
                    ListTile(
                      leading: const Icon(Icons.bolt_outlined),
                      title: Text(
                        macro.isReversible
                            ? l10n.macroRunTo(macro.name)
                            : macro.name,
                      ),
                      onTap: () => Navigator.of(
                        context,
                      ).pop<Object>((macroId: macro.id, reverse: false)),
                    ),
                    if (macro.isReversible)
                      ListTile(
                        leading: const Icon(Icons.undo),
                        title: Text(l10n.macroRunFrom(macro.name)),
                        onTap: () => Navigator.of(
                          context,
                        ).pop<Object>((macroId: macro.id, reverse: true)),
                      ),
                  ],
                ],
                AsyncValue(hasError: true, :final error) => [
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(
                      error is AppFailure
                          ? failureMessage(context, error)
                          : l10n.commonError,
                    ),
                    trailing: IconButton(
                      onPressed: onRetryMacros,
                      tooltip: l10n.commonRetry,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ],
                _ => [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ],
              },
              const Divider(indent: 16, endIndent: 16),
              _routeTile(
                context,
                icon: Icons.tune,
                label: l10n.macroManage,
                route: '/money/macros',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _routeTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(route),
    );
  }
}
