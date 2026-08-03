import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';

const _biometricLoginEnabledKey = 'biometric_login_enabled';
const _biometricEmailKey = 'finance_suit_biometric_email';
const _biometricPasswordKey = 'finance_suit_biometric_password';

enum BiometricLoginOutcome {
  authenticated,
  canceled,
  unavailable,
  invalidCredentials,
  sessionExpired,
  failed,
}

class BiometricLoginState {
  const BiometricLoginState({
    required this.enabled,
    required this.hasCredential,
    this.authenticating = false,
  });

  final bool enabled;
  final bool hasCredential;
  final bool authenticating;

  bool get canSignIn => enabled && hasCredential;

  BiometricLoginState copyWith({
    bool? enabled,
    bool? hasCredential,
    bool? authenticating,
  }) => BiometricLoginState(
    enabled: enabled ?? this.enabled,
    hasCredential: hasCredential ?? this.hasCredential,
    authenticating: authenticating ?? this.authenticating,
  );
}

class BiometricCredentials {
  const BiometricCredentials({required this.email, required this.password});

  final String email;
  final String password;
}

abstract interface class BiometricCredentialStore {
  Future<BiometricCredentials?> read();

  Future<void> write(BiometricCredentials credentials);

  Future<void> clear();
}

class SecureBiometricCredentialStore implements BiometricCredentialStore {
  SecureBiometricCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'finance_suit_biometric_login',
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<BiometricCredentials?> read() async {
    final values = await Future.wait([
      _storage.read(key: _biometricEmailKey),
      _storage.read(key: _biometricPasswordKey),
    ]);
    final email = values[0];
    final password = values[1];
    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }
    return BiometricCredentials(email: email, password: password);
  }

  @override
  Future<void> write(BiometricCredentials credentials) async {
    await _storage.write(key: _biometricEmailKey, value: credentials.email);
    try {
      await _storage.write(
        key: _biometricPasswordKey,
        value: credentials.password,
      );
    } on Object {
      await clear();
      rethrow;
    }
  }

  @override
  Future<void> clear() => Future.wait([
    _storage.delete(key: _biometricEmailKey),
    _storage.delete(key: _biometricPasswordKey),
  ]);
}

final biometricCredentialStoreProvider = Provider<BiometricCredentialStore>(
  (ref) => SecureBiometricCredentialStore(),
);

abstract interface class BiometricSessionManager {
  String? get currentEmail;

  Future<void> verifyPassword(String password);

  Future<void> signIn(BiometricCredentials credentials);
}

class SupabaseBiometricSessionManager implements BiometricSessionManager {
  SupabaseBiometricSessionManager(this._client);

  final SupabaseClient _client;

  @override
  String? get currentEmail => _client.auth.currentUser?.email;

  @override
  Future<void> verifyPassword(String password) async {
    final email = currentEmail;
    if (email == null || email.isEmpty) throw AuthSessionMissingException();
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signIn(BiometricCredentials credentials) =>
      _client.auth.signInWithPassword(
        email: credentials.email,
        password: credentials.password,
      );
}

final biometricSessionManagerProvider = Provider<BiometricSessionManager>(
  (ref) => SupabaseBiometricSessionManager(ref.watch(supabaseClientProvider)),
);

class BiometricLoginController extends AsyncNotifier<BiometricLoginState> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  BiometricCredentialStore get _store =>
      ref.read(biometricCredentialStoreProvider);

  @override
  Future<BiometricLoginState> build() async {
    final enabled =
        await _preferences.getBool(_biometricLoginEnabledKey) ?? false;
    BiometricCredentials? credentials;
    try {
      credentials = await _store.read();
    } on Object {
      await _preferences.setBool(_biometricLoginEnabledKey, false);
      return const BiometricLoginState(enabled: false, hasCredential: false);
    }
    if (enabled && credentials == null) {
      await _preferences.setBool(_biometricLoginEnabledKey, false);
      return const BiometricLoginState(enabled: false, hasCredential: false);
    }
    return BiometricLoginState(
      enabled: enabled,
      hasCredential: credentials != null,
    );
  }

