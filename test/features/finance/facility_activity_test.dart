import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/facility_activity.dart';

/// One centralized capability decision drives every Related activity row, so
/// a generic Edit action can never appear on a record that another flow owns.
FacilityActivityItem _item(
  String kind, {
  bool settled = false,
  String? planId,
  String transactionKind = 'expense',
}) => FacilityActivityItem.fromJson({
  'transaction_id': 'tx-1',
  'account_id': 'card-1',
  'activity_kind': kind,
  'transaction_kind': transactionKind,
  'occurred_on': '2026-08-01',
  'amount_minor': 25000,
  'currency_code': 'EGP',
  'is_settled': settled,
  'plan_id': planId,
  'category_id': 'cat-1',
  'title': 'Groceries',
  'notes': null,
  'counterparty': null,
});

void main() {
  test('an ordinary expense opens the canonical transaction editor', () {
    expect(
      resolveFacilityActivityAction(_item('ordinary_expense')),
      FacilityActivityAction.editTransaction,
    );
  });

  test('a settled charge explains itself instead of offering a dead edit', () {
    expect(
      resolveFacilityActivityAction(_item('ordinary_expense', settled: true)),
      FacilityActivityAction.explainSettled,
    );
  });

  test('installment rows route to the plan editor, never to the form', () {
    expect(
      resolveFacilityActivityAction(
        _item('installment_purchase', planId: 'plan-1'),
      ),
      FacilityActivityAction.editPlan,
    );
    expect(
      resolveFacilityActivityAction(
        _item('installment_down_payment', planId: 'plan-1'),
      ),
      FacilityActivityAction.editPlan,
    );
  });

  test('a repayment offers reversal, not the expense editor', () {
    expect(
      resolveFacilityActivityAction(
        _item('facility_repayment', transactionKind: 'transfer'),
      ),
      FacilityActivityAction.reversePayment,
    );
  });

  test('fees and system records explain why they are locked', () {
    expect(
      resolveFacilityActivityAction(_item('fee_charge')),
      FacilityActivityAction.explainFee,
    );
    expect(
      resolveFacilityActivityAction(
        _item('repayment_reversal', transactionKind: 'transfer'),
      ),
      FacilityActivityAction.explainSystem,
    );
  });

  test('an unknown server kind degrades to an explanation', () {
    expect(
      resolveFacilityActivityAction(_item('something_new')),
      FacilityActivityAction.explainSystem,
    );
  });

  test('the ledger row keeps the facility as its source account', () {
    final tx = _item('ordinary_expense').toTransaction();

    expect(tx.id, 'tx-1');
    expect(tx.kind, TransactionKind.expense);
    expect(tx.sourceAccountId, 'card-1');
    expect(tx.destinationAccountId, isNull);
    expect(tx.categoryId, 'cat-1');
    expect(tx.title, 'Groceries');
  });
}
