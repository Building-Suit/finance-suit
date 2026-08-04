import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `app_finance.credit_card_fee_rules`: one recurring or one-off
/// card fee (annual membership, insurance, …). The rule is client-editable;
/// the generated fee charges themselves are ledger rows written only by
/// `apply_credit_card_fees`.
///
/// Exactly one of [fixedAmountMinor] or ([percentBasisPoints] +
/// [percentBasis]) is set, mirroring the table's shape constraint.
@immutable
class CardFeeRule {
  const CardFeeRule({
    required this.id,
    required this.accountId,
    required this.name,
    required this.feeType,
    required this.frequency,
    required this.startsOn,
    required this.categoryId,
    required this.isActive,
    this.fixedAmountMinor,
    this.percentBasisPoints,
    this.percentBasis,
    this.nextChargeOn,
    this.notes,
  });

  factory CardFeeRule.fromJson(Map<String, dynamic> json) {
    return CardFeeRule(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      name: json['name'] as String,
      feeType: CardFeeType.fromDb(json['fee_type'] as String),
      frequency: FeeFrequency.fromDb(json['frequency'] as String),
      startsOn: PlainDate.parse(json['starts_on'] as String),
      categoryId: json['category_id'] as String,
      isActive: json['is_active'] as bool,
      fixedAmountMinor: (json['fixed_amount_minor'] as num?)?.toInt(),
      percentBasisPoints: (json['percent_basis_points'] as num?)?.toInt(),
      percentBasis: json['percent_basis'] == null
          ? null
          : FeePercentBasis.fromDb(json['percent_basis'] as String),
      nextChargeOn: json['next_charge_on'] == null
          ? null
          : PlainDate.parse(json['next_charge_on'] as String),
      notes: json['notes'] as String?,
    );
  }

  final String id;
  final String accountId;
  final String name;
  final CardFeeType feeType;
  final FeeFrequency frequency;
  final PlainDate startsOn;
  final String categoryId;
  final bool isActive;
  final int? fixedAmountMinor;
  final int? percentBasisPoints;
  final FeePercentBasis? percentBasis;
  final PlainDate? nextChargeOn;
  final String? notes;

  bool get isPercent => percentBasisPoints != null;

  Money? fixedAmount(String currencyCode) => fixedAmountMinor == null
      ? null
      : Money(minor: fixedAmountMinor!, currencyCode: currencyCode);

  /// Percent as a display fraction, e.g. 150 basis points -> 1.5.
  double? get percentValue =>
      percentBasisPoints == null ? null : percentBasisPoints! / 100;
}

/// Insert/update payload for a fee rule. The row is owner-writable under
/// RLS; charges stay locked to the generator RPC.
@immutable
class CardFeeRuleDraft {
  const CardFeeRuleDraft({
    required this.accountId,
    required this.name,
    required this.feeType,
    required this.frequency,
    required this.startsOn,
    required this.categoryId,
    this.fixedAmountMinor,
    this.percentBasisPoints,
    this.percentBasis,
    this.notes,
  }) : assert(
         (fixedAmountMinor != null) ^ (percentBasisPoints != null),
         'exactly one of fixed amount or percent must be set',
       );

  final String accountId;
  final String name;
  final CardFeeType feeType;
  final FeeFrequency frequency;
  final PlainDate startsOn;
  final String categoryId;
  final int? fixedAmountMinor;
  final int? percentBasisPoints;
  final FeePercentBasis? percentBasis;
  final String? notes;

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'account_id': accountId,
    'name': name,
    'fee_type': feeType.dbValue,
    'frequency': frequency.dbValue,
    'starts_on': startsOn.toIso(),
    'category_id': categoryId,
    'fixed_amount_minor': fixedAmountMinor,
    'percent_basis_points': percentBasisPoints,
    'percent_basis': percentBasis?.dbValue,
    'notes': notes,
  };
}
