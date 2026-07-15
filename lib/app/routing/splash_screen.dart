import 'package:flutter/material.dart';
import 'package:work_tracker/app/branding/finance_suit_brand.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// Shown while the session is being restored or onboarding status resolved.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: FinanceSuitBrand.buildingNavy,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FinanceSuitMark(
                size: 96,
                withBackground: false,
                semanticLabel: null,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.appTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: FinanceSuitBrand.pearlWhite,
                ),
              ),
              const SizedBox(height: 24),
              CircularProgressIndicator(
                color: FinanceSuitBrand.premiumGold,
                semanticsLabel: l10n.commonLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
