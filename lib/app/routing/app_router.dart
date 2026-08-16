import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/routing/app_shell.dart';
import 'package:work_tracker/app/routing/finance_suit_menu.dart';
import 'package:work_tracker/app/routing/splash_screen.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/auth/presentation/screens/confirm_email_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/login_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/register_screen.dart';
import 'package:work_tracker/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:work_tracker/features/commercial/presentation/screens/subscription_screen.dart';
import 'package:work_tracker/features/dashboard/presentation/screens/home_screen.dart';
import 'package:work_tracker/features/finance/domain/financial_transaction.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/income_source.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';
import 'package:work_tracker/features/finance/domain/transaction_macro.dart';
import 'package:work_tracker/features/finance/presentation/screens/account_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/categories_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/category_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/credit_facility_detail_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/facility_payment_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/held_amount_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/income_source_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/income_sources_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/installment_purchase_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/linked_installment_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/macro_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/macros_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/money_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/recurring_rule_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/recurring_rules_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/transaction_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/screens/transfer_form_screen.dart';
import 'package:work_tracker/features/network/presentation/screens/network_screen.dart';
import 'package:work_tracker/features/network/presentation/screens/network_search_screen.dart';
import 'package:work_tracker/features/onboarding/presentation/providers/onboarding_status_provider.dart';
import 'package:work_tracker/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:work_tracker/features/reports/presentation/screens/reports_screen.dart';
import 'package:work_tracker/features/salary/presentation/screens/salary_adjustment_form_screen.dart';
import 'package:work_tracker/features/salary/presentation/screens/salary_period_detail_screen.dart';
import 'package:work_tracker/features/salary/presentation/screens/salary_periods_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/change_email_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/change_password_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/delete_account_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/legal_document_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/salary_settings_screen.dart';
import 'package:work_tracker/features/settings/presentation/screens/settings_screen.dart';
import 'package:work_tracker/features/work/domain/work_entry.dart';
import 'package:work_tracker/features/work/presentation/screens/holiday_form_screen.dart';
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
  static const privacyPolicy = '/legal/privacy';
  static const terms = '/legal/terms';
  static const accountDeletionPolicy = '/legal/account-deletion';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const work = '/work';
  static const money = '/money';
  static const reports = '/reports';
  static const settings = '/settings';
  static const subscription = '/settings/subscription';
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

  // Only the four primary roots (/home, /work, /money, /reports) render
  // inside the bottom-navigation shell. Every authenticated route lives in a
  // shared navigator below the page-plane adapter, so a global drawer moves
  // the active route coherently while focused routes still cover the bottom
  // navigation. Settings remains a pushed utility destination, not a tab.
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final appNavigatorKey = GlobalKey<NavigatorState>();

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final onboarding = ref.read(onboardingStatusProvider);
      final location = state.matchedLocation;
      final onAuthRoute = location.startsWith('/auth');
      final onLegalRoute = location.startsWith('/legal');
      final onSplash = location == AppRoutes.splash;
      final onOnboarding = location == AppRoutes.onboarding;

      switch (auth.phase) {
        case AuthPhase.restoring:
          // Never flash a protected screen while the session restores.
          return onSplash ? null : AppRoutes.splash;
        case AuthPhase.signedOut:
          return onAuthRoute || onLegalRoute ? null : AppRoutes.login;
        case AuthPhase.passwordRecovery:
          return location == AppRoutes.resetPassword || onLegalRoute
              ? null
              : AppRoutes.resetPassword;
        case AuthPhase.signedIn:
          switch (onboarding) {
            case OnboardingStatus.unknown:
              return onSplash || onLegalRoute ? null : AppRoutes.splash;
            case OnboardingStatus.incomplete:
              return onOnboarding || onLegalRoute ? null : AppRoutes.onboarding;
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
        path: AppRoutes.privacyPolicy,
        builder: (context, state) =>
            const LegalDocumentScreen(document: LegalDocument.privacyPolicy),
      ),
      GoRoute(
        path: AppRoutes.terms,
        builder: (context, state) =>
            const LegalDocumentScreen(document: LegalDocument.terms),
      ),
      GoRoute(
        path: AppRoutes.accountDeletionPolicy,
        builder: (context, state) =>
            const LegalDocumentScreen(document: LegalDocument.accountDeletion),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        navigatorKey: appNavigatorKey,
        builder: (context, state, child) =>
            FinanceSuitMenuPagePlane(child: child),
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
                    path: AppRoutes.home,
                    builder: (context, state) => AuthenticatedBackScope(
                      currentLocation: state.uri.path,
                      child: const HomeScreen(),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.work,
                    builder: (context, state) => AuthenticatedBackScope(
                      currentLocation: state.uri.path,
                      child: const WorkScreen(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'entry/new',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => WorkEntryFormScreen(
                          initialDate:
                              switch (state.uri.queryParameters['date']) {
                                final String iso => PlainDate.parse(iso),
                                null => null,
                              },
                          initialType:
                              switch (state.uri.queryParameters['type']) {
                                final String type => WorkEntryType.fromDb(type),
                                null => null,
                              },
                        ),
                      ),
                      GoRoute(
                        path: 'entry/edit',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => WorkEntryFormScreen(
                          existing: state.extra! as WorkEntry,
                        ),
                      ),
                      GoRoute(
                        path: 'holidays',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => const HolidaysScreen(),
                        routes: [
                          GoRoute(
                            path: 'new',
                            parentNavigatorKey: appNavigatorKey,
                            builder: (context, state) =>
                                const HolidayFormScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'periods',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) =>
                            const SalaryPeriodsScreen(),
                        routes: [
                          GoRoute(
                            path: ':id',
                            parentNavigatorKey: appNavigatorKey,
                            builder: (context, state) =>
                                SalaryPeriodDetailScreen(
                                  periodId: state.pathParameters['id']!,
                                ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'adjustments/new',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => SalaryAdjustmentFormScreen(
                          preferredPeriodId:
                              state.uri.queryParameters['periodId'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.money,
                    builder: (context, state) => AuthenticatedBackScope(
                      currentLocation: state.uri.path,
                      child: MoneyScreen(
                        key: ValueKey(state.uri.queryParameters['tab']),
                        initialTab:
                            state.uri.queryParameters['tab'] == 'transactions'
                            ? 1
                            : 0,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'accounts/new',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => const AccountFormScreen(),
                      ),
                      GoRoute(
                        path: 'accounts/:id',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => AccountFormScreen(
                          accountId: state.pathParameters['id'],
                        ),
                      ),
                      // Static facility routes must precede the ':id' pattern.
                      GoRoute(
                        path: 'facilities/purchase',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => InstallmentPurchaseScreen(
                          accountId: state.uri.queryParameters['accountId'],
                          planId: state.uri.queryParameters['planId'],
                        ),
                      ),
                      GoRoute(
                        path: 'facilities/pay',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => FacilityPaymentScreen(
                          accountId: state.uri.queryParameters['accountId'],
                          monthStartIso: state.uri.queryParameters['month'],
                        ),
                      ),
                      GoRoute(
                        path: 'facilities/:id',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => CreditFacilityDetailScreen(
                          accountId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'tx/new',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => TransactionFormScreen(
                          kind: TransactionKind.fromDb(
                            state.uri.queryParameters['kind'] ?? 'expense',
                          ),
                          initialAccountId:
                              state.uri.queryParameters['accountId'],
                        ),
                      ),
                      GoRoute(
                        path: 'tx/edit',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => TransactionFormScreen(
                          kind: (state.extra! as FinancialTransaction).kind,
                          existing: state.extra! as FinancialTransaction,
                        ),
                      ),
                      GoRoute(
                        path: 'transfer',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => const TransferFormScreen(),
                      ),
                      GoRoute(
                        path: 'categories',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => const CategoriesScreen(),
                        routes: [
                          GoRoute(
                            path: 'new',
                            parentNavigatorKey: appNavigatorKey,
                            builder: (context, state) => CategoryFormScreen(
                              initialKind:
                                  state.uri.queryParameters['kind'] == null
                                  ? null
                                  : CategoryKind.fromDb(
                                      state.uri.queryParameters['kind']!,
                                    ),
                              initialParentCategoryId:
                                  state.uri.queryParameters['parent'],
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'macros',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => const MacrosScreen(),
                        routes: [
                          GoRoute(
                            path: 'new',
                            parentNavigatorKey: appNavigatorKey,
                            builder: (context, state) =>
                                const MacroFormScreen(),
                          ),
                          GoRoute(
                            path: 'edit',
                            parentNavigatorKey: appNavigatorKey,
                            builder: (context, state) => MacroFormScreen(
                              existing: state.extra! as TransactionMacro,
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'network',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => NetworkScreen(
                          initialTab:
                              switch (state.uri.queryParameters['tab']) {
                                'requests' => 1,
                                'transfers' => 2,
                                'linked' => 3,
                                _ => 0,
                              },
                        ),
                        routes: [
                          GoRoute(
                            path: 'search',
                            parentNavigatorKey: appNavigatorKey,
                            builder: (context, state) =>
                                const NetworkSearchScreen(),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'linked/:linkId',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => LinkedInstallmentScreen(
                          linkId: state.pathParameters['linkId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'held/new',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => HeldAmountFormScreen(
                          prefill: state.extra as HeldAmountDraft?,
                        ),
                      ),
                      GoRoute(
                        path: 'held/edit',
                        parentNavigatorKey: appNavigatorKey,
                        builder: (context, state) => HeldAmountFormScreen(
                          existing: state.extra! as HeldAmount,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.reports,
                    builder: (context, state) => AuthenticatedBackScope(
                      currentLocation: state.uri.path,
                      child: const ReportsScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Pushed utility destinations retain their URLs and cover the bottom
          // navigation, while remaining inside the shared page-plane navigator.
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'subscription',
                builder: (context, state) => const SubscriptionScreen(),
              ),
              GoRoute(
                path: 'salary',
                builder: (context, state) => const SalarySettingsScreen(),
              ),
              GoRoute(
                path: 'income-sources',
                builder: (context, state) => const IncomeSourcesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const IncomeSourceFormScreen(),
                  ),
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => IncomeSourceFormScreen(
                      existing: state.extra! as IncomeSource,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'recurring',
                builder: (context, state) => const RecurringRulesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) =>
                        const RecurringRuleFormScreen(),
                  ),
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => RecurringRuleFormScreen(
                      existing: state.extra! as RecurringRule,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'password',
                builder: (context, state) => const ChangePasswordScreen(),
              ),
              GoRoute(
                path: 'email',
                builder: (context, state) => const ChangeEmailScreen(),
              ),
              GoRoute(
                path: 'delete-account',
                builder: (context, state) => const DeleteAccountScreen(),
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
