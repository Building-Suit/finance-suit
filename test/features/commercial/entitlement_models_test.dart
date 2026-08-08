import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';

void main() {
  test('daysRemaining uses UTC timestamps and rounds partial days up', () {
    final entitlement = EffectiveEntitlement(
      plan: CommercialPlan.pro,
      source: EntitlementSource.earlyAccess,
      startsAt: DateTime.utc(2026, 8, 8, 12),
      endsAt: DateTime.utc(2026, 8, 10, 11),
      subscriptionStatus: null,
      renewalAt: null,
      features: const {},
      limits: const {},
      metadata: {},
    );

    expect(entitlement.daysRemaining(DateTime.utc(2026, 8, 8, 12)), 2);
    expect(entitlement.daysRemaining(DateTime.utc(2026, 8, 10, 12)), 0);
  });

  test('feature map and limits are centralized on entitlement model', () {
    const entitlement = EffectiveEntitlement(
      plan: CommercialPlan.pro,
      source: EntitlementSource.paid,
      startsAt: null,
      endsAt: null,
      subscriptionStatus: 'active',
      renewalAt: null,
      features: {'transaction_macros': true, 'ai_card_research': false},
      limits: {'transaction_macros': null, 'ai_card_research': 0},
      metadata: {},
    );

    expect(entitlement.isPro, isTrue);
    expect(entitlement.hasFeature('transaction_macros'), isTrue);
    expect(entitlement.hasFeature('ai_card_research'), isFalse);
    expect(entitlement.featureLimit('ai_card_research'), 0);
  });

  test('tester access permits a configured provider without granting Pro', () {
    final catalog = CommercialCatalog.fromJson({
      'prices': const <dynamic>[],
      'monetization': const {'mode': 'open_early_access'},
      'billing_readiness': const {
        'provider': 'synced',
        'product': 'synced',
        'verification': 'not_verified',
      },
      'billing_test_access': true,
    });

    expect(catalog.billingTestAccess, isTrue);
    expect(catalog.googlePlayConfigured, isTrue);
    expect(catalog.billingReady, isFalse);
    expect(EffectiveEntitlement.free().isPro, isFalse);
  });

  test(
    'Google Play offers require the configured base plan, not product ID',
    () {
      final monthly = PlanPrice.fromJson({
        'id': 'monthly',
        'plan_key': 'pro',
        'provider': 'google_play',
        'interval': 'month',
        'amount_minor': 9900,
        'currency_code': 'EGP',
        'provider_product_id': 'finance_suit_pro',
        'provider_base_plan_id': 'pro-monthly-egp',
        'provider_sync_status': 'synced',
      });

      expect(
        monthly.matchesGooglePlayOffer(
          productId: 'finance_suit_pro',
          basePlanId: 'pro-monthly-egp',
          offerToken: 'monthly-token',
        ),
        isTrue,
      );
      expect(
        monthly.matchesGooglePlayOffer(
          productId: 'finance_suit_pro',
          basePlanId: 'pro-yearly-egp',
          offerToken: 'yearly-token',
        ),
        isFalse,
        reason: 'the shared product ID must not select the annual base plan',
      );
    },
  );

  test('Google Play price mismatch is rejected before checkout', () {
    final price = PlanPrice.fromJson({
      'id': 'monthly',
      'plan_key': 'pro',
      'provider': 'google_play',
      'interval': 'month',
      'amount_minor': 9900,
      'currency_code': 'EGP',
      'provider_product_id': 'finance_suit_pro',
      'provider_base_plan_id': 'pro-monthly-egp',
      'provider_sync_status': 'synced',
    });

    expect(
      price.matchesGooglePlayPrice(currencyCode: 'EGP', rawPrice: 99),
      isTrue,
    );
    expect(
      price.matchesGooglePlayPrice(currencyCode: 'USD', rawPrice: 99),
      isFalse,
    );
    expect(
      price.matchesGooglePlayPrice(currencyCode: 'EGP', rawPrice: 109),
      isFalse,
    );
  });
}
