import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_adjustment.dart';
import 'package:work_tracker/features/salary/domain/salary_estimate.dart';
import 'package:work_tracker/features/salary/domain/salary_period.dart';

class SalaryRepository {
  SalaryRepository(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.salary);

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure(AuthFailureKind.sessionMissing);
    }
    return id;
  }

  Future<Result<List<SalaryPeriod>>> fetchPeriods() {
    return guard(() async {
      final rows = await _db
          .from('salary_periods')
          .select()
          .eq('user_id', _userId)
          .order('period_start', ascending: false);
      return rows.map(SalaryPeriod.fromJson).toList();
    });
  }

  Future<Result<SalaryPeriod>> fetchPeriod(String id) {
    return guard(() async {
      final row = await _db
          .from('salary_periods')
          .select()
          .eq('id', id)
          .single();
      return SalaryPeriod.fromJson(row);
    });
  }

  /// Ensures an open period row exists for [bounds] and returns it.
  /// Idempotent thanks to the (user_id, period_start) unique constraint.
  Future<Result<SalaryPeriod>> ensurePeriod(PeriodBounds bounds) {
    return guard(() async {
      await _db
          .from('salary_periods')
          .upsert(
            {
              'user_id': _userId,
              'period_start': bounds.start.toIso(),
              'period_end': bounds.end.toIso(),
              'expected_payment_date': bounds.expectedPaymentDate.toIso(),
            },
            onConflict: 'user_id,period_start',
            ignoreDuplicates: true,
          );
      final row = await _db
          .from('salary_periods')
          .select()
          .eq('user_id', _userId)
          .eq('period_start', bounds.start.toIso())
          .single();
      return SalaryPeriod.fromJson(row);
    });
  }

  Future<Result<void>> finalizePeriod(
    String id,
    Map<String, dynamic> snapshot,
  ) {
    return guard(() async {
      await _db
          .from('salary_periods')
          .update({
            'status': 'finalized',
            'snapshot': snapshot,
            'finalized_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id)
          .eq('status', 'open');
    });
  }

  /// Explicit reopen of a finalized (not paid) period.
  Future<Result<void>> reopenPeriod(String id) {
    return guard(() async {
      await _db
          .from('salary_periods')
          .update({'status': 'open', 'finalized_at': null})
          .eq('id', id)
          .eq('status', 'finalized');
    });
  }

  /// Atomic, idempotent payment recording via the database RPC: creates
  /// the salary_income transaction, marks the period paid, links both.
  Future<Result<String>> recordPayment({
    required String periodId,
    required int actualAmountMinor,
    required String destinationAccountId,
    required PlainDate receivedDate,
    String? notes,
  }) {
    return guard(() async {
      return _db.rpc<String>(
        'record_salary_payment',
        params: {
          'p_period_id': periodId,
          'p_actual_amount_minor': actualAmountMinor,
          'p_destination_account_id': destinationAccountId,
          'p_received_date': receivedDate.toIso(),
          'p_notes': notes,
        },
      );
    });
  }

  Future<Result<List<SalaryAdjustment>>> fetchAdjustments({
    required PlainDate start,
    required PlainDate end,
  }) {
    return guard(() async {
      final rows = await _db
          .from('salary_adjustments')
          .select()
          .eq('user_id', _userId)
          .gte('effective_date', start.toIso())
          .lte('effective_date', end.toIso())
          .order('effective_date', ascending: false)
          .order('id', ascending: false);
      return rows.map(SalaryAdjustment.fromJson).toList();
    });
  }

  Future<Result<void>> createAdjustment(SalaryAdjustmentDraft draft) {
    return guard(() async {
      await _db.from('salary_adjustments').insert({
        'user_id': _userId,
        ...draft.toJson(),
      });
    });
  }

  Future<Result<void>> updateAdjustment(
    String id,
    SalaryAdjustmentDraft draft,
  ) {
    return guard(() async {
      await _db.from('salary_adjustments').update(draft.toJson()).eq('id', id);
    });
  }

  Future<Result<void>> deleteAdjustment(String id) {
    return guard(() async {
      await _db.from('salary_adjustments').delete().eq('id', id);
    });
  }
}

final salaryRepositoryProvider = Provider<SalaryRepository>(
  (ref) => SalaryRepository(ref.watch(supabaseClientProvider)),
);
