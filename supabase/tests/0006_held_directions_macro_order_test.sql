begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '00000000-0000-0000-0000-00000000000e',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'user-e@test.local',
  '',
  now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"User E"}',
  now(),
  now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-00000000000e","role":"authenticated"}';

select app_core.complete_onboarding(
  'User E', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
  1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
  'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
  'Current Balance', 'current', 1000000, false
);

-- Existing and older app clients omit direction; that remains "I owe".
select lives_ok(
  $$insert into app_finance.held_amounts (
      user_id, amount_minor, currency_code, counterparty, held_on
    ) values (
      '00000000-0000-0000-0000-00000000000e',
      2500, 'EGP', 'Legacy payable', current_date
    )$$,
  'held amount remains compatible when direction is omitted'
);

select is(
  (select direction::text
     from app_finance.held_amounts
     where counterparty = 'Legacy payable'),
  'i_owe',
  'omitted held direction defaults to i_owe'
);

select lives_ok(
  $$insert into app_finance.held_amounts (
      user_id, amount_minor, currency_code, counterparty, held_on, direction
    ) values (
      '00000000-0000-0000-0000-00000000000e',
      5000, 'EGP', 'Client receivable', current_date, 'owed_to_me'
    )$$,
  'held amount accepts owed_to_me direction'
);

select is(
  (select direction::text
     from app_finance.held_amounts
     where counterparty = 'Client receivable'),
  'owed_to_me',
  'owed_to_me direction persists'
);

select throws_ok(
  $$insert into app_finance.held_amounts (
      user_id, amount_minor, currency_code, counterparty, held_on, direction
    ) values (
      '00000000-0000-0000-0000-00000000000e',
      100, 'EGP', 'Invalid direction', current_date, 'sideways'
    )$$,
  '22P02',
  null,
  'unknown held direction is rejected'
);

-- Client-provided positions are ignored; JSON array order is authoritative.
select lives_ok(
  $$select app_finance.save_macro('Route', jsonb_build_array(
      jsonb_build_object(
        'position', 99,
        'transaction_kind', 'expense',
        'amount_minor', 100,
        'source_account_id', (
          select id from app_finance.accounts where name = 'Current Balance'
        ),
        'title', 'First',
        'is_reversible', true
      ),
      jsonb_build_object(
        'position', -5,
        'transaction_kind', 'expense',
        'amount_minor', 200,
        'source_account_id', (
          select id from app_finance.accounts where name = 'Current Balance'
        ),
        'title', 'Second',
        'is_reversible', true
      ),
      jsonb_build_object(
        'position', 99,
        'transaction_kind', 'expense',
        'amount_minor', 300,
        'source_account_id', (
          select id from app_finance.accounts where name = 'Current Balance'
        ),
        'title', 'Third',
        'is_reversible', true
      )
    ))$$,
  'macro saves actions in JSON array order'
);

select is(
  (select array_agg(position order by position)
     from app_finance.transaction_macro_items
     where macro_id = (
       select id from app_finance.transaction_macros where name = 'Route'
     )),
  array[0, 1, 2],
  'macro positions are contiguous and server-owned'
);

select is(
  (select array_agg(title order by position)
     from app_finance.transaction_macro_items
     where macro_id = (
       select id from app_finance.transaction_macros where name = 'Route'
     )),
  array['First', 'Second', 'Third']::text[],
  'stored macro actions retain authored order'
);

select throws_ok(
  $$insert into app_finance.transaction_macro_items (
      user_id, macro_id, position, transaction_kind, amount_minor,
      source_account_id
    ) values (
      '00000000-0000-0000-0000-00000000000e',
      (select id from app_finance.transaction_macros where name = 'Route'),
      -1, 'expense', 100,
      (select id from app_finance.accounts where name = 'Current Balance')
    )$$,
  '23514',
  null,
  'negative macro position is rejected'
);

select throws_ok(
  $$insert into app_finance.transaction_macro_items (
      user_id, macro_id, position, transaction_kind, amount_minor,
      source_account_id
    ) values (
      '00000000-0000-0000-0000-00000000000e',
      (select id from app_finance.transaction_macros where name = 'Route'),
      0, 'expense', 100,
      (select id from app_finance.accounts where name = 'Current Balance')
    )$$,
  '23505',
  null,
  'duplicate macro position is rejected'
);

create temporary table forward_result (
  id uuid not null,
  ordinal bigint not null
) on commit drop;

insert into forward_result (id, ordinal)
select result.id, result.ordinal
from app_finance.apply_macro(
  (select id from app_finance.transaction_macros where name = 'Route'),
  current_date,
  false
) with ordinality as result(id, ordinal);

select is(
  (select count(*)::integer from forward_result),
  3,
  'forward macro applies every action'
);

select is(
  (select array_agg(tx.title order by result.ordinal)
     from forward_result result
     join app_finance.financial_transactions tx on tx.id = result.id),
  array[
    'To Route · First',
    'To Route · Second',
    'To Route · Third'
  ]::text[],
  'forward macro returns records in authored order'
);

select is(
  (select array_agg(title order by sort_at desc, id desc)
     from app_finance.financial_transactions
     where title like 'To Route%'),
  array[
    'To Route · First',
    'To Route · Second',
    'To Route · Third'
  ]::text[],
  'newest-first transaction lists preserve forward macro order'
);

create temporary table reverse_result (
  id uuid not null,
  ordinal bigint not null
) on commit drop;

insert into reverse_result (id, ordinal)
select result.id, result.ordinal
from app_finance.apply_macro(
  (select id from app_finance.transaction_macros where name = 'Route'),
  current_date,
  true
) with ordinality as result(id, ordinal);

select is(
  (select count(*)::integer from reverse_result),
  3,
  'reverse macro applies every reversible action'
);

select is(
  (select array_agg(tx.title order by result.ordinal)
     from reverse_result result
     join app_finance.financial_transactions tx on tx.id = result.id),
  array[
    'From Route · Third',
    'From Route · Second',
    'From Route · First'
  ]::text[],
  'reverse macro returns records in inverse authored order'
);

select is(
  (select array_agg(title order by sort_at desc, id desc)
     from app_finance.financial_transactions
     where title like 'From Route%'),
  array[
    'From Route · Third',
    'From Route · Second',
    'From Route · First'
  ]::text[],
  'newest-first transaction lists preserve reverse macro order'
);

select * from finish();
rollback;
