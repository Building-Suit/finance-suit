begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user-d@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"User D"}', now(), now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
      'User D', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
      1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
      'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
      'Current Balance', 'current', 1000000, false)$$,
  'complete_onboarding succeeds');

insert into app_finance.financial_transactions (user_id, transaction_kind, occurred_on, amount_minor, currency_code, source_account_id, title)
values
  ('00000000-0000-0000-0000-00000000000d', 'expense', '2026-07-07', 50000, 'EGP', (select id from app_finance.accounts where name = 'Current Balance'), 'Backdated expense'),
  ('00000000-0000-0000-0000-00000000000d', 'allowance_given', '2026-07-08', 100000, 'EGP', (select id from app_finance.accounts where name = 'Current Balance'), 'Family support');

insert into app_finance.financial_transactions (user_id, transaction_kind, occurred_on, amount_minor, currency_code, destination_account_id, title)
values ('00000000-0000-0000-0000-00000000000d', 'freelance_income', '2026-07-09', 300000, 'EGP', (select id from app_finance.accounts where name = 'Current Balance'), 'Client invoice');

insert into app_work.work_entries (user_id, work_date, entry_type, duration_minutes, break_minutes, computed_amount_minor, calc_snapshot)
values ('00000000-0000-0000-0000-00000000000d', '2026-07-09', 'overtime', 120, 0, 25000, '{"source":"test"}');

insert into app_salary.salary_adjustments (user_id, effective_date, adjustment_type, amount_minor, title)
values ('00000000-0000-0000-0000-00000000000d', '2026-07-10', 'deduction', 10000, 'Late fee');

insert into app_salary.salary_periods (user_id, period_start, period_end, expected_payment_date, status, snapshot, finalized_at)
values ('00000000-0000-0000-0000-00000000000d', '2026-07-01', '2026-07-31', '2026-08-25', 'finalized', '{"total_minor":1000000,"currency_code":"EGP"}', now());

select has_view('app_reports', 'history_items', 'history_items view exists');

select is((select count(*)::int from app_reports.history_items), 5, 'history unifies transactions, work and salary adjustments');

select results_eq(
  $$select record_date, title from app_reports.history_items where title = 'Backdated expense'$$,
  $$values ('2026-07-07'::date, 'Backdated expense'::text)$$,
  'history displays occurred_on business date');

select results_eq(
  $$select income_minor, expenses_minor, allowances_minor, net_minor from app_reports.cash_flow_summary('2026-07-01', '2026-07-31')$$,
  $$values (300000::bigint, 50000::bigint, 100000::bigint, 150000::bigint)$$,
  'cash flow keeps allowances separate');

select is(
  (select count(*)::int from app_reports.finance_series('2026-07-01', '2026-07-31', 'day')),
  3,
  'finance series buckets by business date');

select results_eq(
  $$select estimated_minor, actual_amount_minor from app_reports.salary_comparison_report('2026-07-01', '2026-07-31')$$,
  $$values (1000000::bigint, null::bigint)$$,
  'salary comparison reads finalized snapshot');

select results_eq(
  $$select overtime_minutes, overtime_amount_minor from app_reports.salary_period_work_report('2026-07-01', '2026-07-31')$$,
  $$values (120::bigint, 25000::bigint)$$,
  'salary work report groups overtime into the period');

select is(
  (select count(*)::int from app_reports.income_amounts_by_category('2026-07-01', '2026-07-31')),
  1,
  'income category report includes freelance income');

select is(
  (select count(*)::int from app_reports.account_balance_history((select id from app_finance.accounts where name = 'Current Balance'), '2026-07-07', '2026-07-09')),
  3,
  'account balance history returns one point per day');

select * from finish();
rollback;
