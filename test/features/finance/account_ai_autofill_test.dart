import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/presentation/screens/account_form_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _MockFinanceRepository extends Mock implements FinanceRepository {}

Map<String, dynamic> _wrapped(
  dynamic value,
  String status, {
  String confidence = 'high',
}) => {
  'value': value,
  'status': status,
  'confidence': value == null ? null : confidence,
  'sourceIds': value == null ? <String>[] : ['s1'],
};

/// A resolved research result: verified product identity, a user-provided
/// credit limit (only ever eligible because the sheet echoed it back), a
/// verified due day/statement day, and a verified minimum-payment formula.
Map<String, dynamic> _resolvedJson({
  String name = 'CIB Platinum',
  int? creditLimitMinor = 500000,
}) => {
  'requestId': 'ignored',
  'status': 'resolved',
  'candidates': <dynamic>[],
  'product': {
    'issuerName': _wrapped('CIB', 'verified'),
    'productName': _wrapped('Platinum', 'verified'),
    'tier': _wrapped(null, 'unknown'),
    'network': _wrapped('visa', 'verified'),
    'currencyCode': _wrapped('EGP', 'verified'),
  },
  'accountForm': {
    'suggestedName': _wrapped(name, 'verified'),
    'creditLimitMinor': creditLimitMinor == null
        ? _wrapped(null, 'unknown')
        : _wrapped(creditLimitMinor, 'user_provided'),
    'defaultDueDay': _wrapped(17, 'verified'),
    'statementDay': _wrapped(24, 'verified'),
    'minPaymentMethod': _wrapped('percent', 'verified'),
    'minPaymentFixedMinor': _wrapped(null, 'unknown'),
    'minPaymentBasisPoints': _wrapped(500, 'verified'),
  },
  'rules': <dynamic>[],
  'installmentTenors': <dynamic>[],
  'sources': <dynamic>[
    {
      'id': 's1',
      'url': 'https://cib.com.eg/tariff',
      'title': 'CIB Tariff',
      'officialDomain': true,
      'publishedDate': null,
      'effectiveDate': null,
    },
  ],
  'unresolvedRequiredFields': <dynamic>[],
  'conflicts': <dynamic>[],
  'unsupportedFindings': <dynamic>[],
};

Map<String, dynamic> _ambiguousJson() => {
  'requestId': 'ignored',
  'status': 'ambiguous',
  'candidates': [
    {'id': 'c1', 'label': 'Platinum'},
    {'id': 'c2', 'label': 'Platinum Cashback'},
  ],
};

