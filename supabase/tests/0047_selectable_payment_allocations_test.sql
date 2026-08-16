begin;
create extension if not exists pgtap with schema extensions;

select plan(60);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000047',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'alloc-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Alloc Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000048',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'alloc-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Alloc Intruder"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------

select has_table('app_finance', 'credit_card_statement_item_allocations',
  'item-level statement allocations table exists');
select has_function('app_finance', 'pay_credit_facility_v2',
  array['uuid', 'uuid', 'bigint', 'date', 'jsonb', 'text', 'uuid'],
  'pay_credit_facility_v2 exists');
select has_function('app_finance', 'facility_due_breakdown',
  array['uuid', 'date'], 'facility_due_breakdown exists');
select has_view('app_finance', 'credit_card_statement_item_statuses',
  'statement item status view exists');
select has_view('app_finance', 'facility_payment_allocations',
  'payment allocation detail view exists');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.credit_card_statement_item_allocations'::regclass),
  'RLS on credit_card_statement_item_allocations');
select has_column('app_finance', 'credit_card_statement_summaries',
  'minimum_remaining_minor', 'summaries expose minimum_remaining_minor');
select has_column('app_finance', 'credit_card_statement_summaries',
  'minimum_paid_minor', 'summaries expose minimum_paid_minor');

-- ---------------------------------------------------------------------------
-- Fixture: card with a 5% minimum, one closed statement, one plan; BNPL plan
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000047","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000047a01',
  '00000000-0000-0000-0000-000000000047',
  'Alloc Wallet', 'cash', 'EGP', 10000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-000000047c01',
  '00000000-0000-0000-0000-000000000047',
  'Alloc Shopping', 'expense'
);

select app_finance.save_credit_facility(
  'Item Visa', 'credit_card', 'EGP', 2000000, 25::smallint,
  p_statement_day => 10::smallint,
  p_min_payment_method => 'percent',
  p_min_payment_basis_points => 500
);
select app_finance.save_credit_facility(
  'Item Valu', 'bnpl', 'EGP', 1000000, 1::smallint
);

-- Two card charges inside the March statement (closes 2026-03-10).
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Item Visa'),
  'OpenAI', '00000000-0000-0000-0000-000000047c01',
  date '2026-03-05', 70000, null, '00000000-0000-0000-0000-000000047f01');
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Item Visa'),
  'Netflix', '00000000-0000-0000-0000-000000047c01',
  date '2026-03-06', 30000, null, '00000000-0000-0000-0000-000000047f02');

-- Card plan: 3 × 100000 due 2026-01-25 / 02-25 / 03-25.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Item Visa'),
  'Samsung', '00000000-0000-0000-0000-000000047c01',
  date '2026-01-05', 300000, 3, date '2026-01-25',
  0, null, null, null, null,
  '00000000-0000-0000-0000-000000047e01'
);

-- BNPL plan: 4 × 50000 due 2026-03-01 / 04-01 / 05-01 / 06-01.
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Item Valu'),
  'Bnpl Phone', '00000000-0000-0000-0000-000000047c01',
  date '2026-02-15', 200000, 4, date '2026-03-01',
  0, null, null, null, null,
  '00000000-0000-0000-0000-000000047e02'
);

select results_eq(
  $$select cycle_close, due_on, card_charges_minor, minimum_due_minor
    from app_finance.credit_card_statement_summaries
    where account_id =
      (select id from app_finance.accounts where name = 'Item Visa')$$,
  $$values (date '2026-03-10', date '2026-03-25',
    100000::bigint, 5000::bigint)$$,
  'the 5%% percent rule yields the configured server-side minimum'
);

-- ---------------------------------------------------------------------------
-- Due breakdown DTO before any payment
-- ---------------------------------------------------------------------------

select results_eq(
  $$select (b ->> 'total_due_minor')::bigint,
      (b ->> 'paid_minor')::bigint,
      (b ->> 'remaining_minor')::bigint,
      (b ->> 'minimum_due_minor')::bigint,
      (b ->> 'minimum_remaining_minor')::bigint
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'Item Visa'),
      date '2026-04-01') b$$,
  $$values (400000::bigint, 0::bigint, 400000::bigint,
    5000::bigint, 5000::bigint)$$,
  'breakdown totals cover items plus current dues, with the server minimum'
);
select results_eq(
  $$select count(*)::integer,
      count(*) filter (where c ->> 'scope' = 'next_due')::integer
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'Item Visa'),
      date '2026-04-01') b,
    jsonb_array_elements(b -> 'components') c$$,
  $$values (5, 0)$$,
  'five current components and no future installments leak into the list'
);
select results_eq(
  $$select (b ->> 'additional_balance_minor')::bigint
      = (b ->> 'outstanding_minor')::bigint
        - (b ->> 'remaining_minor')::bigint
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'Item Visa'),
      date '2026-04-01') b$$,
  $$values (true)$$,
  'non-current outstanding is explicit additional balance, never fake dues'
);

