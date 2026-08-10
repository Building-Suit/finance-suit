import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';

Map<String, dynamic> _value(
  dynamic value,
  String status, {
  String? confidence,
}) => {
  'value': value,
  'status': status,
  'confidence': confidence,
  'sourceIds': value == null ? <String>[] : ['s1'],
};

Map<String, dynamic> _resolvedJson() => {
  'requestId': 'req-1',
  'status': 'resolved',
  'errorMessage': null,
  'candidates': <dynamic>[],
  'product': {
    'issuerName': _value('CIB', 'verified', confidence: 'high'),
    'productName': _value('Platinum', 'verified', confidence: 'high'),
    'tier': _value(null, 'unknown'),
    'network': _value('visa', 'verified', confidence: 'high'),
    'currencyCode': _value('EGP', 'verified', confidence: 'high'),
  },
  'accountForm': {
    'suggestedName': _value('CIB Platinum', 'verified', confidence: 'high'),
    'creditLimitMinor': _value(5000000, 'user_provided', confidence: 'high'),
    'defaultDueDay': _value(17, 'verified', confidence: 'high'),
    'statementDay': _value(24, 'verified', confidence: 'high'),
    'minPaymentMethod': _value('percent', 'verified', confidence: 'high'),
    'minPaymentFixedMinor': _value(null, 'unknown'),
    'minPaymentBasisPoints': _value(500, 'verified', confidence: 'high'),
  },
  'rules': [
    {
      'feeType': 'annual_membership',
      'calculationType': 'fixed',
      'frequency': 'annually',
      'fixedAmountMinor': 70000,
      'percentBasisPoints': null,
      'percentBasis': null,
      'minimumMinor': null,
      'maximumMinor': null,
      'lookbackCycles': null,
      'status': 'verified',
      'confidence': 'high',
      'sourceIds': ['s1'],
    },
  ],
  'installmentTenors': [
    {
      'fromMonths': 3,
      'toMonths': 6,
      'ratePercentBasisPoints': 150,
      'method': 'flat',
      'period': 'monthly',
      'status': 'verified',
      'sourceIds': ['s1'],
    },
  ],
  'sources': [
    {
      'id': 's1',
      'url': 'https://cib.com.eg/tariff',
      'title': 'CIB Tariff',
      'officialDomain': true,
      'publishedDate': '2026-01-01',
      'effectiveDate': '2026-01-01',
    },
  ],
  'unresolvedRequiredFields': <dynamic>[],
  'conflicts': <dynamic>[],
  'unsupportedFindings': <dynamic>[],
};

