import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';

class _FakeAuthNotifier extends AuthStateNotifier {
  @override
  AuthStateData build() =>
      const AuthStateData(phase: AuthPhase.signedIn, userId: 'user-1');
}

class _FakeOnboardingNotifier extends OnboardingStatusNotifier {
  @override
  OnboardingStatus build() => OnboardingStatus.complete;
}

/// Structural checks of the central shell-chrome routing policy: the shell
/// hosts exactly the four primary destinations, while one authenticated
/// navigator owns the page-plane transform for primary and pushed routes.
/// Settings remains a pushed utility destination while History is represented
/// by the Money branch's Transactions tab.
void main() {
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_FakeAuthNotifier.new),
        onboardingStatusProvider.overrideWith(_FakeOnboardingNotifier.new),
      ],
    );
    router = container.read(appRouterProvider);
  });

  tearDown(() => container.dispose());

  ShellRoute authenticatedRoute() =>
      router.configuration.routes.whereType<ShellRoute>().single;

  StatefulShellRoute shellRoute() =>
      authenticatedRoute().routes.whereType<StatefulShellRoute>().single;

  Iterable<GoRoute> descendants(RouteBase route) sync* {
    for (final child in route.routes) {
      if (child is GoRoute) yield child;
      yield* descendants(child);
    }
  }

  test('shell hosts exactly the four primary destinations', () {
    final shell = shellRoute();
    expect(shell.branches, hasLength(4));
    final roots = [
      for (final branch in shell.branches)
        (branch.routes.single as GoRoute).path,
    ];
    expect(roots, ['/home', '/work', '/money', '/reports']);
  });

  test('Settings is a pushed utility destination with unchanged URLs', () {
    final topLevel = authenticatedRoute().routes.whereType<GoRoute>();
    final settings = topLevel.singleWhere((r) => r.path == '/settings');
    final nested = descendants(settings).map((r) => r.path).toList();
    expect(
      nested,
      containsAll([
        'salary',
        'income-sources',
        'new',
        'edit',
        'password',
        'email',
        'delete-account',
      ]),
    );
    expect(topLevel.any((r) => r.path == '/history'), isFalse);
  });

  test('every nested branch route uses the shared authenticated navigator', () {
    final appKey = authenticatedRoute().navigatorKey;
    for (final branch in shellRoute().branches) {
      final root = branch.routes.single as GoRoute;
      expect(root.parentNavigatorKey, isNull);
      for (final nested in descendants(root)) {
        expect(
          nested.parentNavigatorKey,
          same(appKey),
          reason:
              '${nested.path} must cover the bottom navigation while '
              'remaining inside the shared page-plane transform',
        );
      }
    }
  });

  test('all previous route locations still exist', () {
    final knownLocations = [
      '/home',
      '/work',
      '/work/entry/new',
      '/work/holidays',
      '/work/holidays/new',
      '/work/periods',
      '/work/adjustments/new',
      '/money',
      '/money/accounts/new',
      '/money/tx/new',
      '/money/transfer',
      '/money/categories',
      '/money/categories/new',
      '/money/macros',
      '/money/macros/new',
      '/money/held/new',
      '/money/facilities/purchase',
      '/money/facilities/pay',
      '/money/facilities/some-account-id',
      '/reports',
      '/settings',
      '/settings/salary',
      '/settings/income-sources',
      '/settings/income-sources/new',
      '/settings/password',
      '/settings/email',
      '/settings/delete-account',
    ];
    for (final location in knownLocations) {
      final matches = router.configuration.findMatch(Uri.parse(location));
      expect(matches.isError, isFalse, reason: location);
    }
  });
}
