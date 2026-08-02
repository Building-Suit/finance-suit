begin;
create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000042',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'salary-rollover@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Salary Rollover User"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000042","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Salary Rollover User', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 0, 1::smallint, 25::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Salary Account', 'current', 25000, false
  )$$,
  'user setup succeeds'
);

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-000000000042', 'Savings', 'savings', 'EGP', 0),
  ('00000000-0000-0000-0000-000000000042', 'Extra Savings', 'savings', 'EGP', 0),
  ('00000000-0000-0000-0000-000000000042', 'Bills', 'bank', 'EGP', 0);

select lives_ok(
  $$select app_finance.save_income_source_v4(
    'Salary', 'salary', 100000, 'EGP', 25::smallint, current_date,
    7::smallint,
    (select account_id from app_finance.account_balances
      where name = 'Salary Account'),
    null,
    jsonb_build_array(
      jsonb_build_object(
        'destination_account_id',
          (select account_id from app_finance.account_balances
            where name = 'Bills'),
        'allocation_method', 'fixed',
        'fixed_amount_minor', 30000
      )
    ),
    null, null, true, false,
    (select account_id from app_finance.account_balances
      where name = 'Extra Savings'),
    true,
    (select account_id from app_finance.account_balances
      where name = 'Savings')
  )$$,
  'salary automation saves rollover and protected extra-work routing'
);

select ok(
  (select rollover_balance_enabled from app_finance.income_sources
    where name = 'Salary'),
  'rollover switch is persisted'
);

insert into app_salary.salary_periods (
  user_id, period_start, period_end, expected_payment_date, status,
  snapshot, finalized_at
) values (
  '00000000-0000-0000-0000-000000000042',
  current_date - 30, current_date - 1, current_date, 'finalized',
  '{"extra_day_amount_minor":10000,"overtime_amount_minor":5000,"holiday_amount_minor":5000}',
  now()
);

insert into app_finance.income_occurrences (
  user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-000000000042',
  (select id from app_finance.income_sources where name = 'Salary'),
  current_date, 100000
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences),
    120000,
    current_date,
    null,
    (select id from app_salary.salary_periods)
  )$$,
  'accepting salary applies rollover, fixed split, and extra-work routing'
);

select is(
  (select amount_minor from app_finance.financial_transactions
    where is_balance_rollover),
  25000::bigint,
  'only the positive balance that existed before salary is rolled over'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where is_balance_rollover),
  1,
  'one auditable rollover transfer is created'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Savings'),
  25000::bigint,
  'previous balance reaches the selected savings account'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Bills'),
  30000::bigint,
  'fixed split still reaches its destination'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Extra Savings'),
  20000::bigint,
  'protected extra-work earnings route with fixed splits'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Salary Account'),
  70000::bigint,
  'only the new salary remainder stays in the deposit account'
);

select is(
  (select income_minor from app_reports.cash_flow_summary(
    current_date - 1, current_date + 1)),
  120000::bigint,
  'rollover and allocations do not double-count income'
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences),
    120000,
    current_date,
    null,
    (select id from app_salary.salary_periods)
  )$$,
  'salary acceptance remains idempotent'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where is_balance_rollover),
  1,
  'retry creates no duplicate rollover'
);

select lives_ok(
  $$select app_finance.save_income_source_v4(
    'Salary', 'salary', 100000, 'EGP', 25::smallint, current_date,
    7::smallint,
    (select account_id from app_finance.account_balances
      where name = 'Salary Account'),
    null,
    jsonb_build_array(
      jsonb_build_object(
        'destination_account_id',
          (select account_id from app_finance.account_balances
            where name = 'Bills'),
        'allocation_method', 'fixed',
        'fixed_amount_minor', 30000
      )
    ),
    null,
    (select id from app_finance.income_sources where name = 'Salary'),
    true, false,
    (select account_id from app_finance.account_balances
      where name = 'Extra Savings'),
    true,
    (select account_id from app_finance.account_balances
      where name = 'Savings')
  )$$,
  'an accepted salary automation remains editable'
);

select throws_ok(
  $$select app_finance.save_income_source_v4(
    'Salary', 'salary', 100000, 'EGP', 25::smallint, current_date,
    7::smallint,
    (select account_id from app_finance.account_balances
      where name = 'Salary Account'),
    null, '[]'::jsonb, null,
    (select id from app_finance.income_sources where name = 'Salary'),
    true, false, null, true,
    (select account_id from app_finance.account_balances where name = 'Bills')
  )$$,
  'P0001', null,
  'rollover destination must be a savings account'
);

select * from finish();
rollback;
