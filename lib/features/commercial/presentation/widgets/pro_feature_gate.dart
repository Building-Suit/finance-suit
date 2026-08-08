import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/app_router.dart';
import 'package:work_tracker/features/commercial/presentation/providers/commercial_providers.dart';

class ProFeatureGate extends ConsumerWidget {
  const ProFeatureGate({
    super.key,
    required this.featureKey,
    required this.child,
    this.locked,
  });

  final String featureKey;
  final Widget child;
  final Widget? locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlement = ref.watch(effectiveEntitlementProvider).value;
    if (entitlement?.hasFeature(featureKey) ?? true) return child;
    return locked ?? const ProUpgradeInline();
  }
}

class ProUpgradeInline extends StatelessWidget {
  const ProUpgradeInline({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FinanceSuitIcon(FinanceSuitIcons.star),
                const SizedBox(width: 8),
                Text(
                  'Finance Suit Pro',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'This Pro capability is unavailable on your current plan. Your existing Finance Suit data remains safe on Free.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.subscription),
              icon: const FinanceSuitIcon(FinanceSuitIcons.payments),
              label: const Text('View Pro options'),
            ),
          ],
        ),
      ),
    );
  }
}
