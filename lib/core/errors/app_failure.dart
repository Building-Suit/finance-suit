import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed application failures. UI layers map these to localized messages;
/// raw SQL / stack traces are never shown to end users.
sealed class AppFailure implements Exception {
  const AppFailure({this.debugDetails});

  /// Developer-facing context. Logged in debug builds only.
  final String? debugDetails;

  @override
  String toString() => '$runtimeType(${debugDetails ?? ''})';
}

class AuthFailure extends AppFailure {
  const AuthFailure(this.kind, {super.debugDetails});
  final AuthFailureKind kind;
}

enum AuthFailureKind {
  invalidCredentials,
  emailNotConfirmed,
  duplicateEmail,
  weakPassword,
  expiredLink,
  usedLink,
  rateLimited,
  sessionMissing,
  unknown,
}

class AuthorizationFailure extends AppFailure {
  const AuthorizationFailure({super.debugDetails});
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(this.message, {super.debugDetails});
  final String message;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure({super.debugDetails});
}

class TimeoutFailure extends AppFailure {
  const TimeoutFailure({super.debugDetails});
}

class ConstraintFailure extends AppFailure {
  const ConstraintFailure(this.constraintName, {super.debugDetails});
  final String? constraintName;
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure({super.debugDetails});
}

class RealtimeFailure extends AppFailure {
  const RealtimeFailure({super.debugDetails});
}

class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure({super.debugDetails});
}

class UnknownFailure extends AppFailure {
  const UnknownFailure({super.debugDetails});
}

/// Maps Supabase / PostgREST exceptions into typed [AppFailure]s.
AppFailure mapSupabaseError(Object error) {
  if (error is AppFailure) return error;
  // Network-level auth failures (no connectivity, DNS, refused sockets)
  // subclass AuthException but are not authentication problems; surface
  // them as connectivity issues instead of a misleading auth error.
  if (error is AuthRetryableFetchException) {
    return NetworkFailure(debugDetails: error.message);
  }
  if (error is AuthException) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();
    if (code == 'invalid_credentials' ||
        message.contains('invalid login') ||
        message.contains('invalid credentials') ||
        message.contains('invalid email or password')) {
      return AuthFailure(
        AuthFailureKind.invalidCredentials,
        debugDetails: error.message,
      );
    }
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return AuthFailure(
        AuthFailureKind.emailNotConfirmed,
        debugDetails: error.message,
      );
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return AuthFailure(
        AuthFailureKind.duplicateEmail,
        debugDetails: error.message,
      );
    }
    if (code == 'weak_password' ||
        message.contains('weak password') ||
        message.contains('password should be') ||
        message.contains('password must')) {
      return AuthFailure(
        AuthFailureKind.weakPassword,
        debugDetails: error.message,
      );
    }
    if (code == 'otp_expired' ||
        message.contains('expired') ||
        message.contains('invalid or has expired')) {
      return AuthFailure(
        AuthFailureKind.expiredLink,
        debugDetails: error.message,
      );
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        error.statusCode == '429') {
      return AuthFailure(
        AuthFailureKind.rateLimited,
        debugDetails: error.message,
      );
    }
    if (code == 'session_not_found' || message.contains('session')) {
      return AuthFailure(
        AuthFailureKind.sessionMissing,
        debugDetails: error.message,
      );
    }
    return AuthFailure(AuthFailureKind.unknown, debugDetails: error.message);
  }
  if (error is PostgrestException) {
    final code = error.code ?? '';
    final details = [
      'code=$code',
      'message=${error.message}',
      if (error.details != null) 'details=${error.details}',
      if (error.hint != null) 'hint=${error.hint}',
    ].join('; ');
    // 23xxx: integrity constraint violations.
    if (code.startsWith('23')) {
      return ConstraintFailure(code, debugDetails: details);
    }
    // RLS denial surfaces as 42501 (insufficient privilege) or empty result.
    if (code == '42501' || code == 'PGRST301') {
      return AuthorizationFailure(debugDetails: details);
    }
    if (code == 'PGRST116') {
      return NotFoundFailure(debugDetails: details);
    }
    if (code == 'PGRST106' || code == 'PGRST202' || code == 'PGRST205') {
      return ConfigurationFailure(debugDetails: details);
    }
    // P0001: raised exceptions from our own database functions.
    if (code == 'P0001') {
      return ValidationFailure(error.message, debugDetails: details);
    }
    return UnknownFailure(debugDetails: details);
  }
  if (error is FunctionException) {
    if (error.status == 401 || error.status == 403) {
      return AuthorizationFailure(debugDetails: error.toString());
    }
    if (error.status == 400) {
      return ValidationFailure(
        'account_deletion_failed',
        debugDetails: error.toString(),
      );
    }
    return UnknownFailure(debugDetails: error.toString());
  }
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Connection refused') ||
      text.contains('Failed host lookup') ||
      text.contains('ClientException')) {
    return NetworkFailure(debugDetails: text);
  }
  if (text.contains('TimeoutException')) {
    return TimeoutFailure(debugDetails: text);
  }
  return UnknownFailure(debugDetails: text);
}
