-- Automation for every entry kind, not only income: recurring rules for
-- expenses (from cash or a credit card) and transfers, materialized into
-- pending occurrences exactly like income sources. Nothing posts silently:
-- each occurrence waits for the user to accept, skip, or snooze it, and
-- accepting books the real transaction through the same paths the manual
-- flows use (direct expense, charge_credit_card, or create_transfer).

-- ---------------------------------------------------------------------------
-- Enums (fresh types, so same-transaction use is safe)
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'recurring_rule_kind') then
    create type app_finance.recurring_rule_kind as enum
      ('expense', 'transfer');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'recurring_frequency') then
    create type app_finance.recurring_frequency as enum
      ('weekly', 'monthly', 'quarterly', 'annually');
  end if;
end $$;

grant usage on type app_finance.recurring_rule_kind
to authenticated, service_role;
grant usage on type app_finance.recurring_frequency
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- payment_day is the day of month (1..28) for monthly/quarterly/annual
-- rules and the ISO weekday (1=Monday..7=Sunday) for weekly rules.
create table if not exists app_finance.recurring_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  rule_kind app_finance.recurring_rule_kind not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  frequency app_finance.recurring_frequency not null default 'monthly',
  payment_day smallint not null,
  start_date date not null,
  prompt_days_before smallint not null default 3
    check (prompt_days_before between 0 and 31),
  source_account_id uuid not null,
  destination_account_id uuid,
  category_id uuid,
  is_active boolean not null default true,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recurring_rules_owner_unique unique (id, user_id),
  constraint recurring_rules_source_owner_fk
    foreign key (source_account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint recurring_rules_destination_owner_fk
    foreign key (destination_account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint recurring_rules_category_owner_fk
    foreign key (category_id, user_id)
    references app_finance.transaction_categories (id, user_id),
  constraint recurring_rules_payment_day_range check (
    (frequency = 'weekly' and payment_day between 1 and 7)
    or (frequency <> 'weekly' and payment_day between 1 and 28)
  ),
  constraint recurring_rules_kind_shape check (
    (rule_kind = 'expense'
      and category_id is not null
      and destination_account_id is null)
    or (rule_kind = 'transfer'
      and category_id is null
      and destination_account_id is not null
      and destination_account_id <> source_account_id)
  )
);

drop trigger if exists trg_recurring_rules_updated_at
  on app_finance.recurring_rules;
create trigger trg_recurring_rules_updated_at
  before update on app_finance.recurring_rules
  for each row execute function app_private.set_updated_at();

create index if not exists idx_recurring_rules_user
  on app_finance.recurring_rules (user_id, is_active);
create index if not exists idx_recurring_rules_source_owner_fk
  on app_finance.recurring_rules (source_account_id, user_id);
create index if not exists idx_recurring_rules_destination_owner_fk
  on app_finance.recurring_rules (destination_account_id, user_id);
create index if not exists idx_recurring_rules_category_owner_fk
  on app_finance.recurring_rules (category_id, user_id);

-- ---------------------------------------------------------------------------
-- Occurrences
-- ---------------------------------------------------------------------------

create table if not exists app_finance.recurring_occurrences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rule_id uuid not null,
  scheduled_on date not null,
  expected_amount_minor bigint not null check (expected_amount_minor > 0),
  status app_finance.income_occurrence_status not null default 'pending',
  actual_amount_minor bigint check (actual_amount_minor > 0),
  paid_on date,
  transaction_id uuid,
  decision_at timestamptz,
  snoozed_until timestamptz,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  constraint recurring_occurrences_owner_unique unique (id, user_id),
  constraint recurring_occurrences_schedule_unique
    unique (rule_id, scheduled_on),
  constraint recurring_occurrences_rule_owner_fk
    foreign key (rule_id, user_id)
    references app_finance.recurring_rules (id, user_id) on delete cascade,
  -- transaction_id stays nullable in every state so the account-deletion
  -- cascade can detach it before removing the ledger.
  constraint recurring_occurrence_state_fields check (
    (status = 'pending'
      and actual_amount_minor is null and paid_on is null
      and transaction_id is null and decision_at is null)
    or (status = 'skipped'
      and actual_amount_minor is null and paid_on is null
      and transaction_id is null and decision_at is not null)
    or (status = 'accepted'
      and actual_amount_minor is not null and paid_on is not null
      and decision_at is not null)
  )
);

