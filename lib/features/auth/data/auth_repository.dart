import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/app/configuration/env.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

/// Wraps Supabase Auth. Widgets and controllers never call the client
/// directly; failures are mapped to typed AppFailure values.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  Future<Result<void>> register({
    required String email,
    required String password,
    required String displayName,
  }) {
    return guard(() async {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
        emailRedirectTo: Env.authCallbackUrl,
      );
    });
  }

  Future<Result<void>> resendConfirmation({required String email}) {
    return guard(() async {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: Env.authCallbackUrl,
      );
    });
  }

  Future<Result<void>> signIn({
    required String email,
    required String password,
  }) {
    return guard(() async {
      await _client.auth.signInWithPassword(email: email, password: password);
    });
  }

  Future<Result<void>> signOut() {
    return guard(() => _client.auth.signOut());
  }

  /// Permanently deletes the signed-in user's Finance Suit profile and product
  /// data after confirming the password. The shared Building Suit Auth
  /// identity and legacy portal data remain available to the user.
  Future<Result<void>> deleteAccount({required String password}) {
    return guard(() async {
      final user = _client.auth.currentUser;
      final email = user?.email;
      if (user == null || email == null || email.isEmpty) {
        throw const AuthFailure(AuthFailureKind.sessionMissing);
      }

      // Refresh proof of account ownership immediately before the destructive
      // request. Finance Suit currently supports email/password accounts only.
      await _client.auth.signInWithPassword(email: email, password: password);

      await _client.functions.invoke(
        'delete-account',
        body: const {'confirmation': 'DELETE'},
      );

      // Finance Suit deletion preserves the shared Auth identity, but this app
      // still signs out locally so the deleted portal is not left open.
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Product deletion already succeeded. Local session cleanup is best
        // effort and must not misreport the permanent data deletion as failed.
      }

      // Remove report filters, locale, and theme values stored on this device.
      // No user-entered finance records are stored in SharedPreferences.
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.clear();
      } catch (_) {
        // Server deletion already succeeded. A local storage failure must not
        // misreport the permanent account deletion as failed.
      }
    });
  }

  Future<Result<void>> sendPasswordReset({required String email}) {
    return guard(() async {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: Env.authCallbackUrl,
      );
    });
  }

  /// Used both for the recovery flow (after the deep link establishes a
  /// recovery session) and for changing the password while signed in.
  Future<Result<void>> updatePassword({required String newPassword}) {
    return guard(() async {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    });
  }

  Future<Result<void>> updateEmail({required String newEmail}) {
    return guard(() async {
      await _client.auth.updateUser(
        UserAttributes(email: newEmail),
        emailRedirectTo: Env.authCallbackUrl,
      );
    });
  }

  /// Handles a `worktracker://auth-callback` deep link. Supabase encodes
  /// the session either in a `code` query parameter (PKCE) or in the URL
  /// fragment (implicit). getSessionFromUrl handles both.
  Future<Result<Session>> recoverSessionFromUrl(Uri uri) {
    return guard(() async {
      final response = await _client.auth.getSessionFromUrl(uri);
      return response.session;
    });
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
