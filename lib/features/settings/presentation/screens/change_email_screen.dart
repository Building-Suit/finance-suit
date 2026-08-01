import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class ChangeEmailScreen extends ConsumerStatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  ConsumerState<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends ConsumerState<ChangeEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  AppFailure? _failure;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _failure = null);
    if (!_formKey.currentState!.validate()) return;
    final failure = await ref
        .read(authActionProvider.notifier)
        .updateEmail(_emailController.text.trim());
    if (!mounted) return;
    if (failure != null) {
      setState(() => _failure = failure);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).setEmailChangeSent)),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(authActionProvider).isLoading;

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.setChangeEmail),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.setNewEmail,
                  prefixIcon: const FinanceSuitIcon(FinanceSuitIcons.email),
                ),
                validator: (v) {
                  final e = Validators.email(v);
                  return e == null ? null : validationMessage(context, e);
                },
              ),
              const SizedBox(height: 16),
              AuthErrorBanner(failure: _failure),
              AuthSubmitButton(
                label: l10n.commonSave,
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
