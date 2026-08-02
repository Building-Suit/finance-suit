import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/widgets/device_privacy_gate.dart';
import 'package:work_tracker/features/settings/presentation/providers/app_settings_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class FinanceSuitApp extends ConsumerWidget {
  const FinanceSuitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(appLocaleProvider);
    final effectiveLocale =
        locale ?? WidgetsBinding.instance.platformDispatcher.locale;

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(locale: effectiveLocale),
      darkTheme: AppTheme.dark(locale: effectiveLocale),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      routerConfig: router,
      builder: (context, child) =>
          DevicePrivacyGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
