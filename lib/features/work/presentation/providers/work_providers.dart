import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/work/data/work_repository.dart';
import 'package:work_tracker/features/work/domain/official_holiday.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';

/// Identifies a calendar month; value type so family providers cache by it.
typedef WorkMonth = ({int year, int month});

/// Entries within one calendar month.
final workEntriesForMonthProvider = FutureProvider.family
    .autoDispose<List<WorkEntry>, WorkMonth>((ref, month) async {
      final start = PlainDate(month.year, month.month, 1);
      final end = start
          .addMonths(1)
          .withDay(1)
          .addDays(-1); // last day of month
      final result = await ref
          .watch(workRepositoryProvider)
          .fetchEntries(start: start, end: end);
      return result.when(ok: (e) => e, err: (f) => throw f);
    });

final holidaysProvider = FutureProvider<List<OfficialHoliday>>((ref) async {
  final result = await ref.watch(workRepositoryProvider).fetchHolidays();
  return result.when(ok: (h) => h, err: (f) => throw f);
});
