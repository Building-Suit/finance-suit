import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/money/money.dart';

/// Reusable, unit-testable validation rules. Screens map the returned
/// error codes to localized messages.
enum ValidationError {
  required,
  invalidEmail,
  passwordTooShort,
  passwordsDoNotMatch,
  invalidAmount,
  amountNotPositive,
  invalidDate,
  startAfterEnd,
  invalidDuration,
  breakTooLong,
  sameAccounts,
  tooLong,
  invalidMultiplier,
  invalidDayFraction,
  invalidDayOfMonth,
}

class Validators {
  const Validators._();

  static final _emailPattern = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  static ValidationError? email(String? value) {
    if (value == null || value.trim().isEmpty) return ValidationError.required;
    if (!_emailPattern.hasMatch(value.trim())) {
      return ValidationError.invalidEmail;
    }
    return null;
  }

  static ValidationError? password(String? value, {int minLength = 8}) {
    if (value == null || value.isEmpty) return ValidationError.required;
    if (value.length < minLength) return ValidationError.passwordTooShort;
    return null;
  }

  static ValidationError? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return ValidationError.required;
    if (value != original) return ValidationError.passwordsDoNotMatch;
    return null;
  }

  static ValidationError? requiredText(String? value, {int maxLength = 120}) {
    if (value == null || value.trim().isEmpty) return ValidationError.required;
    if (value.length > maxLength) return ValidationError.tooLong;
    return null;
  }

  static ValidationError? optionalText(String? value, {int maxLength = 1000}) {
    if (value != null && value.length > maxLength) {
      return ValidationError.tooLong;
    }
    return null;
  }

  /// Positive money amount from user input.
  static ValidationError? positiveAmount(
    String? value, {
    required String currencyCode,
  }) {
    if (value == null || value.trim().isEmpty) return ValidationError.required;
    final money = Money.tryParse(value, currencyCode: currencyCode);
    if (money == null) return ValidationError.invalidAmount;
    if (!money.isPositive) return ValidationError.amountNotPositive;
    return null;
  }

  /// Amount that may be zero (opening balance).
  static ValidationError? nonNegativeAmount(
    String? value, {
    required String currencyCode,
  }) {
    if (value == null || value.trim().isEmpty) return ValidationError.required;
    final money = Money.tryParse(value, currencyCode: currencyCode);
    if (money == null) return ValidationError.invalidAmount;
    if (money.isNegative) return ValidationError.amountNotPositive;
    return null;
  }

  static ValidationError? dateRange(PlainDate? start, PlainDate? end) {
    if (start == null || end == null) return ValidationError.invalidDate;
    if (start.isAfter(end)) return ValidationError.startAfterEnd;
    return null;
  }

  /// Work duration in minutes; supports overnight sessions capped at 2 days.
  static ValidationError? durationMinutes(int? minutes) {
    if (minutes == null || minutes <= 0 || minutes > 2880) {
      return ValidationError.invalidDuration;
    }
    return null;
  }

  static ValidationError? breakWithinDuration(
    int breakMinutes,
    int totalMinutes,
  ) {
    if (breakMinutes < 0) return ValidationError.invalidDuration;
    if (breakMinutes >= totalMinutes) return ValidationError.breakTooLong;
    return null;
  }

  static ValidationError? differentAccounts(String? source, String? dest) {
    if (source == null || dest == null) return ValidationError.required;
    if (source == dest) return ValidationError.sameAccounts;
    return null;
  }

  /// Multiplier percent: 0..1000 (0x..10x).
  static ValidationError? multiplierPct(int? pct) {
    if (pct == null || pct < 0 || pct > 1000) {
      return ValidationError.invalidMultiplier;
    }
    return null;
  }

  /// Day units hundredths: 1..200 (0.01..2 days).
  static ValidationError? dayUnitsHundredths(int? units) {
    if (units == null || units <= 0 || units > 200) {
      return ValidationError.invalidDayFraction;
    }
    return null;
  }

  /// Salary period start / payment day limited to 1..28 so every month works.
  static ValidationError? dayOfMonth(int? day) {
    if (day == null || day < 1 || day > 28) {
      return ValidationError.invalidDayOfMonth;
    }
    return null;
  }
}