-- ---------------------------------------------------------------------------
-- Partial statement item + minimum remaining after a qualifying payment
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      3000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object(
        'type', 'statement_item',
        'id', (select statement_item_id
          from app_finance.credit_card_statement_item_statuses
          where title = 'OpenAI'),
        'amount_minor', 3000)),
      null, '00000000-0000-0000-0000-000000047901')$$,
  'a partial allocation to a single statement item is accepted'
);
select results_eq(
  $$select paid_minor, remaining_minor, payment_status
    from app_finance.credit_card_statement_item_statuses
    where title = 'OpenAI'$$,
  $$values (3000::bigint, 67000::bigint, 'partially_paid'::text)$$,
  'the item reports paid 3000 / remaining 67000, partially paid'
);
select results_eq(
  $$select minimum_paid_minor, minimum_remaining_minor
    from app_finance.credit_card_statement_summaries
    where account_id =
      (select id from app_finance.accounts where name = 'Item Visa')$$,
  $$values (3000::bigint, 2000::bigint)$$,
  'a qualifying payment reduces the remaining minimum, not restart it'
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_statement_allocations
    where payment_transaction_id =
      '00000000-0000-0000-0000-000000047901'$$,
  $$values (3000::bigint)$$,
  'the compatibility cycle aggregate equals the item allocation sum'
);

-- ---------------------------------------------------------------------------
-- Selected components only: one due + one item, nothing else moves
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      130000, date '2026-04-01',
      jsonb_build_array(
        jsonb_build_object('type', 'installment_due',
          'id', (select id from app_finance.installment_dues
            where plan_id = '00000000-0000-0000-0000-000000047e01'
              and sequence_number = 1),
          'amount_minor', 100000),
        jsonb_build_object('type', 'statement_item',
          'id', (select statement_item_id
            from app_finance.credit_card_statement_item_statuses
            where title = 'Netflix'),
          'amount_minor', 30000)),
      null, '00000000-0000-0000-0000-000000047902')$$,
  'paying exactly the selected due and item succeeds'
);
select results_eq(
  $$select sequence_number, remaining_minor, due_status
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-000000047e01'
    order by sequence_number$$,
  $$values (1, 0::bigint, 'paid'::text),
    (2, 100000::bigint, 'overdue'::text),
    (3, 100000::bigint, 'overdue'::text)$$,
  'only the selected due is settled; the others are untouched'
);
select results_eq(
  $$select title, payment_status
    from app_finance.credit_card_statement_item_statuses
    order by title$$,
  $$values ('Netflix'::text, 'paid'::text),
    ('OpenAI'::text, 'partially_paid'::text)$$,
  'the selected item is paid; the unselected item keeps its state'
);
select results_eq(
  $$select component_type, title, amount_minor
    from app_finance.facility_payment_allocations
    where payment_transaction_id = '00000000-0000-0000-0000-000000047902'
    order by component_type, title$$,
  $$values ('installment_due'::text, 'Samsung'::text, 100000::bigint),
    ('statement_item'::text, 'Netflix'::text, 30000::bigint)$$,
  'payment detail shows the exact persisted Applied-to list'
);

-- Idempotency: identical retry returns the same payment, conflicting reuse
-- is rejected, and nothing is duplicated.
select results_eq(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      130000, date '2026-04-01',
      jsonb_build_array(
        jsonb_build_object('type', 'installment_due',
          'id', (select id from app_finance.installment_dues
            where plan_id = '00000000-0000-0000-0000-000000047e01'
              and sequence_number = 1),
          'amount_minor', 100000),
        jsonb_build_object('type', 'statement_item',
          'id', (select statement_item_id
            from app_finance.credit_card_statement_item_statuses
            where title = 'Netflix'),
          'amount_minor', 30000)),
      null, '00000000-0000-0000-0000-000000047902')$$,
  $$values ('00000000-0000-0000-0000-000000047902'::uuid)$$,
  'an identical retry with the same payment id is a safe no-op'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.installment_payment_allocations
    where payment_transaction_id =
      '00000000-0000-0000-0000-000000047902'$$,
  $$values (1)$$,
  'the retry does not duplicate allocations'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      130000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'facility_balance',
        'id', (select id from app_finance.accounts
          where name = 'Item Visa'),
        'amount_minor', 130000)),
      null, '00000000-0000-0000-0000-000000047902')$$,
  'P0001', null,
  'the same payment id with different allocations is a typed conflict'
);