  /// Enables quick login only after both device-owner authentication and a
  /// fresh Finance Suit password check. The credentials are encrypted by the
  /// platform keystore/keychain and never replace ordinary password login.
  Future<BiometricLoginOutcome> enable({
    required String reason,
    required String password,
  }) async {
    final deviceOutcome = await _authenticateDevice(reason);
    final mapped = _mapDeviceOutcome(deviceOutcome);
    if (mapped != BiometricLoginOutcome.authenticated) return mapped;

    final sessions = ref.read(biometricSessionManagerProvider);
    final email = sessions.currentEmail;
    if (email == null || email.isEmpty) return BiometricLoginOutcome.failed;
    try {
      await sessions.verifyPassword(password);
      await _store.write(
        BiometricCredentials(email: email, password: password),
      );
      await _preferences.setBool(_biometricLoginEnabledKey, true);
      _update(
        (current) => current.copyWith(enabled: true, hasCredential: true),
      );
      return BiometricLoginOutcome.authenticated;
    } on AuthException {
      return BiometricLoginOutcome.invalidCredentials;
    } on Object {
      return BiometricLoginOutcome.failed;
    }
  }

  Future<DeviceAuthOutcome> disable({required String reason}) async {
    final outcome = await _authenticateDevice(reason);
    if (outcome != DeviceAuthOutcome.authenticated) return outcome;
    await clear();
    return DeviceAuthOutcome.authenticated;
  }

  Future<BiometricLoginOutcome> signIn({required String reason}) async {
    final current = state.value;
    if (current == null || !current.canSignIn || current.authenticating) {
      return BiometricLoginOutcome.failed;
    }

    final deviceOutcome = await _authenticateDevice(reason);
    final mapped = _mapDeviceOutcome(deviceOutcome);
    if (mapped != BiometricLoginOutcome.authenticated) return mapped;

    _update((current) => current.copyWith(authenticating: true));
    try {
      final credentials = await _store.read();
      if (credentials == null) {
        await clear();
        return BiometricLoginOutcome.sessionExpired;
      }
      await ref.read(biometricSessionManagerProvider).signIn(credentials);
      return BiometricLoginOutcome.authenticated;
    } on AuthException {
      await clear();
      return BiometricLoginOutcome.sessionExpired;
    } on Object {
      return BiometricLoginOutcome.failed;
    } finally {
      _update((current) => current.copyWith(authenticating: false));
    }
  }

  Future<void> clear() async {
    try {
      await _store.clear();
    } on Object {
      // The preference remains the source of truth, so a platform storage
      // cleanup failure can never leave quick login enabled in the UI.
    }
    await _preferences.setBool(_biometricLoginEnabledKey, false);
    _update(
      (current) => current.copyWith(
        enabled: false,
        hasCredential: false,
        authenticating: false,
      ),
    );
  }

  Future<DeviceAuthOutcome> _authenticateDevice(String reason) async {
    final current = state.value;
    if (current?.authenticating == true) return DeviceAuthOutcome.canceled;
    _update((current) => current.copyWith(authenticating: true));
    final authenticator = ref.read(deviceAuthenticatorProvider);
    final supported = await authenticator.isSupported();
    final outcome = supported
        ? await authenticator.authenticate(reason: reason)
        : DeviceAuthOutcome.unavailable;
    _update((current) => current.copyWith(authenticating: false));
    return outcome;
  }

  BiometricLoginOutcome _mapDeviceOutcome(DeviceAuthOutcome outcome) =>
      switch (outcome) {
        DeviceAuthOutcome.authenticated => BiometricLoginOutcome.authenticated,
        DeviceAuthOutcome.canceled => BiometricLoginOutcome.canceled,
        DeviceAuthOutcome.unavailable => BiometricLoginOutcome.unavailable,
        DeviceAuthOutcome.failed => BiometricLoginOutcome.failed,
      };

  void _update(BiometricLoginState Function(BiometricLoginState) update) {
    final current = state.value;
    if (current != null) state = AsyncData(update(current));
  }
}

final biometricLoginProvider =
    AsyncNotifierProvider<BiometricLoginController, BiometricLoginState>(
      BiometricLoginController.new,
    );
