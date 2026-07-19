begin;
create extension if not exists pgtap with schema extensions;

select plan(8);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-00000000000f',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'user-f@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"User F"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000000f","role":"authenticated"}';

select app_core.complete_onboarding(
  'User F', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
  1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
  'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
  'Current Balance', 'current', 100000, false
);

select lives_ok(
  $$select app_finance.save_held_amount(
    'i_owe', 2500, 'EGP', 'Ahmed', current_date, 'Held expense', null,
    (select id from app_finance.accounts where name = 'Current Balance')
  )$$,
  'standalone payable is saved atomically'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions),
  1,
  'standalone hold creates one actual transaction'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Current Balance'),
  97500::bigint,
  'payable hold immediately reduces account balance'
);

select ok(
  (select manages_transaction and transaction_id is not null
    from app_finance.held_amounts where title = 'Held expense'),
  'held amount owns its generated transaction'
);

select lives_ok(
  $$select app_finance.save_held_amount(
    'owed_to_me', 5000, 'EGP', 'Mona', current_date, 'Held income', null,
    (select id from app_finance.accounts where name = 'Current Balance')
  )$$,
  'standalone receivable is saved atomically'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Current Balance'),
  102500::bigint,
  'receivable hold immediately increases account balance'
);

select lives_ok(
  $$select app_finance.delete_held_amount(
    (select id from app_finance.held_amounts where title = 'Held expense')
  )$$,
  'deleting a managed hold succeeds'
);

select is(
  (select balance_minor from app_finance.account_balances
    where name = 'Current Balance'),
  105000::bigint,
  'deleting a managed hold removes its transaction and restores balance'
);

select * from finish();
rollback;
