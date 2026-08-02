import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/theme/finance_suit_semantic_colors.dart';

enum AppToastTone { success, warning, error, info }

class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Presents one consistent, floating notification above the current route.
///
/// A new toast replaces the current one. The root overlay keeps success
/// messages visible when a form closes immediately after saving.
class AppToast {
  const AppToast._();

  static OverlayEntry? _currentEntry;
  static GlobalKey<_AppToastOverlayState>? _currentKey;

  static void show(
    BuildContext context, {
    required String message,
    AppToastTone tone = AppToastTone.info,
    AppToastAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _removeImmediately();
    final key = GlobalKey<_AppToastOverlayState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppToastOverlay(
        key: key,
        message: message,
        tone: tone,
        action: action,
        duration: duration,
        onRemoved: () {
          if (_currentEntry != entry) return;
          _currentEntry = null;
          _currentKey = null;
          entry.remove();
        },
      ),
    );
    _currentEntry = entry;
    _currentKey = key;
    overlay.insert(entry);
  }

  static void success(BuildContext context, String message) =>
      show(context, message: message, tone: AppToastTone.success);

  static void warning(BuildContext context, String message) =>
      show(context, message: message, tone: AppToastTone.warning);

  static void error(BuildContext context, String message) =>
      show(context, message: message, tone: AppToastTone.error);

  static void info(BuildContext context, String message) =>
      show(context, message: message, tone: AppToastTone.info);

  static void dismiss() {
    final state = _currentKey?.currentState;
    if (state != null) {
      state.dismiss();
    } else {
      _removeImmediately();
    }
  }

  static void _removeImmediately() {
    _currentEntry?.remove();
    _currentEntry = null;
    _currentKey = null;
  }
}

class _AppToastOverlay extends StatefulWidget {
  const _AppToastOverlay({
    super.key,
    required this.message,
    required this.tone,
    required this.duration,
    required this.onRemoved,
    this.action,
  });

  final String message;
  final AppToastTone tone;
  final AppToastAction? action;
  final Duration duration;
  final VoidCallback onRemoved;

  @override
  State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = animation;
    _position = Tween<Offset>(
      begin: const Offset(0, -0.18),
      end: Offset.zero,
    ).animate(animation);
    _controller.forward();
    _timer = Timer(widget.duration, dismiss);
  }

  Future<void> dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onRemoved();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status(context, widget.tone);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _position,
              child: Material(
                key: const ValueKey('app-toast'),
                color: status.background,
                elevation: 6,
                shadowColor: Theme.of(context).shadowColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: status.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Semantics(
                    liveRegion: true,
                    container: true,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 16,
                        top: 10,
                        bottom: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FinanceSuitIcon(
                            _icon(widget.tone),
                            color: status.icon,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: status.text),
                            ),
                          ),
                          if (widget.action != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                widget.action!.onPressed();
                                dismiss();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: status.icon,
                              ),
                              child: Text(widget.action!.label),
                            ),
                          ],
                          IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                            onPressed: dismiss,
                            color: status.icon,
                            icon: const FinanceSuitIcon(FinanceSuitIcons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  FinanceSuitStatusColors _status(BuildContext context, AppToastTone tone) {
    final colors = context.suitColors;
    return switch (tone) {
      AppToastTone.success => colors.success,
      AppToastTone.warning => colors.warning,
      AppToastTone.error => colors.error,
      AppToastTone.info => colors.info,
    };
  }

  FinanceSuitGlyph _icon(AppToastTone tone) => switch (tone) {
    AppToastTone.success => FinanceSuitIcons.checkCircle,
    AppToastTone.warning => FinanceSuitIcons.warning,
    AppToastTone.error => FinanceSuitIcons.error,
    AppToastTone.info => FinanceSuitIcons.info,
  };
}
