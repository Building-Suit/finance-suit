begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000077',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'penalty-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Penalty Owner"}', now(), now()
);

select has_function('app_finance', 'apply_statement_penalty_fees',
  'apply_statement_penalty_fees exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000077","role":"authenticated"}';

select app_finance.save_credit_facility(
  'Penalty Card', 'credit_card', 'EGP', 2010000, 10::smallint,
  25::smallint, '7700', 3::smallint, null, null,
  'active', 'fixed', 100000, null);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c401',
  '00000000-0000-0000-0000-000000000077',
  'Card Spending', 'expense'
);

-- ---------------------------------------------------------------------------
-- Late payment: required minimum 1,000; fixture from the product spec
-- (paid 999.99 -> late fee; paid 1,000 -> no late fee).
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Penalty Card'),
  'Late Fee', 'late_payment', '00000000-0000-0000-0000-00000000c401',
  'configured', 'late_payment_missed_minimum', date '2026-01-01', 'fixed',
  15000, null, null, null, null, null, 'per_transaction', null, null, null,
  null, 100, null, null
);

select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Penalty Card'),
  'March spend', '00000000-0000-0000-0000-00000000c401',
  date '2026-03-10', 100000, null, null
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a401',
  '00000000-0000-0000-0000-000000000077',
  'Cash Wallet', 'cash', 'EGP', 5000000
);

-- A payment of only 999.99 (99999 minor units) against the required
-- minimum of 1,000.00 (the fixed 100000-minor-unit floor) leaves the
-- minimum unmet.
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Penalty Card'),
  '00000000-0000-0000-0000-00000000a401', 99999, date '2026-04-09'
);
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-04-12')$$,
  $$values (1)$$,
  'paying 999.99 against a 1,000.00 minimum triggers exactly one late fee'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Late Fee'$$,
  $$values (1)$$,
  'only one late-payment charge exists for this statement'
);
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-04-13')$$,
  $$values (0)$$,
  're-running the penalty sweep never double-charges the same cycle'
);

-- ---------------------------------------------------------------------------
-- Paying the full required minimum never triggers a late fee (fixture 2)
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Clean Card', 'credit_card', 'EGP', 5000000, 10::smallint,
  25::smallint, '8800', 3::smallint, null, null,
  'active', 'fixed', 100000, null);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Clean Card'),
  'Late Fee 2', 'late_payment', '00000000-0000-0000-0000-00000000c401',
  'configured', 'late_payment_missed_minimum', date '2026-01-01', 'fixed',
  15000, null, null, null, null, null, 'per_transaction', null, null, null,
  null, 100, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Clean Card'),
  'March spend', '00000000-0000-0000-0000-00000000c401',
  date '2026-03-10', 100000, null, null
);
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Clean Card'),
  '00000000-0000-0000-0000-00000000a401', 100000, date '2026-04-09'
);
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-04-12')$$,
  $$values (0)$$,
  'paying exactly the required minimum never triggers a late fee'
);

-- Not paying at all is a *different* case from "minimum missed" only in
-- degree, not in kind — it still triggers exactly once.
select app_finance.save_credit_facility(
  'Unpaid Card', 'credit_card', 'EGP', 5000000, 10::smallint,
  25::smallint, '9900', 3::smallint, null, null,
  'active', 'fixed', 100000, null);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Unpaid Card'),
  'Late Fee 3', 'late_payment', '00000000-0000-0000-0000-00000000c401',
  'configured', 'late_payment_missed_minimum', date '2026-01-01', 'fixed',
  15000, null, null, null, null, null, 'per_transaction', null, null, null,
  null, 100, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Unpaid Card'),
  'March spend', '00000000-0000-0000-0000-00000000c401',
  date '2026-03-10', 100000, null, null
);
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-04-12')$$,
  $$values (1)$$,
  'never paying anything against the minimum still triggers one late fee'
);

-- ---------------------------------------------------------------------------
-- Over limit: fixture from the product spec (limit 20,000; outstanding
-- 20,100 -> exactly one over-limit fee, which cannot recurse).
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Limit Card', 'credit_card', 'EGP', 2000000, 10::smallint,
  25::smallint, '1200', 3::smallint, null, null,
  'active', 'fixed', 100000, null);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Limit Card'),
  'Over Limit Fee', 'over_limit', '00000000-0000-0000-0000-00000000c401',
  'configured', 'over_limit_event', date '2026-01-01', 'fixed', 25000,
  null, null, null, null, null, 'per_transaction', null, null, null, null,
  100, null, null
);
-- The card's own fee-rule sweep can push a card over its limit (an
-- annual fee posting on top of near-limit spending); simulate that
-- directly with an internal-flagged charge rather than requiring the
-- purchase path to allow an over-limit purchase.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Limit Card'),
  'Big purchase', '00000000-0000-0000-0000-00000000c401',
  date '2026-05-01', 2000000, null, null
);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Limit Card'),
  'Insurance Push', 'insurance', '00000000-0000-0000-0000-00000000c401',
  'configured', 'schedule', date '2026-05-05', 'fixed', 100, null, null,
  null, null, null, 'once', null, null, null, null, 100, null, null
);
select app_finance.apply_credit_card_fees(date '2026-05-05');
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Limit Card'$$,
  $$values (2000100::bigint)$$,
  'a generated fee (not a purchase) is what pushes this card over its limit'
);
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-05-06')$$,
  $$values (1)$$,
  'exceeding the limit by any generated charge triggers exactly one fee'
);
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-05-07')$$,
  $$values (0)$$,
  'the over-limit fee itself never triggers a second over-limit fee'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Over Limit Fee'$$,
  $$values (1)$$,
  'exactly one over-limit charge exists for this card'
);

-- ---------------------------------------------------------------------------
-- Over limit tolerance: a configured allowance is respected
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Tolerant Card', 'credit_card', 'EGP', 2000000, 10::smallint,
  25::smallint, '1300', 3::smallint, null, null,
  'active', 'fixed', 100000, null);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Tolerant Card'),
  'Tolerant Over Limit', 'over_limit', '00000000-0000-0000-0000-00000000c401',
  'configured', 'over_limit_event', date '2026-01-01', 'fixed', 25000, null,
  null, null, null, null, 'per_transaction', null, 50000, null, null, 100,
  null, null
);
-- Ordinary purchases stay hard-blocked at the limit itself (tolerance
-- only ever governs whether a *generated* charge triggers a fee), so
-- reaching "over, but within tolerance" has to come from a fee, exactly
-- like the untolerated fixture above.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Tolerant Card'),
  'At the limit', '00000000-0000-0000-0000-00000000c401',
  date '2026-05-01', 2000000, null, null
);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Tolerant Card'),
  'Small Statement Fee', 'other', '00000000-0000-0000-0000-00000000c401',
  'configured', 'schedule', date '2026-05-05', 'fixed', 20000, null, null,
  null, null, null, 'once', null, null, null, null, 100, null, null
);
select app_finance.apply_credit_card_fees(date '2026-05-05');
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-05-02')$$,
  $$values (0)$$,
  'exceeding the limit within the configured tolerance never charges'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000078',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'penalty-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Penalty Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000078","role":"authenticated"}';
select results_eq(
  $$select app_finance.apply_statement_penalty_fees(date '2026-05-06')$$,
  $$values (0)$$,
  'another user has no cards to evaluate and generates nothing'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges
    where rule_id in (
      select id from app_finance.credit_card_fee_rules
      where name in ('Late Fee', 'Over Limit Fee')
    )$$,
  $$values (0)$$,
  'another user cannot see the generated penalty charges'
);

select * from finish();
rollback;
