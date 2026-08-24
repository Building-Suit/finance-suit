begin;
create extension if not exists pgtap with schema extensions;

select plan(61);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000051',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'bnpl-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Bnpl Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000052',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'bnpl-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Bnpl Intruder"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------

select has_table('app_finance', 'bnpl_purchase_obligations',
  'bnpl obligations table exists');
select has_table('app_finance', 'bnpl_purchase_payment_allocations',
  'bnpl allocations table exists');
select has_view('app_finance', 'bnpl_purchase_obligation_statuses',
  'bnpl obligation status view exists');
select has_function('app_finance', 'bnpl_purchase_due_on',
  array['smallint', 'date'], 'due-date rule exists');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.bnpl_purchase_obligations'::regclass),
  'RLS on bnpl_purchase_obligations');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.bnpl_purchase_payment_allocations'::regclass),
  'RLS on bnpl_purchase_payment_allocations');

-- ---------------------------------------------------------------------------
-- The due-date rule
-- ---------------------------------------------------------------------------

select results_eq(
  $$select app_finance.bnpl_purchase_due_on(5::smallint, date '2026-08-02')$$,
  $$values (date '2026-09-05')$$,
  'a purchase is always billed with the following month'
);
select results_eq(
  $$select app_finance.bnpl_purchase_due_on(5::smallint, date '2026-08-05')$$,
  $$values (date '2026-09-05')$$,
  'a purchase on the due day is billed next month'
);
select results_eq(
  $$select app_finance.bnpl_purchase_due_on(5::smallint, date '2026-08-16')$$,
  $$values (date '2026-09-05')$$,
  'a purchase after the due day rolls to next month'
);
select results_eq(
  $$select app_finance.bnpl_purchase_due_on(31::smallint, date '2026-01-31')$$,
  $$values (date '2026-02-28')$$,
  'day 31 clamps to the last day of a common February'
);
select results_eq(
  $$select app_finance.bnpl_purchase_due_on(31::smallint, date '2028-01-31')$$,
  $$values (date '2028-02-29')$$,
  'day 31 clamps to the 29th in a leap February'
);
select results_eq(
  $$select app_finance.bnpl_purchase_due_on(30::smallint, date '2026-02-27')$$,
  $$values (date '2026-03-30')$$,
  'a short-month purchase is billed on the configured day next month'
);
select results_eq(
  $$select app_finance.bnpl_purchase_due_on(5::smallint, date '2026-12-20')$$,
  $$values (date '2027-01-05')$$,
  'December rolls into January of the next year'
);
select ok(
  (select app_finance.bnpl_purchase_due_on(5::smallint, date '2026-08-05'))
    > date '2026-08-05',
  'the due date is always strictly after the purchase date'
);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000051","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000051a01',
  '00000000-0000-0000-0000-000000000051', 'Bnpl Wallet', 'cash', 'EGP',
  100000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-000000051c01',
  '00000000-0000-0000-0000-000000000051', 'Bnpl Shopping', 'expense'
);

select app_finance.save_credit_facility(
  'ValU', 'bnpl', 'EGP', 2000000, 5::smallint);
select app_finance.save_credit_facility(
  'Aman', 'bnpl', 'EGP', 2000000, 5::smallint);
select app_finance.save_credit_facility(
  'Card', 'credit_card', 'EGP', 2000000, 25::smallint,
  p_statement_day => 10::smallint);

-- An ordinary purchase on the 2nd is billed on the 5th of next month.
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'ValU'),
  'Amazon', '00000000-0000-0000-0000-000000051c01',
  date_trunc('month', current_date)::date + 1, 100000, null,
  '00000000-0000-0000-0000-000000051f01');

select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where id = '00000000-0000-0000-0000-000000051f01'
      and transaction_kind = 'expense'$$,
  $$values (1)$$,
  'an ordinary BNPL purchase books exactly one expense'
);
select results_eq(
  $$select count(*)::integer, min(due_on)
    from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000051f01'$$,
  $$values (1, (date_trunc('month', current_date) + interval '1 month 4 days')::date)$$,
  'it creates exactly one obligation on the configured due day'
);
select results_eq(
  $$select outstanding_minor, available_credit_minor
    from app_finance.credit_facility_summaries where name = 'ValU'$$,
  $$values (100000::bigint, 1900000::bigint)$$,
  'outstanding rises once and available credit falls once'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items si
    join app_finance.financial_transactions t on t.id = si.transaction_id
    where t.id = '00000000-0000-0000-0000-000000051f01'$$,
  $$values (0)$$,
  'a BNPL purchase never becomes a credit card statement item'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_plans
    where account_id = (select id from app_finance.accounts where name = 'ValU')$$,
  $$values (0)$$,
  'no installment plan is invented for an ordinary purchase'
);

