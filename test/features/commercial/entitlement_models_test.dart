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
}
