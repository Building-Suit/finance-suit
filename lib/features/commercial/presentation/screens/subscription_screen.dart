import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:work_tracker/app/branding/finance_suit_icons.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/core/widgets/app_toast.dart';
import 'package:work_tracker/core/widgets/async_view.dart';
import 'package:work_tracker/features/commercial/data/commercial_repository.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/providers/commercial_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  Future<void> _buy(
    BuildContext context,
    WidgetRef ref,
    PlanPrice price,
    ProductDetails product,
  ) async {
    final result = await ref
        .read(commercialRepositoryProvider)
        .buyPro(price, product);
    if (!context.mounted) return;
    result.when(
      ok: (_) => AppToast.success(context, 'Google Play checkout opened.'),
      err: (_) => AppToast.error(context, 'Unable to start checkout.'),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(commercialRepositoryProvider)
        .restorePurchases();
    if (!context.mounted) return;
    result.when(
      ok: (_) => AppToast.success(context, 'Restore requested.'),
      err: (_) => AppToast.error(context, 'Unable to restore purchases.'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(purchaseSyncProvider);
    final entitlement = ref.watch(effectiveEntitlementProvider);
    final catalog = ref.watch(commercialCatalogProvider);
    final products = ref.watch(googlePlayProductsProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: FinanceSuitAppBar.focused(semanticTitle: 'Subscription'),
      body: FinanceSuitFocusedBody(
        title: 'Subscription',
        child: AsyncView(
          value: entitlement,
          data: (effective) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(effectiveEntitlementProvider);
              ref.invalidate(commercialCatalogProvider);
              ref.invalidate(googlePlayProductsProvider);
            },
            child: ListView(
              children: [
                _StatusCard(entitlement: effective),
                const SizedBox(height: 16),
                Text(
                  'Finance Suit Free remains available permanently. Pro unlocks advanced automation, salary, facility, reporting, and convenience features without deleting data when access ends.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (effective.source == EntitlementSource.openEarlyAccess)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(l10n.proIncludedEarlyAccess),
                  )
                else ...[
                  const SizedBox(height: 16),
                  Text(
                    'Upgrade options',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  catalog.when(
                    data: (commercialCatalog) => products.when(
                      data: (productResponse) => commercialCatalog.billingReady
                          ? Column(
                              children: [
                                for (final interval in const ['month', 'year'])
                                  _PriceTile(
                                    price: commercialCatalog.googlePlayPrice(
                                      interval,
                                    ),
                                    product: _productFor(
                                      productResponse.productDetails,
                                      commercialCatalog.googlePlayPrice(
                                        interval,
                                      ),
                                    ),
                                    locale: locale,
                                    onBuy: (price, product) =>
                                        _buy(context, ref, price, product),
                                  ),
                              ],
                            )
                          : Text(l10n.billingNotReady),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const Text(
                        'Google Play products are unavailable. Check provider sync.',
                      ),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) =>
                        const Text('Commercial catalog is unavailable.'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _restore(context, ref),
                  icon: const FinanceSuitIcon(FinanceSuitIcons.refresh),
                  label: const Text('Restore purchases'),
                ),
                TextButton.icon(
                  onPressed: () => context.pop(),
                  icon: const FinanceSuitIcon(FinanceSuitIcons.chevronLeft),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ProductDetails? _productFor(List<ProductDetails> products, PlanPrice? price) {
    final id = price?.providerProductId;
    if (id == null) return null;
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.entitlement});

  final EffectiveEntitlement entitlement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = entitlement.endsAt;
    final days = entitlement.daysRemaining(DateTime.now().toUtc());
    final formatter = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
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
                  entitlement.isPro ? 'Finance Suit Pro' : 'Finance Suit Free',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_subtitle(context, entitlement)),
            if (entitlement.source == EntitlementSource.adminGrant &&
                end == null)
              Text(AppLocalizations.of(context).noExpiration),
            if (end != null)
              Text(
                AppLocalizations.of(
                  context,
                ).availableUntil(formatter.format(end.toLocal())),
              ),
            if (days != null &&
                entitlement.source != EntitlementSource.openEarlyAccess)
              Text(AppLocalizations.of(context).daysRemaining(days)),
            if (!entitlement.isPro)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Your Finance Suit data remains safe and Free features continue working.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, EffectiveEntitlement entitlement) {
    final l10n = AppLocalizations.of(context);
    switch (entitlement.source) {
      case EntitlementSource.openEarlyAccess:
        return l10n.proEarlyAccess;
      case EntitlementSource.adminGrant:
        return l10n.complimentaryAccess;
      default:
        return entitlement.sourceLabel;
    }
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({
    required this.price,
    required this.product,
    required this.locale,
    required this.onBuy,
  });

  final PlanPrice? price;
  final ProductDetails? product;
  final String locale;
  final void Function(PlanPrice price, ProductDetails product) onBuy;

  @override
  Widget build(BuildContext context) {
    final price = this.price;
    if (price == null) {
      return const ListTile(title: Text('Price not configured'));
    }
    final interval = price.interval == 'year' ? 'Yearly' : 'Monthly';
    final providerReady =
        product != null && price.providerSyncStatus == 'synced';
    return ListTile(
      leading: const FinanceSuitIcon(FinanceSuitIcons.payments),
      title: Text('$interval Pro'),
      subtitle: Text(
        '${price.money.format(locale: locale)} / ${price.interval}'
        '${providerReady ? '' : '\nGoogle Play sync required before purchase.'}',
      ),
      trailing: FilledButton(
        onPressed: providerReady ? () => onBuy(price, product!) : null,
        child: const Text('Choose'),
      ),
    );
  }
}
