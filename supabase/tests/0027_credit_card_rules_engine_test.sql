begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000073',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'rules-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Rules Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000074',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'rules-intruder@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Rules Intruder"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------

select has_table('app_finance', 'credit_card_fee_rule_versions',
  'fee rule versions table exists');
select has_function('app_finance', 'save_credit_card_fee_rule',
  'save_credit_card_fee_rule exists');
select has_function('app_finance', 'create_fee_rule_version',
  'create_fee_rule_version exists');
select has_function('app_finance', 'cancel_fee_rule_version',
  'cancel_fee_rule_version exists');
select has_function('app_finance', 'resolve_fee_rule_calculation',
  'resolve_fee_rule_calculation exists');
select has_function('app_finance', 'highest_statement_due_minor',
  'highest_statement_due_minor exists');
select has_view('app_finance', 'credit_card_fee_rule_current',
  'credit_card_fee_rule_current view exists');

-- ---------------------------------------------------------------------------
-- Seed owner data
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000073","role":"authenticated"}';

select app_finance.save_credit_facility(
  'Rules Card', 'credit_card', 'EGP', 5000000, 10::smallint,
  25::smallint, '9911', 3::smallint, null, null,
  'active', 'fixed', 5000, null);

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c201',
  '00000000-0000-0000-0000-000000000073',
  'Card Fees', 'expense'
);

-- ---------------------------------------------------------------------------
-- save_credit_card_fee_rule: create writes identity + version 1
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.save_credit_card_fee_rule(
      (select id from app_finance.accounts where name = 'Rules Card'),
      'Annual Membership', 'annual_membership',
      '00000000-0000-0000-0000-00000000c201', 'configured', 'schedule',
      date '2026-05-01', 'fixed', 20000, null, null, null, null, null,
      'annually', null, null, null, null, 100, null, null)$$,
  'creating a rule with a fixed calculation succeeds'
);
select results_eq(
  $$select current_calculation_type::text, current_fixed_amount_minor,
      state::text, is_active
    from app_finance.credit_card_fee_rule_current
    where name = 'Annual Membership'$$,
  $$values ('fixed'::text, 20000::bigint, 'configured'::text, true)$$,
  'the current-version view resolves the freshly created version'
);

-- A "state = configured" rule needs a real calculation.
select throws_ok(
  $$select app_finance.save_credit_card_fee_rule(
      (select id from app_finance.accounts where name = 'Rules Card'),
      'Broken Rule', 'other', '00000000-0000-0000-0000-00000000c201',
      'configured', 'schedule', date '2026-05-01', 'manual', null, null,
      null, null, null, null, 'annually', null, null, null, null, 100,
      null, null)$$,
  'P0001', null, 'a configured rule without a calculation is rejected'
);

-- ---------------------------------------------------------------------------
-- Unknown state never charges (Unknown must never silently become zero)
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Foreign Markup', 'foreign_transaction',
  '00000000-0000-0000-0000-00000000c201', 'unknown', 'foreign_transaction',
  date '2026-05-01', 'manual', null, null, null, null, null, null,
  'per_transaction', null, null, null, null, 100, null, null
);
select results_eq(
  $$select is_active from app_finance.credit_card_fee_rules
    where name = 'Foreign Markup'$$,
  $$values (false)$$,
  'an unknown-state rule is never active'
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-06-01')$$,
  $$values (1)$$,
  'only the configured schedule rule is due (the unknown rule is skipped)'
);

-- ---------------------------------------------------------------------------
-- Percentage with minimum and maximum clamp
-- ---------------------------------------------------------------------------

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Statement Insurance', 'insurance', '00000000-0000-0000-0000-00000000c201',
  'configured', 'schedule', date '2026-05-01', 'percentage', null, 100,
  'credit_limit', 3000, 40000, null, 'monthly', null, null, null, null, 100,
  null, null
);
-- 1% of a 5,000,000 minor-unit limit is 50,000, clamped down to the 40,000
-- maximum.
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-05-02')$$,
  $$values (1)$$,
  'the percentage rule with a maximum clamp charges when due'
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Statement Insurance'$$,
  $$values (40000::bigint)$$,
  'the calculated amount is clamped to the configured maximum'
);

