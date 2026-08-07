begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000078',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fxdb-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FXDB Owner"}', now(), now()
);

select has_function('app_finance', 'highest_daily_balance_minor',
  'highest_daily_balance_minor exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000078","role":"authenticated"}';

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c501',
  '00000000-0000-0000-0000-000000000078',
  'Card Spending', 'expense'
);

-- ---------------------------------------------------------------------------
-- Foreign markup that fires only for a foreign merchant billing in the
-- card's own currency (the CIB pattern: a genuinely foreign-currency
-- purchase carries the markup inside the exchange rate instead).
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'FX Home Card', 'credit_card', 'EGP', 5000000, 10::smallint,
  25::smallint, '4411', 3::smallint, null, null,
  'active', 'fixed', 5000, null);

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'FX Home Card'),
  'Foreign Exchange Fee', 'foreign_transaction',
  '00000000-0000-0000-0000-00000000c501', 'configured',
  'foreign_transaction', date '2026-06-01', 'percentage', null, 300,
  'transaction_amount', null, null, null, 'per_transaction',
  'foreign_merchant_home_currency', null, null, null, 100, null, null
);

-- Foreign merchant billed in EGP: the one case the markup applies to.
select lives_ok(
  $$select app_finance.charge_credit_card(
      (select id from app_finance.accounts where name = 'FX Home Card'),
      'Netflix billed in EGP', '00000000-0000-0000-0000-00000000c501',
      date '2026-07-12', 17000, null, null, 'purchase', false, true,
      null, null, null)$$,
  'a foreign merchant billing in the home currency is accepted'
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Exchange Fee'$$,
  $$values (510::bigint)$$,
  '3% of the EGP 170 charge is exactly EGP 5.10'
);

-- A genuinely foreign-currency purchase (converted by the bank) does NOT
-- add the markup under this condition.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Home Card'),
  'Google Play billed in USD', '00000000-0000-0000-0000-00000000c501',
  date '2026-07-16', 130166, null, null, 'purchase', true, true,
  2500, 'USD', 52.0664
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Exchange Fee'$$,
  $$values (1)$$,
  'a foreign-currency purchase never triggers the home-currency markup'
);

-- A domestic purchase does not trigger it either.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'FX Home Card'),
  'Local Groceries', '00000000-0000-0000-0000-00000000c501',
  date '2026-07-18', 20000, null, null, 'purchase', false, false,
  null, null, null
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Foreign Exchange Fee'$$,
  $$values (1)$$,
  'a domestic purchase never triggers the foreign markup'
);

-- ---------------------------------------------------------------------------
-- Highest daily balance over a lookback window: build a balance that
-- peaks mid-quarter and is partly paid down before the charge date, so
-- the peak is provably different from the current outstanding.
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Stamp Card', 'credit_card', 'EGP', 3000000, 10::smallint,
  25::smallint, '4412', 3::smallint, null, null,
  'active', 'fixed', 5000, null);

select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Stamp Card'),
  'April spend', '00000000-0000-0000-0000-00000000c501',
  date '2026-04-15', 2000000, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Stamp Card'),
  'May spend', '00000000-0000-0000-0000-00000000c501',
  date '2026-05-20', 624000, null, null
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a501',
  '00000000-0000-0000-0000-000000000078',
  'Cash Wallet', 'cash', 'EGP', 5000000
);
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Stamp Card'),
  '00000000-0000-0000-0000-00000000a501', 1000000, date '2026-06-10'
);

-- Peak 2,000,000 + 624,000 = 2,624,000, later paid down to 1,624,000: the
-- basis is the peak, not the current outstanding.
select results_eq(
  $$select app_finance.highest_daily_balance_minor(
      (select id from app_finance.accounts where name = 'Stamp Card'),
      date '2026-07-01', 3)$$,
  $$values (2624000::bigint)$$,
  'the basis is the quarter''s peak balance, not the paid-down current one'
);

-- ---------------------------------------------------------------------------
-- Quarterly stamp duty at 0.05% of that peak: the real CIB Gold figure.
-- 2,624,000 minor x 5 / 10000 = 1,312 minor = EGP 13.12.
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Stamp Card'),
  'Stamp Duty', 'stamp_tax', '00000000-0000-0000-0000-00000000c501',
  'configured', 'schedule', date '2026-07-01', 'percentage', null, 5,
  'highest_daily_balance_lookback', null, null, 3, 'quarterly', null,
  null, null, null, 100, null, null
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-07-01')$$,
  $$values (1)$$,
  'the quarterly stamp-duty rule generates exactly one charge'
);
select results_eq(
  $$select c.amount_minor, c.charged_on
    from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Stamp Duty'$$,
  $$values (1312::bigint, date '2026-07-01')$$,
  '0.05% of the 26,240.00 peak is exactly the statement''s EGP 13.12'
);
select results_eq(
  $$select next_charge_on from app_finance.credit_card_fee_rules
    where name = 'Stamp Duty'$$,
  $$values (date '2026-10-01')$$,
  'the schedule advances one quarter after charging'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000079',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fxdb-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FXDB Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000079","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges
    where rule_id in (
      select id from app_finance.credit_card_fee_rules
      where name in ('Foreign Exchange Fee', 'Stamp Duty')
    )$$,
  $$values (0)$$,
  'another user cannot see any of these generated charges'
);

select * from finish();
rollback;
