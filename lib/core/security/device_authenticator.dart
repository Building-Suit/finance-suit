import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

enum DeviceAuthOutcome { authenticated, canceled, unavailable, failed }

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
        // A system surface such as the notification shade can temporarily
        // interrupt authentication. Returning a cancellation keeps that
        // interruption from silently starting a second prompt on resume.
        persistAcrossBackgrounding: false,
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
