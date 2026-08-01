import 'package:flutter/widgets.dart';

/// Moves focus to the next eligible form control after a selection input
/// commits a value.
///
/// The next control is resolved from the real focus-traversal order of the
/// enclosing scope (reading order by default, honoring RTL), so it may be a
/// text input, a numeric or date input, or another selection field. Hidden,
/// disabled, read-only, and unmounted controls never participate in
/// traversal, so they are skipped naturally. When no eligible control
/// follows, focus is released instead of wrapping around, so the keyboard
/// dismisses cleanly.
///
/// The advance is deferred to the end of the next frame so widgets revealed
/// or removed by the committed selection settle first — no fixed delays.
void advanceFocusAfterSelection(FocusNode from) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = from.context;
    if (context == null || !context.mounted || !from.canRequestFocus) return;
    final policy =
        FocusTraversalGroup.maybeOf(context) ?? ReadingOrderTraversalPolicy();
    final last = policy.findLastFocus(from, ignoreCurrentFocus: true);
    if (from == last) {
      // The committed field is the final control: release focus instead of
      // wrapping back to the first field.
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    // Anchor traversal on the committed field, then advance one step.
    from.requestFocus();
    policy.next(from);
  });
}