-- ---------------------------------------------------------------------------
-- Partial installment allocation
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      40000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000047e01'
            and sequence_number = 2),
        'amount_minor', 40000)),
      null, '00000000-0000-0000-0000-000000047903')$$,
  'a partial installment allocation is accepted'
);
select results_eq(
  $$select paid_minor, remaining_minor, due_status
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-000000047e01'
      and sequence_number = 2$$,
  $$values (40000::bigint, 60000::bigint, 'overdue'::text)$$,
  'the due keeps canonical status math: paid 40000, remaining 60000'
);

-- ---------------------------------------------------------------------------
-- The Home due-breakdown DTO carries the same item-level paid state
-- ---------------------------------------------------------------------------

select results_eq(
  $$select item ->> 'title', item ->> 'payment_status',
      (item ->> 'paid_minor')::bigint, (item ->> 'remaining_minor')::bigint
    from app_finance.home_current_month_obligations(date '2026-04-01') o,
      jsonb_array_elements(o.details -> 'items') item
    where o.obligation_kind = 'card_statement'
    order by item ->> 'title'$$,
  $$values ('Netflix'::text, 'paid'::text, 30000::bigint, 0::bigint),
    ('OpenAI'::text, 'partially_paid'::text, 3000::bigint, 67000::bigint)$$,
  'Home statement items expose exact paid, remaining, and status'
);
select results_eq(
  $$select inst ->> 'payment_status', (inst ->> 'remaining_minor')::bigint
    from app_finance.home_current_month_obligations(date '2026-04-01') o,
      jsonb_array_elements(o.details -> 'installments') inst
    where o.obligation_kind = 'card_statement'$$,
  $$values ('unpaid'::text, 100000::bigint)$$,
  'Home statement installments expose their payment status'
);

-- ---------------------------------------------------------------------------
-- Validation rejects
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', (select statement_item_id
          from app_finance.credit_card_statement_item_statuses
          where title = 'OpenAI'),
        'amount_minor', 0)),
      null, null)$$,
  'P0001', null, 'a zero allocation amount is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      999999, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', (select statement_item_id
          from app_finance.credit_card_statement_item_statuses
          where title = 'OpenAI'),
        'amount_minor', 999999)),
      null, null)$$,
  'P0001', null, 'allocating more than the item remaining is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      2000, date '2026-04-01',
      jsonb_build_array(
        jsonb_build_object('type', 'statement_item',
          'id', (select statement_item_id
            from app_finance.credit_card_statement_item_statuses
            where title = 'OpenAI'),
          'amount_minor', 1000),
        jsonb_build_object('type', 'statement_item',
          'id', (select statement_item_id
            from app_finance.credit_card_statement_item_statuses
            where title = 'OpenAI'),
          'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'duplicate allocation targets are rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000047e02'
            and sequence_number = 1),
        'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'a due belonging to another facility is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      2000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', (select statement_item_id
          from app_finance.credit_card_statement_item_statuses
          where title = 'OpenAI'),
        'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'allocation totals must equal the payment amount'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', (select statement_item_id
          from app_finance.credit_card_statement_item_statuses
          where title = 'Netflix'),
        'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'an already paid item cannot be allocated again'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'mystery',
        'id', '00000000-0000-0000-0000-000000047f01',
        'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'unknown allocation types are rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01', '{"due_id": "nope"}'::jsonb, null, null)$$,
  'P0001', null, 'a non-array allocation payload is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01', '[]'::jsonb, null, null)$$,
  'P0001', null, 'an empty allocation payload is rejected'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', 'not-a-uuid', 'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'a malformed allocation entry is rejected'
);

-- Stale-state overpay: once remaining is 67000, an allocation of 67001 must
-- fail. Concurrency serializes on the facility account row lock, so a second
-- device replays exactly this validation against fresh remaining amounts.
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      67001, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', (select statement_item_id
          from app_finance.credit_card_statement_item_statuses
          where title = 'OpenAI'),
        'amount_minor', 67001)),
      null, null)$$,
  'P0001', null, 'a stale over-allocation is rejected after revalidation'
);

-- ---------------------------------------------------------------------------
-- BNPL: dues only, no statement rows, no invented minimum, no future dues
-- ---------------------------------------------------------------------------