-- Credit card regression: statement linkage still happens, no BNPL obligation.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Card'),
  'Card Groceries', '00000000-0000-0000-0000-000000051c01',
  date_trunc('month', current_date)::date, 50000, null,
  '00000000-0000-0000-0000-000000051f02');
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-000000051f02'$$,
  $$values (1)$$,
  'a credit card charge still lands on its statement cycle'
);
select results_eq(
  $$select count(*)::integer from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000051f02'$$,
  $$values (0)$$,
  'a credit card charge never creates a BNPL obligation'
);

-- Installment regression: the plan purchase must not double as an obligation.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'ValU'),
  'Phone', '00000000-0000-0000-0000-000000051c01',
  date_trunc('month', current_date)::date, 300000, 3,
  (date_trunc('month', current_date) + interval '1 month 4 days')::date,
  0, null, null, null, null,
  '00000000-0000-0000-0000-000000051e01'
);
select results_eq(
  $$select count(*)::integer from app_finance.bnpl_purchase_obligations o
    join app_finance.installment_plans p
      on p.purchase_transaction_id = o.transaction_id$$,
  $$values (0)$$,
  'a plan-controlled purchase never also becomes an ordinary obligation'
);

-- ---------------------------------------------------------------------------
-- Facility summary
-- ---------------------------------------------------------------------------

select results_eq(
  $$select next_due_on, next_due_amount_minor
    from app_finance.credit_facility_summaries where name = 'ValU'$$,
  $$values ((date_trunc('month', current_date) + interval '1 month 4 days')::date,
    200000::bigint)$$,
  'next due sums the purchase and the installment sharing that date'
);

-- A second purchase on the same due date adds to the same bill.
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'ValU'),
  'Carrefour', '00000000-0000-0000-0000-000000051c01',
  date_trunc('month', current_date)::date + 1, 50000, null,
  '00000000-0000-0000-0000-000000051f03');
select results_eq(
  $$select next_due_amount_minor
    from app_finance.credit_facility_summaries where name = 'ValU'$$,
  $$values (250000::bigint)$$,
  'a second purchase on the same date raises the next due amount'
);

-- A later purchase must not pull the next due date forward or inflate it.
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'ValU'),
  'Later', '00000000-0000-0000-0000-000000051c01',
  (date_trunc('month', current_date) + interval '1 month 10 days')::date,
  70000, null, '00000000-0000-0000-0000-000000051f04');
select results_eq(
  $$select next_due_on, next_due_amount_minor
    from app_finance.credit_facility_summaries where name = 'ValU'$$,
  $$values ((date_trunc('month', current_date) + interval '1 month 4 days')::date,
    250000::bigint)$$,
  'the earliest date wins and later months are not summed into it'
);

-- ---------------------------------------------------------------------------
-- Due breakdown and Home
-- ---------------------------------------------------------------------------

select results_eq(
  $$select count(*)::integer
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'ValU'),
      (date_trunc('month', current_date) + interval '1 month 4 days')::date) b,
    jsonb_array_elements(b -> 'components') c
    where c ->> 'component_type' = 'bnpl_purchase'$$,
  $$values (2)$$,
  'the due breakdown exposes ordinary BNPL purchases as components'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'ValU'),
      (date_trunc('month', current_date) + interval '1 month 4 days')::date) b,
    jsonb_array_elements(b -> 'components') c
    where c ->> 'component_type' = 'bnpl_purchase'
      and (c ->> 'due_on')::date
        = (date_trunc('month', current_date) + interval '1 month 4 days')::date
      and (c ->> 'occurred_on')::date
        = (date_trunc('month', current_date) + interval '1 day')::date$$,
  $$values (2)$$,
  'a BNPL component carries both its purchase date and its due date'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.home_current_month_obligations(
      (date_trunc('month', current_date) + interval '1 month 1 day')::date) o
    where o.obligation_kind = 'bnpl_purchase'
      and o.due_on = (date_trunc('month', current_date) + interval '1 month 4 days')::date
      and o.remaining_minor = 150000$$,
  $$values (1)$$,
  'Home groups the two purchases due that day into one real obligation'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.home_current_month_obligations(
      (date_trunc('month', current_date) + interval '1 month 1 day')::date) o
    where o.obligation_kind = 'bnpl_purchase'
      and o.due_on
        = (date_trunc('month', current_date) + interval '1 month 1 day')::date$$,
  $$values (0)$$,
  'Home no longer invents a due-today obligation for BNPL purchases'
);
select results_eq(
  $$select o.remaining_minor
    from app_finance.home_current_month_obligations(
      (date_trunc('month', current_date) + interval '1 month 1 day')::date) o
    where o.obligation_kind = 'installment_due'
      and o.source_name = 'ValU'
    order by o.due_on limit 1$$,
  $$values (100000::bigint)$$,
  'the installment row no longer absorbs ordinary purchase totals'
);

