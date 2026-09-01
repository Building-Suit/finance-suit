import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/src/shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/widgets/app_money_text.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/domain/held_amount.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/finance/presentation/screens/money_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  AccountBalance balance({
    int balanceMinor = 100000,
    int pendingTransferHoldMinor = 0,
    int heldOutgoingMinor = 0,
    int heldIncomingMinor = 0,
  }) => AccountBalance(
    accountId: 'account-1',
    name: 'Wallet',
    accountType: AccountType.wallet,
    currencyCode: 'EGP',
    isDefault: true,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: balanceMinor,
    totalIncomingMinor: 0,
    totalOutgoingMinor: 0,
    pendingTransferHoldMinor: pendingTransferHoldMinor,
    heldOutgoingMinor: heldOutgoingMinor,
    heldIncomingMinor: heldIncomingMinor,
  );

  group('AccountBalance reservations', () {
    test('an account with nothing committed reserves nothing', () {
      final account = balance();
      expect(account.reservedMinor, 0);
      expect(account.availableBalanceMinor, 100000);
      expect(account.hasReservedFunds, isFalse);
      expect(account.hasIncomingHolds, isFalse);
    });

    test('pending transfers and i_owe holds both reduce what is available', () {
      final account = balance(
        pendingTransferHoldMinor: 30000,
        heldOutgoingMinor: 20000,
      );
      expect(account.reservedMinor, 50000);
      expect(account.availableBalanceMinor, 50000);
      expect(account.hasReservedFunds, isTrue);
    });

    test('money owed to me is reported but never raises what I can spend', () {
      final account = balance(heldIncomingMinor: 90000);
      expect(account.heldIncomingMinor, 90000);
      expect(account.reservedMinor, 0);
      // The cash is not in the account, and settling will book it as income.
      expect(account.availableBalanceMinor, 100000);
      expect(account.hasIncomingHolds, isTrue);
    });

    test('available is allowed to go negative', () {
      final account = balance(pendingTransferHoldMinor: 250000);
      expect(account.availableBalanceMinor, -150000);
      // The real balance is untouched: reserving is not spending.
      expect(account.balanceMinor, 100000);
    });

    test('the derived money getters carry the account currency', () {
      final account = balance(pendingTransferHoldMinor: 30000);
      expect(account.reserved.currencyCode, 'EGP');
      expect(account.reserved.minor, 30000);
      expect(account.availableBalance.minor, 70000);
    });
  });

  group('AccountBalance.fromJson', () {
    test('reads the reservation columns when the view provides them', () {
      final account = AccountBalance.fromJson({
        'account_id': 'a1',
        'name': 'Wallet',
        'account_type': 'wallet',
        'currency_code': 'EGP',
        'is_default': true,
        'is_archived': false,
        'allow_negative_balance': false,
        'opening_balance_minor': 0,
        'balance_minor': 100000,
        'total_incoming_minor': 0,
        'total_outgoing_minor': 0,
        'pending_transfer_hold_minor': 30000,
        'held_outgoing_minor': 20000,
        'held_incoming_minor': 5000,
      });
      expect(account.reservedMinor, 50000);
      expect(account.heldIncomingMinor, 5000);
      expect(account.availableBalanceMinor, 50000);
    });

    test('treats missing reservation columns as nothing reserved', () {
      // A client can outrun the migration that adds the columns; that must
      // read as "no holds", not crash the Money tab.
      final account = AccountBalance.fromJson({
        'account_id': 'a1',
        'name': 'Wallet',
        'account_type': 'wallet',
        'currency_code': 'EGP',
        'is_default': true,
        'is_archived': false,
        'allow_negative_balance': false,
        'opening_balance_minor': 0,
        'balance_minor': 100000,
        'total_incoming_minor': 0,
        'total_outgoing_minor': 0,
      });
      expect(account.pendingTransferHoldMinor, 0);
      expect(account.heldOutgoingMinor, 0);
      expect(account.heldIncomingMinor, 0);
      expect(account.availableBalanceMinor, 100000);
    });
  });

  group('Accounts tab', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    Future<void> pumpMoney(WidgetTester tester, AccountBalance account) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountBalancesProvider.overrideWith((ref) async => [account]),
            allAccountBalancesProvider.overrideWith((ref) async => [account]),
            creditFacilitiesProvider.overrideWith(
              (ref) async => const <CreditFacilitySummary>[],
            ),
            allCreditFacilitiesProvider.overrideWith(
              (ref) async => const <CreditFacilitySummary>[],
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
    }

    testWidgets('shows held and available when something is reserved', (
      tester,
    ) async {
      await pumpMoney(tester, balance(pendingTransferHoldMinor: 30000));
      expect(find.text('Held '), findsOneWidget);
      expect(find.text('Available '), findsOneWidget);
    });

    testWidgets('stays quiet when nothing is reserved', (tester) async {
      await pumpMoney(tester, balance());
      expect(find.text('Held '), findsNothing);
      expect(find.text('Available '), findsNothing);
      expect(find.text('Expected '), findsNothing);
    });

    testWidgets('reports money owed to me separately', (tester) async {
      await pumpMoney(tester, balance(heldIncomingMinor: 90000));
      expect(find.text('Expected '), findsOneWidget);
      // Nothing is reserved, so no available line competes with the balance.
      expect(find.text('Available '), findsNothing);
    });

    testWidgets('renders reserved amounts through the money privacy widget', (
      tester,
    ) async {
      // Interpolating money into a Text would bypass the app-wide amount
      // blur, so the amounts must go through AppMoneyText.
      await pumpMoney(tester, balance(pendingTransferHoldMinor: 30000));
      expect(find.byType(AppMoneyText), findsWidgets);
    });
  });
}
