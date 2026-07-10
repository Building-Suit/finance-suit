import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_shell.dart';
import 'package:work_tracker/app/routing/splash_screen.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/screens/confirm_email_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/login_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/register_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/presentation/screens/account_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/categories_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/money_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/transaction_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/transfer_form_screen.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';
import 'package:work_tracker/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:work_tracker/features/reports/presentation/screens/reports_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/change_email_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/change_password_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/salary_settings_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/settings_screen.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';
import 'package:work_tracker/features/work/presentation/screens/holidays_screen.dart';
import 'package:work_tracker/features/work/presentation/screens/work_entry_form_screen.dart';
import 'package:work_tracker/features/work/presentation/screens/work_screen.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const confirmEmail = '/auth/confirm-email';
  static const forgotPassword = '/auth/forgot-password';
  static const resetPassword = '/auth/reset-password';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const work = '/work';
  static const money = '/money';
  static const reports = '/reports';
  static const settings = '/settings';
}

/// Bridges Riverpod state changes into go_router's refreshListenable.
class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen(authStateProvider, (_, next) => refreshNotifier.refresh());
  ref.listen(onboardingStatusProvider, (_, next) => refreshNotifier.refresh());
  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final onboarding = ref.read(onboardingStatusProvider);
      final location = state.matchedLocation;
      final onAuthRoute = location.startsWith('/auth');
      final onSplash = location == AppRoutes.splash;
      final onOnboarding = location == AppRoutes.onboarding;

      switch (auth.phase) {
        case AuthPhase.restoring:
          // Never flash a protected screen while the session restores.
          return onSplash ? null : AppRoutes.splash;
        case AuthPhase.signedOut:
          return onAuthRoute ? null : AppRoutes.login;
        case AuthPhase.passwordRecovery:
          return location == AppRoutes.resetPassword
              ? null
              : AppRoutes.resetPassword;
        case AuthPhase.signedIn:
          switch (onboarding) {
            case OnboardingStatus.unknown:
              return onSplash ? null : AppRoutes.splash;
            case OnboardingStatus.incomplete:
              return onOnboarding ? null : AppRoutes.onboarding;
            case OnboardingStatus.complete:
              if (onAuthRoute || onSplash || onOnboarding) {
                return AppRoutes.home;
              }
              return null;
          }
      }
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.confirmEmail,
        builder: (context, state) =>
            ConfirmEmailScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.work,
                builder: (context, state) => const WorkScreen(),
                routes: [
                  GoRoute(
                    path: 'entry/new',
                    builder: (context, state) => WorkEntryFormScreen(
                      initialDate: switch (state.uri.queryParameters['date']) {
                        final String iso => PlainDate.parse(iso),
                        null => null,
                      },
                    ),
                  ),
                  GoRoute(
                    path: 'entry/edit',
                    builder: (context, state) => WorkEntryFormScreen(
                      existing: state.extra! as WorkEntry,
                    ),
                  ),
                  GoRoute(
                    path: 'holidays',
                    builder: (context, state) => const HolidaysScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.money,
                builder: (context, state) => const MoneyScreen(),
                routes: [
                  GoRoute(
                    path: 'accounts/new',
                    builder: (context, state) => const AccountFormScreen(),
                  ),
                  GoRoute(
                    path: 'accounts/:id',
                    builder: (context, state) => AccountFormScreen(
                      accountId: state.pathParameters['id'],
                    ),
                  ),
                  GoRoute(
                    path: 'tx/new',
                    builder: (context, state) => TransactionFormScreen(
                      kind: TransactionKind.fromDb(
                        state.uri.queryParameters['kind'] ?? 'expense',
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'tx/edit',
                    builder: (context, state) => TransactionFormScreen(
                      kind: (state.extra! as FinancialTransaction).kind,
                      existing: state.extra! as FinancialTransaction,
                    ),
                  ),
                  GoRoute(
                    path: 'transfer',
                    builder: (context, state) => const TransferFormScreen(),
                  ),
                  GoRoute(
                    path: 'categories',
                    builder: (context, state) => const CategoriesScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.reports,
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'salary',
                    builder: (context, state) => const SalarySettingsScreen(),
                  ),
                  GoRoute(
                    path: 'password',
                    builder: (context, state) => const ChangePasswordScreen(),
                  ),
                  GoRoute(
                    path: 'email',
                    builder: (context, state) => const ChangeEmailScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
