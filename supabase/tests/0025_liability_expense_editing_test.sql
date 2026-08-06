begin;
create extension if not exists pgtap with schema extensions;

select plan(61);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000060',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'liability-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Liability Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000061',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'liability-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Liability Intruder"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------

select has_function('app_finance', 'charge_liability_account',
  'charge_liability_account exists');
select has_function('app_finance', 'update_expense_transaction',
  'update_expense_transaction exists');
select has_function('app_finance', 'delete_ledger_transaction',
  'delete_ledger_transaction exists');
select has_view('app_finance', 'facility_activity_items',
  'facility_activity_items view exists');

-- ---------------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000060","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-0000000a0001',
  '00000000-0000-0000-0000-000000000060',
  'Cash Wallet', 'cash', 'EGP', 2000000
), (
  '00000000-0000-0000-0000-0000000a0002',
  '00000000-0000-0000-0000-000000000060',
  'Second Wallet', 'cash', 'EGP', 1000000
), (
  '00000000-0000-0000-0000-0000000a0003',
  '00000000-0000-0000-0000-000000000060',
  'Dollar Wallet', 'cash', 'USD', 100000
), (
  '00000000-0000-0000-0000-0000000a0004',
  '00000000-0000-0000-0000-000000000060',
  'Old Wallet', 'cash', 'EGP', 0
);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-0000000c0001',
  '00000000-0000-0000-0000-000000000060', 'Shopping', 'expense'
), (
  '00000000-0000-0000-0000-0000000c0002',
  '00000000-0000-0000-0000-000000000060', 'Side Work', 'income'
);

select app_finance.save_credit_facility(
  'Visa', 'credit_card', 'EGP', 500000, 10::smallint,
  25::smallint, '4321', 3::smallint, null, null);
select app_finance.save_credit_facility(
  'Mastercard', 'credit_card', 'EGP', 400000, 12::smallint,
  20::smallint, '8765', 3::smallint, null, null);
select app_finance.save_credit_facility(
  'Aman', 'bnpl', 'EGP', 300000, 5::smallint,
  null, null, 5::smallint, null, null);
select app_finance.save_credit_facility(
  'Frozen Card', 'credit_card', 'EGP', 100000, 10::smallint,
  15::smallint, null, 3::smallint, null, null);
select app_finance.set_credit_facility_status(
  (select id from app_finance.accounts where name = 'Frozen Card'), 'frozen');

-- ---------------------------------------------------------------------------
-- Creating an ordinary liability-backed expense
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Aman'),
  'Headphones', '00000000-0000-0000-0000-0000000c0001',
  date '2026-03-10', 50000, null, '00000000-0000-0000-0000-0000000f0001');

select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where id = '00000000-0000-0000-0000-0000000f0001'
      and transaction_kind = 'expense'$$,
  $$values (1)$$,
  'a BNPL expense books exactly one expense row'
);
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Aman'$$,
  $$values (50000::bigint)$$,
  'a BNPL expense raises outstanding once'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_plans
    where account_id = (select id from app_finance.accounts where name='Aman')$$,
  $$values (0)$$,
  'a BNPL expense never silently creates an installment plan'
);
select results_eq(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'Aman'),
      'Headphones', '00000000-0000-0000-0000-0000000c0001',
      date '2026-03-10', 50000, null,
      '00000000-0000-0000-0000-0000000f0001')$$,
  $$values ('00000000-0000-0000-0000-0000000f0001'::uuid)$$,
  'a retried charge with the same id is idempotent'
);

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Visa'),
  'Groceries', '00000000-0000-0000-0000-0000000c0001',
  date '2026-03-10', 40000, null, '00000000-0000-0000-0000-0000000f0002');

select results_eq(
  $$select charges_minor from app_finance.credit_card_statement_summaries
    where account_id = (select id from app_finance.accounts where name='Visa')$$,
  $$values (40000::bigint)$$,
  'a card expense joins the statement cycle of its business date'
);
select results_eq(
  $$select outstanding_minor, available_credit_minor
    from app_finance.credit_facility_summaries where name = 'Visa'$$,
  $$values (40000::bigint, 460000::bigint)$$,
  'a card expense raises outstanding and lowers available credit once'
);
select throws_ok(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'Aman'),
      'Too big', '00000000-0000-0000-0000-0000000c0001',
      date '2026-03-11', 400000, null, null)$$,
  'P0001', null, 'a charge above the credit limit is rejected'
);
select throws_ok(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'Frozen Card'),
      'Nope', '00000000-0000-0000-0000-0000000c0001',
      date '2026-03-11', 1000, null, null)$$,
  'P0001', null, 'a frozen facility cannot fund a new charge'
);
select throws_ok(
  $$select app_finance.charge_liability_account(
      '00000000-0000-0000-0000-0000000a0001',
      'Nope', '00000000-0000-0000-0000-0000000c0001',
      date '2026-03-11', 1000, null, null)$$,
  'P0001', null, 'the liability charge flow refuses an asset account'
);

