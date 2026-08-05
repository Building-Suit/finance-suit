import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/recurring_rule.dart';

void main() {
  group('RecurringRule', () {
    test('parses an expense rule', () {
      final rule = RecurringRule.fromJson(const {
        'id': 'rule-1',
        'name': 'Internet',
        'rule_kind': 'expense',
        'amount_minor': 50000,
        'currency_code': 'EGP',
        'frequency': 'monthly',
        'payment_day': 5,
        'start_date': '2026-01-01',
        'prompt_days_before': 3,
        'source_account_id': 'acc-1',
        'is_active': true,
        'destination_account_id': null,
        'category_id': 'cat-1',
        'notes': null,
      });
      expect(rule.kind, RecurringRuleKind.expense);
      expect(rule.frequency, RecurringFrequency.monthly);
      expect(rule.amount.minor, 50000);
      expect(rule.categoryId, 'cat-1');
      expect(rule.destinationAccountId, isNull);
      expect(rule.startDate, PlainDate.parse('2026-01-01'));
    });

    test('parses a weekly transfer rule', () {
      final rule = RecurringRule.fromJson(const {
        'id': 'rule-2',
        'name': 'To Savings',
        'rule_kind': 'transfer',
        'amount_minor': 100000,
        'currency_code': 'EGP',
        'frequency': 'weekly',
        'payment_day': 1,
        'start_date': '2026-01-01',
        'prompt_days_before': 0,
        'source_account_id': 'acc-1',
        'is_active': false,
        'destination_account_id': 'acc-2',
        'category_id': null,
        'notes': 'note',
      });
      expect(rule.kind, RecurringRuleKind.transfer);
      expect(rule.frequency, RecurringFrequency.weekly);
      expect(rule.paymentDay, 1);
      expect(rule.destinationAccountId, 'acc-2');
      expect(rule.isActive, isFalse);
    });
  });

  group('PendingRecurring', () {
    RecurringOccurrence occurrence(String scheduledOn) =>
        RecurringOccurrence.fromJson({
          'id': 'occ-1',
          'rule_id': 'rule-1',
          'scheduled_on': scheduledOn,
          'expected_amount_minor': 50000,
          'status': 'pending',
          'actual_amount_minor': null,
          'paid_on': null,
          'transaction_id': null,
          'snoozed_until': null,
          'notes': null,
        });

    final rule = RecurringRule.fromJson(const {
      'id': 'rule-1',
      'name': 'Internet',
      'rule_kind': 'expense',
      'amount_minor': 50000,
      'currency_code': 'EGP',
      'frequency': 'monthly',
      'payment_day': 5,
      'start_date': '2026-01-01',
      'prompt_days_before': 3,
      'source_account_id': 'acc-1',
      'is_active': true,
      'destination_account_id': null,
      'category_id': 'cat-1',
      'notes': null,
    });

    test('is due on or before today, upcoming after', () {
      final today = PlainDate.parse('2026-02-05');
      expect(
        PendingRecurring(
          occurrence: occurrence('2026-02-05'),
          rule: rule,
        ).isDueOn(today),
        isTrue,
      );
      expect(
        PendingRecurring(
          occurrence: occurrence('2026-02-04'),
          rule: rule,
        ).isDueOn(today),
        isTrue,
      );
      expect(
        PendingRecurring(
          occurrence: occurrence('2026-02-06'),
          rule: rule,
        ).isDueOn(today),
        isFalse,
      );
    });

    test('expected amount carries the rule currency', () {
      final pending = PendingRecurring(
        occurrence: occurrence('2026-02-05'),
        rule: rule,
      );
      expect(pending.expectedAmount.minor, 50000);
      expect(pending.expectedAmount.currencyCode, 'EGP');
    });
  });
}
