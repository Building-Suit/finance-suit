import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:work_tracker/core/money/money.dart';

enum AppMoneySign { automatic, explicit, never }

/// Canonical visual money rendering for user-facing amounts.
///
/// Keeps the numeric amount and currency code in an LTR, non-wrapping group so
/// currency codes such as EGP remain physically to the right in RTL layouts.
class AppMoneyText extends StatelessWidget {
  const AppMoneyText({
    super.key,
    required this.money,
    this.sign = AppMoneySign.automatic,
    this.style,
    this.currencyStyle,
    this.color,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final Money money;
  final AppMoneySign sign;
  final TextStyle? style;
  final TextStyle? currencyStyle;
  final Color? color;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag();
    final textTheme = Theme.of(context).textTheme;
    final amountStyle = (style ?? textTheme.titleMedium)?.copyWith(
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final codeStyle = (currencyStyle ?? textTheme.labelSmall)?.copyWith(
      color: color ?? amountStyle?.color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amount = _amount(locale);
    final label = '$amount ${money.currencyCode}';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: amount, style: amountStyle),
                const TextSpan(text: '\u00A0'),
                TextSpan(text: money.currencyCode, style: codeStyle),
              ],
            ),
            maxLines: maxLines,
            overflow: overflow,
            softWrap: false,
            textAlign: textAlign,
          ),
        ),
      ),
    );
  }

  String _amount(String? locale) {
    final absMinor = sign == AppMoneySign.never
        ? money.minor.abs()
        : money.minor;
    final value = absMinor.abs() / Money.minorUnitsPerMajor;
    final formatter = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 2,
    );
    final prefix = switch (sign) {
      AppMoneySign.never => '',
      AppMoneySign.explicit when money.minor > 0 => '+',
      AppMoneySign.explicit when money.minor < 0 => '-',
      AppMoneySign.automatic when money.minor < 0 => '-',
      _ => '',
    };
    return '$prefix${formatter.format(value)}';
  }
}
