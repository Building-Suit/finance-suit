import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:work_tracker/app/theme/app_theme.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/result/result.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';
import 'package:work_tracker/features/finance/presentation/screens/account_form_screen.dart';
import 'package:work_tracker/l10n/generated/app_localizations.dart';

class _MockFinanceRepository extends Mock implements FinanceRepository {}

Map<String, dynamic> _wrapped(dynamic value, String status) => {
  'value': value,
  'status': status,
  'confidence': value == null ? null : 'high',
  'sourceIds': value == null ? <String>[] : ['s1'],
};

Map<String, dynamic> _researchPayload({String name = 'CIB Platinum'}) => {
  'requestId': 'catalog:version-1',
  'status': 'resolved',
  'candidates': <dynamic>[],
  'product': {
    'issuerName': _wrapped('CIB', 'verified'),
    'productName': _wrapped('Platinum', 'verified'),
    'tier': _wrapped('Platinum', 'verified'),
    'network': _wrapped('visa', 'verified'),
    'currencyCode': _wrapped('EGP', 'verified'),
  },
  'accountForm': {
    'suggestedName': _wrapped(name, 'verified'),
    'creditLimitMinor': _wrapped(null, 'unknown'),
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
      'url': 'https://www.cibeg.com/terms',
      'title': 'CIB terms',
      'officialDomain': true,
      'publishedDate': null,
      'effectiveDate': null,
    },
  ],
  'unresolvedRequiredFields': <dynamic>[],
  'conflicts': <dynamic>[],
  'unsupportedFindings': <dynamic>[],
};

CatalogResearchMatch _catalogMatch({
  AccountType accountType = AccountType.creditCard,
  String issuer = 'CIB',
  String product = 'Platinum',
}) => CatalogResearchMatch.fromJson({
  'catalog_product_id': 'product-1',
  'catalog_version_id': 'version-1',
  'account_type': accountType.dbValue,
  'country_code': 'EG',
  'issuer_name': issuer,
  'official_website': 'https://example.com',
  'product_name': product,
  'tier': 'Platinum',
  'network': accountType == AccountType.creditCard ? 'visa' : null,
  'currency_code': 'EGP',
  'version_number': 1,
  'research_payload': _researchPayload(name: '$issuer $product'),
  'sources': <dynamic>[],
  'verified_at': '2026-08-01T00:00:00Z',
  'is_fresh': true,
  'age_days': 13,
  'match_quality': 100,
});

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
        builder: (_, _) => const Scaffold(body: Text('accounts list stub')),
      ),
      GoRoute(
        path: '/money/accounts/new',
        builder: (_, _) => const AccountFormScreen(),
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

  testWidgets('catalog action appears only for Credit Card and BNPL creation', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    await _pump(tester, repository: repo);
    expect(find.byKey(const Key('ai-autofill-button')), findsNothing);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    expect(find.text('Choose from catalog'), findsOneWidget);
    await _selectAccountType(tester, 'Credit Card', 'BNPL / Finance Company');
    expect(find.text('Choose from catalog'), findsOneWidget);
  });

  testWidgets('catalog picker requires bank then product selection', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    when(
      () => repo.browseCardCatalog(accountType: AccountType.creditCard),
    ).thenAnswer((_) async => Ok([_catalogMatch()]));
    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();
    expect(find.text('Product catalog'), findsOneWidget);
    expect(find.text('CIB'), findsOneWidget);
    expect(find.text('1 product'), findsOneWidget);
    await tester.tap(find.text('CIB'));
    await tester.pumpAndSettle();
    expect(find.text('Platinum'), findsOneWidget);
  });

  testWidgets('selection fills the form but waits for user confirmation', (
    tester,
  ) async {
    final repo = _MockFinanceRepository();
    final match = _catalogMatch();
    final result = CardResearchResult.fromJson(_researchPayload())
        .withCatalogMetadata(
          productId: match.productId,
          versionId: match.versionId,
          verifiedAt: match.verifiedAt,
          request: const CardResearchRequest(
            requestId: 'request-1',
            accountType: AccountType.creditCard,
            issuerName: 'CIB',
            countryCode: 'EG',
            productName: 'Platinum',
          ),
        );
    when(
      () => repo.browseCardCatalog(accountType: AccountType.creditCard),
    ).thenAnswer((_) async => Ok([match]));
    when(
      () => repo.researchCardProduct(any()),
    ).thenAnswer((_) async => Ok(result));

    await _pump(tester, repository: repo);
    await _selectAccountType(tester, 'Current balance', 'Credit Card');
    await tester.tap(find.byKey(const Key('ai-autofill-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CIB'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Platinum'));
    await tester.pumpAndSettle();

    final nameField = find.descendant(
      of: find.byKey(const Key('account-name')),
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(nameField).controller.text,
      'CIB Platinum',
    );
    expect(find.byKey(const Key('catalog-verified-indicator')), findsOneWidget);
    verifyNever(() => repo.saveCreditFacility(any()));
    expect(find.byType(AccountFormScreen), findsOneWidget);
  });

  testWidgets('catalog entry point renders in Arabic RTL', (tester) async {
    final repo = _MockFinanceRepository();
    await _pump(tester, repository: repo, locale: const Locale('ar'));
    await _selectAccountType(tester, 'الرصيد الجاري', 'بطاقة ائتمان');
    expect(find.text('اختر من الكتالوج'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
