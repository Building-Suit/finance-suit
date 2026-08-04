begin;
create extension if not exists pgtap with schema extensions;

select plan(77);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000046',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'card-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Card Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000047',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'card-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Card Intruder"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------

select has_table('app_finance', 'installment_plan_revisions',
  'plan revisions table exists');
select has_table('app_finance', 'credit_card_statement_cycles',
  'statement cycles table exists');
select has_table('app_finance', 'credit_card_statement_items',
  'statement items table exists');
select has_table('app_finance', 'credit_card_statement_allocations',
  'statement allocations table exists');
select has_table('app_finance', 'credit_card_fee_rules',
  'fee rules table exists');
select has_table('app_finance', 'credit_card_fee_charges',
  'fee charges table exists');
select has_table('app_core', 'push_devices', 'push devices table exists');
select has_table('app_core', 'notification_preferences',
  'notification preferences table exists');
select has_table('app_core', 'notification_outbox',
  'notification outbox table exists');
select has_function('app_finance', 'charge_credit_card',
  'charge_credit_card exists');
select has_function('app_finance', 'delete_credit_facility',
  'delete_credit_facility exists');
select has_function('app_finance', 'update_installment_plan',
  'update_installment_plan exists');
select has_function('app_finance', 'restructure_installment_plan',
  'restructure_installment_plan exists');

-- ---------------------------------------------------------------------------
-- Statement cycle bounds
-- ---------------------------------------------------------------------------

select results_eq(
  $$select * from app_finance.statement_bounds_for(25, 10, date '2026-03-10')$$,
  $$values (date '2026-02-26', date '2026-03-25', date '2026-04-10')$$,
  'a charge on or before the closing day joins the cycle closing that day'
);
select results_eq(
  $$select * from app_finance.statement_bounds_for(25, 10, date '2026-03-26')$$,
  $$values (date '2026-03-26', date '2026-04-25', date '2026-05-10')$$,
  'a charge after the closing day rolls into the next cycle'
);
select results_eq(
  $$select * from app_finance.statement_bounds_for(31, 5, date '2026-02-10')$$,
  $$values (date '2026-02-01', date '2026-02-28', date '2026-03-05')$$,
  'closing days clamp to the last day of short months'
);

-- ---------------------------------------------------------------------------
-- Seed owner data
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000046","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a101',
  '00000000-0000-0000-0000-000000000046',
  'Cash Wallet', 'cash', 'EGP', 2000000
);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c101',
  '00000000-0000-0000-0000-000000000046',
  'Card Spending', 'expense'
);

select app_finance.save_credit_facility(
  'Everyday Card', 'credit_card', 'EGP', 1000000, 10::smallint,
  25::smallint, '4321', 3::smallint, null, null,
  'active', 'fixed', 5000, null);
select app_finance.save_credit_facility(
  'Aman', 'bnpl', 'EGP', 500000, 5::smallint,
  null, null, 5::smallint, null, null);
select app_finance.save_credit_facility(
  'NoDay Card', 'credit_card', 'EGP', 100000, 10::smallint,
  null, null, 3::smallint, null, null);

-- ---------------------------------------------------------------------------
-- Facility settings, lifecycle, and pristine deletion
-- ---------------------------------------------------------------------------

select results_eq(
  $$select facility_status::text, min_payment_method::text,
      min_payment_fixed_minor
    from app_finance.credit_facility_summaries
    where name = 'Everyday Card'$$,
  $$values ('active'::text, 'fixed'::text, 5000::bigint)$$,
  'the summary exposes lifecycle status and minimum payment settings'
);
select throws_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'NoDay Card'),
      'Coffee', '00000000-0000-0000-0000-00000000c101',
      date '2026-03-10', 1000, null, null)$$,
  'P0001', null, 'ordinary charges need a statement closing day'
);
select lives_ok(
  $$select app_finance.delete_credit_facility(
      (select id from app_finance.accounts where name = 'NoDay Card'))$$,
  'a pristine facility with no history can be hard-deleted'
);
select results_eq(
  $$select count(*)::integer from app_finance.accounts
    where name = 'NoDay Card'$$,
  $$values (0)$$,
  'hard deletion removes the facility account'
);

