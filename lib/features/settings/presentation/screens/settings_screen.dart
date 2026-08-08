import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/configuration/env.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/notifications/notifications_repository.dart';
import 'package:work_tracker/core/notifications/push_notifications_service.dart';
import 'package:work_tracker/core/security/biometric_login_controller.dart';
import 'package:work_tracker/core/security/device_authenticator.dart';
import 'package:work_tracker/core/security/device_privacy_controller.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/app_selection_field.dart';
import 'package:work_tracker/core/widgets/app_text_form_field.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/providers/commercial_providers.dart';
import 'package:work_tracker/features/settings/data/settings_repository.dart';
import 'package:work_tracker/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showDeviceAuthOutcome(BuildContext context, DeviceAuthOutcome outcome) {
    final l10n = AppLocalizations.of(context);
    switch (outcome) {
      case DeviceAuthOutcome.authenticated:
        AppToast.success(context, l10n.setSaved);
      case DeviceAuthOutcome.canceled:
        return;
      case DeviceAuthOutcome.unavailable:
        AppToast.warning(context, l10n.privacyDeviceAuthUnavailable);
      case DeviceAuthOutcome.failed:
        AppToast.error(context, l10n.privacyDeviceAuthFailed);
    }
  }

  Future<void> _setMoneyPrivacy(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final controller = ref.read(devicePrivacyProvider.notifier);
    if (!enabled) {
      final outcome = await controller.disableMoneyPrivacy(
        reason: AppLocalizations.of(context).privacyDisableMoneyReason,
      );
      if (context.mounted) _showDeviceAuthOutcome(context, outcome);
      return;
    }
    final outcome = await controller.enableMoneyPrivacy(
      reason: AppLocalizations.of(context).privacyEnableMoneyReason,
    );
    if (context.mounted) _showDeviceAuthOutcome(context, outcome);
  }

  Future<void> _setAppLock(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final controller = ref.read(devicePrivacyProvider.notifier);
    if (!enabled) {
      final outcome = await controller.disableAppLock(
        reason: AppLocalizations.of(context).privacyDisableAppLockReason,
      );
      if (context.mounted) _showDeviceAuthOutcome(context, outcome);
      return;
    }
    final outcome = await controller.enableAppLock(
      reason: AppLocalizations.of(context).privacyEnableAppLockReason,
    );
    if (context.mounted) _showDeviceAuthOutcome(context, outcome);
  }

  Future<void> _setBiometricLogin(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(biometricLoginProvider.notifier);
    if (!enabled) {
      final outcome = await controller.disable(
        reason: l10n.privacyDisableBiometricLoginReason,
      );
      if (context.mounted) _showDeviceAuthOutcome(context, outcome);
      return;
    }

    final password = await _requestPassword(context);
    if (password == null || !context.mounted) return;
    final outcome = await controller.enable(
      reason: l10n.privacyEnableBiometricLoginReason,
      password: password,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case BiometricLoginOutcome.authenticated:
        AppToast.success(context, l10n.setSaved);
      case BiometricLoginOutcome.canceled:
        return;
      case BiometricLoginOutcome.unavailable:
        AppToast.warning(context, l10n.privacyDeviceAuthUnavailable);
      case BiometricLoginOutcome.invalidCredentials:
        AppToast.error(context, l10n.privacyIncorrectPassword);
      case BiometricLoginOutcome.sessionExpired:
      case BiometricLoginOutcome.failed:
        AppToast.error(context, l10n.authBiometricLoginFailed);
    }
  }

  Future<String?> _requestPassword(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.privacyConfirmPasswordTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.privacyConfirmPasswordHelp),
              const SizedBox(height: 16),
              AppTextFormField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: l10n.authPassword),
                validator: (value) {
                  final error = Validators.requiredText(value);
                  return error == null
                      ? null
                      : validationMessage(dialogContext, error);
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState!.validate()) {
                    Navigator.of(dialogContext).pop(passwordController.text);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(passwordController.text);
              }
            },
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    passwordController.dispose();
    return password;
  }

  Future<void> _editDisplayName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: current);
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.setDisplayName),
        content: Form(
          key: formKey,
          child: AppTextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              final e = Validators.requiredText(v, maxLength: 120);
              return e == null ? null : validationMessage(dialogContext, e);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final result = await ref
        .read(settingsRepositoryProvider)
        .updateDisplayName(controller.text.trim());
    if (!context.mounted) return;
    result.when(
      ok: (_) {
        ref.invalidate(profileProvider);
        AppToast.success(context, l10n.setSaved);
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.setSignOutConfirmTitle),
        content: Text(l10n.setSignOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.authLogout),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authActionProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(appLocaleProvider);
    final profile = ref.watch(profileProvider);
    final privacy = ref.watch(devicePrivacyProvider).value;
    final biometricLogin = ref.watch(biometricLoginProvider).value;
    final entitlement = ref.watch(effectiveEntitlementProvider).value;
    final securityControlsEnabled =
        privacy != null &&
        biometricLogin != null &&
        !privacy.authenticating &&
        !biometricLogin.authenticating;

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: l10n.tabSettings),
      body: FinanceSuitFocusedBody(
        title: l10n.tabSettings,
        child: ListView(
          children: [
            _SectionHeader(title: l10n.setAppearance),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.brightness),
              title: Text(l10n.setTheme),
              trailing: SizedBox(
                width: 160,
                child: AppSelectionField<ThemeMode>(
                  initialValue: themeMode,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(themeModeProvider.notifier).setMode(mode);
                    }
                  },
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(l10n.setThemeSystem),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(l10n.setThemeLight),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(l10n.setThemeDark),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.language),
              title: Text(l10n.onbLanguage),
              trailing: SizedBox(
                width: 140,
                child: AppSelectionField<String>(
                  initialValue: locale?.languageCode ?? 'en',
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (code) {
                    if (code != null) {
                      ref
                          .read(appLocaleProvider.notifier)
                          .setLocale(Locale(code));
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  ],
                ),
              ),
            ),
            const Divider(),
            _SectionHeader(title: l10n.setSecurity),
            SwitchListTile.adaptive(
              secondary: const FinanceSuitIcon(FinanceSuitIcons.visibilityOff),
              title: Text(l10n.privacyMoneyTitle),
              subtitle: Text(l10n.privacyMoneyHelp),
              value: privacy?.moneyPrivacyEnabled ?? false,
              onChanged: securityControlsEnabled
                  ? (value) => _setMoneyPrivacy(context, ref, value)
                  : null,
            ),
            SwitchListTile.adaptive(
              secondary: const FinanceSuitIcon(FinanceSuitIcons.fingerprint),
              title: Text(l10n.privacyAppLockTitle),
              subtitle: Text(l10n.privacyAppLockHelp),
              value: privacy?.appLockEnabled ?? false,
              onChanged: securityControlsEnabled
                  ? (value) => _setAppLock(context, ref, value)
                  : null,
            ),
            SwitchListTile.adaptive(
              secondary: const FinanceSuitIcon(FinanceSuitIcons.fingerprint),
              title: Text(l10n.privacyBiometricLoginTitle),
              subtitle: Text(l10n.privacyBiometricLoginHelp),
              value: biometricLogin?.enabled ?? false,
              onChanged: securityControlsEnabled
                  ? (value) => _setBiometricLogin(context, ref, value)
                  : null,
            ),
            const Divider(),
            _SectionHeader(title: l10n.setNotificationsSection),
            const _NotificationPreferencesSection(),
            const Divider(),
            _SectionHeader(title: l10n.setProfileSection),
            profile.when(
              data: (p) => ListTile(
                leading: const FinanceSuitIcon(FinanceSuitIcons.person),
                title: Text(l10n.setDisplayName),
                subtitle: Text(p.displayName),
                trailing: const FinanceSuitIcon(FinanceSuitIcons.edit),
                onTap: () => _editDisplayName(context, ref, p.displayName),
              ),
              loading: () => ListTile(
                leading: const FinanceSuitIcon(FinanceSuitIcons.person),
                title: Text(l10n.setDisplayName),
                subtitle: Text(l10n.commonLoading),
              ),
              error: (e, _) => ListTile(
                leading: const FinanceSuitIcon(FinanceSuitIcons.person),
                title: Text(l10n.setDisplayName),
                subtitle: Text(l10n.commonError),
                trailing: IconButton(
                  icon: const FinanceSuitIcon(FinanceSuitIcons.refresh),
                  onPressed: () => ref.invalidate(profileProvider),
                ),
              ),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.email),
              title: Text(l10n.setChangeEmail),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go('${AppRoutes.settings}/email'),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.password),
              title: Text(l10n.setChangePassword),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go('${AppRoutes.settings}/password'),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.star),
              title: Text(l10n.planBilling),
              subtitle: Text(_planSummary(l10n, entitlement)),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go(AppRoutes.subscription),
            ),
            const Divider(),
            _SectionHeader(title: l10n.setSalarySection),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.payments),
              title: Text(l10n.setSalarySection),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go('${AppRoutes.settings}/salary'),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.trendingUp),
              title: Text(l10n.incomeAutomationCenter),
              subtitle: Text(l10n.incomeSourcesSubtitle),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go('${AppRoutes.settings}/income-sources'),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.eventRepeat),
              title: Text(l10n.recurringCenterTitle),
              subtitle: Text(l10n.recurringCenterSubtitle),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go('${AppRoutes.settings}/recurring'),
            ),
            const Divider(),
            _SectionHeader(title: l10n.setAccountSection),
            ListTile(
              leading: FinanceSuitIcon(
                FinanceSuitIcons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.setDeleteAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: Text(l10n.setDeleteAccountSubtitle),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.go('${AppRoutes.settings}/delete-account'),
            ),
            ListTile(
              leading: FinanceSuitIcon(
                FinanceSuitIcons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.authLogout,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => _confirmSignOut(context, ref),
            ),
            const Divider(),
            _SectionHeader(title: l10n.setAboutSection),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.lock),
              title: Text(l10n.setPrivacyPolicy),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.push(AppRoutes.privacyPolicy),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.receiptLong),
              title: Text(l10n.setTerms),
              trailing: const FinanceSuitIcon(FinanceSuitIcons.chevronRight),
              onTap: () => context.push(AppRoutes.terms),
            ),
            ListTile(
              leading: const FinanceSuitIcon(FinanceSuitIcons.info),
              title: Text(l10n.setAppVersion),
              subtitle: Text(Env.appVersion),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _planSummary(AppLocalizations l10n, EffectiveEntitlement? value) {
    if (value == null || !value.isPro) return l10n.freePlan;
    return switch (value.source) {
      EntitlementSource.openEarlyAccess => l10n.proEarlyAccessSummary,
      EntitlementSource.adminGrant => l10n.proComplimentary,
      EntitlementSource.paid =>
        value.metadataInterval == 'year' ? l10n.proAnnual : l10n.proMonthly,
      _ => value.sourceLabel,
    };
  }
}

