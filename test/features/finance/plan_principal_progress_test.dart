import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';

/// Bank-style plan progress: a monthly installment pays the item only with
/// its principal share (original amount / count); the interest-and-fees
/// share belongs to the bank and never counts toward the item.
void main() {
  InstallmentPlan plan({
    required int principal,
    required int total,
    required int paid,
    int count = 12,
    int remainingPrincipal = -1,
  }) => InstallmentPlan(
    id: 'plan-1',
    accountId: 'card-1',
    title: 'Samsung Monitor',
    categoryId: 'cat-1',
    purchasedOn: const PlainDate(2026, 7, 1),
    firstDueOn: const PlainDate(2026, 8, 1),
    installmentCount: count,
    purchasePriceMinor: principal,
    downPaymentMinor: 0,
    financedPrincipalMinor: principal,
    financingFeesMinor: total - principal,
    totalPayableMinor: total,
    currencyCode: 'EGP',
    status: InstallmentPlanStatus.active,
    paidMinor: paid,
    remainingMinor: total - paid,
    pricingMethod: PlanPricingMethod.interestRate,
    interestMinor: total - principal,
    remainingPrincipalMinor: remainingPrincipal,
  );

  test('one paid installment credits the item with principal / count', () {
    // 6,000.00 over 12 months, 6,622.44 payable: the 551.87 installment
    // pays the monitor 500.00; 51.87 is the bank's.
    final p = plan(principal: 600000, total: 662244, paid: 55187);
    expect(p.principalPaidMinor, 50000);
    expect(p.bankCostPaidMinor, 5187);
    expect(p.bankCostTotalMinor, 62244);
  });

  test('a fully paid plan lands exactly on the original amount', () {
    final p = plan(principal: 600000, total: 662244, paid: 662244);
    expect(p.principalPaidMinor, 600000);
    expect(p.bankCostPaidMinor, 62244);
  });

  test('a plan with no bank cost keeps paid and principal identical', () {
    final p = plan(principal: 600000, total: 600000, paid: 150000);
    expect(p.principalPaidMinor, 150000);
    expect(p.bankCostPaidMinor, 0);
    expect(p.bankCostTotalMinor, 0);
  });

  test('nothing paid means nothing credited', () {
    final p = plan(principal: 600000, total: 662244, paid: 0);
    expect(p.principalPaidMinor, 0);
    expect(p.bankCostPaidMinor, 0);
  });

  test('explicit bank principal overrides proportional legacy progress', () {
    final p = plan(
      principal: 1300000,
      total: 1986734,
      paid: 1490000,
      count: 36,
      remainingPrincipal: 439869,
    );
    expect(p.remainingPrincipalMinor, 439869);
    expect(p.principalPaidMinor, 860131);
  });
}
