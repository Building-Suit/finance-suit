begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000049',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'month-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Month Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000050',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'month-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Month Intruder"}', now(), now()
);

select has_function('app_finance', 'facility_month_due_breakdown',
  array['uuid', 'date'], 'facility_month_due_breakdown exists');
select has_function('app_finance', 'pay_credit_facility_v3',
  array['uuid', 'uuid', 'bigint', 'date', 'date', 'jsonb', 'text', 'uuid'],
  'pay_credit_facility_v3 exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000049","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000049a01',
  '00000000-0000-0000-0000-000000000049',
  'Month Wallet', 'cash', 'EGP', 100000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-000000049c01',
  '00000000-0000-0000-0000-000000000049', 'Month Shopping', 'expense'
);

select app_finance.save_credit_facility(
  'Month Visa', 'credit_card', 'EGP', 100000000, 25::smallint,
  p_statement_day => 10::smallint);
select app_finance.save_credit_facility(
  'Other Visa', 'credit_card', 'EGP', 10000000, 25::smallint,
  p_statement_day => 10::smallint);

-- Plan A: dues on the 25th of this month, next month, and the month after.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Month Visa'),
  'Fridge', '00000000-0000-0000-0000-000000049c01',
  date_trunc('month', current_date)::date, 300000, 3,
  (date_trunc('month', current_date) + interval '24 days')::date,
  0, null, null, null, null,
  '00000000-0000-0000-0000-000000049e01'
);
-- Plan B on the other facility, same due dates, to prove account isolation.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Other Visa'),
  'Other Fridge', '00000000-0000-0000-0000-000000049c01',
  date_trunc('month', current_date)::date, 200000, 2,
  (date_trunc('month', current_date) + interval '24 days')::date,
  0, null, null, null, null,
  '00000000-0000-0000-0000-000000049e02'
);
-- Plan C across the December -> January boundary (fixed dates).
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Month Visa'),
  'Winter Sofa', '00000000-0000-0000-0000-000000049c01',
  date '2026-12-01', 200000, 2, date '2026-12-25',
  0, null, null, null, null,
  '00000000-0000-0000-0000-000000049e03'
);
-- A card charge dated the 1st of this month always lands in the cycle that
-- closes on the 10th and falls due on the 25th of this month.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Month Visa'),
  'Groceries', '00000000-0000-0000-0000-000000049c01',
  date_trunc('month', current_date)::date, 40000, null,
  '00000000-0000-0000-0000-000000049f01');

-- ---------------------------------------------------------------------------
-- The existing breakdown is cumulative, not month scoped
-- ---------------------------------------------------------------------------

-- Asking the payable-now breakdown for next month still returns this month's
-- installment due, which is exactly why a month-scoped RPC is needed.
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      (date_trunc('month', current_date) + interval '1 month')::date) b,
    jsonb_array_elements(b -> 'components') c
    where c ->> 'component_id' = (select id::text
      from app_finance.installment_dues
      where plan_id = '00000000-0000-0000-0000-000000049e01'
        and sequence_number = 1)$$,
  $$values (1)$$,
  'the payable-now breakdown still carries this month''s due when asked for next month'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      (date_trunc('month', current_date) + interval '1 month')::date) m,
    jsonb_array_elements(m -> 'components') c
    where c ->> 'component_id' = (select id::text
      from app_finance.installment_dues
      where plan_id = '00000000-0000-0000-0000-000000049e01'
        and sequence_number = 1)$$,
  $$values (0)$$,
  'the month-scoped breakdown excludes it, proving real month isolation'
);

-- ---------------------------------------------------------------------------
-- Month scoping
-- ---------------------------------------------------------------------------

select results_eq(
  $$select (m ->> 'month_start')::date, (m ->> 'month_end')::date
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      current_date) m$$,
  $$values (date_trunc('month', current_date)::date,
    (date_trunc('month', current_date) + interval '1 month - 1 day')::date)$$,
  'the month window is derived from calendar boundaries'
);
select results_eq(
  $$select (m ->> 'total_due_minor')::bigint,
      (m ->> 'paid_minor')::bigint, (m ->> 'remaining_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      current_date) m$$,
  $$values (140000::bigint, 0::bigint, 140000::bigint)$$,
  'this month totals one installment due plus the statement charge'
);
select results_eq(
  $$select (m ->> 'total_due_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      (date_trunc('month', current_date) + interval '1 month')::date) m$$,
  $$values (100000::bigint)$$,
  'next month totals only next month''s installment due'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      (date_trunc('month', current_date) + interval '1 month')::date) m,
    jsonb_array_elements(m -> 'components') c
    where (c ->> 'due_on')::date
      not between (date_trunc('month', current_date) + interval '1 month')::date
        and (date_trunc('month', current_date)
          + interval '2 months - 1 day')::date$$,
  $$values (0)$$,
  'no component outside the requested month leaks into the payload'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      current_date) m,
    jsonb_array_elements(m -> 'components') c
    where c ->> 'title' = 'Other Fridge'$$,
  $$values (0)$$,
  'another facility''s dues never appear in this facility''s month'
);

