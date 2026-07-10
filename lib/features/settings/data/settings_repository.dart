import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/domain/user_profile.dart';

class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure(AuthFailureKind.sessionMissing);
    }
    return id;
  }

  Future<Result<UserProfile>> fetchProfile() {
    return guard(() async {
      final row = await _client
          .from('profiles')
          .select('id, display_name')
          .eq('id', _userId)
          .single();
      return UserProfile.fromJson(row);
    });
  }

  Future<Result<void>> updateDisplayName(String displayName) {
    return guard(() async {
      await _client
          .from('profiles')
          .update({'display_name': displayName})
          .eq('id', _userId);
    });
  }

  Future<Result<UserPreferences>> fetchPreferences() {
    return guard(() async {
      final row = await _client
          .from('user_preferences')
          .select()
          .eq('user_id', _userId)
          .single();
      return UserPreferences.fromJson(row);
    });
  }

  Future<Result<void>> updatePreferences({
    String? locale,
    int? weekStartsOn,
    List<int>? weekendDays,
    int? defaultHistoryDays,
  }) {
    return guard(() async {
      final patch = <String, dynamic>{
        'locale': ?locale,
        'week_starts_on': ?weekStartsOn,
        'weekend_days': ?weekendDays,
        'default_history_days': ?defaultHistoryDays,
      };
      if (patch.isEmpty) return;
      await _client
          .from('user_preferences')
          .update(patch)
          .eq('user_id', _userId);
    });
  }

  Future<Result<SalarySettings>> fetchSalarySettings() {
    return guard(() async {
      final row = await _client
          .from('salary_settings')
          .select()
          .eq('user_id', _userId)
          .single();
      return SalarySettings.fromJson(row);
    });
  }

  Future<Result<void>> updateSalarySettings(SalarySettings settings) {
    return guard(() async {
      await _client
          .from('salary_settings')
          .update(settings.toUpdateJson())
          .eq('user_id', _userId);
    });
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(supabaseClientProvider)),
);
