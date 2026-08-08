import 'package:meta/meta.dart';
import 'package:work_tracker/core/money/money.dart';

enum CommercialPlan { free, pro }

enum EntitlementSource {
  free,
  paid,
  adminGrant,
  earlyAccess,
  openEarlyAccess,
  standardTrial,
}

enum MonetizationMode { openEarlyAccess, timedEarlyAccess, paidLive }

@immutable
class PlanPrice {
  const PlanPrice({
    required this.id,
    required this.plan,
    required this.provider,
    required this.interval,
    required this.money,
    required this.providerProductId,
    required this.providerBasePlanId,
    required this.providerSyncStatus,
  });

  factory PlanPrice.fromJson(Map<String, dynamic> json) => PlanPrice(
    id: json['id'] as String,
    plan: _plan(json['plan_key'] as String),
    provider: json['provider'] as String,
    interval: json['interval'] as String,
    money: Money(
      minor: json['amount_minor'] as int,
      currencyCode: json['currency_code'] as String,
    ),
    providerProductId: json['provider_product_id'] as String?,
    providerBasePlanId: json['provider_base_plan_id'] as String?,
    providerSyncStatus: json['provider_sync_status'] as String,
  );

  final String id;
  final CommercialPlan plan;
  final String provider;
  final String interval;
  final Money money;
  final String? providerProductId;
  final String? providerBasePlanId;
  final String providerSyncStatus;

  bool matchesGooglePlayOffer({
    required String productId,
    required String basePlanId,
    required String? offerToken,
  }) =>
      provider == 'google_play' &&
      providerProductId == productId &&
      providerBasePlanId == basePlanId &&
      offerToken != null;

  bool matchesGooglePlayPrice({
    required String currencyCode,
    required double rawPrice,
  }) =>
      money.currencyCode == currencyCode &&
      (rawPrice * 100).round() == money.minor;
}

@immutable
class CommercialCatalog {
  const CommercialCatalog({
    required this.prices,
    required this.monetizationMode,
    required this.billingReady,
    required this.googlePlayConfigured,
    required this.billingTestAccess,
  });

  factory CommercialCatalog.fromJson(Map<String, dynamic> json) {
    final pricesJson = json['prices'] as List<dynamic>? ?? const [];
    final monetization =
        json['monetization'] as Map<String, dynamic>? ?? const {};
    final readiness =
        json['billing_readiness'] as Map<String, dynamic>? ?? const {};
    return CommercialCatalog(
      prices: pricesJson
          .map((e) => PlanPrice.fromJson(e as Map<String, dynamic>))
          .toList(),
      monetizationMode: _mode(monetization['mode'] as String?),
      billingReady:
          readiness['provider'] == 'synced' &&
          readiness['product'] == 'synced' &&
          readiness['verification'] == 'verified',
      googlePlayConfigured:
          readiness['provider'] == 'synced' && readiness['product'] == 'synced',
      billingTestAccess: json['billing_test_access'] == true,
    );
  }

  final List<PlanPrice> prices;
  final MonetizationMode monetizationMode;
  final bool billingReady;

  /// The provider and its configured catalog mapping are ready to be queried.
  /// This deliberately does not require a previous verified purchase so an
  /// authorized tester can exercise the first real checkout safely.
  final bool googlePlayConfigured;
  final bool billingTestAccess;

  PlanPrice? googlePlayPrice(String interval) {
    for (final price in prices) {
      if (price.plan == CommercialPlan.pro &&
          price.provider == 'google_play' &&
          price.interval == interval) {
        return price;
      }
    }
    return null;
  }
}

@immutable
class EffectiveEntitlement {
  const EffectiveEntitlement({
    required this.plan,
    required this.source,
    required this.startsAt,
    required this.endsAt,
    required this.subscriptionStatus,
    required this.renewalAt,
    required this.features,
    required this.limits,
    required this.metadata,
  });

  factory EffectiveEntitlement.free() => const EffectiveEntitlement(
    plan: CommercialPlan.free,
    source: EntitlementSource.free,
    startsAt: null,
    endsAt: null,
    subscriptionStatus: null,
    renewalAt: null,
    features: {},
    limits: {},
    metadata: {},
  );

  factory EffectiveEntitlement.fromJson(Map<String, dynamic> json) =>
      EffectiveEntitlement(
        plan: _plan(json['effective_plan'] as String),
        source: _source(json['source'] as String),
        startsAt: _date(json['starts_at']),
        endsAt: _date(json['ends_at']),
        subscriptionStatus: json['subscription_status'] as String?,
        renewalAt: _date(json['renewal_at']),
        features: Map<String, bool>.from(json['features'] as Map),
        limits: (json['limits'] as Map).map(
          (key, value) => MapEntry(key as String, value as int?),
        ),
        metadata: Map<String, dynamic>.from(
          json['metadata'] as Map? ?? const {},
        ),
      );

  final CommercialPlan plan;
  final EntitlementSource source;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? subscriptionStatus;
  final DateTime? renewalAt;
  final Map<String, bool> features;
  final Map<String, int?> limits;
  final Map<String, dynamic> metadata;

  String? get metadataInterval =>
      (metadata['base_plan_id'] as String?)?.contains('annual') == true ||
          (metadata['base_plan_id'] as String?)?.contains('year') == true
      ? 'year'
      : 'month';

  bool get isPro => plan == CommercialPlan.pro;
  bool hasFeature(String key) => features[key] ?? false;
  int? featureLimit(String key) => limits[key];

  int? daysRemaining(DateTime now) {
    final end = endsAt;
    if (end == null) return null;
    final remaining = end.difference(now.toUtc()).inHours / 24;
    if (remaining <= 0) return 0;
    return remaining.ceil();
  }

  String get sourceLabel {
    switch (source) {
      case EntitlementSource.free:
        return 'Free';
      case EntitlementSource.paid:
        return 'Paid Pro';
      case EntitlementSource.adminGrant:
        return 'Super Admin grant';
      case EntitlementSource.earlyAccess:
        return 'Early Access';
      case EntitlementSource.openEarlyAccess:
        return 'Pro Early Access';
      case EntitlementSource.standardTrial:
        return 'Pro Trial';
    }
  }
}

CommercialPlan _plan(String value) =>
    value == 'pro' ? CommercialPlan.pro : CommercialPlan.free;

EntitlementSource _source(String value) {
  switch (value) {
    case 'paid':
      return EntitlementSource.paid;
    case 'admin_grant':
      return EntitlementSource.adminGrant;
    case 'early_access':
      return EntitlementSource.earlyAccess;
    case 'open_early_access':
      return EntitlementSource.openEarlyAccess;
    case 'standard_trial':
      return EntitlementSource.standardTrial;
    default:
      return EntitlementSource.free;
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

MonetizationMode _mode(String? value) {
  switch (value) {
    case 'timed_early_access':
      return MonetizationMode.timedEarlyAccess;
    case 'paid_live':
      return MonetizationMode.paidLive;
    default:
      return MonetizationMode.openEarlyAccess;
  }
}