select results_eq(
  $$select (b ->> 'total_due_minor')::bigint,
      b ->> 'minimum_due_minor',
      count(c) filter (where c ->> 'component_type' = 'statement_item')
        ::integer,
      count(c) filter (where (c ->> 'occurred_on')::date > date '2026-04-01')
        ::integer
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'Item Valu'),
      date '2026-04-01') b
    left join lateral jsonb_array_elements(b -> 'components') c on true
    group by b$$,
  $$values (100000::bigint, null::text, 0, 0)$$,
  'BNPL exposes only current dues: no statement rows, no fake minimum'
);
select results_eq(
  $$select count(*)::integer,
      min(c ->> 'scope')
    from app_finance.facility_due_breakdown(
      (select id from app_finance.accounts where name = 'Item Valu'),
      date '2026-02-01') b,
    jsonb_array_elements(b -> 'components') c$$,
  $$values (1, 'next_due'::text)$$,
  'with nothing current, only the next due date group is exposed as next'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Valu'),
      '00000000-0000-0000-0000-000000047a01',
      50000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000047e02'
            and sequence_number = 4),
        'amount_minor', 50000)),
      null, null)$$,
  'P0001', null, 'a hidden future due cannot be paid by the current-due flow'
);
select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Valu'),
      '00000000-0000-0000-0000-000000047a01',
      20000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000047e02'
            and sequence_number = 1),
        'amount_minor', 20000)),
      null, '00000000-0000-0000-0000-000000047904')$$,
  'BNPL partial due allocation persists through the same flow'
);
select results_eq(
  $$select paid_minor, remaining_minor
    from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-000000047e02'
      and sequence_number = 1$$,
  $$values (20000::bigint, 30000::bigint)$$,
  'the BNPL due keeps exact partial state'
);
select results_eq(
  $$select inst ->> 'payment_status', (inst ->> 'paid_minor')::bigint
    from app_finance.home_current_month_obligations(date '2026-04-01') o,
      jsonb_array_elements(o.details -> 'installments') inst
    where o.obligation_kind = 'installment_due'
      and (inst ->> 'sequence_number')::integer = 1$$,
  $$values ('partially_paid'::text, 20000::bigint)$$,
  'the Home BNPL due entry carries its partial paid state'
);

-- A due settled in full stays visible on Home as 'paid' while its due date
-- has not passed, instead of vanishing the moment it is paid.
select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Valu'),
      '00000000-0000-0000-0000-000000047a01',
      50000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'installment_due',
        'id', (select id from app_finance.installment_dues
          where plan_id = '00000000-0000-0000-0000-000000047e02'
            and sequence_number = 2),
        'amount_minor', 50000)),
      null, '00000000-0000-0000-0000-000000047907')$$,
  'settling a whole due on its due date succeeds'
);
select results_eq(
  $$select o.obligation_status, o.remaining_minor,
      inst ->> 'payment_status'
    from app_finance.home_current_month_obligations(date '2026-04-01') o,
      jsonb_array_elements(o.details -> 'installments') inst
    where o.obligation_id = (select id from app_finance.installment_dues
      where plan_id = '00000000-0000-0000-0000-000000047e02'
        and sequence_number = 2)$$,
  $$values ('paid'::text, 0::bigint, 'paid'::text)$$,
  'the settled due stays on Home as paid with zero remaining'
);

-- ---------------------------------------------------------------------------
-- Explicit facility balance component
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      10000, date '2026-04-01',
      jsonb_build_array(
        jsonb_build_object('type', 'statement_item',
          'id', (select statement_item_id
            from app_finance.credit_card_statement_item_statuses
            where title = 'OpenAI'),
          'amount_minor', 4000),
        jsonb_build_object('type', 'facility_balance',
          'id', (select id from app_finance.accounts
            where name = 'Item Visa'),
          'amount_minor', 6000)),
      null, '00000000-0000-0000-0000-000000047905')$$,
  'an explicit facility-balance component absorbs non-due amounts'
);
select results_eq(
  $$select coalesce(sum(amount_minor), 0)::bigint
    from app_finance.facility_payment_allocations
    where payment_transaction_id =
      '00000000-0000-0000-0000-000000047905'$$,
  $$values (4000::bigint)$$,
  'the balance component stays derived: only real targets store rows'
);

