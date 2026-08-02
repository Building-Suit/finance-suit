import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/domain_labels.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Creates a category from the global Add flow, including the category kind
/// that was previously implied by the selected tab on the management page.
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({
    super.key,
    this.initialKind,
    this.initialParentCategoryId,
  });

  final CategoryKind? initialKind;
  final String? initialParentCategoryId;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  late CategoryKind _kind = widget.initialKind ?? CategoryKind.expense;
  late String? _parentCategoryId = widget.initialParentCategoryId;
  AppFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final result = await ref
        .read(financeRepositoryProvider)
        .createCategory(
          name: _nameController.text.trim(),
          kind: _kind,
          parentCategoryId: _parentCategoryId,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      ok: (_) {
        ref
          ..invalidate(allCategoriesProvider)
          ..invalidate(categoriesProvider(_kind));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).setSaved)),
        );
        context.pop();
      },
      err: (failure) => setState(() => _failure = failure),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider(_kind));
    final parents = (categories.value ?? <TransactionCategory>[])
        .where((category) => !category.isSubcategory)
        .toList();
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.catNew),
      body: FinanceSuitFocusedBody(
        title: l10n.catNew,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSelectionField<CategoryKind>(
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: l10n.catKind),
                  items: [
                    for (final kind in CategoryKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(categoryKindLabel(l10n, kind)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (kind) {
                          if (kind != null) {
                            setState(() {
                              _kind = kind;
                              _parentCategoryId = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                AppSelectionField<String?>(
                  key: ValueKey(_kind),
                  initialValue: _parentCategoryId,
                  decoration: InputDecoration(labelText: l10n.catParent),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.catTopLevel),
                    ),
                    for (final category in parents)
                      DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _parentCategoryId = value),
                ),
                const SizedBox(height: 16),
                AppTextFormField(
                  controller: _nameController,
                  autofocus: true,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l10n.catName),
                  validator: (value) {
                    final error = Validators.requiredText(value, maxLength: 80);
                    return error == null
                        ? null
                        : validationMessage(context, error);
                  },
                ),
                const SizedBox(height: 16),
                AuthErrorBanner(failure: _failure),
                AuthSubmitButton(
                  label: l10n.commonSave,
                  busy: _busy,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
