begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

-- ---------------------------------------------------------------------------
-- A salary accepted for less than the period owed, with no remainder tracked
-- (the shape every acceptance had before partial acceptance shipped), gets
-- the missing money back on the pending list.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000056',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'backfill-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Backfill Owner"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000056","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Backfill Owner', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 4000000, 1::smallint, 5::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Salary Account', 'current', 0, false
  )$$,
  'user setup succeeds'
);

select lives_ok(
  $$select app_finance.save_income_source_v4(
    'Salary', 'salary', 4000000, 'EGP', 5::smallint, current_date - 40,
    7::smallint,
    (select account_id from app_finance.account_balances
      where name = 'Salary Account'),
    null, '[]'::jsonb, null, null, true, true, null, false, null
  )$$,
  'the salary automation is configured'
);

insert into app_salary.salary_periods (
  id, user_id, period_start, period_end, expected_payment_date, status,
  snapshot, finalized_at
) values (
  '00000000-0000-0000-0000-00000000e801',
  '00000000-0000-0000-0000-000000000056',
  current_date - 40, current_date - 11, current_date - 10, 'finalized',
  '{"base_salary_minor":4000000,"extra_day_amount_minor":400000,
    "overtime_amount_minor":0,"holiday_amount_minor":0,
    "bonuses_minor":0,"deductions_minor":0,"total_minor":4400000}',
  now()
);

insert into app_finance.income_occurrences (
  id, user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-00000000d801',
  '00000000-0000-0000-0000-000000000056',
  (select id from app_finance.income_sources where name = 'Salary'),
  current_date - 10, 4000000
);

-- Accepted plainly for less than the period owed: no remainder is created,
-- which is exactly the state older acceptances are stuck in.
select lives_ok(
  $$select app_finance.accept_income_occurrence(
    '00000000-0000-0000-0000-00000000d801', 4000000, current_date - 10,
    null, '00000000-0000-0000-0000-00000000e801')$$,
  'the salary is accepted for less than the period owed'
);
select is(
  (select count(*)::integer from app_finance.income_occurrences
    where remainder_of_occurrence_id is not null),
  0,
  'a plain acceptance tracks no remainder on its own'
);

reset role;

select is(
  app_private.backfill_untracked_salary_shortfalls(),
  1,
  'the backfill finds the untracked shortfall'
);
select results_eq(
  $$select status::text, expected_amount_minor, scheduled_on
    from app_finance.income_occurrences
    where remainder_of_occurrence_id = '00000000-0000-0000-0000-00000000d801'$$,
  $$values ('pending'::text, 400000::bigint, current_date - 10)$$,
  'the missing money returns to the pending list'
);
select is(
  app_private.backfill_untracked_salary_shortfalls(),
  0,
  'running the backfill again changes nothing'
);

select * from finish();
rollback;