-- ---------------------------------------------------------------------------
-- Card charges land on statement cycles
-- ---------------------------------------------------------------------------

select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'Groceries', '00000000-0000-0000-0000-00000000c101',
  date '2026-03-10', 40000, null, '00000000-0000-0000-0000-00000000f101');
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'Pharmacy', '00000000-0000-0000-0000-00000000c101',
  date '2026-03-20', 10000, null, '00000000-0000-0000-0000-00000000f102');
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'Electronics', '00000000-0000-0000-0000-00000000c101',
  date '2026-03-26', 20000, null, '00000000-0000-0000-0000-00000000f103');

select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_cycles
    where account_id =
      (select id from app_finance.accounts where name = 'Everyday Card')$$,
  $$values (2)$$,
  'charges before and after the closing day open exactly two cycles'
);
select results_eq(
  $$select cycle_close, charges_minor
    from app_finance.credit_card_statement_summaries
    where account_id =
      (select id from app_finance.accounts where name = 'Everyday Card')
    order by cycle_close$$,
  $$values (date '2026-03-25', 50000::bigint),
    (date '2026-04-25', 20000::bigint)$$,
  'each charge lands on the cycle containing its business date'
);
select results_eq(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'Everyday Card'),
      'Groceries', '00000000-0000-0000-0000-00000000c101',
      date '2026-03-10', 40000, null,
      '00000000-0000-0000-0000-00000000f101')$$,
  $$values ('00000000-0000-0000-0000-00000000f101'::uuid)$$,
  'charging is idempotent for the same charge id'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where source_account_id =
      (select id from app_finance.accounts where name = 'Everyday Card')
      and transaction_kind = 'expense'$$,
  $$values (3)$$,
  'an idempotent charge retry books no duplicate expense'
);
select throws_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'Aman'),
      'BNPL Coffee', '00000000-0000-0000-0000-00000000c101',
      date '2026-03-10', 1000, null, null)$$,
  'P0001', null, 'ordinary card charges reject BNPL facilities'
);
select throws_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'Everyday Card'),
      'Too Big', '00000000-0000-0000-0000-00000000c101',
      date '2026-03-27', 950000, null, null)$$,
  'P0001', null, 'a charge beyond available credit is rejected'
);

select app_finance.set_credit_facility_status(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'frozen');
select throws_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'Everyday Card'),
      'Frozen Buy', '00000000-0000-0000-0000-00000000c101',
      date '2026-03-27', 1000, null, null)$$,
  'P0001', null, 'a frozen card cannot fund new purchases'
);
select app_finance.set_credit_facility_status(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'active');

select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'Today Snack', '00000000-0000-0000-0000-00000000c101',
  current_date, 5000, null, '00000000-0000-0000-0000-00000000f104');
select results_eq(
  $$select cycle_status from app_finance.credit_card_statement_summaries
    where account_id =
      (select id from app_finance.accounts where name = 'Everyday Card')
    order by cycle_close desc limit 1$$,
  $$values ('open'::text)$$,
  'the cycle containing today reads open, not due'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from app_finance.accounts where name = 'Everyday Card'))$$,
  $$values (75000::bigint)$$,
  'card charges add to the outstanding debt exactly once'
);
select throws_ok(
  $$select app_finance.delete_credit_facility(
      (select id from app_finance.accounts where name = 'Everyday Card'))$$,
  'P0001', null, 'a facility with history cannot be hard-deleted'
);

-- ---------------------------------------------------------------------------
-- Statement summary and minimum due
-- ---------------------------------------------------------------------------

