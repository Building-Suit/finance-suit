-- Generic, bank-agnostic Credit Card rules engine.
--
-- Extends the existing `credit_card_fee_rules` / `credit_card_fee_charges`
-- tables (added in 20260805090000) instead of creating a parallel system.
-- `credit_card_fee_rules` stays the rule *identity* (name, category, which
-- account, tri-state configured/unknown/disabled, mutual-exclusion group,
-- priority) plus the `next_charge_on` materialization cursor for
-- schedule-triggered rules. All calculation shape (fixed/percent/min/max/
-- lookback/trigger condition) moves to the new, effective-dated
-- `credit_card_fee_rule_versions` table so editing a rate creates a new
-- version instead of rewriting history — `apply_credit_card_fees` resolves,
-- for each occurrence date, the version whose effective range contains it.
--
-- `credit_card_fee_charges` (the generated-charge ledger) gains a link to
-- the exact rule version used, an idempotency shape that also covers
-- per-transaction trigger fees (foreign markup, cash advances, wallet
-- fees) and once-per-statement penalty fees (late payment, over limit),
-- and expected-vs-actual reconciliation fields.
--
-- Every existing rule is backfilled into a version 1 row with identical
-- values, and `apply_credit_card_fees` keeps its exact prior amount
-- resolution and idempotency contract for schedule-triggered fixed/percent
-- rules with no minimum/maximum/lookback configured, so all previously
-- generated charges and existing pgTAP coverage stay valid.

-- ---------------------------------------------------------------------------
-- New enums (brand new types are safe to use in this same transaction;
-- values added to *existing* enums live in the prior migration file).
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_rule_state') then
    create type app_finance.card_rule_state as enum
      ('configured', 'unknown', 'disabled');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_rule_calculation_type') then
    create type app_finance.card_rule_calculation_type as enum
      ('fixed', 'percentage', 'fixed_plus_percentage', 'manual');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_rule_trigger') then
    create type app_finance.card_rule_trigger as enum (
      'schedule', 'foreign_transaction', 'domestic_cash_advance',
      'international_cash_advance', 'wallet_transaction',
      'late_payment_missed_minimum', 'over_limit_event',
      'early_settlement', 'manual'
    );
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'foreign_apply_when') then
    create type app_finance.foreign_apply_when as enum
      ('currency_differs', 'merchant_outside_home', 'either', 'both');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'charge_reconciliation_status') then
    create type app_finance.charge_reconciliation_status as enum
      ('expected', 'confirmed', 'adjusted', 'waived', 'reversed', 'missing');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_transaction_subtype') then
    create type app_finance.card_transaction_subtype as enum (
      'purchase', 'domestic_cash_advance', 'international_cash_advance',
      'wallet_load'
    );
  end if;
end
$$;

grant usage on type app_finance.card_rule_state to authenticated, service_role;
grant usage on type app_finance.card_rule_calculation_type
to authenticated, service_role;
grant usage on type app_finance.card_rule_trigger
to authenticated, service_role;
grant usage on type app_finance.foreign_apply_when
to authenticated, service_role;
grant usage on type app_finance.charge_reconciliation_status
to authenticated, service_role;
grant usage on type app_finance.card_transaction_subtype
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Rule identity: tri-state, mutual exclusion, priority, trigger category
-- ---------------------------------------------------------------------------

alter table app_finance.credit_card_fee_rules
  add column if not exists state app_finance.card_rule_state
    not null default 'configured',
  add column if not exists trigger_kind app_finance.card_rule_trigger
    not null default 'schedule',
  add column if not exists mutual_exclusion_group text
    check (mutual_exclusion_group is null
      or char_length(mutual_exclusion_group) <= 80),
  add column if not exists priority integer not null default 100
    check (priority between 1 and 1000);

comment on column app_finance.credit_card_fee_rules.state is
  'configured: charges normally. unknown: the user has not supplied a '
  'rate yet, never charges, and the UI should offer to fill it in. '
  'disabled: intentionally off. Distinct from is_active, which stays the '
  'operational on/off switch apply_credit_card_fees filters on.';
comment on column app_finance.credit_card_fee_rules.trigger_kind is
  'What materializes this rule''s charges: a recurring schedule (handled '
  'by apply_credit_card_fees), a per-transaction condition (handled '
  'inline by charge_credit_card), a missed-minimum/over-limit statement '
  'event (handled by apply_statement_penalty_fees), or a one-off early '
  'settlement (handled by settle_installment_plan_early).';

-- A rule with no calculation configured yet ("I don't know the rate")
-- still needs an identity row; the shape check now also allows "nothing
-- set", which is what an unknown/manual rule's fields look like.
alter table app_finance.credit_card_fee_rules
  drop constraint if exists fee_rules_amount_shape;
alter table app_finance.credit_card_fee_rules
  add constraint fee_rules_amount_shape check (
    (fixed_amount_minor is not null
      and percent_basis_points is null and percent_basis is null)
    or (fixed_amount_minor is null
      and percent_basis_points is not null and percent_basis is not null)
    or (fixed_amount_minor is null
      and percent_basis_points is null and percent_basis is null)
  );

create index if not exists idx_fee_rules_trigger_kind
  on app_finance.credit_card_fee_rules
  (account_id, user_id, trigger_kind, state);

