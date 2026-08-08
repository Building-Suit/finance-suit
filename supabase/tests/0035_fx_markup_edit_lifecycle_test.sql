begin;
create extension if not exists pgtap with schema extensions;

select plan(19);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007c',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fxel-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FXEL Owner"}', now(), now()
);

select has_table('app_finance', 'credit_card_fx_markup_charges',
  'credit_card_fx_markup_charges exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007c","role":"authenticated"}';

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c701',
  '00000000-0000-0000-0000-00000000007c',
  'Card Spending', 'expense'
);
insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a701',
  '00000000-0000-0000-0000-00000000007c',
  'Cash Wallet', 'cash', 'EGP', 5000000
);

select app_finance.save_credit_facility(
  'FX Edit Card', 'credit_card', 'EGP', 5000000, 25::smallint,
  28::smallint, '6011', 3::smallint, null, null,
  'active', 'fixed', 5000, null, null, 300);

-- ---------------------------------------------------------------------------
-- Turning the switch ON during an edit creates the markup
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'FX Edit Card'),
  'Netflix', '00000000-0000-0000-0000-00000000c701',
  date '2026-07-12', 17000, null, null, false
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (0)$$,
  'the purchase starts with no markup'
);

select lives_ok(
  $$select app_finance.update_expense_transaction(
      (select id from app_finance.financial_transactions
        where title = 'Netflix'),
      (select id from app_finance.accounts where name = 'FX Edit Card'),
      date '2026-07-12', 17000,
      '00000000-0000-0000-0000-00000000c701', null, 'Netflix', null, true)$$,
  'flipping the switch on during an edit is accepted'
);
select results_eq(
  $$select amount_minor from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (510::bigint)$$,
  'turning the switch on creates the exact 3% markup'
);

-- ---------------------------------------------------------------------------
-- Changing the amount while the switch stays on resizes the markup
-- ---------------------------------------------------------------------------

select app_finance.update_expense_transaction(
  (select id from app_finance.financial_transactions where title = 'Netflix'),
  (select id from app_finance.accounts where name = 'FX Edit Card'),
  date '2026-07-12', 20000,
  '00000000-0000-0000-0000-00000000c701', null, 'Netflix', null, true
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (1)$$,
  'resizing never creates a second markup transaction'
);
select results_eq(
  $$select amount_minor from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (600::bigint)$$,
  '3% of the new EGP 200.00 amount resizes the markup to 6.00'
);

-- ---------------------------------------------------------------------------
-- Turning the switch OFF during an edit removes the markup
-- ---------------------------------------------------------------------------

select app_finance.update_expense_transaction(
  (select id from app_finance.financial_transactions where title = 'Netflix'),
  (select id from app_finance.accounts where name = 'FX Edit Card'),
  date '2026-07-12', 20000,
  '00000000-0000-0000-0000-00000000c701', null, 'Netflix', null, false
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (0)$$,
  'turning the switch off removes the markup transaction'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.credit_card_fx_markup_charges$$,
  $$values (0)$$,
  'the link row is gone along with the markup transaction'
);

-- ---------------------------------------------------------------------------
-- Moving the purchase off the card removes the markup even if the switch
-- is left on: eligibility is re-evaluated against the destination, never
-- assumed from what was there before.
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'FX Edit Card'),
  'Badoo', '00000000-0000-0000-0000-00000000c701',
  date '2026-07-15', 6399, null, null, true
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (1)$$,
  'the second purchase starts with its own markup'
);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c702',
  '00000000-0000-0000-0000-00000000007c',
  'Personal', 'expense'
);
select app_finance.update_expense_transaction(
  (select id from app_finance.financial_transactions where title = 'Badoo'),
  '00000000-0000-0000-0000-00000000a701', date '2026-07-15', 6399,
  '00000000-0000-0000-0000-00000000c702', null, 'Badoo', null, true
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'$$,
  $$values (0)$$,
  'moving the purchase to a cash account drops its markup regardless of the switch'
);

-- ---------------------------------------------------------------------------
-- The markup transaction itself is never independently editable or
-- deletable, exactly like a rule-generated fee.
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'FX Edit Card'),
  'Cloudflare', '00000000-0000-0000-0000-00000000c701',
  date '2026-08-04', 53675, null, null, true
);
select throws_ok(
  $$select app_finance.update_expense_transaction(
      (select id from app_finance.financial_transactions
        where title = 'Foreign Exchange Markup' order by created_at desc limit 1),
      (select id from app_finance.accounts where name = 'FX Edit Card'),
      date '2026-08-04', 100, '00000000-0000-0000-0000-00000000c701',
      null, 'renamed', null, false)$$,
  'P0001',
  'fx_markup_locked: this charge follows its purchase; edit the purchase instead',
  'the markup transaction cannot be edited directly'
);
select throws_ok(
  $$select app_finance.delete_ledger_transaction(
      (select id from app_finance.financial_transactions
        where title = 'Foreign Exchange Markup' order by created_at desc limit 1))$$,
  'P0001',
  'fx_markup_locked: this charge follows its purchase; edit the purchase instead',
  'the markup transaction cannot be deleted directly'
);

