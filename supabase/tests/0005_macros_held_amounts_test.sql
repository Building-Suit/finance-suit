begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'user-d@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{"display_name":"User D"}', now(), now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000d","role":"authenticated"}';

select app_core.complete_onboarding(
  'User D', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
  1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
  'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
  'Current Balance', 'current', 1000000, false);

insert into app_finance.accounts (user_id, name, account_type, opening_balance_minor)
values ('00000000-0000-0000-0000-00000000000d', 'Savings', 'savings', 200000);

-- Reversible macro with a mixed set of actions.
select lives_ok(
  $$select app_finance.save_macro('Work', jsonb_build_array(
      jsonb_build_object(
        'transaction_kind', 'expense', 'amount_minor', 500,
        'source_account_id', (select id from app_finance.accounts where name = 'Current Balance'),
        'category_id', (select id from app_finance.transaction_categories where name = 'Transportation'),
        'title', 'Metro', 'is_reversible', true),
      jsonb_build_object(
        'transaction_kind', 'expense', 'amount_minor', 300,
        'source_account_id', (select id from app_finance.accounts where name = 'Current Balance'),
        'is_reversible', true),
      jsonb_build_object(
        'transaction_kind', 'expense', 'amount_minor', 1000,
        'source_account_id', (select id from app_finance.accounts where name = 'Current Balance'),
        'title', 'Lunch', 'is_reversible', false)))$$,
  'save_macro creates macro with items');

select is(
  (select count(*)::int from app_finance.transaction_macro_items),
  3, 'macro has three items');

select is(
  (select count(*)::int from app_finance.apply_macro(
    (select id from app_finance.transaction_macros where name = 'Work'),
    current_date, false)),
  3, 'forward run applies all actions');

select is(
  (select count(*)::int from app_finance.financial_transactions where title like 'To Work%'),
  3, 'forward run titles transactions To <name>');

select is(
  (select count(*)::int from app_finance.apply_macro(
    (select id from app_finance.transaction_macros where name = 'Work'),
    current_date, true)),
  2, 'reverse run applies only reversible actions');

select is(
  (select count(*)::int from app_finance.financial_transactions where title like 'From Work%'),
  2, 'reverse run titles transactions From <name>');

select is(
  (select count(*)::int from app_finance.financial_transactions where title = 'From Work · Metro'),
  1, 'item title is appended to the directional title');

-- Reversed transfers move the money back.
select lives_ok(
  $$select app_finance.save_macro('Stash', jsonb_build_array(
      jsonb_build_object(
        'transaction_kind', 'transfer', 'amount_minor', 1000,
        'source_account_id', (select id from app_finance.accounts where name = 'Current Balance'),
        'destination_account_id', (select id from app_finance.accounts where name = 'Savings'),
        'is_reversible', true)))$$,
  'save_macro creates transfer macro');

select is(
  (select count(*)::int from app_finance.apply_macro(
    (select id from app_finance.transaction_macros where name = 'Stash'),
    current_date, false)),
  1, 'transfer macro applies forward');

select is(
  (select source_account_id from app_finance.financial_transactions
    where transaction_kind = 'transfer'
    order by created_at desc limit 1),
  (select id from app_finance.accounts where name = 'Current Balance'),
  'forward transfer keeps stored direction');

select is(
  (select count(*)::int from app_finance.apply_macro(
    (select id from app_finance.transaction_macros where name = 'Stash'),
    current_date, true)),
  1, 'transfer macro applies in reverse');

select is(
  (select source_account_id from app_finance.financial_transactions
    where title = 'From Stash'),
  (select id from app_finance.accounts where name = 'Savings'),
  'reversed transfer swaps source and destination');

-- One-way macros refuse reverse runs.
select app_finance.save_macro('One way', jsonb_build_array(
  jsonb_build_object(
    'transaction_kind', 'expense', 'amount_minor', 100,
    'source_account_id', (select id from app_finance.accounts where name = 'Current Balance'))));

select throws_ok(
  $$select app_finance.apply_macro(
      (select id from app_finance.transaction_macros where name = 'One way'),
      current_date, true)$$,
  'P0001', null, 'reverse run of one-way macro rejected');

select throws_ok(
  $$select app_finance.save_macro('Empty', '[]'::jsonb)$$,
  'P0001', null, 'macro without actions rejected');

select throws_ok(
  $$select app_finance.save_macro('Broken', jsonb_build_array(
      jsonb_build_object(
        'transaction_kind', 'expense', 'amount_minor', 100,
        'source_account_id', (select id from app_finance.accounts where name = 'Current Balance'),
        'destination_account_id', (select id from app_finance.accounts where name = 'Savings'))))$$,
  '23514', null, 'macro item direction rules enforced');

-- Held amounts: linked to a transaction, survive its deletion.
select lives_ok(
  $$insert into app_finance.held_amounts (user_id, amount_minor, currency_code, counterparty, held_on, transaction_id)
    values ('00000000-0000-0000-0000-00000000000d', 2500, 'EGP', 'Ahmed', current_date,
            (select id from app_finance.financial_transactions where title = 'To Work · Metro' limit 1))$$,
  'held amount linked to transaction');

delete from app_finance.financial_transactions
  where id = (select transaction_id from app_finance.held_amounts where counterparty = 'Ahmed');

select ok(
  (select transaction_id is null from app_finance.held_amounts where counterparty = 'Ahmed'),
  'deleting the transaction unlinks but keeps the held amount');

select throws_ok(
  $$insert into app_finance.held_amounts (user_id, amount_minor, currency_code, counterparty, held_on, settled_on)
    values ('00000000-0000-0000-0000-00000000000d', 100, 'EGP', 'Sara', current_date, current_date - 1)$$,
  '23514', null, 'settling before the held date rejected');

select * from finish();
rollback;
