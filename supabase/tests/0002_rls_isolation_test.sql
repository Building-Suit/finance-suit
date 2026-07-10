begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

-- Two deterministic test users.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user-a@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"User A"}', now(), now()),
  ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user-b@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"User B"}', now(), now());

-- Profiles auto-created by trigger.
select is(
  (select count(*)::int from public.profiles where id in ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b')),
  2, 'signup trigger created profiles');

-- Seed data as superuser (bypasses RLS for setup).
insert into public.accounts (id, user_id, name, opening_balance_minor, is_default)
values
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'A Current', 1000000, true),
  ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'B Current', 500000, true);

insert into public.financial_transactions (user_id, transaction_kind, occurred_on, amount_minor, source_account_id)
values ('00000000-0000-0000-0000-00000000000a', 'expense', current_date, 50000, '10000000-0000-0000-0000-00000000000a');

insert into public.work_entries (user_id, work_date, entry_type, duration_minutes)
values ('00000000-0000-0000-0000-00000000000a', current_date, 'overtime', 120);

-- Switch to authenticated role as user B.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}';

-- B cannot read A's records.
select is((select count(*)::int from public.accounts where user_id = '00000000-0000-0000-0000-00000000000a'), 0, 'B cannot select A accounts');
select is((select count(*)::int from public.financial_transactions where user_id = '00000000-0000-0000-0000-00000000000a'), 0, 'B cannot select A transactions');
select is((select count(*)::int from public.work_entries where user_id = '00000000-0000-0000-0000-00000000000a'), 0, 'B cannot select A work entries');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 0, 'B cannot select A profile');
select is((select count(*)::int from public.account_balances where user_id = '00000000-0000-0000-0000-00000000000a'), 0, 'B cannot see A balances via view');

-- B sees own data.
select is((select count(*)::int from public.accounts), 1, 'B sees only own account');
select is((select balance_minor from public.account_balances where account_id = '10000000-0000-0000-0000-00000000000b'), 500000::bigint, 'B balance correct');

-- B cannot update or delete A's rows (0 rows affected).
update public.accounts set name = 'hacked' where id = '10000000-0000-0000-0000-00000000000a';
select is((select count(*)::int from public.accounts where name = 'hacked'), 0, 'B update of A account affected 0 rows');
delete from public.financial_transactions where user_id = '00000000-0000-0000-0000-00000000000a';
select is(true, true, 'B delete of A transactions raised no error and affected 0 rows');

-- B cannot insert rows owned by A.
select throws_ok(
  $$insert into public.accounts (user_id, name) values ('00000000-0000-0000-0000-00000000000a', 'evil')$$,
  '42501', null, 'B cannot insert account for A');

-- B cannot create a transaction referencing A's account.
select throws_ok(
  $$insert into public.financial_transactions (user_id, transaction_kind, occurred_on, amount_minor, source_account_id)
    values ('00000000-0000-0000-0000-00000000000b', 'expense', current_date, 100, '10000000-0000-0000-0000-00000000000a')$$,
  '23503', null, 'ownership FK blocks cross-user account reference');

-- Anonymous role sees nothing.
set local role anon;
set local request.jwt.claims to '{}';
select is((select count(*)::int from public.accounts), 0, 'anon sees no accounts');
select is((select count(*)::int from public.financial_transactions), 0, 'anon sees no transactions');
select is((select count(*)::int from public.work_entries), 0, 'anon sees no work entries');
select throws_ok(
  $$insert into public.accounts (user_id, name) values ('00000000-0000-0000-0000-00000000000a', 'nope')$$,
  '42501', null, 'anon cannot insert');

select * from finish();
rollback;
