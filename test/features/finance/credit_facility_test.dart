import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/date_time/plain_date.dart';
import 'package:work_tracker/core/domain/db_enums.dart';
import 'package:work_tracker/core/utils/client_uuid.dart';
import 'package:work_tracker/features/finance/domain/account.dart';
import 'package:work_tracker/features/finance/domain/credit_facility.dart';

void main() {
  test('credit card and BNPL types are liabilities, everything else asset', () {
    expect(AccountType.creditCard.dbValue, 'credit_card');
    expect(AccountType.bnpl.dbValue, 'bnpl');
    expect(AccountType.creditCard.role, AccountRole.liability);
    expect(AccountType.bnpl.role, AccountRole.liability);
    for (final type in AccountType.values) {
      if (type == AccountType.creditCard || type == AccountType.bnpl) {
        expect(type.isLiability, isTrue, reason: type.name);
      } else {
        expect(type.role, AccountRole.asset, reason: type.name);
      }
    }
    expect(AccountType.fromDb('credit_card'), AccountType.creditCard);
    expect(AccountType.fromDb('bnpl'), AccountType.bnpl);
  });

  test('asset picker eligibility filters liabilities centrally', () {
    const asset = AccountBalance(
      accountId: 'a',
      name: 'Wallet',
      accountType: AccountType.cash,
      currencyCode: 'EGP',
      isDefault: true,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: 1000,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 0,
    );
    const liability = AccountBalance(
      accountId: 'b',
      name: 'Visa',
      accountType: AccountType.creditCard,
      currencyCode: 'EGP',
      isDefault: false,
      isArchived: false,
      allowNegativeBalance: false,
      openingBalanceMinor: 0,
      balanceMinor: -5000,
      totalIncomingMinor: 0,
      totalOutgoingMinor: 5000,
    );
    expect(liability.isLiability, isTrue);
    expect([asset, liability].assetAccounts, [asset]);
  });

  test('facility summary parses the view row and derives Money figures', () {
    final summary = CreditFacilitySummary.fromJson(const {
      'account_id': 'f1',
      'name': 'ValU',
      'account_type': 'bnpl',
      'currency_code': 'EGP',
      'is_archived': false,
      'notes': null,
      'opening_owed_minor': 20000,
      'credit_limit_minor': 300000,
      'statement_day': null,
      'default_due_day': 5,
      'last_four_digits': null,
      'reminder_lead_days': 3,
      'outstanding_minor': 70000,
      'available_credit_minor': 230000,
      'utilization_basis_points': 2333,
      'due_now_minor': 11000,
      'overdue_minor': 4000,
      'next_due_on': '2026-08-10',
      'next_due_amount_minor': 7000,
      'active_plan_count': 2,
    });
    expect(summary.outstanding.minor, 70000);
    expect(summary.availableCredit.minor, 230000);
    expect(summary.creditLimit.minor, 300000);
    expect(summary.utilizationFraction, closeTo(0.2333, 0.00001));
    expect(summary.hasOverdue, isTrue);
    expect(summary.nextDueOn, const PlainDate(2026, 8, 10));
    expect(summary.nextDueAmount!.minor, 7000);
  });

  test('due status derives from remaining amount and business date', () {
    InstallmentDue due({
      required PlainDate dueOn,
      int amount = 10000,
      int paid = 0,
      InstallmentPlanStatus plan = InstallmentPlanStatus.active,
    }) => InstallmentDue(
      id: 'd',
      planId: 'p',
      accountId: 'a',
      sequenceNumber: 1,
      dueOn: dueOn,
      amountMinor: amount,
      currencyCode: 'EGP',
      planTitle: 'Plan',
      planStatus: plan,
      paidMinor: paid,
      remainingMinor: amount - paid,
      status: InstallmentDueStatus.upcoming,
    );
    const today = PlainDate(2026, 8, 4);
    expect(
      due(dueOn: const PlainDate(2026, 8, 3)).statusFor(today),
      InstallmentDueStatus.overdue,
    );
    expect(due(dueOn: today).statusFor(today), InstallmentDueStatus.dueToday);
    expect(
      due(dueOn: const PlainDate(2026, 9, 1)).statusFor(today),
      InstallmentDueStatus.upcoming,
    );
    expect(
      due(dueOn: const PlainDate(2026, 9, 1), paid: 4000).statusFor(today),
      InstallmentDueStatus.partiallyPaid,
    );
    expect(
      due(dueOn: const PlainDate(2026, 8, 3), paid: 10000).statusFor(today),
      InstallmentDueStatus.paid,
    );
    expect(
      due(
        dueOn: const PlainDate(2026, 8, 3),
        plan: InstallmentPlanStatus.cancelled,
      ).statusFor(today),
      InstallmentDueStatus.cancelled,
    );
  });

  test('schedule preview splits exactly with the remainder on early dues', () {
    final divisible = previewInstallmentSchedule(
      totalPayableMinor: 120000,
      installmentCount: 12,
      firstDueOn: const PlainDate(2026, 8, 10),
    );
    expect(divisible, hasLength(12));
    expect(divisible.every((e) => e.amountMinor == 10000), isTrue);

    final uneven = previewInstallmentSchedule(
      totalPayableMinor: 100000,
      installmentCount: 3,
      firstDueOn: const PlainDate(2026, 8, 10),
    );
    expect(uneven.map((e) => e.amountMinor), [33334, 33333, 33333]);
    expect(uneven.fold<int>(0, (sum, e) => sum + e.amountMinor), 100000);

    final single = previewInstallmentSchedule(
      totalPayableMinor: 999,
      installmentCount: 1,
      firstDueOn: const PlainDate(2026, 8, 10),
    );
    expect(single.single.amountMinor, 999);
  });

  test('schedule preview clamps month ends and honors leap years', () {
    final clamped = previewInstallmentSchedule(
      totalPayableMinor: 30000,
      installmentCount: 3,
      firstDueOn: const PlainDate(2026, 1, 31),
    );
    expect(clamped.map((e) => e.dueOn), const [
      PlainDate(2026, 1, 31),
      PlainDate(2026, 2, 28),
      PlainDate(2026, 3, 31),
    ]);

    final leap = previewInstallmentSchedule(
      totalPayableMinor: 20000,
      installmentCount: 2,
      firstDueOn: const PlainDate(2028, 1, 31),
    );
    expect(leap.map((e) => e.dueOn), const [
      PlainDate(2028, 1, 31),
      PlainDate(2028, 2, 29),
    ]);
  });

  test('drafts serialize to the RPC parameter names', () {
    const facilityDraft = CreditFacilityDraft(
      name: 'Visa',
      accountType: AccountType.creditCard,
      currencyCode: 'EGP',
      creditLimitMinor: 500000,
      defaultDueDay: 10,
      statementDay: 5,
      lastFourDigits: '1234',
      notes: 'main card',
      accountId: 'acc-1',
      facilityStatus: FacilityStatus.frozen,
      minPaymentMethod: MinPaymentMethod.percent,
      minPaymentBasisPoints: 500,
    );
    expect(facilityDraft.toJson(), {
      'p_name': 'Visa',
      'p_account_type': 'credit_card',
      'p_currency_code': 'EGP',
      'p_credit_limit_minor': 500000,
      'p_default_due_day': 10,
      'p_statement_day': 5,
      'p_last_four_digits': '1234',
      'p_reminder_lead_days': 3,
      'p_notes': 'main card',
      'p_account_id': 'acc-1',
      'p_facility_status': 'frozen',
      'p_min_payment_method': 'percent',
      'p_min_payment_fixed_minor': null,
      'p_min_payment_basis_points': 500,
      'p_color_hex': null,
    });

    const planDraft = InstallmentPlanDraft(
      accountId: 'f1',
      title: 'Fridge',
      categoryId: 'c1',
      purchasedOn: PlainDate(2026, 8, 1),
      purchasePriceMinor: 50000,
      installmentCount: 3,
      firstDueOn: PlainDate(2026, 8, 10),
      downPaymentMinor: 20000,
      downPaymentAccountId: 'a1',
      financingFeesMinor: 3000,
      planId: 'plan-1',
    );
    final planJson = planDraft.toJson();
    expect(planJson['p_account_id'], 'f1');
    expect(planJson['p_purchased_on'], '2026-08-01');
    expect(planJson['p_first_due_on'], '2026-08-10');
    expect(planJson['p_down_payment_minor'], 20000);
    expect(planJson['p_financing_fees_minor'], 3000);
    expect(planJson['p_total_payable_minor'], isNull);
    expect(planJson['p_plan_id'], 'plan-1');

    const paymentDraft = FacilityPaymentDraft(
      accountId: 'f1',
      sourceAccountId: 'a1',
      amountMinor: 15000,
      paidOn: PlainDate(2026, 8, 4),
      allocations: [(dueId: 'd1', amountMinor: 15000)],
      paymentId: 'pay-1',
    );
    final paymentJson = paymentDraft.toJson();
    expect(paymentJson['p_amount_minor'], 15000);
    expect(paymentJson['p_paid_on'], '2026-08-04');
    expect(paymentJson['p_allocations'], [
      {'due_id': 'd1', 'amount_minor': 15000},
    ]);
    expect(paymentJson['p_payment_id'], 'pay-1');
  });

  test('client uuids are well-formed v4 and unique', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final seen = <String>{};
    for (var i = 0; i < 100; i++) {
      final id = newClientUuid();
      expect(pattern.hasMatch(id), isTrue, reason: id);
      expect(seen.add(id), isTrue);
    }
  });
}
