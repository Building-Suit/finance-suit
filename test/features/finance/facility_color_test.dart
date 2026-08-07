import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/app/theme/facility_palette.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/account_form_screen.dart';
import 'package:work_tracker/features/finance/presentation/widgets/finance_widgets.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

CreditFacilitySummary _facility({String? colorHex, String name = 'Visa'}) =>
    CreditFacilitySummary(
      accountId: 'card-1',
      name: name,
      accountType: AccountType.creditCard,
      currencyCode: 'EGP',
      isArchived: false,
      openingOwedMinor: 0,
      creditLimitMinor: 500000,
      defaultDueDay: 10,
      reminderLeadDays: 3,
      outstandingMinor: 100000,
      availableCreditMinor: 400000,
      utilizationBasisPoints: 2000,
      dueNowMinor: 0,
      overdueMinor: 0,
      activePlanCount: 0,
      statementDay: 5,
      colorHex: colorHex,
    );

void main() {
  group('swatches', () {
    test('every offered swatch round-trips and carries white text', () {
      for (final color in FacilitySwatches.values) {
        final hex = FacilitySwatches.hexOf(color);
        expect(RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex), isTrue, reason: hex);
        // What is stored is what comes back.
        expect(FacilitySwatches.parse(hex), color);
        // The picker only offers colours dark enough for white foreground,
        // which is what keeps every card's figures legible.
        expect(onFacilitySwatch(color).computeLuminance(), greaterThan(0.9));
      }
    });

    test('a malformed or absent colour degrades to no colour', () {
      expect(FacilitySwatches.parse(null), isNull);
      expect(FacilitySwatches.parse(''), isNull);
      expect(FacilitySwatches.parse('#12345'), isNull);
      expect(FacilitySwatches.parse('1F3A5F'), isNull);
      expect(FacilitySwatches.parse('#zzzzzz'), isNull);
    });

    test('a stored colour parses case-insensitively', () {
      final navy = FacilitySwatches.values.first;
      final hex = FacilitySwatches.hexOf(navy);
      expect(FacilitySwatches.parse(hex.toLowerCase()), navy);
      expect(FacilitySwatches.parse(' $hex '), navy);
    });
  });

  group('facility palette', () {
    testWidgets('no colour keeps the brand surface', (tester) async {
      late FacilityPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              palette = facilityPalette(context, null);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(palette.isCustom, isFalse);
    });

    testWidgets('a colour becomes the surface with a readable foreground', (
      tester,
    ) async {
      late FacilityPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              palette = facilityPalette(
                context,
                FacilitySwatches.hexOf(FacilitySwatches.values[3]),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(palette.isCustom, isTrue);
      expect(palette.surface, FacilitySwatches.values[3]);
      expect(palette.onSurface.computeLuminance(), greaterThan(0.9));
      expect(palette.onSurfaceMuted.a, lessThan(1.0));
    });
  });

  group('money list', () {
    Future<void> pumpTile(
      WidgetTester tester,
      CreditFacilitySummary facility,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: FacilityTile(facility: facility)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a coloured facility shows its swatch', (tester) async {
      final chosen = FacilitySwatches.values[5];
      await pumpTile(
        tester,
        _facility(colorHex: FacilitySwatches.hexOf(chosen)),
      );

      final swatch = find.byKey(const Key('facility-swatch-card-1'));
      expect(swatch, findsOneWidget);
      final decoration =
          tester.widget<Container>(swatch).decoration! as BoxDecoration;
      expect(decoration.color, chosen);
    });

    testWidgets('an uncoloured facility shows no swatch', (tester) async {
      await pumpTile(tester, _facility());

      expect(find.byKey(const Key('facility-swatch-card-1')), findsNothing);
    });
  });

  group('account form', () {
    testWidgets('a liability account offers the colour picker', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('user-1'),
            allAccountBalancesProvider.overrideWith(
              (ref) async => const <AccountBalance>[],
            ),
            allCreditFacilitiesProvider.overrideWith(
              (ref) async => const <CreditFacilitySummary>[],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AccountFormScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cash accounts do not carry a card colour.
      expect(find.byKey(const Key('facility-color-default')), findsNothing);

      await tester.tap(find.text('Current balance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'BNPL');
      await tester.pumpAndSettle();
      await tester.tap(find.text('BNPL / Finance Company').last);
      await tester.pumpAndSettle();

      final defaultSwatch = find.byKey(const Key('facility-color-default'));
      expect(defaultSwatch, findsOneWidget);
      // BNPL gets colours too, not just credit cards.
      expect(
        find.byKey(
          Key(
            'facility-color-'
            '${FacilitySwatches.hexOf(FacilitySwatches.values.first)}',
          ),
        ),
        findsOneWidget,
      );

      final chosen = find.byKey(
        Key(
          'facility-color-'
          '${FacilitySwatches.hexOf(FacilitySwatches.values[1])}',
        ),
      );
      await tester.ensureVisible(chosen);
      await tester.tap(chosen);
      await tester.pumpAndSettle();

      // The picked swatch shows the check, and Default releases it.
      expect(
        find.descendant(of: chosen, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: defaultSwatch, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
