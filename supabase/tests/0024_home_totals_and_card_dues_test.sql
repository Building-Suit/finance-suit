begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

select has_function('app_reports', 'cash_flow_summary_v3',
  'the home-aware cash flow RPC exists');
select has_column('app_finance', 'credit_facility_summaries',
  'upcoming_due_minor', 'facilities expose what falls due next month');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000058',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'home-totals@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Home Totals"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000058","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor,
  hide_from_home
) values (
  '00000000-0000-0000-0000-00000000a501',
  '00000000-0000-0000-0000-000000000058',
  'Everyday', 'cash', 'EGP', 100000, false
), (
  '00000000-0000-0000-0000-00000000a502',
  '00000000-0000-0000-0000-000000000058',
  'Hidden Vault', 'savings', 'EGP', 900000, true
);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c501',
  '00000000-0000-0000-0000-000000000058', 'Groceries', 'expense'
);

insert into app_finance.financial_transactions (
  user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, category_id, title
) values (
  '00000000-0000-0000-0000-000000000058', 'expense', current_date, 20000,
  'EGP', '00000000-0000-0000-0000-00000000a501',
  '00000000-0000-0000-0000-00000000c501', 'Visible spend'
), (
  '00000000-0000-0000-0000-000000000058', 'expense', current_date, 50000,
  'EGP', '00000000-0000-0000-0000-00000000a502',
  '00000000-0000-0000-0000-00000000c501', 'Hidden spend'
);

-- Everything counted: both accounts, both expenses.
select results_eq(
  $$select starting_balance_minor, expenses_minor, ending_balance_minor
    from app_reports.cash_flow_summary_v3(
      current_date - 1, current_date + 1, false)$$,
  $$values (1000000::bigint, 70000::bigint, 930000::bigint)$$,
  'the full picture still counts hidden accounts'
);

-- Home's view: the hidden vault and its spending disappear entirely.
select results_eq(
  $$select starting_balance_minor, expenses_minor, ending_balance_minor
    from app_reports.cash_flow_summary_v3(
      current_date - 1, current_date + 1, true)$$,
  $$values (100000::bigint, 20000::bigint, 80000::bigint)$$,
  'hiding an account removes its balance and its spending from Home'
);

select results_eq(
  $$select count(*)::integer
    from app_reports.cash_flow_summary_v2(current_date - 1, current_date + 1)$$,
  $$values (1)$$,
  'the previous cash flow RPC keeps working for reports'
);

-- ---------------------------------------------------------------------------
-- Upcoming dues accumulate across every installment falling due next month
-- ---------------------------------------------------------------------------

select app_finance.save_credit_facility(
  'Everyday Card', 'credit_card', 'EGP', 50000000, 10::smallint,
  25::smallint, '4242', 3::smallint, null, null, 'active',
  'full', null, null);

-- Four monthly dues of 1,000.00 starting yesterday: two of them fall on or
-- before one month from today.
select app_finance.create_installment_plan(
  p_account_id => (select account_id from app_finance.credit_facility_summaries
    where name = 'Everyday Card'),
  p_title => 'Samsung Monitor',
  p_category_id => '00000000-0000-0000-0000-00000000c501',
  p_purchased_on => current_date - 1,
  p_purchase_price_minor => 400000::bigint,
  p_installment_count => 4,
  p_first_due_on => current_date - 1,
  p_down_payment_minor => 0::bigint,
  p_financing_fees_minor => 0::bigint
);

-- Two of the four monthly dues land inside the next month.
select results_eq(
  $$select count(*)::integer
    from app_finance.installment_due_statuses
    where due_on <= (current_date + interval '1 month')::date$$,
  $$values (2)$$,
  'the plan puts two dues inside the coming month'
);
select results_eq(
  $$select upcoming_due_minor, next_due_amount_minor
    from app_finance.credit_facility_summaries
    where name = 'Everyday Card'$$,
  $$values (200000::bigint, 100000::bigint)$$,
  'the card sums both upcoming dues instead of showing only the earliest'
);

-- ---------------------------------------------------------------------------
-- Open salary periods track the current payment offset
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer from app_salary.salary_periods p
    join app_salary.salary_settings s on s.user_id = p.user_id
    where p.status = 'open'
      and p.expected_payment_date <>
        (date_trunc('month', p.period_start)
          + make_interval(months => s.payment_month_offset))::date
        + (s.payment_day - 1)),
  0,
  'no open period is left on a stale expected payment date'
);

reset role;

select is(
  (select count(*)::integer from app_salary.salary_periods p
    join app_salary.salary_settings s on s.user_id = p.user_id
    where p.status = 'open'
      and p.expected_payment_date <>
        (date_trunc('month', p.period_start)
          + make_interval(months => s.payment_month_offset))::date
        + (s.payment_day - 1)),
  0,
  'the backfill left no stale open period for any user'
);

select * from finish();
rollback;
