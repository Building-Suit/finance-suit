import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Manage expense / allowance / income categories: add, rename, archive.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  static const _kinds = CategoryKind.values;
  late final TabController _tabController = TabController(
    length: _kinds.length,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _invalidate() {
    ref.invalidate(allCategoriesProvider);
    for (final kind in _kinds) {
      ref.invalidate(categoriesProvider(kind));
    }
  }

  Future<String?> _promptName(String initial) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.commonEdit),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.catName),
            validator: (v) {
              final e = Validators.requiredText(v, maxLength: 80);
              return e == null ? null : validationMessage(dialogContext, e);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    return saved == true ? controller.text.trim() : null;
  }

  void _showFailure(AppFailure failure) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure))));
  }

  Future<void> _renameCategory(TransactionCategory category) async {
    final name = await _promptName(category.name);
    if (name == null || !mounted) return;
    final result = await ref
        .read(financeRepositoryProvider)
        .renameCategory(category.id, name);
    if (!mounted) return;
    result.when(ok: (_) => _invalidate(), err: _showFailure);
  }

  Future<void> _toggleArchived(TransactionCategory category) async {
    final result = await ref
        .read(financeRepositoryProvider)
        .setCategoryArchived(category.id, archived: !category.isArchived);
    if (!mounted) return;
    result.when(ok: (_) => _invalidate(), err: _showFailure);
  }

  Widget _kindTab(CategoryKind kind, List<TransactionCategory> all) {
    final l10n = AppLocalizations.of(context);
    final categories = all.where((c) => c.kind == kind).toList();
    if (categories.isEmpty) {
      return EmptyStateView(
        icon: FinanceSuitIcons.label,
        message: l10n.catNoneYet,
      );
    }
    return ListView(
      children: [
        for (final category in categories)
          ListTile(
            leading: const FinanceSuitIcon(FinanceSuitIcons.label),
            title: Text(category.name),
            subtitle: category.isArchived
                ? Text(l10n.moneyArchivedLabel)
                : null,
            onTap: () => _renameCategory(category),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'rename') _renameCategory(category);
                if (action == 'archive') _toggleArchived(category);
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.commonEdit)),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    category.isArchived
                        ? l10n.moneyUnarchive
                        : l10n.moneyArchive,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 88),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(allCategoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.catManage),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.txExpense),
            Tab(text: l10n.txAllowance),
            Tab(text: l10n.txCustomIncome),
          ],
        ),
      ),
      body: AsyncView<List<TransactionCategory>>(
        value: categories,
        onRetry: () => ref.invalidate(allCategoriesProvider),
        data: (all) => TabBarView(
          controller: _tabController,
          children: [for (final kind in _kinds) _kindTab(kind, all)],
        ),
      ),
    );
  }
}
