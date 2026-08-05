begin;
create extension if not exists pgtap with schema extensions;

select plan(15);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000052',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partial-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Partial Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000053',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'partial-intruder@test.local', '',
  now(), '{"provider":"email","providers":["email"]}',
  '{"display_name":"Partial Intruder"}', now(), now()
);

select has_function('app_finance', 'accept_income_occurrence_partial',
  'partial acceptance RPC exists');

-- ---------------------------------------------------------------------------
-- Seed a non-salary source so the flow needs no salary period
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000052","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a401',
  '00000000-0000-0000-0000-000000000052',
  'Main Wallet', 'cash', 'EGP', 0
);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c401',
  '00000000-0000-0000-0000-000000000052',
  'Side Income', 'income'
);

select app_finance.save_income_source(
  'Side Gig', 'other', 4400000, 'EGP', 5::smallint,
  date '2026-06-01', 3::smallint,
  '00000000-0000-0000-0000-00000000a401',
  '00000000-0000-0000-0000-00000000c401', '[]', null, null);

select app_finance.materialize_income_occurrences(date '2026-06-30');

select results_eq(
  $$select count(*)::integer from app_finance.income_occurrences o
    join app_finance.income_sources s on s.id = o.income_source_id
    where s.name = 'Side Gig'$$,
  $$values (1)$$,
  'one scheduled occurrence materializes for June'
);

-- ---------------------------------------------------------------------------
-- Partial acceptance: 44,000 owed, 40,000 received
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.accept_income_occurrence_partial(
      (select o.id from app_finance.income_occurrences o
        join app_finance.income_sources s on s.id = o.income_source_id
        where s.name = 'Side Gig' and o.status = 'pending'),
      4000000, 4400000, date '2026-06-05', null, null)$$,
  'a shortfall payment can be accepted partially'
);
select results_eq(
  $$select o.status::text, o.actual_amount_minor, t.amount_minor
    from app_finance.income_occurrences o
    join app_finance.financial_transactions t
      on t.id = o.primary_transaction_id
    where o.remainder_of_occurrence_id is null
      and o.income_source_id =
        (select id from app_finance.income_sources where name = 'Side Gig')$$,
  $$values ('accepted'::text, 4000000::bigint, 4000000::bigint)$$,
  'the received part books exactly like a normal acceptance'
);
select results_eq(
  $$select o.status::text, o.expected_amount_minor, o.scheduled_on
    from app_finance.income_occurrences o
    where o.remainder_of_occurrence_id is not null$$,
  $$values ('pending'::text, 400000::bigint, date '2026-06-05')$$,
  'the shortfall becomes a linked pending remainder'
);
select results_eq(
  $$select count(*)::integer from app_finance.income_occurrences o
    where o.remainder_of_occurrence_id =
      (select p.id from app_finance.income_occurrences p
        where p.remainder_of_occurrence_id is null
          and p.status = 'accepted')$$,
  $$values (1)$$,
  'the remainder links back to the occurrence it came from'
);

-- Re-materializing never collides with or duplicates the remainder.
select lives_ok(
  $$select app_finance.materialize_income_occurrences(date '2026-06-30')$$,
  'materialization ignores remainder rows'
);
select results_eq(
  $$select count(*)::integer from app_finance.income_occurrences$$,
  $$values (2)$$,
  'no duplicate occurrences appear after re-materializing'
);

-- ---------------------------------------------------------------------------
-- Accepting the remainder books the late money plainly
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.accept_income_occurrence(
      (select id from app_finance.income_occurrences
        where remainder_of_occurrence_id is not null),
      400000, date '2026-06-20', null,
      '00000000-0000-0000-0000-00000000ffff')$$,
  'P0001', null, 'a remainder never takes a salary period'
);
select lives_ok(
  $$select app_finance.accept_income_occurrence(
      (select id from app_finance.income_occurrences
        where remainder_of_occurrence_id is not null),
      400000, date '2026-06-20', null, null)$$,
  'the remainder can be accepted when the money arrives'
);
select results_eq(
  $$select sum(t.amount_minor)::bigint, count(*)::integer
    from app_finance.financial_transactions t
    where t.user_id = '00000000-0000-0000-0000-000000000052'
      and t.transaction_kind <> 'transfer'$$,
  $$values (4400000::bigint, 2)$$,
  'received and remainder together equal the full amount owed'
);

-- ---------------------------------------------------------------------------
-- Guard rails
-- ---------------------------------------------------------------------------

select app_finance.materialize_income_occurrences(date '2026-07-31');

select throws_ok(
  $$select app_finance.accept_income_occurrence_partial(
      (select o.id from app_finance.income_occurrences o
        where o.status = 'pending'
          and o.remainder_of_occurrence_id is null limit 1),
      4400000, 4400000, date '2026-07-05', null, null)$$,
  'P0001', null,
  'a partial acceptance requires the owed amount to exceed the received one'
);
select throws_ok(
  $$select app_finance.accept_income_occurrence_partial(
      (select o.id from app_finance.income_occurrences o
        where o.status = 'pending'
          and o.remainder_of_occurrence_id is null limit 1),
      0, 4400000, date '2026-07-05', null, null)$$,
  'P0001', null, 'a partial acceptance rejects a zero received amount'
);

-- ---------------------------------------------------------------------------
-- RLS isolation
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000053","role":"authenticated"}';

select results_eq(
  $$select count(*)::integer from app_finance.income_occurrences$$,
  $$values (0)$$,
  'occurrences stay invisible to other users'
);
select throws_ok(
  $$select app_finance.accept_income_occurrence_partial(
      (select o.id from app_finance.income_occurrences o
        where o.user_id = '00000000-0000-0000-0000-000000000052'
          and o.status = 'pending' limit 1),
      100, 200, current_date, null, null)$$,
  'P0001', null, 'cross-user partial acceptance is rejected'
);

select * from finish();
rollback;
