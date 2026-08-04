begin;
create extension if not exists pgtap with schema extensions;

select plan(67);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000044',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'facility-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Facility Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000045',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'facility-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Facility Intruder"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------

select has_table('app_finance', 'credit_facility_settings',
  'facility settings table exists');
select has_table('app_finance', 'installment_plans',
  'installment plans table exists');
select has_table('app_finance', 'installment_dues',
  'installment dues table exists');
select has_table('app_finance', 'installment_payment_allocations',
  'payment allocations table exists');
select has_function('app_finance', 'create_installment_plan',
  array['uuid', 'text', 'uuid', 'date', 'bigint', 'integer', 'date',
    'bigint', 'uuid', 'bigint', 'bigint', 'text', 'uuid'],
  'create_installment_plan exists');
select has_function('app_finance', 'pay_credit_facility',
  array['uuid', 'uuid', 'bigint', 'date', 'jsonb', 'text', 'uuid'],
  'pay_credit_facility exists');

select results_eq(
  $$select app_finance.account_role('cash'::app_finance.account_type),
      app_finance.account_role('credit_card'::app_finance.account_type)$$,
  $$values ('asset'::text, 'liability'::text)$$,
  'account_role maps cash to asset and credit_card to liability'
);

-- ---------------------------------------------------------------------------
-- Seed owner data
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000044","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a001',
  '00000000-0000-0000-0000-000000000044',
  'Main Wallet', 'cash', 'EGP', 1000000
), (
  '00000000-0000-0000-0000-00000000a002',
  '00000000-0000-0000-0000-000000000044',
  'Dollar Wallet', 'cash', 'USD', 100000
), (
  '00000000-0000-0000-0000-00000000a003',
  '00000000-0000-0000-0000-000000000044',
  'Old Wallet', 'cash', 'EGP', 0
);
update app_finance.accounts set is_archived = true
  where id = '00000000-0000-0000-0000-00000000a003';

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c001',
  '00000000-0000-0000-0000-000000000044',
  'Facility Shopping', 'expense'
);

-- save_credit_facility creates its own account; look accounts up by name.
select app_finance.save_credit_facility(
  'Visa Card', 'credit_card', 'EGP', 0, 500000, 10::smallint,
  5::smallint, '1234', 3::smallint, null, null);
select app_finance.save_credit_facility(
  'ValU', 'bnpl', 'EGP', 20000, 300000, 5::smallint,
  null, null, 3::smallint, null, null);
select app_finance.save_credit_facility(
  'Half Card', 'credit_card', 'EGP', 1001, 20000, 15::smallint,
  null, null, 3::smallint, null, null);

-- ---------------------------------------------------------------------------
-- Liability account guard rails
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update app_finance.accounts set is_default = true
      where name = 'Visa Card'$$,
  'P0001', null, 'a liability account cannot become the default account'
);
select throws_ok(
  $$update app_finance.accounts set allow_negative_balance = true
      where name = 'Visa Card'$$,
  'P0001', null, 'a liability account cannot allow negative balances'
);
select throws_ok(
  $$insert into app_finance.credit_facility_settings (
      account_id, user_id, credit_limit_minor, default_due_day
    ) values (
      '00000000-0000-0000-0000-00000000a001',
      '00000000-0000-0000-0000-000000000044', 10000, 5
    )$$,
  'P0001', null, 'facility settings are rejected on an asset account'
);
select throws_ok(
  $$select app_finance.save_credit_facility(
      'Bad BNPL', 'bnpl', 'EGP', 0, 10000, 5::smallint,
      7::smallint, null, 3::smallint, null, null)$$,
  'P0001', null, 'statement day is credit-card only'
);
select throws_ok(
  $$select app_finance.save_credit_facility(
      'Bad Asset', 'cash', 'EGP', 0, 10000, 5::smallint,
      null, null, 3::smallint, null, null)$$,
  'P0001', null, 'save_credit_facility rejects asset account types'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from app_finance.accounts where name = 'ValU'))$$,
  $$values (20000::bigint)$$,
  'opening amount owed seeds the outstanding balance'
);

select throws_ok(
  $$insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id
    ) values (
      '00000000-0000-0000-0000-000000000044', 'expense', current_date, 500,
      'EGP', (select id from app_finance.accounts where name = 'Visa Card'),
      '00000000-0000-0000-0000-00000000c001'
    )$$,
  'P0001', null, 'direct client charges on a facility are rejected'
);
select throws_ok(
  $$select app_finance.create_transfer(
      '00000000-0000-0000-0000-00000000a001',
      (select id from app_finance.accounts where name = 'Visa Card'),
      1000, current_date, null)$$,
  'P0001', null,
  'generic transfers cannot reach a facility outside the payment flow'
);

