import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/branding/finance_suit_mark.dart';
import 'package:work_tracker/app/routing/finance_suit_app_bar.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/features/commercial/domain/commercial_models.dart';
import 'package:work_tracker/features/commercial/presentation/widgets/subscription_status_strip.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/domain/transaction_query.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/money_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  const menuButton = Key('finance-suit-menu-button');

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    required PreferredSizeWidget appBar,
    Locale locale = const Locale('en'),
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(locale: locale),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => disableAnimations
              ? MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                )
              : child!,
          home: Scaffold(appBar: appBar, body: const SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('top-level header centers the logo with a start hamburger', (
    tester,
  ) async {
    await pumpBar(
      tester,
      appBar: const FinanceSuitAppBar.topLevel(semanticTitle: 'Home'),
    );

    final width = tester.getSize(find.byType(MaterialApp)).width;
    final logo = tester.getCenter(find.byType(FinanceSuitMark));
    final hamburger = tester.getCenter(find.byKey(menuButton));
    expect(logo.dx, closeTo(width / 2, 1.0));
    expect(hamburger.dx, lessThan(width / 4));
    // No visible page title.
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('Home header keeps the logo centered while its surface morphs', (
    tester,
  ) async {
    await pumpBar(
      tester,
      appBar: const FinanceSuitHomeAppBar(
        semanticTitle: 'Home',
        isSolid: false,
      ),
    );

    final surface = find.byKey(const Key('finance-suit-home-header-surface'));
    final width = tester.getSize(find.byType(MaterialApp)).width;
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      const EdgeInsetsDirectional.symmetric(horizontal: 16),
    );
    expect(
      tester.getCenter(find.byType(FinanceSuitMark)).dx,
      closeTo(width / 2, 1.0),
    );
    expect(
      find.byKey(const Key('finance-suit-notifications-button')),
      findsOneWidget,
    );

    await pumpBar(
      tester,
      appBar: const FinanceSuitHomeAppBar(semanticTitle: 'Home', isSolid: true),
    );
    expect(
      tester.widget<AnimatedContainer>(surface).margin,
      EdgeInsetsDirectional.zero,
    );
    expect(
      tester.getCenter(find.byType(FinanceSuitMark)).dx,
      closeTo(width / 2, 1.0),
    );
  });

  testWidgets('Home header disables its motion when requested by the device', (
    tester,
  ) async {
    await pumpBar(
      tester,
      appBar: const FinanceSuitHomeAppBar(
        semanticTitle: 'Home',
        isSolid: false,
      ),
      disableAnimations: true,
    );

    expect(
      tester
          .widget<AnimatedContainer>(
            find.byKey(const Key('finance-suit-home-header-surface')),
          )
          .duration,
      Duration.zero,
    );
  });

  testWidgets('Home status rail tucks under the floating header and retracts', (
    tester,
  ) async {
    const entitlement = EffectiveEntitlement(
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
    const appBar = FinanceSuitHomeAppBar(
      semanticTitle: 'Home',
      isSolid: false,
      entitlement: entitlement,
    );
    await pumpBar(tester, appBar: appBar);

    final surface = find.byKey(const Key('finance-suit-home-header-surface'));
    final strip = find.byKey(const Key('subscription-status-strip'));
    final surfaceRect = tester.getRect(surface);
    final stripRect = tester.getRect(strip);
    expect(stripRect.top, lessThan(surfaceRect.bottom));
    expect(stripRect.bottom, greaterThan(surfaceRect.bottom));
    expect(stripRect.width, closeTo((surfaceRect.width - 32) * 0.9, 1));
    expect(appBar.preferredSize.height, 80);

    await pumpBar(
      tester,
      appBar: const FinanceSuitHomeAppBar(
        semanticTitle: 'Home',
        isSolid: true,
        entitlement: entitlement,
      ),
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(SubscriptionStatusStrip),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
    expect(
      const FinanceSuitHomeAppBar(
        semanticTitle: 'Home',
        isSolid: true,
        entitlement: entitlement,
      ).preferredSize.height,
      kToolbarHeight,
    );
  });

  testWidgets('RTL mirrors the hamburger but never the logo artwork', (
    tester,
  ) async {
    await pumpBar(
      tester,
      appBar: const FinanceSuitAppBar.topLevel(semanticTitle: 'الرئيسية'),
      locale: const Locale('ar'),
    );

    final width = tester.getSize(find.byType(MaterialApp)).width;
    final logo = tester.getCenter(find.byType(FinanceSuitMark));
    final hamburger = tester.getCenter(find.byKey(menuButton));
    expect(logo.dx, closeTo(width / 2, 1.0));
    expect(hamburger.dx, greaterThan(width * 3 / 4));
    // The brand artwork must not be mirrored for RTL.
    expect(
      find.ancestor(
        of: find.byType(FinanceSuitMark),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('focused header shows Back at the start and the logo centered', (
    tester,
  ) async {
    await pumpBar(
      tester,
      appBar: const FinanceSuitAppBar.focused(semanticTitle: 'Details'),
    );
    final width = tester.getSize(find.byType(MaterialApp)).width;
    expect(find.byKey(const Key('finance-suit-back-button')), findsOneWidget);
    expect(find.byKey(menuButton), findsNothing);
    expect(
      tester.getCenter(find.byType(FinanceSuitMark)).dx,
      closeTo(width / 2, 1.0),
    );
    expect(find.text('Details'), findsNothing);
  });

  testWidgets('focused body renders the visible contextual title', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            appBar: FinanceSuitAppBar.focused(semanticTitle: 'Details'),
            body: FinanceSuitFocusedBody(title: 'Details', child: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The title lives in the page content, not in the AppBar.
    final title = tester.getCenter(find.text('Details'));
    final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(title.dy, greaterThan(appBarBottom));
  });

  testWidgets('announces the screen name as a semantic header', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpBar(
      tester,
      appBar: const FinanceSuitAppBar.topLevel(semanticTitle: 'Home'),
    );
    expect(
      tester.getSemantics(find.byType(FinanceSuitMark)),
      matchesSemantics(label: 'Home', isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets(
    'real Money screen keeps its internal tabs under the new header',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allAccountBalancesProvider.overrideWith(
              (ref) async => const <AccountBalance>[],
            ),
            transactionsPageProvider.overrideWith(
              (ref, query) async =>
                  const TransactionPage(items: [], hasMore: false),
            ),
            heldAmountsProvider.overrideWith(
              (ref) async => const <HeldAmount>[],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const MoneyScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Canonical header: hamburger + centered logo, no Money title, no
      // icon-only Macros/Categories shortcuts.
      expect(find.byKey(menuButton), findsOneWidget);
      expect(find.byType(FinanceSuitMark), findsOneWidget);
      expect(find.text('Money'), findsNothing);
      expect(find.byTooltip('Macros'), findsNothing);
      expect(find.byTooltip('Manage categories'), findsNothing);

      // The Accounts/Transactions/Held TabBar is preserved.
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Held'), findsOneWidget);
    },
  );

  testWidgets('Money header and tabs fit 320x480 in Arabic', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allAccountBalancesProvider.overrideWith(
            (ref) async => const <AccountBalance>[],
          ),
          transactionsPageProvider.overrideWith(
            (ref, query) async =>
                const TransactionPage(items: [], hasMore: false),
          ),
          heldAmountsProvider.overrideWith((ref) async => const <HeldAmount>[]),
        ],
        child: MaterialApp(
          theme: AppTheme.light(locale: const Locale('ar')),
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MoneyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