-- ---------------------------------------------------------------------------
-- A: asset -> asset
-- ---------------------------------------------------------------------------

insert into app_finance.financial_transactions (
  id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, category_id, title
) values (
  '00000000-0000-0000-0000-0000000f0010',
  '00000000-0000-0000-0000-000000000060', 'expense',
  date '2026-03-12', 30000, 'EGP', '00000000-0000-0000-0000-0000000a0001',
  '00000000-0000-0000-0000-0000000c0001', 'Dinner'
);

select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  '00000000-0000-0000-0000-0000000a0002',
  date '2026-03-12', 30000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner', null);

select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-0000000a0001'$$,
  $$values (2000000::bigint)$$,
  'asset to asset reverses the old balance effect'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-0000000a0002'$$,
  $$values (970000::bigint)$$,
  'asset to asset applies the expense to the new account'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Dinner'$$,
  $$values (1)$$,
  'asset to asset preserves exactly one expense'
);

-- ---------------------------------------------------------------------------
-- B: asset -> credit card
-- ---------------------------------------------------------------------------

select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  (select id from app_finance.accounts where name = 'Visa'),
  date '2026-03-12', 30000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner', null);

select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-0000000a0002'$$,
  $$values (1000000::bigint)$$,
  'asset to card releases the cash balance effect'
);
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Visa'$$,
  $$values (70000::bigint)$$,
  'asset to card raises the destination outstanding exactly once'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (1)$$,
  'asset to card creates exactly one statement linkage'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where title = 'Dinner'$$,
  $$values (1)$$,
  'asset to card never duplicates the expense'
);

-- ---------------------------------------------------------------------------
-- E: same liability, changed data
-- ---------------------------------------------------------------------------

select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  (select id from app_finance.accounts where name = 'Visa'),
  date '2026-03-12', 50000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner out', null);

select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Visa'$$,
  $$values (90000::bigint)$$,
  'an amount change applies only the delta to outstanding'
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (50000::bigint)$$,
  'the statement item follows the corrected amount'
);
select results_eq(
  $$select charges_minor from app_finance.credit_card_statement_summaries
    where account_id = (select id from app_finance.accounts where name='Visa')
      and cycle_close = date '2026-03-25'$$,
  $$values (90000::bigint)$$,
  'the cycle total recomputes from its items'
);

-- A purchase date crossing the closing day moves cycles, without leaving a
-- membership behind.
select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  (select id from app_finance.accounts where name = 'Visa'),
  date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner out', null);

select results_eq(
  $$select cycle_close from app_finance.credit_card_statement_cycles c
    join app_finance.credit_card_statement_items i on i.cycle_id = c.id
    where i.transaction_id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (date '2026-04-25')$$,
  'a date past the closing day re-links the charge to the next cycle'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (1)$$,
  'a cycle move never leaves a second statement item behind'
);

-- ---------------------------------------------------------------------------
-- D: credit card -> BNPL and back
-- ---------------------------------------------------------------------------

select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  (select id from app_finance.accounts where name = 'Aman'),
  date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner out', null);

select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Visa'$$,
  $$values (40000::bigint)$$,
  'card to BNPL removes the charge from the old facility'
);
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Aman'$$,
  $$values (100000::bigint)$$,
  'card to BNPL adds the charge to the destination facility'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (0)$$,
  'card to BNPL leaves no stale statement linkage'
);

select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  (select id from app_finance.accounts where name = 'Mastercard'),
  date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner out', null);

select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Aman'$$,
  $$values (50000::bigint)$$,
  'BNPL to card reduces the old facility outstanding'
);
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Mastercard'$$,
  $$values (50000::bigint)$$,
  'BNPL to card raises the destination facility outstanding'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items i
    join app_finance.credit_card_statement_cycles c on c.id = i.cycle_id
    where i.transaction_id = '00000000-0000-0000-0000-0000000f0010'
      and c.account_id =
        (select id from app_finance.accounts where name = 'Mastercard')$$,
  $$values (1)$$,
  'BNPL to card builds the statement linkage on the destination card'
);

-- ---------------------------------------------------------------------------
-- C: liability -> asset
-- ---------------------------------------------------------------------------

