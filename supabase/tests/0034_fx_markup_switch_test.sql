begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007a',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fxsw-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FXSW Owner"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007a","role":"authenticated"}';

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c601',
  '00000000-0000-0000-0000-00000000007a',
  'Card Spending', 'expense'
);

-- ---------------------------------------------------------------------------
-- A card with a flat 3% FX markup rate configured
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'FX Switch Card', 'credit_card', 'EGP', 5000000, 25::smallint,
  28::smallint, '6011', 3::smallint, null, null,
  'active', 'fixed', 5000, null, null, 300);

select results_eq(
  $$select fx_markup_basis_points from app_finance.credit_facility_settings
    where account_id =
      (select id from app_finance.accounts where name = 'FX Switch Card')$$,
  $$values (300)$$,
  'the flat 3% markup rate is stored on the facility'
);

-- Foreign-currency charge: 170.00 at 3% adds a 5.10 markup, matching the
-- CIB Gold statement's own Netflix fee exactly.
select lives_ok(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'FX Switch Card'),
      'Netflix', '00000000-0000-0000-0000-00000000c601',
      date '2026-07-12', 17000, null, null, true)$$,
  'a foreign-currency charge on a card with a configured rate is accepted'
);
select results_eq(
  $$select amount_minor from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'
      and source_account_id =
        (select id from app_finance.accounts where name = 'FX Switch Card')$$,
  $$values (510::bigint)$$,
  '3% of the EGP 170.00 charge is exactly the EGP 5.10 markup'
);
select results_eq(
  $$select i.cycle_id = j.cycle_id
    from app_finance.financial_transactions p
    join app_finance.credit_card_statement_items i on i.transaction_id = p.id
    join app_finance.financial_transactions m
      on m.title = 'Foreign Exchange Markup'
    join app_finance.credit_card_statement_items j on j.transaction_id = m.id
    where p.title = 'Netflix'$$,
  $$values (true)$$,
  'the markup lands in the same statement cycle as the purchase it followed'
);

-- A domestic charge on the same card never adds a markup.
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'FX Switch Card'),
  'Local Groceries', '00000000-0000-0000-0000-00000000c601',
  date '2026-07-13', 20000, null, null, false
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (1)$$,
  'leaving the switch off never adds a markup'
);

-- ---------------------------------------------------------------------------
-- An unconfigured card (no rate) ignores the switch entirely
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Plain Card', 'credit_card', 'EGP', 3000000, 25::smallint,
  28::smallint, '5500', 3::smallint, null, null,
  'active', 'fixed', 5000, null);

select lives_ok(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'Plain Card'),
      'Overseas Coffee', '00000000-0000-0000-0000-00000000c601',
      date '2026-07-14', 30000, null, null, true)$$,
  'a foreign-currency charge still posts on a card with no configured rate'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where source_account_id =
      (select id from app_finance.accounts where name = 'Plain Card')
      and title = 'Foreign Exchange Markup'$$,
  $$values (0)$$,
  'no markup is fabricated when the card has no configured rate'
);

-- ---------------------------------------------------------------------------
-- BNPL never charges the markup, even if a rate happens to be configured
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'BNPL Plan', 'bnpl', 'EGP', 2000000, 10::smallint,
  null, null, 3::smallint, null, null,
  'active', 'fixed', 5000, null, null, 300);

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'BNPL Plan'),
  'Overseas Furniture', '00000000-0000-0000-0000-00000000c601',
  date '2026-07-15', 40000, null, null, true
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where source_account_id =
      (select id from app_finance.accounts where name = 'BNPL Plan')
      and title = 'Foreign Exchange Markup'$$,
  $$values (0)$$,
  'BNPL never charges the flat markup even with a rate configured'
);

-- ---------------------------------------------------------------------------
-- The credit-limit check accounts for the markup, not just the purchase
-- ---------------------------------------------------------------------------

-- 17,000 alone fits under the limit; 17,000 + its 510 markup does not —
-- proving the check accounts for the markup before either insert runs.
select app_finance.save_credit_facility(
  'Tight Limit Card', 'credit_card', 'EGP', 17509, 25::smallint,
  28::smallint, '7777', 3::smallint, null, null,
  'active', 'fixed', 5000, null, null, 300);

select throws_ok(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'Tight Limit Card'),
      'Just Over', '00000000-0000-0000-0000-00000000c601',
      date '2026-07-16', 17000, null, null, true)$$,
  'P0001',
  'insufficient_credit: purchase exceeds available credit',
  'a purchase that only fits without its markup is still rejected'
);

-- ---------------------------------------------------------------------------
-- Idempotent retry: resubmitting the same charge id never double-books
-- the purchase or its markup.
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'FX Switch Card'),
  'Repeatable Purchase', '00000000-0000-0000-0000-00000000c601',
  date '2026-07-17', 10000, null, '00000000-0000-0000-0000-00000000fd02', true
);
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'FX Switch Card'),
  'Repeatable Purchase', '00000000-0000-0000-0000-00000000c601',
  date '2026-07-17', 10000, null, '00000000-0000-0000-0000-00000000fd02', true
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where source_account_id =
      (select id from app_finance.accounts where name = 'FX Switch Card')
      and title = 'Foreign Exchange Markup'
      and amount_minor = 300$$,
  $$values (1)$$,
  'retrying the same charge id never generates a second markup'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007b',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fxsw-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FXSW Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007b","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (0)$$,
  'another user cannot see any of these generated markup charges'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_facility_settings
    where fx_markup_basis_points = 300$$,
  $$values (0)$$,
  'another user cannot see any of these configured markup rates'
);

select * from finish();
rollback;
