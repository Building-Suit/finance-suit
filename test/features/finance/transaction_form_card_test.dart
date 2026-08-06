import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/transaction_category.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/transaction_form_screen.dart';
import 'package:work_tracker/features/settings/domain/user_profile.dart';
import 'package:work_tracker/features/settings/presentation/providers/settings_data_providers.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

/// A credit card that cannot take charges yet must stay visible in the
/// expense form's account picker and explain what it is missing — hiding
/// it read as "cards cannot take expenses at all".
void main() {
  const wallet = AccountBalance(
    accountId: 'wallet',
    name: 'Wallet',
    accountType: AccountType.cash,
    currencyCode: 'EGP',
    isDefault: true,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 100000,
    totalIncomingMinor: 100000,
    totalOutgoingMinor: 0,
  );
  const unconfiguredCard = CreditFacilitySummary(
    accountId: 'card-1',
    name: 'Everyday Card',
    accountType: AccountType.creditCard,
    currencyCode: 'EGP',
    isArchived: false,
    openingOwedMinor: 0,
    creditLimitMinor: 5000000,
    defaultDueDay: 10,
    reminderLeadDays: 3,
    outstandingMinor: 0,
    availableCreditMinor: 5000000,
    utilizationBasisPoints: 0,
    dueNowMinor: 0,
    overdueMinor: 0,
    activePlanCount: 0,
  );
  const prefs = UserPreferences(
    currencyCode: 'EGP',
    timezone: 'Africa/Cairo',
    locale: 'en',
    weekStartsOn: 6,
    weekendDays: [5, 6],
    defaultHistoryDays: 30,
    onboardingCompleted: true,
  );

  testWidgets('an unconfigured card is listed and explains what it needs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          accountBalancesProvider.overrideWith((ref) async => const [wallet]),
          creditFacilitiesProvider.overrideWith(
            (ref) async => const [unconfiguredCard],
          ),
          categoriesProvider.overrideWith(
            (ref, kind) async => const <TransactionCategory>[],
          ),
          preferencesProvider.overrideWith((ref) async => prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TransactionFormScreen(kind: TransactionKind.expense),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The card is offered even though it cannot charge yet.
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Everyday Card'), findsOneWidget);
    await tester.tap(find.textContaining('Everyday Card'));
    await tester.pumpAndSettle();

    // Picking it surfaces the missing statement day and a way to fix it.
    expect(find.byKey(const Key('card-charge-blocked')), findsOneWidget);
    expect(
      find.text("Set the card's statement closing day first"),
      findsOneWidget,
    );
    expect(find.text('Open card settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
