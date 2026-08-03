import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/security/biometric_login_controller.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';

class _FakeDeviceAuthenticator implements DeviceAuthenticator {
  DeviceAuthOutcome outcome = DeviceAuthOutcome.authenticated;
  var authenticationCount = 0;

  @override
  Future<DeviceAuthOutcome> authenticate({required String reason}) async {
    authenticationCount++;
    return outcome;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<bool> isSupported() async => true;
}

class _MemoryCredentialStore implements BiometricCredentialStore {
  BiometricCredentials? credentials;

  @override
  Future<void> clear() async => credentials = null;

  @override
  Future<BiometricCredentials?> read() async => credentials;

  @override
  Future<void> write(BiometricCredentials value) async => credentials = value;
}

class _FakeSessionManager implements BiometricSessionManager {
  @override
  String? currentEmail = 'person@example.com';

  String? verifiedPassword;
  BiometricCredentials? signedInCredentials;
  Exception? signInError;

  @override
  Future<void> signIn(BiometricCredentials credentials) async {
    signedInCredentials = credentials;
    final error = signInError;
    if (error != null) throw error;
  }

  @override
  Future<void> verifyPassword(String password) async =>
      verifiedPassword = password;
}

class _RejectingPasswordSessionManager extends _FakeSessionManager {
  @override
  Future<void> verifyPassword(String password) async {
    throw const AuthException('Invalid login credentials');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'quick login is opt-in, password-verified, and device-authenticated',
    () async {
      final authenticator = _FakeDeviceAuthenticator();
      final store = _MemoryCredentialStore();
      final sessions = _FakeSessionManager();
      final container = ProviderContainer(
        overrides: [
          deviceAuthenticatorProvider.overrideWithValue(authenticator),
          biometricCredentialStoreProvider.overrideWithValue(store),
          biometricSessionManagerProvider.overrideWithValue(sessions),
        ],
      );
      addTearDown(container.dispose);

      expect(
        (await container.read(biometricLoginProvider.future)).canSignIn,
        isFalse,
      );
      final controller = container.read(biometricLoginProvider.notifier);

      expect(
        await controller.enable(
          reason: 'Enable secure login',
          password: 'correct-password',
        ),
        BiometricLoginOutcome.authenticated,
      );
      expect(sessions.verifiedPassword, 'correct-password');
      expect(store.credentials?.email, 'person@example.com');
      expect(store.credentials?.password, 'correct-password');
      expect(
        container.read(biometricLoginProvider).requireValue.canSignIn,
        true,
      );

      expect(
        await controller.signIn(reason: 'Login securely'),
        BiometricLoginOutcome.authenticated,
      );
      expect(sessions.signedInCredentials?.email, 'person@example.com');
      expect(sessions.signedInCredentials?.password, 'correct-password');
      expect(authenticator.authenticationCount, 2);
    },
  );

  test('an invalid saved login disables quick login safely', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'biometric_login_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
    final store = _MemoryCredentialStore()
      ..credentials = const BiometricCredentials(
        email: 'person@example.com',
        password: 'old-password',
      );
    final sessions = _FakeSessionManager()
      ..signInError = const AuthException('Invalid login credentials');
    final container = ProviderContainer(
      overrides: [
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
        biometricCredentialStoreProvider.overrideWithValue(store),
        biometricSessionManagerProvider.overrideWithValue(sessions),
      ],
    );
    addTearDown(container.dispose);

    await container.read(biometricLoginProvider.future);
    expect(
      await container
          .read(biometricLoginProvider.notifier)
          .signIn(reason: 'Login securely'),
      BiometricLoginOutcome.sessionExpired,
    );
    expect(store.credentials, isNull);
    expect(
      container.read(biometricLoginProvider).requireValue.canSignIn,
      isFalse,
    );
  });

  test('an incorrect password cannot enable quick login', () async {
    final authenticator = _FakeDeviceAuthenticator();
    final store = _MemoryCredentialStore();
    final sessions = _RejectingPasswordSessionManager();
    final container = ProviderContainer(
      overrides: [
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
        biometricCredentialStoreProvider.overrideWithValue(store),
        biometricSessionManagerProvider.overrideWithValue(sessions),
      ],
    );
    addTearDown(container.dispose);
    await container.read(biometricLoginProvider.future);

    expect(
      await container
          .read(biometricLoginProvider.notifier)
          .enable(reason: 'Enable secure login', password: 'wrong'),
      BiometricLoginOutcome.invalidCredentials,
    );
    expect(store.credentials, isNull);
  });
}
