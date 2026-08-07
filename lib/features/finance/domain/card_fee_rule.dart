import 'package:flutter/foundation.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/money/money.dart';

/// A row from `app_finance.credit_card_fee_rules`: one recurring or one-off
/// card fee (annual membership, insurance, …). Created and versioned
/// through `save_credit_card_fee_rule` / `create_fee_rule_version`; the
/// generated fee charges themselves are ledger rows written only by the
/// server-side materializers.
///
/// [state] is tri-state on purpose: an [CardRuleState.unknown] rule never
/// charges and must never be displayed as if it were a configured zero.
/// When [state] is [CardRuleState.configured], exactly one of
/// [fixedAmountMinor] or ([percentBasisPoints] + [percentBasis]) is set,
/// mirroring version 1's calculation shape at creation time; a later rate
/// change via `create_fee_rule_version` is not reflected here — read
/// `credit_card_fee_rule_current` for the live effective rate once a card
/// has more than one version.
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
    required this.state,
    this.triggerKind = CardRuleTrigger.schedule,
    this.mutualExclusionGroup,
    this.priority = 100,
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
      state: CardRuleState.fromDb(json['state'] as String),
      triggerKind: CardRuleTrigger.fromDb(json['trigger_kind'] as String),
      mutualExclusionGroup: json['mutual_exclusion_group'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 100,
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
  final CardRuleState state;
  final CardRuleTrigger triggerKind;
  final String? mutualExclusionGroup;
  final int priority;
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

/// Create/edit payload for a fee rule, sent to `save_credit_card_fee_rule`.
/// Creating a rule also creates its first version there; editing an
/// existing rule through this draft only ever touches identity fields
/// (name, category, state, mutual-exclusion group, priority, notes) —
/// changing a rate goes through `create_fee_rule_version` instead, so a
/// rate change is always dated rather than silently rewriting history.
@immutable
class CardFeeRuleDraft {
  const CardFeeRuleDraft({
    required this.accountId,
    required this.name,
    required this.feeType,
    required this.frequency,
    required this.startsOn,
    required this.categoryId,
    required this.state,
    this.triggerKind = CardRuleTrigger.schedule,
    this.calculationType = CardRuleCalculationType.manual,
    this.fixedAmountMinor,
    this.percentBasisPoints,
    this.percentBasis,
    this.minimumMinor,
    this.maximumMinor,
    this.lookbackCycles,
    this.mutualExclusionGroup,
    this.priority = 100,
    this.notes,
  }) : assert(
         state != CardRuleState.configured ||
             calculationType != CardRuleCalculationType.manual,
         'a configured rule needs a real calculation',
       );

  final String accountId;
  final String name;
  final CardFeeType feeType;
  final FeeFrequency frequency;
  final PlainDate startsOn;
  final String categoryId;
  final CardRuleState state;
  final CardRuleTrigger triggerKind;
  final CardRuleCalculationType calculationType;
  final int? fixedAmountMinor;
  final int? percentBasisPoints;
  final FeePercentBasis? percentBasis;
  final int? minimumMinor;
  final int? maximumMinor;
  final int? lookbackCycles;
  final String? mutualExclusionGroup;
  final int priority;
  final String? notes;

  /// Named params for `save_credit_card_fee_rule`; pass `ruleId` to edit an
  /// existing rule's identity fields instead of creating a new one.
  Map<String, dynamic> toRpcParams({String? ruleId}) => {
    'p_account_id': accountId,
    'p_name': name,
    'p_fee_type': feeType.dbValue,
    'p_category_id': categoryId,
    'p_state': state.dbValue,
    'p_trigger_kind': triggerKind.dbValue,
    'p_starts_on': startsOn.toIso(),
    'p_calculation_type': calculationType.dbValue,
    'p_fixed_amount_minor': fixedAmountMinor,
    'p_percent_basis_points': percentBasisPoints,
    'p_percent_basis': percentBasis?.dbValue,
    'p_minimum_minor': minimumMinor,
    'p_maximum_minor': maximumMinor,
    'p_lookback_cycles': lookbackCycles,
    'p_frequency': frequency.dbValue,
    'p_mutual_exclusion_group': mutualExclusionGroup,
    'p_priority': priority,
    'p_notes': notes,
    'p_rule_id': ruleId,
  };
}
