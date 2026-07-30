begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matrix-salary@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matrix-allowance@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000033', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matrix-other@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000034', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matrix-none@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000035', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'matrix-invalid@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000031","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding_v2(
    'Salary Matrix', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
    true, 1200000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
    'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
    'Salary Wallet', 'current', 0, false,
    'salary', 'My salary', 1200000, 25::smallint, 7::smallint
  )$$,
  'salary onboarding completes'
);
select ok(
  (select is_default from app_finance.accounts where name = 'Salary Wallet'),
  'salary onboarding creates the default account'
);
select is(
  (select salary_enabled from app_salary.salary_settings where user_id = auth.uid()),
  true,
  'salary is enabled'
);
select is(
  (select count(*)::integer from app_finance.income_sources where source_kind = 'salary'),
  1,
  'salary onboarding reuses exactly one automation'
);
select is(
  (select expected_amount_minor::text || ':' || payment_day::text || ':' || is_active::text
   from app_finance.income_sources where source_kind = 'salary'),
  '1200000:25:true',
  'salary automation matches settings and is active'
);

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000032","role":"authenticated"}';
select lives_ok(
  $$select app_core.complete_onboarding_v2(
    'Allowance Matrix', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
    false, 0, 1::smallint, 10::smallint, 1::smallint, 22::smallint, 480,
    'manual', null, 'manual', null, 100, 200, 150, 'additional_pay',
    'Allowance Wallet', 'current', 0, false,
    'allowance', 'Family allowance', 75000, 10::smallint, 3::smallint
  )$$,
  'allowance onboarding ignores invalid hidden manual salary controls'
);
select ok((select is_default from app_finance.accounts where name = 'Allowance Wallet'), 'allowance account is default');
select is((select salary_enabled from app_salary.salary_settings where user_id = auth.uid()), false, 'allowance leaves salary disabled');
select is((select count(*)::integer from app_finance.income_sources), 1, 'allowance creates one source');
select is(
  (select source_kind::text || ':' || expected_amount_minor::text || ':' || payment_day::text || ':' || is_active::text
   from app_finance.income_sources),
  'allowance:75000:10:true',
  'allowance source has the normalized fields'
);

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000033","role":"authenticated"}';
select lives_ok(
  $$select app_core.complete_onboarding_v2(
    'Other Matrix', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
    false, 0, 1::smallint, 18::smallint, 1::smallint, 22::smallint, 480,
    'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
    'Other Wallet', 'current', 0, false,
    'other', 'Rental income', 88000, 18::smallint, 5::smallint
  )$$,
  'other-income onboarding completes'
);
select ok((select is_default from app_finance.accounts where name = 'Other Wallet'), 'other-income account is default');
select is((select salary_enabled from app_salary.salary_settings where user_id = auth.uid()), false, 'other income leaves salary disabled');
select is((select count(*)::integer from app_finance.income_sources), 1, 'other income creates one source');
select is(
  (select source_kind::text || ':' || expected_amount_minor::text || ':' || payment_day::text || ':' || is_active::text
   from app_finance.income_sources),
  'other:88000:18:true',
  'other source has the normalized fields'
);

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000034","role":"authenticated"}';
select lives_ok(
  $$select app_core.complete_onboarding_v2(
    'None Matrix', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
    false, 0, 1::smallint, 1::smallint, 1::smallint, 22::smallint, 480,
    'manual', null, 'manual', null, 100, 200, 150, 'additional_pay',
    'No Income Wallet', 'current', 0, false,
    null, null, null, null, 7::smallint
  )$$,
  'no-primary-income onboarding completes with hidden invalid salary controls'
);
select ok((select is_default from app_finance.accounts where name = 'No Income Wallet'), 'no-income account is default');
select is((select salary_enabled from app_salary.salary_settings where user_id = auth.uid()), false, 'no-income leaves salary disabled');
select is((select count(*)::integer from app_finance.income_sources), 0, 'no-income creates no source');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000035","role":"authenticated"}';
select throws_ok(
  $$select app_core.complete_onboarding_v2(
    'Invalid Matrix', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
    false, 0, 1::smallint, 1::smallint, 1::smallint, 22::smallint, 480,
    'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
    'Invalid Wallet', 'current', 0, false,
    'allowance', '', -1, 30::smallint, 7::smallint
  )$$,
  'P0001', null,
  'invalid income input fails before onboarding writes'
);
select is((select count(*)::integer from app_finance.accounts), 0, 'invalid onboarding rolls back its account');
select is(
  (select count(*)::integer from app_core.user_preferences
   where user_id = auth.uid() and onboarding_completed_at is not null),
  0,
  'invalid onboarding does not mark preferences complete'
);
select is((select count(*)::integer from app_finance.income_sources), 0, 'invalid onboarding rolls back its source');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000033","role":"authenticated"}';
select is(
  (select count(*)::integer from app_finance.income_sources where user_id = '00000000-0000-0000-0000-000000000031'),
  0,
  'RLS hides another user source'
);
select is_empty(
  $$update app_finance.income_sources set name = 'Stolen'
    where user_id = '00000000-0000-0000-0000-000000000031' returning id$$,
  'RLS prevents modifying another user source'
);

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-000000000031","role":"authenticated"}';
select throws_ok(
  $$update app_finance.income_sources set source_kind = 'other'
    where source_kind = 'salary'$$,
  'P0001', null,
  'an existing automation semantic type is immutable'
);

select ok(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'app_finance'
      and tablename = 'income_source_allocations'
  ),
  'income allocations are published for realtime invalidation'
);

select * from finish();
rollback;
