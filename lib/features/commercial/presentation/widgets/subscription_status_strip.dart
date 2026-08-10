import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Slim entitlement rail used beneath the floating Home header.
///
/// Its geometry is intentionally identical for Free, Pro, and Pro Early
/// Access, so an entitlement refresh never changes the Home layout.
class SubscriptionStatusStrip extends StatelessWidget {
  const SubscriptionStatusStrip({
    super.key,
    required this.entitlement,
    required this.visible,
    required this.onUpgrade,
  });

  final EffectiveEntitlement entitlement;
  final bool visible;
  final VoidCallback onUpgrade;

  static const double height = 32;
  static const double bottomRadius = 12;
  static const _motionDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.suitColors;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final state = _SubscriptionStripState.fromEntitlement(entitlement);
    final label = switch (state) {
      _SubscriptionStripState.free =>
        '${l10n.freePlan} — ${l10n.subscriptionUpgradePrompt}',
      _SubscriptionStripState.pro => l10n.proPlan,
      _SubscriptionStripState.proEarlyAccess => l10n.proEarlyAccess,
    };
    final child = Container(
      key: const Key('subscription-status-strip'),
      height: height,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.warning.background,
        border: Border.all(color: colors.warning.border),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(bottomRadius),
          bottomRight: Radius.circular(bottomRadius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FinanceSuitIcon(
            FinanceSuitIcons.star,
            size: 16,
            color: colors.warning.icon,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.warning.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    final semanticChild = state == _SubscriptionStripState.free
        ? Semantics(
            button: true,
            label: l10n.subscriptionUpgradeFromFree,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(bottomRadius),
                  bottomRight: Radius.circular(bottomRadius),
                ),
                onTap: onUpgrade,
                child: child,
              ),
            ),
          )
        : Semantics(label: label, child: child);

    return ClipRect(
      child: AnimatedSlide(
        duration: reducedMotion ? Duration.zero : _motionDuration,
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, -1),
        child: AnimatedOpacity(
          duration: reducedMotion ? Duration.zero : _motionDuration,
          curve: Curves.easeOutCubic,
          opacity: visible ? 1 : 0,
          child: semanticChild,
        ),
      ),
    );
  }
}

enum _SubscriptionStripState {
  free,
  pro,
  proEarlyAccess;

  static _SubscriptionStripState fromEntitlement(
    EffectiveEntitlement entitlement,
  ) {
    if (!entitlement.isPro) return _SubscriptionStripState.free;
    return switch (entitlement.source) {
      EntitlementSource.earlyAccess || EntitlementSource.openEarlyAccess =>
        _SubscriptionStripState.proEarlyAccess,
      _ => _SubscriptionStripState.pro,
    };
  }
}
