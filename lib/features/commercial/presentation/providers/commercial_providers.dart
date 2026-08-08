import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/commercial/data/commercial_repository.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';

final commercialCatalogProvider = FutureProvider<CommercialCatalog>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref.watch(commercialRepositoryProvider).fetchCatalog();
  return result.when(ok: (catalog) => catalog, err: (failure) => throw failure);
});

final effectiveEntitlementProvider = FutureProvider<EffectiveEntitlement>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final result = await ref
      .watch(commercialRepositoryProvider)
      .fetchEffectiveEntitlement();
  return result.when(
    ok: (entitlement) => entitlement,
    err: (failure) => throw failure,
  );
});

final googlePlayProductsProvider = FutureProvider<ProductDetailsResponse>((
  ref,
) async {
  final catalog = await ref.watch(commercialCatalogProvider.future);
  final result = await ref
      .watch(commercialRepositoryProvider)
      .queryGooglePlayProducts(catalog);
  return result.when(
    ok: (response) => response,
    err: (failure) => throw failure,
  );
});

class PurchaseSyncController extends AsyncNotifier<void> {
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  Future<void> build() async {
    final repository = ref.watch(commercialRepositoryProvider);
    _subscription = repository.purchaseUpdates.listen(_handlePurchases);
    ref.onDispose(() => _subscription?.cancel());
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;
      if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        continue;
      }
      await ref
          .read(commercialRepositoryProvider)
          .verifyGooglePlayPurchase(
            purchase: purchase,
            restore: purchase.status == PurchaseStatus.restored,
          );
      ref.invalidate(effectiveEntitlementProvider);
    }
  }
}

final purchaseSyncProvider =
    AsyncNotifierProvider<PurchaseSyncController, void>(
      PurchaseSyncController.new,
    );
