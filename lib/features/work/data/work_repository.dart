import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/work/domain/official_holiday.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';

class WorkRepository {
  WorkRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.work);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure(AuthFailureKind.sessionMissing);
    }
    return id;
  }

  Future<Result<List<WorkEntry>>> fetchEntries({
    required PlainDate start,
    required PlainDate end,
  }) {
    return guard(() async {
      final rows = await _client
          .from('work_entries')
          .select()
          .eq('user_id', _userId)
          .gte('work_date', start.toIso())
          .lte('work_date', end.toIso())
          .order('work_date', ascending: false)
          .order('id', ascending: false);
      return rows.map(WorkEntry.fromJson).toList();
    });
  }

  Future<Result<void>> createEntry(WorkEntryDraft draft) {
    return guard(() async {
      await _db.from('work_entries').insert({
        'user_id': _userId,
        ...draft.toJson(),
      });
    });
  }

  Future<Result<void>> updateEntry(String id, WorkEntryDraft draft) {
    return guard(() async {
      await _db.from('work_entries').update(draft.toJson()).eq('id', id);
    });
  }

  Future<Result<void>> deleteEntry(String id) {
    return guard(() async {
      await _db.from('work_entries').delete().eq('id', id);
    });
  }

  Future<Result<List<OfficialHoliday>>> fetchHolidays() {
    return guard(() async {
      final rows = await _client
          .from('official_holidays')
          .select()
          .eq('user_id', _userId)
          .order('holiday_date', ascending: false);
      return rows.map(OfficialHoliday.fromJson).toList();
    });
  }

  Future<Result<void>> createHoliday({
    required PlainDate date,
    required String name,
    String? notes,
  }) {
    return guard(() async {
      await _db.from('official_holidays').insert({
        'user_id': _userId,
        'holiday_date': date.toIso(),
        'name': name,
        'notes': notes,
      });
    });
  }

  Future<Result<void>> updateHoliday({
    required String id,
    required PlainDate date,
    required String name,
    String? notes,
  }) {
    return guard(() async {
      await _client
          .from('official_holidays')
          .update({'holiday_date': date.toIso(), 'name': name, 'notes': notes})
          .eq('id', id);
    });
  }

  Future<Result<void>> deleteHoliday(String id) {
    return guard(() async {
      await _db.from('official_holidays').delete().eq('id', id);
    });
  }
}

final workRepositoryProvider = Provider<WorkRepository>(
  (ref) => WorkRepository(ref.watch(supabaseClientProvider)),
);