-- ---------------------------------------------------------------------------
-- Quarterly historical-lookback basis (fixture from the product spec)
-- ---------------------------------------------------------------------------

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000c202',
  '00000000-0000-0000-0000-000000000073',
  'Purchases', 'expense'
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Feb spend', '00000000-0000-0000-0000-00000000c202',
  date '2026-02-20', 8000, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Mar spend', '00000000-0000-0000-0000-00000000c202',
  date '2026-03-20', 12000, null, null
);
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Apr spend', '00000000-0000-0000-0000-00000000c202',
  date '2026-04-20', 10000, null, null
);
select results_eq(
  $$select app_finance.highest_statement_due_minor(
      (select id from app_finance.accounts where name = 'Rules Card'),
      date '2026-05-01', 3)$$,
  $$values (12000::bigint)$$,
  'the highest of the previous 3 statements is 12,000'
);

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Quarterly Stamp Duty', 'stamp_tax', '00000000-0000-0000-0000-00000000c201',
  'configured', 'schedule', date '2026-05-01', 'percentage', null, 5,
  'highest_statement_due_lookback', null, null, 3, 'quarterly', null, null,
  null, null, 100, null, null
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-05-02')$$,
  $$values (1)$$,
  'the quarterly lookback rule charges when due'
);
select results_eq(
  $$select amount_minor from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.name = 'Quarterly Stamp Duty'$$,
  $$values (6::bigint)$$,
  '0.05% of the 12,000 highest previous statement is exactly 6'
);

-- ---------------------------------------------------------------------------
-- Rule versioning: future-dated change, overlap rejection, cancellation
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.create_fee_rule_version(
      (select id from app_finance.credit_card_fee_rules
        where name = 'Annual Membership'),
      date '2026-01-01', 'fixed', 25000, null, null, null, null, null,
      'annually', null, null, null, null)$$,
  'P0001', null, 'a version cannot be backdated before today'
);

select app_finance.create_fee_rule_version(
  (select id from app_finance.credit_card_fee_rules
    where name = 'Annual Membership'),
  date '2027-01-01', 'fixed', 25000, null, null, null, null, null,
  'annually', null, null, null, null
);
select results_eq(
  $$select current_fixed_amount_minor, upcoming_fixed_amount_minor,
      upcoming_effective_from
    from app_finance.credit_card_fee_rule_current
    where name = 'Annual Membership'$$,
  $$values (20000::bigint, 25000::bigint, date '2027-01-01')$$,
  'the current rate is unchanged; the new rate is scheduled, not active yet'
);

-- Direct writes to the versions table are RPC-only.
select throws_ok(
  $$insert into app_finance.credit_card_fee_rule_versions (
      user_id, rule_id, version_number, effective_from, calculation_type,
      fixed_amount_minor
    ) values (
      '00000000-0000-0000-0000-000000000073',
      (select id from app_finance.credit_card_fee_rules
        where name = 'Annual Membership'),
      99, date '2028-01-01', 'fixed', 1
    )$$,
  'P0001', null, 'direct inserts into rule versions are blocked'
);

-- Cancelling an already-active version is rejected; cancelling the future
-- one reopens the version that was covering today.
select throws_ok(
  $$select app_finance.cancel_fee_rule_version(
      (select id from app_finance.credit_card_fee_rule_versions
        where rule_id = (select id from app_finance.credit_card_fee_rules
          where name = 'Annual Membership')
        and version_number = 1))$$,
  'P0001', null, 'the currently active version cannot be cancelled'
);
select lives_ok(
  $$select app_finance.cancel_fee_rule_version(
      (select id from app_finance.credit_card_fee_rule_versions
        where rule_id = (select id from app_finance.credit_card_fee_rules
          where name = 'Annual Membership')
        and version_number = 2))$$,
  'cancelling the future, not-yet-started version succeeds'
);
select results_eq(
  $$select current_fixed_amount_minor, upcoming_version_id
    from app_finance.credit_card_fee_rule_current
    where name = 'Annual Membership'$$,
  $$values (20000::bigint, null::uuid)$$,
  'cancelling the future version reopens the original version'
);