-- ---------------------------------------------------------------------------
-- Rule versions: the authoritative, effective-dated calculation
-- ---------------------------------------------------------------------------

create table if not exists app_finance.credit_card_fee_rule_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rule_id uuid not null,
  version_number integer not null check (version_number >= 1),
  effective_from date not null,
  effective_until date,
  calculation_type app_finance.card_rule_calculation_type
    not null default 'fixed',
  fixed_amount_minor bigint
    check (fixed_amount_minor is null or fixed_amount_minor > 0),
  percent_basis_points integer
    check (percent_basis_points is null
      or percent_basis_points between 1 and 100000),
  percent_basis app_finance.fee_percent_basis,
  minimum_minor bigint check (minimum_minor is null or minimum_minor >= 0),
  maximum_minor bigint check (maximum_minor is null or maximum_minor >= 0),
  lookback_cycles integer
    check (lookback_cycles is null or lookback_cycles between 1 and 24),
  frequency app_finance.fee_frequency not null default 'annually',
  apply_when app_finance.foreign_apply_when,
  tolerance_minor bigint
    check (tolerance_minor is null or tolerance_minor >= 0),
  tolerance_basis_points integer
    check (tolerance_basis_points is null
      or tolerance_basis_points between 0 and 100000),
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  constraint fee_rule_versions_owner_unique unique (id, user_id),
  constraint fee_rule_versions_rule_owner_fk foreign key (rule_id, user_id)
    references app_finance.credit_card_fee_rules (id, user_id)
    on delete cascade,
  constraint fee_rule_versions_number_unique unique (rule_id, version_number),
  constraint fee_rule_versions_range
    check (effective_until is null or effective_until > effective_from),
  constraint fee_rule_versions_min_max check (
    maximum_minor is null or minimum_minor is null
    or maximum_minor >= minimum_minor
  ),
  constraint fee_rule_versions_shape check (
    (calculation_type = 'fixed'
      and fixed_amount_minor is not null and percent_basis_points is null)
    or (calculation_type = 'percentage'
      and fixed_amount_minor is null and percent_basis_points is not null
      and percent_basis is not null)
    or (calculation_type = 'fixed_plus_percentage'
      and fixed_amount_minor is not null and percent_basis_points is not null
      and percent_basis is not null)
    or (calculation_type = 'manual'
      and fixed_amount_minor is null and percent_basis_points is null)
  )
);

create index if not exists idx_fee_rule_versions_rule
  on app_finance.credit_card_fee_rule_versions
  (rule_id, user_id, effective_from);

alter table app_finance.credit_card_fee_rule_versions enable row level security;
drop policy if exists credit_card_fee_rule_versions_select
  on app_finance.credit_card_fee_rule_versions;
create policy credit_card_fee_rule_versions_select
  on app_finance.credit_card_fee_rule_versions
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_rule_versions_insert
  on app_finance.credit_card_fee_rule_versions;
create policy credit_card_fee_rule_versions_insert
  on app_finance.credit_card_fee_rule_versions
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_rule_versions_delete
  on app_finance.credit_card_fee_rule_versions;
create policy credit_card_fee_rule_versions_delete
  on app_finance.credit_card_fee_rule_versions
  for delete to authenticated using ((select auth.uid()) = user_id);
-- Needed so create_fee_rule_version can close the previously open-ended
-- version's effective_until; actual write access is still RPC-only via
-- the protect trigger below.
drop policy if exists credit_card_fee_rule_versions_update
  on app_finance.credit_card_fee_rule_versions;
create policy credit_card_fee_rule_versions_update
  on app_finance.credit_card_fee_rule_versions
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- No overlapping effective ranges for the same rule (mandatory: rule
-- versioning must reject overlapping effective date ranges).
create or replace function app_private.enforce_no_overlapping_rule_versions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from app_finance.credit_card_fee_rule_versions v
    where v.rule_id = new.rule_id
      and v.id <> new.id
      and v.effective_from < coalesce(new.effective_until, 'infinity'::date)
      and coalesce(v.effective_until, 'infinity'::date) > new.effective_from
  ) then
    raise exception
      'overlapping_version: rule versions cannot share effective dates';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_no_overlapping_rule_versions
  on app_finance.credit_card_fee_rule_versions;
create trigger trg_enforce_no_overlapping_rule_versions
  before insert or update on app_finance.credit_card_fee_rule_versions
  for each row execute function
    app_private.enforce_no_overlapping_rule_versions();

-- Versions are written only by the rule-versioning RPCs (overlap/sequence
-- invariants need a single transactional writer), reusing the existing
-- facility-internal bypass flag.
create or replace function app_private.protect_fee_rule_versions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app_finance.facility_internal', true), '')
      = 'on'
    or (select auth.uid()) is null then
    return coalesce(new, old);
  end if;
  raise exception
    'fee_rule_version_locked: change rates from the card rules screen';
end;
$$;

drop trigger if exists trg_protect_fee_rule_versions
  on app_finance.credit_card_fee_rule_versions;
create trigger trg_protect_fee_rule_versions
  before insert or update or delete
  on app_finance.credit_card_fee_rule_versions
  for each row execute function app_private.protect_fee_rule_versions();

-- ---------------------------------------------------------------------------
-- Generated charges: version link, trigger/statement idempotency,
-- expected-vs-actual reconciliation
-- ---------------------------------------------------------------------------

