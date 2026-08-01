import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Saved macros: run them (forward or in reverse) or manage their actions.
class MacrosScreen extends ConsumerStatefulWidget {
  const MacrosScreen({super.key});

  @override
  ConsumerState<MacrosScreen> createState() => _MacrosScreenState();
}

class _MacrosScreenState extends ConsumerState<MacrosScreen> {
  Future<void> _run(TransactionMacro macro, {required bool reverse}) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(financeRepositoryProvider)
        .applyMacro(
          macroId: macro.id,
          occurredOn: PlainDate.today(),
          reverse: reverse,
        );
    if (!mounted) return;
    result.when(
      ok: (count) {
        invalidateFinanceData(ref);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.macroApplied(count))));
      },
      err: (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure)))),
    );
  }

  Future<void> _delete(TransactionMacro macro) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.macroDeleteConfirmTitle),
        content: Text(l10n.macroDeleteConfirmBody),
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
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .deleteMacro(macro.id);
    if (!mounted) return;
    result.when(
      ok: (_) => ref.invalidate(macrosProvider),
      err: (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure)))),
    );
  }

  Future<void> _onAction(TransactionMacro macro, String action) async {
    switch (action) {
      case 'run':
        await _run(macro, reverse: false);
      case 'runReverse':
        await _run(macro, reverse: true);
      case 'edit':
        await context.push('${AppRoutes.money}/macros/edit', extra: macro);
      case 'delete':
        await _delete(macro);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final macros = ref.watch(macrosProvider);
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.macrosTitle),
      body: AsyncView<List<TransactionMacro>>(
        value: macros,
        onRetry: () => ref.invalidate(macrosProvider),
        data: (list) {
          if (list.isEmpty) {
            return EmptyStateView(
              icon: FinanceSuitIcons.bolt,
              message: l10n.macroEmpty,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(macrosProvider),
            child: ListView(
              children: [
                for (final macro in list)
                  _MacroTile(
                    macro: macro,
                    l10n: l10n,
                    onAction: (action) => _onAction(macro, action),
                  ),
                const SizedBox(height: 88),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.macro,
    required this.l10n,
    required this.onAction,
  });

  final TransactionMacro macro;
  final AppLocalizations l10n;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = [
      l10n.macroActionCount(macro.items.length),
      if (macro.isReversible) l10n.macroReversibleBadge,
    ];
    return ListTile(
      leading: const FinanceSuitIcon(FinanceSuitIcons.bolt),
      title: Text(macro.name),
      subtitle: Text(subtitleParts.join(' · ')),
      onTap: () => onAction('edit'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const FinanceSuitIcon(FinanceSuitIcons.play),
            tooltip: macro.isReversible
                ? l10n.macroRunTo(macro.name)
                : l10n.macroRun,
            onPressed: () => onAction('run'),
          ),
          if (macro.isReversible)
            IconButton(
              icon: const FinanceSuitIcon(FinanceSuitIcons.undo),
              tooltip: l10n.macroRunFrom(macro.name),
              onPressed: () => onAction('runReverse'),
            ),
          PopupMenuButton<String>(
            onSelected: onAction,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'run', child: Text(l10n.macroRun)),
              if (macro.isReversible)
                PopupMenuItem(
                  value: 'runReverse',
                  child: Text(l10n.macroRunReverse),
                ),
              PopupMenuItem(value: 'edit', child: Text(l10n.commonEdit)),
              PopupMenuItem(value: 'delete', child: Text(l10n.commonDelete)),
            ],
          ),
        ],
      ),
    );
  }
}