-- ---------------------------------------------------------------------------
-- Plan creation, rounding, and schedule dates
-- ---------------------------------------------------------------------------

-- P1: 1200.00 over 12 -> 100.00 each, first due in 10 days.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Visa Card'),
  'Fridge', '00000000-0000-0000-0000-00000000c001',
  current_date, 120000, 12, current_date + 10,
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e001'
);

select results_eq(
  $$select count(*)::integer, sum(amount_minor)::bigint,
      min(amount_minor)::bigint, max(amount_minor)::bigint
    from app_finance.installment_dues
    where plan_id = '00000000-0000-0000-0000-00000000e001'$$,
  $$values (12, 120000::bigint, 10000::bigint, 10000::bigint)$$,
  'a divisible schedule splits into equal installments summing exactly'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where user_id = '00000000-0000-0000-0000-000000000044'$$,
  $$values (1)$$,
  'generating dues books exactly one purchase expense and no future rows'
);

-- Idempotent retry returns the same plan without duplicating anything.
select results_eq(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'Visa Card'),
      'Fridge', '00000000-0000-0000-0000-00000000c001',
      current_date, 120000, 12, current_date + 10,
      0, null, null, null, null,
      '00000000-0000-0000-0000-00000000e001')$$,
  $$values ('00000000-0000-0000-0000-00000000e001'::uuid)$$,
  'creating a plan is idempotent for the same plan id'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_dues
    where plan_id = '00000000-0000-0000-0000-00000000e001'$$,
  $$values (12)$$,
  'an idempotent retry does not duplicate dues'
);

-- P2: 1000.00 over 3 -> 333.34 + 333.33 + 333.33.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Visa Card'),
  'Phone', '00000000-0000-0000-0000-00000000c001',
  current_date, 100000, 3, current_date + 20,
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e002'
);
select results_eq(
  $$select array_agg(amount_minor order by sequence_number)
    from app_finance.installment_dues
    where plan_id = '00000000-0000-0000-0000-00000000e002'$$,
  $$values (array[33334, 33333, 33333]::bigint[])$$,
  'a non-divisible total puts the extra minor units on the first dues'
);

-- P3: down payment 200.00 from the wallet plus 30.00 fees on 500.00.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Visa Card'),
  'Laptop', '00000000-0000-0000-0000-00000000c001',
  current_date, 50000, 3, current_date + 15,
  20000, '00000000-0000-0000-0000-00000000a001', 3000, null, null,
  '00000000-0000-0000-0000-00000000e003'
);
select results_eq(
  $$select
      (select sum(amount_minor) from app_finance.financial_transactions
        where user_id = '00000000-0000-0000-0000-000000000044'
          and transaction_kind = 'expense'),
      (select total_payable_minor from app_finance.installment_plans
        where id = '00000000-0000-0000-0000-00000000e003')$$,
  $$values (273000::bigint, 33000::bigint)$$,
  'purchase price plus fees is recognized as expense exactly once'
);

-- P4 overdue yesterday, P5 due today.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Visa Card'),
  'Overdue Thing', '00000000-0000-0000-0000-00000000c001',
  current_date - 30, 10000, 1, current_date - 1,
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e004'
);
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Visa Card'),
  'Due Today Thing', '00000000-0000-0000-0000-00000000c001',
  current_date - 10, 8000, 1, current_date,
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e005'
);
select results_eq(
  $$select due_status from app_finance.installment_due_statuses
    where plan_id in ('00000000-0000-0000-0000-00000000e004',
                      '00000000-0000-0000-0000-00000000e005')
    order by due_on$$,
  $$values ('overdue'::text), ('due_today'::text)$$,
  'due statuses derive overdue and due today from the due date'
);

-- Month-end clamping and leap-year schedules on the BNPL facility.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'ValU'),
  'January Sofa', '00000000-0000-0000-0000-00000000c001',
  date '2026-01-15', 30000, 3, date '2026-01-31',
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e006'
);
select results_eq(
  $$select array_agg(due_on order by sequence_number)
    from app_finance.installment_dues
    where plan_id = '00000000-0000-0000-0000-00000000e006'$$,
  $$values (array[date '2026-01-31', date '2026-02-28', date '2026-03-31'])$$,
  'schedules clamp to the last day of shorter months'
);
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'ValU'),
  'Leap TV', '00000000-0000-0000-0000-00000000c001',
  date '2028-01-01', 20000, 2, date '2028-01-31',
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e007'
);
select results_eq(
  $$select array_agg(due_on order by sequence_number)
    from app_finance.installment_dues
    where plan_id = '00000000-0000-0000-0000-00000000e007'$$,
  $$values (array[date '2028-01-31', date '2028-02-29'])$$,
  'leap-year February keeps the 29th'
);