Future<GoRouter> _pump(
  WidgetTester tester, {
  required FinanceRepository repository,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/list',
    routes: [
      GoRoute(
        path: '/list',
        builder: (context, state) =>
            const Scaffold(body: Text('accounts list stub')),
      ),
      GoRoute(
        path: '/money/accounts/new',
        builder: (context, state) => const AccountFormScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [financeRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  unawaited(router.push('/money/accounts/new'));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _selectAccountType(
  WidgetTester tester,
  String currentLabel,
  String targetLabel,
) async {
  await tester.tap(find.text(currentLabel));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, targetLabel);
  await tester.pumpAndSettle();
  await tester.tap(find.text(targetLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _fillIdentificationSheet(
  WidgetTester tester, {
  String issuer = 'CIB',
  String product = 'Platinum',
  String? creditLimit,
}) async {
  await tester.enterText(find.byKey(const Key('ai-research-issuer')), issuer);
  await tester.tap(find.byKey(const Key('ai-research-country')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, 'Egypt');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Egypt (EG)').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('ai-research-product')), product);
  if (creditLimit != null) {
    await tester.ensureVisible(
      find.byKey(const Key('ai-research-credit-limit')),
    );
    await tester.enterText(
      find.byKey(const Key('ai-research-credit-limit')),
      creditLimit,
    );
  }
  await tester.ensureVisible(find.byKey(const Key('ai-research-submit')));
  await tester.tap(find.byKey(const Key('ai-research-submit')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const CardResearchRequest(
        requestId: 'fallback',
        accountType: AccountType.creditCard,
        issuerName: 'fallback',
        countryCode: 'EG',
        productName: 'fallback',
      ),
    );
    registerFallbackValue(
      const CreditFacilityDraft(
        name: 'fallback',
        accountType: AccountType.creditCard,
        currencyCode: 'EGP',
        creditLimitMinor: 0,
        defaultDueDay: 1,
      ),
    );
  });

  testWidgets('AI autofill button appears only for Credit Card/BNPL creation', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    await _pump(tester, repository: repo);

    expect(find.byKey(const Key('ai-autofill-button')), findsNothing);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    expect(find.byKey(const Key('ai-autofill-button')), findsOneWidget);

    await _selectAccountType(tester, 'Credit Card', 'BNPL / Finance Company');
    expect(find.byKey(const Key('ai-autofill-button')), findsOneWidget);
  });

  testWidgets('tapping the button opens a structured, non-chat sheet', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');

    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-research-issuer')), findsOneWidget);
    expect(find.byKey(const Key('ai-research-country')), findsOneWidget);
    expect(find.byKey(const Key('ai-research-product')), findsOneWidget);
    expect(find.byKey(const Key('ai-research-network')), findsOneWidget);
    expect(find.byKey(const Key('ai-research-notes')), findsOneWidget);
    expect(
      find.text(
        'Do not enter your full card number, CVV, PIN, password, or OTP.',
      ),
      findsOneWidget,
    );
    // Structured submit, not a chat "send" action.
    expect(find.byKey(const Key('ai-research-submit')), findsOneWidget);
    expect(find.text('Find and fill my card'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);
  });

  testWidgets(
    'BNPL sheet swaps in BNPL-specific fields and hides card-only ones',
    (tester) async {
      final repo = _MockFinanceRepository();
      await _pump(tester, repository: repo);
      await _selectAccountType(
        tester,
        'Current balance',
        'BNPL / Finance Company',
      );

      await tester.tap(find.byKey(const Key('ai-autofill-button')));
      await tester.pumpAndSettle();

      expect(find.text('Find and fill my account'), findsOneWidget);
      expect(find.byKey(const Key('ai-research-tenor')), findsOneWidget);
      expect(find.byKey(const Key('ai-research-network')), findsNothing);
      expect(find.byKey(const Key('ai-research-statement-day')), findsNothing);
    },
  );

  testWidgets('shows a deterministic status line while research is in flight', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    when(() => repo.researchCardProduct(any())).thenAnswer(
      (_) => Future<Result<CardResearchResult>>.delayed(
        const Duration(milliseconds: 500),
        () => Ok(CardResearchResult.fromJson(_resolvedJson())),
      ),
    );
    when(
      () => repo.saveCreditFacility(any()),
    ).thenAnswer((_) async => const Ok('new-account-id'));
    when(
      () => repo.setHideFromHome(any(), hidden: any(named: 'hidden')),
    ).thenAnswer((_) async => const Ok(null));

    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();
    // Drive frames manually while the indeterminate spinner is visible —
    // pumpAndSettle would spin forever against a repeating animation.
    await tester.enterText(find.byKey(const Key('ai-research-issuer')), 'CIB');
    await tester.tap(find.byKey(const Key('ai-research-country')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Egypt');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Egypt (EG)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-research-product')),
      'Platinum',
    );
    await tester.ensureVisible(find.byKey(const Key('ai-research-submit')));
    await tester.tap(find.byKey(const Key('ai-research-submit')));
    await tester.pump();

    expect(find.text('Finding your product…'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('ai-autofill-button')),
    );
    expect(button.onPressed, isNull);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump();
  });

  testWidgets(
    'a resolved result fills the form and auto-submits through the existing Create path',
    (tester) async {
      final repo = _MockFinanceRepository();
      when(() => repo.researchCardProduct(any())).thenAnswer(
        (_) async => Ok(CardResearchResult.fromJson(_resolvedJson())),
      );
      when(
        () => repo.saveCreditFacility(any()),
      ).thenAnswer((_) async => const Ok('new-account-id'));
      when(
        () => repo.setHideFromHome(any(), hidden: any(named: 'hidden')),
      ).thenAnswer((_) async => const Ok(null));

      await _pump(tester, repository: repo);
      await _selectAccountType(tester, 'Current balance', 'Credit Card');
      await tester.tap(find.byKey(const Key('ai-autofill-button')));
      await tester.pumpAndSettle();
      await _fillIdentificationSheet(tester, creditLimit: '5000');

      final captured = verify(
        () => repo.saveCreditFacility(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      final draft = captured.single as CreditFacilityDraft;
      expect(draft.name, 'CIB Platinum');
      expect(draft.creditLimitMinor, 500000);
      expect(draft.defaultDueDay, 17);
      expect(draft.statementDay, 24);
      expect(draft.minPaymentMethod, MinPaymentMethod.percent);
      expect(draft.minPaymentBasisPoints, 500);

      // The screen popped back to the caller — the same outcome a manual
      // Create tap produces.
      expect(find.byType(AccountFormScreen), findsNothing);
      expect(find.text('accounts list stub'), findsOneWidget);
    },
  );

  testWidgets('an incomplete result fills what it can but never auto-submits', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    when(() => repo.researchCardProduct(any())).thenAnswer(
      (_) async => Ok(
        CardResearchResult.fromJson(_resolvedJson(creditLimitMinor: null)),
      ),
    );

    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();
    // No credit limit provided in the sheet either — the field the AI
    // can never safely guess (task spec section 33) stays empty.
    await _fillIdentificationSheet(tester);

    verifyNever(() => repo.saveCreditFacility(any()));
    expect(
      find.text(
        'We filled what we could. Complete the highlighted fields to continue.',
      ),
      findsOneWidget,
    );
    expect(find.text('CIB Platinum'), findsOneWidget);
    expect(find.byType(AccountFormScreen), findsOneWidget);
  });

  testWidgets('a manually-entered name is never overwritten by AI autofill', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    when(
      () => repo.researchCardProduct(any()),
    ).thenAnswer((_) async => Ok(CardResearchResult.fromJson(_resolvedJson())));
    when(
      () => repo.saveCreditFacility(captureAny()),
    ).thenAnswer((_) async => const Ok('new-account-id'));
    when(
      () => repo.setHideFromHome(any(), hidden: any(named: 'hidden')),
    ).thenAnswer((_) async => const Ok(null));

    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.enterText(
      find.byKey(const Key('account-name')),
      'My Own Card Name',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();
    await _fillIdentificationSheet(tester, creditLimit: '5000');

    final draft =
        verify(() => repo.saveCreditFacility(captureAny())).captured.single
            as CreditFacilityDraft;
    expect(draft.name, 'My Own Card Name');
  });

  testWidgets(
    'an ambiguous match offers a plain disambiguation choice, not a chat',
    (tester) async {
      final repo = _MockFinanceRepository();
      when(() => repo.researchCardProduct(any())).thenAnswer((
        invocation,
      ) async {
        final request =
            invocation.positionalArguments[0] as CardResearchRequest;
        if (request.selectedProductId == null) {
          return Ok(CardResearchResult.fromJson(_ambiguousJson()));
        }
        return Ok(
          CardResearchResult.fromJson(
            _resolvedJson(name: 'CIB Platinum Cashback'),
          ),
        );
      });
      when(
        () => repo.saveCreditFacility(captureAny()),
      ).thenAnswer((_) async => const Ok('new-account-id'));
      when(
        () => repo.setHideFromHome(any(), hidden: any(named: 'hidden')),
      ).thenAnswer((_) async => const Ok(null));

      await _pump(tester, repository: repo);
      await _selectAccountType(tester, 'Current balance', 'Credit Card');
      await tester.tap(find.byKey(const Key('ai-autofill-button')));
      await tester.pumpAndSettle();
      await _fillIdentificationSheet(tester, creditLimit: '5000');

      expect(find.text('Which one do you have?'), findsOneWidget);
      expect(find.byKey(const Key('ai-research-candidate-c1')), findsOneWidget);
      expect(find.byKey(const Key('ai-research-candidate-c2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-research-candidate-c2')));
      await tester.pumpAndSettle();

      verify(() => repo.researchCardProduct(any())).called(2);
      final draft =
          verify(() => repo.saveCreditFacility(captureAny())).captured.single
              as CreditFacilityDraft;
      expect(draft.name, 'CIB Platinum Cashback');
    },
  );

  testWidgets('a provider failure leaves the manual form fully usable', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    when(
      () => repo.researchCardProduct(any()),
    ).thenAnswer((_) async => const Err(NetworkFailure()));

    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();
    await _fillIdentificationSheet(tester);

    verifyNever(() => repo.saveCreditFacility(any()));
    expect(
      find.text(
        "We couldn't find enough reliable information. You can continue filling the form manually.",
      ),
      findsOneWidget,
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('ai-autofill-button')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.byKey(const Key('facility-credit-limit')), findsOneWidget);
  });

  testWidgets('renders correctly in Arabic RTL', (tester) async {
    final repo = _MockFinanceRepository();
    await _pump(tester, repository: repo, locale: const Locale('ar'));
    await _selectAccountType(tester, 'الرصيد الجاري', 'بطاقة ائتمان');

    expect(find.byKey(const Key('ai-autofill-button')), findsOneWidget);
    expect(find.text('دع الذكاء الاصطناعي يساعدك'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a small phone viewport without overflow', (tester) async {
    final repo = _MockFinanceRepository();
    await _pump(tester, repository: repo, size: const Size(320, 640));
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
