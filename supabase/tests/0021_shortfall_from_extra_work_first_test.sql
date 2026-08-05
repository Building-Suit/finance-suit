begin;
create extension if not exists pgtap with schema extensions;

select plan(25);

-- ---------------------------------------------------------------------------
-- A salary owed 44,000 (40,000 base + 4,000 extra work) paid as 40,000 must
-- take the shortfall out of the extra-work pay first, so nothing routes to
-- the extra-work account while the ordinary splits keep running.
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000054',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'shortfall-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Shortfall Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000055',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'shortfall-rollover@test.local', '',
  now(), '{"provider":"email","providers":["email"]}',
  '{"display_name":"Shortfall Rollover"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000054","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Shortfall Owner', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 4000000, 1::smallint, 5::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Salary Account', 'current', 0, false
  )$$,
  'user setup succeeds'
);

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-000000000054', 'Extra Savings', 'savings', 'EGP', 0),
  ('00000000-0000-0000-0000-000000000054', 'Splits', 'savings', 'EGP', 0);

select lives_ok(
  $$select app_finance.save_income_source_v4(
    'Salary', 'salary', 4000000, 'EGP', 5::smallint, date '2026-06-01',
    7::smallint,
    (select account_id from app_finance.account_balances
      where name = 'Salary Account'),
    null,
    jsonb_build_array(
      jsonb_build_object(
        'destination_account_id',
          (select account_id from app_finance.account_balances
            where name = 'Splits'),
        'allocation_method', 'percentage',
        'percentage_basis_points', 1000,
        'calculation_basis', 'original'
      )
    ),
    null, null, true, false,
    (select account_id from app_finance.account_balances
      where name = 'Extra Savings'),
    false, null
  )$$,
  'salary automation protects extra-work pay from the percentage split'
);

-- 40,000 base + 3,000 extra days + 1,000 overtime = 44,000 owed.
insert into app_salary.salary_periods (
  id, user_id, period_start, period_end, expected_payment_date, status,
  snapshot, finalized_at
) values (
  '00000000-0000-0000-0000-00000000e601',
  '00000000-0000-0000-0000-000000000054',
  date '2026-05-01', date '2026-05-31', date '2026-06-05', 'finalized',
  '{"base_salary_minor":4000000,"extra_day_amount_minor":300000,
    "overtime_amount_minor":100000,"holiday_amount_minor":0,
    "bonuses_minor":0,"deductions_minor":0,"total_minor":4400000}',
  now()
);

insert into app_finance.income_occurrences (
  id, user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-00000000d601',
  '00000000-0000-0000-0000-000000000054',
  (select id from app_finance.income_sources where name = 'Salary'),
  date '2026-06-05', 4000000
);

select lives_ok(
  $$select app_finance.accept_income_occurrence_partial(
    '00000000-0000-0000-0000-00000000d601', 4000000, 4400000,
    date '2026-06-05', null, '00000000-0000-0000-0000-00000000e601')$$,
  'a short salary can be accepted partially'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where is_extra_work_routing),
  0,
  'a shortfall eats the extra-work pay before anything routes to savings'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Extra Savings'),
  0::bigint,
  'the extra-work account stays untouched while money is missing'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Splits'),
  400000::bigint,
  'the percentage split still runs on everything that arrived'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Salary Account'),
  3600000::bigint,
  'the deposit account keeps the received salary minus its splits'
);
select results_eq(
  $$select status::text, actual_amount_minor from app_salary.salary_periods
    where id = '00000000-0000-0000-0000-00000000e601'$$,
  $$values ('paid'::text, 4000000::bigint)$$,
  'the salary period records what actually arrived'
);
select results_eq(
  $$select status::text, expected_amount_minor
    from app_finance.income_occurrences
    where remainder_of_occurrence_id = '00000000-0000-0000-0000-00000000d601'$$,
  $$values ('pending'::text, 400000::bigint)$$,
  'only the missing 4,000 stays pending'
);

-- ---------------------------------------------------------------------------
-- The withheld extra-work pay arrives with the remainder
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      where remainder_of_occurrence_id =
        '00000000-0000-0000-0000-00000000d601'),
    400000, date '2026-06-20', null, null)$$,
  'the remainder can be accepted when the rest of the money lands'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Extra Savings'),
  400000::bigint,
  'the late money carries the extra-work pay that was held back'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Splits'),
  400000::bigint,
  'extra-work pay never enters the percentage split'
);
select is(
  (select sum(amount_minor)::bigint from app_finance.financial_transactions
    where transaction_kind <> 'transfer'),
  4400000::bigint,
  'both acceptances together book the full amount owed'
);

