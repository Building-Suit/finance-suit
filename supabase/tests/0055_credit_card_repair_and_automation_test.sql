begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

-- Setup test user in auth.users
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000c001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'card_test@example.com', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Card Test User"}', now(), now()
);

-- Authenticate as test user
set local search_path = app_finance, extensions, public;
select set_config('role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000c001","role":"authenticated"}', true);
select set_config('app_finance.facility_internal', 'on', true);

-- Setup liability card account and asset bank account
insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code
) values (
  '00000000-0000-0000-0000-00000000c010', '00000000-0000-0000-0000-00000000c001',
  'CIB Card', 'credit_card', 'EGP'
), (
  '00000000-0000-0000-0000-00000000c011', '00000000-0000-0000-0000-00000000c001',
  'CIB Bank', 'bank', 'EGP'
);

insert into app_finance.credit_facility_settings (
  user_id, account_id, credit_limit_minor, statement_day, default_due_day, automation_mode
) values (
  '00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000c010',
  2580000, 31, 25, 'dry_run'
);

-- 1. Test functions exist
select has_function('app_finance', 'materialize_installment_interest', 'materialize_installment_interest exists');
select has_function('app_finance', 'relink_card_statement_item', 'relink_card_statement_item exists');
select has_function('app_finance', 'pay_credit_facility_v3', 'pay_credit_facility_v3 exists');
select has_function('app_finance', 'process_credit_card_automation', 'process_credit_card_automation exists');
select has_function('app_finance', 'preview_cib_historical_repair', 'preview_cib_historical_repair exists');
select has_function('app_finance', 'apply_reconciliation_repair_plan', 'apply_reconciliation_repair_plan exists');

-- 2. Setup purchase transaction & installment plan with reducing balance interest
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001',
  'Electronics', 'expense'
);

insert into app_finance.financial_transactions (
  id, user_id, transaction_kind, occurred_on, amount_minor, currency_code, source_account_id, title
) values (
  '00000000-0000-0000-0000-0000000000f0', '00000000-0000-0000-0000-00000000c001',
  'expense', '2026-07-25', 439869, 'EGP', '00000000-0000-0000-0000-00000000c010', 'Samsung Monitor Purchase'
);

insert into app_finance.installment_plans (
  id, user_id, account_id, title, category_id, purchased_on, first_due_on,
  installment_count, purchase_price_minor, financed_principal_minor,
  financing_fees_minor, total_payable_minor, interest_method, status, purchase_transaction_id
) values (
  '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000c001',
  '00000000-0000-0000-0000-00000000c010', 'Samsung Monitor',
  '00000000-0000-0000-0000-000000000001', '2026-07-25', '2026-08-25',
  10, 439869, 439869, 60131, 500000, 'reducing', 'active',
  '00000000-0000-0000-0000-0000000000f0'
);

-- installment_dues trigger populate_installment_due_components & protect_installment_rows
-- require app_finance.facility_internal to be 'on' (already set above)
insert into app_finance.installment_dues (
  id, user_id, plan_id, sequence_number, due_on,
  opening_principal_minor, principal_minor, interest_minor, financing_fee_minor,
  closing_principal_minor, amount_minor
) values (
  '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000c001',
  '00000000-0000-0000-0000-0000000000a1', 1, '2026-08-25',
  439869, 39563, 10997, 0, 400306, 50560
), (
  '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-00000000c001',
  '00000000-0000-0000-0000-0000000000a1', 2, '2026-09-25',
  400306, 40958, 9602, 0, 359348, 50560
);

-- 3. Test interest materialization
select is(
  app_finance.materialize_installment_interest('2026-09-26', '00000000-0000-0000-0000-00000000c010'),
  2,
  'materializes 2 due interest charges'
);

-- 4. Test idempotency of interest materialization (running twice adds 0 new transactions)
select is(
  app_finance.materialize_installment_interest('2026-09-26', '00000000-0000-0000-0000-00000000c010'),
  0,
  'second materialization run is idempotent (0 added)'
);

-- 5. Test statement relinking with strict date-based assignment
-- Bypass the protect_facility_transactions trigger (as RPCs do internally)
select set_config('app_finance.facility_internal', 'on', true);
insert into app_finance.financial_transactions (
  id, user_id, transaction_kind, occurred_on, amount_minor, currency_code, source_account_id, title
) values (
  '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-00000000c001',
  'expense', '2026-08-23', 81000, 'EGP', '00000000-0000-0000-0000-00000000c010', 'Store Purchase'
);

select lives_ok(
  $$select app_finance.relink_card_statement_item(
    '00000000-0000-0000-0000-00000000c001'::uuid,
    '00000000-0000-0000-0000-00000000f001'::uuid,
    '00000000-0000-0000-0000-00000000c010'::uuid,
    '2026-08-23'::date,
    81000::bigint
  )$$,
  'statement item relinked by date'
);

select results_eq(
  $$select c.cycle_close
    from app_finance.credit_card_statement_items i
    join app_finance.credit_card_statement_cycles c on c.id = i.cycle_id
    where i.transaction_id = '00000000-0000-0000-0000-00000000f001'$$,
  $$values ('2026-08-31'::date)$$,
  'purchase dated 23 August bills to August 31 cycle close'
);

-- 6. Test Dry-Run Automation Execution
select is(
  (app_finance.process_credit_card_automation('00000000-0000-0000-0000-00000000c010', 'dry_run', '2026-09-20') ->> 'candidates_found')::integer,
  0,
  'dry run automation finds 0 remaining candidate dues'
);

-- Verify log entry recorded
select is(
  (select count(*)::integer from app_finance.card_automation_logs where account_id = '00000000-0000-0000-0000-00000000c010'),
  1,
  'automation log entry created'
);

-- 7. Test Bank Statement Line Save
select lives_ok(
  $$select app_finance.save_bank_statement_line(
    '00000000-0000-0000-0000-00000000c010'::uuid,
    '2026-08-01'::date, '2026-08-01'::date, 10996::bigint,
    'EGP', 'CIB Interest Charge', 'REF123', false
  )$$,
  'bank statement line saved'
);

select is(
  (select count(*)::integer from app_finance.bank_statement_lines where account_id = '00000000-0000-0000-0000-00000000c010'),
  1,
  'bank statement line count is 1'
);

-- 8. Test Repair Preview Manifest Generation
select is(
  (app_finance.preview_cib_historical_repair('00000000-0000-0000-0000-00000000c010') ->> 'status'),
  'preview_ready',
  'repair manifest preview is ready'
);

-- 9. Test Applying Repair Plan
select is(
  (app_finance.apply_reconciliation_repair_plan(app_finance.preview_cib_historical_repair('00000000-0000-0000-0000-00000000c010')) ->> 'status'),
  'applied',
  'repair plan applied successfully'
);

-- 10. Re-apply repair plan (Idempotency)
select is(
  (app_finance.apply_reconciliation_repair_plan(app_finance.preview_cib_historical_repair('00000000-0000-0000-0000-00000000c010')) ->> 'status'),
  'applied',
  're-applying repair plan is idempotent'
);

select * from finish();
rollback;
