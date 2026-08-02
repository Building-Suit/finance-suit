import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class ConfirmEmailScreen extends ConsumerStatefulWidget {
  const ConfirmEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends ConsumerState<ConfirmEmailScreen> {
  static const _cooldownSeconds = 60;
  Timer? _timer;
  int _secondsLeft = 0;
  AppFailure? _failure;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    setState(() => _failure = null);
    final failure = await ref
        .read(authActionProvider.notifier)
        .resendConfirmation(widget.email);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _failure = failure);
      return;
    }
    _startCooldown();
    AppToast.success(context, AppLocalizations.of(context).authResendDone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(authActionProvider).isLoading;

    return AuthScaffold(
      title: l10n.authConfirmEmailTitle,
      subtitle: l10n.authConfirmEmailBody(widget.email),
      children: [
        AuthErrorBanner(failure: _failure),
        AuthSubmitButton(
          label: _secondsLeft > 0
              ? l10n.authResendIn(_secondsLeft)
              : l10n.authResend,
          busy: busy,
          onPressed: _secondsLeft > 0 ? null : _resend,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go(AppRoutes.login),
          child: Text(l10n.authChangeEmail),
        ),
      ],
    );
  }
}
