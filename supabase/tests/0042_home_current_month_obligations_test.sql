begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

select has_function(
  'app_finance', 'home_current_month_obligations',
  array['date'],
  'Home has a dedicated calendar-month obligation contract'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'home-due-one@test.local', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000902',
   '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'home-due-two@test.local', '', now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000901","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000d901',
  '00000000-0000-0000-0000-000000000901', 'Everyday', 'cash', 'EGP', 100000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000e901',
  '00000000-0000-0000-0000-000000000901', 'Bills', 'expense'
);
insert into app_finance.recurring_rules (
  id, user_id, name, rule_kind, amount_minor, currency_code, frequency,
  payment_day, start_date, source_account_id, category_id
) values (
  '00000000-0000-0000-0000-00000000f901',
  '00000000-0000-0000-0000-000000000901', 'Internet', 'expense', 2500,
  'EGP', 'monthly', 1, date '2026-07-31',
  '00000000-0000-0000-0000-00000000d901',
  '00000000-0000-0000-0000-00000000e901'
);
insert into app_finance.recurring_occurrences (
  user_id, rule_id, scheduled_on, expected_amount_minor, status
) values
  ('00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-00000000f901', date '2026-07-31', 2500, 'pending'),
  ('00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-00000000f901', date '2026-08-01', 2500, 'pending'),
  ('00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-00000000f901', date '2026-08-31', 2500, 'pending'),
  ('00000000-0000-0000-0000-000000000901',
   '00000000-0000-0000-0000-00000000f901', date '2026-09-01', 2500, 'pending');

select results_eq(
  $$select count(*)::integer from app_finance.home_current_month_obligations(
    date '2026-08-15') where obligation_kind = 'recurring_expense'$$,
  $$values (3::integer)$$,
  'month-start, month-end, and overdue pending recurring expenses are included'
);

select results_eq(
  $$select count(*)::integer from app_finance.home_current_month_obligations(
    date '2026-08-15') where due_on > date '2026-08-31'$$,
  $$values (0::integer)$$,
  'future occurrences after the calendar month are excluded'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000902","role":"authenticated"}';
select is_empty(
  $$select * from app_finance.home_current_month_obligations(date '2026-08-15')$$,
  'the authenticated contract never returns another user''s obligations'
);

select * from finish();
rollback;