select app_finance.update_expense_transaction(
  '00000000-0000-0000-0000-0000000f0010',
  '00000000-0000-0000-0000-0000000a0001',
  date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
  null, 'Dinner out', null);

select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Mastercard'$$,
  $$values (0::bigint)$$,
  'card to asset removes the charge from the facility'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-0000000a0001'$$,
  $$values (1950000::bigint)$$,
  'card to asset applies the expense to the destination account'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (0)$$,
  'card to asset leaves no orphaned statement item'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (1)$$,
  'the expense survives every move exactly once'
);
select results_eq(
  $$select count(*)::integer from app_reports.history_items
    where user_id = '00000000-0000-0000-0000-000000000060'
      and id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (1)$$,
  'reports count the moved expense exactly once'
);

-- ---------------------------------------------------------------------------
-- Rejections leave every table untouched
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0010',
      (select id from app_finance.accounts where name = 'Aman'),
      date '2026-03-26', 900000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Dinner out', null)$$,
  'P0001', null, 'a move above the destination credit limit is rejected'
);
select results_eq(
  $$select amount_minor, source_account_id
    from app_finance.financial_transactions
    where id = '00000000-0000-0000-0000-0000000f0010'$$,
  $$values (50000::bigint, '00000000-0000-0000-0000-0000000a0001'::uuid)$$,
  'a rejected move leaves the transaction unchanged'
);
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Aman'$$,
  $$values (50000::bigint)$$,
  'a rejected move leaves the destination facility unchanged'
);
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0010',
      '00000000-0000-0000-0000-0000000a0003',
      date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Dinner out', null)$$,
  'P0001', null, 'a currency mismatch is rejected'
);

update app_finance.accounts set is_archived = true
  where id = '00000000-0000-0000-0000-0000000a0004';
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0010',
      '00000000-0000-0000-0000-0000000a0004',
      date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Dinner out', null)$$,
  'P0001', null, 'an archived destination is rejected'
);

-- Income never lands on a liability account.
insert into app_finance.financial_transactions (
  id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  destination_account_id, category_id, title
) values (
  '00000000-0000-0000-0000-0000000f0011',
  '00000000-0000-0000-0000-000000000060', 'custom_income',
  date '2026-03-13', 20000, 'EGP', '00000000-0000-0000-0000-0000000a0001',
  '00000000-0000-0000-0000-0000000c0002', 'Gift'
);
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0011',
      (select id from app_finance.accounts where name = 'Aman'),
      date '2026-03-13', 20000, '00000000-0000-0000-0000-0000000c0002',
      null, 'Gift', null)$$,
  'P0001', null, 'income cannot be moved onto a credit facility'
);

-- ---------------------------------------------------------------------------
-- Specialized records stay protected
-- ---------------------------------------------------------------------------

select app_finance.create_installment_plan(
  (select id from app_finance.accounts where name = 'Visa'),
  'Fridge', '00000000-0000-0000-0000-0000000c0001',
  date '2026-03-01', 120000, 3, date '2026-04-01',
  0, null, 0, null, null, '00000000-0000-0000-0000-0000000e0001');

select throws_ok(
  $$select app_finance.update_expense_transaction(
      (select purchase_transaction_id from app_finance.installment_plans
        where id = '00000000-0000-0000-0000-0000000e0001'),
      '00000000-0000-0000-0000-0000000a0001',
      date '2026-03-01', 120000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Fridge', null)$$,
  'P0001', null,
  'an installment purchase cannot be detached by the generic editor'
);
select throws_ok(
  $$select app_finance.delete_ledger_transaction(
      (select purchase_transaction_id from app_finance.installment_plans
        where id = '00000000-0000-0000-0000-0000000e0001'))$$,
  'P0001', null,
  'an installment purchase cannot be deleted by the generic editor'
);

select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Visa'),
  '00000000-0000-0000-0000-0000000a0001', 40000, date '2026-04-02',
  null, null, '00000000-0000-0000-0000-0000000f0020');

select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0020',
      '00000000-0000-0000-0000-0000000a0002',
      date '2026-04-02', 40000, null, null, 'Payment', null)$$,
  'P0001', null, 'a facility repayment is not editable as an expense'
);

-- A closed Mastercard cycle that has been paid into is settled history:
-- the charge inside it may be renamed but never re-priced or moved.
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Mastercard'),
  'Settled charge', '00000000-0000-0000-0000-0000000c0001',
  date '2026-05-10', 30000, null, '00000000-0000-0000-0000-0000000f0021');
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Mastercard'),
  '00000000-0000-0000-0000-0000000a0001', 30000, date '2026-06-12',
  null, null, '00000000-0000-0000-0000-0000000f0022');