-- Deleting the purchase takes its still-attached markup with it.
select app_finance.delete_ledger_transaction(
  (select id from app_finance.financial_transactions where title = 'Cloudflare')
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title in ('Cloudflare', 'Foreign Exchange Markup')$$,
  $$values (0)$$,
  'deleting the purchase deletes its markup too'
);

-- ---------------------------------------------------------------------------
-- Creating a markup through an edit still respects the credit limit
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'New Markup Limit Card', 'credit_card', 'EGP', 10299, 25::smallint,
  28::smallint, '1111', 3::smallint, null, null,
  'active', 'fixed', 5000, null, null, 300);
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'New Markup Limit Card'),
  'Starter', '00000000-0000-0000-0000-00000000c701',
  date '2026-07-20', 5000, null, null, false
);
-- 100.00 alone fits under the 102.99 limit, but its 3.00 markup pushes the
-- total to 103.00 — a check that only re-validated the purchase amount
-- would miss this.
select throws_ok(
  $$select app_finance.update_expense_transaction(
      (select id from app_finance.financial_transactions
        where title = 'Starter'),
      (select id from app_finance.accounts
        where name = 'New Markup Limit Card'),
      date '2026-07-20', 10000,
      '00000000-0000-0000-0000-00000000c701', null, 'Starter', null, true)$$,
  'P0001',
  'insufficient_credit: purchase exceeds available credit',
  'a new markup created by an edit is still checked against the limit'
);
select results_eq(
  $$select amount_minor from app_finance.financial_transactions
    where title = 'Starter'$$,
  $$values (5000::bigint)$$,
  'the rejected edit left the purchase amount exactly as it was'
);

-- ---------------------------------------------------------------------------
-- Resizing an existing markup through an edit also respects the limit —
-- not just creating a new one.
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Resize Limit Card', 'credit_card', 'EGP', 10402, 25::smallint,
  28::smallint, '2222', 3::smallint, null, null,
  'active', 'fixed', 5000, null, null, 300);
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Resize Limit Card'),
  'Grower', '00000000-0000-0000-0000-00000000c701',
  date '2026-07-21', 5000, null, null, true
);
-- 100.00 + its 3.00 markup = 103.00, comfortably under the 104.02 limit.
select app_finance.update_expense_transaction(
  (select id from app_finance.financial_transactions where title = 'Grower'),
  (select id from app_finance.accounts where name = 'Resize Limit Card'),
  date '2026-07-21', 10000,
  '00000000-0000-0000-0000-00000000c701', null, 'Grower', null, true
);
select results_eq(
  $$select amount_minor from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'
      and source_account_id =
        (select id from app_finance.accounts where name = 'Resize Limit Card')$$,
  $$values (300::bigint)$$,
  '200.00 + its resized 3% markup (300) fits comfortably under the limit'
);
-- 101.00 + its 3.03 (rounded 3.00... actually 3.03 rounds to 3.03->3? no:
-- 10100 * 300 / 10000 = 303 minor = 3.03) markup = 104.03, one piastre over
-- the 104.02 limit.
select throws_ok(
  $$select app_finance.update_expense_transaction(
      (select id from app_finance.financial_transactions
        where title = 'Grower'),
      (select id from app_finance.accounts where name = 'Resize Limit Card'),
      date '2026-07-21', 10100,
      '00000000-0000-0000-0000-00000000c701', null, 'Grower', null, true)$$,
  'P0001',
  'insufficient_credit: purchase exceeds available credit',
  'a resize that pushes an existing markup over the limit is rejected'
);
select results_eq(
  $$select amount_minor from app_finance.financial_transactions
    where title = 'Foreign Exchange Markup'
      and source_account_id =
        (select id from app_finance.accounts where name = 'Resize Limit Card')$$,
  $$values (300::bigint)$$,
  'the rejected resize left the markup exactly as it was'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

reset role;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000007d',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'fxel-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"FXEL Intruder"}', now(), now()
);
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000007d","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fx_markup_charges$$,
  $$values (0)$$,
  'another user cannot see any of these markup links'
);

select * from finish();
rollback;