-- Financing input validation.
select throws_ok(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'ValU'),
      'Bad Financing', '00000000-0000-0000-0000-00000000c001',
      current_date, 10000, 2, current_date + 5,
      0, null, 500, 12000, null, null)$$,
  'P0001', null, 'inconsistent fees and total payable are rejected'
);
select throws_ok(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'Visa Card'),
      'Too Big', '00000000-0000-0000-0000-00000000c001',
      current_date, 300000, 6, current_date + 10,
      0, null, null, null, null, null)$$,
  'P0001', null, 'a purchase beyond available credit is rejected'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where user_id = '00000000-0000-0000-0000-000000000044'
      and transaction_kind = 'expense'$$,
  $$values (8)$$,
  'a rejected purchase leaves no partial rows behind'
);

-- ---------------------------------------------------------------------------
-- Summaries
-- ---------------------------------------------------------------------------

select results_eq(
  $$select outstanding_minor, available_credit_minor
    from app_finance.credit_facility_summaries
    where name = 'Visa Card'$$,
  $$values (271000::bigint, 229000::bigint)$$,
  'outstanding and available credit follow the liability formulas'
);
select results_eq(
  $$select utilization_basis_points
    from app_finance.credit_facility_summaries
    where name = 'Half Card'$$,
  $$values (501)$$,
  'utilization basis points round half up'
);
select results_eq(
  $$select due_now_minor, overdue_minor
    from app_finance.credit_facility_summaries
    where name = 'Visa Card'$$,
  $$values (18000::bigint, 10000::bigint)$$,
  'due-now covers overdue plus due-today amounts'
);

-- ---------------------------------------------------------------------------
-- Payments and allocation order
-- ---------------------------------------------------------------------------

-- Partial payment lands on the oldest overdue due first.
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Visa Card'),
  '00000000-0000-0000-0000-00000000a001',
  5000, current_date, null, null,
  '00000000-0000-0000-0000-00000000d001'
);
select results_eq(
  $$select paid_minor, due_status from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e004'$$,
  $$values (5000::bigint, 'overdue'::text)$$,
  'a partial payment reduces the oldest overdue due and keeps it overdue'
);

-- Idempotent retry does not double-pay.
select results_eq(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts where name = 'Visa Card'),
      '00000000-0000-0000-0000-00000000a001',
      5000, current_date, null, null,
      '00000000-0000-0000-0000-00000000d001')$$,
  $$values ('00000000-0000-0000-0000-00000000d001'::uuid)$$,
  'paying is idempotent for the same payment id'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.installment_payment_allocations
    where payment_transaction_id = '00000000-0000-0000-0000-00000000d001'$$,
  $$values (1)$$,
  'an idempotent payment retry does not duplicate allocations'
);

-- One payment covering multiple dues in order: rest of P4, all of P5,
-- P1 first due, then early money onto the next upcoming due (P3).
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Visa Card'),
  '00000000-0000-0000-0000-00000000a001',
  25000, current_date, null, null,
  '00000000-0000-0000-0000-00000000d002'
);
select results_eq(
  $$select
      (select due_status from app_finance.installment_due_statuses
        where plan_id = '00000000-0000-0000-0000-00000000e004'),
      (select due_status from app_finance.installment_due_statuses
        where plan_id = '00000000-0000-0000-0000-00000000e005'),
      (select paid_minor from app_finance.installment_due_statuses
        where plan_id = '00000000-0000-0000-0000-00000000e001'
          and sequence_number = 1),
      (select paid_minor from app_finance.installment_due_statuses
        where plan_id = '00000000-0000-0000-0000-00000000e003'
          and sequence_number = 1)$$,
  $$values ('paid'::text, 'paid'::text, 10000::bigint, 2000::bigint)$$,
  'one payment settles multiple dues oldest first'
);
select results_eq(
  $$select status from app_finance.installment_plans
    where id in ('00000000-0000-0000-0000-00000000e004',
                 '00000000-0000-0000-0000-00000000e005')
    order by id$$,
  $$values ('completed'::app_finance.installment_plan_status),
    ('completed'::app_finance.installment_plan_status)$$,
  'plans complete when every due is fully paid'
);
select results_eq(
  $$select due_status from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e003'
      and sequence_number = 1$$,
  $$values ('partially_paid'::text)$$,
  'an upcoming due with money on it reads partially paid'
);

