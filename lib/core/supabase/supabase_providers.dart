import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class AppSchemas {
  static const core = 'app_core';
  static const finance = 'app_finance';
  static const work = 'app_work';
  static const salary = 'app_salary';
  static const reports = 'app_reports';
  static const commercial = 'app_commercial';
}

/// Single access point for the Supabase client. Repositories depend on this
/// provider; widgets never touch the client directly.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Emits on every auth state change (sign in, sign out, token refresh,
/// password recovery deep link).
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Current user id, or null when signed out.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser?.id;
});