-- Calendar boundaries.
select results_eq(
  $$select (m ->> 'month_start')::date, (m ->> 'month_end')::date,
      (m ->> 'total_due_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      date '2026-12-14') m$$,
  $$values (date '2026-12-01', date '2026-12-31', 100000::bigint)$$,
  'December resolves to its own month and dues'
);
select results_eq(
  $$select (m ->> 'month_start')::date, (m ->> 'month_end')::date,
      (m ->> 'total_due_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      date '2027-01-03') m$$,
  $$values (date '2027-01-01', date '2027-01-31', 100000::bigint)$$,
  'December rolls into January of the next year, not month 13'
);
select results_eq(
  $$select (m ->> 'month_end')::date
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      date '2028-02-07') m$$,
  $$values (date '2028-02-29')$$,
  'February in a leap year ends on the 29th'
);
select results_eq(
  $$select (m ->> 'month_end')::date
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      date '2027-02-07') m$$,
  $$values (date '2027-02-28')$$,
  'February in a common year ends on the 28th'
);

-- ---------------------------------------------------------------------------
-- Next-month prepayment while this month is still unpaid
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      40000, current_date,
      (date_trunc('month', current_date) + interval '1 month')::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 2),
        'amount_minor', 40000)),
      null, '00000000-0000-0000-0000-000000049901')$$,
  'next month can be prepaid while this month is still unpaid'
);
select results_eq(
  $$select (m ->> 'paid_minor')::bigint, (m ->> 'remaining_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      (date_trunc('month', current_date) + interval '1 month')::date) m$$,
  $$values (40000::bigint, 60000::bigint)$$,
  'the partial prepayment raises next month paid and lowers left to pay'
);
select results_eq(
  $$select (m ->> 'paid_minor')::bigint, (m ->> 'remaining_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      current_date) m$$,
  $$values (0::bigint, 140000::bigint)$$,
  'this month is left completely untouched by the prepayment'
);
select results_eq(
  $$select due_status from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-000000049e01'
      and sequence_number = 1$$,
  $$values ('upcoming'::text)$$,
  'this month''s due keeps its own unpaid state'
);
select lives_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      60000, current_date,
      (date_trunc('month', current_date) + interval '1 month')::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 2),
        'amount_minor', 60000)),
      null, '00000000-0000-0000-0000-000000049902')$$,
  'the rest of the next-month due can be paid later'
);
select results_eq(
  $$select (m ->> 'remaining_minor')::bigint
    from app_finance.facility_month_due_breakdown(
      (select id from app_finance.accounts where name = 'Month Visa'),
      (date_trunc('month', current_date) + interval '1 month')::date) m$$,
  $$values (0::bigint)$$,
  'next month is settled once its dues are fully prepaid'
);
select results_eq(
  $$select due_on, amount_minor, remaining_minor
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-000000049e01'
      and sequence_number = 2$$,
  $$values ((date_trunc('month', current_date)
      + interval '1 month 24 days')::date, 100000::bigint, 0::bigint)$$,
  'the prepaid due keeps its schedule and cannot be charged again'
);

-- ---------------------------------------------------------------------------
-- Month-scoped rejections
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      40000, current_date,
      (date_trunc('month', current_date) + interval '1 month')::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 1),
        'amount_minor', 40000)),
      null, null)$$,
  'P0001', null,
  'a component from another month is rejected atomically'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      40000, current_date,
      (date_trunc('month', current_date) + interval '2 months')::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 3),
        'amount_minor', 40000)),
      null, null)$$,
  'P0001', null,
  'a month beyond next month cannot be paid at all'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      40000, current_date,
      date_trunc('month', current_date)::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e02'
            and sequence_number = 1),
        'amount_minor', 40000)),
      null, null)$$,
  'P0001', null,
  'a component from another facility is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      10000, current_date,
      (date_trunc('month', current_date) + interval '1 month')::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 2),
        'amount_minor', 10000)),
      null, null)$$,
  'P0001', null,
  'an already settled component is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      999999, current_date,
      date_trunc('month', current_date)::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 1),
        'amount_minor', 999999)),
      null, null)$$,
  'P0001', null,
  'paying more than the component remaining is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      0, current_date,
      date_trunc('month', current_date)::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 1),
        'amount_minor', 0)),
      null, null)$$,
  'P0001', null,
  'a zero payment is rejected'
);

-- ---------------------------------------------------------------------------
-- The legacy contract is untouched
-- ---------------------------------------------------------------------------

-- v2 still refuses a future due while a current one is unpaid: the new month
-- scope must not have broadened its upcoming-due fallback.
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      40000, current_date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 3),
        'amount_minor', 40000)),
      null, null)$$,
  'P0001', null,
  'pay_credit_facility_v2 keeps its currently-payable eligibility'
);
select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Month Visa'),
      '00000000-0000-0000-0000-000000049a01',
      100000, current_date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000049e01'
            and sequence_number = 1),
        'amount_minor', 100000)),
      null, '00000000-0000-0000-0000-000000049903')$$,
  'pay_credit_facility_v2 still pays a currently payable due'
);

-- ---------------------------------------------------------------------------
-- Authorization
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000050","role":"authenticated"}';

select throws_ok(
  $$select app_finance.facility_month_due_breakdown(
      (select a.id from app_finance.accounts a where a.name = 'Month Visa'
        and a.user_id = '00000000-0000-0000-0000-000000000049'),
      current_date)$$,
  'P0001', null,
  'another user cannot read this facility''s month breakdown'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v3(
      (select a.id from app_finance.accounts a where a.name = 'Month Visa'
        and a.user_id = '00000000-0000-0000-0000-000000000049'),
      '00000000-0000-0000-0000-000000049a01',
      10000, current_date, date_trunc('month', current_date)::date,
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', '00000000-0000-0000-0000-000000049e01',
        'amount_minor', 10000)),
      null, null)$$,
  'P0001', null,
  'another user cannot pay against this facility'
);

select * from finish();
rollback;