select results_eq(
  $$select charges_minor, remaining_minor, minimum_due_minor,
      cycle_status
    from app_finance.credit_card_statement_summaries
    where cycle_close = date '2026-03-25'
      and account_id =
        (select id from app_finance.accounts where name = 'Everyday Card')$$,
  $$values (50000::bigint, 50000::bigint, 5000::bigint, 'overdue'::text)$$,
  'a closed unpaid statement is overdue with a fixed minimum due'
);
select app_finance.save_credit_facility(
  'Everyday Card', 'credit_card', 'EGP', 1000000, 10::smallint,
  25::smallint, '4321', 3::smallint, null,
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'active', 'percent', null, 2000);
select results_eq(
  $$select minimum_due_minor
    from app_finance.credit_card_statement_summaries
    where cycle_close = date '2026-03-25'
      and account_id =
        (select id from app_finance.accounts where name = 'Everyday Card')$$,
  $$values (10000::bigint)$$,
  'a percent minimum due follows the statement balance'
);

-- ---------------------------------------------------------------------------
-- Installment pricing engine
-- ---------------------------------------------------------------------------

select results_eq(
  $$select * from app_finance.resolve_plan_financing(
      'interest_rate', 100000, 10, null, null, null,
      200, 'monthly', 'flat', 0)$$,
  $$values (20000::bigint, 20000::bigint, 120000::bigint)$$,
  'flat monthly interest multiplies rate by installment count'
);
select results_eq(
  $$select * from app_finance.resolve_plan_financing(
      'interest_rate', 100000, 10, null, null, null,
      2400, 'annual', 'flat', 0)$$,
  $$values (20000::bigint, 20000::bigint, 120000::bigint)$$,
  'annual rates divide by twelve before applying'
);
select results_eq(
  $$select * from app_finance.resolve_plan_financing(
      'interest_rate', 120000, 12, null, null, null,
      200, 'monthly', 'reducing', 0)$$,
  $$values (16166::bigint, 16166::bigint, 136166::bigint)$$,
  'reducing-balance interest uses the annuity payment'
);
select results_eq(
  $$select * from app_finance.resolve_plan_financing(
      'monthly_amount', 100000, 10, null, null, 11000,
      0, 'monthly', 'flat', 0)$$,
  $$values (10000::bigint, 10000::bigint, 110000::bigint)$$,
  'a quoted monthly amount back-solves the financing cost'
);
select results_eq(
  $$select * from app_finance.resolve_plan_financing(
      'total_payable', 100000, 10, null, 115000, null,
      0, 'monthly', 'flat', 5000)$$,
  $$values (10000::bigint, 15000::bigint, 115000::bigint)$$,
  'a quoted total payable splits interest from financed fees'
);
select throws_ok(
  $$select * from app_finance.resolve_plan_financing(
      'monthly_amount', 100000, 10, null, null, 9000,
      0, 'monthly', 'flat', 0)$$,
  'P0001', null, 'a monthly amount below the principal is rejected'
);

-- ---------------------------------------------------------------------------
-- Rate-priced plan
-- ---------------------------------------------------------------------------

select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Aman'),
  'Rate Fridge', '00000000-0000-0000-0000-00000000c101',
  current_date, 120000, 12, current_date + 30,
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e101',
  'interest_rate', null, 200, 'monthly', 'flat', 0, 0, null, 0);
select results_eq(
  $$select pricing_method::text, interest_minor, financing_fees_minor,
      total_payable_minor
    from app_finance.installment_plans
    where id = '00000000-0000-0000-0000-00000000e101'$$,
  $$values ('interest_rate'::text, 28800::bigint, 28800::bigint,
    148800::bigint)$$,
  'an interest-rate plan stores its resolved financing'
);
select results_eq(
  $$select count(*)::integer, min(amount_minor)::bigint,
      max(amount_minor)::bigint
    from app_finance.installment_dues
    where plan_id = '00000000-0000-0000-0000-00000000e101'$$,
  $$values (12, 12400::bigint, 12400::bigint)$$,
  'rate-priced dues split the total evenly'
);

-- ---------------------------------------------------------------------------
-- Importing a running plan with already-paid dues
-- ---------------------------------------------------------------------------

