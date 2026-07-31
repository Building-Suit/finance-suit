import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';

enum TopMessageTone { success, warning, error, info }

class TopMessageAction {
  const TopMessageAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

class TopMessage {
  const TopMessage._();

  static ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>
  show(
    BuildContext context, {
    required String message,
    TopMessageTone tone = TopMessageTone.info,
    TopMessageAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    final banner = MaterialBanner(
      leading: FinanceSuitIcon(_icon(tone), color: _status(context, tone).icon),
      content: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: _status(context, tone).text),
      ),
      backgroundColor: _status(context, tone).background,
      dividerColor: _status(context, tone).border,
      actions: [
        if (action != null)
          TextButton(onPressed: action.onPressed, child: Text(action.label)),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: messenger.hideCurrentMaterialBanner,
          icon: const FinanceSuitIcon(FinanceSuitIcons.close),
        ),
      ],
    );
    final controller = messenger.showMaterialBanner(banner);
    Future<void>.delayed(duration, () {
      if (context.mounted) messenger.hideCurrentMaterialBanner();
    });
    return controller;
  }

  static void success(BuildContext context, String message) =>
      show(context, message: message, tone: TopMessageTone.success);

  static void error(BuildContext context, String message) =>
      show(context, message: message, tone: TopMessageTone.error);

  static FinanceSuitStatusColors _status(
    BuildContext context,
    TopMessageTone tone,
  ) {
    final colors = context.suitColors;
    return switch (tone) {
      TopMessageTone.success => colors.success,
      TopMessageTone.warning => colors.warning,
      TopMessageTone.error => colors.error,
      TopMessageTone.info => colors.info,
    };
  }

  static FinanceSuitGlyph _icon(TopMessageTone tone) => switch (tone) {
    TopMessageTone.success => FinanceSuitIcons.checkCircle,
    TopMessageTone.warning => FinanceSuitIcons.warning,
    TopMessageTone.error => FinanceSuitIcons.error,
    TopMessageTone.info => FinanceSuitIcons.info,
  };
}