-- ---------------------------------------------------------------------------
-- A shortfall bigger than the extra-work pay also bites the base salary
-- ---------------------------------------------------------------------------

insert into app_salary.salary_periods (
  id, user_id, period_start, period_end, expected_payment_date, status,
  snapshot, finalized_at
) values (
  '00000000-0000-0000-0000-00000000e602',
  '00000000-0000-0000-0000-000000000054',
  date '2026-06-01', date '2026-06-30', date '2026-07-05', 'finalized',
  '{"base_salary_minor":4000000,"extra_day_amount_minor":300000,
    "overtime_amount_minor":100000,"holiday_amount_minor":0,
    "bonuses_minor":0,"deductions_minor":0,"total_minor":4400000}',
  now()
);

insert into app_finance.income_occurrences (
  id, user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-00000000d602',
  '00000000-0000-0000-0000-000000000054',
  (select id from app_finance.income_sources where name = 'Salary'),
  date '2026-07-05', 4000000
);

select lives_ok(
  $$select app_finance.accept_income_occurrence_partial(
    '00000000-0000-0000-0000-00000000d602', 3800000, 4400000,
    date '2026-07-05', null, '00000000-0000-0000-0000-00000000e602')$$,
  'a 6,000 shortfall is accepted partially'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Extra Savings'),
  400000::bigint,
  'nothing new routes to the extra-work account while money is missing'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Splits'),
  780000::bigint,
  'the split runs on the full amount received once extra work is exhausted'
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      where remainder_of_occurrence_id =
        '00000000-0000-0000-0000-00000000d602'),
    600000, date '2026-07-20', null, null)$$,
  'the second remainder is accepted when the rest arrives'
);
select results_eq(
  $$select
      (select balance_minor from app_finance.account_balances
        where name = 'Extra Savings'),
      (select balance_minor from app_finance.account_balances
        where name = 'Splits')$$,
  $$values (800000::bigint, 800000::bigint)$$,
  'a partial payment plus its remainder land exactly where one full payment '
  'would have'
);

-- ---------------------------------------------------------------------------
-- The previous balance rolls over once per payment, not once per remainder
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000055","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Shortfall Rollover', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 4000000, 1::smallint, 5::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Salary Account', 'current', 25000, false
  )$$,
  'the rollover user is set up with a previous balance'
);

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000000055', 'Rollover Savings', 'savings',
  'EGP', 0
);

select lives_ok(
  $$select app_finance.save_income_source_v4(
    'Salary', 'salary', 4000000, 'EGP', 5::smallint, date '2026-06-01',
    7::smallint,
    (select account_id from app_finance.account_balances
      where name = 'Salary Account'),
    null, '[]'::jsonb, null, null, true, true, null, true,
    (select account_id from app_finance.account_balances
      where name = 'Rollover Savings')
  )$$,
  'salary automation rolls the previous balance over'
);

insert into app_salary.salary_periods (
  id, user_id, period_start, period_end, expected_payment_date, status,
  snapshot, finalized_at
) values (
  '00000000-0000-0000-0000-00000000e701',
  '00000000-0000-0000-0000-000000000055',
  date '2026-05-01', date '2026-05-31', date '2026-06-05', 'finalized',
  '{"base_salary_minor":4000000,"extra_day_amount_minor":400000,
    "overtime_amount_minor":0,"holiday_amount_minor":0,
    "bonuses_minor":0,"deductions_minor":0,"total_minor":4400000}',
  now()
);

insert into app_finance.income_occurrences (
  id, user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-00000000d701',
  '00000000-0000-0000-0000-000000000055',
  (select id from app_finance.income_sources where name = 'Salary'),
  date '2026-06-05', 4000000
);

select lives_ok(
  $$select app_finance.accept_income_occurrence_partial(
    '00000000-0000-0000-0000-00000000d701', 4000000, 4400000,
    date '2026-06-05', null, '00000000-0000-0000-0000-00000000e701')$$,
  'the rollover user accepts a short salary'
);
select is(
  (select count(*)::integer from app_finance.financial_transactions
    where is_balance_rollover),
  1,
  'the received part rolls the previous balance over once'
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      where remainder_of_occurrence_id =
        '00000000-0000-0000-0000-00000000d701'),
    400000, date '2026-06-20', null, null)$$,
  'the rollover user accepts the remainder'
);
select is(
  (select count(*)::integer from app_finance.financial_transactions
    where is_balance_rollover),
  1,
  'late money never sweeps the account a second time'
);
select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Rollover Savings'),
  25000::bigint,
  'only the balance that existed before the salary was rolled over'
);

select * from finish();
rollback;
