import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';

abstract final class CommercialFeatureKeys {
  static const coreAccounts = 'core_accounts';
  static const transactions = 'transactions';
  static const basicDashboard = 'basic_dashboard';
  static const recurringEntries = 'recurring_entries';
  static const transactionMacros = 'transaction_macros';
  static const incomeAutomation = 'income_automation';
  static const salaryAdvanced = 'salary_advanced';
  static const creditFacilities = 'credit_facilities';
  static const advancedReports = 'advanced_reports';
  static const aiCardResearch = 'ai_card_research';
}

class CommercialRepository {
  CommercialRepository(this._client, {InAppPurchase? purchases})
    : _purchases = purchases ?? InAppPurchase.instance;

  final SupabaseClient _client;
  final InAppPurchase _purchases;

  SupabaseQuerySchema get _db => _client.schema(AppSchemas.commercial);

  Future<Result<CommercialCatalog>> fetchCatalog() {
    return guard(() async {
      final data = await _db.rpc<Map<String, dynamic>>(
        'current_published_catalog',
      );
      return CommercialCatalog.fromJson(data);
    });
  }

  Future<Result<EffectiveEntitlement>> fetchEffectiveEntitlement() {
    return guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'resolve_effective_entitlement',
      );
      if (rows.isEmpty) return EffectiveEntitlement.free();
      return EffectiveEntitlement.fromJson(rows.single as Map<String, dynamic>);
    });
  }

  Future<Result<ProductDetailsResponse>> queryGooglePlayProducts(
    CommercialCatalog catalog,
  ) {
    return guard(() async {
      final ids = catalog.prices
          .where(
            (price) =>
                price.provider == 'google_play' &&
                price.providerProductId != null,
          )
          .map((price) => price.providerProductId!)
          .toSet();
      if (ids.isEmpty) {
        return ProductDetailsResponse(
          productDetails: const [],
          notFoundIDs: const [],
          error: null,
        );
      }
      return _purchases.queryProductDetails(ids);
    });
  }

  Future<Result<void>> buyPro(PlanPrice price, ProductDetails product) {
    return guard(() async {
      final purchaseParam = PurchaseParam(productDetails: product);
      await _purchases.buyNonConsumable(purchaseParam: purchaseParam);
    });
  }

  Future<Result<void>> restorePurchases() {
    return guard(() => _purchases.restorePurchases());
  }

  Stream<List<PurchaseDetails>> get purchaseUpdates =>
      _purchases.purchaseStream;

  Future<Result<EffectiveEntitlement>> verifyGooglePlayPurchase({
    required PlanPrice price,
    required PurchaseDetails purchase,
    required bool restore,
  }) {
    return guard(() async {
      final response = await _client.functions.invoke(
        'google-play-billing',
        body: {
          'action': restore ? 'restore' : 'verify_purchase',
          'provider': 'google_play',
          'productId': price.providerProductId,
          'basePlanId': price.providerBasePlanId,
          'purchaseToken': purchase.verificationData.serverVerificationData,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final entitlement = data['entitlement'] as Map<String, dynamic>?;
      if (entitlement == null) return EffectiveEntitlement.free();
      if (purchase.pendingCompletePurchase) {
        await _purchases.completePurchase(purchase);
      }
      return EffectiveEntitlement.fromJson(entitlement);
    });
  }
}

final commercialRepositoryProvider = Provider<CommercialRepository>(
  (ref) => CommercialRepository(ref.watch(supabaseClientProvider)),
);
