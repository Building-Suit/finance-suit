import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/history/domain/history_models.dart';

class HistoryRepository {
  HistoryRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.reports);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure(AuthFailureKind.sessionMissing);
    }
    return id;
  }

  Future<Result<HistoryPage>> fetchHistory(HistoryQuery input) {
    return guard(() async {
      final query = _normalize(input);
      PostgrestFilterBuilder<PostgrestList> request = _db
          .from('history_items')
          .select()
          .eq('user_id', _userId)
          .gte('record_date', query.range.start.toIso())
          .lte('record_date', query.range.end.toIso());

      request = _applyTypeFilter(request, query.type);

      final accountId = query.accountId;
      if (accountId != null) {
        request = request.or(
          'source_account_id.eq.$accountId,destination_account_id.eq.$accountId',
        );
      }
      final categoryId = query.categoryId;
      if (categoryId != null) {
        request = request.eq('category_id', categoryId);
      }
      final counterparty = query.counterparty?.trim();
      if (counterparty != null && counterparty.isNotEmpty) {
        request = request.ilike(
          'counterparty',
          '%${_filterText(counterparty)}%',
        );
      }
      final minAmountMinor = query.minAmountMinor;
      if (minAmountMinor != null) {
        request = request.gte('amount_abs_minor', minAmountMinor);
      }
      final maxAmountMinor = query.maxAmountMinor;
      if (maxAmountMinor != null) {
        request = request.lte('amount_abs_minor', maxAmountMinor);
      }
      final keyword = query.keyword?.trim();
      if (keyword != null && keyword.isNotEmpty) {
        final term = '%${_filterText(keyword)}%';
        request = request.or(
          'title.ilike.$term,notes.ilike.$term,counterparty.ilike.$term',
        );
      }
      final salaryPeriodId = query.salaryPeriodId;
      if (salaryPeriodId != null) {
        request = request.eq('salary_period_id', salaryPeriodId);
      }

      if (query.usesDefaultKeyset) {
        final cursor = query.cursor!;
        final date = cursor.recordDate.toIso();
        final sortAt = cursor.sortAt.toUtc().toIso8601String();
        request = request.or(
          'record_date.lt.$date,'
          'and(record_date.eq.$date,sort_at.lt.$sortAt),'
          'and(record_date.eq.$date,sort_at.eq.$sortAt,id.lt.${cursor.id})',
        );
      }

      final sortedRequest = _applySort(request, query.sort);

      final rows = await sortedRequest.limit(query.limit + 1);
      final items = rows.take(query.limit).map(HistoryItem.fromJson).toList();
      return HistoryPage(items: items, hasMore: rows.length > query.limit);
    });
  }

  HistoryQuery _normalize(HistoryQuery query) {
    final limit = query.limit.clamp(10, 100);
    if (query.sort != HistorySort.recordDateDesc && query.cursor != null) {
      return query.copyWith(limit: limit, cursor: () => null);
    }
    return query.copyWith(limit: limit);
  }

  PostgrestFilterBuilder<PostgrestList> _applyTypeFilter(
    PostgrestFilterBuilder<PostgrestList> request,
    HistoryFilterType type,
  ) {
    switch (type) {
      case HistoryFilterType.all:
        return request;
      case HistoryFilterType.work:
        return request.eq('record_group', HistoryItemGroup.work.dbValue);
      case HistoryFilterType.regularWork:
        return request
            .eq('record_group', HistoryItemGroup.work.dbValue)
            .eq('record_type', WorkEntryType.regular.dbValue);
      case HistoryFilterType.overtime:
        return request
            .eq('record_group', HistoryItemGroup.work.dbValue)
            .eq('record_type', WorkEntryType.overtime.dbValue);
      case HistoryFilterType.extraDay:
        return request
            .eq('record_group', HistoryItemGroup.work.dbValue)
            .eq('record_type', WorkEntryType.extraDay.dbValue);
      case HistoryFilterType.holidayWorked:
        return request
            .eq('record_group', HistoryItemGroup.work.dbValue)
            .eq('record_type', WorkEntryType.holidayWorked.dbValue);
      case HistoryFilterType.expense:
        return request
            .eq('record_group', HistoryItemGroup.transaction.dbValue)
            .eq('record_type', TransactionKind.expense.dbValue);
      case HistoryFilterType.allowanceGiven:
        return request
            .eq('record_group', HistoryItemGroup.transaction.dbValue)
            .eq('record_type', TransactionKind.allowanceGiven.dbValue);
      case HistoryFilterType.income:
        return request
            .eq('record_group', HistoryItemGroup.transaction.dbValue)
            .inFilter('record_type', [
              TransactionKind.customIncome.dbValue,
              TransactionKind.freelanceIncome.dbValue,
              TransactionKind.salaryIncome.dbValue,
            ]);
      case HistoryFilterType.freelanceIncome:
        return request
            .eq('record_group', HistoryItemGroup.transaction.dbValue)
            .eq('record_type', TransactionKind.freelanceIncome.dbValue);
      case HistoryFilterType.salaryIncome:
        return request
            .eq('record_group', HistoryItemGroup.transaction.dbValue)
            .eq('record_type', TransactionKind.salaryIncome.dbValue);
      case HistoryFilterType.transfer:
        return request
            .eq('record_group', HistoryItemGroup.transaction.dbValue)
            .eq('record_type', TransactionKind.transfer.dbValue);
      case HistoryFilterType.salaryAdjustment:
        return request.eq(
          'record_group',
          HistoryItemGroup.salaryAdjustment.dbValue,
        );
    }
  }

  PostgrestTransformBuilder<PostgrestList> _applySort(
    PostgrestFilterBuilder<PostgrestList> request,
    HistorySort sort,
  ) {
    // Ties use the explicit display order. created_at remains an immutable
    // audit timestamp and macro-run rows may intentionally share it.
    switch (sort) {
      case HistorySort.recordDateDesc:
        return request
            .order('record_date', ascending: false)
            .order('sort_at', ascending: false)
            .order('id', ascending: false);
      case HistorySort.recordDateAsc:
        return request
            .order('record_date', ascending: true)
            // A date-direction change must not invert actions inside one
            // macro run; sort_at always represents logical display order.
            .order('sort_at', ascending: false)
            .order('id', ascending: false);
      case HistorySort.amountDesc:
        return request
            .order('amount_abs_minor', ascending: false)
            .order('record_date', ascending: false)
            .order('sort_at', ascending: false)
            .order('id', ascending: false);
      case HistorySort.amountAsc:
        return request
            .order('amount_abs_minor', ascending: true)
            .order('record_date', ascending: false)
            .order('sort_at', ascending: false)
            .order('id', ascending: false);
      case HistorySort.createdAtDesc:
        return request
            .order('created_at', ascending: false)
            .order('sort_at', ascending: false)
            .order('id', ascending: false);
    }
  }

  String _filterText(String value) {
    return value
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll(',', ' ');
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(supabaseClientProvider)),
);
