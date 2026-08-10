import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/widgets/subscription_status_strip.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  const free = EffectiveEntitlement(
    plan: CommercialPlan.free,
    source: EntitlementSource.free,
    startsAt: null,
    endsAt: null,
    subscriptionStatus: null,
    renewalAt: null,
    features: {},
    limits: {},
    metadata: {},
  );
  const pro = EffectiveEntitlement(
    plan: CommercialPlan.pro,
    source: EntitlementSource.paid,
    startsAt: null,
    endsAt: null,
    subscriptionStatus: 'active',
    renewalAt: null,
    features: {},
    limits: {},
    metadata: {},
  );
  const earlyAccess = EffectiveEntitlement(
    plan: CommercialPlan.pro,
    source: EntitlementSource.openEarlyAccess,
    startsAt: null,
    endsAt: null,
    subscriptionStatus: null,
    renewalAt: null,
    features: {},
    limits: {},
    metadata: {},
  );

  Future<void> pumpStrip(
    WidgetTester tester, {
    required EffectiveEntitlement entitlement,
    bool visible = true,
    VoidCallback? onUpgrade,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: SubscriptionStatusStrip(
              entitlement: entitlement,
              visible: visible,
              onUpgrade: onUpgrade ?? () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('uses one slim geometry for every entitlement state', (
    tester,
  ) async {
    for (final entitlement in [free, pro, earlyAccess]) {
      await pumpStrip(tester, entitlement: entitlement);
      expect(
        tester.getSize(find.byKey(const Key('subscription-status-strip'))),
        const Size(320, SubscriptionStatusStrip.height),
      );
    }
  });

  testWidgets('shows the approved Free upgrade copy and keeps it interactive', (
    tester,
  ) async {
    var upgradeCalls = 0;
    await pumpStrip(tester, entitlement: free, onUpgrade: () => upgradeCalls++);

    expect(find.text('Free — click here to upgrade'), findsOneWidget);
    await tester.tap(find.byKey(const Key('subscription-status-strip')));
    expect(upgradeCalls, 1);
  });

  testWidgets('uses compact Pro and Pro Early Access labels', (tester) async {
    await pumpStrip(tester, entitlement: pro);
    expect(find.text('Pro'), findsOneWidget);

    await pumpStrip(tester, entitlement: earlyAccess);
    expect(find.text('Pro Early Access'), findsOneWidget);
  });
}
