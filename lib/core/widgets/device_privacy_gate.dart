import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/splash_screen.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class DevicePrivacyGate extends ConsumerStatefulWidget {
  const DevicePrivacyGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DevicePrivacyGate> createState() => _DevicePrivacyGateState();
}

class _DevicePrivacyGateState extends ConsumerState<DevicePrivacyGate>
    with WidgetsBindingObserver {
  late final DeviceAuthenticator _authenticator;
  bool _automaticAttempted = false;
  bool _fullyBackgrounded = false;
  DeviceAuthOutcome? _lastOutcome;

  @override
  void initState() {
    super.initState();
    _authenticator = ref.read(deviceAuthenticatorProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authenticator.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Opening notification/quick-settings surfaces and showing the native
        // authentication dialog can both make the app inactive briefly. They
        // must not lock the app or arm another fingerprint prompt.
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        final privacy = ref.read(devicePrivacyProvider).value;
        if (_fullyBackgrounded || privacy?.authenticating == true) return;
        _fullyBackgrounded = true;
        ref.read(devicePrivacyProvider.notifier).lockForBackground();
        _automaticAttempted = false;
      case AppLifecycleState.detached:
        return;
      case AppLifecycleState.resumed:
        if (!_fullyBackgrounded) return;
        _fullyBackgrounded = false;
        if (mounted) setState(() => _automaticAttempted = false);
    }
  }

  Future<void> _unlock() async {
    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(devicePrivacyProvider.notifier)
        .unlockApp(reason: l10n.privacyUnlockReason);
    if (mounted) setState(() => _lastOutcome = outcome);
  }

  Future<void> _usePassword() async {
    ref.read(devicePrivacyProvider.notifier).signedOut();
    await ref.read(authActionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    ref.listen(authStateProvider, (previous, next) {
      if (next.phase == AuthPhase.signedOut) {
        ref.read(devicePrivacyProvider.notifier).signedOut();
      }
    });
    if (auth.phase != AuthPhase.signedIn) return widget.child;

    final privacyAsync = ref.watch(devicePrivacyProvider);
    final privacy = privacyAsync.value;
    if (privacy == null) return const SplashScreen();
    if (!privacy.appLockEnabled || privacy.appUnlocked) return widget.child;

    if (!_automaticAttempted && !privacy.authenticating) {
      _automaticAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unlock();
      });
    }

    return _DeviceUnlockScreen(
      authenticating: privacy.authenticating,
      outcome: _lastOutcome,
      onUnlock: _unlock,
      onUsePassword: _usePassword,
    );
  }
}

class _DeviceUnlockScreen extends StatelessWidget {
  const _DeviceUnlockScreen({
    required this.authenticating,
    required this.outcome,
    required this.onUnlock,
    required this.onUsePassword,
  });

  final bool authenticating;
  final DeviceAuthOutcome? outcome;
  final VoidCallback onUnlock;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = switch (outcome) {
      DeviceAuthOutcome.unavailable => l10n.privacyDeviceAuthUnavailable,
      DeviceAuthOutcome.failed => l10n.privacyDeviceAuthFailed,
      _ => null,
    };
    return Scaffold(
      backgroundColor: FinanceSuitBrand.buildingNavy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FinanceSuitMark(
                    size: 88,
                    withBackground: false,
                    semanticLabel: null,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.privacyUnlockTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: FinanceSuitBrand.pearlWhite,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.privacyUnlockBody,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FinanceSuitBrand.pearlWhite,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: FinanceSuitBrand.premiumGold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: authenticating ? null : onUnlock,
                    icon: authenticating
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const FinanceSuitIcon(FinanceSuitIcons.fingerprint),
                    label: Text(l10n.privacyUnlockButton),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: authenticating ? null : onUsePassword,
                    style: TextButton.styleFrom(
                      foregroundColor: FinanceSuitBrand.pearlWhite,
                    ),
                    child: Text(l10n.privacyUsePassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
