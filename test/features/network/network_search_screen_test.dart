import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/features/network/data/network_repository.dart';
import 'package:work_tracker/features/network/domain/network_models.dart';
import 'package:work_tracker/features/network/presentation/screens/network_search_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _MockNetworkRepository extends Mock implements NetworkRepository {}

void main() {
  const mona = NetworkUserSearchResult(
    userId: 'user-2',
    displayName: 'Mona Ahmed',
    email: 'mona@example.com',
    relationshipState: NetworkRelationshipState.none,
  );
  const requested = NetworkUserSearchResult(
    userId: 'user-3',
    displayName: 'Ahmed Work',
    email: 'ahmed@example.com',
    relationshipState: NetworkRelationshipState.outgoingPending,
  );
  const connected = NetworkUserSearchResult(
    userId: 'user-4',
    displayName: 'Dad',
    email: 'dad@example.com',
    relationshipState: NetworkRelationshipState.connected,
  );
  const responder = NetworkUserSearchResult(
    userId: 'user-5',
    displayName: 'Sara',
    email: 'sara@example.com',
    relationshipState: NetworkRelationshipState.incomingPending,
    requestId: 'request-9',
  );

  late _MockNetworkRepository repository;

  setUp(() {
    repository = _MockNetworkRepository();
  });

  Future<void> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [networkRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const NetworkSearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('search debounces and skips too-short name queries', (
    tester,
  ) async {
    when(
      () => repository.searchUsers(any()),
    ).thenAnswer((_) async => const Ok([mona]));
    await pumpSearch(tester);

    await tester.enterText(find.byKey(const Key('network-search-field')), 'Mo');
    await tester.pump(const Duration(milliseconds: 600));
    verifyNever(() => repository.searchUsers(any()));

    await tester.enterText(
      find.byKey(const Key('network-search-field')),
      'Mona',
    );
    await tester.pump(const Duration(milliseconds: 200));
    verifyNever(() => repository.searchUsers(any()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    verify(() => repository.searchUsers('Mona')).called(1);
    expect(find.text('Mona Ahmed'), findsOneWidget);
    expect(find.text('mona@example.com'), findsOneWidget);
  });

  testWidgets('results reflect the relationship state', (tester) async {
    when(() => repository.searchUsers(any())).thenAnswer(
      (_) async => const Ok([mona, requested, connected, responder]),
    );
    await pumpSearch(tester);

    await tester.enterText(
      find.byKey(const Key('network-search-field')),
      'people',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('network-add-user-2')), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.byKey(const Key('network-respond-user-5')), findsOneWidget);
  });

  testWidgets('adding asks for a private alias and sends the request', (
    tester,
  ) async {
    when(
      () => repository.searchUsers(any()),
    ).thenAnswer((_) async => const Ok([mona]));
    when(
      () => repository.sendAddRequest(
        targetUserId: any(named: 'targetUserId'),
        localAlias: any(named: 'localAlias'),
      ),
    ).thenAnswer((_) async => const Ok('request-1'));
    await pumpSearch(tester);

    await tester.enterText(
      find.byKey(const Key('network-search-field')),
      'Mona',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('network-add-user-2')));
    await tester.pumpAndSettle();
    expect(find.text('What do you want to call this person?'), findsOneWidget);
    expect(find.textContaining('Adding: Mona Ahmed'), findsOneWidget);

    // An empty alias is rejected before anything is sent.
    await tester.tap(find.byKey(const Key('network-alias-save')));
    await tester.pumpAndSettle();
    verifyNever(
      () => repository.sendAddRequest(
        targetUserId: any(named: 'targetUserId'),
        localAlias: any(named: 'localAlias'),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('network-alias-field')),
      'Wife',
    );
    await tester.tap(find.byKey(const Key('network-alias-save')));
    await tester.pumpAndSettle();

    verify(
      () =>
          repository.sendAddRequest(targetUserId: 'user-2', localAlias: 'Wife'),
    ).called(1);
    expect(find.text('Requested'), findsOneWidget);
  });
}
