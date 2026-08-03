begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000043',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'typed-held@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Typed Held User"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000043","role":"authenticated"}';

select lives_ok(
  $$select app_core.complete_onboarding(
    'Typed Held User', 'EGP', 'Africa/Cairo', 'en', 6::smallint,
    '{5,6}'::smallint[], 0, 1::smallint, 25::smallint, 1::smallint,
    22::smallint, 480, 'derived', null, 'derived', null, 100, 200, 150,
    'additional_pay', 'Current', 'current', 100000, false
  )$$,
  'user setup succeeds'
);

insert into app_finance.transaction_categories (
  user_id, name, category_kind
) values
  ('00000000-0000-0000-0000-000000000043', 'Held Refund', 'income'),
  ('00000000-0000-0000-0000-000000000043', 'Disposable Held Category', 'income'),
  ('00000000-0000-0000-0000-000000000043', 'Held Groceries', 'expense');

select has_column(
  'app_finance', 'held_amounts', 'transaction_kind',
  'held amounts store their transaction kind'
);

select has_column(
  'app_finance', 'held_amounts', 'category_id',
  'held amounts store an optional category'
);

select ok(
  (
    select pg_get_indexdef(index_class.oid)
      like '%(category_id, user_id)%'
    from pg_class index_class
    join pg_namespace namespace on namespace.oid = index_class.relnamespace
    where namespace.nspname = 'app_finance'
      and index_class.relname = 'idx_held_amounts_category'
  ),
  'held category ownership foreign key has a covering index'
);

select has_function(
  'app_finance', 'save_held_amount',
  array[
    'app_finance.transaction_kind', 'bigint', 'text', 'text', 'date',
    'text', 'text', 'uuid', 'uuid', 'uuid', 'uuid'
  ],
  'typed save_held_amount overload exists'
);

select is(
  (
    select count(*)::integer
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'app_finance'
      and function.proname = 'save_held_amount'
      and pg_get_function_identity_arguments(function.oid)
        like 'p_direction app_finance.held_amount_direction%'
  ),
  0,
  'legacy direction-based save overload is removed'
);

select app_finance.save_held_amount(
  'custom_income', 25000, 'EGP', 'Client', current_date,
  'Pending refund', null,
  (select id from app_finance.accounts where name = 'Current'),
  (select id from app_finance.transaction_categories where name = 'Held Refund')
);

select results_eq(
  $$select transaction_kind, direction, category_id is not null
    from app_finance.held_amounts where title = 'Pending refund'$$,
  $$values (
    'custom_income'::app_finance.transaction_kind,
    'owed_to_me'::app_finance.held_amount_direction,
    true
  )$$,
  'income hold derives direction and preserves category'
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Pending refund'),
  current_date
);

select results_eq(
  $$select transaction_kind, amount_minor, destination_account_id is not null,
           category_id is not null
    from app_finance.financial_transactions
    where id = (select settlement_transaction_id
      from app_finance.held_amounts where title = 'Pending refund')$$,
  $$values (
    'custom_income'::app_finance.transaction_kind,
    25000::bigint,
    true,
    true
  )$$,
  'settling creates a typed categorized income transaction'
);

select is(
  (select balance_minor from app_finance.account_balances where name = 'Current'),
  125000::bigint,
  'settled income affects the account balance'
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Pending refund'),
  current_date
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where title = 'Pending refund'),
  1,
  'repeated settlement remains idempotent'
);

select app_finance.save_held_amount(
  'expense', 10000, 'EGP', 'Market', current_date,
  'Pending groceries', null,
  (select id from app_finance.accounts where name = 'Current'),
  (select id from app_finance.transaction_categories where name = 'Held Groceries')
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Pending groceries'),
  current_date
);

select is(
  (select balance_minor from app_finance.account_balances where name = 'Current'),
  115000::bigint,
  'settled expense decreases the account balance'
);

select throws_ok(
  $$select app_finance.save_held_amount(
    'expense', 1000, 'EGP', 'Mismatch', current_date,
    'Invalid category', null,
    (select id from app_finance.accounts where name = 'Current'),
    (select id from app_finance.transaction_categories where name = 'Held Refund')
  )$$,
  'P0001', null,
  'transaction kind rejects a mismatched category kind'
);

select app_finance.save_held_amount(
  'freelance_income', 5000, 'EGP', 'Client', current_date,
  'Temporary category hold', null,
  (select id from app_finance.accounts where name = 'Current'),
  (select id from app_finance.transaction_categories
    where name = 'Disposable Held Category')
);

delete from app_finance.transaction_categories
where name = 'Disposable Held Category';

select ok(
  (select category_id is null
      and user_id = '00000000-0000-0000-0000-000000000043'
    from app_finance.held_amounts where title = 'Temporary category hold'),
  'category deletion clears only category_id and preserves held ownership'
);

select app_finance.delete_held_amount(
  (select id from app_finance.held_amounts where title = 'Pending groceries')
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where title = 'Pending groceries'),
  0,
  'deleting a settled hold removes its settlement transaction'
);

select is(
  (select balance_minor from app_finance.account_balances where name = 'Current'),
  125000::bigint,
  'deleting the settled hold restores its balance effect'
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Pending refund'),
  null
);

select is(
  (select balance_minor from app_finance.account_balances where name = 'Current'),
  100000::bigint,
  'unsettling removes the transaction and reverses its balance effect'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where title = 'Pending refund'),
  0,
  'unsettling removes the generated transaction'
);

select * from finish();
rollback;
