begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000041',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'advanced-splits@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Advanced Splits User"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000041","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Advanced Splits User', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 0, 1::smallint, 25::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Wallet', 'current', 0, false
  )$$,
  'user setup succeeds'
);

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-000000000041', 'Savings', 'savings', 'EGP', 0),
  ('00000000-0000-0000-0000-000000000041', 'Bills', 'bank', 'EGP', 0);

select lives_ok(
  $$select app_finance.save_income_source_v3(
    'Project retainer', 'freelance', 10000, 'EGP', 1::smallint,
    current_date, 7::smallint,
    (select account_id from app_finance.account_balances where name = 'Wallet'),
    null,
    jsonb_build_array(
      jsonb_build_object(
        'destination_account_id', (select account_id from app_finance.account_balances where name = 'Savings'),
        'allocation_method', 'percentage',
        'calculation_basis', 'original',
        'percentage_basis_points', 5000
      ),
      jsonb_build_object(
        'destination_account_id', (select account_id from app_finance.account_balances where name = 'Bills'),
        'allocation_method', 'percentage',
        'calculation_basis', 'remaining',
        'percentage_basis_points', 5000
      )
    ),
    null, null, true
  )$$,
  'v3 saves ordered percentage rules'
);

select is(
  (select count(*)::integer
   from app_finance.income_source_allocations
   where income_source_id = (
     select id from app_finance.income_sources where name = 'Project retainer'
   )
     and allocation_method = 'percentage'
     and calculation_basis in ('original', 'remaining')),
  2,
  'allocation rows store method and basis'
);

insert into app_finance.income_occurrences (
  user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-000000000041',
  (select id from app_finance.income_sources where name = 'Project retainer'),
  current_date, 10000
);

select lives_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      where income_source_id = (
        select id from app_finance.income_sources where name = 'Project retainer'
      )),
    10000, current_date
  )$$,
  'accepting income applies advanced splits'
);

select bag_eq(
  $$select amount_minor::integer
    from app_finance.financial_transactions
    where transaction_kind = 'transfer'
    order by amount_minor$$,
  $$values (2500), (5000)$$,
  'remaining-basis percentage uses the current remainder'
);

select lives_ok(
  $$select app_finance.save_income_source_v3(
    'Over split', 'other', 10000, 'EGP', 2::smallint,
    current_date, 7::smallint,
    (select account_id from app_finance.account_balances where name = 'Wallet'),
    null,
    jsonb_build_array(
      jsonb_build_object(
        'destination_account_id', (select account_id from app_finance.account_balances where name = 'Savings'),
        'allocation_method', 'fixed',
        'fixed_amount_minor', 11000
      )
    ),
    null, null, true
  )$$,
  'fixed split source can be saved for runtime validation'
);

insert into app_finance.income_occurrences (
  user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-000000000041',
  (select id from app_finance.income_sources where name = 'Over split'),
  current_date, 10000
);

select throws_ok(
  $$select app_finance.accept_income_occurrence(
    (select id from app_finance.income_occurrences
      where income_source_id = (
        select id from app_finance.income_sources where name = 'Over split'
      )),
    10000, current_date
  )$$,
  'P0001', null,
  'runtime rejects over-allocation atomically'
);

select lives_ok(
  $$select app_finance.save_income_source_v3(
    'Over split', 'allowance', 10000, 'EGP', 2::smallint,
    current_date, 7::smallint,
    (select account_id from app_finance.account_balances where name = 'Wallet'),
    null, '[]'::jsonb, null,
    (select id from app_finance.income_sources where name = 'Over split'),
    true
  )$$,
  'income type can be edited'
);

select is(
  (select count(*)::integer
   from app_finance.income_occurrences
   where income_source_id = (
     select id from app_finance.income_sources where name = 'Over split'
   )
     and status = 'pending'),
  0,
  'changing the income type deletes undecided pending occurrences'
);

select * from finish();
rollback;
