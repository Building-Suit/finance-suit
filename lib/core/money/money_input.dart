import 'package:flutter/services.dart';
import 'package:work_tracker/core/money/money.dart';

/// Canonical thousands-grouping for every money and large-number input.
///
/// Inserts `,` between groups of three integer digits while the user types,
/// keeps the caret anchored to the digit it was next to, and accepts an
/// optional decimal part (`maxDecimalDigits`). Parsing back to exact minor
/// units stays in [Money.tryParse], which already ignores separators, so a
/// grouped field never changes the stored amount.
///
/// Never attach this to phone numbers, OTPs, card last-four digits, dates,
/// day-of-month fields, or reference numbers.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter({this.maxDecimalDigits = 2});

  /// 0 turns the field into a grouped integer input (counts, quantities).
  final int maxDecimalDigits;

  static const _separator = ',';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    // Digits before the caret survive any regrouping; count them first.
    final caret = newValue.selection.baseOffset.clamp(0, raw.length);
    var digitsBeforeCaret = 0;
    for (var i = 0; i < caret; i++) {
      if (_isKept(raw[i])) digitsBeforeCaret++;
    }

    final buffer = StringBuffer();
    var seenDot = false;
    var decimals = 0;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '.' && maxDecimalDigits > 0 && !seenDot) {
        seenDot = true;
        buffer.write('.');
        continue;
      }
      if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        if (seenDot) {
          if (decimals >= maxDecimalDigits) continue;
          decimals++;
        }
        buffer.write(ch);
      }
      // Separators and every other character are dropped and regenerated.
    }
    final cleaned = buffer.toString();
    if (cleaned.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final dotIndex = cleaned.indexOf('.');
    final integerPart = dotIndex < 0 ? cleaned : cleaned.substring(0, dotIndex);
    final decimalPart = dotIndex < 0 ? null : cleaned.substring(dotIndex);
    final grouped = StringBuffer();
    for (var i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        grouped.write(_separator);
      }
      grouped.write(integerPart[i]);
    }
    if (decimalPart != null) grouped.write(decimalPart);
    final text = grouped.toString();

    // Re-place the caret after the same number of kept characters.
    var offset = text.length;
    var seen = 0;
    for (var i = 0; i < text.length; i++) {
      if (seen == digitsBeforeCaret) {
        offset = i;
        break;
      }
      if (_isKept(text[i])) seen++;
    }
    if (seen < digitsBeforeCaret) offset = text.length;
    // Never leave the caret directly before a separator the user just
    // crossed; sitting after it matches what typing feels like.
    while (offset < text.length && text[offset] == _separator) {
      offset++;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  static bool _isKept(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) || ch == '.';
  }
}

/// Formatters for a money amount field (grouped, up to 2 decimals).
List<TextInputFormatter> moneyInputFormatters() => const [
  ThousandsSeparatorInputFormatter(),
];

/// Formatters for a whole-number field that still deserves grouping.
List<TextInputFormatter> groupedIntegerFormatters() => const [
  ThousandsSeparatorInputFormatter(maxDecimalDigits: 0),
];

/// Pre-fills a controller with a grouped representation of stored minor
/// units, so editing an existing record shows `1,234.56` and not `1234.56`.
String formatMinorForInput(int minor) {
  final major = minor ~/ Money.minorUnitsPerMajor;
  final fraction = (minor % Money.minorUnitsPerMajor).abs();
  final integerText = major.abs().toString();
  final grouped = StringBuffer();
  if (minor < 0) grouped.write('-');
  for (var i = 0; i < integerText.length; i++) {
    if (i > 0 && (integerText.length - i) % 3 == 0) grouped.write(',');
    grouped.write(integerText[i]);
  }
  grouped
    ..write('.')
    ..write(fraction.toString().padLeft(2, '0'));
  return grouped.toString();
}
