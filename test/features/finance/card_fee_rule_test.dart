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
    });

    test('drafts serialize exactly one amount shape', () {
      final fixed = CardFeeRuleDraft(
        accountId: 'facility-1',
        name: 'Annual Membership',
        feeType: CardFeeType.annualMembership,
        frequency: FeeFrequency.annually,
        startsOn: PlainDate.parse('2026-05-01'),
        categoryId: 'cat-1',
        fixedAmountMinor: 20000,
      );
      final json = fixed.toJson('user-1');
      expect(json['fixed_amount_minor'], 20000);
      expect(json['percent_basis_points'], isNull);
      expect(json['percent_basis'], isNull);
      expect(json['user_id'], 'user-1');
      expect(json['starts_on'], '2026-05-01');

      expect(
        () => CardFeeRuleDraft(
          accountId: 'facility-1',
          name: 'Broken',
          feeType: CardFeeType.other,
          frequency: FeeFrequency.once,
          startsOn: PlainDate.parse('2026-05-01'),
          categoryId: 'cat-1',
          fixedAmountMinor: 1000,
          percentBasisPoints: 100,
        ),
        throwsAssertionError,
      );
    });
  });
}
