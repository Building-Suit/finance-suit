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

enum CardResearchOrigin { liveAi, catalog }

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

  /// User-provided values remain authoritative. Researched values must be
  /// verified, carry source provenance, and have non-low confidence before
  /// they are safe to write into the form automatically.
  bool get isAutofillEligible =>
      value != null &&
      (status == ResearchFieldStatus.userProvided ||
          (status == ResearchFieldStatus.verified &&
              sourceIds.isNotEmpty &&
              confidence != null &&
              confidence != ConfidenceLevel.low));
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
    publishedDate:
        (json['publicationDate'] ?? json['publishedDate']) as String?,
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

/// Public product identity used by catalog lookup and queueing. This type is
/// deliberately unable to carry account limits, dates, notes, or credentials.
@immutable
class CatalogProductIdentity {
  const CatalogProductIdentity({
    required this.accountType,
    required this.countryCode,
    required this.issuerName,
    required this.productName,
    this.tier,
    this.network,
    this.currencyCode,
    this.officialWebsite,
  });

  factory CatalogProductIdentity.fromRequest(CardResearchRequest request) =>
      CatalogProductIdentity(
        accountType: request.accountType,
        countryCode: request.countryCode.trim().toUpperCase(),
        issuerName: request.issuerName.trim(),
        productName: request.productName.trim(),
        tier: request.tier?.trim(),
        network: request.network,
        currencyCode: request.currencyCode?.trim().toUpperCase(),
        officialWebsite: request.officialWebsite?.trim(),
      );

  final AccountType accountType;
  final String countryCode;
  final String issuerName;
  final String productName;
  final String? tier;
  final CardNetworkGuess? network;
  final String? currencyCode;
  final String? officialWebsite;

  Map<String, dynamic> toSearchParams() => {
    'p_account_type': accountType.dbValue,
    'p_country_code': countryCode,
    'p_issuer_name': issuerName,
    'p_product_name': productName,
    'p_tier': tier,
    'p_network': network?.wireValue,
    'p_currency_code': currencyCode,
  };

  Map<String, dynamic> toEnqueueParams(String reason) => {
    ...toSearchParams(),
    'p_official_website': officialWebsite,
    'p_reason': reason,
    'p_priority': 0,
  };
}

/// One normalized row returned by `catalog_search`.
@immutable
class CatalogResearchMatch {
  const CatalogResearchMatch({
    required this.productId,
    required this.versionId,
    required this.identity,
    required this.researchPayload,
    required this.sources,
    required this.verifiedAt,
    required this.isFresh,
    required this.ageDays,
    required this.matchQuality,
  });

  factory CatalogResearchMatch.fromJson(Map<String, dynamic> json) {
    final accountType = AccountType.fromDb(json['account_type'] as String);
    return CatalogResearchMatch(
      productId: json['catalog_product_id'] as String,
      versionId: json['catalog_version_id'] as String,
      identity: CatalogProductIdentity(
        accountType: accountType,
        countryCode: json['country_code'] as String,
        issuerName: json['issuer_name'] as String,
        productName: json['product_name'] as String,
        tier: json['tier'] as String?,
        network: json['network'] == null
            ? null
            : CardNetworkGuess.fromWire(json['network'] as String),
        currencyCode: json['currency_code'] as String?,
        officialWebsite: json['official_website'] as String?,
      ),
      researchPayload: Map<String, dynamic>.from(
        json['research_payload'] as Map,
      ),
      sources:
          (json['sources'] as List?)
              ?.map((source) => Map<String, dynamic>.from(source as Map))
              .toList() ??
          const [],
      verifiedAt: DateTime.parse(json['verified_at'] as String).toUtc(),
      isFresh: json['is_fresh'] as bool? ?? false,
      ageDays: (json['age_days'] as num?)?.toInt() ?? 0,
      matchQuality: (json['match_quality'] as num?)?.toInt() ?? 0,
    );
  }

  final String productId;
  final String versionId;
  final CatalogProductIdentity identity;
  final Map<String, dynamic> researchPayload;
  final List<Map<String, dynamic>> sources;
  final DateTime verifiedAt;
  final bool isFresh;
  final int ageDays;
  final int matchQuality;

