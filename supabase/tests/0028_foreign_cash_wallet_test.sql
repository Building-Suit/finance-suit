begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000075',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fcw-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FCW Owner"}', now(), now()
);

select has_function('app_finance', 'resolve_trigger_rule',
  'resolve_trigger_rule exists');
select has_function('app_finance', 'calculate_rule_amount',
  'calculate_rule_amount exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000075","role":"authenticated"}';

select app_finance.save_credit_facility(
  'FX Card', 'credit_card', 'EGP', 5000000, 10::smallint,
  25::smallint, '4400', 3::smallint, null, null,
  'active', 'fixed', 5000, null);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c301',
  '00000000-0000-0000-0000-000000000075',
  'Card Spending', 'expense'
);

-- ---------------------------------------------------------------------------
-- Foreign markup: 3% of the converted (card-currency) amount, fixture from
-- the product spec (converted EGP 5,000 -> EGP 150 fee).
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Foreign Markup', 'foreign_transaction',
  '00000000-0000-0000-0000-00000000c301', 'configured', 'foreign_transaction',
  date '2026-05-01', 'percentage', null, 300, 'transaction_amount', null,
  null, null, 'per_transaction', 'currency_differs', null, null, null, 100,
  null, null
);

select lives_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'FX Card'),
      'Hotel in Paris', '00000000-0000-0000-0000-00000000c301',
      date '2026-05-10', 500000, null, null, 'purchase', true, true,
      10000, 'USD', 50.00)$$,
  'a foreign-currency purchase is accepted'
);
select results_eq(
  $$select amount_minor, calculation_snapshot ->> 'is_foreign_currency'
    from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Markup'$$,
  $$values (15000::bigint, 'true'::text)$$,
  '3% of the converted EGP 5,000 charge is exactly EGP 150'
);
select results_eq(
  $$select f.transaction_id = p.id
    from app_finance.credit_card_fee_charges f
    join app_finance.credit_card_fee_rules r on r.id = f.rule_id
    cross join lateral (
      select t.id from app_finance.financial_transactions t
      where t.title = 'Hotel in Paris'
    ) p
    where r.name = 'Foreign Markup'$$,
  $$values (false)$$,
  'the markup posts as its own charge, separate from the purchase expense'
);

-- A same-currency, domestic-merchant purchase never triggers the rule
-- just because it happens on the same card.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Local Groceries', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-11', 20000, null, null, 'purchase', false, false,
  null, null, null
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Markup'$$,
  $$values (1)$$,
  'a domestic purchase in the same currency never triggers the markup'
);

-- ---------------------------------------------------------------------------
-- Domestic cash advance: percentage with a minimum
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Domestic Cash Fee', 'cash_advance', '00000000-0000-0000-0000-00000000c301',
  'configured', 'domestic_cash_advance', date '2026-05-01', 'percentage',
  null, 200, 'transaction_amount', 5000, null, null, 'per_transaction',
  null, null, null, null, 100, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'ATM Withdrawal', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-12', 100000, null, null, 'domestic_cash_advance', false,
  false, null, null, null
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Domestic Cash Fee'$$,
  $$values (5000::bigint)$$,
  '2% of a 100,000 withdrawal (2,000) is clamped up to the 5,000 minimum'
);

-- A small domestic withdrawal (2% clears the minimum on its own).
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'ATM Withdrawal 2', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-13', 1000000, null, null, 'domestic_cash_advance', false,
  false, null, null, null
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Domestic Cash Fee'$$,
  $$values (2)$$,
  'a second withdrawal generates its own separate cash-advance fee'
);

-- ---------------------------------------------------------------------------
-- Domestic and international cash advances stay independent
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'FX Card'),
  'International Cash Fee', 'international_cash_advance',
  '00000000-0000-0000-0000-00000000c301', 'configured',
  'international_cash_advance', date '2026-05-01', 'fixed', 10000, null,
  null, null, null, null, 'per_transaction', null, null, null, null, 100,
  null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Overseas ATM', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-14', 300000, null, null, 'international_cash_advance',
  true, true, null, null, null
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'International Cash Fee'$$,
  $$values (10000::bigint)$$,
  'the fixed international cash-advance fee applies'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Domestic Cash Fee'$$,
  $$values (2)$$,
  'the international withdrawal never touched the domestic cash-fee rule'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Markup'$$,
  $$values (1)$$,
  'cash advances never trigger the ordinary foreign-purchase markup rule'
);

-- ---------------------------------------------------------------------------
-- Wallet load fee: percentage with a maximum
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Wallet Load Fee', 'wallet_fee', '00000000-0000-0000-0000-00000000c301',
  'configured', 'wallet_transaction', date '2026-05-01', 'percentage', null,
  150, 'transaction_amount', null, 3000, null, 'per_transaction', null,
  null, null, null, 100, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Wallet Top-up', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-15', 500000, null, null, 'wallet_load', false, false,
  null, null, null
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Wallet Load Fee'$$,
  $$values (3000::bigint)$$,
  '1.5% of 500,000 (7,500) is clamped down to the 3,000 maximum'
);

-- A wallet load is never mistaken for an ordinary purchase or a cash
-- advance.
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name in ('Domestic Cash Fee', 'International Cash Fee',
      'Foreign Markup')
      and c.trigger_transaction_id = (
        select id from app_finance.financial_transactions
        where title = 'Wallet Top-up'
      )$$,
  $$values (0)$$,
  'the wallet load did not also trigger a cash-advance or FX rule'
);

-- ---------------------------------------------------------------------------
-- Unconfigured rule: charge still posts, no fee fabricated
-- ---------------------------------------------------------------------------

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c302',
  '00000000-0000-0000-0000-000000000075',
  'Second Category', 'expense'
);
select app_finance.save_credit_facility(
  'Plain Card', 'credit_card', 'EGP', 2000000, 10::smallint,
  25::smallint, '5500', 3::smallint, null, null,
  'active', 'fixed', 5000, null);
select lives_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'Plain Card'),
      'Overseas Coffee', '00000000-0000-0000-0000-00000000c302',
      date '2026-05-10', 30000, null, null, 'purchase', true, false,
      null, null, null)$$,
  'a foreign purchase still posts even with no foreign-markup rule configured'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.financial_transactions t on t.id = c.transaction_id
    where t.source_account_id =
      (select id from app_finance.accounts where name = 'Plain Card')$$,
  $$values (0)$$,
  'no fee is fabricated when the foreign-markup rule was never configured'
);

-- ---------------------------------------------------------------------------
-- Idempotent retry: resubmitting the same charge id never double-books
-- the purchase or its triggered fee.
-- ---------------------------------------------------------------------------

select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Repeatable Purchase', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-16', 400000, null, '00000000-0000-0000-0000-00000000fd01',
  'purchase', true, false, null, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Card'),
  'Repeatable Purchase', '00000000-0000-0000-0000-00000000c301',
  date '2026-05-16', 400000, null, '00000000-0000-0000-0000-00000000fd01',
  'purchase', true, false, null, null, null
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Markup'
      and c.trigger_transaction_id =
        '00000000-0000-0000-0000-00000000fd01'$$,
  $$values (1)$$,
  'retrying the same charge id never generates a second markup fee'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000076',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fcw-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FCW Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000076","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges
    where rule_id in (
      select id from app_finance.credit_card_fee_rules
      where name in ('Foreign Markup', 'Domestic Cash Fee',
        'International Cash Fee', 'Wallet Load Fee')
    )$$,
  $$values (0)$$,
  'another user cannot see any of these generated charges'
);

select * from finish();
rollback;
