import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  AppFailure? _failure;
  String _password = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final failure = await ref
        .read(authActionProvider.notifier)
        .register(email, _passwordController.text, _nameController.text.trim());
    if (!mounted) return;
    if (failure != null) {
      setState(() => _failure = failure);
      return;
    }
    if (ref.read(supabaseClientProvider).auth.currentSession != null) {
      return;
    }
    context.go(
      Uri(
        path: AppRoutes.confirmEmail,
        queryParameters: {'email': email},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(authActionProvider).isLoading;

    return AuthScaffold(
      title: l10n.authRegisterTitle,
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.authFullName,
                    prefixIcon: const FinanceSuitIcon(FinanceSuitIcons.person),
                  ),
                  validator: (v) {
                    final e = Validators.requiredText(v, maxLength: 120);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.authEmail,
                    prefixIcon: const FinanceSuitIcon(FinanceSuitIcons.email),
                  ),
                  validator: (v) {
                    final e = Validators.email(v);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _passwordController,
                  label: l10n.authPassword,
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
                  label: l10n.authRegister,
                  busy: busy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(AppRoutes.login),
                  child: Text(l10n.authHaveAccount),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