-- Historical charge stays unchanged when a rule is edited going forward:
-- schedule a real future rate change and confirm the already-generated
-- May charge keeps its original amount and version link.
select app_finance.create_fee_rule_version(
  (select id from app_finance.credit_card_fee_rules
    where name = 'Annual Membership'),
  date '2027-01-01', 'fixed', 30000, null, null, null, null, null,
  'annually', null, null, null, null
);
select results_eq(
  $$select f.amount_minor, v.fixed_amount_minor
    from app_finance.credit_card_fee_charges f
    join app_finance.credit_card_fee_rule_versions v
      on v.id = f.rule_version_id
    join app_finance.credit_card_fee_rules r on r.id = f.rule_id
    where r.name = 'Annual Membership'$$,
  $$values (20000::bigint, 20000::bigint)$$,
  'the already-generated charge keeps referencing its original version'
);

-- ---------------------------------------------------------------------------
-- Insurance mutual exclusion: only one rule in a group generates
-- ---------------------------------------------------------------------------

-- Catch up the monthly Statement Insurance rule (unrelated to this group)
-- first, so the assertions below isolate cleanly to the exclusion group.
-- Each call only catches up one missed period, so June and July both need
-- a pass before the July 2nd group check runs.
select app_finance.apply_credit_card_fees(date '2026-06-02');
select app_finance.apply_credit_card_fees(date '2026-07-01');

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Standard Insurance', 'insurance', '00000000-0000-0000-0000-00000000c201',
  'configured', 'schedule', date '2026-07-01', 'fixed', 5000, null, null,
  null, null, null, 'monthly', null, null, null, 'protection', 10, null,
  null
);
select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'Rules Card'),
  'Credit Protection Plan', 'insurance',
  '00000000-0000-0000-0000-00000000c201', 'configured', 'schedule',
  date '2026-07-01', 'fixed', 7500, null, null, null, null, null, 'monthly',
  null, null, null, 'protection', 20, null, null
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.mutual_exclusion_group = 'protection'
      and c.charged_on = date '2026-07-01'$$,
  $$values (0)$$,
  'nothing has generated for the protection group yet'
);
select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-07-02')$$,
  $$values (1)$$,
  'exactly one rule in the mutual exclusion group generates this cycle'
);
select results_eq(
  $$select r.name from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_fee_rules r on r.id = c.rule_id
    where r.mutual_exclusion_group = 'protection'
      and c.charged_on = date '2026-07-01'$$,
  $$values ('Standard Insurance'::text)$$,
  'the lower-priority-number rule in the group is the one that wins'
);
select results_eq(
  $$select is_active from app_finance.credit_card_fee_rules
    where name = 'Credit Protection Plan'$$,
  $$values (true)$$,
  'the suppressed rule still advances its schedule instead of stalling'
);

-- ---------------------------------------------------------------------------
-- Idempotent retry
-- ---------------------------------------------------------------------------

select results_eq(
  $$select app_finance.apply_credit_card_fees(date '2026-07-02')$$,
  $$values (0)$$,
  're-running the generator a second time never double-charges'
);

-- ---------------------------------------------------------------------------
-- Cross-user isolation
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000074","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_rules
    where name = 'Annual Membership'$$,
  $$values (0)$$,
  'another user cannot see the rule at all'
);
select throws_ok(
  $$select app_finance.create_fee_rule_version(
      (select id from app_finance.credit_card_fee_rules
        where name = 'Standard Insurance'),
      date '2027-01-01', 'fixed', 1, null, null, null, null, null,
      'annually', null, null, null, null)$$,
  'P0001', null, 'another user cannot version a rule they do not own'
);

select * from finish();
rollback;
