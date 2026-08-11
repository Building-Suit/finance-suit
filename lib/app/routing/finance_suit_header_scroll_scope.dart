import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shares the shell-owned scroll state with authenticated page headers.
class FinanceSuitHeaderScrollScope
    extends InheritedNotifier<ValueNotifier<bool>> {
  const FinanceSuitHeaderScrollScope({
    super.key,
    required ValueNotifier<bool> isSolid,
    required super.child,
  }) : super(notifier: isSolid);

  /// Returns `null` for isolated previews and routes outside the app shell.
  static ValueListenable<bool>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FinanceSuitHeaderScrollScope>()
      ?.notifier;
}
