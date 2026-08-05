begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000050',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'recurring-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Recurring Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000051',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'recurring-intruder@test.local', '',
  now(), '{"provider":"email","providers":["email"]}',
  '{"display_name":"Recurring Intruder"}', now(), now()
);

select has_table('app_finance', 'recurring_rules',
  'recurring rules table exists');
select has_table('app_finance', 'recurring_occurrences',
  'recurring occurrences table exists');
select results_eq(
  $$select count(*)::integer from pg_tables
    where schemaname like 'app\_%' escape '\'
      and rowsecurity = false$$,
  $$values (0)$$,
  'the new tables keep the no-RLS-less-table invariant'
);

-- ---------------------------------------------------------------------------
-- Seed owner data
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000050","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a301',
  '00000000-0000-0000-0000-000000000050',
  'Wallet', 'cash', 'EGP', 1000000
), (
  '00000000-0000-0000-0000-00000000a302',
  '00000000-0000-0000-0000-000000000050',
  'Savings', 'savings', 'EGP', 0
);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c301',
  '00000000-0000-0000-0000-000000000050',
  'Bills', 'expense'
), (
  '00000000-0000-0000-0000-00000000c302',
  '00000000-0000-0000-0000-000000000050',
  'Unused', 'expense'
);

-- ---------------------------------------------------------------------------
-- Rule shape validation
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.save_recurring_rule(
      'Internet', 'expense', 50000, 'monthly', 5::smallint,
      date '2026-01-01', 3::smallint,
      '00000000-0000-0000-0000-00000000a301', null,
      '00000000-0000-0000-0000-00000000c301', null,
      '00000000-0000-0000-0000-00000000e301', true)$$,
  'a monthly recurring expense can be created'
);
select lives_ok(
  $$select app_finance.save_recurring_rule(
      'To Savings', 'transfer', 100000, 'monthly', 1::smallint,
      date '2026-01-01', 3::smallint,
      '00000000-0000-0000-0000-00000000a301',
      '00000000-0000-0000-0000-00000000a302', null, null,
      '00000000-0000-0000-0000-00000000e302', true)$$,
  'a monthly recurring transfer can be created'
);
select throws_ok(
  $$select app_finance.save_recurring_rule(
      'Broken', 'expense', 1000, 'monthly', 5::smallint,
      date '2026-01-01', 3::smallint,
      '00000000-0000-0000-0000-00000000a301', null, null, null, null, true)$$,
  'P0001', null, 'an expense rule requires an expense category'
);
select throws_ok(
  $$select app_finance.save_recurring_rule(
      'Broken', 'transfer', 1000, 'monthly', 5::smallint,
      date '2026-01-01', 3::smallint,
      '00000000-0000-0000-0000-00000000a301',
      '00000000-0000-0000-0000-00000000a301', null, null, null, true)$$,
  '23514', null, 'a transfer rule rejects the same source and destination'
);

-- ---------------------------------------------------------------------------
-- Materialization
-- ---------------------------------------------------------------------------

select results_eq(
  $$select app_finance.materialize_recurring_occurrences(
      date '2026-03-31') >= 5$$,
  $$values (true)$$,
  'materialization fills the monthly schedule through the window'
);
select results_eq(
  $$select count(*)::integer from app_finance.recurring_occurrences o
    join app_finance.recurring_rules r on r.id = o.rule_id
    where r.name = 'Internet' and o.scheduled_on <= date '2026-03-31'$$,
  $$values (3)$$,
  'a monthly rule yields one occurrence per month on its day'
);
select results_eq(
  $$select app_finance.materialize_recurring_occurrences(
      date '2026-03-31')$$,
  $$values (0)$$,
  're-materializing the same window inserts nothing new'
);
select throws_ok(
  $$select app_finance.materialize_recurring_occurrences(
      current_date + 90)$$,
  'P0001', null, 'lookahead beyond two months is rejected'
);

-- Weekly rules land on the requested ISO weekday.
select app_finance.save_recurring_rule(
  'Gym', 'expense', 2000, 'weekly', 1::smallint,
  date '2026-01-01', 1::smallint,
  '00000000-0000-0000-0000-00000000a301', null,
  '00000000-0000-0000-0000-00000000c301', null,
  '00000000-0000-0000-0000-00000000e303', true);
select app_finance.materialize_recurring_occurrences(date '2026-01-31');
select results_eq(
  $$select count(*)::integer,
      bool_and(extract(isodow from o.scheduled_on) = 1)
    from app_finance.recurring_occurrences o
    where o.rule_id = '00000000-0000-0000-0000-00000000e303'
      and o.scheduled_on <= date '2026-01-31'$$,
  $$values (4, true)$$,
  'a weekly rule yields every Monday after its start date'
);

