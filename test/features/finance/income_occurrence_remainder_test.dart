import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';

void main() {
  Map<String, dynamic> row({String? remainderOf}) => {
    'id': 'occ-1',
    'income_source_id': 'source-1',
    'scheduled_on': '2026-06-05',
    'expected_amount_minor': 400000,
    'status': 'pending',
    'actual_amount_minor': null,
    'received_on': null,
    'primary_transaction_id': null,
    'salary_period_id': null,
    'snoozed_until': null,
    'notes': null,
    'remainder_of_occurrence_id': remainderOf,
  };

  test('a schedule occurrence is not a remainder', () {
    final occurrence = IncomeOccurrence.fromJson(row());
    expect(occurrence.isRemainder, isFalse);
    expect(occurrence.remainderOfOccurrenceId, isNull);
  });

  test('a remainder links back to its parent occurrence', () {
    final occurrence = IncomeOccurrence.fromJson(row(remainderOf: 'occ-0'));
    expect(occurrence.isRemainder, isTrue);
    expect(occurrence.remainderOfOccurrenceId, 'occ-0');
  });

  test('rows without the column parse as plain occurrences', () {
    final json = row()..remove('remainder_of_occurrence_id');
    expect(IncomeOccurrence.fromJson(json).isRemainder, isFalse);
  });
}