alter table app_finance.credit_card_fee_charges
  add column if not exists rule_version_id uuid,
  add column if not exists trigger_transaction_id uuid,
  add column if not exists statement_cycle_id uuid,
  add column if not exists expected_amount_minor bigint,
  add column if not exists actual_amount_minor bigint,
  add column if not exists reconciliation_status
    app_finance.charge_reconciliation_status not null default 'confirmed',
  add column if not exists calculation_snapshot jsonb not null default '{}',
  add column if not exists reconciled_at timestamptz,
  add column if not exists reconciliation_notes text
    check (reconciliation_notes is null
      or char_length(reconciliation_notes) <= 1000);

-- Backfill: every historical charge is treated as already reconciled at
-- the amount it actually booked (no financial history is fabricated or
-- changed; see the migration header).
update app_finance.credit_card_fee_charges
  set expected_amount_minor = amount_minor,
    actual_amount_minor = amount_minor
  where expected_amount_minor is null;

alter table app_finance.credit_card_fee_charges
  drop constraint if exists fee_charges_version_owner_fk;
alter table app_finance.credit_card_fee_charges
  add constraint fee_charges_version_owner_fk
  foreign key (rule_version_id, user_id)
  references app_finance.credit_card_fee_rule_versions (id, user_id);
alter table app_finance.credit_card_fee_charges
  drop constraint if exists fee_charges_trigger_tx_owner_fk;
alter table app_finance.credit_card_fee_charges
  add constraint fee_charges_trigger_tx_owner_fk
  foreign key (trigger_transaction_id, user_id)
  references app_finance.financial_transactions (id, user_id)
  on delete set null (trigger_transaction_id);
alter table app_finance.credit_card_fee_charges
  drop constraint if exists fee_charges_cycle_owner_fk;
alter table app_finance.credit_card_fee_charges
  add constraint fee_charges_cycle_owner_fk
  foreign key (statement_cycle_id, user_id)
  references app_finance.credit_card_statement_cycles (id, user_id)
  on delete set null (statement_cycle_id);

-- Idempotency generalizes from "once per rule per date" to "once per
-- rule, date, triggering transaction, and statement cycle" so a
-- per-transaction fee (many per day) and a schedule fee (one per date)
-- both stay safe to retry, while old schedule-fee behavior is unchanged
-- (trigger_transaction_id and statement_cycle_id are both null for them,
-- same as the constraint they replace).
alter table app_finance.credit_card_fee_charges
  drop constraint if exists fee_charges_once_per_date;
drop index if exists app_finance.idx_fee_charges_idempotent;
create unique index idx_fee_charges_idempotent
  on app_finance.credit_card_fee_charges (
    rule_id, charged_on,
    coalesce(trigger_transaction_id, '00000000-0000-0000-0000-000000000000'),
    coalesce(statement_cycle_id, '00000000-0000-0000-0000-000000000000')
  );

create index if not exists idx_fee_charges_version
  on app_finance.credit_card_fee_charges (rule_version_id, user_id);
create index if not exists idx_fee_charges_trigger_tx
  on app_finance.credit_card_fee_charges (trigger_transaction_id, user_id)
  where trigger_transaction_id is not null;
create index if not exists idx_fee_charges_cycle
  on app_finance.credit_card_fee_charges (statement_cycle_id, user_id)
  where statement_cycle_id is not null;

-- Reconciliation needs to correct a previously generated charge; the
-- protect trigger already restricts writes to the facility-internal flag
-- (RPC-only), so an update policy is safe to add alongside it.
drop policy if exists credit_card_fee_charges_update
  on app_finance.credit_card_fee_charges;
create policy credit_card_fee_charges_update
  on app_finance.credit_card_fee_charges
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Backfill: one version per existing rule, preserving exact prior values
-- ---------------------------------------------------------------------------

insert into app_finance.credit_card_fee_rule_versions (
  user_id, rule_id, version_number, effective_from, effective_until,
  calculation_type, fixed_amount_minor, percent_basis_points, percent_basis,
  frequency
)
select
  r.user_id, r.id, 1, r.starts_on, null,
  case
    when r.fixed_amount_minor is not null then 'fixed'
    when r.percent_basis_points is not null then 'percentage'
    else 'manual'
  end::app_finance.card_rule_calculation_type,
  r.fixed_amount_minor, r.percent_basis_points, r.percent_basis, r.frequency
from app_finance.credit_card_fee_rules r
where not exists (
  select 1 from app_finance.credit_card_fee_rule_versions v
  where v.rule_id = r.id
);

update app_finance.credit_card_fee_charges c
  set rule_version_id = v.id
  from app_finance.credit_card_fee_rule_versions v
  where v.rule_id = c.rule_id and v.version_number = 1
    and c.rule_version_id is null;

alter table app_finance.credit_card_fee_charges
  alter column expected_amount_minor set not null,
  alter column rule_version_id set not null;

-- ---------------------------------------------------------------------------
-- Version resolution
-- ---------------------------------------------------------------------------