-- ---------------------------------------------------------------------------
-- Payment
-- ---------------------------------------------------------------------------

-- The activity classification agrees with what the server will allow: an
-- unpaid purchase stays editable, a purchase carrying an allocation does not.
select results_eq(
  $$select count(*)::integer from app_finance.facility_activity_items i
    where i.transaction_id = '00000000-0000-0000-0000-000000051f01'
      and not i.is_settled$$,
  $$values (1)$$,
  'an unpaid ordinary BNPL purchase is not reported as settled'
);

select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'ValU'),
      '00000000-0000-0000-0000-000000051a01',
      40000, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', (select obligation_id
          from app_finance.bnpl_purchase_obligation_statuses
          where title = 'Amazon'),
        'amount_minor', 40000)),
      null, '00000000-0000-0000-0000-000000051901')$$,
  'an ordinary BNPL purchase can be paid partially'
);
select results_eq(
  $$select paid_minor, remaining_minor, payment_status
    from app_finance.bnpl_purchase_obligation_statuses where title = 'Amazon'$$,
  $$values (40000::bigint, 60000::bigint, 'partially_paid'::text)$$,
  'the purchase reports paid 40000 / remaining 60000'
);
select results_eq(
  $$select count(*)::integer from app_finance.facility_activity_items i
    where i.transaction_id = '00000000-0000-0000-0000-000000051f01'
      and i.is_settled$$,
  $$values (1)$$,
  'once money is applied the purchase reports itself as settled'
);
select results_eq(
  $$select remaining_minor
    from app_finance.bnpl_purchase_obligation_statuses where title = 'Carrefour'$$,
  $$values (50000::bigint)$$,
  'the unselected purchase is untouched'
);
select results_eq(
  $$select outstanding_minor
    from app_finance.credit_facility_summaries where name = 'ValU'$$,
  $$values (480000::bigint)$$,
  'the repayment reduces facility outstanding exactly once'
);
select results_eq(
  $$select component_type, title, amount_minor
    from app_finance.facility_payment_allocations
    where payment_transaction_id = '00000000-0000-0000-0000-000000051901'$$,
  $$values ('bnpl_purchase'::text, 'Amazon'::text, 40000::bigint)$$,
  'payment detail shows the exact persisted BNPL allocation'
);

-- One payment across a purchase and an installment due.
select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'ValU'),
      '00000000-0000-0000-0000-000000051a01',
      110000, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(
        jsonb_build_object('type', 'bnpl_purchase',
          'id', (select obligation_id
            from app_finance.bnpl_purchase_obligation_statuses
            where title = 'Carrefour'),
          'amount_minor', 50000),
        jsonb_build_object('type', 'installment_due',
          'id', (select id from app_finance.installment_dues
            where plan_id = '00000000-0000-0000-0000-000000051e01'
              and sequence_number = 1),
          'amount_minor', 60000)),
      null, '00000000-0000-0000-0000-000000051902')$$,
  'one payment can settle a purchase and an installment together'
);
select results_eq(
  $$select payment_status
    from app_finance.bnpl_purchase_obligation_statuses where title = 'Carrefour'$$,
  $$values ('paid'::text)$$,
  'the fully paid purchase is marked paid'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_payment_allocations
    where payment_transaction_id = '00000000-0000-0000-0000-000000051902'$$,
  $$values (2)$$,
  'both allocations are persisted for that payment'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.home_current_month_obligations(
      (date_trunc('month', current_date) + interval '1 month 1 day')::date) o,
    jsonb_array_elements(o.details -> 'items') i
    where o.obligation_kind = 'bnpl_purchase'
      and i ->> 'title' = 'Carrefour'$$,
  $$values (0)$$,
  'a fully paid purchase stops showing as due on Home'
);

-- Rejections.
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'ValU'),
      '00000000-0000-0000-0000-000000051a01',
      999999, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', (select obligation_id
          from app_finance.bnpl_purchase_obligation_statuses
          where title = 'Amazon'),
        'amount_minor', 999999)),
      null, null)$$,
  'P0001', null, 'over-allocating a purchase is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'ValU'),
      '00000000-0000-0000-0000-000000051a01',
      10000, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', (select obligation_id
          from app_finance.bnpl_purchase_obligation_statuses
          where title = 'Carrefour'),
        'amount_minor', 10000)),
      null, null)$$,
  'P0001', null, 'an already settled purchase is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Aman'),
      '00000000-0000-0000-0000-000000051a01',
      10000, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', (select obligation_id
          from app_finance.bnpl_purchase_obligation_statuses
          where title = 'Amazon'),
        'amount_minor', 10000)),
      null, null)$$,
  'P0001', null, 'a purchase from another facility is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'ValU'),
      '00000000-0000-0000-0000-000000051a01',
      20000, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(
        jsonb_build_object('type', 'bnpl_purchase',
          'id', (select obligation_id
            from app_finance.bnpl_purchase_obligation_statuses
            where title = 'Amazon'),
          'amount_minor', 10000),
        jsonb_build_object('type', 'bnpl_purchase',
          'id', (select obligation_id
            from app_finance.bnpl_purchase_obligation_statuses
            where title = 'Amazon'),
          'amount_minor', 10000)),
      null, null)$$,
  'P0001', null, 'the same purchase cannot be allocated twice in one payment'
);
select results_eq(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'ValU'),
      '00000000-0000-0000-0000-000000051a01',
      40000, (date_trunc('month', current_date) + interval '1 month 4 days')::date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', (select obligation_id
          from app_finance.bnpl_purchase_obligation_statuses
          where title = 'Amazon'),
        'amount_minor', 40000)),
      null, '00000000-0000-0000-0000-000000051901')$$,
  $$values ('00000000-0000-0000-0000-000000051901'::uuid)$$,
  'retrying the same payment id is idempotent'
);

