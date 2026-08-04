begin;
create extension if not exists pgtap with schema extensions;

select plan(5);

-- The production verification rejects any app_* table without RLS; this
-- mirrors that check in CI so a future migration can never ship one.

select results_eq(
  $$select rowsecurity from pg_tables
    where schemaname = 'app_finance'
      and tablename = 'credit_card_statement_cycles'$$,
  $$values (true)$$,
  'statement cycles enforce row level security'
);
select results_eq(
  $$select rowsecurity from pg_tables
    where schemaname = 'app_finance'
      and tablename = 'credit_card_statement_items'$$,
  $$values (true)$$,
  'statement items enforce row level security'
);
select results_eq(
  $$select rowsecurity from pg_tables
    where schemaname = 'app_finance'
      and tablename = 'credit_card_statement_allocations'$$,
  $$values (true)$$,
  'statement allocations enforce row level security'
);
select results_eq(
  $$select count(*)::integer from pg_tables
    where schemaname like 'app\_%' escape '\'
      and rowsecurity = false$$,
  $$values (0)$$,
  'every private app_* table has row level security enabled'
);

-- Direct table reads across users must come back empty, not filtered by a
-- lucky join: seed one owner cycle, then read it as another user.

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000048',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'rls-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"RLS Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000049',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'rls-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"RLS Intruder"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000048","role":"authenticated"}';

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c201',
  '00000000-0000-0000-0000-000000000048',
  'RLS Spending', 'expense'
);
select app_finance.save_credit_facility(
  'RLS Card', 'credit_card', 'EGP', 1000000, 10::smallint,
  25::smallint, null, 3::smallint, null, null);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'RLS Card'),
  'Groceries', '00000000-0000-0000-0000-00000000c201',
  date '2026-03-10', 40000, null, null);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000049","role":"authenticated"}';

select results_eq(
  $$select
      (select count(*) from app_finance.credit_card_statement_cycles)
      + (select count(*) from app_finance.credit_card_statement_items)
      + (select count(*) from app_finance.credit_card_statement_allocations)$$,
  $$values (0::bigint)$$,
  'statement rows are invisible to other users on direct table reads'
);

select * from finish();
rollback;