-- ---------------------------------------------------------------------------
-- Accept, skip, idempotency
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.accept_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'Internet'
        order by o.scheduled_on limit 1),
      50000, date '2026-01-05', null)$$,
  'accepting a recurring expense books the transaction'
);
select results_eq(
  $$select t.transaction_kind::text, t.amount_minor,
      t.source_account_id
    from app_finance.recurring_occurrences o
    join app_finance.financial_transactions t on t.id = o.transaction_id
    join app_finance.recurring_rules r on r.id = o.rule_id
    where r.name = 'Internet' and o.status = 'accepted'$$,
  $$values ('expense'::text, 50000::bigint,
    '00000000-0000-0000-0000-00000000a301'::uuid)$$,
  'the booked entry is a real expense from the rule source account'
);
select results_eq(
  $$select
      (select o.transaction_id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'Internet' and o.status = 'accepted') =
      app_finance.accept_recurring_occurrence(
        (select o.id from app_finance.recurring_occurrences o
          join app_finance.recurring_rules r on r.id = o.rule_id
          where r.name = 'Internet' and o.status = 'accepted'),
        50000, date '2026-01-05', null)$$,
  $$values (true)$$,
  'accepting twice returns the same transaction without double-booking'
);
select lives_ok(
  $$select app_finance.accept_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'To Savings'
        order by o.scheduled_on limit 1),
      100000, date '2026-01-01', null)$$,
  'accepting a recurring transfer moves the money atomically'
);
select results_eq(
  $$select t.transaction_kind::text, t.destination_account_id
    from app_finance.recurring_occurrences o
    join app_finance.financial_transactions t on t.id = o.transaction_id
    join app_finance.recurring_rules r on r.id = o.rule_id
    where r.name = 'To Savings' and o.status = 'accepted'$$,
  $$values ('transfer'::text,
    '00000000-0000-0000-0000-00000000a302'::uuid)$$,
  'the transfer lands in the rule destination account'
);
select lives_ok(
  $$select app_finance.skip_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'Internet' and o.status = 'pending'
        order by o.scheduled_on limit 1))$$,
  'a pending occurrence can be skipped'
);
select throws_ok(
  $$select app_finance.skip_recurring_occurrence(
      (select o.id from app_finance.recurring_occurrences o
        join app_finance.recurring_rules r on r.id = o.rule_id
        where r.name = 'Internet' and o.status = 'accepted' limit 1))$$,
  'P0001', null, 'a decided occurrence cannot be skipped again'
);

-- Editing a rule wipes only the future pending schedule.
select app_finance.save_recurring_rule(
  'Internet Plus', 'expense', 60000, 'monthly', 7::smallint,
  date '2026-01-01', 3::smallint,
  '00000000-0000-0000-0000-00000000a301', null,
  '00000000-0000-0000-0000-00000000c301', null,
  '00000000-0000-0000-0000-00000000e301', true);
select results_eq(
  $$select
      (select count(*) from app_finance.recurring_occurrences
        where rule_id = '00000000-0000-0000-0000-00000000e301'
          and status = 'pending'),
      (select count(*) from app_finance.recurring_occurrences
        where rule_id = '00000000-0000-0000-0000-00000000e301'
          and status <> 'pending')$$,
  $$values (0::bigint, 2::bigint)$$,
  'editing a rule clears pending occurrences and keeps decided history'
);

-- ---------------------------------------------------------------------------
-- Category deletion
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.delete_transaction_category(
      '00000000-0000-0000-0000-00000000c302')$$,
  'an unreferenced category deletes cleanly'
);
select results_eq(
  $$select count(*)::integer from app_finance.transaction_categories
    where id = '00000000-0000-0000-0000-00000000c302'$$,
  $$values (0)$$,
  'the deleted category is gone'
);
select throws_ok(
  $$select app_finance.delete_transaction_category(
      '00000000-0000-0000-0000-00000000c301')$$,
  'P0001', null, 'a category referenced by records refuses deletion'
);

-- ---------------------------------------------------------------------------
-- RLS isolation
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000051","role":"authenticated"}';

select results_eq(
  $$select
      (select count(*) from app_finance.recurring_rules)
      + (select count(*) from app_finance.recurring_occurrences)$$,
  $$values (0::bigint)$$,
  'recurring rules and occurrences are invisible to other users'
);
select throws_ok(
  $$select app_finance.delete_transaction_category(
      '00000000-0000-0000-0000-00000000c301')$$,
  'P0001', null, 'cross-user category deletion is rejected'
);

-- ---------------------------------------------------------------------------
-- Account deletion cascade
-- ---------------------------------------------------------------------------

reset role;
set local role service_role;
select app_core.delete_finance_suit_data(
  '00000000-0000-0000-0000-000000000050');
reset role;

select results_eq(
  $$select
      (select count(*) from app_finance.recurring_rules
        where user_id = '00000000-0000-0000-0000-000000000050')
      + (select count(*) from app_finance.recurring_occurrences
        where user_id = '00000000-0000-0000-0000-000000000050')$$,
  $$values (0::bigint)$$,
  'account deletion removes every recurring record'
);

select * from finish();
rollback;
