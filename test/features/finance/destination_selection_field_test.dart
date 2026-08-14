import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/money_destination.dart';
import 'package:work_tracker/features/finance/presentation/widgets/destination_selection_field.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

void main() {
  const cash = AccountBalance(
    accountId: 'account-cash',
    name: 'Cash',
    accountType: AccountType.cash,
    currencyCode: 'EGP',
    isDefault: true,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 2500000,
    totalIncomingMinor: 0,
    totalOutgoingMinor: 0,
  );
  final wife = NetworkContact(
    connectionId: 'connection-1',
    otherUserId: 'user-2',
    localAlias: 'Wife',
    realDisplayName: 'Mona Ahmed',
    email: 'mona@example.com',
    connectedAt: DateTime.utc(2026, 8, 1),
  );

  Future<void> pumpField(
    WidgetTester tester, {
    required List<NetworkContact> contacts,
    required ValueChanged<MoneyDestination?> onChanged,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Form(
              child: DestinationSelectionField(
                accounts: const [cash],
                contacts: contacts,
                onChanged: onChanged,
                decoration: const InputDecoration(labelText: 'To'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups own accounts and network contacts without balances', (
    tester,
  ) async {
    MoneyDestination? selected;
    await pumpField(
      tester,
      contacts: [wife],
      onChanged: (value) => selected = value,
    );

    await tester.tap(find.byType(DestinationSelectionField));
    await tester.pumpAndSettle();

    expect(find.text('My accounts'), findsOneWidget);
    expect(find.text('My network'), findsOneWidget);
    // The own account row carries its balance; the network row never does.
    expect(find.textContaining('Cash ('), findsOneWidget);
    expect(find.textContaining('Wife — Network contact'), findsOneWidget);
    expect(find.textContaining('Wife ('), findsNothing);

    await tester.tap(find.textContaining('Wife — Network contact'));
    await tester.pumpAndSettle();
    expect(selected, const NetworkContactDestination('connection-1'));
  });

  testWidgets('selecting an own account returns the typed account shape', (
    tester,
  ) async {
    MoneyDestination? selected;
    await pumpField(
      tester,
      contacts: [wife],
      onChanged: (value) => selected = value,
    );

    await tester.tap(find.byType(DestinationSelectionField));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cash ('));
    await tester.pumpAndSettle();
    expect(selected, const OwnAccountDestination('account-cash'));
  });

  testWidgets('without contacts there are no group rows at all', (
    tester,
  ) async {
    await pumpField(tester, contacts: const [], onChanged: (_) {});

    await tester.tap(find.byType(DestinationSelectionField));
    await tester.pumpAndSettle();

    expect(find.text('My accounts'), findsNothing);
    expect(find.text('My network'), findsNothing);
    expect(find.textContaining('Cash ('), findsOneWidget);
  });
}
