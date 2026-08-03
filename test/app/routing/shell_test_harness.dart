import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_shell.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/supabase/realtime_invalidation.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Builds a router that mirrors the production routing policy — a
/// four-branch shell hosting the real [AppShell], root-navigator nested
/// routes, and top-level pushed utility destinations — with lightweight
/// stub screens so shell chrome can be tested without Supabase data.
GoRouter buildShellTestRouter({String initialLocation = '/home'}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          currentLocation: state.uri.path,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) =>
                    const StubPrimaryScreen(label: 'home-root'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/work',
                builder: (context, state) =>
                    const StubPrimaryScreen(label: 'work-root'),
                routes: [
                  GoRoute(
                    path: 'entry/new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'work-entry-form'),
                  ),
                  GoRoute(
                    path: 'holidays',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'holidays-screen'),
                  ),
                  GoRoute(
                    path: 'periods',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'salary-periods-screen'),
                  ),
                  GoRoute(
                    path: 'adjustments/new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => StubFocusedScreen(
                      label:
                          'salary-adjustment-form'
                          '${state.uri.query.isEmpty ? '' : '?${state.uri.query}'}',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/money',
                builder: (context, state) =>
                    const StubPrimaryScreen(label: 'money-root'),
                routes: [
                  GoRoute(
                    path: 'tx/new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => StubFocusedScreen(
                      label:
                          'tx-form-${state.uri.queryParameters['kind'] ?? ''}',
                    ),
                  ),
                  GoRoute(
                    path: 'transfer',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'transfer-form'),
                  ),
                  GoRoute(
                    path: 'categories',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'categories-screen'),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const StubFocusedScreen(label: 'category-form'),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'macros',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'macros-screen'),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const StubFocusedScreen(label: 'macro-form'),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'held/new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'held-form'),
                  ),
                  GoRoute(
                    path: 'accounts/new',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const StubFocusedScreen(label: 'account-form'),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) =>
                    const StubPrimaryScreen(label: 'reports-root'),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) =>
            const StubFocusedScreen(label: 'history-screen'),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const StubFocusedScreen(label: 'settings-root'),
        routes: [
          GoRoute(
            path: 'income-sources',
            builder: (context, state) =>
                const StubFocusedScreen(label: 'automation-center'),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) =>
                    const StubFocusedScreen(label: 'income-source-form'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Pumps the harness app with the given [router].
///
/// [extraOverrides] lets individual tests override additional providers
/// (typed dynamically because Riverpod 3 does not export `Override`).
Future<void> pumpShellApp(
  WidgetTester tester,
  GoRouter router, {
  Locale locale = const Locale('en'),
  List<dynamic> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        realtimeInvalidationProvider.overrideWith((ref) {}),
        macrosProvider.overrideWith((ref) async => const <TransactionMacro>[]),
        ...extraOverrides.cast(),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(locale: locale),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A primary-tab stub with the canonical top-level header, a tap counter to
/// verify branch-state preservation, and a button that pushes a nested
/// focused route.
class StubPrimaryScreen extends StatefulWidget {
  const StubPrimaryScreen({super.key, required this.label});

  final String label;

  @override
  State<StubPrimaryScreen> createState() => _StubPrimaryScreenState();
}

class _StubPrimaryScreenState extends State<StubPrimaryScreen> {
  var _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FinanceSuitAppBar.topLevel(semanticTitle: widget.label),
      body: Column(
        children: [
          Text(widget.label),
          Text('${widget.label}-taps-$_taps'),
          TextButton(
            key: Key('${widget.label}-counter'),
            onPressed: () => setState(() => _taps++),
            child: const Text('count'),
          ),
        ],
      ),
    );
  }
}

/// A focused-route stub using the canonical focused header.
class StubFocusedScreen extends StatelessWidget {
  const StubFocusedScreen({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: label),
      body: Center(child: Text(label)),
    );
  }
}
