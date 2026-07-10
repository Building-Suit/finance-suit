begin;
create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user-c@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"User C"}', now(), now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000c","role":"authenticated"}';

-- Onboarding function creates everything atomically.
select lives_ok(
  $$select public.complete_onboarding(
      'User C', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
      1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
      'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
      'Current Balance', 'current', 1000000, false)$$,
  'complete_onboarding succeeds');

select is((select count(*)::int from public.accounts), 1, 'onboarding created one account');
select is((select count(*)::int from public.transaction_categories), 22, 'default categories seeded');
select ok((select onboarding_completed_at is not null from public.user_preferences), 'onboarding marked complete');
select ok((select is_default from public.accounts limit 1), 'first account is default');

-- Positive amount constraint.
select throws_ok(
  $$insert into public.financial_transactions (user_id, transaction_kind, occurred_on, amount_minor, source_account_id)
    values ('00000000-0000-0000-0000-00000000000c', 'expense', current_date, 0,
            (select id from public.accounts limit 1))$$,
  '23514', null, 'zero amount rejected');

-- Direction rule: expense cannot have destination.
select throws_ok(
  $$insert into public.financial_transactions (user_id, transaction_kind, occurred_on, amount_minor, source_account_id, destination_account_id)
    values ('00000000-0000-0000-0000-00000000000c', 'expense', current_date, 100,
            (select id from public.accounts limit 1), (select id from public.accounts limit 1))$$,
  '23514', null, 'expense with destination rejected');

-- Transfer via function, balances update.
insert into public.accounts (user_id, name, account_type, opening_balance_minor)
values ('00000000-0000-0000-0000-00000000000c', 'Savings', 'savings', 200000);

select lives_ok(
  $$select public.create_transfer(
      (select id from public.accounts where name = 'Current Balance'),
      (select id from public.accounts where name = 'Savings'),
      300000, current_date, null)$$,
  'transfer succeeds');

select is((select balance_minor from public.account_balances where name = 'Current Balance'), 700000::bigint, 'source reduced');
select is((select balance_minor from public.account_balances where name = 'Savings'), 500000::bigint, 'destination increased');
select is((select sum(balance_minor)::bigint from public.account_balances), 1200000::bigint, 'total unchanged');

-- Insufficient funds blocked (default account disallows negative).
select throws_ok(
  $$select public.create_transfer(
      (select id from public.accounts where name = 'Current Balance'),
      (select id from public.accounts where name = 'Savings'),
      99999999, current_date, null)$$,
  'P0001', null, 'overdraft transfer rejected');

-- Salary payment idempotency.
insert into public.salary_periods (user_id, period_start, period_end, expected_payment_date, status, snapshot, finalized_at)
values ('00000000-0000-0000-0000-00000000000c', '2026-06-01', '2026-06-30', '2026-07-25', 'finalized', '{"total": 1000000}', now());

select lives_ok(
  $$select public.record_salary_payment(
      (select id from public.salary_periods where period_start = '2026-06-01'),
      1000000,
      (select id from public.accounts where name = 'Current Balance'),
      '2026-07-25', null)$$,
  'salary payment recorded');

select throws_ok(
  $$select public.record_salary_payment(
      (select id from public.salary_periods where period_start = '2026-06-01'),
      1000000,
      (select id from public.accounts where name = 'Current Balance'),
      '2026-07-25', null)$$,
  'P0001', null, 'duplicate salary payment rejected');

-- Cash-flow summary excludes transfers, includes salary income.
select results_eq(
  $$select income_minor, expenses_minor, allowances_minor from public.cash_flow_summary('2026-01-01', '2099-12-31')$$,
  $$values (1000000::bigint, 0::bigint, 0::bigint)$$,
  'cash flow summary correct: transfers excluded, salary counted');

select * from finish();
rollback;
