begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000021',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'controls@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Controls User"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000021","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Controls User', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 1000000, 1::smallint, 25::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Wallet', 'current', 0, false
  )$$,
  'user setup succeeds'
);

insert into app_finance.transaction_categories (
  user_id, name, category_kind
) values ('00000000-0000-0000-0000-000000000021', 'Home', 'expense');

insert into app_finance.transaction_categories (
  user_id, name, category_kind, parent_category_id
) values (
  '00000000-0000-0000-0000-000000000021', 'Repairs', 'expense',
  (select id from app_finance.transaction_categories where name = 'Home')
);

select throws_ok(
  $$update app_finance.transaction_categories set is_archived = true
    where name = 'Home'$$,
  'P0001', null,
  'a parent with an active child cannot be archived'
);

select lives_ok(
  $$update app_finance.transaction_categories set is_archived = true
    where name = 'Repairs'$$,
  'a child can be archived independently'
);

select lives_ok(
  $$update app_finance.transaction_categories set is_archived = true
    where name = 'Home'$$,
  'the parent can be archived after its children'
);

select throws_ok(
  $$update app_finance.transaction_categories set is_archived = false
    where name = 'Repairs'$$,
  'P0001', null,
  'a child cannot be restored while its parent is archived'
);

select lives_ok(
  $$update app_finance.transaction_categories set is_archived = false
    where name = 'Home'$$,
  'the parent can be restored first'
);

select lives_ok(
  $$select app_finance.save_income_source_v2(
    'Paused allowance', 'allowance', 50000, 'EGP', 15::smallint,
    current_date, 7::smallint,
    (select id from app_finance.accounts where name = 'Wallet'),
    null, '[]'::jsonb, null, null, false
  )$$,
  'an automation can be created paused'
);

select is(
  (select is_active from app_finance.income_sources
    where name = 'Paused allowance'),
  false,
  'the paused state is persisted'
);

select lives_ok(
  $$select app_finance.save_income_source_v2(
    'Paused allowance edited', 'allowance', 60000, 'EGP', 16::smallint,
    current_date, 3::smallint,
    (select id from app_finance.accounts where name = 'Wallet'),
    null, '[]'::jsonb, null,
    (select id from app_finance.income_sources where name = 'Paused allowance'),
    false
  )$$,
  'editing a paused automation does not resume it'
);

select lives_ok(
  $$select app_finance.save_income_source_v2(
    'My salary', 'salary', 1200000, 'EGP', 25::smallint,
    current_date, 7::smallint,
    (select id from app_finance.accounts where name = 'Wallet'),
    null, '[]'::jsonb, null, null, false
  )$$,
  'salary automation can be paused independently from having a salary'
);

select is(
  (select count(*)::integer from app_finance.income_sources
    where source_kind = 'salary'),
  1,
  'salary synchronization does not create a duplicate active source'
);

select is(
  (select is_active from app_finance.income_sources
    where source_kind = 'salary'),
  false,
  'salary synchronization preserves the paused state'
);

select * from finish();
rollback;
