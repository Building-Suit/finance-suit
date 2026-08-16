import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/features/finance/domain/facility_payment_component.dart';

FacilityPaymentComponent _component({
  required String id,
  String type = 'statement_item',
  String? title,
  String activityKind = 'ordinary_expense',
  String? occurredOn,
  String? dueOn,
  int amount = 10000,
  int paid = 0,
  String scope = 'current',
  int? sequence,
}) {
  return FacilityPaymentComponent.fromJson({
    'component_type': type,
    'component_id': id,
    'title': title,
    'activity_kind': activityKind,
    'sequence_number': sequence,
    'occurred_on': occurredOn,
    'due_on': dueOn,
    'amount_minor': amount,
    'paid_minor': paid,
    'remaining_minor': amount - paid,
    'payment_status': paid == 0
        ? 'unpaid'
        : paid >= amount
        ? 'paid'
        : 'partially_paid',
    'scope': scope,
  });
}

void main() {
  group('FacilityDueBreakdown', () {
    test('parses the RPC payload and exposes the minimum', () {
      final breakdown = FacilityDueBreakdown.fromJson(const {
        'account_id': 'a',
        'account_type': 'credit_card',
        'currency_code': 'EGP',
        'as_of': '2026-04-01',
        'outstanding_minor': 400000,
        'total_due_minor': 100000,
        'paid_minor': 25000,
        'remaining_minor': 75000,
        'additional_balance_minor': 325000,
        'minimum_due_minor': 5000,
        'minimum_remaining_minor': 2000,
        'components': [
          {
            'component_type': 'installment_due',
            'component_id': 'd1',
            'amount_minor': 100000,
            'paid_minor': 25000,
            'remaining_minor': 75000,
            'payment_status': 'partially_paid',
            'scope': 'current',
          },
        ],
      });
      expect(breakdown.supportsMinimumPayment, isTrue);
      expect(
        breakdown.components.single.type,
        FacilityComponentType.installmentDue,
      );
      expect(
        breakdown.components.single.status,
        ComponentPaymentStatus.partiallyPaid,
      );
    });

    test('a BNPL breakdown without a minimum hides the preset', () {
      final breakdown = FacilityDueBreakdown.fromJson(const {
        'account_id': 'a',
        'account_type': 'bnpl',
        'currency_code': 'EGP',
        'as_of': '2026-04-01',
        'outstanding_minor': 100,
        'total_due_minor': 100,
        'paid_minor': 0,
        'remaining_minor': 100,
        'components': <dynamic>[],
      });
      expect(breakdown.supportsMinimumPayment, isFalse);
    });
  });

  group('paymentPriorityOrder', () {
    test('orders dues, then fees, then purchases, chronologically', () {
      final ordered = paymentPriorityOrder([
        _component(id: 'p2', occurredOn: '2026-03-08'),
        _component(
          id: 'f1',
          activityKind: 'fee_charge',
          occurredOn: '2026-03-09',
        ),
        _component(id: 'p1', occurredOn: '2026-03-02'),
        _component(id: 'd2', type: 'installment_due', occurredOn: '2026-03-25'),
        _component(id: 'd1', type: 'installment_due', occurredOn: '2026-02-25'),
        _component(
          id: 'n1',
          type: 'installment_due',
          occurredOn: '2026-04-25',
          scope: 'next_due',
        ),
      ]);
      expect(ordered.map((c) => c.id).toList(), [
        'd1',
        'd2',
        'f1',
        'p1',
        'p2',
        'n1',
      ]);
    });
  });

  group('FacilityComponentType', () {
    test('parses the ordinary BNPL purchase type', () {
      final component = _component(
        id: 'b1',
        type: 'bnpl_purchase',
        title: 'Noon',
        activityKind: 'bnpl_purchase',
        occurredOn: '2026-08-16',
        dueOn: '2026-09-05',
        amount: 500000,
      );
      expect(component.type, FacilityComponentType.bnplPurchase);
      expect(component.key, 'bnpl_purchase:b1');
      expect(component.dueOn?.toIso(), '2026-09-05');
      expect(component.occurredOn?.toIso(), '2026-08-16');
      expect(component.isSelectable, isTrue);
      expect(component.isFeeOrInterest, isFalse);
    });

    test('an unknown server type is never misfiled as a statement item', () {
      final component = _component(id: 'x1', type: 'something_new');
      expect(component.type, FacilityComponentType.unknown);
      expect(component.isSelectable, isFalse);
    });
  });

  group('nextDueAllocation', () {
    test('case A — the only ordinary BNPL purchase due', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'b1',
          type: 'bnpl_purchase',
          occurredOn: '2026-08-16',
          dueOn: '2026-09-05',
          amount: 150000,
        ),
      ]);
      expect(allocation.componentAmounts, {'bnpl_purchase:b1': 150000});
      expect(allocation.totalMinor, 150000);
    });

    test('case B — several purchases sharing one due date pay together', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'b1',
          type: 'bnpl_purchase',
          occurredOn: '2026-08-16',
          dueOn: '2026-09-05',
          amount: 100000,
        ),
        _component(
          id: 'b2',
          type: 'bnpl_purchase',
          occurredOn: '2026-08-20',
          dueOn: '2026-09-05',
          amount: 200000,
        ),
      ]);
      expect(allocation.componentAmounts, {
        'bnpl_purchase:b1': 100000,
        'bnpl_purchase:b2': 200000,
      });
      expect(allocation.totalMinor, 300000);
    });

    test('case C — a purchase and an installment on the same date', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'b1',
          type: 'bnpl_purchase',
          occurredOn: '2026-08-16',
          dueOn: '2026-09-05',
          amount: 200000,
        ),
        _component(
          id: 'd1',
          type: 'installment_due',
          occurredOn: '2026-09-05',
          dueOn: '2026-09-05',
          amount: 50000,
          sequence: 4,
        ),
      ]);
      expect(allocation.totalMinor, 250000);
      expect(
        allocation.componentAmounts.keys,
        containsAll(<String>['bnpl_purchase:b1', 'installment_due:d1']),
      );
    });

    test('case D — never jumps past current debt to a later due', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'b2',
          type: 'bnpl_purchase',
          occurredOn: '2026-08-20',
          dueOn: '2026-10-05',
          amount: 900000,
        ),
        _component(
          id: 'd1',
          type: 'installment_due',
          occurredOn: '2026-08-25',
          dueOn: '2026-08-25',
          amount: 55187,
        ),
      ]);
      expect(allocation.componentAmounts, {'installment_due:d1': 55187});
    });

    test('settled components are skipped', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'd1',
          type: 'installment_due',
          occurredOn: '2026-02-25',
          dueOn: '2026-02-25',
          paid: 10000,
        ),
        _component(
          id: 'd2',
          type: 'installment_due',
          occurredOn: '2026-03-25',
          dueOn: '2026-03-25',
          amount: 42000,
        ),
      ]);
      expect(allocation.componentAmounts, {'installment_due:d2': 42000});
    });

    test('falls back to the next-due group only when nothing is payable', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'n1',
          type: 'installment_due',
          occurredOn: '2026-04-25',
          dueOn: '2026-04-25',
          scope: 'next_due',
          amount: 33000,
        ),
        _component(
          id: 'n2',
          type: 'bnpl_purchase',
          occurredOn: '2026-04-02',
          dueOn: '2026-04-25',
          scope: 'next_due',
          amount: 12000,
        ),
      ]);
      expect(allocation.totalMinor, 45000);
    });

    test('returns nothing when every component is settled', () {
      final allocation = nextDueAllocation([
        _component(
          id: 'd1',
          type: 'installment_due',
          occurredOn: '2026-02-25',
          dueOn: '2026-02-25',
          paid: 10000,
        ),
      ]);
      expect(allocation.componentAmounts, isEmpty);
    });
  });

  group('minimumPaymentAllocation', () {
    test('covers exactly the server minimum in priority order', () {
      final allocation = minimumPaymentAllocation(12000, [
        _component(id: 'p1', occurredOn: '2026-03-02', amount: 5000),
        _component(
          id: 'd1',
          type: 'installment_due',
          occurredOn: '2026-02-25',
          amount: 10000,
        ),
        _component(
          id: 'f1',
          activityKind: 'purchase_interest',
          occurredOn: '2026-03-09',
          amount: 4000,
        ),
      ]);
      expect(allocation.componentAmounts, {
        'installment_due:d1': 10000,
        'statement_item:f1': 2000,
      });
      expect(allocation.totalMinor, 12000);
    });

    test('never reaches into next-due components', () {
      final allocation = minimumPaymentAllocation(9000, [
        _component(id: 'p1', amount: 5000, occurredOn: '2026-03-02'),
        _component(
          id: 'n1',
          type: 'installment_due',
          occurredOn: '2026-04-25',
          scope: 'next_due',
        ),
      ]);
      expect(allocation.componentAmounts, {'statement_item:p1': 5000});
      expect(allocation.totalMinor, 5000);
    });
  });

  group('fullOutstandingAllocation', () {
    test('selects every payable component plus the explicit balance', () {
      final breakdown = FacilityDueBreakdown.fromJson(const {
        'account_id': 'a',
        'account_type': 'credit_card',
        'currency_code': 'EGP',
        'as_of': '2026-04-01',
        'outstanding_minor': 50000,
        'total_due_minor': 30000,
        'paid_minor': 10000,
        'remaining_minor': 20000,
        'additional_balance_minor': 30000,
        'components': [
          {
            'component_type': 'statement_item',
            'component_id': 'p1',
            'amount_minor': 20000,
            'paid_minor': 10000,
            'remaining_minor': 10000,
            'payment_status': 'partially_paid',
            'scope': 'current',
          },
          {
            'component_type': 'installment_due',
            'component_id': 'd1',
            'amount_minor': 10000,
            'paid_minor': 0,
            'remaining_minor': 10000,
            'payment_status': 'unpaid',
            'scope': 'current',
          },
          {
            'component_type': 'statement_item',
            'component_id': 'paid1',
            'amount_minor': 500,
            'paid_minor': 500,
            'remaining_minor': 0,
            'payment_status': 'paid',
            'scope': 'current',
          },
        ],
      });
      final allocation = fullOutstandingAllocation(breakdown);
      expect(allocation.componentAmounts, {
        'statement_item:p1': 10000,
        'installment_due:d1': 10000,
      });
      expect(allocation.facilityBalanceMinor, 30000);
      expect(allocation.totalMinor, breakdown.outstandingMinor);
    });
  });

  group('FacilityPaymentV2Draft', () {
    test('serializes typed allocations for the v2 RPC', () {
      final draft = FacilityPaymentV2Draft(
        accountId: 'a',
        sourceAccountId: 's',
        amountMinor: 686,
        paidOn: PlainDate.parse('2026-04-01'),
        allocations: const [
          FacilityAllocationEntry(
            type: 'installment_due',
            id: 'd1',
            amountMinor: 551,
          ),
          FacilityAllocationEntry(
            type: 'statement_item',
            id: 'i1',
            amountMinor: 135,
          ),
        ],
        paymentId: 'p1',
      );
      final json = draft.toJson();
      expect(json['p_amount_minor'], 686);
      expect(json['p_allocations'], [
        {'type': 'installment_due', 'id': 'd1', 'amount_minor': 551},
        {'type': 'statement_item', 'id': 'i1', 'amount_minor': 135},
      ]);
    });
  });
}
