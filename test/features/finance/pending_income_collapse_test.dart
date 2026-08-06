import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';

void main() {
  const salary = IncomeSource(
    id: 'salary-source',
    name: 'Salary',
    kind: IncomeSourceKind.salary,
    expectedAmountMinor: 4000000,
    currencyCode: 'EGP',
    paymentDay: 5,
    startDate: PlainDate(2026, 1, 1),
    promptDaysBefore: 7,
    primaryAccountId: 'default-account',
    isActive: true,
    allocations: [],
  );

  PendingIncome pending({
    required String id,
    required PlainDate scheduledOn,
    required int minor,
    String? remainderOf,
  }) => PendingIncome(
    source: salary,
    occurrence: IncomeOccurrence(
      id: id,
      incomeSourceId: salary.id,
      scheduledOn: scheduledOn,
      expectedAmountMinor: minor,
      status: IncomeOccurrenceStatus.pending,
      remainderOfOccurrenceId: remainderOf,
    ),
  );

  test('a source is collapsed to its earliest scheduled occurrence', () {
    final collapsed = collapsePendingIncome([
      pending(
        id: 'aug',
        scheduledOn: const PlainDate(2026, 8, 5),
        minor: 4000000,
      ),
      pending(
        id: 'sep',
        scheduledOn: const PlainDate(2026, 9, 5),
        minor: 4000000,
      ),
    ], const PlainDate(2026, 9, 6));
    expect(collapsed, hasLength(1));
    expect(collapsed.single.occurrence.id, 'aug');
  });

  test('a remainder is never hidden behind a same-day scheduled salary', () {
    // Regression: a partial acceptance received on the day the next month is
    // scheduled produced two occurrences dated 2026-08-05, and the schedule
    // row won the collapse, so the shortfall disappeared from the banner.
    final collapsed = collapsePendingIncome([
      pending(
        id: 'aug',
        scheduledOn: const PlainDate(2026, 8, 5),
        minor: 4000000,
      ),
      pending(
        id: 'remainder',
        scheduledOn: const PlainDate(2026, 8, 5),
        minor: 400002,
        remainderOf: 'jul',
      ),
    ], const PlainDate(2026, 8, 6));

    expect(collapsed, hasLength(2));
    expect(collapsed.first.occurrence.id, 'remainder');
    expect(collapsed.first.occurrence.expectedAmountMinor, 400002);
    expect(collapsed.last.occurrence.id, 'aug');
  });

  test('several remainders of the same source all stay visible', () {
    final collapsed = collapsePendingIncome([
      pending(
        id: 'remainder-1',
        scheduledOn: const PlainDate(2026, 7, 5),
        minor: 100000,
        remainderOf: 'jun',
      ),
      pending(
        id: 'remainder-2',
        scheduledOn: const PlainDate(2026, 8, 5),
        minor: 400002,
        remainderOf: 'jul',
      ),
    ], const PlainDate(2026, 8, 6));
    expect(collapsed.map((item) => item.occurrence.id), [
      'remainder-1',
      'remainder-2',
    ]);
  });

  test('items still due today sort ahead of upcoming ones', () {
    final collapsed = collapsePendingIncome([
      pending(
        id: 'upcoming',
        scheduledOn: const PlainDate(2026, 8, 10),
        minor: 4000000,
      ),
      pending(
        id: 'due',
        scheduledOn: const PlainDate(2026, 8, 5),
        minor: 400002,
        remainderOf: 'jul',
      ),
    ], const PlainDate(2026, 8, 6));
    expect(collapsed.first.occurrence.id, 'due');
  });
}
