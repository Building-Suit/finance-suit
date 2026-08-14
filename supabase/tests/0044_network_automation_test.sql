begin;
create extension if not exists pgtap with schema extensions;

select plan(34);

-- ---------------------------------------------------------------------------
-- Users, accounts, and a connection
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000000f7',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'automation-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Automation Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000f8',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'automation-wife@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Automation Wife"}', now(), now()
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-00000000a501',
   '00000000-0000-0000-0000-0000000000f7', 'Main', 'cash', 'EGP', 500000),
  ('00000000-0000-0000-0000-00000000a502',
   '00000000-0000-0000-0000-0000000000f7', 'Savings', 'savings', 'EGP', 0),
  ('00000000-0000-0000-0000-00000000a503',
   '00000000-0000-0000-0000-0000000000f8', 'Wallet', 'wallet', 'EGP', 0);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f7","role":"authenticated"}';
select lives_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f8', 'Wife')$$,
  'owner adds the receiver'
);
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f8","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.status = 'pending' limit 1), 'Tarek')$$,
  'receiver accepts'
);

-- ---------------------------------------------------------------------------
-- Recurring transfer rules can target the network contact
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f7","role":"authenticated"}';

select throws_ok(
  $$select app_finance.save_recurring_rule_v2(
      p_name => 'Both', p_rule_kind => 'transfer', p_amount_minor => 40000,
      p_frequency => 'weekly',
      p_payment_day => extract(isodow from current_date)::smallint,
      p_start_date => current_date - 7, p_prompt_days_before => 0::smallint,
      p_source_account_id => '00000000-0000-0000-0000-00000000a501',
      p_destination_account_id => '00000000-0000-0000-0000-00000000a502',
      p_destination_network_connection_id =>
        (select connection_id from app_finance.list_network_contacts()))$$,
  'invalid_destination: choose one destination',
  'a transfer rule cannot have two destinations'
);
select throws_ok(
  $$select app_finance.save_recurring_rule_v2(
      p_name => 'Neither', p_rule_kind => 'transfer', p_amount_minor => 40000,
      p_frequency => 'weekly',
      p_payment_day => extract(isodow from current_date)::smallint,
      p_start_date => current_date - 7, p_prompt_days_before => 0::smallint,
      p_source_account_id => '00000000-0000-0000-0000-00000000a501')$$,
  'invalid_account: destination not found, archived, or mismatched',
  'a transfer rule still needs exactly one destination'
);
select lives_ok(
  $$select app_finance.save_recurring_rule_v2(
      p_name => 'Weekly to wife', p_rule_kind => 'transfer',
      p_amount_minor => 40000, p_frequency => 'weekly',
      p_payment_day => extract(isodow from current_date)::smallint,
      p_start_date => current_date - 7, p_prompt_days_before => 0::smallint,
      p_source_account_id => '00000000-0000-0000-0000-00000000a501',
      p_destination_network_connection_id =>
        (select connection_id from app_finance.list_network_contacts()))$$,
  'a recurring transfer rule may target a network contact'
);
select results_eq(
  $$select (destination_account_id is null),
      (destination_network_connection_id is not null)
    from app_finance.recurring_rules where name = 'Weekly to wife'$$,
  $$values (true, true)$$,
  'the rule stores the network destination, not a fake account'
);
select lives_ok(
  $$select app_finance.save_recurring_rule(
      'Local rule', 'transfer', 1000, 'monthly', 5::smallint,
      current_date, 3::smallint,
      '00000000-0000-0000-0000-00000000a501',
      '00000000-0000-0000-0000-00000000a502', null, null, null, true)$$,
  'the existing local save_recurring_rule keeps working unchanged'
);