create index if not exists idx_recurring_occurrences_actionable
  on app_finance.recurring_occurrences
  (user_id, status, snoozed_until, scheduled_on, id);
create index if not exists idx_recurring_occurrences_rule
  on app_finance.recurring_occurrences (rule_id, user_id);

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table app_finance.recurring_rules enable row level security;
alter table app_finance.recurring_occurrences enable row level security;

drop policy if exists recurring_rules_select on app_finance.recurring_rules;
create policy recurring_rules_select on app_finance.recurring_rules
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists recurring_rules_insert on app_finance.recurring_rules;
create policy recurring_rules_insert on app_finance.recurring_rules
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists recurring_rules_update on app_finance.recurring_rules;
create policy recurring_rules_update on app_finance.recurring_rules
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists recurring_rules_delete on app_finance.recurring_rules;
create policy recurring_rules_delete on app_finance.recurring_rules
  for delete to authenticated using ((select auth.uid()) = user_id);

drop policy if exists recurring_occurrences_select
  on app_finance.recurring_occurrences;
create policy recurring_occurrences_select
  on app_finance.recurring_occurrences
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists recurring_occurrences_insert
  on app_finance.recurring_occurrences;
create policy recurring_occurrences_insert
  on app_finance.recurring_occurrences
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists recurring_occurrences_update
  on app_finance.recurring_occurrences;
create policy recurring_occurrences_update
  on app_finance.recurring_occurrences
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists recurring_occurrences_delete
  on app_finance.recurring_occurrences;
