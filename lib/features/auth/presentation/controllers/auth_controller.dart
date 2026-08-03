import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/security/biometric_login_controller.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/auth/data/auth_repository.dart';

/// High-level authentication phase used by router redirects.
enum AuthPhase {
  /// Session restoration still in progress — show splash, never a
  /// protected screen.
  restoring,
  signedOut,
  signedIn,

  /// A password-recovery deep link established a temporary session; the
  /// user must set a new password before entering the app.
  passwordRecovery,
}

class AuthStateData {
  const AuthStateData({required this.phase, this.userId});
  final AuthPhase phase;
  final String? userId;
}

class AuthStateNotifier extends Notifier<AuthStateData> {
  StreamSubscription<AuthState>? _sub;

  @override
  AuthStateData build() {
    final client = ref.watch(supabaseClientProvider);

    _sub?.cancel();
    _sub = client.auth.onAuthStateChange.listen(
      (event) {
        switch (event.event) {
          case AuthChangeEvent.initialSession:
            final session = event.session;
            state = session == null
                ? const AuthStateData(phase: AuthPhase.signedOut)
                : AuthStateData(
                    phase: AuthPhase.signedIn,
                    userId: session.user.id,
                  );
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.tokenRefreshed:
          case AuthChangeEvent.userUpdated:
            // Do not downgrade an active recovery phase on token refresh.
            if (state.phase == AuthPhase.passwordRecovery &&
                event.event == AuthChangeEvent.tokenRefreshed) {
              return;
            }
            final session = event.session;
            if (session != null) {
              state = AuthStateData(
                phase: AuthPhase.signedIn,
                userId: session.user.id,
              );
            }
          case AuthChangeEvent.passwordRecovery:
            state = AuthStateData(
              phase: AuthPhase.passwordRecovery,
              userId: event.session?.user.id,
            );
          case AuthChangeEvent.signedOut:
            state = const AuthStateData(phase: AuthPhase.signedOut);
          // ignore: deprecated_member_use
          case AuthChangeEvent.userDeleted:
            state = const AuthStateData(phase: AuthPhase.signedOut);
          case AuthChangeEvent.mfaChallengeVerified:
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // A transient refresh/network error must not become an unhandled zone
        // exception. Supabase will retry while the last known auth phase stays.
      },
    );
    ref.onDispose(() => _sub?.cancel());

    // Synchronous best-effort initial value; initialSession event follows.
    final session = client.auth.currentSession;
    if (session != null) {
      return AuthStateData(phase: AuthPhase.signedIn, userId: session.user.id);
    }
    return const AuthStateData(phase: AuthPhase.restoring);
  }

  /// Called after the user sets a new password in the recovery flow.
  void completePasswordRecovery() {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    state = userId == null
        ? const AuthStateData(phase: AuthPhase.signedOut)
        : AuthStateData(phase: AuthPhase.signedIn, userId: userId);
  }
}

final authStateProvider = NotifierProvider<AuthStateNotifier, AuthStateData>(
  AuthStateNotifier.new,
);

/// Async action state for auth forms (login, register, reset...).
class AuthActionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<AppFailure?> _run(Future<AppFailure?> Function() action) async {
    state = const AsyncValue.loading();
    final failure = await action();
    if (failure != null) {
      state = AsyncValue.error(failure, StackTrace.current);
      return failure;
    }
    state = const AsyncValue.data(null);
    return null;
  }

  Future<AppFailure?> signIn(String email, String password) => _run(
    () async =>
        (await _repo.signIn(email: email, password: password)).failureOrNull,
  );

  Future<AppFailure?> register(
    String email,
    String password,
    String displayName,
  ) => _run(
    () async => (await _repo.register(
      email: email,
      password: password,
      displayName: displayName,
    )).failureOrNull,
  );

  Future<AppFailure?> resendConfirmation(String email) => _run(
    () async => (await _repo.resendConfirmation(email: email)).failureOrNull,
  );

  Future<AppFailure?> sendPasswordReset(String email) => _run(
    () async => (await _repo.sendPasswordReset(email: email)).failureOrNull,
  );

  Future<AppFailure?> updatePassword(String newPassword) => _run(() async {
    final result = await _repo.updatePassword(newPassword: newPassword);
    if (result.failureOrNull == null) {
      await ref.read(biometricLoginProvider.notifier).clear();
    }
    return result.failureOrNull;
  });

  Future<AppFailure?> updateEmail(String newEmail) => _run(() async {
    final result = await _repo.updateEmail(newEmail: newEmail);
    if (result.failureOrNull == null) {
      await ref.read(biometricLoginProvider.notifier).clear();
    }
    return result.failureOrNull;
  });

  Future<AppFailure?> signOut() =>
      _run(() async => (await _repo.signOut()).failureOrNull);

  Future<AppFailure?> deleteAccount(String password) => _run(() async {
    final result = await _repo.deleteAccount(password: password);
    if (result.failureOrNull == null) {
      await ref.read(biometricLoginProvider.notifier).clear();
    }
    return result.failureOrNull;
  });
}

final authActionProvider =
    NotifierProvider<AuthActionController, AsyncValue<void>>(
      AuthActionController.new,
    );
