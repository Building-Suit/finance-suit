import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  AppFailure? _failure;
  bool _understood = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate() || !_understood) return;

    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteAccountFinalTitle),
        content: Text(l10n.deleteAccountFinalBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteAccountConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final failure = await ref
        .read(authActionProvider.notifier)
        .deleteAccount(_passwordController.text);
    if (!mounted || failure == null) return;
    setState(() => _failure = failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(authActionProvider).isLoading;
    final errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.deleteAccountTitle),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deleteAccountWarning,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.deleteAccountDataList,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.accountDeletionPolicy),
                child: Text(l10n.deleteAccountPolicy),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _passwordController,
                label: l10n.deleteAccountPasswordPrompt,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  final error = Validators.password(value);
                  return error == null
                      ? null
                      : validationMessage(context, error);
                },
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _understood,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.deleteAccountAcknowledge),
                onChanged: busy
                    ? null
                    : (value) => setState(() => _understood = value ?? false),
              ),
              const SizedBox(height: 8),
              AuthErrorBanner(failure: _failure),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: errorColor,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: busy || !_understood ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.deleteAccountConfirmButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