-- ---------------------------------------------------------------------------
-- Reversal
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.reverse_facility_payment(
      '00000000-0000-0000-0000-000000051902')$$,
  'a payment carrying a BNPL allocation can be reversed'
);
select results_eq(
  $$select remaining_minor, payment_status
    from app_finance.bnpl_purchase_obligation_statuses where title = 'Carrefour'$$,
  $$values (50000::bigint, 'unpaid'::text)$$,
  'reversal restores the purchase remaining amount'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.bnpl_purchase_payment_allocations
    where payment_transaction_id = '00000000-0000-0000-0000-000000051902'$$,
  $$values (0)$$,
  'its BNPL allocation rows are gone'
);

-- ---------------------------------------------------------------------------
-- Edit and delete lifecycle
-- ---------------------------------------------------------------------------

-- Re-dating an unpaid purchase recalculates its due date.
select lives_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-000000051f04',
      (select id from app_finance.accounts where name = 'ValU'),
      date_trunc('month', current_date)::date + 1, 70000,
      '00000000-0000-0000-0000-000000051c01')$$,
  'an unpaid BNPL purchase can be re-dated'
);
select results_eq(
  $$select due_on from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000051f04'$$,
  $$values ((date_trunc('month', current_date) + interval '1 month 4 days')::date)$$,
  'the obligation due date follows the new purchase date'
);
-- Moving it to an asset account drops the obligation.
select lives_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-000000051f04',
      '00000000-0000-0000-0000-000000051a01',
      date_trunc('month', current_date)::date + 1, 70000,
      '00000000-0000-0000-0000-000000051c01')$$,
  'a BNPL purchase can be moved to an asset account'
);
select results_eq(
  $$select count(*)::integer from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000051f04'$$,
  $$values (0)$$,
  'moving it off BNPL removes the obligation'
);
-- And back again recreates it.
select lives_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-000000051f04',
      (select id from app_finance.accounts where name = 'Aman'),
      date_trunc('month', current_date)::date + 1, 70000,
      '00000000-0000-0000-0000-000000051c01')$$,
  'it can move to another BNPL facility'
);
select results_eq(
  $$select account_id from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000051f04'$$,
  $$values ((select id from app_finance.accounts where name = 'Aman'))$$,
  'the obligation follows it to the new facility'
);
-- A settled purchase is protected.
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-000000051f01',
      (select id from app_finance.accounts where name = 'ValU'),
      date_trunc('month', current_date)::date + 3, 100000,
      '00000000-0000-0000-0000-000000051c01')$$,
  'P0001', null,
  'a purchase with payments cannot be silently re-dated'
);
select throws_ok(
  $$select app_finance.delete_ledger_transaction(
      '00000000-0000-0000-0000-000000051f01')$$,
  'P0001', null,
  'a purchase with payments cannot be ordinary-deleted'
);
select lives_ok(
  $$select app_finance.delete_ledger_transaction(
      '00000000-0000-0000-0000-000000051f04')$$,
  'an unpaid purchase deletes safely'
);
select results_eq(
  $$select count(*)::integer from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000051f04'$$,
  $$values (0)$$,
  'its obligation is removed with it, leaving no orphan'
);

-- ---------------------------------------------------------------------------
-- Isolation
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000052","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer
    from app_finance.bnpl_purchase_obligation_statuses$$,
  $$values (0)$$,
  'another user sees no BNPL obligations'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select a.id from app_finance.accounts a where a.name = 'ValU'
        and a.user_id = '00000000-0000-0000-0000-000000000051'),
      '00000000-0000-0000-0000-000000051a01',
      10000, current_date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', '00000000-0000-0000-0000-000000051f01',
        'amount_minor', 10000)),
      null, null)$$,
  'P0001', null,
  'another user cannot allocate against these obligations'
);

select * from finish();
rollback;
