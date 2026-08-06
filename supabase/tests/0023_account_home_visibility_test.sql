begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

select has_column('app_finance', 'accounts', 'hide_from_home',
  'accounts carry the home-visibility flag');
select col_default_is('app_finance', 'accounts', 'hide_from_home', 'false',
  'accounts stay visible on Home unless the user opts out');
select has_column('app_finance', 'account_balances', 'hide_from_home',
  'the balances view exposes the home-visibility flag');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000057',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'home-visibility@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Home Visibility"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000057","role":"authenticated"}';

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000000057', 'Deposit Box', 'savings', 'EGP',
  100000
);

select results_eq(
  $$select hide_from_home from app_finance.account_balances
    where name = 'Deposit Box'$$,
  $$values (false)$$,
  'a new account shows on Home by default'
);

update app_finance.accounts
  set hide_from_home = true
  where name = 'Deposit Box';

select results_eq(
  $$select hide_from_home, balance_minor from app_finance.account_balances
    where name = 'Deposit Box'$$,
  $$values (true, 100000::bigint)$$,
  'hiding from Home flips the flag without touching the balance'
);
select results_eq(
  $$select count(*)::integer from app_finance.accounts
    where hide_from_home$$,
  $$values (1)$$,
  'the owner can manage home visibility directly'
);

select * from finish();
rollback;