-- The version effective for one rule on one business date, or no rows if
-- the rule has never been versioned (a legacy or directly-inserted row).
create or replace function app_finance.resolve_fee_rule_calculation(
  p_rule_id uuid,
  p_user_id uuid,
  p_on date
)
returns table (
  version_id uuid,
  calculation_type app_finance.card_rule_calculation_type,
  fixed_amount_minor bigint,
  percent_basis_points integer,
  percent_basis app_finance.fee_percent_basis,
  minimum_minor bigint,
  maximum_minor bigint,
  lookback_cycles integer,
  frequency app_finance.fee_frequency,
  apply_when app_finance.foreign_apply_when,
  tolerance_minor bigint,
  tolerance_basis_points integer
)
language sql
stable
set search_path = ''
as $$
  select v.id, v.calculation_type, v.fixed_amount_minor,
      v.percent_basis_points, v.percent_basis, v.minimum_minor,
      v.maximum_minor, v.lookback_cycles, v.frequency, v.apply_when,
      v.tolerance_minor, v.tolerance_basis_points
    from app_finance.credit_card_fee_rule_versions v
    where v.rule_id = p_rule_id and v.user_id = p_user_id
      and v.effective_from <= p_on
      and (v.effective_until is null or v.effective_until > p_on)
    order by v.effective_from desc
    limit 1;
$$;

revoke execute on function app_finance.resolve_fee_rule_calculation(
  uuid, uuid, date
) from public, anon;
grant execute on function app_finance.resolve_fee_rule_calculation(
  uuid, uuid, date
) to authenticated, service_role;

