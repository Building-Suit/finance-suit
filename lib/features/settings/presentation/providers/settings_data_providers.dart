import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/salary/domain/salary_settings.dart';
import 'package:work_tracker/features/settings/data/settings_repository.dart';
import 'package:work_tracker/features/settings/domain/user_profile.dart';

/// Throwing the AppFailure lets AsyncView render the localized error.
final profileProvider = FutureProvider<UserProfile>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(settingsRepositoryProvider).fetchProfile();
  return result.when(ok: (p) => p, err: (f) => throw f);
});

final preferencesProvider = FutureProvider<UserPreferences>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(settingsRepositoryProvider).fetchPreferences();
  return result.when(ok: (p) => p, err: (f) => throw f);
});

final salarySettingsProvider = FutureProvider<SalarySettings>((ref) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(settingsRepositoryProvider)
      .fetchSalarySettings();
  return result.when(ok: (s) => s, err: (f) => throw f);
});