void main() {
  group('ResearchedValue.isAutofillEligible', () {
    test('is true for supported verified and user-provided values', () {
      const verified = ResearchedValue<String>(
        value: 'CIB',
        status: ResearchFieldStatus.verified,
        confidence: ConfidenceLevel.high,
        sourceIds: ['s1'],
      );
      const userProvided = ResearchedValue<int>(
        value: 5000000,
        status: ResearchFieldStatus.userProvided,
      );
      expect(verified.isAutofillEligible, isTrue);
      expect(userProvided.isAutofillEligible, isTrue);
    });

    test('is false for probable, conflicting, unknown, and not_applicable', () {
      for (final status in [
        ResearchFieldStatus.probable,
        ResearchFieldStatus.conflicting,
        ResearchFieldStatus.unknown,
        ResearchFieldStatus.notApplicable,
      ]) {
        final researched = ResearchedValue<String>(value: 'X', status: status);
        expect(researched.isAutofillEligible, isFalse, reason: status.name);
      }
    });

    test('is false when value is null even if status is verified', () {
      const researched = ResearchedValue<String>(
        value: null,
        status: ResearchFieldStatus.verified,
      );
      expect(researched.isAutofillEligible, isFalse);
    });
  });

  group('wire enum fallbacks', () {
    test(
      'ResearchFieldStatus.fromWire defaults to unknown on malformed input',
      () {
        expect(
          ResearchFieldStatus.fromWire('nonsense'),
          ResearchFieldStatus.unknown,
        );
        expect(ResearchFieldStatus.fromWire(null), ResearchFieldStatus.unknown);
      },
    );

    test('ResearchStatus.fromWire defaults to error on malformed input', () {
      expect(ResearchStatus.fromWire('nonsense'), ResearchStatus.error);
    });

    test(
      'ConfidenceLevel.fromWire returns null for missing/unknown values',
      () {
        expect(ConfidenceLevel.fromWire(null), isNull);
        expect(ConfidenceLevel.fromWire('nonsense'), isNull);
        expect(ConfidenceLevel.fromWire('high'), ConfidenceLevel.high);
      },
    );
  });

  group('CardResearchResult.fromJson', () {
    test('parses a full resolved result end-to-end', () {
      final result = CardResearchResult.fromJson(_resolvedJson());

      expect(result.status, ResearchStatus.resolved);
      expect(result.issuerName.value, 'CIB');
      expect(result.issuerName.isAutofillEligible, isTrue);
      expect(result.tier.status, ResearchFieldStatus.unknown);
      expect(result.tier.isAutofillEligible, isFalse);
      expect(result.network.value, CardNetworkGuess.visa);

      expect(result.suggestedName.value, 'CIB Platinum');
      expect(result.creditLimitMinor.status, ResearchFieldStatus.userProvided);
      expect(result.defaultDueDay.value, 17);
      expect(result.statementDay.value, 24);
      expect(result.minPaymentMethod.value, MinPaymentMethod.percent);
      expect(result.minPaymentBasisPoints.value, 500);

      expect(result.rules, hasLength(1));
      expect(result.rules.single.feeType, CardFeeType.annualMembership);
      expect(result.rules.single.fixedAmountMinor, 70000);
      expect(result.rules.single.isEligible, isTrue);

      expect(result.installmentTenors, hasLength(1));
      expect(result.installmentTenors.single.method, InterestMethod.flat);

      expect(result.sources, hasLength(1));
      expect(result.sources.single.officialDomain, isTrue);
    });

    test('parses an ambiguous result with candidates and no rules', () {
      final json = {
        'requestId': 'req-2',
        'status': 'ambiguous',
        'candidates': [
          {'id': 'c1', 'label': 'Platinum'},
          {'id': 'c2', 'label': 'Platinum Cashback'},
        ],
      };
      final result = CardResearchResult.fromJson(json);
      expect(result.status, ResearchStatus.ambiguous);
      expect(result.candidates, hasLength(2));
      expect(result.candidates.first.label, 'Platinum');
      expect(result.rules, isEmpty);
      expect(result.issuerName.isAutofillEligible, isFalse);
    });

    test(
      'missing optional maps default to empty/unknown rather than throwing',
      () {
        final result = CardResearchResult.fromJson({
          'requestId': 'req-3',
          'status': 'insufficient_information',
        });
        expect(result.status, ResearchStatus.insufficientInformation);
        expect(result.rules, isEmpty);
        expect(result.sources, isEmpty);
        expect(result.issuerName.status, ResearchFieldStatus.unknown);
      },
    );
  });

  group('CardResearchRequest.toJson', () {
    test(
      'serializes account type and network as dbValue/wireValue strings',
      () {
        const request = CardResearchRequest(
          requestId: 'req-1',
          accountType: AccountType.creditCard,
          issuerName: 'CIB',
          countryCode: 'EG',
          productName: 'Platinum',
          network: CardNetworkGuess.visa,
        );
        final json = request.toJson();
        expect(json['accountType'], 'credit_card');
        expect(json['network'], 'visa');
        expect(json['issuerName'], 'CIB');
        expect(json['countryCode'], 'EG');
      },
    );

    test(
      'copyWith sets a disambiguation product id without losing other fields',
      () {
        const request = CardResearchRequest(
          requestId: 'req-1',
          accountType: AccountType.bnpl,
          issuerName: 'ValU',
          countryCode: 'EG',
          productName: 'Standard Plan',
        );
        final rerun = request.copyWith(selectedProductId: 'candidate-2');
        expect(rerun.selectedProductId, 'candidate-2');
        expect(rerun.issuerName, 'ValU');
        expect(rerun.accountType, AccountType.bnpl);
      },
    );
  });
}
