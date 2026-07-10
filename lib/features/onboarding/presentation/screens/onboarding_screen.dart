import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Four-step onboarding wizard (profile, salary, account, review).
/// Steps are implemented in the onboarding feature phase.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
