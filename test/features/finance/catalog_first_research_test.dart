import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/data/card_research_data_source.dart';
import 'package:work_tracker/features/finance/data/finance_repository.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';

Map<String, dynamic> _value(dynamic value, String status) => {
  'value': value,
  'status': status,
  'confidence': value == null ? null : 'high',
  'sourceIds': value == null ? <String>[] : ['official'],
};

Map<String, dynamic> _payload({String requestId = 'live-request'}) => {
  'requestId': requestId,
  'status': 'resolved',
  'candidates': <dynamic>[],
  'product': {
    'issuerName': _value('CIB', 'verified'),
    'productName': _value('Platinum', 'verified'),
    'tier': _value('Platinum', 'verified'),
    'network': _value('visa', 'verified'),
    'currencyCode': _value('EGP', 'verified'),
  },
  'accountForm': {
    'suggestedName': _value('CIB Platinum', 'verified'),
    'creditLimitMinor': _value(null, 'unknown'),
    'defaultDueDay': _value(17, 'verified'),
    'statementDay': _value(24, 'verified'),
    'minPaymentMethod': _value('full', 'verified'),
    'minPaymentFixedMinor': _value(null, 'unknown'),
    'minPaymentBasisPoints': _value(null, 'unknown'),
  },
  'rules': <dynamic>[],
  'installmentTenors': <dynamic>[],
  'sources': [
    {
      'id': 'official',
      'url': 'https://www.cibeg.com/cards/platinum',
      'title': 'CIB Platinum',
      'officialDomain': true,
    },
  ],
  'unresolvedRequiredFields': <dynamic>[],
  'conflicts': <dynamic>[],
  'unsupportedFindings': <dynamic>[],
};

Map<String, dynamic> _catalogRow({
  String productId = '00000000-0000-0000-0000-000000000001',
  String versionId = '00000000-0000-0000-0000-000000000011',
  bool fresh = true,
  int quality = 100,
}) => {
  'catalog_product_id': productId,
  'catalog_version_id': versionId,
  'account_type': 'credit_card',
  'country_code': 'EG',
  'issuer_name': 'CIB',
  'official_website': 'https://www.cibeg.com',
  'product_name': 'Platinum',
  'tier': 'Platinum',
  'network': 'visa',
  'currency_code': 'EGP',
  'research_payload': _payload()
    ..remove('requestId')
    ..remove('status'),
  'sources': (_payload()['sources'] as List),
  'verified_at': '2026-08-01T10:00:00Z',
  'is_fresh': fresh,
  'age_days': 8,
  'match_quality': quality,
};

CardResearchRequest _request({
  String? selectedProductId,
  List<CatalogResearchMatch> catalogMatches = const [],
}) => CardResearchRequest(
  requestId: 'request-1',
  accountType: AccountType.creditCard,
  issuerName: ' CIB ',
  countryCode: 'eg',
  productName: 'Platinum',
  officialWebsite: 'https://www.cibeg.com',
  tier: 'Platinum',
  network: CardNetworkGuess.visa,
  currencyCode: 'egp',
  activationDate: '2026-01-02',
  knownCreditLimitMinor: 500000,
  knownStatementDay: 22,
  knownDueDay: 12,
  userNotes: 'private note',
  selectedProductId: selectedProductId,
  catalogMatches: catalogMatches,
);

class _FakeCardResearchDataSource implements CardResearchDataSource {
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> liveResult = _payload();
  Error? searchError;
  Error? liveError;
  int searchCalls = 0;
  int liveCalls = 0;
  final List<(CatalogProductIdentity, String)> queued = [];

  @override
  Future<List<Map<String, dynamic>>> searchCatalog(
    CatalogProductIdentity identity,
  ) async {
    searchCalls++;
    if (searchError case final error?) throw error;
    return rows;
  }

  @override
  Future<void> enqueueCatalogResearch(
    CatalogProductIdentity identity, {
    required String reason,
  }) async {
    queued.add((identity, reason));
  }

  @override
  Future<Map<String, dynamic>> researchLive(CardResearchRequest request) async {
    liveCalls++;
    if (liveError case final error?) throw error;
    return liveResult;
  }
}

FinanceRepository _repository(_FakeCardResearchDataSource source) =>
    FinanceRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      cardResearchDataSource: source,
    );