-- Early explicit allocation to a chosen future due.
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Visa Card'),
  '00000000-0000-0000-0000-00000000a001',
  3000, current_date,
  (select jsonb_build_array(jsonb_build_object(
      'due_id', d.id, 'amount_minor', 3000))
    from app_finance.installment_dues d
    where d.plan_id = '00000000-0000-0000-0000-00000000e002'
      and d.sequence_number = 2),
  null, '00000000-0000-0000-0000-00000000d003'
);
select results_eq(
  $$select paid_minor from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e002'
      and sequence_number = 2$$,
  $$values (3000::bigint)$$,
  'explicit allocations pay a chosen due early'
);

-- Guard rails on payments.
select throws_ok(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts where name = 'Visa Card'),
      '00000000-0000-0000-0000-00000000a001',
      999999999, current_date, null, null, null)$$,
  'P0001', null, 'overpaying beyond the outstanding debt is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts where name = 'Visa Card'),
      '00000000-0000-0000-0000-00000000a002',
      1000, current_date, null, null, null)$$,
  'P0001', null, 'cross-currency repayments are rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts where name = 'Visa Card'),
      '00000000-0000-0000-0000-00000000a003',
      1000, current_date, null, null, null)$$,
  'P0001', null, 'archived source accounts are rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts where name = 'Visa Card'),
      (select id from app_finance.accounts where name = 'ValU'),
      1000, current_date, null, null, null)$$,
  'P0001', null, 'a liability cannot fund a facility repayment'
);

-- ---------------------------------------------------------------------------
-- Asset formula regression and report neutrality
-- ---------------------------------------------------------------------------

select results_eq(
  $$select balance_minor from app_finance.account_balances
    where name = 'Main Wallet'$$,
  $$values (947000::bigint)$$,
  'asset balances keep the original opening-plus-flows formula'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from app_finance.accounts where name = 'Visa Card'))$$,
  $$values (238000::bigint)$$,
  'repayments reduce the liability by exactly the paid amount'
);
select results_eq(
  $$select expenses_minor, income_minor
    from app_reports.cash_flow_summary_v2(date '2026-01-01', date '2028-12-31')
    where currency_code = 'EGP'$$,
  $$values (341000::bigint, 0::bigint)$$,
  'repayment transfers never count as expense or income'
);
select results_eq(
  $$select repayments_minor, outstanding_minor
    from app_reports.debt_summary(date '2026-01-01', date '2028-12-31')
    where currency_code = 'EGP'$$,
  $$values (33000::bigint, 309001::bigint)$$,
  'the debt summary reports repayments and total outstanding'
);

-- ---------------------------------------------------------------------------
-- Locks on generated records
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update app_finance.installment_plans
      set total_payable_minor = 1
      where id = '00000000-0000-0000-0000-00000000e001'$$,
  'P0001', null, 'financial plan fields are locked after creation'
);
select lives_ok(
  $$update app_finance.installment_plans
      set title = 'Fridge (kitchen)', notes = 'silver'
      where id = '00000000-0000-0000-0000-00000000e001'$$,
  'plan title and notes stay editable'
);
select throws_ok(
  $$delete from app_finance.installment_plans
      where id = '00000000-0000-0000-0000-00000000e001'$$,
  'P0001', null, 'plans cannot be hard-deleted by clients'
);
select throws_ok(
  $$insert into app_finance.installment_dues (
      user_id, plan_id, sequence_number, due_on, amount_minor
    ) values (
      '00000000-0000-0000-0000-000000000044',
      '00000000-0000-0000-0000-00000000e001', 99, current_date, 100
    )$$,
  'P0001', null, 'dues cannot be forged outside the RPCs'
);
select throws_ok(
  $$delete from app_finance.financial_transactions
      where id = '00000000-0000-0000-0000-00000000d002'$$,
  'P0001', null, 'facility payments are locked from the generic editor'
);
select throws_ok(
  $$delete from app_finance.credit_facility_settings
      where account_id =
        (select id from app_finance.accounts where name = 'Visa Card')$$,
  'P0001', null, 'facility settings cannot be deleted by clients'
);
select throws_ok(
  $$update app_finance.accounts set account_type = 'credit_card'
      where id = '00000000-0000-0000-0000-00000000a001'$$,
  'P0001', null, 'an account with history cannot switch roles'
);
select throws_ok(
  $$update app_finance.accounts set is_archived = true
      where name = 'Visa Card'$$,
  'P0001', null, 'a facility with outstanding debt cannot be archived'
);
select throws_ok(
  $$update app_finance.credit_facility_settings set credit_limit_minor = 1000
      where account_id =
        (select id from app_finance.accounts where name = 'Visa Card')$$,
  'P0001', null, 'the credit limit cannot drop below the outstanding debt'
);

