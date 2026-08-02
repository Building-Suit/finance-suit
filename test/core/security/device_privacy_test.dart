import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/core/widgets/device_privacy_gate.dart';
import 'package:work_tracker/core/widgets/protected_money.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _FakeDeviceAuthenticator implements DeviceAuthenticator {
  _FakeDeviceAuthenticator({
    this.supported = true,
    this.outcome = DeviceAuthOutcome.authenticated,
  });

  bool supported;
  DeviceAuthOutcome outcome;
  int authenticationCount = 0;

  @override
  Future<DeviceAuthOutcome> authenticate({required String reason}) async {
    authenticationCount++;
    return outcome;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<bool> isSupported() async => supported;
}

class _SignedInAuthNotifier extends AuthStateNotifier {
  @override
  AuthStateData build() =>
      const AuthStateData(phase: AuthPhase.signedIn, userId: 'user-1');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'privacy settings lock again when the app leaves the foreground',
    () async {
      final authenticator = _FakeDeviceAuthenticator();
      final container = ProviderContainer(
        overrides: [
          deviceAuthenticatorProvider.overrideWithValue(authenticator),
        ],
      );
      addTearDown(container.dispose);

      await container.read(devicePrivacyProvider.future);
      final controller = container.read(devicePrivacyProvider.notifier);

      expect(
        await controller.enableMoneyPrivacy(reason: 'Protect money'),
        DeviceAuthOutcome.authenticated,
      );
      expect(
        await controller.enableAppLock(reason: 'Lock app'),
        DeviceAuthOutcome.authenticated,
      );

      controller.lockForBackground();
      var state = container.read(devicePrivacyProvider).requireValue;
      expect(state.moneyRevealed, isFalse);
      expect(state.appUnlocked, isFalse);

      expect(
        await controller.revealMoney(reason: 'Reveal money'),
        DeviceAuthOutcome.authenticated,
      );
      expect(
        await controller.unlockApp(reason: 'Unlock app'),
        DeviceAuthOutcome.authenticated,
      );
      state = container.read(devicePrivacyProvider).requireValue;
      expect(state.moneyRevealed, isTrue);
      expect(state.appUnlocked, isTrue);
      expect(authenticator.authenticationCount, 4);

      authenticator.outcome = DeviceAuthOutcome.canceled;
      expect(
        await controller.disableMoneyPrivacy(reason: 'Disable protection'),
        DeviceAuthOutcome.canceled,
      );
      expect(
        container.read(devicePrivacyProvider).requireValue.moneyPrivacyEnabled,
        isTrue,
      );
    },
  );

  test(
    'unsupported device credentials do not enable privacy settings',
    () async {
      final authenticator = _FakeDeviceAuthenticator(supported: false);
      final container = ProviderContainer(
        overrides: [
          deviceAuthenticatorProvider.overrideWithValue(authenticator),
        ],
      );
      addTearDown(container.dispose);

      await container.read(devicePrivacyProvider.future);
      final outcome = await container
          .read(devicePrivacyProvider.notifier)
          .enableAppLock(reason: 'Lock app');

      expect(outcome, DeviceAuthOutcome.unavailable);
      expect(
        container.read(devicePrivacyProvider).requireValue.appLockEnabled,
        isFalse,
      );
      expect(authenticator.authenticationCount, 0);
    },
  );

  testWidgets('a hidden amount authenticates on tap and reveals the session', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_money_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
    final container = ProviderContainer(
      overrides: [deviceAuthenticatorProvider.overrideWithValue(authenticator)],
    );
    addTearDown(container.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ProtectedMoneyText('12,345.67 EGP')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.bySemanticsLabel('Hidden financial amount'), findsOneWidget);
    expect(find.bySemanticsLabel('12,345.67 EGP'), findsNothing);

    await tester.tap(find.byType(ProtectedMoney));
    await tester.pumpAndSettle();

    expect(authenticator.authenticationCount, 1);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('12,345.67 EGP'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a restored signed-in session authenticates before showing app', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_app_lock_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator(
      outcome: DeviceAuthOutcome.canceled,
    );
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_SignedInAuthNotifier.new),
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DevicePrivacyGate(child: Text('Private app content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(authenticator.authenticationCount, 1);
    expect(find.text('Private app content'), findsNothing);
    expect(find.text('Finance Suit is locked'), findsOneWidget);

    authenticator.outcome = DeviceAuthOutcome.authenticated;
    await tester.tap(find.text('Unlock with device security'));
    await tester.pumpAndSettle();

    expect(authenticator.authenticationCount, 2);
    expect(find.text('Private app content'), findsOneWidget);
  });
}
