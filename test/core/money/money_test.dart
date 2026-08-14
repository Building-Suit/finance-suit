import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/money/money.dart';

Money egp(int minor) => Money(minor: minor, currencyCode: 'EGP');

void main() {
  group('arithmetic', () {
    test('addition and subtraction are exact', () {
      expect(egp(10000) + egp(2550), egp(12550));
      expect(egp(10000) - egp(2550), egp(7450));
      expect(-egp(500), egp(-500));
    });

    test('currency mismatch throws', () {
      final usd = Money(minor: 100, currencyCode: 'USD');
      expect(() => egp(100) + usd, throwsArgumentError);
      expect(() => egp(100).compareTo(usd), throwsArgumentError);
    });

    test('comparisons', () {
      expect(egp(200) > egp(100), isTrue);
      expect(egp(100) < egp(200), isTrue);
      expect(egp(100) >= egp(100), isTrue);
      expect(egp(100) <= egp(100), isTrue);
    });

    test('timesInt is exact', () {
      expect(egp(1234).timesInt(3), egp(3702));
      expect(egp(1234).timesInt(0), egp(0));
      expect(egp(1234).timesInt(-1), egp(-1234));
    });
  });

  group('timesRational (multipliers as integer percent)', () {
    test('1.5x overtime multiplier: 150/100', () {
      // 100.00 EGP * 1.5 = 150.00 EGP
      expect(egp(10000).timesRational(150, 100), egp(15000));
    });

    test('rounding halfUp on .5 boundary', () {
      // 0.01 * 150 / 100 = 1.5 minor -> 2
      expect(egp(1).timesRational(150, 100), egp(2));
      // negative rounds away from zero
      expect(egp(-1).timesRational(150, 100), egp(-2));
    });

    test('rounding halfEven (banker\'s)', () {
      // 1.5 -> 2 (even), 2.5 -> 2 (even), 3.5 -> 4 (even)
      expect(
        egp(3).timesRational(50, 100, rounding: MoneyRounding.halfEven),
        egp(2),
      ); // 1.5 -> 2
      expect(
        egp(5).timesRational(50, 100, rounding: MoneyRounding.halfEven),
        egp(2),
      ); // 2.5 -> 2
      expect(
        egp(7).timesRational(50, 100, rounding: MoneyRounding.halfEven),
        egp(4),
      ); // 3.5 -> 4
    });

    test('floor and ceiling', () {
      expect(
        egp(10).timesRational(1, 3, rounding: MoneyRounding.floor),
        egp(3),
      );
      expect(
        egp(10).timesRational(1, 3, rounding: MoneyRounding.ceiling),
        egp(4),
      );
      expect(
        egp(-10).timesRational(1, 3, rounding: MoneyRounding.floor),
        egp(-4),
      );
      expect(
        egp(-10).timesRational(1, 3, rounding: MoneyRounding.ceiling),
        egp(-3),
      );
    });

    test('zero denominator throws', () {
      expect(() => egp(100).timesRational(1, 0), throwsArgumentError);
      expect(() => egp(100).divideBy(0), throwsArgumentError);
    });
  });

  group('divideBy (day rate derivation)', () {
    test('salary / standard paid days', () {
      // 12,000.00 EGP / 26 days = 461.5384... -> 461.54 halfUp
      expect(egp(1200000).divideBy(26), egp(46154));
    });

    test('hourly rate from day rate', () {
      // 461.54 / 8 h = 57.6925 -> 57.69
      expect(egp(46154).divideBy(8), egp(5769));
    });
  });

  group('tryParse', () {
    test('plain and decimal input', () {
      expect(Money.tryParse('100', currencyCode: 'EGP'), egp(10000));
      expect(Money.tryParse('100.5', currencyCode: 'EGP'), egp(10050));
      expect(Money.tryParse('100.55', currencyCode: 'EGP'), egp(10055));
      expect(Money.tryParse('0.01', currencyCode: 'EGP'), egp(1));
    });

    test('thousands separators stripped', () {
      expect(Money.tryParse('1,234.56', currencyCode: 'EGP'), egp(123456));
    });

    test('negative input', () {
      expect(Money.tryParse('-42.10', currencyCode: 'EGP'), egp(-4210));
    });

    test('invalid input returns null', () {
      expect(Money.tryParse('', currencyCode: 'EGP'), isNull);
      expect(Money.tryParse('abc', currencyCode: 'EGP'), isNull);
      expect(Money.tryParse('1.234', currencyCode: 'EGP'), isNull);
      expect(Money.tryParse('1.2.3', currencyCode: 'EGP'), isNull);
    });
  });

  group('format', () {
    test('formats with currency code', () {
      expect(egp(1234567).format(locale: 'en'), '12,345.67 EGP');
    });

    test('signed format', () {
      expect(egp(10000).formatSigned(locale: 'en'), '+100.00 EGP');
      expect(egp(-10000).formatSigned(locale: 'en'), '-100.00 EGP');
      expect(egp(0).formatSigned(locale: 'en'), '0.00 EGP');
    });
  });

  group('equality', () {
    test('value equality', () {
      expect(egp(100), egp(100));
      expect(egp(100).hashCode, egp(100).hashCode);
      expect(egp(100), isNot(Money(minor: 100, currencyCode: 'USD')));
    });
  });
}
