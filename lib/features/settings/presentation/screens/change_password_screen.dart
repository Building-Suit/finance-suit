import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  AppFailure? _failure;
  String _password = '';

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final failure = await ref
        .read(authActionProvider.notifier)
        .updatePassword(_passwordController.text);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _failure = failure);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).authPasswordUpdated)),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(authActionProvider).isLoading;

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.setChangePassword),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                controller: _passwordController,
                label: l10n.authNewPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                onChanged: (v) => setState(() => _password = v),
                validator: (v) {
                  final e = Validators.password(v);
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              PasswordStrengthIndicator(password: _password),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirmController,
                label: l10n.authConfirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  final e = Validators.confirmPassword(
                    v,
                    _passwordController.text,
                  );
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              const SizedBox(height: 16),
              AuthErrorBanner(failure: _failure),
              AuthSubmitButton(
                label: l10n.authUpdatePassword,
                busy: busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
