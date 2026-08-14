import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

/// Rounding strategy for money math that produces fractional minor units.
enum MoneyRounding { halfUp, halfEven, floor, ceiling }

/// Immutable money value backed by integer minor units.
///
/// 100 EGP == Money(minor: 10000, currencyCode: 'EGP').
/// Never use doubles as the authoritative representation.
@immutable
class Money implements Comparable<Money> {
  const Money({required this.minor, required this.currencyCode});

  const Money.zero(this.currencyCode) : minor = 0;

  /// Minor units (piastres for EGP). May be negative for derived values
  /// such as net cash flow; persisted transaction amounts stay positive.
  final int minor;
  final String currencyCode;

  static const int minorUnitsPerMajor = 100;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get isPositive => minor > 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor: minor + other.minor, currencyCode: currencyCode);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor: minor - other.minor, currencyCode: currencyCode);
  }

  Money operator -() => Money(minor: -minor, currencyCode: currencyCode);

  bool operator >(Money other) {
    _assertSameCurrency(other);
    return minor > other.minor;
  }

  bool operator <(Money other) {
    _assertSameCurrency(other);
    return minor < other.minor;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other);
    return minor >= other.minor;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other);
    return minor <= other.minor;
  }

  Money abs() => Money(minor: minor.abs(), currencyCode: currencyCode);

  /// Multiplies by an integer factor (exact).
  Money timesInt(int factor) =>
      Money(minor: minor * factor, currencyCode: currencyCode);

  /// Multiplies by a rational `numerator / denominator` with deterministic
  /// rounding. Used for multipliers such as 1.5x stored as 150/100.
  Money timesRational(
    int numerator,
    int denominator, {
    MoneyRounding rounding = MoneyRounding.halfUp,
  }) {
    if (denominator == 0) {
      throw ArgumentError('denominator must not be zero');
    }
    return Money(
      minor: _divRounded(minor * numerator, denominator, rounding),
      currencyCode: currencyCode,
    );
  }

  /// Divides by an integer with deterministic rounding.
  Money divideBy(int divisor, {MoneyRounding rounding = MoneyRounding.halfUp}) {
    if (divisor == 0) throw ArgumentError('divisor must not be zero');
    return Money(
      minor: _divRounded(minor, divisor, rounding),
      currencyCode: currencyCode,
    );
  }

  static int _divRounded(int dividend, int divisor, MoneyRounding rounding) {
    if (divisor < 0) {
      dividend = -dividend;
      divisor = -divisor;
    }
    final quotient = dividend ~/ divisor;
    final remainder = dividend.remainder(divisor);
    if (remainder == 0) return quotient;

    final negative = dividend < 0;
    final absRemainder = remainder.abs();
    final twice = absRemainder * 2;

    switch (rounding) {
      case MoneyRounding.floor:
        return negative ? quotient - 1 : quotient;
      case MoneyRounding.ceiling:
        return negative ? quotient : quotient + 1;
      case MoneyRounding.halfUp:
        if (twice >= divisor) {
          return negative ? quotient - 1 : quotient + 1;
        }
        return quotient;
      case MoneyRounding.halfEven:
        if (twice > divisor) {
          return negative ? quotient - 1 : quotient + 1;
        }
        if (twice == divisor) {
          final roundedAway = negative ? quotient - 1 : quotient + 1;
          return quotient.isEven ? quotient : roundedAway;
        }
        return quotient;
    }
  }

  /// Parses user input such as "1,234.56" into money.
  /// Returns null for invalid input; callers surface a validation error.
  static Money? tryParse(String input, {required String currencyCode}) {
    final cleaned = input.trim().replaceAll(',', '').replaceAll('٬', '');
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final sign = match.group(1) == null ? 1 : -1;
    final major = int.parse(match.group(2)!);
    final fractionText = (match.group(3) ?? '').padRight(2, '0');
    final fraction = int.parse(fractionText);
    return Money(
      minor: sign * (major * minorUnitsPerMajor + fraction),
      currencyCode: currencyCode,
    );
  }

  /// Formats as e.g. `12,345.67 EGP` (or locale equivalent).
  String format({String? locale, bool withSymbol = true}) {
    final majorValue = minor / minorUnitsPerMajor;
    final formatter = NumberFormat.currency(
      locale: locale,
      name: currencyCode,
      symbol: '',
      decimalDigits: 2,
    );
    final amount = formatter.format(majorValue).trim();
    return withSymbol ? '$amount $currencyCode' : amount;
  }

  /// Signed format with explicit + / − prefix, for flows and adjustments.
  String formatSigned({String? locale}) {
    final text = abs().format(locale: locale);
    if (minor < 0) return '-$text';
    if (minor > 0) return '+$text';
    return text;
  }

  void _assertSameCurrency(Money other) {
    if (other.currencyCode != currencyCode) {
      throw ArgumentError(
        'Currency mismatch: $currencyCode vs ${other.currencyCode}',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minor == minor &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(minor, currencyCode);

  @override
  String toString() => 'Money($minor $currencyCode)';
}
