import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/validation/validators.dart';

void main() {
  group('email', () {
    test('valid addresses pass', () {
      expect(Validators.email('user@example.com'), isNull);
      expect(Validators.email('a.b+tag@sub.domain.co'), isNull);
      expect(Validators.email('  user@example.com  '), isNull);
    });

    test('invalid addresses fail', () {
      expect(Validators.email(null), ValidationError.required);
      expect(Validators.email(''), ValidationError.required);
      expect(Validators.email('plainaddress'), ValidationError.invalidEmail);
      expect(Validators.email('user@'), ValidationError.invalidEmail);
      expect(Validators.email('user@domain'), ValidationError.invalidEmail);
    });
  });

  group('password', () {
    test('length rules', () {
      expect(Validators.password(null), ValidationError.required);
      expect(Validators.password(''), ValidationError.required);
      expect(Validators.password('short'), ValidationError.passwordTooShort);
      expect(Validators.password('longenough'), isNull);
    });

    test('confirmPassword matches', () {
      expect(Validators.confirmPassword('abc12345', 'abc12345'), isNull);
      expect(
        Validators.confirmPassword('abc12345', 'different'),
        ValidationError.passwordsDoNotMatch,
      );
      expect(Validators.confirmPassword(null, 'x'), ValidationError.required);
    });
  });

  group('text', () {
    test('requiredText', () {
      expect(Validators.requiredText('  '), ValidationError.required);
      expect(Validators.requiredText('ok'), isNull);
      expect(Validators.requiredText('x' * 121), ValidationError.tooLong);
    });

    test('optionalText', () {
      expect(Validators.optionalText(null), isNull);
      expect(Validators.optionalText(''), isNull);
      expect(Validators.optionalText('x' * 1001), ValidationError.tooLong);
    });
  });

  group('amounts', () {
    test('positiveAmount', () {
      expect(Validators.positiveAmount('100.50', currencyCode: 'EGP'), isNull);
      expect(
        Validators.positiveAmount('0', currencyCode: 'EGP'),
        ValidationError.amountNotPositive,
      );
      expect(
        Validators.positiveAmount('-5', currencyCode: 'EGP'),
        ValidationError.amountNotPositive,
      );
      expect(
        Validators.positiveAmount('abc', currencyCode: 'EGP'),
        ValidationError.invalidAmount,
      );
      expect(
        Validators.positiveAmount('', currencyCode: 'EGP'),
        ValidationError.required,
      );
    });

    test('nonNegativeAmount accepts zero', () {
      expect(Validators.nonNegativeAmount('0', currencyCode: 'EGP'), isNull);
      expect(
        Validators.nonNegativeAmount('-1', currencyCode: 'EGP'),
        ValidationError.amountNotPositive,
      );
    });
  });

  group('dates and durations', () {
    test('dateRange', () {
      expect(
        Validators.dateRange(
          const PlainDate(2026, 7, 1),
          const PlainDate(2026, 7, 31),
        ),
        isNull,
      );
      expect(
        Validators.dateRange(
          const PlainDate(2026, 8, 1),
          const PlainDate(2026, 7, 31),
        ),
        ValidationError.startAfterEnd,
      );
      expect(
        Validators.dateRange(null, const PlainDate(2026, 7, 31)),
        ValidationError.invalidDate,
      );
    });

    test('durationMinutes bounds 1..2880', () {
      expect(Validators.durationMinutes(480), isNull);
      expect(Validators.durationMinutes(2880), isNull);
      expect(Validators.durationMinutes(0), ValidationError.invalidDuration);
      expect(Validators.durationMinutes(2881), ValidationError.invalidDuration);
      expect(Validators.durationMinutes(null), ValidationError.invalidDuration);
    });

    test('breakWithinDuration', () {
      expect(Validators.breakWithinDuration(30, 480), isNull);
      expect(
        Validators.breakWithinDuration(480, 480),
        ValidationError.breakTooLong,
      );
      expect(
        Validators.breakWithinDuration(-1, 480),
        ValidationError.invalidDuration,
      );
    });
  });

  group('domain-specific', () {
    test('differentAccounts', () {
      expect(Validators.differentAccounts('a', 'b'), isNull);
      expect(
        Validators.differentAccounts('a', 'a'),
        ValidationError.sameAccounts,
      );
      expect(Validators.differentAccounts(null, 'b'), ValidationError.required);
    });

    test('multiplierPct 0..1000', () {
      expect(Validators.multiplierPct(150), isNull);
      expect(Validators.multiplierPct(0), isNull);
      expect(Validators.multiplierPct(1000), isNull);
      expect(Validators.multiplierPct(1001), ValidationError.invalidMultiplier);
      expect(Validators.multiplierPct(-1), ValidationError.invalidMultiplier);
    });

    test('dayUnitsHundredths 1..200', () {
      expect(Validators.dayUnitsHundredths(100), isNull);
      expect(Validators.dayUnitsHundredths(200), isNull);
      expect(
        Validators.dayUnitsHundredths(0),
        ValidationError.invalidDayFraction,
      );
      expect(
        Validators.dayUnitsHundredths(201),
        ValidationError.invalidDayFraction,
      );
    });

    test('dayOfMonth 1..28', () {
      expect(Validators.dayOfMonth(1), isNull);
      expect(Validators.dayOfMonth(28), isNull);
      expect(Validators.dayOfMonth(0), ValidationError.invalidDayOfMonth);
      expect(Validators.dayOfMonth(29), ValidationError.invalidDayOfMonth);
    });
  });
}
