import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';

const _moneyPrivacyEnabledKey = 'device_privacy_money_enabled';
const _appLockEnabledKey = 'device_privacy_app_lock_enabled';

class DevicePrivacyState {
  const DevicePrivacyState({
    required this.moneyPrivacyEnabled,
    required this.appLockEnabled,
    required this.moneyRevealed,
    required this.appUnlocked,
    this.authenticating = false,
  });

  final bool moneyPrivacyEnabled;
  final bool appLockEnabled;
  final bool moneyRevealed;
  final bool appUnlocked;
  final bool authenticating;

  DevicePrivacyState copyWith({
    bool? moneyPrivacyEnabled,
    bool? appLockEnabled,
    bool? moneyRevealed,
    bool? appUnlocked,
    bool? authenticating,
  }) => DevicePrivacyState(
    moneyPrivacyEnabled: moneyPrivacyEnabled ?? this.moneyPrivacyEnabled,
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    moneyRevealed: moneyRevealed ?? this.moneyRevealed,
    appUnlocked: appUnlocked ?? this.appUnlocked,
    authenticating: authenticating ?? this.authenticating,
  );
}

class DevicePrivacyController extends AsyncNotifier<DevicePrivacyState> {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<DevicePrivacyState> build() async {
    final moneyPrivacyEnabled =
        await _preferences.getBool(_moneyPrivacyEnabledKey) ?? false;
    final appLockEnabled =
        await _preferences.getBool(_appLockEnabledKey) ?? false;
    return DevicePrivacyState(
      moneyPrivacyEnabled: moneyPrivacyEnabled,
      appLockEnabled: appLockEnabled,
      moneyRevealed: !moneyPrivacyEnabled,
      appUnlocked: !appLockEnabled,
    );
  }

  Future<DeviceAuthOutcome> enableMoneyPrivacy({required String reason}) async {
    final outcome = await _authenticate(reason);
    if (outcome != DeviceAuthOutcome.authenticated) return outcome;
    await _preferences.setBool(_moneyPrivacyEnabledKey, true);
    _update(
      (current) =>
          current.copyWith(moneyPrivacyEnabled: true, moneyRevealed: false),
    );
    return outcome;
  }

  Future<DeviceAuthOutcome> disableMoneyPrivacy({
    required String reason,
  }) async {
    final outcome = await _authenticate(reason);
    if (outcome != DeviceAuthOutcome.authenticated) return outcome;
    await _preferences.setBool(_moneyPrivacyEnabledKey, false);
    _update(
      (current) =>
          current.copyWith(moneyPrivacyEnabled: false, moneyRevealed: true),
    );
    return outcome;
  }

  Future<DeviceAuthOutcome> enableAppLock({required String reason}) async {
    final outcome = await _authenticate(reason);
    if (outcome != DeviceAuthOutcome.authenticated) return outcome;
    await _preferences.setBool(_appLockEnabledKey, true);
    _update(
      (current) => current.copyWith(appLockEnabled: true, appUnlocked: true),
    );
    return outcome;
  }

  Future<DeviceAuthOutcome> disableAppLock({required String reason}) async {
    final outcome = await _authenticate(reason);
    if (outcome != DeviceAuthOutcome.authenticated) return outcome;
    await _preferences.setBool(_appLockEnabledKey, false);
    _update(
      (current) => current.copyWith(appLockEnabled: false, appUnlocked: true),
    );
    return outcome;
  }

  Future<DeviceAuthOutcome> revealMoney({required String reason}) async {
    final current = state.value;
    if (current == null ||
        !current.moneyPrivacyEnabled ||
        current.moneyRevealed) {
      return DeviceAuthOutcome.authenticated;
    }
    final outcome = await _authenticate(reason);
    if (outcome == DeviceAuthOutcome.authenticated) {
      _update((current) => current.copyWith(moneyRevealed: true));
    }
    return outcome;
  }

  Future<DeviceAuthOutcome> unlockApp({required String reason}) async {
    final current = state.value;
    if (current == null || !current.appLockEnabled) {
      _update((current) => current.copyWith(appUnlocked: true));
      return DeviceAuthOutcome.authenticated;
    }
    final outcome = await _authenticate(reason);
    if (outcome == DeviceAuthOutcome.authenticated) {
      _update((current) => current.copyWith(appUnlocked: true));
    }
    return outcome;
  }

  /// A successful Finance Suit password login is also a valid unlock for the
  /// current foreground session. The next background/resume still uses the
  /// configured device lock.
  void markPasswordAuthenticated() {
    _update((current) => current.copyWith(appUnlocked: true));
  }

  void lockForBackground() {
    _update(
      (current) => current.copyWith(
        moneyRevealed: !current.moneyPrivacyEnabled,
        appUnlocked: !current.appLockEnabled,
      ),
    );
  }

  void signedOut() {
    _update(
      (current) => current.copyWith(
        moneyRevealed: !current.moneyPrivacyEnabled,
        appUnlocked: !current.appLockEnabled,
      ),
    );
  }

  Future<DeviceAuthOutcome> _authenticate(String reason) async {
    final current = state.value;
    if (current == null || current.authenticating) {
      return DeviceAuthOutcome.canceled;
    }
    _update((current) => current.copyWith(authenticating: true));
    final authenticator = ref.read(deviceAuthenticatorProvider);
    final supported = await authenticator.isSupported();
    final outcome = supported
        ? await authenticator.authenticate(reason: reason)
        : DeviceAuthOutcome.unavailable;
    _update((current) => current.copyWith(authenticating: false));
    return outcome;
  }

  void _update(DevicePrivacyState Function(DevicePrivacyState) update) {
    final current = state.value;
    if (current != null) state = AsyncData(update(current));
  }
}

final devicePrivacyProvider =
    AsyncNotifierProvider<DevicePrivacyController, DevicePrivacyState>(
      DevicePrivacyController.new,
    );

final moneyShouldBeHiddenProvider = Provider<bool>((ref) {
  final privacy = ref.watch(devicePrivacyProvider).value;
  return privacy?.moneyPrivacyEnabled == true && privacy?.moneyRevealed != true;
});