select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Aman'),
  'Imported Phone', '00000000-0000-0000-0000-00000000c101',
  date '2026-01-10', 60000, 6, date '2026-02-05',
  0, null, null, null, null,
  '00000000-0000-0000-0000-00000000e102',
  'manual_fees', null, 0, 'monthly', 'flat', 0, 0, null, 3);
select results_eq(
  $$select
      (select count(*)::integer from app_finance.installment_dues
        where plan_id = '00000000-0000-0000-0000-00000000e102'
          and is_presettled),
      (select count(*)::integer from app_finance.installment_due_statuses
        where plan_id = '00000000-0000-0000-0000-00000000e102'
          and due_status = 'paid')$$,
  $$values (3, 3)$$,
  'imported plans mark the already-paid dues as presettled and paid'
);
select results_eq(
  $$select t.amount_minor from app_finance.installment_plans p
    join app_finance.financial_transactions t
      on t.id = p.purchase_transaction_id
    where p.id = '00000000-0000-0000-0000-00000000e102'$$,
  $$values (30000::bigint)$$,
  'importing books only the remaining amount as the recognized expense'
);
select results_eq(
  $$select paid_minor, remaining_minor, origin::text
    from app_finance.installment_plan_summaries
    where id = '00000000-0000-0000-0000-00000000e102'$$,
  $$values (30000::bigint, 30000::bigint, 'historical_import'::text)$$,
  'imported plan summaries count presettled dues as paid'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from app_finance.accounts where name = 'Aman'))$$,
  $$values (178800::bigint)$$,
  'presettled dues never inflate the outstanding debt'
);
select throws_ok(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'Aman'),
      'Fully Paid', '00000000-0000-0000-0000-00000000c101',
      date '2026-01-10', 60000, 6, date '2026-02-05',
      0, null, null, null, null, null,
      'manual_fees', null, 0, 'monthly', 'flat', 0, 0, null, 6)$$,
  'P0001', null, 'a fully paid import is rejected'
);

-- ---------------------------------------------------------------------------
-- Down payment and upfront fees from an asset account
-- ---------------------------------------------------------------------------

select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'TV', '00000000-0000-0000-0000-00000000c101',
  date '2026-03-15', 36000, 3, date '2026-04-10',
  6000, '00000000-0000-0000-0000-00000000a101', null, null, null,
  '00000000-0000-0000-0000-00000000e103',
  'manual_fees', null, 0, 'monthly', 'flat', 0, 900, date '2026-03-15', 0);
select results_eq(
  $$select count(*)::integer, sum(amount_minor)::bigint
    from app_finance.financial_transactions
    where source_account_id = '00000000-0000-0000-0000-00000000a101'
      and transaction_kind = 'expense'$$,
  $$values (2, 6900::bigint)$$,
  'the down payment and upfront fees are cash expenses, not financed'
);
select throws_ok(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'Aman'),
      'No Funding', '00000000-0000-0000-0000-00000000c101',
      current_date, 20000, 2, current_date + 10,
      5000, null, null, null, null, null,
      'manual_fees', null, 0, 'monthly', 'flat', 0, 0, null, 0)$$,
  'P0001', null, 'a down payment without a funding account is rejected'
);

-- ---------------------------------------------------------------------------
-- Payments settle statement dues before installment dues
-- ---------------------------------------------------------------------------

select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Everyday Card'),
  '00000000-0000-0000-0000-00000000a101',
  55000, current_date, null, null,
  '00000000-0000-0000-0000-00000000d101');
