import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/card_fee_rule.dart';

void main() {
  group('CardFeeRule', () {
    test('parses a fixed-amount rule', () {
      final rule = CardFeeRule.fromJson(const {
        'id': 'rule-1',
        'account_id': 'facility-1',
        'name': 'Annual Membership',
        'fee_type': 'annual_membership',
        'frequency': 'annually',
        'starts_on': '2026-05-01',
        'category_id': 'cat-1',
        'is_active': true,
        'state': 'configured',
        'trigger_kind': 'schedule',
        'mutual_exclusion_group': null,
        'priority': 100,
        'fixed_amount_minor': 20000,
        'percent_basis_points': null,
        'percent_basis': null,
        'next_charge_on': '2027-05-01',
        'notes': null,
      });
      expect(rule.isPercent, isFalse);
      expect(rule.fixedAmount('EGP')!.minor, 20000);
      expect(rule.percentValue, isNull);
      expect(rule.nextChargeOn, PlainDate.parse('2027-05-01'));
      expect(rule.frequency, FeeFrequency.annually);
      expect(rule.state, CardRuleState.configured);
      expect(rule.triggerKind, CardRuleTrigger.schedule);
      expect(rule.mutualExclusionGroup, isNull);
      expect(rule.priority, 100);
    });

    test('parses a percent rule and exposes a display rate', () {
      final rule = CardFeeRule.fromJson(const {
        'id': 'rule-2',
        'account_id': 'facility-1',
        'name': 'Insurance',
        'fee_type': 'insurance',
        'frequency': 'monthly',
        'starts_on': '2026-05-01',
        'category_id': 'cat-1',
        'is_active': false,
        'state': 'disabled',
        'trigger_kind': 'schedule',
        'mutual_exclusion_group': 'protection',
        'priority': 10,
        'fixed_amount_minor': null,
        'percent_basis_points': 150,
        'percent_basis': 'outstanding_balance',
        'next_charge_on': null,
        'notes': null,
      });
      expect(rule.isPercent, isTrue);
      expect(rule.percentValue, 1.5);
      expect(rule.percentBasis, FeePercentBasis.outstandingBalance);
      expect(rule.fixedAmount('EGP'), isNull);
      expect(rule.state, CardRuleState.disabled);
      expect(rule.mutualExclusionGroup, 'protection');
      expect(rule.priority, 10);
    });

    test('parses an unknown-state rule with no calculation', () {
      final rule = CardFeeRule.fromJson(const {
        'id': 'rule-3',
        'account_id': 'facility-1',
        'name': 'Foreign Markup',
        'fee_type': 'foreign_transaction',
        'frequency': 'per_transaction',
        'starts_on': '2026-05-01',
        'category_id': 'cat-1',
        'is_active': false,
        'state': 'unknown',
        'trigger_kind': 'foreign_transaction',
        'mutual_exclusion_group': null,
        'priority': 100,
        'fixed_amount_minor': null,
        'percent_basis_points': null,
        'percent_basis': null,
        'next_charge_on': null,
        'notes': null,
      });
      expect(rule.state, CardRuleState.unknown);
      expect(rule.isActive, isFalse);
      expect(rule.fixedAmount('EGP'), isNull);
      expect(rule.percentValue, isNull);
    });

    test('drafts build the save_credit_card_fee_rule RPC params', () {
      final fixed = CardFeeRuleDraft(
        accountId: 'facility-1',
        name: 'Annual Membership',
        feeType: CardFeeType.annualMembership,
        frequency: FeeFrequency.annually,
        startsOn: PlainDate.parse('2026-05-01'),
        categoryId: 'cat-1',
        state: CardRuleState.configured,
        calculationType: CardRuleCalculationType.fixed,
        fixedAmountMinor: 20000,
      );
      final params = fixed.toRpcParams();
      expect(params['p_fixed_amount_minor'], 20000);
      expect(params['p_percent_basis_points'], isNull);
      expect(params['p_percent_basis'], isNull);
      expect(params['p_state'], 'configured');
      expect(params['p_calculation_type'], 'fixed');
      expect(params['p_starts_on'], '2026-05-01');
      expect(params['p_rule_id'], isNull);

      final editing = fixed.toRpcParams(ruleId: 'rule-1');
      expect(editing['p_rule_id'], 'rule-1');
    });

    test('an unknown-state draft carries no calculation', () {
      final unknown = CardFeeRuleDraft(
        accountId: 'facility-1',
        name: 'Foreign Markup',
        feeType: CardFeeType.foreignTransaction,
        frequency: FeeFrequency.perTransaction,
        startsOn: PlainDate.parse('2026-05-01'),
        categoryId: 'cat-1',
        state: CardRuleState.unknown,
        triggerKind: CardRuleTrigger.foreignTransaction,
      );
      final params = unknown.toRpcParams();
      expect(params['p_state'], 'unknown');
      expect(params['p_calculation_type'], 'manual');
      expect(params['p_fixed_amount_minor'], isNull);
      expect(params['p_percent_basis_points'], isNull);
    });

    test('a configured draft requires a real calculation', () {
      expect(
        () => CardFeeRuleDraft(
          accountId: 'facility-1',
          name: 'Broken',
          feeType: CardFeeType.other,
          frequency: FeeFrequency.once,
          startsOn: PlainDate.parse('2026-05-01'),
          categoryId: 'cat-1',
          state: CardRuleState.configured,
        ),
        throwsAssertionError,
      );
    });

    test('a percentage draft carries minimum, maximum, and lookback', () {
      final draft = CardFeeRuleDraft(
        accountId: 'facility-1',
        name: 'Quarterly Stamp Duty',
        feeType: CardFeeType.stampTax,
        frequency: FeeFrequency.quarterly,
        startsOn: PlainDate.parse('2026-05-01'),
        categoryId: 'cat-1',
        state: CardRuleState.configured,
        calculationType: CardRuleCalculationType.percentage,
        percentBasisPoints: 5,
        percentBasis: FeePercentBasis.highestStatementDueLookback,
        minimumMinor: 100,
        maximumMinor: 5000,
        lookbackCycles: 3,
      );
      final params = draft.toRpcParams();
      expect(params['p_percent_basis'], 'highest_statement_due_lookback');
      expect(params['p_minimum_minor'], 100);
      expect(params['p_maximum_minor'], 5000);
      expect(params['p_lookback_cycles'], 3);
    });

    test('a foreign-transaction draft carries its trigger and condition', () {
      final draft = CardFeeRuleDraft(
        accountId: 'facility-1',
        name: 'Foreign Exchange Fee',
        feeType: CardFeeType.foreignTransaction,
        frequency: FeeFrequency.perTransaction,
        startsOn: PlainDate.parse('2026-06-01'),
        categoryId: 'cat-1',
        state: CardRuleState.configured,
        triggerKind: CardRuleTrigger.foreignTransaction,
        calculationType: CardRuleCalculationType.percentage,
        percentBasisPoints: 300,
        percentBasis: FeePercentBasis.transactionAmount,
        applyWhen: ForeignApplyWhen.foreignMerchantHomeCurrency,
      );
      final params = draft.toRpcParams();
      expect(params['p_trigger_kind'], 'foreign_transaction');
      expect(params['p_frequency'], 'per_transaction');
      expect(params['p_percent_basis'], 'transaction_amount');
      expect(params['p_apply_when'], 'foreign_merchant_home_currency');
    });

    test('a schedule draft carries no apply-when condition', () {
      final draft = CardFeeRuleDraft(
        accountId: 'facility-1',
        name: 'Stamp Duty',
        feeType: CardFeeType.stampTax,
        frequency: FeeFrequency.quarterly,
        startsOn: PlainDate.parse('2026-07-01'),
        categoryId: 'cat-1',
        state: CardRuleState.configured,
        calculationType: CardRuleCalculationType.percentage,
        percentBasisPoints: 5,
        percentBasis: FeePercentBasis.highestDailyBalanceLookback,
        lookbackCycles: 3,
      );
      final params = draft.toRpcParams();
      expect(params['p_apply_when'], isNull);
      expect(params['p_percent_basis'], 'highest_daily_balance_lookback');
    });

    test('fee types map to the trigger that materializes them', () {
      expect(
        cardFeeTypeTrigger(CardFeeType.foreignTransaction),
        CardRuleTrigger.foreignTransaction,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.cashAdvance),
        CardRuleTrigger.domesticCashAdvance,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.internationalCashAdvance),
        CardRuleTrigger.internationalCashAdvance,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.walletFee),
        CardRuleTrigger.walletTransaction,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.latePayment),
        CardRuleTrigger.latePaymentMissedMinimum,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.overLimit),
        CardRuleTrigger.overLimitEvent,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.earlySettlement),
        CardRuleTrigger.earlySettlement,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.annualMembership),
        CardRuleTrigger.schedule,
      );
      expect(
        cardFeeTypeTrigger(CardFeeType.stampTax),
        CardRuleTrigger.schedule,
      );
    });
  });
}