  String get label => [
    identity.issuerName,
    identity.productName,
    identity.tier,
    identity.network?.wireValue,
  ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');

  CardResearchResult toResearchResult(CardResearchRequest request) {
    final payload = Map<String, dynamic>.from(researchPayload);
    payload['requestId'] = 'catalog:$versionId';
    payload['status'] = ResearchStatus.resolved.wireValue;
    if (sources.isNotEmpty) payload['sources'] = sources;
    return CardResearchResult.fromJson(payload).withCatalogMetadata(
      productId: productId,
      versionId: versionId,
      verifiedAt: verifiedAt,
      request: request,
    );
  }
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
        ratePercentBasisPoints:
            ((json['ratePercentBasisPoints'] ?? json['rateBasisPoints']) as num)
                .toInt(),
        method: InterestMethod.fromDb(
          (json['method'] ?? json['interestMethod']) as String,
        ),
        period: InterestRatePeriod.fromDb(
          (json['period'] ?? json['ratePeriod']) as String,
        ),
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
    this.origin = CardResearchOrigin.liveAi,
    this.catalogProductId,
    this.catalogVersionId,
    this.catalogVerifiedAt,
    this.catalogMatches = const [],
  });

  factory CardResearchResult.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? const {};
    final accountForm =
        json['accountForm'] as Map<String, dynamic>? ?? const {};
    final installments =
        json['installments'] as Map<String, dynamic>? ?? const {};
    final feeRows = (json['fees'] ?? json['rules']) as List? ?? const [];
    final tenorRows =
        (installments['tenors'] ?? json['installmentTenors']) as List? ??
        const [];
    final conflictRows = (json['conflicts'] as List?) ?? const [];
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
      // Catalog v2 covers more fee and installment concepts than the current
      // account editor. Preserve temporary compatibility by carrying only
      // rows the existing enums/form can represent; Prompt 2 owns the full
      // model and UI expansion.
      rules: feeRows
          .whereType<Map<Object?, Object?>>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(_isLegacyCompatibleFee)
          .map(ResearchedFeeRule.fromJson)
          .toList(growable: false),
      installmentTenors: tenorRows
          .whereType<Map<Object?, Object?>>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(_isLegacyCompatibleTenor)
          .map(ResearchedTenorRate.fromJson)
          .toList(growable: false),
      sources:
          (json['sources'] as List?)
              ?.map((s) => ResearchSource.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      unresolvedRequiredFields:
          (json['unresolvedRequiredFields'] as List?)?.cast<String>() ??
          const [],
      // v2 conflicts compare public sources; the legacy UI compares user
      // input with official values. Do not mislabel public-source conflicts
      // as user conflicts while that screen is being upgraded.
      conflicts: conflictRows
          .whereType<Map<Object?, Object?>>()
          .map((row) => Map<String, dynamic>.from(row))
          .where(
            (row) =>
                row.containsKey('userValue') &&
                row.containsKey('officialValue'),
          )
          .map(CardResearchConflict.fromJson)
          .toList(growable: false),
      unsupportedFindings:
          (json['unsupportedFindings'] as List?)
              ?.map(
                (f) => UnsupportedFinding.fromJson(f as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  static bool _isLegacyCompatibleFee(Map<String, dynamic> row) {
    final feeType = row['feeType'];
    final calculationType = row['calculationType'];
    final frequency = row['frequency'];
    return feeType is String &&
        CardFeeType.values.any((value) => value.dbValue == feeType) &&
        calculationType is String &&
        CardRuleCalculationType.values.any(
          (value) => value.dbValue == calculationType,
        ) &&
        frequency is String &&
        FeeFrequency.values.any((value) => value.dbValue == frequency);
  }

  static bool _isLegacyCompatibleTenor(Map<String, dynamic> row) {
    final rate = row['ratePercentBasisPoints'] ?? row['rateBasisPoints'];
    final method = row['method'] ?? row['interestMethod'];
    final period = row['period'] ?? row['ratePeriod'];
    return row['fromMonths'] is num &&
        row['toMonths'] is num &&
        rate is num &&
        method is String &&
        InterestMethod.values.any((value) => value.dbValue == method) &&
        period is String &&
        InterestRatePeriod.values.any((value) => value.dbValue == period);
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
  final CardResearchOrigin origin;
  final String? catalogProductId;
  final String? catalogVersionId;
  final DateTime? catalogVerifiedAt;
  final List<CatalogResearchMatch> catalogMatches;

  CardResearchResult withCatalogMetadata({
    required String productId,
    required String versionId,
    required DateTime verifiedAt,
    required CardResearchRequest request,
  }) => CardResearchResult(
    requestId: requestId,
    status: status,
    candidates: candidates,
    issuerName: issuerName,
    productName: productName,
    tier: tier,
    network: network,
    currencyCode: currencyCode,
    suggestedName: suggestedName,
    creditLimitMinor: request.knownCreditLimitMinor == null
        ? creditLimitMinor
        : _userProvided(request.knownCreditLimitMinor!),
    defaultDueDay: request.knownDueDay == null
        ? defaultDueDay
        : _userProvided(request.knownDueDay!),
    statementDay: request.knownStatementDay == null
        ? statementDay
        : _userProvided(request.knownStatementDay!),
    minPaymentMethod: minPaymentMethod,
    minPaymentFixedMinor: minPaymentFixedMinor,
    minPaymentBasisPoints: minPaymentBasisPoints,
    rules: rules,
    installmentTenors: installmentTenors,
    sources: sources,
    unresolvedRequiredFields: unresolvedRequiredFields,
    conflicts: conflicts,
    unsupportedFindings: unsupportedFindings,
    errorMessage: errorMessage,
    origin: CardResearchOrigin.catalog,
    catalogProductId: productId,
    catalogVersionId: versionId,
    catalogVerifiedAt: verifiedAt,
  );

  static ResearchedValue<T> _userProvided<T>(T value) => ResearchedValue<T>(
    value: value,
    status: ResearchFieldStatus.userProvided,
    confidence: ConfidenceLevel.high,
  );
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
    this.catalogMatches = const [],
    this.skipCatalog = false,
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

  /// Session-only matches used after disambiguation; never serialized.
  final List<CatalogResearchMatch> catalogMatches;

  /// Session-only flag preventing another lookup after live disambiguation.
  final bool skipCatalog;

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
        catalogMatches: catalogMatches,
        skipCatalog: skipCatalog,
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