select results_eq(
  $$select remaining_minor, cycle_status
    from app_finance.credit_card_statement_summaries
    where cycle_close = date '2026-03-25'
      and account_id =
        (select id from app_finance.accounts where name = 'Everyday Card')$$,
  $$values (0::bigint, 'paid'::text)$$,
  'the oldest statement due is settled first'
);
select results_eq(
  $$select paid_minor, due_status
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e103'
      and sequence_number = 1$$,
  $$values (5000::bigint, 'overdue'::text)$$,
  'leftover money reaches the installment due on the same day'
);
select results_eq(
  $$select count(*)::integer, sum(amount_minor)::bigint
    from app_finance.credit_card_statement_allocations
    where payment_transaction_id =
      '00000000-0000-0000-0000-00000000d101'$$,
  $$values (1, 50000::bigint)$$,
  'statement allocations record how the payment was applied'
);
select throws_ok(
  $$select app_finance.update_installment_plan(
      '00000000-0000-0000-0000-00000000e103',
      'TV', '00000000-0000-0000-0000-00000000c101',
      date '2026-03-15', 36000, 4, date '2026-04-10',
      6000, '00000000-0000-0000-0000-00000000a101', null, null, null,
      'manual_fees', null, 0, 'monthly', 'flat', 0,
      date '2026-03-15', 0)$$,
  'P0001', null, 'a plan with recorded payments cannot be fully edited'
);
select app_finance.reverse_facility_payment(
  '00000000-0000-0000-0000-00000000d101');
select results_eq(
  $$select
      (select remaining_minor
        from app_finance.credit_card_statement_summaries
        where cycle_close = date '2026-03-25'
          and account_id =
            (select id from app_finance.accounts
              where name = 'Everyday Card')),
      (select paid_minor from app_finance.installment_due_statuses
        where plan_id = '00000000-0000-0000-0000-00000000e103'
          and sequence_number = 1)$$,
  $$values (50000::bigint, 0::bigint)$$,
  'reversing a payment releases statement and installment allocations'
);

-- ---------------------------------------------------------------------------
-- Full plan edit before any payment
-- ---------------------------------------------------------------------------

select app_finance.update_installment_plan(
  '00000000-0000-0000-0000-00000000e101',
  'Rate Fridge', '00000000-0000-0000-0000-00000000c101',
  current_date, 120000, 10, current_date + 30,
  0, null, null, null, null,
  'interest_rate', null, 200, 'monthly', 'flat', 0, null, 0);
select results_eq(
  $$select p.installment_count, p.total_payable_minor, p.interest_minor,
      (select count(*)::integer from app_finance.installment_dues d
        where d.plan_id = p.id)
    from app_finance.installment_plans p
    where p.id = '00000000-0000-0000-0000-00000000e101'$$,
  $$values (10, 144000::bigint, 24000::bigint, 10)$$,
  'editing an unpaid plan rebuilds its financing and schedule in place'
);

-- ---------------------------------------------------------------------------
-- Restructuring a partially paid plan
-- ---------------------------------------------------------------------------

select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Aman'),
  '00000000-0000-0000-0000-00000000a101',
  14400, current_date,
  (select jsonb_build_array(jsonb_build_object(
      'due_id', d.id, 'amount_minor', 14400))
    from app_finance.installment_dues d
    where d.plan_id = '00000000-0000-0000-0000-00000000e101'
      and d.sequence_number = 1),
  null, '00000000-0000-0000-0000-00000000d102');
select results_eq(
  $$select paid_minor, due_status
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e101'
      and sequence_number = 1$$,
  $$values (14400::bigint, 'paid'::text)$$,
  'the first installment is fully paid before restructuring'
);
select app_finance.restructure_installment_plan(
  '00000000-0000-0000-0000-00000000e101',
  135000, 6, current_date + 60, 'bank raised the interest', current_date);
