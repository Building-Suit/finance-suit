begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000010',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'delete-me@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Delete Me"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000010","role":"authenticated"}';

select app_core.complete_onboarding(
  'Delete Me', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
  1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
  'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
  'Current Balance', 'current', 100000, false
);

insert into app_salary.salary_adjustments (
  user_id, effective_date, adjustment_type, amount_minor, title
) values (
  '00000000-0000-0000-0000-000000000010', current_date, 'bonus', 1000,
  'Deletion test'
);

insert into app_work.official_holidays (id, user_id, holiday_date, name)
values (
  '10000000-0000-0000-0000-000000000010',
  '00000000-0000-0000-0000-000000000010', current_date, 'Deletion day'
);

insert into app_work.work_entries (
  user_id, work_date, entry_type, duration_minutes, break_minutes,
  computed_amount_minor, holiday_id
) values (
  '00000000-0000-0000-0000-000000000010', current_date, 'regular', 480, 0,
  1000, '10000000-0000-0000-0000-000000000010'
);

insert into app_salary.salary_periods (
  id, user_id, period_start, period_end, expected_payment_date
) values (
  '20000000-0000-0000-0000-000000000010',
  '00000000-0000-0000-0000-000000000010',
  current_date, current_date + 27, current_date + 30
);

insert into app_finance.financial_transactions (
  id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, category_id, title
) values (
  '30000000-0000-0000-0000-000000000010',
  '00000000-0000-0000-0000-000000000010', 'expense', current_date, 100,
  'EGP',
  (select id from app_finance.accounts where user_id =
    '00000000-0000-0000-0000-000000000010'),
  (select id from app_finance.transaction_categories where user_id =
    '00000000-0000-0000-0000-000000000010' and category_kind = 'expense'
    order by sort_order limit 1),
  'Deletion transaction'
);

insert into app_finance.transaction_macros (id, user_id, name)
values (
  '40000000-0000-0000-0000-000000000010',
  '00000000-0000-0000-0000-000000000010', 'Deletion macro'
);

insert into app_finance.transaction_macro_items (
  user_id, macro_id, position, transaction_kind, amount_minor,
  source_account_id, title
) values (
  '00000000-0000-0000-0000-000000000010',
  '40000000-0000-0000-0000-000000000010', 0, 'expense', 100,
  (select id from app_finance.accounts where user_id =
    '00000000-0000-0000-0000-000000000010'),
  'Deletion macro item'
);

insert into app_finance.held_amounts (
  user_id, direction, amount_minor, currency_code, counterparty, held_on,
  account_id, transaction_id, manages_transaction, title
) values (
  '00000000-0000-0000-0000-000000000010', 'i_owe', 100, 'EGP',
  'Deletion counterparty', current_date,
  (select id from app_finance.accounts where user_id =
    '00000000-0000-0000-0000-000000000010'),
  '30000000-0000-0000-0000-000000000010', true, 'Deletion held amount'
);

reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000000010';

select is((select count(*)::integer from auth.users where id =
  '00000000-0000-0000-0000-000000000010'), 0, 'Auth user is deleted');
select is((select count(*)::integer from app_core.profiles where id =
  '00000000-0000-0000-0000-000000000010'), 0, 'profile cascades');
select is((select count(*)::integer from app_core.user_preferences where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'preferences cascade');
select is((select count(*)::integer from app_salary.salary_settings where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'salary settings cascade');
select is((select count(*)::integer from app_salary.salary_adjustments where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'salary adjustments cascade');
select is((select count(*)::integer from app_salary.salary_periods where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'salary periods cascade');
select is((select count(*)::integer from app_work.official_holidays where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'holidays cascade');
select is((select count(*)::integer from app_work.work_entries where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'work entries cascade');
select is((select count(*)::integer from app_finance.accounts where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'accounts cascade');
select is((select count(*)::integer from app_finance.transaction_categories where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'categories cascade');
select is((select count(*)::integer from app_finance.financial_transactions where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'transactions cascade');
select is((select count(*)::integer from app_finance.transaction_macros where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'macros cascade');
select is((select count(*)::integer from app_finance.transaction_macro_items where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'macro items cascade');
select is((select count(*)::integer from app_finance.held_amounts where user_id =
  '00000000-0000-0000-0000-000000000010'), 0, 'held amounts cascade');

select * from finish();
rollback;
