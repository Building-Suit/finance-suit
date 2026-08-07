begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000079',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'tenor-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Tenor Owner"}', now(), now()
);

select has_table('app_finance', 'installment_tenor_rates',
  'tenor rates table exists');
select has_function('app_finance', 'resolve_tenor_rate',
  'resolve_tenor_rate exists');
select has_function('app_finance', 'settle_installment_plan_early',
  'settle_installment_plan_early exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000079","role":"authenticated"}';

select app_finance.save_credit_facility(
  'Tenor Card', 'bnpl', 'EGP', 5000000, 5::smallint, null, null, 3::smallint,
  null, null);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a501',
  '00000000-0000-0000-0000-000000000079',
  'Wallet', 'cash', 'EGP', 5000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c501',
  '00000000-0000-0000-0000-000000000079',
  'Financed Purchases', 'expense'
);

-- ---------------------------------------------------------------------------
-- Tenor tiers: 3-5, 6-11, 12-23 months; overlap rejected
-- ---------------------------------------------------------------------------

insert into app_finance.installment_tenor_rates (
  user_id, account_id, from_months, to_months, rate_basis_points,
  interest_method, rate_period
) values (
  '00000000-0000-0000-0000-000000000079',
  (select id from app_finance.accounts where name = 'Tenor Card'),
  3, 5, 100, 'flat', 'monthly'
), (
  '00000000-0000-0000-0000-000000000079',
  (select id from app_finance.accounts where name = 'Tenor Card'),
  6, 11, 150, 'flat', 'monthly'
), (
  '00000000-0000-0000-0000-000000000079',
  (select id from app_finance.accounts where name = 'Tenor Card'),
  12, 23, 200, 'reducing', 'monthly'
);

select throws_ok(
  $$insert into app_finance.installment_tenor_rates (
      user_id, account_id, from_months, to_months, rate_basis_points
    ) values (
      '00000000-0000-0000-0000-000000000079',
      (select id from app_finance.accounts where name = 'Tenor Card'),
      5, 7, 120
    )$$,
  'P0001', null, 'an overlapping tenor range is rejected'
);
select results_eq(
  $$select rate_basis_points, interest_method::text
    from app_finance.resolve_tenor_rate(
      (select id from app_finance.accounts where name = 'Tenor Card'),
      '00000000-0000-0000-0000-000000000079', 8)$$,
  $$values (150::integer, 'flat'::text)$$,
  'an 8-month plan resolves the 6-11 tier'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.resolve_tenor_rate(
      (select id from app_finance.accounts where name = 'Tenor Card'),
      '00000000-0000-0000-0000-000000000079', 30)$$,
  $$values (0)$$,
  'an uncovered tenor gap resolves to nothing (never fabricated)'
);

-- ---------------------------------------------------------------------------
-- A plan using the card default resolves and snapshots the tier's rate
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'Tenor Card'),
      'Uncovered tenor', '00000000-0000-0000-0000-00000000c501',
      date '2026-05-01', 120000, 30, date '2026-06-01', 0, null, null, null,
      null, null, 'card_tenor_default')$$,
  'P0001', null, 'a plan with no covering tenor tier is rejected'
);
select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from app_finance.accounts where name = 'Tenor Card'),
      'Laptop', '00000000-0000-0000-0000-00000000c501',
      date '2026-05-01', 1200000, 12, date '2026-06-01', 0, null, null,
      null, null, null, 'card_tenor_default')$$,
  'a 12-month plan resolves the reducing-balance 12-23 tier'
);
select results_eq(
  $$select interest_rate_basis_points, interest_method::text,
      pricing_method::text
    from app_finance.installment_plan_summaries where title = 'Laptop'$$,
  $$values (200::integer, 'reducing'::text, 'interest_rate'::text)$$,
  'the plan snapshots the resolved tier rate and method at creation'
);

-- Changing the tenor table afterward never touches the already-created
-- plan (rules never rewrite booked history).
update app_finance.installment_tenor_rates
  set rate_basis_points = 999
  where from_months = 12;
select results_eq(
  $$select interest_rate_basis_points
    from app_finance.installment_plan_summaries where title = 'Laptop'$$,
  $$values (200::integer)$$,
  'editing the tenor table afterward does not change the existing plan'
);

-- ---------------------------------------------------------------------------
-- Early settlement: percentage of remaining principal, booked once
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Tenor Card'),
  'Early Settlement Fee', 'other', '00000000-0000-0000-0000-00000000c501',
  'configured', 'early_settlement', date '2026-01-01', 'percentage', null,
  200, 'remaining_principal', null, null, null, 'per_transaction', null,
  null, null, null, 100, null, null
);

-- Pay the first due normally, then settle the remainder early.
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Tenor Card'),
  '00000000-0000-0000-0000-00000000a501', 100000, date '2026-06-01'
);
select lives_ok(
  $$select app_finance.settle_installment_plan_early(
      (select id from app_finance.installment_plans where title = 'Laptop'),
      '00000000-0000-0000-0000-00000000a501', date '2026-07-01', null,
      null)$$,
  'settling the plan early succeeds'
);
select results_eq(
  $$select status::text, remaining_minor
    from app_finance.installment_plan_summaries where title = 'Laptop'$$,
  $$values ('completed'::text, 0::bigint)$$,
  'the plan is fully settled with nothing remaining'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Early Settlement Fee'$$,
  $$values (1)$$,
  'exactly one early-settlement fee was booked'
);

-- Settling an already-fully-paid plan a second time is rejected outright,
-- so an early-settlement fee can never be booked twice for one plan.
select throws_ok(
  $$select app_finance.settle_installment_plan_early(
      (select id from app_finance.installment_plans where title = 'Laptop'),
      '00000000-0000-0000-0000-00000000a501', date '2026-07-02', null,
      null)$$,
  'P0001', null, 'a plan with nothing left owed cannot be settled again'
);

-- ---------------------------------------------------------------------------
-- A plan with no early-settlement rule configured pays off with no fee
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Plain BNPL', 'bnpl', 'EGP', 2000000, 5::smallint, null, null, 3::smallint,
  null, null);
select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Plain BNPL'),
  'Phone', '00000000-0000-0000-0000-00000000c501',
  date '2026-05-01', 600000, 6, date '2026-06-01', 0, null, null, null,
  null, null, 'manual_fees'
);
select lives_ok(
  $$select app_finance.settle_installment_plan_early(
      (select id from app_finance.installment_plans where title = 'Phone'),
      '00000000-0000-0000-0000-00000000a501', date '2026-06-15', null,
      null)$$,
  'settling a plan with no early-settlement rule succeeds with no fee'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Early Settlement Fee'$$,
  $$values (1)$$,
  'no fee is fabricated on a card with no early-settlement rule configured'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007a',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'tenor-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Tenor Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007a","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.installment_tenor_rates$$,
  $$values (0)$$,
  'another user cannot see the tenor tiers at all'
);

select * from finish();
rollback;
