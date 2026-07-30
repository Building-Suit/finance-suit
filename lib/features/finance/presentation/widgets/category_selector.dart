import 'package:flutter/material.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Selects a regular category first, then an optional child category.
///
/// The persisted value remains the existing single `category_id`: selecting no
/// child stores the parent id, while selecting a child stores the child id.
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
    super.key,
  });

  final List<TransactionCategory> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = categories
        .where((category) => category.id == selectedCategoryId)
        .firstOrNull;
    final selectedParentId = selected?.parentCategoryId ?? selected?.id;
    final parents = categories
        .where((category) => !category.isSubcategory)
        .toList();
    final children = categories
        .where((category) => category.parentCategoryId == selectedParentId)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          key: ValueKey('category-parent-$selectedParentId'),
          initialValue: selectedParentId,
          decoration: InputDecoration(labelText: l10n.txCategory),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.txNoCategory),
            ),
            for (final parent in parents)
              DropdownMenuItem<String?>(
                value: parent.id,
                child: Text(parent.name),
              ),
          ],
          onChanged: onChanged,
        ),
        if (selectedParentId != null && children.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            key: ValueKey('category-child-$selectedCategoryId'),
            initialValue: selected?.isSubcategory == true ? selected!.id : null,
            decoration: InputDecoration(labelText: l10n.catSubcategoryOptional),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.catUseParentCategory),
              ),
              for (final child in children)
                DropdownMenuItem<String?>(
                  value: child.id,
                  child: Text(child.name),
                ),
            ],
            onChanged: (childId) => onChanged(childId ?? selectedParentId),
          ),
        ],
      ],
    );
  }
}