-- ---------------------------------------------------------------------------
-- Approving a network occurrence creates one pending transfer, no ledger
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.materialize_recurring_occurrences(current_date)$$,
  'occurrences materialize'
);
select lives_ok(
  $$select app_finance.accept_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'Weekly to wife' and o.status = 'pending'
        order by o.scheduled_on limit 1),
      40000, current_date)$$,
  'approving the occurrence works'
);
select results_eq(
  $$select status::text, amount_minor, origin_kind::text
    from app_finance.network_transfers
    where origin_kind = 'recurring_rule'$$,
  $$values ('pending', 40000::bigint, 'recurring_rule')$$,
  'approval created one pending network transfer'
);
select results_eq(
  $$select (o.transaction_id is null)
    from app_finance.recurring_occurrences o
    where o.status = 'accepted'$$,
  $$values (true)$$,
  'the accepted occurrence booked no local ledger row'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a501'$$,
  $$values (500000::bigint)$$,
  'the sender balance is unchanged before the receiver accepts'
);
select lives_ok(
  $$select app_finance.accept_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        where o.status = 'accepted' limit 1),
      40000, current_date)$$,
  'retrying the approval is idempotent'
);
select results_eq(
  $$select count(*)::integer from app_finance.network_transfers
    where origin_kind = 'recurring_rule'$$,
  $$values (1)$$,
  'the retry did not duplicate the transfer'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f8","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.status = 'pending'),
      '00000000-0000-0000-0000-00000000a503')$$,
  'the receiver accepts the recurring transfer'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a503'$$,
  $$values (40000::bigint)$$,
  'the receiver got the money on acceptance'
);

-- ---------------------------------------------------------------------------
-- Income allocations can split to the network contact
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f7","role":"authenticated"}';

select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a501'$$,
  $$values (460000::bigint)$$,
  'the sender paid only when the receiver accepted'
);

select lives_ok(
  $$select app_finance.save_income_source_v5(
      p_name => 'Side income', p_source_kind => 'other',
      p_expected_amount_minor => 100000, p_currency_code => 'EGP',
      p_payment_day => least(extract(day from current_date), 28)::smallint,
      p_start_date => current_date - 40, p_prompt_days_before => 3::smallint,
      p_primary_account_id => '00000000-0000-0000-0000-00000000a501',
      p_category_id => null,
      p_allocations => jsonb_build_array(
        jsonb_build_object(
          'allocation_method', 'percentage',
          'percentage_basis_points', 1000,
          'destination_network_connection_id',
          (select connection_id from app_finance.list_network_contacts())),
        jsonb_build_object(
          'allocation_method', 'fixed',
          'fixed_amount_minor', 5000,
          'destination_account_id',
          '00000000-0000-0000-0000-00000000a502')))$$,
  'an income source may split to a network contact and an own account'
);
select lives_ok(
  $$select app_finance.materialize_income_occurrences(current_date)$$,
  'income occurrences materialize'
);
select lives_ok(
  $$select app_finance.accept_income_occurrence(
      (select o.id from app_finance.income_occurrences o
        join app_finance.income_sources s on s.id = o.income_source_id
        where s.name = 'Side income' and o.status = 'pending'
        order by o.scheduled_on limit 1),
      100000, current_date)$$,
  'accepting the income occurrence works'
);
select results_eq(
  $$select status::text, amount_minor
    from app_finance.network_transfers
    where origin_kind = 'income_allocation'$$,
  $$values ('pending', 10000::bigint)$$,
  'the network split became one pending transfer of ten percent'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a501'$$,
  $$values (555000::bigint)$$,
  'income posted once, the local split moved, the network split did not'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a502'$$,
  $$values (5000::bigint)$$,
  'the existing local allocation behaves exactly as before'
);
select results_eq(
  $$select income_minor, expenses_minor
    from app_reports.cash_flow_summary(current_date - 7, current_date + 1)$$,
  $$values (100000::bigint, 0::bigint)$$,
  'income is counted once and no network leg counts as expense'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f8","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.status = 'pending'),
      '00000000-0000-0000-0000-00000000a503')$$,
  'the receiver accepts the allocation transfer'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f7","role":"authenticated"}';
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a501'$$,
  $$values (545000::bigint)$$,
  'the sender source decreased only on the receiver acceptance'
);

