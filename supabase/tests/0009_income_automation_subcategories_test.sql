begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000019',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'income@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Income User"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000019","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Income User', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 1000000, 1::smallint, 25::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Current Balance', 'current', 0, false
  )$$,
  'the original onboarding RPC remains compatible'
);

select is(
  (select count(*)::integer from app_finance.transaction_categories
    where parent_category_id is not null),
  0,
  'all existing seeded categories remain regular top-level categories'
);

insert into app_finance.transaction_categories (
  user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-000000000019', 'Home', 'expense'
);

insert into app_finance.transaction_categories (
  user_id, name, category_kind, parent_category_id
) values (
  '00000000-0000-0000-0000-000000000019', 'Repairs', 'expense',
  (select id from app_finance.transaction_categories where name = 'Home')
);

select ok(
  (select parent_category_id is not null
    from app_finance.transaction_categories where name = 'Repairs'),
  'a same-kind one-level subcategory is accepted'
);

select throws_ok(
  $$insert into app_finance.transaction_categories (
      user_id, name, category_kind, parent_category_id
    ) values (
      '00000000-0000-0000-0000-000000000019', 'Urgent', 'expense',
      (select id from app_finance.transaction_categories where name = 'Repairs')
    )$$,
  'P0001', null,
  'a nested subcategory is rejected'
);

select throws_ok(
  $$insert into app_finance.transaction_categories (
      user_id, name, category_kind, parent_category_id
    ) values (
      '00000000-0000-0000-0000-000000000019', 'Wrong kind', 'income',
      (select id from app_finance.transaction_categories where name = 'Home')
    )$$,
  'P0001', null,
  'a subcategory cannot cross category types'
);

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000000019',
  'Savings', 'savings', 'EGP', 0
);

select lives_ok(
  $$select app_finance.save_income_source(
    'Monthly allowance', 'allowance', 100000, 'EGP', 15::smallint,
    date_trunc('month', current_date)::date, 7::smallint,
    (select id from app_finance.accounts where name = 'Current Balance'),
    (select id from app_finance.transaction_categories
      where name = 'Other' and category_kind = 'income'),
    jsonb_build_array(jsonb_build_object(
      'destination_account_id',
        (select id from app_finance.accounts where name = 'Savings'),
      'percentage_basis_points', 3000
    )), null, null
  )$$,
  'a recurring allowance with a 30 percent split is saved atomically'
);

select is(
  (select sum(percentage_basis_points)::integer
    from app_finance.income_source_allocations),
  3000,
  'the split percentage is stored in basis points'
);

select lives_ok(
  $$select app_finance.materialize_income_occurrences(
    (date_trunc('month', current_date) + interval '1 month 20 days')::date
  )$$,
  'monthly pending occurrences are materialized'
);

select is(
  (select count(*)::integer from app_finance.income_occurrences
    where status = 'pending'),
  2,
  'the current and next monthly decisions are pending'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions),
  0,
  'pending income does not affect transactions or balances'
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      order by scheduled_on limit 1),
    100000, current_date, 'Arrived', null
  )$$,
  'the user can explicitly accept an occurrence'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions),
  2,
  'acceptance creates one income and one split transfer'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Current Balance'),
  70000::bigint,
  'the remainder stays in the primary account'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Savings'),
  30000::bigint,
  'the configured percentage reaches the split account'
);

select is(
  (select income_minor from app_reports.cash_flow_summary(
    current_date - 1, current_date + 1)),
  100000::bigint,
  'automatic transfers do not double-count income'
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      where status = 'accepted' limit 1),
    100000, current_date, 'Retry', null
  )$$,
  'acceptance is idempotent on retry'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions),
  2,
  'an idempotent retry creates no duplicate transactions'
);

select lives_ok(
  $$select app_finance.skip_income_occurrence(
    (select id from app_finance.income_occurrences
      where status = 'pending' order by scheduled_on limit 1)
  )$$,
  'a delayed or unwanted occurrence can be skipped explicitly'
);

select is(
  (select count(*)::integer from app_finance.income_occurrences
    where status = 'skipped'),
  1,
  'skipping records the decision without a transaction'
);

reset role;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000020',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'allowance@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Allowance User"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000020","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding_v2(
    'Allowance User', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], false, 0, 1::smallint, 20::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Wallet', 'current', 0, false,
    'allowance', 'Family allowance', 50000, 20::smallint, 5::smallint
  )$$,
  'onboarding supports an allowance without enabling salary'
);

select is(
  (select salary_enabled from app_salary.salary_settings
    where user_id = '00000000-0000-0000-0000-000000000020'),
  false,
  'allowance onboarding leaves salary disabled'
);

select is(
  (select count(*)::integer from app_finance.income_sources
    where user_id = '00000000-0000-0000-0000-000000000020'
      and source_kind = 'allowance' and is_active),
  1,
  'allowance onboarding creates an active automated source'
);

update app_salary.salary_settings
set salary_enabled = true, base_salary_minor = 75000
where user_id = '00000000-0000-0000-0000-000000000020';

select is(
  (select expected_amount_minor from app_finance.income_sources
    where user_id = '00000000-0000-0000-0000-000000000020'
      and source_kind = 'salary' and is_active),
  75000::bigint,
  'enabling salary in settings creates its automation beside allowance'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000019","role":"authenticated"}';

select lives_ok(
  $$select app_finance.save_income_source(
    'Salary', 'salary', 200000, 'EGP', 25::smallint, current_date,
    7::smallint,
    (select id from app_finance.accounts where name = 'Current Balance'),
    (select id from app_finance.transaction_categories
      where name = 'Salary' and category_kind = 'income'),
    '[]'::jsonb, null, null
  )$$,
  'a salary source can coexist with another income source'
);

update app_salary.salary_settings
set salary_enabled = false
where user_id = '00000000-0000-0000-0000-000000000019';

select is(
  (select is_active from app_finance.income_sources
    where user_id = '00000000-0000-0000-0000-000000000019'
      and source_kind = 'salary'),
  false,
  'disabling salary also disables its automation source'
);

update app_finance.income_sources
set is_active = true
where user_id = '00000000-0000-0000-0000-000000000019'
  and source_kind = 'salary';

select is(
  (select salary_enabled from app_salary.salary_settings
    where user_id = '00000000-0000-0000-0000-000000000019'),
  true,
  're-enabling a salary source also enables salary settings'
);

select * from finish();
rollback;
