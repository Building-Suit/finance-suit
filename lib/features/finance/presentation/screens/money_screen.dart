import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  bool _showArchived = false;

  Future<void> _openAddSheet() async {
    final l10n = AppLocalizations.of(context);
    final kind = await showModalBottomSheet<TransactionKind>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in const [
              TransactionKind.expense,
              TransactionKind.allowanceGiven,
              TransactionKind.customIncome,
              TransactionKind.freelanceIncome,
              TransactionKind.transfer,
            ])
              ListTile(
                leading: Icon(transactionKindIcon(kind)),
                title: Text(transactionKindLabel(l10n, kind)),
                onTap: () => Navigator.of(sheetContext).pop(kind),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == TransactionKind.transfer) {
      await context.push('${AppRoutes.money}/transfer');
    } else {
      await context.push('${AppRoutes.money}/tx/new?kind=${kind.dbValue}');
    }
  }

  Future<void> _onTransactionTap(FinancialTransaction tx) async {
    final l10n = AppLocalizations.of(context);
    if (tx.isSalaryPayment) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.txSalaryLocked)));
      return;
    }
    if (tx.isTransfer) {
      await _confirmDeleteTransfer(tx);
      return;
    }
    await context.push('${AppRoutes.money}/tx/edit', extra: tx);
  }

  Future<void> _confirmDeleteTransfer(FinancialTransaction tx) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.txDeleteConfirmTitle),
        content: Text(l10n.txDeleteConfirmBody),
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
        .deleteTransaction(tx.id);
    if (!mounted) return;
    result.when(
      ok: (_) => invalidateFinanceData(ref),
      err: (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure)))),
    );
  }

  Future<void> _accountAction(AccountBalance account, String action) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(financeRepositoryProvider);
    switch (action) {
      case 'edit':
        await context.push('${AppRoutes.money}/accounts/${account.accountId}');
        return;
      case 'default':
        final result = await repo.setDefaultAccount(account.accountId);
        if (!mounted) return;
        result.when(
          ok: (_) => invalidateFinanceData(ref),
          err: (failure) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failureMessage(context, failure))),
          ),
        );
        return;
      case 'archive':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.moneyArchiveConfirmTitle),
            content: Text(l10n.moneyArchiveConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.moneyArchive),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final result = await repo.setArchived(
          account.accountId,
          archived: true,
        );
        if (!mounted) return;
        result.when(
          ok: (_) => invalidateFinanceData(ref),
          err: (failure) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failureMessage(context, failure))),
          ),
        );
        return;
      case 'unarchive':
        final result = await repo.setArchived(
          account.accountId,
          archived: false,
        );
        if (!mounted) return;
        result.when(
          ok: (_) => invalidateFinanceData(ref),
          err: (failure) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failureMessage(context, failure))),
          ),
        );
        return;
    }
  }

  Widget _accountsTab(AppLocalizations l10n) {
    final accounts = ref.watch(allAccountBalancesProvider);
    return AsyncView<List<AccountBalance>>(
      value: accounts,
      onRetry: () => ref.invalidate(allAccountBalancesProvider),
      data: (all) {
        final active = all.where((a) => !a.isArchived).toList();
        final archived = all.where((a) => a.isArchived).toList();
        if (all.isEmpty) {
          return EmptyStateView(
            icon: Icons.account_balance_wallet_outlined,
            message: l10n.moneyNoAccounts,
            actionLabel: l10n.moneyNewAccount,
            onAction: () => context.push('${AppRoutes.money}/accounts/new'),
          );
        }

        // Total per currency (mixing currencies in one sum is meaningless).
        final totals = <String, int>{};
        for (final a in active) {
          totals[a.currencyCode] =
              (totals[a.currencyCode] ?? 0) + a.balanceMinor;
        }

        return RefreshIndicator(
          onRefresh: () async => invalidateFinanceData(ref),
          child: ListView(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.moneyTotalBalance,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final entry in totals.entries)
                        BalanceText(
                          money: Money(
                            minor: entry.value,
                            currencyCode: entry.key,
                          ),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                    ],
                  ),
                ),
              ),
              for (final account in active)
                _AccountTile(
                  account: account,
                  l10n: l10n,
                  onAction: (action) => _accountAction(account, action),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('${AppRoutes.money}/accounts/new'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.moneyNewAccount),
                ),
              ),
              if (archived.isNotEmpty)
                SwitchListTile(
                  title: Text(l10n.moneyShowArchived),
                  value: _showArchived,
                  onChanged: (v) => setState(() => _showArchived = v),
                ),
              if (_showArchived)
                for (final account in archived)
                  _AccountTile(
                    account: account,
                    l10n: l10n,
                    onAction: (action) => _accountAction(account, action),
                  ),
              const SizedBox(height: 88),
            ],
          ),
        );
      },
    );
  }

  Widget _transactionsTab(AppLocalizations l10n) {
    final transactions = ref.watch(recentTransactionsProvider);
    final accounts = ref.watch(allAccountBalancesProvider);
    final accountNames = {
      for (final a in accounts.value ?? <AccountBalance>[]) a.accountId: a.name,
    };
    return AsyncView<List<FinancialTransaction>>(
      value: transactions,
      onRetry: () => ref.invalidate(recentTransactionsProvider),
      data: (list) {
        if (list.isEmpty) {
          return EmptyStateView(
            icon: Icons.receipt_long_outlined,
            message: l10n.moneyNoTransactions,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => invalidateFinanceData(ref),
          child: ListView.builder(
            itemCount: list.length + 1,
            itemBuilder: (context, index) {
              if (index == list.length) return const SizedBox(height: 88);
              final tx = list[index];
              return TransactionTile(
                transaction: tx,
                accountNames: accountNames,
                onTap: () => _onTransactionTap(tx),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tabMoney),
          actions: [
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: l10n.catManage,
              onPressed: () => context.push('${AppRoutes.money}/categories'),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.moneyAccountsTab),
              Tab(text: l10n.moneyTransactionsTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [_accountsTab(l10n), _transactionsTab(l10n)],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openAddSheet,
          tooltip: l10n.txAddTitle,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.l10n,
    required this.onAction,
  });

  final AccountBalance account;
  final AppLocalizations l10n;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      accountTypeLabel(l10n, account.accountType),
      if (account.isDefault) l10n.moneyDefaultLabel,
      if (account.isArchived) l10n.moneyArchivedLabel,
    ];
    return ListTile(
      leading: Icon(accountTypeIcon(account.accountType)),
      title: Text(account.name),
      subtitle: Text(badges.join(' · ')),
      onTap: () => onAction('edit'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BalanceText(money: account.balance),
          PopupMenuButton<String>(
            onSelected: onAction,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(l10n.commonEdit)),
              if (!account.isArchived && !account.isDefault)
                PopupMenuItem(
                  value: 'default',
                  child: Text(l10n.moneySetDefault),
                ),
              if (!account.isArchived)
                PopupMenuItem(value: 'archive', child: Text(l10n.moneyArchive)),
              if (account.isArchived)
                PopupMenuItem(
                  value: 'unarchive',
                  child: Text(l10n.moneyUnarchive),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