-- ---------------------------------------------------------------------------
-- Protected extra-work pay can route to the network contact
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.save_income_source_v5(
      p_name => 'Salary', p_source_kind => 'salary',
      p_expected_amount_minor => 2000000, p_currency_code => 'EGP',
      p_payment_day => least(extract(day from current_date), 28)::smallint,
      p_start_date => current_date - 40, p_prompt_days_before => 3::smallint,
      p_primary_account_id => '00000000-0000-0000-0000-00000000a501',
      p_category_id => null,
      p_include_extra_work_in_percentage => false,
      p_extra_work_destination_account_id =>
        '00000000-0000-0000-0000-00000000a502',
      p_extra_work_destination_network_connection_id =>
        (select connection_id from app_finance.list_network_contacts()))$$,
  'invalid_destination: choose one destination',
  'extra work routes to one destination only'
);

insert into app_salary.salary_periods (
  id, user_id, period_start, period_end, expected_payment_date,
  status, snapshot, finalized_at
) values (
  '00000000-0000-0000-0000-00000000e501',
  '00000000-0000-0000-0000-0000000000f7',
  date_trunc('month', current_date)::date,
  (date_trunc('month', current_date) + interval '1 month - 1 day')::date,
  current_date, 'finalized',
  '{"total_minor": 2000000, "base_salary_minor": 1800000,
    "extra_day_amount_minor": 150000, "overtime_amount_minor": 50000,
    "holiday_amount_minor": 0}'::jsonb,
  now()
);

select lives_ok(
  $$select app_finance.save_income_source_v5(
      p_name => 'Salary', p_source_kind => 'salary',
      p_expected_amount_minor => 2000000, p_currency_code => 'EGP',
      p_payment_day => least(extract(day from current_date), 28)::smallint,
      p_start_date => current_date - 40, p_prompt_days_before => 3::smallint,
      p_primary_account_id => '00000000-0000-0000-0000-00000000a501',
      p_category_id => null,
      p_include_extra_work_in_percentage => false,
      p_extra_work_destination_network_connection_id =>
        (select connection_id from app_finance.list_network_contacts()))$$,
  'salary extra work may route to the network contact'
);
select lives_ok(
  $$select app_finance.materialize_income_occurrences(current_date)$$,
  'salary occurrences materialize'
);
select lives_ok(
  $$select app_finance.accept_income_occurrence(
      (select o.id from app_finance.income_occurrences o
        join app_finance.income_sources s on s.id = o.income_source_id
        where s.name = 'Salary' and o.status = 'pending'
        order by o.scheduled_on limit 1),
      2000000, current_date, null,
      '00000000-0000-0000-0000-00000000e501')$$,
  'accepting the salary occurrence works'
);
select results_eq(
  $$select status::text, amount_minor
    from app_finance.network_transfers
    where origin_kind = 'extra_work_allocation'$$,
  $$values ('pending', 200000::bigint)$$,
  'the protected extra-work pay became one pending network transfer'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a501'$$,
  $$values (2545000::bigint)$$,
  'salary posted once and the extra-work share was not deducted yet'
);

-- ---------------------------------------------------------------------------
-- A removed connection blocks the automation instead of rerouting it
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.remove_network_connection(
      (select connection_id from app_finance.list_network_contacts()))$$,
  'the owner removes the connection'
);
select throws_ok(
  $$select app_finance.accept_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'Weekly to wife' and o.status = 'pending'
        order by o.scheduled_on limit 1),
      40000, current_date)$$,
  'network_destination_unavailable: this contact was removed from your network',
  'approving an occurrence for a removed contact asks for a rule edit'
);

select * from finish();
rollback;