select results_eq(
  $$select count(*)::integer
    from app_finance.credit_card_statement_allocations
    where payment_transaction_id = '00000000-0000-0000-0000-0000000f0022'$$,
  $$values (1)$$,
  'the repayment allocated to the closed statement cycle'
);
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0021',
      (select id from app_finance.accounts where name = 'Mastercard'),
      date '2026-05-10', 45000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Settled charge', null)$$,
  'P0001', null, 'a charge inside a paid statement cannot be re-priced'
);
select throws_ok(
  $$select app_finance.delete_ledger_transaction(
      '00000000-0000-0000-0000-0000000f0021')$$,
  'P0001', null, 'a charge inside a paid statement cannot be deleted'
);
select lives_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0021',
      (select id from app_finance.accounts where name = 'Mastercard'),
      date '2026-05-10', 30000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Settled charge renamed', null)$$,
  'renaming a settled charge stays allowed'
);

-- ---------------------------------------------------------------------------
-- Ownership
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000061","role":"authenticated"}';
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-0000000f0010',
      '00000000-0000-0000-0000-0000000a0001',
      date '2026-03-26', 50000, '00000000-0000-0000-0000-0000000c0001',
      null, 'Dinner out', null)$$,
  'P0001', null, 'another user cannot edit this transaction'
);
select throws_ok(
  $$select app_finance.delete_ledger_transaction(
      '00000000-0000-0000-0000-0000000f0010')$$,
  'P0001', null, 'another user cannot delete this transaction'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000060","role":"authenticated"}';

-- ---------------------------------------------------------------------------
-- Related activity classification
-- ---------------------------------------------------------------------------

select results_eq(
  $$select activity_kind from app_finance.facility_activity_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0002'$$,
  $$values ('ordinary_expense'::text)$$,
  'an ordinary card charge is classified as an editable expense'
);
select results_eq(
  $$select is_settled from app_finance.facility_activity_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0021'$$,
  $$values (true)$$,
  'a charge on a paid statement is reported as settled'
);
select results_eq(
  $$select activity_kind from app_finance.facility_activity_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0020'$$,
  $$values ('facility_repayment'::text)$$,
  'a repayment is classified as a repayment'
);
select results_eq(
  $$select activity_kind, plan_id from app_finance.facility_activity_items
    where transaction_id = (select purchase_transaction_id
      from app_finance.installment_plans
      where id = '00000000-0000-0000-0000-0000000e0001')$$,
  $$values ('installment_purchase'::text,
    '00000000-0000-0000-0000-0000000e0001'::uuid)$$,
  'a financed purchase carries its plan id for the plan editor'
);
select results_eq(
  $$select count(*)::integer from app_finance.facility_activity_items
    where account_id = '00000000-0000-0000-0000-0000000a0001'$$,
  $$values (0)$$,
  'asset accounts never appear in facility activity'
);

-- ---------------------------------------------------------------------------
-- Deletion
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Mastercard'),
  'Mistake', '00000000-0000-0000-0000-0000000c0001',
  date '2026-07-02', 15000, null, '00000000-0000-0000-0000-0000000f0030');
select app_finance.delete_ledger_transaction(
  '00000000-0000-0000-0000-0000000f0030');

select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where id = '00000000-0000-0000-0000-0000000f0030'$$,
  $$values (0)$$,
  'deleting a card charge removes the transaction'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_statement_items
    where transaction_id = '00000000-0000-0000-0000-0000000f0030'$$,
  $$values (0)$$,
  'deleting a card charge removes its statement linkage'
);
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'Mastercard'$$,
  $$values (0::bigint)$$,
  'deleting a card charge returns the facility outstanding to zero'
);

-- An ordinary transfer between two asset accounts still deletes cleanly
-- through the same canonical RPC.
select app_finance.create_transfer(
  '00000000-0000-0000-0000-0000000a0001',
  '00000000-0000-0000-0000-0000000a0002', 10000, date '2026-07-03', null);
select lives_ok(
  $$select app_finance.delete_ledger_transaction(
      (select id from app_finance.financial_transactions
        where transaction_kind = 'transfer'
          and occurred_on = date '2026-07-03'))$$,
  'a plain transfer is still deletable through the canonical RPC'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where transaction_kind = 'transfer'
      and occurred_on = date '2026-07-03'$$,
  $$values (0)$$,
  'deleting a transfer removes its single ledger row'
);

select * from finish();
rollback;