-- Highest per-statement charge total in the N cycles closing before a
-- date — the generic "quarterly tax on the highest recent statement"
-- calculation pattern (section: historical-lookback rules).
create or replace function app_finance.highest_statement_due_minor(
  p_account_id uuid,
  p_before date,
  p_lookback_cycles integer
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(max(y.charges_minor), 0)::bigint
  from (
    select charges_minor from app_finance.credit_card_statement_summaries
    where account_id = p_account_id and cycle_close < p_before
    order by cycle_close desc
    limit greatest(coalesce(p_lookback_cycles, 3), 1)
  ) y;
$$;

revoke execute on function app_finance.highest_statement_due_minor(
  uuid, date, integer
) from public, anon;
grant execute on function app_finance.highest_statement_due_minor(
  uuid, date, integer
) to authenticated, service_role;

-- A rule that predates versioning (or was inserted directly against the
-- table) is lazily given a version 1 that mirrors its own legacy
-- calculation columns, so every generated charge always links to a real
-- version without rewriting any rule's directly-set values. Lives in
-- app_finance (not app_private) because apply_credit_card_fees calls it
-- directly as the plain `authenticated` role; the explicit owner check
-- keeps that safe even though the function is technically callable via
-- RPC too.
create or replace function app_finance.ensure_fee_rule_version(
  p_rule app_finance.credit_card_fee_rules
)
returns app_finance.credit_card_fee_rule_versions
language plpgsql
set search_path = ''
as $$
declare
  v_version app_finance.credit_card_fee_rule_versions;
  v_calc_type app_finance.card_rule_calculation_type;
  v_next_number integer;
begin
  if p_rule.user_id <> (select auth.uid()) then
    raise exception 'not_authenticated';
  end if;

  select v.* into v_version
    from app_finance.resolve_fee_rule_calculation(
      p_rule.id, p_rule.user_id, p_rule.starts_on
    ) r
    join app_finance.credit_card_fee_rule_versions v on v.id = r.version_id;
  if found then
    return v_version;
  end if;

  v_calc_type := case
    when p_rule.fixed_amount_minor is not null then 'fixed'
    when p_rule.percent_basis_points is not null then 'percentage'
    else 'manual'
  end;
  select coalesce(max(version_number), 0) + 1 into v_next_number
    from app_finance.credit_card_fee_rule_versions where rule_id = p_rule.id;

  insert into app_finance.credit_card_fee_rule_versions (
    user_id, rule_id, version_number, effective_from, calculation_type,
    fixed_amount_minor, percent_basis_points, percent_basis, frequency
  ) values (
    p_rule.user_id, p_rule.id, v_next_number, p_rule.starts_on, v_calc_type,
    p_rule.fixed_amount_minor, p_rule.percent_basis_points,
    p_rule.percent_basis, p_rule.frequency
  )
  returning * into v_version;
  return v_version;
end;
$$;

-- The version effective for a rule on a business date, lazily backfilling
-- one from the rule's own legacy columns when none exists yet. Always
-- returns a real, persisted version row.
create or replace function app_finance.resolve_or_create_fee_rule_version(
  p_rule app_finance.credit_card_fee_rules,
  p_on date
)
returns app_finance.credit_card_fee_rule_versions
language plpgsql
set search_path = ''
as $$
declare
  v_version app_finance.credit_card_fee_rule_versions;
begin
  if p_rule.user_id <> (select auth.uid()) then
    raise exception 'not_authenticated';
  end if;

  select v.* into v_version
    from app_finance.credit_card_fee_rule_versions v
    where v.rule_id = p_rule.id and v.user_id = p_rule.user_id
      and v.effective_from <= p_on
      and (v.effective_until is null or v.effective_until > p_on)
    order by v.effective_from desc
    limit 1;
  if found then
    return v_version;
  end if;
  return app_finance.ensure_fee_rule_version(p_rule);
end;
$$;

revoke execute on function app_finance.ensure_fee_rule_version(
  app_finance.credit_card_fee_rules
) from public, anon;
grant execute on function app_finance.ensure_fee_rule_version(
  app_finance.credit_card_fee_rules
) to authenticated, service_role;
revoke execute on function app_finance.resolve_or_create_fee_rule_version(
  app_finance.credit_card_fee_rules, date
) from public, anon;
grant execute on function app_finance.resolve_or_create_fee_rule_version(
  app_finance.credit_card_fee_rules, date
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Recurring fee generator, rewritten to resolve calculation from the
-- effective rule version. Preserves the exact prior contract for simple
-- fixed/percent rules with no minimum/maximum/lookback: same idempotency
-- table, same schedule-advance semantics, same skip-on-zero-basis
-- behavior — the additions (minimum/maximum clamp, historical-lookback
-- basis, mutual-exclusion suppression) are all no-ops when unconfigured.
-- ---------------------------------------------------------------------------

create or replace function app_finance.apply_credit_card_fees(
  p_through date default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_through date := coalesce(p_through, current_date);
  v_rule record;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_on date;
  v_basis bigint;
  v_amount bigint;
  v_suppressed boolean;
  v_suppressed_ids uuid[];
  v_tx_id uuid;
  v_cycle_id uuid;
  v_bounds record;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Mutual exclusion must be decided from a snapshot taken before any
  -- charge in this pass runs: charging a rule advances its own cursor, so
  -- re-checking "is the other rule also still due" against live table
  -- state mid-loop would stop seeing the winner as due the moment it's
  -- processed, letting every later rule in the group through too.
  select array_agg(loser.id) into v_suppressed_ids
    from app_finance.credit_card_fee_rules loser
    where loser.user_id = v_user_id
      and loser.is_active and loser.state = 'configured'
      and loser.trigger_kind = 'schedule'
      and loser.mutual_exclusion_group is not null
      and coalesce(loser.next_charge_on, loser.starts_on) <= v_through
      and exists (
        select 1 from app_finance.credit_card_fee_rules winner
        where winner.account_id = loser.account_id
          and winner.mutual_exclusion_group = loser.mutual_exclusion_group
          and winner.id <> loser.id
          and winner.user_id = v_user_id
          and winner.is_active and winner.state = 'configured'
          and winner.trigger_kind = 'schedule'
          and coalesce(winner.next_charge_on, winner.starts_on) <= v_through
          and (winner.priority < loser.priority
            or (winner.priority = loser.priority
              and winner.created_at < loser.created_at))
      );

  for v_rule in
    select r.*, a.currency_code, s.statement_day, s.default_due_day,
        s.facility_status, s.credit_limit_minor
    from app_finance.credit_card_fee_rules r
    join app_finance.accounts a on a.id = r.account_id
    join app_finance.credit_facility_settings s on s.account_id = r.account_id
    where r.user_id = v_user_id
      and r.is_active
      and r.state = 'configured'
      and r.trigger_kind = 'schedule'
      and not a.is_archived
      and s.facility_status = 'active'
      and coalesce(r.next_charge_on, r.starts_on) <= v_through
    order by r.created_at
  loop
    v_on := coalesce(v_rule.next_charge_on, v_rule.starts_on);

    perform set_config('app_finance.facility_internal', 'on', true);

    -- v_rule is a wider record (joined with account/settings columns), so
    -- re-select the pure row type the helper functions expect.
    v_calc := app_finance.resolve_or_create_fee_rule_version(
      (select fr from app_finance.credit_card_fee_rules fr
        where fr.id = v_rule.id),
      v_on
    );

    -- Mutual exclusion: among rules sharing a group that were also due at
    -- the start of this pass, only the lowest-priority (then
    -- earliest-created) one may generate; the rest advance their schedule
    -- without charging (decided from the pre-loop snapshot above).
    v_suppressed := v_rule.id = any(v_suppressed_ids);

    if v_suppressed or v_calc.calculation_type = 'manual' then
      v_amount := 0;
    else
      v_basis := case v_calc.percent_basis
        when 'credit_limit' then v_rule.credit_limit_minor
        when 'outstanding_balance' then
          app_finance.facility_outstanding_minor(v_rule.account_id)
        when 'highest_statement_due_lookback' then
          app_finance.highest_statement_due_minor(
            v_rule.account_id, v_on, v_calc.lookback_cycles
          )
        when 'statement_balance' then coalesce((
          select y.remaining_minor
          from app_finance.credit_card_statement_summaries y
          where y.account_id = v_rule.account_id
          order by y.cycle_close desc limit 1
        ), 0)
        else 0
      end;

      v_amount := case v_calc.calculation_type
        when 'fixed' then coalesce(v_calc.fixed_amount_minor, 0)
        when 'percentage' then
          round(v_basis::numeric * coalesce(v_calc.percent_basis_points, 0)
            / 10000)::bigint
        when 'fixed_plus_percentage' then
          coalesce(v_calc.fixed_amount_minor, 0) + round(
            v_basis::numeric * coalesce(v_calc.percent_basis_points, 0)
              / 10000
          )::bigint
        else 0
      end;

      if v_calc.calculation_type in ('percentage', 'fixed_plus_percentage')
      then
        if v_calc.minimum_minor is not null then
          v_amount := greatest(v_amount, v_calc.minimum_minor);
        end if;
        if v_calc.maximum_minor is not null then
          v_amount := least(v_amount, v_calc.maximum_minor);
        end if;
      end if;
    end if;

    if v_amount <= 0 then
      -- Nothing to charge (zero basis, manual/unknown, or suppressed by
      -- mutual exclusion); still move the schedule forward.
      update app_finance.credit_card_fee_rules
        set next_charge_on = case v_calc.frequency
            when 'once' then null
            when 'monthly' then (v_on + make_interval(months => 1))::date
            when 'quarterly' then (v_on + make_interval(months => 3))::date
            else (v_on + make_interval(years => 1))::date
          end,
          is_active = (v_calc.frequency <> 'once')
        where id = v_rule.id;
      perform set_config('app_finance.facility_internal', '', true);
      continue;
    end if;

    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    ) values (
      v_user_id, 'expense', v_on, v_amount, v_rule.currency_code,
      v_rule.account_id, v_rule.category_id, v_rule.name
    )
    returning id into v_tx_id;

    begin
      insert into app_finance.credit_card_fee_charges (
        user_id, rule_id, rule_version_id, transaction_id, charged_on,
        amount_minor, expected_amount_minor, actual_amount_minor,
        calculation_snapshot
      ) values (
        v_user_id, v_rule.id, v_calc.id, v_tx_id, v_on, v_amount,
        v_amount, v_amount,
        jsonb_build_object(
          'calculation_type', v_calc.calculation_type,
          'basis_minor', v_basis,
          'percent_basis', v_calc.percent_basis,
          'percent_basis_points', v_calc.percent_basis_points,
          'fixed_amount_minor', v_calc.fixed_amount_minor,
          'minimum_minor', v_calc.minimum_minor,
          'maximum_minor', v_calc.maximum_minor
        )
      );
    exception when unique_violation then
      -- Another run already charged this date; drop the duplicate expense.
      delete from app_finance.financial_transactions where id = v_tx_id;
      perform set_config('app_finance.facility_internal', '', true);
      continue;
    end;

    if v_rule.statement_day is not null then
      select * into v_bounds from app_finance.statement_bounds_for(
        v_rule.statement_day, v_rule.default_due_day, v_on
      );
      insert into app_finance.credit_card_statement_cycles (
        user_id, account_id, cycle_start, cycle_close, due_on
      ) values (
        v_user_id, v_rule.account_id, v_bounds.cycle_start,
        v_bounds.cycle_close, v_bounds.due_on
      )
      on conflict (account_id, cycle_close) do nothing;
      select id into v_cycle_id
        from app_finance.credit_card_statement_cycles
        where account_id = v_rule.account_id
          and cycle_close = v_bounds.cycle_close;
      insert into app_finance.credit_card_statement_items (
        user_id, cycle_id, transaction_id, amount_minor
      ) values (v_user_id, v_cycle_id, v_tx_id, v_amount);
      update app_finance.credit_card_fee_charges
        set statement_cycle_id = v_cycle_id
        where rule_id = v_rule.id and charged_on = v_on
          and trigger_transaction_id is null;
    end if;

    update app_finance.credit_card_fee_rules
      set next_charge_on = case v_calc.frequency
          when 'once' then null
          when 'monthly' then (v_on + make_interval(months => 1))::date
          when 'quarterly' then (v_on + make_interval(months => 3))::date
          else (v_on + make_interval(years => 1))::date
        end,
        is_active = (v_calc.frequency <> 'once')
      where id = v_rule.id;

    perform set_config('app_finance.facility_internal', '', true);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rule identity + first version (create), or identity-only edit (update).
-- Changing a rate never goes through here — see create_fee_rule_version.
-- ---------------------------------------------------------------------------

create or replace function app_finance.save_credit_card_fee_rule(
  p_account_id uuid,
  p_name text,
  p_fee_type app_finance.card_fee_type,
  p_category_id uuid,
  p_state app_finance.card_rule_state default 'configured',
  p_trigger_kind app_finance.card_rule_trigger default 'schedule',
  p_starts_on date default current_date,
  p_calculation_type app_finance.card_rule_calculation_type default 'manual',
  p_fixed_amount_minor bigint default null,
  p_percent_basis_points integer default null,
  p_percent_basis app_finance.fee_percent_basis default null,
  p_minimum_minor bigint default null,
  p_maximum_minor bigint default null,
  p_lookback_cycles integer default null,
  p_frequency app_finance.fee_frequency default 'annually',
  p_apply_when app_finance.foreign_apply_when default null,
  p_tolerance_minor bigint default null,
  p_tolerance_basis_points integer default null,
  p_mutual_exclusion_group text default null,
  p_priority integer default 100,
  p_notes text default null,
  p_rule_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
  v_calc_type app_finance.card_rule_calculation_type;
  v_fixed bigint;
  v_points integer;
  v_basis app_finance.fee_percent_basis;
  v_rule_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select a.id, a.account_type into v_account
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived;
  if v_account is null
    or app_finance.account_role(v_account.account_type) <> 'liability' then
    raise exception
      'invalid_account: card rules require a credit card or BNPL account';
  end if;
  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  -- An unknown/disabled rule never carries a stale rate: only a
  -- configured rule may specify a real calculation.
  if p_state = 'configured' then
    if p_calculation_type = 'manual' then
      raise exception
        'invalid_rule: a configured rule needs a calculation';
    end if;
    v_calc_type := p_calculation_type;
    v_fixed := case when p_calculation_type in ('fixed', 'fixed_plus_percentage')
      then p_fixed_amount_minor end;
    v_points := case when p_calculation_type in ('percentage', 'fixed_plus_percentage')
      then p_percent_basis_points end;
    v_basis := case when p_calculation_type in ('percentage', 'fixed_plus_percentage')
      then p_percent_basis end;
  else
    v_calc_type := 'manual';
    v_fixed := null;
    v_points := null;
    v_basis := null;
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  if p_rule_id is null then
    insert into app_finance.credit_card_fee_rules (
      user_id, account_id, name, fee_type, category_id, frequency,
      starts_on, state, trigger_kind, mutual_exclusion_group, priority,
      is_active, notes, fixed_amount_minor, percent_basis_points,
      percent_basis
    ) values (
      v_user_id, p_account_id, p_name, p_fee_type, p_category_id,
      p_frequency, p_starts_on, p_state, p_trigger_kind,
      p_mutual_exclusion_group, p_priority, (p_state = 'configured'),
      p_notes, v_fixed, v_points, v_basis
    )
    returning id into v_rule_id;

    insert into app_finance.credit_card_fee_rule_versions (
      user_id, rule_id, version_number, effective_from, calculation_type,
      fixed_amount_minor, percent_basis_points, percent_basis,
      minimum_minor, maximum_minor, lookback_cycles, frequency, apply_when,
      tolerance_minor, tolerance_basis_points, notes
    ) values (
      v_user_id, v_rule_id, 1, p_starts_on, v_calc_type, v_fixed, v_points,
      v_basis, p_minimum_minor, p_maximum_minor, p_lookback_cycles,
      p_frequency, p_apply_when, p_tolerance_minor, p_tolerance_basis_points,
      p_notes
    );
  else
    update app_finance.credit_card_fee_rules set
      name = p_name,
      category_id = p_category_id,
      state = p_state,
      is_active = (p_state = 'configured'),
      mutual_exclusion_group = p_mutual_exclusion_group,
      priority = p_priority,
      notes = p_notes
    where id = p_rule_id and account_id = p_account_id and user_id = v_user_id
    returning id into v_rule_id;
    if v_rule_id is null then
      raise exception 'not_found: card rule';
    end if;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_rule_id;
end;
$$;

revoke execute on function app_finance.save_credit_card_fee_rule(
  uuid, text, app_finance.card_fee_type, uuid, app_finance.card_rule_state,
  app_finance.card_rule_trigger, date, app_finance.card_rule_calculation_type,
  bigint, integer, app_finance.fee_percent_basis, bigint, bigint, integer,
  app_finance.fee_frequency, app_finance.foreign_apply_when, bigint, integer,
  text, integer, text, uuid
) from public, anon;
grant execute on function app_finance.save_credit_card_fee_rule(
  uuid, text, app_finance.card_fee_type, uuid, app_finance.card_rule_state,
  app_finance.card_rule_trigger, date, app_finance.card_rule_calculation_type,
  bigint, integer, app_finance.fee_percent_basis, bigint, bigint, integer,
  app_finance.fee_frequency, app_finance.foreign_apply_when, bigint, integer,
  text, integer, text, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Rate change: "use this new value starting from" — never rewrites history
-- ---------------------------------------------------------------------------

create or replace function app_finance.create_fee_rule_version(
  p_rule_id uuid,
  p_effective_from date,
  p_calculation_type app_finance.card_rule_calculation_type,
  p_fixed_amount_minor bigint default null,
  p_percent_basis_points integer default null,
  p_percent_basis app_finance.fee_percent_basis default null,
  p_minimum_minor bigint default null,
  p_maximum_minor bigint default null,
  p_lookback_cycles integer default null,
  p_frequency app_finance.fee_frequency default 'annually',
  p_apply_when app_finance.foreign_apply_when default null,
  p_tolerance_minor bigint default null,
  p_tolerance_basis_points integer default null,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_rule record;
  v_latest app_finance.credit_card_fee_rule_versions;
  v_version_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_effective_from < current_date then
    raise exception
      'invalid_date: a new rate can only start today or in the future';
  end if;

  select id into v_rule from app_finance.credit_card_fee_rules
    where id = p_rule_id and user_id = v_user_id
    for update;
  if v_rule is null then
    raise exception 'not_found: card rule';
  end if;

  select * into v_latest from app_finance.credit_card_fee_rule_versions
    where rule_id = p_rule_id and user_id = v_user_id
    order by effective_from desc limit 1;
  -- v_latest is a full-row composite with nullable columns (effective_until,
  -- minimum_minor, ...); "IS NOT NULL" on a row requires every field to be
  -- non-null, so it would wrongly read as "not found" whenever an open-
  -- ended version's effective_until is null. Test the identity column
  -- instead, which is always present on a genuinely selected row.
  if v_latest.id is not null and p_effective_from <= v_latest.effective_from
  then
    raise exception
      'invalid_date: must start after the latest scheduled version';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  if v_latest.id is not null then
    update app_finance.credit_card_fee_rule_versions
      set effective_until = p_effective_from
      where id = v_latest.id;
  end if;

  insert into app_finance.credit_card_fee_rule_versions (
    user_id, rule_id, version_number, effective_from, calculation_type,
    fixed_amount_minor, percent_basis_points, percent_basis, minimum_minor,
    maximum_minor, lookback_cycles, frequency, apply_when, tolerance_minor,
    tolerance_basis_points, notes
  ) values (
    v_user_id, p_rule_id, coalesce(v_latest.version_number, 0) + 1,
    p_effective_from, p_calculation_type, p_fixed_amount_minor,
    p_percent_basis_points, p_percent_basis, p_minimum_minor,
    p_maximum_minor, p_lookback_cycles, p_frequency, p_apply_when,
    p_tolerance_minor, p_tolerance_basis_points, p_notes
  )
  returning id into v_version_id;

  -- A rule that gets a real rate becomes configured automatically; the
  -- "unknown" prompt stops once the user actually fills it in.
  update app_finance.credit_card_fee_rules
    set state = 'configured', is_active = true
    where id = p_rule_id and state <> 'configured';

  perform set_config('app_finance.facility_internal', '', true);
  return v_version_id;
end;
$$;

revoke execute on function app_finance.create_fee_rule_version(
  uuid, date, app_finance.card_rule_calculation_type, bigint, integer,
  app_finance.fee_percent_basis, bigint, bigint, integer,
  app_finance.fee_frequency, app_finance.foreign_apply_when, bigint, integer,
  text
) from public, anon;
grant execute on function app_finance.create_fee_rule_version(
  uuid, date, app_finance.card_rule_calculation_type, bigint, integer,
  app_finance.fee_percent_basis, bigint, bigint, integer,
  app_finance.fee_frequency, app_finance.foreign_apply_when, bigint, integer,
  text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Cancel a future version before it starts
-- ---------------------------------------------------------------------------

create or replace function app_finance.cancel_fee_rule_version(
  p_version_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_version app_finance.credit_card_fee_rule_versions;
  v_sibling_count integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_version
    from app_finance.credit_card_fee_rule_versions
    where id = p_version_id and user_id = v_user_id
    for update;
  if v_version is null then
    raise exception 'not_found: rule version';
  end if;
  if v_version.effective_from <= current_date then
    raise exception 'version_active: only a future version can be cancelled';
  end if;

  select count(*) into v_sibling_count
    from app_finance.credit_card_fee_rule_versions
    where rule_id = v_version.rule_id;
  if v_sibling_count <= 1 then
    raise exception
      'last_version: a rule must keep at least one version';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  -- Delete first: reopening the sibling while the cancelled version still
  -- exists would momentarily overlap it and trip the exclusion trigger.
  delete from app_finance.credit_card_fee_rule_versions
    where id = p_version_id;

  update app_finance.credit_card_fee_rule_versions
    set effective_until = null
    where rule_id = v_version.rule_id
      and effective_until = v_version.effective_from;

  perform set_config('app_finance.facility_internal', '', true);
end;
$$;

revoke execute on function app_finance.cancel_fee_rule_version(uuid)
from public, anon;
grant execute on function app_finance.cancel_fee_rule_version(uuid)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Readable current-state view for the client: one row per rule with its
-- currently effective calculation and, if any, the next scheduled change.
-- ---------------------------------------------------------------------------

create or replace view app_finance.credit_card_fee_rule_current
with (security_invoker = on) as
  select
    r.id, r.user_id, r.account_id, r.name, r.fee_type, r.category_id,
    r.state, r.trigger_kind, r.mutual_exclusion_group, r.priority,
    r.is_active, r.starts_on, r.next_charge_on, r.notes, r.created_at,
    r.updated_at,
    cur.id as current_version_id,
    cur.version_number as current_version_number,
    cur.effective_from as current_effective_from,
    cur.calculation_type as current_calculation_type,
    cur.fixed_amount_minor as current_fixed_amount_minor,
    cur.percent_basis_points as current_percent_basis_points,
    cur.percent_basis as current_percent_basis,
    cur.minimum_minor as current_minimum_minor,
    cur.maximum_minor as current_maximum_minor,
    cur.lookback_cycles as current_lookback_cycles,
    cur.frequency as current_frequency,
    cur.apply_when as current_apply_when,
    cur.tolerance_minor as current_tolerance_minor,
    cur.tolerance_basis_points as current_tolerance_basis_points,
    upcoming.id as upcoming_version_id,
    upcoming.effective_from as upcoming_effective_from,
    upcoming.calculation_type as upcoming_calculation_type,
    upcoming.fixed_amount_minor as upcoming_fixed_amount_minor,
    upcoming.percent_basis_points as upcoming_percent_basis_points,
    upcoming.percent_basis as upcoming_percent_basis
  from app_finance.credit_card_fee_rules r
  left join lateral (
    select * from app_finance.credit_card_fee_rule_versions cv
    where cv.rule_id = r.id and cv.effective_from <= current_date
      and (cv.effective_until is null or cv.effective_until > current_date)
    order by cv.effective_from desc limit 1
  ) cur on true
  left join lateral (
    select * from app_finance.credit_card_fee_rule_versions fv
    where fv.rule_id = r.id and fv.effective_from > current_date
    order by fv.effective_from asc limit 1
  ) upcoming on true;

notify pgrst, 'reload schema';
