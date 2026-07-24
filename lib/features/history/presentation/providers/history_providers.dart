import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/history/data/history_repository.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';

final historyPageProvider = FutureProvider.family<HistoryPage, HistoryQuery>((
  ref,
  query,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(historyRepositoryProvider).fetchHistory(query);
  return result.when(ok: (page) => page, err: (failure) => throw failure);
});

void invalidateHistoryData(WidgetRef ref) {
  ref.invalidate(historyPageProvider);
}