-- ---------------------------------------------------------------------------
-- Reversal and cancellation
-- ---------------------------------------------------------------------------

select app_finance.reverse_facility_payment(
  '00000000-0000-0000-0000-00000000d003');
select results_eq(
  $$select paid_minor from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e002'
      and sequence_number = 2$$,
  $$values (0::bigint)$$,
  'reversing a payment removes its allocations and reopens the due'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where facility_reversal_of_id = '00000000-0000-0000-0000-00000000d003'$$,
  $$values (1)$$,
  'a reversal keeps the audit link to the original payment'
);
select throws_ok(
  $$select app_finance.reverse_facility_payment(
      '00000000-0000-0000-0000-00000000d003')$$,
  'P0001', null, 'a payment cannot be reversed twice'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from app_finance.accounts where name = 'Visa Card'))$$,
  $$values (241000::bigint)$$,
  'a reversal restores the outstanding debt'
);

-- Reversing the multi-due payment reopens completed plans.
select app_finance.reverse_facility_payment(
  '00000000-0000-0000-0000-00000000d002');
select results_eq(
  $$select status from app_finance.installment_plans
    where id = '00000000-0000-0000-0000-00000000e004'$$,
  $$values ('active'::app_finance.installment_plan_status)$$,
  'reversal reopens plans whose dues are unpaid again'
);
select throws_ok(
  $$select app_finance.cancel_installment_plan(
      '00000000-0000-0000-0000-00000000e004')$$,
  'P0001', null, 'a plan with recorded payments cannot be cancelled'
);

-- Cancel an unpaid plan: purchase rows disappear, dues read cancelled.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'ValU'),
  'Cancelled Chair', '00000000-0000-0000-0000-00000000c001',
  current_date, 5000, 1, current_date + 5,
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e008'
);
select app_finance.cancel_installment_plan(
  '00000000-0000-0000-0000-00000000e008');
select results_eq(
  $$select p.status, p.purchase_transaction_id is null,
      (select due_status from app_finance.installment_due_statuses s
        where s.plan_id = p.id)
    from app_finance.installment_plans p
    where p.id = '00000000-0000-0000-0000-00000000e008'$$,
  $$values ('cancelled'::app_finance.installment_plan_status, true,
    'cancelled'::text)$$,
  'cancelling an unpaid plan removes the purchase and cancels its dues'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from app_finance.accounts where name = 'ValU'))$$,
  $$values (70000::bigint)$$,
  'cancelling restores the facility outstanding'
);

-- ---------------------------------------------------------------------------
-- RLS isolation and cross-user rejection
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000045","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer from app_finance.credit_facility_summaries$$,
  $$values (0)$$,
  'facility summaries are invisible to other users'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_due_statuses$$,
  $$values (0)$$,
  'installment dues are invisible to other users'
);
select throws_ok(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts
        where name = 'Visa Card'
          and user_id = '00000000-0000-0000-0000-000000000044'),
      '00000000-0000-0000-0000-00000000a001',
      1000, current_date, null, null, null)$$,
  'P0001', null, 'cross-user facility payments are rejected'
);
select throws_ok(
  $$select app_finance.cancel_installment_plan(
      '00000000-0000-0000-0000-00000000e001')$$,
  'P0001', null, 'cross-user plan cancellation is rejected'
);

-- ---------------------------------------------------------------------------
-- Account deletion cascade
-- ---------------------------------------------------------------------------

reset role;
set local role service_role;
select app_core.delete_finance_suit_data(
  '00000000-0000-0000-0000-000000000044');
reset role;

select results_eq(
  $$select
      (select count(*) from app_finance.credit_facility_settings
        where user_id = '00000000-0000-0000-0000-000000000044')
      + (select count(*) from app_finance.installment_plans
        where user_id = '00000000-0000-0000-0000-000000000044')
      + (select count(*) from app_finance.installment_dues
        where user_id = '00000000-0000-0000-0000-000000000044')
      + (select count(*) from app_finance.installment_payment_allocations
        where user_id = '00000000-0000-0000-0000-000000000044')$$,
  $$values (0::bigint)$$,
  'account deletion removes every facility record'
);

select * from finish();
rollback;