select results_eq(
  $$select revision, installment_count, total_payable_minor
    from app_finance.installment_plans
    where id = '00000000-0000-0000-0000-00000000e101'$$,
  $$values (2, 7, 149400::bigint)$$,
  'restructuring bumps the revision and adopts the new totals'
);
select results_eq(
  $$select count(*)::integer, sum(remaining_minor)::bigint
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-00000000e101'$$,
  $$values (7, 135000::bigint)$$,
  'restructuring replaces only the unpaid dues'
);
select results_eq(
  $$select previous_total_payable_minor, new_total_payable_minor,
      change_summary
    from app_finance.installment_plan_revisions
    where plan_id = '00000000-0000-0000-0000-00000000e101'
      and revision = 2$$,
  $$values (144000::bigint, 149400::bigint,
    'bank raised the interest'::text)$$,
  'restructuring records an auditable revision'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where source_account_id =
      (select id from app_finance.accounts where name = 'Aman')
      and transaction_kind = 'expense' and amount_minor = 5400$$,
  $$values (1)$$,
  'extra recognized cost books one explicit adjustment expense'
);
select throws_ok(
  $$select app_finance.restructure_installment_plan(
      '00000000-0000-0000-0000-00000000e101',
      1000, 2, current_date + 30, null, null)$$,
  'P0001', null,
  'restructuring below the recognized cost is rejected'
);
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Aman'),
  '00000000-0000-0000-0000-00000000a101',
  4000, current_date,
  (select jsonb_build_array(jsonb_build_object(
      'due_id', d.id, 'amount_minor', 4000))
    from app_finance.installment_dues d
    where d.plan_id = '00000000-0000-0000-0000-00000000e102'
      and d.sequence_number = 5),
  null, '00000000-0000-0000-0000-00000000d103');
select throws_ok(
  $$select app_finance.restructure_installment_plan(
      '00000000-0000-0000-0000-00000000e102',
      20000, 2, current_date + 30, null, null)$$,
  'P0001', null,
  'a partially paid installment blocks restructuring until settled'
);

-- ---------------------------------------------------------------------------
-- Recurring card fee rules
-- ---------------------------------------------------------------------------

insert into app_finance.credit_card_fee_rules (
  id, user_id, account_id, name, fee_type, fixed_amount_minor,
  frequency, starts_on, category_id
) values (
  '00000000-0000-0000-0000-00000000b101',
  '00000000-0000-0000-0000-000000000046',
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'Annual Membership', 'annual_membership', 20000,
  'annually', date '2026-05-01', '00000000-0000-0000-0000-00000000c101'
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-05-02')$$,
  $$values (1)$$,
  'a due fee rule generates exactly one charge'
);
select results_eq(
  $$select f.charged_on, f.amount_minor, t.amount_minor
    from app_finance.credit_card_fee_charges f
    join app_finance.financial_transactions t on t.id = f.transaction_id
    where f.rule_id = '00000000-0000-0000-0000-00000000b101'$$,
  $$values (date '2026-05-01', 20000::bigint, 20000::bigint)$$,
  'the fee charge and its expense agree on date and amount'
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-05-02')$$,
  $$values (0)$$,
  're-running the fee generator never double-charges'
);
select results_eq(
  $$select charges_minor from app_finance.credit_card_statement_summaries
    where cycle_close = date '2026-05-25'
      and account_id =
        (select id from app_finance.accounts where name = 'Everyday Card')$$,
  $$values (20000::bigint)$$,
  'card fees join the statement cycle of their charge date'
);

insert into app_finance.credit_card_fee_rules (
  id, user_id, account_id, name, fee_type, percent_basis_points,
  percent_basis, frequency, starts_on, category_id
) values (
  '00000000-0000-0000-0000-00000000b102',
  '00000000-0000-0000-0000-000000000046',
  (select id from app_finance.accounts where name = 'Everyday Card'),
  'Issuance Fee', 'administration', 100,
  'credit_limit', 'once', date '2026-06-01',
  '00000000-0000-0000-0000-00000000c101'
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-06-02')$$,
  $$values (1)$$,
  'percent fee rules charge when they fall due'
);
select results_eq(
  $$select
      (select amount_minor from app_finance.credit_card_fee_charges
        where rule_id = '00000000-0000-0000-0000-00000000b102'),
      (select is_active from app_finance.credit_card_fee_rules
        where id = '00000000-0000-0000-0000-00000000b102')$$,
  $$values (10000::bigint, false)$$,
  'a one-off percent fee charges its basis and deactivates itself'
);

-- ---------------------------------------------------------------------------
-- Push devices, preferences, and the notification outbox
-- ---------------------------------------------------------------------------

