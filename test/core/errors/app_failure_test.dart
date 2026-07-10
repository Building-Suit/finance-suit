import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/errors/app_failure.dart';

void main() {
  group('mapSupabaseError auth', () {
    test('maps invalid email or password to invalid credentials', () {
      final failure = mapSupabaseError(
        const AuthException('Invalid email or password', statusCode: '400'),
      );

      expect(failure, isA<AuthFailure>());
      expect((failure as AuthFailure).kind, AuthFailureKind.invalidCredentials);
    });

    test('maps weak password only for actual weak-password errors', () {
      final failure = mapSupabaseError(
        const AuthException(
          'Password should be at least 8 characters',
          statusCode: '422',
          code: 'weak_password',
        ),
      );

      expect(failure, isA<AuthFailure>());
      expect((failure as AuthFailure).kind, AuthFailureKind.weakPassword);
    });
  });
}
