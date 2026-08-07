import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/domain/db_enums.dart';

/// Confidence/provenance a single AI-researched value carries. Mirrors the
/// Edge Function's FieldStatus wire values exactly (see
/// supabase/functions/ai-card-research/types.ts). "unknown" is never the
/// same as zero, and only [verified]/[userProvided] values are ever
/// eligible to autofill the existing Add Account form — see
/// [ResearchedValue.isAutofillEligible].
enum ResearchFieldStatus {
  verified('verified'),
  userProvided('user_provided'),
  probable('probable'),
  conflicting('conflicting'),
  unknown('unknown'),
  notApplicable('not_applicable');

  const ResearchFieldStatus(this.wireValue);
  final String wireValue;

  static ResearchFieldStatus fromWire(String? value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => ResearchFieldStatus.unknown,
  );
}

enum ConfidenceLevel {
  high('high'),
  medium('medium'),
  low('low');

  const ConfidenceLevel(this.wireValue);
  final String wireValue;

  static ConfidenceLevel? fromWire(String? value) {
    if (value == null) return null;
    return values.firstWhereOrNull((e) => e.wireValue == value);
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

enum ResearchStatus {
  resolved('resolved'),
  ambiguous('ambiguous'),
  insufficientInformation('insufficient_information'),
  error('error');

  const ResearchStatus(this.wireValue);
  final String wireValue;

  static ResearchStatus fromWire(String? value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => ResearchStatus.error,
  );
}

/// Where a value currently on the account-creation form came from. Tracked
/// per logical field so a manually-typed value is never silently
/// overwritten by AI autofill (task spec section 56).
enum FieldOrigin { defaultValue, manual, ai }

enum CardNetworkGuess {
  visa('visa'),
  mastercard('mastercard'),
  other('other'),
  unknown('unknown');

  const CardNetworkGuess(this.wireValue);
  final String wireValue;

  static CardNetworkGuess fromWire(String? value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => CardNetworkGuess.unknown,
  );
}

@immutable
class ResearchedValue<T> {
  const ResearchedValue({
    required this.value,
    required this.status,
    this.confidence,
    this.sourceIds = const [],
  });

  const ResearchedValue.empty()
    : value = null,
      status = ResearchFieldStatus.unknown,
      confidence = null,
      sourceIds = const [];

  final T? value;
  final ResearchFieldStatus status;
  final ConfidenceLevel? confidence;
  final List<String> sourceIds;

  /// Only [verified] and [userProvided] values are safe to write into the
  /// form automatically — see task spec section 23 ("safest default: do
  /// not autofill weak financial values").
  bool get isAutofillEligible =>
      value != null &&
      (status == ResearchFieldStatus.verified ||
          status == ResearchFieldStatus.userProvided);
}

ResearchedValue<T> _parseValue<T>(
  Map<String, dynamic>? json,
  T? Function(dynamic raw) parse,
) {
  if (json == null) return ResearchedValue<T>.empty();
  return ResearchedValue<T>(
    value: parse(json['value']),
    status: ResearchFieldStatus.fromWire(json['status'] as String?),
    confidence: ConfidenceLevel.fromWire(json['confidence'] as String?),
    sourceIds: (json['sourceIds'] as List?)?.cast<String>() ?? const <String>[],
  );
}

@immutable
class ResearchSource {
  const ResearchSource({
    required this.id,
    required this.url,
    required this.title,
    required this.officialDomain,
    this.publishedDate,
    this.effectiveDate,
  });

  factory ResearchSource.fromJson(Map<String, dynamic> json) => ResearchSource(
    id: json['id'] as String,
    url: json['url'] as String,
    title: json['title'] as String,
    officialDomain: json['officialDomain'] as bool? ?? false,
    publishedDate: json['publishedDate'] as String?,
    effectiveDate: json['effectiveDate'] as String?,
  );

  final String id;
  final String url;
  final String title;
  final bool officialDomain;
  final String? publishedDate;
  final String? effectiveDate;
}

@immutable
class ProductCandidate {
  const ProductCandidate({required this.id, required this.label});

  factory ProductCandidate.fromJson(Map<String, dynamic> json) =>
      ProductCandidate(
        id: json['id'] as String,
        label: json['label'] as String,
      );

  final String id;
  final String label;
}

@immutable
class CardResearchConflict {
  const CardResearchConflict({
    required this.field,
    required this.userValue,
    required this.officialValue,
  });

  factory CardResearchConflict.fromJson(Map<String, dynamic> json) =>
      CardResearchConflict(
        field: json['field'] as String,
        userValue: json['userValue'] as String,
        officialValue: json['officialValue'] as String,
      );

  final String field;
  final String userValue;
  final String officialValue;
}

@immutable
class UnsupportedFinding {
  const UnsupportedFinding({required this.description, required this.note});

  factory UnsupportedFinding.fromJson(Map<String, dynamic> json) =>
      UnsupportedFinding(
        description: json['description'] as String,
        note: json['note'] as String? ?? '',
      );

  final String description;
  final String note;
}

/// One researched card fee, shaped like [CardFeeRuleDraft] so a future
/// screen can hand it straight to `saveFeeRule` without remapping.
@immutable
class ResearchedFeeRule {
  const ResearchedFeeRule({
    required this.feeType,
    required this.calculationType,
    required this.frequency,
    required this.status,
    this.fixedAmountMinor,
    this.percentBasisPoints,
    this.percentBasis,
    this.minimumMinor,
    this.maximumMinor,
    this.lookbackCycles,
    this.confidence,
    this.sourceIds = const [],
  });

  factory ResearchedFeeRule.fromJson(Map<String, dynamic> json) =>
      ResearchedFeeRule(
        feeType: CardFeeType.fromDb(json['feeType'] as String),
        calculationType: CardRuleCalculationType.fromDb(
          json['calculationType'] as String,
        ),
        frequency: FeeFrequency.fromDb(json['frequency'] as String),
        fixedAmountMinor: (json['fixedAmountMinor'] as num?)?.toInt(),
        percentBasisPoints: (json['percentBasisPoints'] as num?)?.toInt(),
        percentBasis: json['percentBasis'] == null
            ? null
            : FeePercentBasis.fromDb(json['percentBasis'] as String),
        minimumMinor: (json['minimumMinor'] as num?)?.toInt(),
        maximumMinor: (json['maximumMinor'] as num?)?.toInt(),
        lookbackCycles: (json['lookbackCycles'] as num?)?.toInt(),
        status: ResearchFieldStatus.fromWire(json['status'] as String?),
        confidence: ConfidenceLevel.fromWire(json['confidence'] as String?),
        sourceIds:
            (json['sourceIds'] as List?)?.cast<String>() ?? const <String>[],
      );

  final CardFeeType feeType;
  final CardRuleCalculationType calculationType;
  final FeeFrequency frequency;
  final int? fixedAmountMinor;
  final int? percentBasisPoints;
  final FeePercentBasis? percentBasis;
  final int? minimumMinor;
  final int? maximumMinor;
  final int? lookbackCycles;
  final ResearchFieldStatus status;
  final ConfidenceLevel? confidence;
  final List<String> sourceIds;

  bool get isEligible =>
      status == ResearchFieldStatus.verified ||
      status == ResearchFieldStatus.userProvided;
}

@immutable
class ResearchedTenorRate {
  const ResearchedTenorRate({
    required this.fromMonths,
    required this.toMonths,
    required this.ratePercentBasisPoints,
    required this.method,
    required this.period,
    required this.status,
    this.sourceIds = const [],
  });

  factory ResearchedTenorRate.fromJson(Map<String, dynamic> json) =>
      ResearchedTenorRate(
        fromMonths: (json['fromMonths'] as num).toInt(),
        toMonths: (json['toMonths'] as num).toInt(),
        ratePercentBasisPoints: (json['ratePercentBasisPoints'] as num).toInt(),
        method: InterestMethod.fromDb(json['method'] as String),
        period: InterestRatePeriod.fromDb(json['period'] as String),
        status: ResearchFieldStatus.fromWire(json['status'] as String?),
        sourceIds:
            (json['sourceIds'] as List?)?.cast<String>() ?? const <String>[],
      );

  final int fromMonths;
  final int toMonths;
  final int ratePercentBasisPoints;
  final InterestMethod method;
  final InterestRatePeriod period;
  final ResearchFieldStatus status;
  final List<String> sourceIds;
}

/// Normalized DTO returned by the `ai-card-research` Edge Function — the
/// only shape Flutter ever sees; provider-specific detail never leaks past
/// the backend.
@immutable
class CardResearchResult {
  const CardResearchResult({
    required this.requestId,
    required this.status,
    required this.candidates,
    required this.issuerName,
    required this.productName,
    required this.tier,
    required this.network,
    required this.currencyCode,
    required this.suggestedName,
    required this.creditLimitMinor,
    required this.defaultDueDay,
    required this.statementDay,
    required this.minPaymentMethod,
    required this.minPaymentFixedMinor,
    required this.minPaymentBasisPoints,
    required this.rules,
    required this.installmentTenors,
    required this.sources,
    required this.unresolvedRequiredFields,
    required this.conflicts,
    required this.unsupportedFindings,
    this.errorMessage,
  });

  factory CardResearchResult.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? const {};
    final accountForm =
        json['accountForm'] as Map<String, dynamic>? ?? const {};
    return CardResearchResult(
      requestId: json['requestId'] as String,
      status: ResearchStatus.fromWire(json['status'] as String?),
      errorMessage: json['errorMessage'] as String?,
      candidates:
          (json['candidates'] as List?)
              ?.map((c) => ProductCandidate.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
      issuerName: _parseValue<String>(
        product['issuerName'] as Map<String, dynamic>?,
        (v) => v as String?,
      ),
      productName: _parseValue<String>(
        product['productName'] as Map<String, dynamic>?,
        (v) => v as String?,
      ),
      tier: _parseValue<String>(
        product['tier'] as Map<String, dynamic>?,
        (v) => v as String?,
      ),
      network: _parseValue<CardNetworkGuess>(
        product['network'] as Map<String, dynamic>?,
        (v) => v == null ? null : CardNetworkGuess.fromWire(v as String),
      ),
      currencyCode: _parseValue<String>(
        product['currencyCode'] as Map<String, dynamic>?,
        (v) => v as String?,
      ),
      suggestedName: _parseValue<String>(
        accountForm['suggestedName'] as Map<String, dynamic>?,
        (v) => v as String?,
      ),
      creditLimitMinor: _parseValue<int>(
        accountForm['creditLimitMinor'] as Map<String, dynamic>?,
        (v) => (v as num?)?.toInt(),
      ),
      defaultDueDay: _parseValue<int>(
        accountForm['defaultDueDay'] as Map<String, dynamic>?,
        (v) => (v as num?)?.toInt(),
      ),
      statementDay: _parseValue<int>(
        accountForm['statementDay'] as Map<String, dynamic>?,
        (v) => (v as num?)?.toInt(),
      ),
      minPaymentMethod: _parseValue<MinPaymentMethod>(
        accountForm['minPaymentMethod'] as Map<String, dynamic>?,
        (v) => v == null ? null : MinPaymentMethod.fromDb(v as String),
      ),
      minPaymentFixedMinor: _parseValue<int>(
        accountForm['minPaymentFixedMinor'] as Map<String, dynamic>?,
        (v) => (v as num?)?.toInt(),
      ),
      minPaymentBasisPoints: _parseValue<int>(
        accountForm['minPaymentBasisPoints'] as Map<String, dynamic>?,
        (v) => (v as num?)?.toInt(),
      ),
      rules:
          (json['rules'] as List?)
              ?.map(
                (r) => ResearchedFeeRule.fromJson(r as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      installmentTenors:
          (json['installmentTenors'] as List?)
              ?.map(
                (t) => ResearchedTenorRate.fromJson(t as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      sources:
          (json['sources'] as List?)
              ?.map((s) => ResearchSource.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      unresolvedRequiredFields:
          (json['unresolvedRequiredFields'] as List?)?.cast<String>() ??
          const [],
      conflicts:
          (json['conflicts'] as List?)
              ?.map(
                (c) => CardResearchConflict.fromJson(c as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      unsupportedFindings:
          (json['unsupportedFindings'] as List?)
              ?.map(
                (f) => UnsupportedFinding.fromJson(f as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  final String requestId;
  final ResearchStatus status;
  final String? errorMessage;
  final List<ProductCandidate> candidates;
  final ResearchedValue<String> issuerName;
  final ResearchedValue<String> productName;
  final ResearchedValue<String> tier;
  final ResearchedValue<CardNetworkGuess> network;
  final ResearchedValue<String> currencyCode;
  final ResearchedValue<String> suggestedName;
  final ResearchedValue<int> creditLimitMinor;
  final ResearchedValue<int> defaultDueDay;
  final ResearchedValue<int> statementDay;
  final ResearchedValue<MinPaymentMethod> minPaymentMethod;
  final ResearchedValue<int> minPaymentFixedMinor;
  final ResearchedValue<int> minPaymentBasisPoints;
  final List<ResearchedFeeRule> rules;
  final List<ResearchedTenorRate> installmentTenors;
  final List<ResearchSource> sources;
  final List<String> unresolvedRequiredFields;
  final List<CardResearchConflict> conflicts;
  final List<UnsupportedFinding> unsupportedFindings;
}

/// Request payload sent to the `ai-card-research` Edge Function. Only
/// product-identifying data — never a prompt, never tool instructions.
@immutable
class CardResearchRequest {
  const CardResearchRequest({
    required this.requestId,
    required this.accountType,
    required this.issuerName,
    required this.countryCode,
    required this.productName,
    this.officialWebsite,
    this.tier,
    this.network,
    this.currencyCode,
    this.activationDate,
    this.knownCreditLimitMinor,
    this.knownStatementDay,
    this.knownDueDay,
    this.bnplTypicalTenorMonths,
    this.userNotes,
    this.selectedProductId,
  }) : assert(
         accountType == AccountType.creditCard ||
             accountType == AccountType.bnpl,
         'AI research only applies to Credit Card and BNPL accounts',
       );

  final String requestId;
  final AccountType accountType;
  final String issuerName;
  final String countryCode;
  final String productName;
  final String? officialWebsite;
  final String? tier;
  final CardNetworkGuess? network;
  final String? currencyCode;
  final String? activationDate;
  final int? knownCreditLimitMinor;
  final int? knownStatementDay;
  final int? knownDueDay;
  final int? bnplTypicalTenorMonths;
  final String? userNotes;
  final String? selectedProductId;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'accountType': accountType.dbValue,
    'issuerName': issuerName,
    'countryCode': countryCode,
    'officialWebsite': officialWebsite,
    'productName': productName,
    'tier': tier,
    'network': network?.wireValue,
    'currencyCode': currencyCode,
    'activationDate': activationDate,
    'knownCreditLimitMinor': knownCreditLimitMinor,
    'knownStatementDay': knownStatementDay,
    'knownDueDay': knownDueDay,
    'bnplTypicalTenorMonths': bnplTypicalTenorMonths,
    'userNotes': userNotes,
    'selectedProductId': selectedProductId,
  };

  CardResearchRequest copyWith({String? selectedProductId}) =>
      CardResearchRequest(
        requestId: requestId,
        accountType: accountType,
        issuerName: issuerName,
        countryCode: countryCode,
        productName: productName,
        officialWebsite: officialWebsite,
        tier: tier,
        network: network,
        currencyCode: currencyCode,
        activationDate: activationDate,
        knownCreditLimitMinor: knownCreditLimitMinor,
        knownStatementDay: knownStatementDay,
        knownDueDay: knownDueDay,
        bnplTypicalTenorMonths: bnplTypicalTenorMonths,
        userNotes: userNotes,
        selectedProductId: selectedProductId ?? this.selectedProductId,
      );
}

/// The autofill state machine (task spec section 26-27). The Create
/// listener must only ever fire from [readyToAutoSubmit], and only once.
enum AiAutofillPhase {
  idle,
  researching,
  needsDisambiguation,
  applyingAutofill,
  autofillApplied,
  validating,
  readyToAutoSubmit,
  submitting,
  incomplete,
  failed,
}
