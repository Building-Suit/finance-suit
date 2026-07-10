import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';

void main() {
  group('parse / toIso', () {
    test('round-trips yyyy-MM-dd', () {
      expect(PlainDate.parse('2026-07-10').toIso(), '2026-07-10');
      expect(PlainDate.parse('2026-01-05').toIso(), '2026-01-05');
    });

    test('accepts timestamp strings, keeps date part', () {
      expect(PlainDate.parse('2026-07-10T14:30:00Z').toIso(), '2026-07-10');
    });

    test('pads single digits', () {
      expect(const PlainDate(2026, 3, 4).toIso(), '2026-03-04');
    });
  });

  group('addDays', () {
    test('crosses month boundaries', () {
      expect(
        const PlainDate(2026, 1, 31).addDays(1),
        const PlainDate(2026, 2, 1),
      );
      expect(
        const PlainDate(2026, 3, 1).addDays(-1),
        const PlainDate(2026, 2, 28),
      );
    });

    test('handles leap years', () {
      expect(
        const PlainDate(2024, 2, 28).addDays(1),
        const PlainDate(2024, 2, 29),
      );
      expect(
        const PlainDate(2025, 2, 28).addDays(1),
        const PlainDate(2025, 3, 1),
      );
    });
  });

  group('addMonths', () {
    test('clamps day to target month length', () {
      expect(
        const PlainDate(2026, 1, 31).addMonths(1),
        const PlainDate(2026, 2, 28),
      );
      expect(
        const PlainDate(2024, 1, 31).addMonths(1),
        const PlainDate(2024, 2, 29),
      );
      expect(
        const PlainDate(2026, 3, 31).addMonths(1),
        const PlainDate(2026, 4, 30),
      );
    });

    test('crosses year boundaries', () {
      expect(
        const PlainDate(2026, 12, 15).addMonths(1),
        const PlainDate(2027, 1, 15),
      );
      expect(
        const PlainDate(2026, 1, 15).addMonths(-1),
        const PlainDate(2025, 12, 15),
      );
    });
  });

  group('withDay', () {
    test('clamps to month length', () {
      expect(
        const PlainDate(2026, 2, 10).withDay(31),
        const PlainDate(2026, 2, 28),
      );
      expect(
        const PlainDate(2026, 2, 10).withDay(15),
        const PlainDate(2026, 2, 15),
      );
    });
  });

  group('comparisons', () {
    test('ordering', () {
      expect(
        const PlainDate(2026, 7, 10).isBefore(const PlainDate(2026, 7, 11)),
        isTrue,
      );
      expect(
        const PlainDate(2026, 8, 1).isAfter(const PlainDate(2026, 7, 31)),
        isTrue,
      );
      expect(
        const PlainDate(2026, 7, 10) <= const PlainDate(2026, 7, 10),
        isTrue,
      );
      expect(
        const PlainDate(2026, 7, 10) >= const PlainDate(2026, 7, 10),
        isTrue,
      );
    });

    test('differenceInDays', () {
      expect(
        const PlainDate(
          2026,
          8,
          1,
        ).differenceInDays(const PlainDate(2026, 7, 1)),
        31,
      );
    });
  });

  test('daysInMonth', () {
    expect(PlainDate.daysInMonth(2026, 2), 28);
    expect(PlainDate.daysInMonth(2024, 2), 29);
    expect(PlainDate.daysInMonth(2026, 4), 30);
    expect(PlainDate.daysInMonth(2026, 12), 31);
  });

  test('today uses injected clock', () {
    final date = PlainDate.today(clock: () => DateTime(2026, 7, 10, 23, 59));
    expect(date, const PlainDate(2026, 7, 10));
  });
}
