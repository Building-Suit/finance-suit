begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007b',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'recon-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Recon Owner"}', now(), now()
);

select has_function('app_finance', 'reconcile_fee_charge',
  'reconcile_fee_charge exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007b","role":"authenticated"}';

select app_finance.save_credit_facility(
  'Recon Card', 'credit_card', 'EGP', 5000000, 10::smallint,
  25::smallint, '6600', 3::smallint, null, null,
  'active', 'fixed', 5000, null);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c602',
  '00000000-0000-0000-0000-00000000007b',
  'Card Fees', 'expense'
);

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Recon Card'),
  'Annual Renewal', 'annual_membership',
  '00000000-0000-0000-0000-00000000c602', 'configured', 'schedule',
  date '2026-01-15', 'fixed', 70000, null, null, null, null, null,
  'annually', null, null, null, null, 100, null, null
);
select app_finance.apply_credit_card_fees(date '2026-01-16');

-- ---------------------------------------------------------------------------
-- Reconciling this single charge only: ledger matches the bank amount,
-- the rule itself is untouched.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.reconcile_fee_charge(
      (select c.id from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.name = 'Annual Renewal'),
      68500, false, null, 'Bank statement showed EGP 685.00')$$,
  'reconciling one charge to the bank amount succeeds'
);
select results_eq(
  $$select c.amount_minor, c.actual_amount_minor, c.expected_amount_minor,
      c.reconciliation_status::text
    from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Annual Renewal'$$,
  $$values (68500::bigint, 68500::bigint, 70000::bigint, 'adjusted'::text)$$,
  'the charge keeps both the original expected value and the reconciled actual'
);
select results_eq(
  $$select t.amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.financial_transactions t on t.id = c.transaction_id
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Annual Renewal'$$,
  $$values (68500::bigint)$$,
  'the ledger transaction now matches the bank-confirmed amount'
);
select results_eq(
  $$select i.amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_statement_items i
      on i.transaction_id = c.transaction_id
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Annual Renewal'$$,
  $$values (68500::bigint)$$,
  'the statement item mirrors the same reconciled amount'
);
select results_eq(
  $$select current_fixed_amount_minor
    from app_finance.credit_card_fee_rule_current
    where name = 'Annual Renewal'$$,
  $$values (70000::bigint)$$,
  'the rule itself keeps predicting EGP 700 for the next occurrence'
);

-- Reconciling to exactly the predicted amount marks it confirmed, not
-- adjusted.
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Recon Card'),
  'Statement Fee', 'statement_fee', '00000000-0000-0000-0000-00000000c602',
  'configured', 'schedule', date '2026-01-15', 'fixed', 2500, null, null,
  null, null, null, 'monthly', null, null, null, null, 100, null, null
);
select app_finance.apply_credit_card_fees(date '2026-01-16');
select app_finance.reconcile_fee_charge(
  (select c.id from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Statement Fee'),
  2500, false, null, null
);
select results_eq(
  $$select reconciliation_status::text from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Statement Fee'$$,
  $$values ('confirmed'::text)$$,
  'matching the predicted amount exactly is recorded as confirmed'
);

-- ---------------------------------------------------------------------------
-- Updating the rule for future charges: a new version, not a rewrite of
-- the charge that was just reconciled.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.reconcile_fee_charge(
      (select c.id from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.name = 'Annual Renewal'),
      68500, true, date '2027-09-15', 'Bank confirmed the new rate')$$,
  'reconciling with "update the rule going forward" succeeds'
);
select results_eq(
  $$select current_fixed_amount_minor, upcoming_fixed_amount_minor,
      upcoming_effective_from
    from app_finance.credit_card_fee_rule_current
    where name = 'Annual Renewal'$$,
  $$values (70000::bigint, 68500::bigint, date '2027-09-15')$$,
  'the current occurrence stays EGP 700; only the future one becomes 685'
);
select results_eq(
  $$select expected_amount_minor, actual_amount_minor
    from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Annual Renewal'$$,
  $$values (70000::bigint, 68500::bigint)$$,
  'the historical charge remains exactly as it was, expected and actual alike'
);

-- Reconciliation is rejected on a percentage-based rule's "update the
-- rule going forward" path (ambiguous: which rate should change?).
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Recon Card'),
  'Quarterly Tax', 'stamp_tax', '00000000-0000-0000-0000-00000000c602',
  'configured', 'schedule', date '2026-01-15', 'percentage', null, 5,
  'credit_limit', null, null, null, 'quarterly', null, null, null, null,
  100, null, null
);
select app_finance.apply_credit_card_fees(date '2026-01-16');
select throws_ok(
  $$select app_finance.reconcile_fee_charge(
      (select c.id from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.name = 'Quarterly Tax'),
      2600, true, null, null)$$,
  'P0001', null,
  'updating a percentage rule from a single reconciled amount is rejected'
);
select lives_ok(
  $$select app_finance.reconcile_fee_charge(
      (select c.id from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.name = 'Quarterly Tax'),
      2600, false, null, null)$$,
  'reconciling that same charge without touching the rule still succeeds'
);

-- Zero (a fully waived charge) is out of scope for this RPC.
select throws_ok(
  $$select app_finance.reconcile_fee_charge(
      (select c.id from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.name = 'Quarterly Tax'),
      0, false, null, null)$$,
  'P0001', null, 'reconciling to zero is rejected (use a reversal instead)'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007c',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'recon-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Recon Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007c","role":"authenticated"}';
select throws_ok(
  $$select app_finance.reconcile_fee_charge(
      (select c.id from app_finance.credit_card_fee_charges c
        join app_finance.credit_card_fee_rules r on r.id = c.rule_id
        where r.name = 'Annual Renewal'),
      1, false, null, null)$$,
  'P0001', null, 'another user cannot reconcile a charge they do not own'
);

select * from finish();
rollback;
