import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
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

  /// When set, [authenticate] stays in flight until the completer resolves,
  /// mimicking a native prompt waiting for the user's finger.
  Completer<DeviceAuthOutcome>? pending;

  @override
  Future<DeviceAuthOutcome> authenticate({required String reason}) async {
    authenticationCount++;
    final pending = this.pending;
    if (pending != null) return pending.future;
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
    DeviceAuthSession.reset();
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

  testWidgets('notification shade lifecycle does not re-open authentication', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_app_lock_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(authenticator.authenticationCount, 1);
    expect(find.text('Private app content'), findsOneWidget);
  });

  testWidgets('a shade pull that stops the activity briefly never locks', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_app_lock_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_SignedInAuthNotifier.new),
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

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
    expect(find.text('Private app content'), findsOneWidget);

    // OEM shells stop the activity for a fully expanded notification shade.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(authenticator.authenticationCount, 1);
    expect(find.text('Private app content'), findsOneWidget);
  });

  testWidgets('a real backgrounding locks and prompts once after resume', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_app_lock_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_SignedInAuthNotifier.new),
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));

    // Locked while away, but no prompt may fire until the app is foreground.
    expect(
      container.read(devicePrivacyProvider).requireValue.appUnlocked,
      isFalse,
    );
    expect(authenticator.authenticationCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(authenticator.authenticationCount, 2);
    expect(find.text('Private app content'), findsOneWidget);
  });

  testWidgets('lifecycle churn from the prompt itself never locks the app', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_money_enabled': true,
          'device_privacy_app_lock_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_SignedInAuthNotifier.new),
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DevicePrivacyGate(
            child: Scaffold(body: ProtectedMoneyText('12,345.67 EGP')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(authenticator.authenticationCount, 1);

    // A fullscreen fingerprint prompt stops the activity while it waits.
    final prompt = Completer<DeviceAuthOutcome>();
    authenticator.pending = prompt;
    await tester.tap(find.byType(ProtectedMoney));
    await tester.pump();
    expect(authenticator.authenticationCount, 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));

    // Still authenticating: the deferred lock must keep waiting.
    expect(
      container.read(devicePrivacyProvider).requireValue.appUnlocked,
      isTrue,
    );

    authenticator.pending = null;
    prompt.complete(DeviceAuthOutcome.authenticated);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // The reveal prompt is the only extra authentication; no relock happened.
    expect(authenticator.authenticationCount, 2);
    expect(
      container.read(devicePrivacyProvider).requireValue.appUnlocked,
      isTrue,
    );
    expect(find.text('12,345.67 EGP'), findsOneWidget);
  });

  testWidgets('backgrounding away during a prompt still locks the app', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'device_privacy_money_enabled': true,
          'device_privacy_app_lock_enabled': true,
        });
    final authenticator = _FakeDeviceAuthenticator();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_SignedInAuthNotifier.new),
        deviceAuthenticatorProvider.overrideWithValue(authenticator),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DevicePrivacyGate(
            child: Scaffold(body: ProtectedMoneyText('12,345.67 EGP')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(authenticator.authenticationCount, 1);

    final prompt = Completer<DeviceAuthOutcome>();
    authenticator.pending = prompt;
    await tester.tap(find.byType(ProtectedMoney));
    await tester.pump();

    // The user leaves for the launcher while the prompt is still up.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));

    authenticator.pending = null;
    prompt.complete(DeviceAuthOutcome.canceled);
    await tester.pump(const Duration(seconds: 3));

    expect(
      container.read(devicePrivacyProvider).requireValue.appUnlocked,
      isFalse,
    );
  });

  testWidgets('header eye reveals once and hides without another prompt', (
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            appBar: FinanceSuitAppBar.topLevel(semanticTitle: 'Home'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('money-visibility-button')));
    await tester.pumpAndSettle();
    expect(authenticator.authenticationCount, 1);
    expect(
      container.read(devicePrivacyProvider).requireValue.moneyRevealed,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('money-visibility-button')));
    await tester.pumpAndSettle();
    expect(authenticator.authenticationCount, 1);
    expect(
      container.read(devicePrivacyProvider).requireValue.moneyRevealed,
      isFalse,
    );
  });
}