/// Due-reminder switches backed by `app_core.notification_preferences`.
/// Saving is optimistic per switch; a failure re-syncs from the server.
class _NotificationPreferencesSection extends ConsumerWidget {
  const _NotificationPreferencesSection();

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    NotificationPreferences updated,
  ) async {
    final result = await ref
        .read(notificationsRepositoryProvider)
        .savePreferences(updated);
    ref.invalidate(notificationPreferencesProvider);
    if (!context.mounted) return;
    result.when(
      ok: (_) {},
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  Future<void> _enableNotifications(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    await ref
        .read(pushNotificationsServiceProvider)
        .syncRegistration(
          userId: userId,
          openRoute: ref.read(appRouterProvider).go,
          locale: Localizations.localeOf(context).toLanguageTag(),
          forcePermissionRequest: true,
        );
    ref.invalidate(pushNotificationStatusProvider);
  }

  Future<void> _sendTestNotification(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await ref
        .read(notificationsRepositoryProvider)
        .sendDeveloperTestNotification();
    if (!context.mounted) return;
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    result.when(
      ok: (delivery) {
        if (delivery.sent > 0) {
          AppToast.success(
            context,
            isArabic ? 'تم إرسال إشعار تجريبي' : 'Test notification sent',
          );
        } else if (delivery.failed > 0 || delivery.suppressed > 0) {
          AppToast.warning(
            context,
            isArabic
                ? 'تم إنشاء الاختبار لكن لم يتم تسليمه'
                : 'Test queued, but delivery did not complete',
          );
        } else {
          AppToast.info(
            context,
            isArabic
                ? 'تم إنشاء الاختبار. انتظر لحظة ثم تحقق من الإشعارات'
                : 'Test queued. Check notifications in a moment',
          );
        }
      },
      err: (failure) =>
          AppToast.error(context, failureMessage(context, failure)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final preferences =
        ref.watch(notificationPreferencesProvider).value ??
        const NotificationPreferences();
    final loaded = ref.watch(notificationPreferencesProvider).hasValue;
    final pushStatus = ref.watch(pushNotificationStatusProvider).value;
    final osPermission = pushStatus?.permission;
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final osStatus = switch (osPermission) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional =>
        isArabic ? 'إشعارات النظام مفعّلة' : 'System notifications are allowed',
      AuthorizationStatus.denied =>
        isArabic ? 'إشعارات النظام متوقفة' : 'System notifications are blocked',
      AuthorizationStatus.notDetermined =>
        isArabic
            ? 'لم يتم طلب إذن النظام بعد'
            : 'System permission has not been requested',
      null =>
        isArabic
            ? 'الإشعارات غير متاحة في هذا البناء'
            : 'Notifications are unavailable in this build',
    };
    final registrationStatus = switch (pushStatus) {
      PushNotificationStatus(firebaseAvailable: false) =>
        isArabic
            ? 'Firebase غير متاح في هذا البناء'
            : 'Firebase is unavailable in this build',
      PushNotificationStatus(registered: true, maskedToken: final token?) =>
        isArabic
            ? 'جاهز على هذا الجهاز ($token)'
            : 'Ready on this device ($token)',
      PushNotificationStatus(hasFcmToken: true) =>
        isArabic
            ? 'تم الاتصال ب Firebase، لكن التسليم لم يكتمل'
            : 'Firebase is connected, but delivery setup is incomplete',
      PushNotificationStatus(lastError: final error?) =>
        isArabic
            ? 'تعذر تفعيل التسليم: $error'
            : 'Delivery setup failed: $error',
      _ =>
        isArabic
            ? 'فعّل الإشعارات لإرسال التنبيهات إلى هذا الجهاز'
            : 'Turn on notifications to send alerts to this device',
    };
    final canSendTest =
        pushStatus?.registered == true &&
        (osPermission == AuthorizationStatus.authorized ||
            osPermission == AuthorizationStatus.provisional);
    return Column(
      children: [
        ListTile(
          key: const Key('notif-os-permission-status'),
          leading: const FinanceSuitIcon(FinanceSuitIcons.eventAvailable),
          title: Text(isArabic ? 'إشعارات الهاتف' : 'Phone notifications'),
          subtitle: Text(osStatus),
          trailing: TextButton(
            onPressed: () => _enableNotifications(context, ref),
            child: Text(isArabic ? 'تفعيل' : 'Enable'),
          ),
        ),
        ListTile(
          key: const Key('notif-device-registration-status'),
          leading: const FinanceSuitIcon(FinanceSuitIcons.payments),
          title: Text(isArabic ? 'تسليم التنبيهات' : 'Alert delivery'),
          subtitle: Text(registrationStatus),
          trailing: TextButton(
            onPressed: () => _enableNotifications(context, ref),
            child: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
          ),
        ),
        ListTile(
          key: const Key('notif-send-test'),
          leading: const FinanceSuitIcon(FinanceSuitIcons.play),
          title: Text(
            isArabic ? 'إرسال إشعار تجريبي' : 'Send test notification',
          ),
          subtitle: Text(
            isArabic
                ? 'يتحقق من التسليم من الخادم إلى هذا الهاتف.'
                : 'Checks delivery from the server to this phone.',
          ),
          trailing: TextButton(
            onPressed: canSendTest
                ? () => _sendTestNotification(context, ref)
                : null,
            child: Text(isArabic ? 'إرسال' : 'Send'),
          ),
        ),
        SwitchListTile.adaptive(
          key: const Key('notif-due-reminders'),
          secondary: const FinanceSuitIcon(FinanceSuitIcons.eventAvailable),
          title: Text(l10n.notifDueRemindersTitle),
          subtitle: Text(l10n.notifDueRemindersHelp),
          value: preferences.dueRemindersEnabled,
          onChanged: !loaded
              ? null
              : (value) => _update(
                  context,
                  ref,
                  preferences.copyWith(dueRemindersEnabled: value),
                ),
        ),
        SwitchListTile.adaptive(
          key: const Key('notif-overdue-reminders'),
          secondary: const FinanceSuitIcon(FinanceSuitIcons.warning),
          title: Text(l10n.notifOverdueRemindersTitle),
          subtitle: Text(l10n.notifOverdueRemindersHelp),
          value: preferences.overdueRemindersEnabled,
          onChanged: !loaded
              ? null
              : (value) => _update(
                  context,
                  ref,
                  preferences.copyWith(overdueRemindersEnabled: value),
                ),
        ),
        SwitchListTile.adaptive(
          key: const Key('notif-payment-confirmations'),
          secondary: const FinanceSuitIcon(FinanceSuitIcons.payments),
          title: Text(l10n.notifPaymentConfirmationsTitle),
          subtitle: Text(l10n.notifPaymentConfirmationsHelp),
          value: preferences.paymentConfirmationsEnabled,
          onChanged: !loaded
              ? null
              : (value) => _update(
                  context,
                  ref,
                  preferences.copyWith(paymentConfirmationsEnabled: value),
                ),
        ),
        SwitchListTile.adaptive(
          key: const Key('notif-show-amounts'),
          secondary: const FinanceSuitIcon(FinanceSuitIcons.visibilityOff),
          title: Text(l10n.notifShowAmountsTitle),
          subtitle: Text(l10n.notifShowAmountsHelp),
          value: preferences.showAmounts,
          onChanged: !loaded
              ? null
              : (value) => _update(
                  context,
                  ref,
                  preferences.copyWith(showAmounts: value),
                ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
