import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/configuration/env.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/core/validation/validators.dart';
import 'package:work_tracker/core/widgets/failure_text.dart';
import 'package:work_tracker/features/auth/presentation/controllers/auth_controller.dart';
import 'package:work_tracker/features/settings/data/settings_repository.dart';
import 'package:work_tracker/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

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
          child: TextFormField(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.setSaved)));
      },
      err: (failure) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage(context, failure)))),
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        children: [
          _SectionHeader(title: l10n.setAppearance),
          ListTile(
            leading: const FinanceSuitIcon(FinanceSuitIcons.brightness),
            title: Text(l10n.setTheme),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              underline: const SizedBox.shrink(),
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
          ListTile(
            leading: const FinanceSuitIcon(FinanceSuitIcons.language),
            title: Text(l10n.onbLanguage),
            trailing: DropdownButton<String>(
              value: locale?.languageCode ?? 'en',
              underline: const SizedBox.shrink(),
              onChanged: (code) {
                if (code != null) {
                  ref.read(appLocaleProvider.notifier).setLocale(Locale(code));
                }
              },
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ar', child: Text('العربية')),
              ],
            ),
          ),
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
