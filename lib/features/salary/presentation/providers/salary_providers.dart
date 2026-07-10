import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/salary/data/salary_repository.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/features/work/data/work_repository.dart';

/// Value-type period range so family providers cache by it.
typedef PeriodRange = ({PlainDate start, PlainDate end});

/// Bounds of the earning period containing today.
final currentPeriodBoundsProvider = FutureProvider<PeriodBounds>((ref) async {
  final settings = await ref.watch(salarySettingsProvider.future);
  return SalaryPeriods.boundsFor(settings, PlainDate.today());
});

final salaryPeriodsProvider = FutureProvider<List<SalaryPeriod>>((ref) async {
  final result = await ref.watch(salaryRepositoryProvider).fetchPeriods();
  return result.when(ok: (p) => p, err: (f) => throw f);
});

final salaryPeriodProvider = FutureProvider.family
    .autoDispose<SalaryPeriod, String>((ref, id) async {
      final result = await ref.watch(salaryRepositoryProvider).fetchPeriod(id);
      return result.when(ok: (p) => p, err: (f) => throw f);
    });

final adjustmentsForRangeProvider = FutureProvider.family
    .autoDispose<List<SalaryAdjustment>, PeriodRange>((ref, range) async {
      final result = await ref
          .watch(salaryRepositoryProvider)
          .fetchAdjustments(start: range.start, end: range.end);
      return result.when(ok: (a) => a, err: (f) => throw f);
    });

/// Live itemized estimate for an arbitrary earning period range.
final estimateForRangeProvider = FutureProvider.family
    .autoDispose<SalaryEstimate, PeriodRange>((ref, range) async {
      final settings = await ref.watch(salarySettingsProvider.future);
      final entriesResult = await ref
          .watch(workRepositoryProvider)
          .fetchEntries(start: range.start, end: range.end);
      final entries = entriesResult.when(ok: (e) => e, err: (f) => throw f);
      final adjustments = await ref.watch(
        adjustmentsForRangeProvider(range).future,
      );
      final bounds = SalaryPeriods.boundsFor(settings, range.start);
      return SalaryEstimate.compute(
        settings,
        bounds: bounds,
        entries: entries,
        adjustments: adjustments,
      );
    });

/// Estimate for the period containing today.
final currentEstimateProvider = FutureProvider<SalaryEstimate>((ref) async {
  final bounds = await ref.watch(currentPeriodBoundsProvider.future);
  return ref.watch(
    estimateForRangeProvider((start: bounds.start, end: bounds.end)).future,
  );
});

/// Invalidate everything derived from periods or adjustments.
void invalidateSalaryData(WidgetRef ref) {
  ref
    ..invalidate(salaryPeriodsProvider)
    ..invalidate(salaryPeriodProvider)
    ..invalidate(adjustmentsForRangeProvider)
    ..invalidate(estimateForRangeProvider)
    ..invalidate(currentEstimateProvider);
}
