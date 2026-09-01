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
import 'package:work_tracker/features/network/domain/held_against_me.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/providers/network_providers.dart';
import 'package:work_tracker/features/network/presentation/screens/network_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _MockNetworkRepository extends Mock implements NetworkRepository {}

void main() {
  NetworkTransfer sent({
    NetworkTransferStatus status = NetworkTransferStatus.pending,
    bool canAmend = true,
    int amendmentCount = 0,
  }) => NetworkTransfer(
    id: 'transfer-1',
    direction: NetworkDirection.outgoing,
    counterpartyAlias: 'Tarek',
    amountMinor: 50000,
    currencyCode: 'EGP',
    status: status,
    requestedOn: const PlainDate(2026, 8, 14),
    requestedAt: DateTime.utc(2026, 8, 14, 9),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-1',
    myAccountId: 'account-egp',
    canAmend: canAmend,
    amendmentCount: amendmentCount,
  );

  final received = NetworkTransfer(
    id: 'transfer-2',
    direction: NetworkDirection.incoming,
    counterpartyAlias: 'Mona',
    amountMinor: 20000,
    currencyCode: 'EGP',
    status: NetworkTransferStatus.pending,
    requestedOn: const PlainDate(2026, 8, 14),
    requestedAt: DateTime.utc(2026, 8, 14, 9),
    origin: NetworkTransferOrigin.manual,
    connectionActive: true,
    connectionId: 'connection-2',
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
    balanceMinor: 100000,
    totalIncomingMinor: 0,
    totalOutgoingMinor: 0,
  );

  late _MockNetworkRepository repository;

  setUp(() {
    repository = _MockNetworkRepository();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<NetworkTransfer> transfers = const [],
    List<HeldAgainstMe> holds = const [],
    int initialTab = 2,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWithValue(repository),
          networkContactsProvider.overrideWith((ref) async => const []),
          networkAddRequestsProvider.overrideWith((ref) async => const []),
          networkTransfersProvider.overrideWith((ref) async => transfers),
          holdsAgainstMeProvider.overrideWith((ref) async => holds),
          accountBalancesProvider.overrideWith(
            (ref) async => const [egpAccount],
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

  testWidgets('my own pending transfer offers withdraw and change', (
    tester,
  ) async {
    await pump(tester, transfers: [sent()]);
    expect(
      find.byKey(const Key('network-transfer-cancel-transfer-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('network-transfer-amend-transfer-1')),
      findsOneWidget,
    );
  });

  testWidgets('a transfer someone sent me offers neither', (tester) async {
    await pump(tester, transfers: [received]);
    expect(
      find.byKey(const Key('network-transfer-cancel-transfer-2')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('network-transfer-amend-transfer-2')),
      findsNothing,
    );
  });

  testWidgets('an already-decided transfer offers neither', (tester) async {
    await pump(
      tester,
      transfers: [
        sent(status: NetworkTransferStatus.accepted, canAmend: false),
      ],
    );
    expect(
      find.byKey(const Key('network-transfer-cancel-transfer-1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('network-transfer-amend-transfer-1')),
      findsNothing,
    );
  });

  testWidgets('withdrawing is gated behind a confirmation', (tester) async {
    when(
      () => repository.cancelTransfer(any()),
    ).thenAnswer((_) async => const Ok(null));
    await pump(tester, transfers: [sent()]);

    await tester.tap(
      find.byKey(const Key('network-transfer-cancel-transfer-1')),
    );
    await tester.pumpAndSettle();
    // Nothing must reach the repository until the dialog is confirmed.
    verifyNever(() => repository.cancelTransfer(any()));

    await tester.tap(find.byKey(const Key('network-cancel-confirm')));
    await tester.pumpAndSettle();
    verify(() => repository.cancelTransfer('transfer-1')).called(1);
  });

  testWidgets('changing the amount sends the new value', (tester) async {
    when(
      () => repository.amendTransfer(
        transferId: any(named: 'transferId'),
        amountMinor: any(named: 'amountMinor'),
        sourceAccountId: any(named: 'sourceAccountId'),
        requestedOn: any(named: 'requestedOn'),
        sharedNote: any(named: 'sharedNote'),
        clearSharedNote: any(named: 'clearSharedNote'),
      ),
    ).thenAnswer((_) async => const Ok('transfer-1'));
    await pump(tester, transfers: [sent()]);

    await tester.tap(
      find.byKey(const Key('network-transfer-amend-transfer-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('network-amend-amount')),
      '750.00',
    );
    await tester.tap(find.byKey(const Key('network-amend-submit')));
    await tester.pumpAndSettle();

    final captured = verify(
      () => repository.amendTransfer(
        transferId: 'transfer-1',
        amountMinor: captureAny(named: 'amountMinor'),
        sourceAccountId: any(named: 'sourceAccountId'),
        requestedOn: any(named: 'requestedOn'),
        sharedNote: any(named: 'sharedNote'),
        clearSharedNote: any(named: 'clearSharedNote'),
      ),
    ).captured.single;
    expect(captured, 75000);
  });

  testWidgets('a changed request is flagged so the receiver notices', (
    tester,
  ) async {
    await pump(tester, transfers: [sent(amendmentCount: 2)]);
    expect(find.text('Changed'), findsOneWidget);
  });

  testWidgets('holds recorded against me read as theirs, not mine', (
    tester,
  ) async {
    await pump(
      tester,
      initialTab: 4,
      holds: [
        HeldAgainstMe(
          id: 'held-1',
          // Their "I owe" means they are holding it *for* me.
          ownerDirection: HeldAmountDirection.iOwe,
          counterpartyAlias: 'Mona',
          amountMinor: 25000,
          currencyCode: 'EGP',
          heldOn: const PlainDate(2026, 8, 20),
          connectionActive: true,
          recordedAt: DateTime.utc(2026, 8, 20),
        ),
      ],
    );
    expect(find.byKey(const Key('held-against-me-held-1')), findsOneWidget);
    expect(find.textContaining('holding'), findsOneWidget);
    expect(find.textContaining('for you'), findsOneWidget);
  });

  testWidgets('the other direction reads as held against me', (tester) async {
    await pump(
      tester,
      initialTab: 4,
      holds: [
        HeldAgainstMe(
          id: 'held-2',
          ownerDirection: HeldAmountDirection.owedToMe,
          counterpartyAlias: 'Mona',
          amountMinor: 25000,
          currencyCode: 'EGP',
          heldOn: const PlainDate(2026, 8, 20),
          connectionActive: true,
          recordedAt: DateTime.utc(2026, 8, 20),
        ),
      ],
    );
    expect(find.textContaining('against you'), findsOneWidget);
  });
}