-- ---------------------------------------------------------------------------
-- Reversal restores item, due, and aggregate state
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.reverse_facility_payment(
      '00000000-0000-0000-0000-000000047902')$$,
  'reversing the selected payment succeeds'
);
select results_eq(
  $$select
      (select count(*)::integer
        from app_finance.credit_card_statement_item_allocations
        where payment_transaction_id =
          '00000000-0000-0000-0000-000000047902'),
      (select count(*)::integer
        from app_finance.installment_payment_allocations
        where payment_transaction_id =
          '00000000-0000-0000-0000-000000047902'),
      (select count(*)::integer
        from app_finance.credit_card_statement_allocations
        where payment_transaction_id =
          '00000000-0000-0000-0000-000000047902')$$,
  $$values (0, 0, 0)$$,
  'reversal removes item, installment, and compatibility allocations'
);
select results_eq(
  $$select payment_status
    from app_finance.credit_card_statement_item_statuses
    where title = 'Netflix'$$,
  $$values ('unpaid'::text)$$,
  'the crossed-out item returns to unpaid after reversal'
);
select results_eq(
  $$select remaining_minor from app_finance.installment_due_statuses
    where plan_id = '00000000-0000-0000-0000-000000047e01'
      and sequence_number = 1$$,
  $$values (100000::bigint)$$,
  'the settled due is owed again after reversal'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where facility_reversal_of_id =
      '00000000-0000-0000-0000-000000047902'$$,
  $$values (1)$$,
  'exactly one reversal transaction exists'
);

-- ---------------------------------------------------------------------------
-- Legacy v1 waterfall keeps item detail and aggregates in lockstep
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.pay_credit_facility(
      (select id from app_finance.accounts where name = 'Item Visa'),
      '00000000-0000-0000-0000-000000047a01',
      180000, date '2026-04-01', null, null,
      '00000000-0000-0000-0000-000000047906')$$,
  'the legacy waterfall payment still works'
);
select results_eq(
  $$select sa.amount_minor,
      (select sum(ia.amount_minor)::bigint
        from app_finance.credit_card_statement_item_allocations ia
        join app_finance.credit_card_statement_items si
          on si.id = ia.statement_item_id
        where ia.payment_transaction_id = sa.payment_transaction_id
          and si.cycle_id = sa.cycle_id),
      (select min(ia.allocation_origin)
        from app_finance.credit_card_statement_item_allocations ia
        where ia.payment_transaction_id = sa.payment_transaction_id)
    from app_finance.credit_card_statement_allocations sa
    where sa.payment_transaction_id =
      '00000000-0000-0000-0000-000000047906'$$,
  $$values (20000::bigint, 20000::bigint, 'system'::text)$$,
  'waterfall cycle aggregates equal their inferred item detail exactly'
);
select results_eq(
  $$select sum(sa.amount_minor)::bigint = sum(ia.item_sum)::bigint
    from app_finance.credit_card_statement_allocations sa
    join lateral (
      select coalesce(sum(x.amount_minor), 0) as item_sum
      from app_finance.credit_card_statement_item_allocations x
      join app_finance.credit_card_statement_items si
        on si.id = x.statement_item_id
      where x.payment_transaction_id = sa.payment_transaction_id
        and si.cycle_id = sa.cycle_id
    ) ia on true
    where sa.user_id = '00000000-0000-0000-0000-000000000047'$$,
  $$values (true)$$,
  'every cycle aggregate matches its item-level sum (no double counting)'
);

-- ---------------------------------------------------------------------------
-- Write protection and isolation
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into app_finance.credit_card_statement_item_allocations (
      user_id, payment_transaction_id, statement_item_id, amount_minor
    ) values (
      '00000000-0000-0000-0000-000000000047',
      '00000000-0000-0000-0000-000000047901',
      (select statement_item_id
        from app_finance.credit_card_statement_item_statuses
        where title = 'OpenAI'),
      1)$$,
  'P0001', null, 'direct client writes to item allocations stay locked'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000048","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer
    from app_finance.credit_card_statement_item_allocations$$,
  $$values (0)$$,
  'another user sees no allocation rows'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.facility_payment_allocations$$,
  $$values (0)$$,
  'another user sees no payment allocation detail'
);
select throws_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select a.id from app_finance.accounts a
        where a.name = 'Item Visa'
          and a.user_id = '00000000-0000-0000-0000-000000000047'),
      '00000000-0000-0000-0000-000000047a01',
      1000, date '2026-04-01',
      jsonb_build_array(jsonb_build_object('type', 'statement_item',
        'id', '00000000-0000-0000-0000-000000047f01',
        'amount_minor', 1000)),
      null, null)$$,
  'P0001', null, 'another user cannot pay against a foreign facility'
);

select * from finish();
rollback;