select lives_ok(
  $$insert into app_core.push_devices (
      id, user_id, fcm_token, platform
    ) values (
      '00000000-0000-0000-0000-00000000de01',
      '00000000-0000-0000-0000-000000000046',
      'unit-test-fake-token-0001', 'android'
    )$$,
  'owners can register their own push devices'
);
insert into app_core.notification_preferences (user_id)
  values ('00000000-0000-0000-0000-000000000046');
select results_eq(
  $$select show_amounts, due_reminders_enabled
    from app_core.notification_preferences
    where user_id = '00000000-0000-0000-0000-000000000046'$$,
  $$values (false, true)$$,
  'notification amounts stay hidden by default'
);
select throws_ok(
  $$insert into app_core.notification_outbox (
      user_id, device_id, obligation_type, obligation_id, reminder_kind,
      scheduled_local_date
    ) values (
      '00000000-0000-0000-0000-000000000046',
      '00000000-0000-0000-0000-00000000de01',
      'installment_due', '00000000-0000-0000-0000-00000000e101',
      'due_today', current_date
    )$$,
  '42501', null, 'clients cannot forge notification outbox rows'
);

reset role;
set local role service_role;
select lives_ok(
  $$insert into app_core.notification_outbox (
      user_id, device_id, obligation_type, obligation_id, reminder_kind,
      scheduled_local_date
    ) values (
      '00000000-0000-0000-0000-000000000046',
      '00000000-0000-0000-0000-00000000de01',
      'installment_due', '00000000-0000-0000-0000-00000000e101',
      'due_today', current_date
    )$$,
  'the trusted sender records deliveries in the outbox'
);
select throws_ok(
  $$insert into app_core.notification_outbox (
      user_id, device_id, obligation_type, obligation_id, reminder_kind,
      scheduled_local_date
    ) values (
      '00000000-0000-0000-0000-000000000046',
      '00000000-0000-0000-0000-00000000de01',
      'installment_due', '00000000-0000-0000-0000-00000000e101',
      'due_today', current_date
    )$$,
  '23505', null, 'the outbox is idempotent per obligation and date'
);
reset role;
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000046","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_core.notification_outbox$$,
  $$values (1)$$,
  'owners can read their own delivery history'
);

-- ---------------------------------------------------------------------------
-- RLS isolation
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000047","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer
    from app_finance.credit_card_statement_summaries$$,
  $$values (0)$$,
  'statement summaries are invisible to other users'
);
select results_eq(
  $$select
      (select count(*) from app_finance.credit_card_fee_rules)
      + (select count(*) from app_core.push_devices)
      + (select count(*) from app_core.notification_outbox)$$,
  $$values (0::bigint)$$,
  'fee rules, devices, and the outbox are invisible to other users'
);
select throws_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts
        where name = 'Everyday Card'
          and user_id = '00000000-0000-0000-0000-000000000046'),
      'Steal', '00000000-0000-0000-0000-00000000c101',
      current_date, 1000, null, null)$$,
  'P0001', null, 'cross-user card charges are rejected'
);
select throws_ok(
  $$select app_finance.restructure_installment_plan(
      '00000000-0000-0000-0000-00000000e101',
      10000, 2, current_date + 30, null, null)$$,
  'P0001', null, 'cross-user restructuring is rejected'
);

-- ---------------------------------------------------------------------------
-- Account deletion cascade
-- ---------------------------------------------------------------------------

reset role;
set local role service_role;
select app_core.delete_finance_suit_data(
  '00000000-0000-0000-0000-000000000046');
reset role;

select results_eq(
  $$select
      (select count(*) from app_finance.credit_card_statement_cycles
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_finance.credit_card_statement_items
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_finance.credit_card_statement_allocations
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_finance.credit_card_fee_rules
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_finance.credit_card_fee_charges
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_finance.installment_plan_revisions
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_core.push_devices
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_core.notification_preferences
        where user_id = '00000000-0000-0000-0000-000000000046')
      + (select count(*) from app_core.notification_outbox
        where user_id = '00000000-0000-0000-0000-000000000046')$$,
  $$values (0::bigint)$$,
  'account deletion removes every statement, fee, and notification record'
);

select * from finish();
rollback;