void main() {
  test('autofill eligibility requires confidence and source provenance', () {
    const lowConfidence = ResearchedValue<int>(
      value: 17,
      status: ResearchFieldStatus.verified,
      confidence: ConfidenceLevel.low,
      sourceIds: ['official'],
    );
    const missingSource = ResearchedValue<int>(
      value: 17,
      status: ResearchFieldStatus.verified,
      confidence: ConfidenceLevel.high,
    );
    const supported = ResearchedValue<int>(
      value: 17,
      status: ResearchFieldStatus.verified,
      confidence: ConfidenceLevel.medium,
      sourceIds: ['official'],
    );

    expect(lowConfidence.isAutofillEligible, isFalse);
    expect(missingSource.isAutofillEligible, isFalse);
    expect(supported.isAutofillEligible, isTrue);
  });

  test(
    'fresh confident catalog hit maps provenance and avoids live AI',
    () async {
      final source = _FakeCardResearchDataSource()..rows = [_catalogRow()];

      final result = await _repository(source).researchCardProduct(_request());
      final research = result.valueOrNull!;

      expect(source.liveCalls, 0);
      expect(research.origin, CardResearchOrigin.catalog);
      expect(research.requestId, startsWith('catalog:'));
      expect(research.catalogProductId, isNotNull);
      expect(research.catalogVersionId, isNotNull);
      expect(research.catalogVerifiedAt, DateTime.utc(2026, 8, 1, 10));
      expect(research.sources.single.officialDomain, isTrue);
      expect(research.creditLimitMinor.value, 500000);
      expect(
        research.creditLimitMinor.status,
        ResearchFieldStatus.userProvided,
      );
      expect(research.defaultDueDay.value, 12);
      expect(research.statementDay.value, 22);
    },
  );

  test('stale catalog match queues stale identity and uses live AI', () async {
    final source = _FakeCardResearchDataSource()
      ..rows = [_catalogRow(fresh: false)];

    final result = await _repository(source).researchCardProduct(_request());

    expect(result.isOk, isTrue);
    expect(source.liveCalls, 1);
    expect(source.queued.single.$2, 'stale');
  });

  test('catalog miss queues only normalized public product identity', () async {
    final source = _FakeCardResearchDataSource();

    await _repository(source).researchCardProduct(_request());

    expect(source.liveCalls, 1);
    final queued = source.queued.single;
    expect(queued.$2, 'new_product');
    final params = queued.$1.toEnqueueParams(queued.$2);
    expect(params['p_country_code'], 'EG');
    expect(params['p_currency_code'], 'EGP');
    expect(params['p_issuer_name'], 'CIB');
    for (final forbidden in [
      'userNotes',
      'activationDate',
      'knownCreditLimitMinor',
      'knownStatementDay',
      'knownDueDay',
      'pan',
      'cvv',
    ]) {
      expect(params, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test(
    'ambiguous catalog selection reuses session matches without requery',
    () async {
      final source = _FakeCardResearchDataSource()
        ..rows = [
          _catalogRow(),
          _catalogRow(
            productId: '00000000-0000-0000-0000-000000000002',
            versionId: '00000000-0000-0000-0000-000000000022',
          ),
        ];
      final repository = _repository(source);

      final ambiguous = (await repository.researchCardProduct(
        _request(),
      )).valueOrNull!;
      expect(ambiguous.status, ResearchStatus.ambiguous);
      expect(ambiguous.candidates, hasLength(2));

      final selected = await repository.researchCardProduct(
        _request(
          selectedProductId: ambiguous.candidates.last.id,
          catalogMatches: ambiguous.catalogMatches,
        ),
      );
      expect(
        selected.valueOrNull!.catalogProductId,
        ambiguous.candidates.last.id,
      );
      expect(source.searchCalls, 1);
      expect(source.liveCalls, 0);
    },
  );

  test('catalog error silently falls back to live AI once', () async {
    final source = _FakeCardResearchDataSource()
      ..searchError = StateError('catalog unavailable');

    final result = await _repository(source).researchCardProduct(_request());

    expect(result.isOk, isTrue);
    expect(source.liveCalls, 1);
  });

  test(
    'catalog and live failure returns failure so manual form stays usable',
    () async {
      final source = _FakeCardResearchDataSource()
        ..searchError = StateError('catalog unavailable')
        ..liveError = StateError('AI unavailable');

      final result = await _repository(source).researchCardProduct(_request());

      expect(result.isOk, isFalse);
      expect(source.liveCalls, 1);
    },
  );

  test('catalog search params match the RPC and exclude official website', () {
    final params = CatalogProductIdentity.fromRequest(
      _request(),
    ).toSearchParams();

    expect(params, hasLength(7));
    expect(params, isNot(contains('p_official_website')));
  });
}
