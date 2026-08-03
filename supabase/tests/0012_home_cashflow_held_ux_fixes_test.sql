begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000021',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'cashflow@test.local', '', now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Cashflow User"}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000022',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'other@test.local', '', now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Other User"}', now(), now()
  );

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000021","role":"authenticated"}';

select app_core.complete_onboarding(
  'Cashflow User', 'EGP', 'Africa/Cairo', 'en', 6::smallint, '{5,6}'::smallint[],
  1000000, 1::smallint, 25::smallint, 1::smallint, 22::smallint, 480,
  'derived', null, 'derived', null, 100, 200, 150, 'additional_pay',
  'Current Balance', 'current', 113000, false
);

insert into app_finance.accounts (
  user_id, name, account_type, currency_code, opening_balance_minor
) values
  (
    '00000000-0000-0000-0000-000000000021',
    'USD Wallet', 'wallet', 'USD', -5000
  ),
  (
    '00000000-0000-0000-0000-000000000021',
    'EGP Parking', 'wallet', 'EGP', 0
  );

insert into app_finance.financial_transactions (
  user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  destination_account_id, title
) values (
  '00000000-0000-0000-0000-000000000021', 'custom_income', '2026-07-10',
  3075000, 'EGP',
  (select id from app_finance.accounts where name = 'Current Balance'),
  'Income'
);

insert into app_finance.financial_transactions (
  user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, title
) values
  (
    '00000000-0000-0000-0000-000000000021', 'expense', '2026-07-11',
    1958877, 'EGP',
    (select id from app_finance.accounts where name = 'Current Balance'),
    'Expenses'
  ),
  (
    '00000000-0000-0000-0000-000000000021', 'allowance_given', '2026-07-12',
    1070000, 'EGP',
    (select id from app_finance.accounts where name = 'Current Balance'),
    'Allowances'
  );

insert into app_finance.financial_transactions (
  user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, destination_account_id, title
) values (
  '00000000-0000-0000-0000-000000000021', 'transfer', '2026-07-15',
  1000, 'EGP',
  (select id from app_finance.accounts where name = 'Current Balance'),
  (select id from app_finance.accounts where name = 'EGP Parking'),
  'Ignored transfer'
);

select results_eq(
  $$select starting_balance_minor, income_minor, expenses_minor, allowances_minor,
           net_minor, ending_balance_minor
    from app_reports.cash_flow_summary_v2('2026-07-01', '2026-07-31')
    where currency_code = 'EGP'$$,
  $$values (113000::bigint, 3075000::bigint, 1958877::bigint,
            1070000::bigint, 46123::bigint, 159123::bigint)$$,
  'cash flow v2 returns screenshot math exactly'
);

select results_eq(
  $$select currency_code, starting_balance_minor
    from app_reports.cash_flow_summary_v2('2026-07-01', '2026-07-31')
    where currency_code = 'USD'$$,
  $$values ('USD'::text, -5000::bigint)$$,
  'cash flow v2 keeps currencies separate'
);

insert into app_finance.financial_transactions (
  user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, title
) values (
  '00000000-0000-0000-0000-000000000021', 'expense', '2026-07-20',
  6000, 'EGP',
  (select id from app_finance.accounts where name = 'Current Balance'),
  'Fast food'
);

select app_finance.save_held_amount(
  'custom_income', 6000, 'EGP', 'Friend', '2026-07-20',
  'Fast food reimbursement', null,
  (select id from app_finance.accounts where name = 'Current Balance'),
  null,
  (select id from app_finance.financial_transactions where title = 'Fast food')
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where title = 'Fast food'),
  1,
  'linked hold creation does not duplicate the original transaction'
);

select ok(
  (select linked_transaction_id is not null and settlement_transaction_id is null
    from app_finance.held_amounts where title = 'Fast food reimbursement'),
  'linked hold stores the reference separately before settlement'
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Fast food reimbursement'),
  '2026-07-21'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where amount_minor = 6000 and currency_code = 'EGP'),
  2,
  'settling linked hold creates a second transaction'
);

select results_eq(
  $$select transaction_kind, destination_account_id is not null
    from app_finance.financial_transactions
    where id = (select settlement_transaction_id from app_finance.held_amounts
      where title = 'Fast food reimbursement')$$,
  $$values ('custom_income'::app_finance.transaction_kind, true)$$,
  'owed-to-me settlement creates income that credits the account'
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Fast food reimbursement'),
  '2026-07-21'
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where amount_minor = 6000 and currency_code = 'EGP'),
  2,
  'repeated settlement is idempotent'
);

select app_finance.set_held_amount_settled(
  (select id from app_finance.held_amounts where title = 'Fast food reimbursement'),
  null
);

select is(
  (select count(*)::integer from app_finance.financial_transactions
    where title = 'Fast food'),
  1,
  'unsettle preserves original reference transaction'
);

select ok(
  (select settlement_transaction_id is null and linked_transaction_id is not null
    from app_finance.held_amounts where title = 'Fast food reimbursement'),
  'unsettle clears only the settlement transaction link'
);

insert into app_finance.income_sources (
  user_id, name, source_kind, transaction_kind, expected_amount_minor,
  currency_code, payment_day, start_date, prompt_days_before, primary_account_id
) values (
  '00000000-0000-0000-0000-000000000021', 'Salary', 'salary', 'salary_income',
  100000, 'EGP', 25, '2026-07-01', 31,
  (select id from app_finance.accounts where name = 'Current Balance')
);

insert into app_finance.income_occurrences (
  user_id, income_source_id, scheduled_on, expected_amount_minor
) values (
  '00000000-0000-0000-0000-000000000021',
  (select id from app_finance.income_sources where name = 'Salary'),
  current_date, 100000
);

select lives_ok(
  $$select app_finance.snooze_income_occurrence(
    (select id from app_finance.income_occurrences limit 1),
    now() + interval '24 hours'
  )$$,
  'pending occurrence can be snoozed'
);

select ok(
  (select status = 'pending' and decision_at is null and snoozed_until > now()
    from app_finance.income_occurrences limit 1),
  'snooze leaves occurrence pending without a decision'
);

select app_finance.skip_income_occurrence(
  (select id from app_finance.income_occurrences limit 1)
);

select throws_ok(
  $$select app_finance.snooze_income_occurrence(
    (select id from app_finance.income_occurrences limit 1),
    now() + interval '24 hours'
  )$$,
  'already_decided',
  'decided occurrence cannot be snoozed'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000022","role":"authenticated"}';

select throws_ok(
  $$select app_finance.snooze_income_occurrence(
    (select id from app_finance.income_occurrences limit 1),
    now() + interval '24 hours'
  )$$,
  'not_found: income occurrence',
  'cross-user snooze is rejected'
);

select * from finish();
rollback;
