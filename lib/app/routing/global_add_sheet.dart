import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
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
class GlobalAddSheet extends StatefulWidget {
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
  State<GlobalAddSheet> createState() => _GlobalAddSheetState();
}

class _GlobalAddSheetState extends State<GlobalAddSheet> {
  static const _childrenPadding = EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8);

  final _moneyController = ExpansibleController();
  final _workController = ExpansibleController();
  final _macrosController = ExpansibleController();

  @override
  void dispose() {
    _moneyController.dispose();
    _workController.dispose();
    _macrosController.dispose();
    super.dispose();
  }

  void _openOnly(ExpansibleController opened, bool expanded) {
    if (!expanded) return;

    for (final controller in [
      _moneyController,
      _workController,
      _macrosController,
    ]) {
      if (!identical(controller, opened) && controller.isExpanded) {
        controller.collapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        key: const Key('global-add-list'),
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
            controller: _moneyController,
            initiallyExpanded: true,
            childrenPadding: _childrenPadding,
            onExpansionChanged: (expanded) =>
                _openOnly(_moneyController, expanded),
            leading: const FinanceSuitIcon(
              FinanceSuitIcons.accountBalanceWallet,
            ),
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
                icon: FinanceSuitIcons.pauseCircle,
                label: l10n.heldNew,
                route: '/money/held/new',
              ),
              const Divider(indent: 16, endIndent: 16),
              _routeTile(
                context,
                icon: FinanceSuitIcons.accountBalanceWallet,
                label: l10n.moneyNewAccount,
                route: '/money/accounts/new',
              ),
              _routeTile(
                context,
                icon: FinanceSuitIcons.label,
                label: l10n.catNew,
                route: '/money/categories/new',
              ),
            ],
          ),
          ExpansionTile(
            key: const Key('global-add-work-control'),
            controller: _workController,
            childrenPadding: _childrenPadding,
            onExpansionChanged: (expanded) =>
                _openOnly(_workController, expanded),
            leading: const FinanceSuitIcon(FinanceSuitIcons.work),
            title: Text(l10n.addSectionWorkControl),
            children: [
              _routeTile(
                context,
                icon: FinanceSuitIcons.work,
                label: l10n.workAddEntry,
                route: '/work/entry/new',
              ),
              _routeTile(
                context,
                icon: FinanceSuitIcons.celebration,
                label: l10n.workNewHoliday,
                route: '/work/holidays/new',
              ),
              _routeTile(
                context,
                icon: FinanceSuitIcons.priceChange,
                label: l10n.salNewAdjustment,
                route: widget.salaryAdjustmentRoute,
              ),
            ],
          ),
          ExpansionTile(
            key: const Key('global-add-macros'),
            controller: _macrosController,
            childrenPadding: _childrenPadding,
            onExpansionChanged: (expanded) =>
                _openOnly(_macrosController, expanded),
            leading: const FinanceSuitIcon(FinanceSuitIcons.bolt),
            title: Text(l10n.macrosTitle),
            children: [
              _routeTile(
                context,
                icon: FinanceSuitIcons.addCircle,
                label: l10n.macroNew,
                route: '/money/macros/new',
              ),
              ...switch (widget.macros) {
                AsyncValue(:final value?) => [
                  if (value.isNotEmpty)
                    const Divider(indent: 16, endIndent: 16),
                  for (final macro in value) ...[
                    ListTile(
                      leading: const FinanceSuitIcon(FinanceSuitIcons.bolt),
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
                        leading: const FinanceSuitIcon(FinanceSuitIcons.undo),
                        title: Text(l10n.macroRunFrom(macro.name)),
                        onTap: () => Navigator.of(
                          context,
                        ).pop<Object>((macroId: macro.id, reverse: true)),
                      ),
                  ],
                ],
                AsyncValue(hasError: true, :final error) => [
                  ListTile(
                    leading: const FinanceSuitIcon(FinanceSuitIcons.error),
                    title: Text(
                      error is AppFailure
                          ? failureMessage(context, error)
                          : l10n.commonError,
                    ),
                    trailing: IconButton(
                      onPressed: widget.onRetryMacros,
                      tooltip: l10n.commonRetry,
                      icon: const FinanceSuitIcon(FinanceSuitIcons.refresh),
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
                icon: FinanceSuitIcons.tune,
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
    required FinanceSuitGlyph icon,
    required String label,
    required String route,
  }) {
    return ListTile(
      leading: FinanceSuitIcon(icon),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(route),
    );
  }
}
