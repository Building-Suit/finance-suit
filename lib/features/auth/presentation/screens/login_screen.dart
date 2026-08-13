import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/security/biometric_login_controller.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  AppFailure? _failure;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final privacyController = ref.read(devicePrivacyProvider.notifier);
    final failure = await ref
        .read(authActionProvider.notifier)
        .signIn(_emailController.text.trim(), _passwordController.text);
    if (failure == null) {
      privacyController.markPasswordAuthenticated();
      return;
    }
    if (!mounted) return;
    if (failure is AuthFailure &&
        failure.kind == AuthFailureKind.emailNotConfirmed) {
      context.go(
        Uri(
          path: AppRoutes.confirmEmail,
          queryParameters: {'email': _emailController.text.trim()},
        ).toString(),
      );
      return;
    }
    setState(() => _failure = failure);
    // On success the auth state change triggers the router redirect.
  }

  Future<void> _biometricSignIn() async {
    setState(() => _failure = null);
    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(biometricLoginProvider.notifier)
        .signIn(reason: l10n.authBiometricLoginReason);
    if (!mounted) return;
    switch (outcome) {
      case BiometricLoginOutcome.authenticated:
        ref.read(devicePrivacyProvider.notifier).markPasswordAuthenticated();
      case BiometricLoginOutcome.canceled:
        return;
      case BiometricLoginOutcome.unavailable:
        AppToast.warning(context, l10n.privacyDeviceAuthUnavailable);
      case BiometricLoginOutcome.invalidCredentials:
      case BiometricLoginOutcome.sessionExpired:
        AppToast.warning(context, l10n.authBiometricSessionExpired);
      case BiometricLoginOutcome.failed:
        AppToast.error(context, l10n.authBiometricLoginFailed);
    }
  }

  void _explainBiometricSetup() {
    final l10n = AppLocalizations.of(context);
    AppToast.info(context, l10n.authBiometricLoginSetupHelp);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final biometricLogin = ref.watch(biometricLoginProvider).value;
    final busy =
        ref.watch(authActionProvider).isLoading ||
        biometricLogin?.authenticating == true;

    return AuthScaffold(
      title: l10n.authLoginTitle,
      showTitle: false,
      brandSubtitle: 'by Building Suit',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextFormField(
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
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    final e = Validators.requiredText(v);
                    return e == null ? null : validationMessage(context, e);
                  },
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.forgotPassword),
                    child: Text(l10n.authForgotPassword),
                  ),
                ),
                const SizedBox(height: 8),
                AuthErrorBanner(failure: _failure),
                Row(
                  children: [
                    Expanded(
                      child: AuthSubmitButton(
                        label: l10n.authLogin,
                        busy: busy,
                        onPressed: _submit,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: l10n.authBiometricLogin,
                      child: OutlinedButton(
                        key: const Key('biometric-login-button'),
                        onPressed: busy
                            ? null
                            : biometricLogin?.canSignIn == true
                            ? _biometricSignIn
                            : _explainBiometricSetup,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.square(48),
                          maximumSize: const Size.square(48),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: biometricLogin?.canSignIn == true
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).disabledColor,
                          ),
                          foregroundColor: biometricLogin?.canSignIn == true
                              ? null
                              : Theme.of(context).disabledColor,
                        ),
                        child: const FinanceSuitIcon(
                          FinanceSuitIcons.fingerprint,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go(AppRoutes.register),
                  child: Text(l10n.authNoAccount),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
