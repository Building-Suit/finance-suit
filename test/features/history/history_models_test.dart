import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/date_range.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';

void main() {
  group('HistoryQuery', () {
    test('last30Days includes today and the previous 29 days', () {
      final query = HistoryQuery.last30Days(const PlainDate(2026, 7, 10));

      expect(query.range.start, const PlainDate(2026, 6, 11));
      expect(query.range.end, const PlainDate(2026, 7, 10));
      expect(query.limit, 30);
    });

    test('uses default keyset only for default sort with a cursor', () {
      final cursor = HistoryCursor(
        recordDate: const PlainDate(2026, 7, 10),
        sortAt: DateTime.utc(2026, 7, 10, 10),
        id: 'abc',
      );
      final base = HistoryQuery(
        range: rangeForPreset(
          DateRangePreset.last30Days,
          const PlainDate(2026, 7, 10),
        ),
        cursor: cursor,
      );

      expect(base.usesDefaultKeyset, isTrue);
      expect(
        base.copyWith(sort: HistorySort.amountDesc).usesDefaultKeyset,
        isFalse,
      );
    });

    test('value equality keeps Riverpod family keys stable', () {
      final range = rangeForPreset(
        DateRangePreset.currentMonth,
        const PlainDate(2026, 7, 10),
      );

      expect(HistoryQuery(range: range), HistoryQuery(range: range));
    });

    test('cursor equality includes display sort time', () {
      final first = HistoryCursor(
        recordDate: const PlainDate(2026, 7, 10),
        sortAt: DateTime.utc(2026, 7, 10, 10),
        id: 'abc',
      );
      final same = HistoryCursor(
        recordDate: const PlainDate(2026, 7, 10),
        sortAt: DateTime.utc(2026, 7, 10, 10),
        id: 'abc',
      );
      final differentlySorted = HistoryCursor(
        recordDate: const PlainDate(2026, 7, 10),
        sortAt: DateTime.utc(2026, 7, 10, 9),
        id: 'abc',
      );

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(differentlySorted));
    });
  });

  group('HistoryItem', () {
    test('parses transaction history and exposes cursor', () {
      final item = HistoryItem.fromJson({
        'id': '00000000-0000-0000-0000-000000000001',
        'record_group': 'transaction',
        'record_type': 'allowance_given',
        'record_date': '2026-07-09',
        'created_at': '2026-07-10T10:00:00Z',
        'sort_at': '2026-07-10T09:59:59.999999Z',
        'amount_minor': 100000,
        'currency_code': 'EGP',
      });

      expect(item.isOutgoing, isTrue);
      expect(item.isIncome, isFalse);
      expect(item.createdAt, DateTime.utc(2026, 7, 10, 10));
      expect(item.cursor.recordDate, const PlainDate(2026, 7, 9));
      expect(item.cursor.sortAt, DateTime.parse('2026-07-10T09:59:59.999999Z'));
    });

    test('parses signed salary adjustment', () {
      final item = HistoryItem.fromJson({
        'id': '00000000-0000-0000-0000-000000000002',
        'record_group': 'salary_adjustment',
        'record_type': 'deduction',
        'record_date': '2026-07-08',
        'created_at': '2026-07-10T10:00:00Z',
        'amount_minor': -25000,
        'currency_code': 'EGP',
      });

      expect(item.amount!.minor, -25000);
      expect(item.isOutgoing, isTrue);
      expect(item.sortAt, item.createdAt);
    });
  });
}
