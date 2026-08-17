import 'dart:async';

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
  /// How long the app must stay backgrounded before it locks. The
  /// notification shade and fullscreen fingerprint prompts stop the activity
  /// for a moment on many devices; deferring the lock keeps that churn from
  /// relocking a live session, while a real backgrounding still locks and a
  /// cold start is always locked.
  static const lockGracePeriod = Duration(seconds: 2);

  /// How long the app must stay backgrounded before revealed amounts blur
  /// again. Kept longer than [lockGracePeriod]: the app lock should demand a
  /// fresh unlock quickly, but a brief glance away (switching apps to paste
  /// a number, answering a quick notification) shouldn't immediately hide
  /// amounts the user just chose to reveal.
  static const blurGracePeriod = Duration(seconds: 10);

  late final DeviceAuthenticator _authenticator;
  Timer? _pendingLock;
  Timer? _pendingBlur;
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
    _pendingLock?.cancel();
    _pendingBlur?.cancel();
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
        // Some devices stop the activity for the notification shade and for
        // fullscreen fingerprint prompts, so a bare paused event is not proof
        // of a real backgrounding. Lock/blur only if the app is still in the
        // background once each grace period passes.
        _pendingLock ??= Timer(lockGracePeriod, _lockIfStillBackgrounded);
        _pendingBlur ??= Timer(blurGracePeriod, _blurIfStillBackgrounded);
      case AppLifecycleState.detached:
        return;
      case AppLifecycleState.resumed:
        _pendingLock?.cancel();
        _pendingLock = null;
        _pendingBlur?.cancel();
        _pendingBlur = null;
        if (!_fullyBackgrounded) return;
        _fullyBackgrounded = false;
        if (mounted) setState(() => _automaticAttempted = false);
    }
  }

  void _lockIfStillBackgrounded() {
    _pendingLock = null;
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden) {
      return;
    }
    final privacy = ref.read(devicePrivacyProvider).value;
    if (privacy?.authenticating == true || DeviceAuthSession.isActive) {
      // A device prompt is still in flight; check again once it settles so a
      // user who backgrounds mid-prompt still comes back to a locked app.
      _pendingLock = Timer(lockGracePeriod, _lockIfStillBackgrounded);
      return;
    }
    _fullyBackgrounded = true;
    ref.read(devicePrivacyProvider.notifier).lockAppForBackground();
    _automaticAttempted = false;
  }

  void _blurIfStillBackgrounded() {
    _pendingBlur = null;
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden) {
      return;
    }
    final privacy = ref.read(devicePrivacyProvider).value;
    if (privacy?.authenticating == true || DeviceAuthSession.isActive) {
      _pendingBlur = Timer(blurGracePeriod, _blurIfStillBackgrounded);
      return;
    }
    ref.read(devicePrivacyProvider.notifier).hideMoneyForBackground();
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

    // Launch the prompt only while the app is actually in the foreground:
    // firing it during a background lock would surface a fingerprint dialog
    // under the notification shade or duplicate one already in flight.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (foreground && !_automaticAttempted && !privacy.authenticating) {
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
