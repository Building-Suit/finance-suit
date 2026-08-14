import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/finance/domain/home_due_obligation.dart';

void main() {
  const today = PlainDate(2026, 8, 13);

  HomeDueObligation due(
    String id,
    String kind,
    PlainDate date,
    int amount, {
    String currency = 'EGP',
  }) => HomeDueObligation(
    id: id,
    kind: kind,
    dueOn: date,
    currencyCode: currency,
    remainingMinor: amount,
  );

  test('aggregates every obligation by payment window, not by account', () {
    final summary = HomeDueSummary(
      today: today,
      items: [
        due('old-card', 'card_statement', const PlainDate(2026, 8, 10), 10000),
        due('today-bill', 'recurring_expense', today, 20000),
        due('cib-aug', 'card_statement', const PlainDate(2026, 8, 25), 421259),
        due(
          'automation-aug',
          'recurring_expense',
          const PlainDate(2026, 8, 28),
          99999,
        ),
        due('valu-sep', 'installment_due', const PlainDate(2026, 9, 5), 400000),
        due('cib-sep', 'card_statement', const PlainDate(2026, 9, 25), 300000),
        due(
          'card-automation-sep',
          'recurring_expense',
          const PlainDate(2026, 9, 12),
          5000,
        ),
        due(
          'cash-automation-sep',
          'recurring_expense',
          const PlainDate(2026, 9, 20),
          7000,
        ),
        due('october', 'installment_due', const PlainDate(2026, 10, 1), 999999),
      ],
    );

    expect(summary.periods, hasLength(3));
    expect(summary.periods[0].period, HomeDuePeriod.current);
    expect(summary.periods[0].totals.single.minor, 30000);
    expect(summary.periods[1].period, HomeDuePeriod.thisMonth);
    expect(summary.periods[1].totals.single.minor, 521258);
    expect(summary.periods[2].period, HomeDuePeriod.nextMonth);
    expect(summary.periods[2].totals.single.minor, 712000);
    expect(summary.periods[2].obligationCount, 4);
  });

  test('keeps currencies separate instead of adding unlike money', () {
    final summary = HomeDueSummary(
      today: today,
      items: [
        due('egp', 'recurring_expense', today, 10000),
        due('usd', 'recurring_expense', today, 2500, currency: 'USD'),
      ],
    );

    expect(summary.periods.single.totals.map((money) => money.currencyCode), [
      'EGP',
      'USD',
    ]);
    expect(summary.periods.single.totals.map((money) => money.minor), [
      10000,
      2500,
    ]);
  });
}
