import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Blurs financial content while money privacy is locked.
///
/// The real content keeps its layout but is excluded from accessibility while
/// hidden. Tapping authenticates with biometrics or the device credential and
/// reveals all protected amounts until the app leaves the foreground.
class ProtectedMoney extends ConsumerWidget {
  const ProtectedMoney({
    super.key,
    required this.child,
    this.interactive = true,
  });

  final Widget child;
  final bool interactive;

  Future<void> _reveal(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(devicePrivacyProvider.notifier)
        .revealMoney(reason: l10n.privacyRevealReason);
    if (!context.mounted) return;
    switch (outcome) {
      case DeviceAuthOutcome.authenticated:
      case DeviceAuthOutcome.canceled:
        return;
      case DeviceAuthOutcome.unavailable:
        AppToast.warning(context, l10n.privacyDeviceAuthUnavailable);
      case DeviceAuthOutcome.failed:
        AppToast.error(context, l10n.privacyDeviceAuthFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(moneyShouldBeHiddenProvider);
    if (!hidden) return child;

    final l10n = AppLocalizations.of(context);
    final blurred = ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: ExcludeSemantics(child: child),
      ),
    );
    if (!interactive) {
      return Semantics(label: l10n.privacyHiddenAmountLabel, child: blurred);
    }
    return Semantics(
      button: true,
      label: l10n.privacyHiddenAmountLabel,
      hint: l10n.privacyRevealAmountHint,
      onTap: () => _reveal(context, ref),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _reveal(context, ref),
        child: blurred,
      ),
    );
  }
}

class ProtectedMoneyText extends StatelessWidget {
  const ProtectedMoneyText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.interactive = true,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return ProtectedMoney(
      interactive: interactive,
      child: Text(
        data,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        softWrap: softWrap,
      ),
    );
  }
}