create policy recurring_occurrences_delete
  on app_finance.recurring_occurrences
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Creates or fully replaces a rule. Editing wipes future pending
-- occurrences so they re-materialize under the new terms; decided
-- occurrences are history and stay untouched.
create or replace function app_finance.save_recurring_rule(
  p_name text,
  p_rule_kind app_finance.recurring_rule_kind,
  p_amount_minor bigint,
  p_frequency app_finance.recurring_frequency,
  p_payment_day smallint,
  p_start_date date,
  p_prompt_days_before smallint,
  p_source_account_id uuid,
  p_destination_account_id uuid default null,
  p_category_id uuid default null,
  p_notes text default null,
  p_rule_id uuid default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source record;
  v_rule_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select a.id, a.currency_code, a.account_type into v_source
    from app_finance.accounts a
    where a.id = p_source_account_id and a.user_id = v_user_id
      and not a.is_archived;
  if v_source is null then
    raise exception 'invalid_account: account not found or archived';
  end if;

  if p_rule_kind = 'expense' then
    if app_finance.account_role(v_source.account_type) = 'liability'
      and v_source.account_type <> 'credit_card' then
      raise exception
        'invalid_account: recurring expenses need cash or a credit card';
    end if;
    if not exists (
      select 1 from app_finance.transaction_categories c
      where c.id = p_category_id and c.user_id = v_user_id
        and not c.is_archived and c.category_kind = 'expense'
    ) then
      raise exception 'invalid_category: expense category required';
    end if;
  else
    if app_finance.account_role(v_source.account_type) <> 'asset' then
      raise exception
        'invalid_account: recurring transfers move your own cash';
    end if;
    if not exists (
      select 1 from app_finance.accounts d
      where d.id = p_destination_account_id and d.user_id = v_user_id
        and not d.is_archived
        and app_finance.account_role(d.account_type) = 'asset'
        and d.currency_code = v_source.currency_code
    ) then
      raise exception
        'invalid_account: destination not found, archived, or mismatched';
    end if;
  end if;

  -- Upsert by client-generated id: an unknown id creates the rule (which
  -- makes save retries idempotent), a known id fully replaces it and
  -- clears the not-yet-decided schedule so it re-materializes under the
  -- new terms. Decided occurrences are history and stay untouched.
  if p_rule_id is not null then
    update app_finance.recurring_rules
      set name = p_name,
        rule_kind = p_rule_kind,
        amount_minor = p_amount_minor,
        currency_code = v_source.currency_code,
        frequency = p_frequency,
        payment_day = p_payment_day,
        start_date = p_start_date,
        prompt_days_before = coalesce(p_prompt_days_before, 3),
        source_account_id = p_source_account_id,
        destination_account_id = p_destination_account_id,
        category_id = p_category_id,
        is_active = coalesce(p_is_active, true),
        notes = p_notes
      where id = p_rule_id and user_id = v_user_id
      returning id into v_rule_id;
    if v_rule_id is not null then
      delete from app_finance.recurring_occurrences
        where rule_id = v_rule_id and user_id = v_user_id
          and status = 'pending';
    end if;
  end if;
  if v_rule_id is null then
    insert into app_finance.recurring_rules (
      id, user_id, name, rule_kind, amount_minor, currency_code, frequency,
      payment_day, start_date, prompt_days_before, source_account_id,
      destination_account_id, category_id, is_active, notes
    ) values (
      coalesce(p_rule_id, gen_random_uuid()), v_user_id, p_name,
      p_rule_kind, p_amount_minor, v_source.currency_code, p_frequency,
      p_payment_day, p_start_date, coalesce(p_prompt_days_before, 3),
      p_source_account_id, p_destination_account_id, p_category_id,
      coalesce(p_is_active, true), p_notes
    )
    returning id into v_rule_id;
  end if;
  return v_rule_id;
end;
$$;

-- Fills the pending schedule through p_through_date; safe to call on
-- every read thanks to the (rule_id, scheduled_on) unique key.
create or replace function app_finance.materialize_recurring_occurrences(
  p_through_date date
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_rule record;
  v_date date;
  v_count integer := 0;
  v_inserted integer;
  v_month date;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_through_date > current_date + 62 then
    raise exception 'invalid_date: lookahead is limited to two months';
  end if;

  for v_rule in
    select * from app_finance.recurring_rules
    where user_id = v_user_id and is_active
  loop
    if v_rule.frequency = 'weekly' then
      -- First matching ISO weekday on or after the start date.
      v_date := v_rule.start_date
        + ((v_rule.payment_day - extract(isodow from v_rule.start_date)::int
            + 7) % 7);
      while v_date <= p_through_date loop
        insert into app_finance.recurring_occurrences (
          user_id, rule_id, scheduled_on, expected_amount_minor
        ) values (v_user_id, v_rule.id, v_date, v_rule.amount_minor)
        on conflict (rule_id, scheduled_on) do nothing;
        get diagnostics v_inserted = row_count;
        v_count := v_count + v_inserted;
        v_date := v_date + 7;
      end loop;
    else
      v_month := date_trunc('month', v_rule.start_date)::date;
      while make_date(
        extract(year from v_month)::int,
        extract(month from v_month)::int,
        v_rule.payment_day
      ) <= p_through_date loop
        v_date := make_date(
          extract(year from v_month)::int,
          extract(month from v_month)::int,
          v_rule.payment_day
        );
        if v_date >= v_rule.start_date then
          insert into app_finance.recurring_occurrences (
            user_id, rule_id, scheduled_on, expected_amount_minor
          ) values (v_user_id, v_rule.id, v_date, v_rule.amount_minor)
          on conflict (rule_id, scheduled_on) do nothing;
          get diagnostics v_inserted = row_count;
          v_count := v_count + v_inserted;
        end if;
        v_month := (v_month + make_interval(months => case v_rule.frequency
          when 'monthly' then 1
          when 'quarterly' then 3
          else 12
        end))::date;
      end loop;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Accepting books the real entry through the same paths as manual ones:
-- a plain expense, a credit-card charge on its statement cycle, or an
-- atomic transfer. Idempotent per occurrence.
create or replace function app_finance.accept_recurring_occurrence(
  p_occurrence_id uuid,
  p_actual_amount_minor bigint,
  p_paid_on date,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_occurrence record;
  v_rule record;
  v_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_actual_amount_minor is null or p_actual_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select o.* into v_occurrence
    from app_finance.recurring_occurrences o
    where o.id = p_occurrence_id and o.user_id = v_user_id
    for update;
  if v_occurrence is null then
    raise exception 'not_found: recurring occurrence';
  end if;
  if v_occurrence.status = 'accepted' then
    return v_occurrence.transaction_id;
  end if;
  if v_occurrence.status <> 'pending' then
    raise exception 'already_decided: this entry was already handled';
  end if;

  select r.* into v_rule from app_finance.recurring_rules r
    where r.id = v_occurrence.rule_id and r.user_id = v_user_id;

  if v_rule.rule_kind = 'transfer' then
    v_tx_id := app_finance.create_transfer(
      v_rule.source_account_id, v_rule.destination_account_id,
      p_actual_amount_minor, p_paid_on, p_notes
    );
  else
    if exists (
      select 1 from app_finance.accounts a
      where a.id = v_rule.source_account_id
        and a.account_type = 'credit_card'
    ) then
      v_tx_id := app_finance.charge_credit_card(
        v_rule.source_account_id, v_rule.name, v_rule.category_id,
        p_paid_on, p_actual_amount_minor, p_notes, null
      );
    else
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, category_id, title, notes
      ) values (
        v_user_id, 'expense', p_paid_on, p_actual_amount_minor,
        v_rule.currency_code, v_rule.source_account_id, v_rule.category_id,
        v_rule.name, p_notes
      )
      returning id into v_tx_id;
    end if;
  end if;

  update app_finance.recurring_occurrences
    set status = 'accepted',
      actual_amount_minor = p_actual_amount_minor,
      paid_on = p_paid_on,
      transaction_id = v_tx_id,
      decision_at = now(),
      notes = coalesce(p_notes, notes)
    where id = p_occurrence_id and user_id = v_user_id;

  return v_tx_id;
end;
$$;

create or replace function app_finance.skip_recurring_occurrence(
  p_occurrence_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  update app_finance.recurring_occurrences
    set status = 'skipped', decision_at = now()
    where id = p_occurrence_id and user_id = v_user_id
      and status = 'pending';
  if not found then
    raise exception 'not_found_or_already_decided: nothing to skip';
  end if;
end;
$$;

create or replace function app_finance.snooze_recurring_occurrence(
  p_occurrence_id uuid,
  p_snoozed_until timestamptz
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_snoozed_until <= now()
    or p_snoozed_until > now() + interval '7 days' then
    raise exception 'invalid_date: snooze up to seven days ahead';
  end if;
  update app_finance.recurring_occurrences
    set snoozed_until = p_snoozed_until
    where id = p_occurrence_id and user_id = v_user_id
      and status = 'pending';
  if not found then
    raise exception 'not_found_or_already_decided: nothing to snooze';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on
  app_finance.recurring_rules,
  app_finance.recurring_occurrences
to authenticated, service_role;

revoke execute on function app_finance.save_recurring_rule(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, text, uuid, boolean
) from public, anon;
grant execute on function app_finance.save_recurring_rule(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, text, uuid, boolean
) to authenticated, service_role;

revoke execute on function
  app_finance.materialize_recurring_occurrences(date) from public, anon;
grant execute on function
  app_finance.materialize_recurring_occurrences(date)
to authenticated, service_role;

revoke execute on function app_finance.accept_recurring_occurrence(
  uuid, bigint, date, text
) from public, anon;
grant execute on function app_finance.accept_recurring_occurrence(
  uuid, bigint, date, text
) to authenticated, service_role;

revoke execute on function app_finance.skip_recurring_occurrence(uuid)
from public, anon;
grant execute on function app_finance.skip_recurring_occurrence(uuid)
to authenticated, service_role;

revoke execute on function app_finance.snooze_recurring_occurrence(
  uuid, timestamptz
) from public, anon;
grant execute on function app_finance.snooze_recurring_occurrence(
  uuid, timestamptz
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Deletion cascade and realtime
-- ---------------------------------------------------------------------------

create or replace function app_core.delete_finance_suit_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then
    raise exception 'user_id_required';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  update app_salary.salary_periods
    set paid_transaction_id = null
    where user_id = p_user_id;
  update app_finance.income_occurrences
    set primary_transaction_id = null
    where user_id = p_user_id;
  update app_finance.financial_transactions
    set salary_period_id = null, income_occurrence_id = null
    where user_id = p_user_id;

  delete from app_core.notification_outbox where user_id = p_user_id;
  delete from app_core.push_devices where user_id = p_user_id;
  delete from app_core.notification_preferences where user_id = p_user_id;

  delete from app_finance.recurring_occurrences where user_id = p_user_id;
  delete from app_finance.recurring_rules where user_id = p_user_id;
  delete from app_finance.installment_payment_allocations
    where user_id = p_user_id;
  delete from app_finance.credit_card_statement_allocations
    where user_id = p_user_id;
  delete from app_finance.credit_card_fee_charges where user_id = p_user_id;
  delete from app_finance.credit_card_statement_items
    where user_id = p_user_id;
  delete from app_finance.credit_card_statement_cycles
    where user_id = p_user_id;
  delete from app_finance.credit_card_fee_rules where user_id = p_user_id;
  delete from app_finance.installment_plan_revisions
    where user_id = p_user_id;
  delete from app_finance.installment_dues where user_id = p_user_id;
  delete from app_finance.installment_plans where user_id = p_user_id;
  delete from app_finance.credit_facility_settings where user_id = p_user_id;
  delete from app_finance.held_amounts where user_id = p_user_id;
  delete from app_finance.transaction_macro_items where user_id = p_user_id;
  delete from app_finance.transaction_macros where user_id = p_user_id;
  delete from app_finance.financial_transactions where user_id = p_user_id;
  delete from app_finance.income_occurrences where user_id = p_user_id;
  delete from app_finance.income_source_allocations where user_id = p_user_id;
  delete from app_finance.income_sources where user_id = p_user_id;
  delete from app_salary.salary_periods where user_id = p_user_id;
  delete from app_finance.transaction_categories where user_id = p_user_id;
  delete from app_finance.accounts where user_id = p_user_id;
  delete from app_work.work_entries where user_id = p_user_id;
  delete from app_work.official_holidays where user_id = p_user_id;
  delete from app_salary.salary_adjustments where user_id = p_user_id;
  delete from app_salary.salary_settings where user_id = p_user_id;
  delete from app_core.user_preferences where user_id = p_user_id;
  delete from app_core.profiles where id = p_user_id;

  perform set_config('app_finance.facility_internal', '', true);
end;
$$;

comment on function app_core.delete_finance_suit_data(uuid) is
  'Deletes Finance Suit product data only; preserves shared Auth and public legacy data.';

revoke all on function app_core.delete_finance_suit_data(uuid) from public;
revoke all on function app_core.delete_finance_suit_data(uuid) from anon;
revoke all on function app_core.delete_finance_suit_data(uuid)
from authenticated;
grant execute on function app_core.delete_finance_suit_data(uuid)
to service_role;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'recurring_rules',
    'recurring_occurrences'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'app_finance'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table app_finance.%I',
        v_table
      );
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
