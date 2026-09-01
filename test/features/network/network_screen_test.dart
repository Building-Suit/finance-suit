import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/presentation/providers/finance_providers.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/network/presentation/screens/network_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _MockNetworkRepository extends Mock implements NetworkRepository {}

void main() {
  final contact = NetworkContact(
    connectionId: 'connection-1',
    otherUserId: 'user-2',
    localAlias: 'Wife',
    realDisplayName: 'Mona Ahmed',
    email: 'mona@example.com',
    connectedAt: DateTime.utc(2026, 8, 1),
  );
  final incomingRequest = NetworkAddRequest(
    id: 'request-1',
    direction: NetworkDirection.incoming,
    otherUserId: 'user-3',
    otherDisplayName: 'Tarek Abdelwahab',
    otherEmail: 'tarek@example.com',
    status: NetworkAddRequestStatus.pending,
    requestedAt: DateTime.utc(2026, 8, 10),
  );
  final sentRequest = NetworkAddRequest(
    id: 'request-2',
    direction: NetworkDirection.outgoing,
    otherUserId: 'user-4',
    otherDisplayName: 'Ahmed Work',
    otherEmail: 'ahmed@example.com',
    myAlias: 'Ahmed',
    status: NetworkAddRequestStatus.rejected,
    requestedAt: DateTime.utc(2026, 8, 9),
    respondedAt: DateTime.utc(2026, 8, 9, 12),
  );
  final incomingTransfer = NetworkTransfer(
    id: 'transfer-1',
    direction: NetworkDirection.incoming,
    counterpartyAlias: 'Tarek',
    amountMinor: 50000,
    currencyCode: 'EGP',
    status: NetworkTransferStatus.pending,
    requestedOn: const PlainDate(2026, 8, 14),
    requestedAt: DateTime.utc(2026, 8, 14, 9),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-1',
    sharedNote: 'rent share',
  );
  const egpAccount = AccountBalance(
    accountId: 'account-egp',
    name: 'Wallet',
    accountType: AccountType.wallet,
    currencyCode: 'EGP',
    isDefault: true,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 1000,
    totalIncomingMinor: 0,
    totalOutgoingMinor: 0,
  );
  const usdAccount = AccountBalance(
    accountId: 'account-usd',
    name: 'Dollars',
    accountType: AccountType.current,
    currencyCode: 'USD',
    isDefault: false,
    isArchived: false,
    allowNegativeBalance: false,
    openingBalanceMinor: 0,
    balanceMinor: 0,
    totalIncomingMinor: 0,
    totalOutgoingMinor: 0,
  );

  late _MockNetworkRepository repository;

  setUp(() {
    repository = _MockNetworkRepository();
  });

  Future<void> pumpNetworkScreen(
    WidgetTester tester, {
    int initialTab = 0,
    List<NetworkContact> contacts = const [],
    List<NetworkAddRequest> requests = const [],
    List<NetworkTransfer> transfers = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWithValue(repository),
          networkContactsProvider.overrideWith((ref) async => contacts),
          networkAddRequestsProvider.overrideWith((ref) async => requests),
          networkTransfersProvider.overrideWith((ref) async => transfers),
          accountBalancesProvider.overrideWith(
            (ref) async => const [egpAccount, usdAccount],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NetworkScreen(initialTab: initialTab),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('connections show my alias with the real identity secondary', (
    tester,
  ) async {
    await pumpNetworkScreen(tester, contacts: [contact]);
    expect(find.text('Wife'), findsOneWidget);
    expect(find.textContaining('Mona Ahmed'), findsOneWidget);
    expect(find.textContaining('mona@example.com'), findsOneWidget);
  });

  testWidgets('an incoming request shows real identity and both decisions', (
    tester,
  ) async {
    await pumpNetworkScreen(
      tester,
      initialTab: 1,
      requests: [incomingRequest, sentRequest],
    );
    expect(find.text('Tarek Abdelwahab'), findsOneWidget);
    expect(find.text('tarek@example.com'), findsOneWidget);
    expect(
      find.text('wants to add you to their Finance Suit network.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('network-accept-request-1')), findsOneWidget);
    expect(find.byKey(const Key('network-reject-request-1')), findsOneWidget);
    // The sent section shows my own alias and the outcome.
    expect(find.textContaining('Ahmed'), findsWidgets);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('accepting a request asks for my own alias first', (
    tester,
  ) async {
    when(
      () => repository.acceptAddRequest(
        requestId: any(named: 'requestId'),
        localAlias: any(named: 'localAlias'),
      ),
    ).thenAnswer((_) async => const Ok('connection-9'));
    await pumpNetworkScreen(tester, initialTab: 1, requests: [incomingRequest]);

    await tester.tap(find.byKey(const Key('network-accept-request-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('What do you want to call Tarek Abdelwahab?'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('network-alias-field')),
      '  Tarek  ',
    );
    await tester.tap(find.byKey(const Key('network-alias-save')));
    await tester.pumpAndSettle();

    verify(
      () => repository.acceptAddRequest(
        requestId: 'request-1',
        localAlias: 'Tarek',
      ),
    ).called(1);
  });

  testWidgets('rejecting a request never asks for an alias', (tester) async {
    when(
      () => repository.rejectAddRequest(any()),
    ).thenAnswer((_) async => const Ok(null));
    await pumpNetworkScreen(tester, initialTab: 1, requests: [incomingRequest]);

    await tester.tap(find.byKey(const Key('network-reject-request-1')));
    await tester.pumpAndSettle();

    verify(() => repository.rejectAddRequest('request-1')).called(1);
    expect(find.byKey(const Key('network-alias-field')), findsNothing);
  });

  testWidgets('an incoming pending transfer offers accept and reject', (
    tester,
  ) async {
    await pumpNetworkScreen(
      tester,
      initialTab: 2,
      transfers: [incomingTransfer],
    );
    expect(find.text('From Tarek'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(
      find.byKey(const Key('network-transfer-accept-transfer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('network-transfer-reject-transfer-1')),
      findsOneWidget,
    );
  });

  testWidgets('accepting lists only my own matching-currency accounts', (
    tester,
  ) async {
    when(
      () => repository.acceptTransfer(
        transferId: any(named: 'transferId'),
        destinationAccountId: any(named: 'destinationAccountId'),
        expectedAmountMinor: any(named: 'expectedAmountMinor'),
      ),
    ).thenAnswer((_) async => const Ok('transfer-1'));
    await pumpNetworkScreen(
      tester,
      initialTab: 2,
      transfers: [incomingTransfer],
    );

    await tester.tap(
      find.byKey(const Key('network-transfer-accept-transfer-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Receive into'), findsOneWidget);
    expect(
      find.byKey(const Key('network-receive-account-egp')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('network-receive-account-usd')), findsNothing);

    await tester.tap(find.byKey(const Key('network-receive-account-egp')));
    await tester.pumpAndSettle();

    // The amount the receiver was actually shown travels with the acceptance,
    // so the server can refuse it if the sender amended the request meanwhile.
    verify(
      () => repository.acceptTransfer(
        transferId: 'transfer-1',
        destinationAccountId: 'account-egp',
        expectedAmountMinor: 50000,
      ),
    ).called(1);
  });

  testWidgets('a sent transfer shows status without receiver actions', (
    tester,
  ) async {
    final sent = NetworkTransfer(
      id: 'transfer-2',
      direction: NetworkDirection.outgoing,
      counterpartyAlias: 'Wife',
      amountMinor: 200000,
      currencyCode: 'EGP',
      status: NetworkTransferStatus.accepted,
      requestedOn: const PlainDate(2026, 8, 10),
      requestedAt: DateTime.utc(2026, 8, 10, 9),
      origin: NetworkTransferOrigin.manual,
      connectionActive: true,
      connectionId: 'connection-1',
    );
    await pumpNetworkScreen(tester, initialTab: 2, transfers: [sent]);

    await tester.tap(find.byKey(const Key('network-filter-accepted')));
    await tester.pumpAndSettle();
    expect(find.text('To Wife'), findsOneWidget);
    expect(find.text('Accepted'), findsWidgets);
    expect(
      find.byKey(const Key('network-transfer-accept-transfer-2')),
      findsNothing,
    );
  });
}
