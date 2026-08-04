import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

enum DeviceAuthOutcome { authenticated, canceled, unavailable, failed }

/// Tracks whether any device-credential prompt is in flight, across every
/// controller that can open one (privacy reveals, app unlock, quick login).
///
/// Fullscreen fingerprint prompts and credential screens stop the host
/// activity on many devices, so the privacy gate must be able to tell
/// prompt-induced lifecycle churn apart from a real backgrounding.
abstract final class DeviceAuthSession {
  static int _active = 0;

  static bool get isActive => _active > 0;

  static Future<T> run<T>(Future<T> Function() action) async {
    _active += 1;
    try {
      return await action();
    } finally {
      _active -= 1;
    }
  }

  @visibleForTesting
  static void reset() => _active = 0;
}

abstract interface class DeviceAuthenticator {
  Future<bool> isSupported();

  Future<DeviceAuthOutcome> authenticate({required String reason});

  Future<void> cancel();
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isSupported() async {
    try {
      return await _authentication.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<DeviceAuthOutcome> authenticate({required String reason}) async {
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: reason,
        // Keeping this false is what enables the phone PIN, pattern,
        // password, or passcode when biometrics are unavailable.
        biometricOnly: false,
        sensitiveTransaction: true,
        // Fullscreen fingerprint UIs and the notification shade background
        // the activity mid-prompt on some devices. Persisting resumes the
        // same session instead of canceling and arming a duplicate prompt.
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? DeviceAuthOutcome.authenticated
          : DeviceAuthOutcome.canceled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          DeviceAuthOutcome.canceled,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware =>
          DeviceAuthOutcome.unavailable,
        _ => DeviceAuthOutcome.failed,
      };
    } on Object {
      return DeviceAuthOutcome.failed;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _authentication.stopAuthentication();
    } on Object {
      // Cancellation is best effort during disposal/background transitions.
    }
  }
}

final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => LocalDeviceAuthenticator(),
);

final deviceAuthAvailabilityProvider = FutureProvider<bool>((ref) async {
  return ref.watch(deviceAuthenticatorProvider).isSupported();
});
