-- Backward-compatible category hierarchy plus user-approved recurring income.
-- Existing categories remain top-level because parent_category_id is nullable.
-- Scheduled income affects balances only after explicit acceptance.

create type app_finance.income_source_kind as enum (
  'salary', 'allowance', 'freelance', 'other'
);

create type app_finance.income_occurrence_status as enum (
  'pending', 'accepted', 'skipped'
);

-- ---------------------------------------------------------------------------
-- One-level subcategories
-- ---------------------------------------------------------------------------
alter table app_finance.transaction_categories
  add column parent_category_id uuid;

alter table app_finance.transaction_categories
  add constraint transaction_categories_owner_kind_unique
  unique (id, user_id, category_kind);

alter table app_finance.transaction_categories
  add constraint category_parent_not_self
  check (parent_category_id is null or parent_category_id <> id),
  add constraint category_parent_owner_kind_fk
  foreign key (parent_category_id, user_id, category_kind)
  references app_finance.transaction_categories (id, user_id, category_kind);

create index idx_categories_parent
  on app_finance.transaction_categories (user_id, parent_category_id, sort_order, name)
  where parent_category_id is not null;

create or replace function app_private.validate_category_parent()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_id uuid;
begin
  if new.parent_category_id is null then
    return new;
  end if;

  select parent_category_id into v_parent_id
  from app_finance.transaction_categories
  where id = new.parent_category_id
    and user_id = new.user_id
    and category_kind = new.category_kind;

  if not found then
    raise exception 'invalid_parent_category: parent not found for this category type';
  end if;
  if v_parent_id is not null then
    raise exception 'invalid_parent_category: only one subcategory level is allowed';
  end if;
  return new;
end;
$$;

create trigger trg_validate_category_parent
  before insert or update of parent_category_id, user_id, category_kind
  on app_finance.transaction_categories
  for each row execute function app_private.validate_category_parent();

-- Existing salary users remain enabled; new allowance-only users can opt out.
alter table app_salary.salary_settings
  add column salary_enabled boolean not null default true;

-- ---------------------------------------------------------------------------
-- Recurring income configuration
-- ---------------------------------------------------------------------------
create table app_finance.income_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  source_kind app_finance.income_source_kind not null,
  transaction_kind app_finance.transaction_kind not null,
  expected_amount_minor bigint not null check (expected_amount_minor > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  payment_day smallint not null check (payment_day between 1 and 28),
  start_date date not null default current_date,
  prompt_days_before smallint not null default 7
    check (prompt_days_before between 0 and 31),
  primary_account_id uuid not null,
  category_id uuid,
  is_active boolean not null default true,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint income_sources_owner_unique unique (id, user_id),
  constraint income_source_primary_account_owner_fk
    foreign key (primary_account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint income_source_category_owner_fk
    foreign key (category_id, user_id)
    references app_finance.transaction_categories (id, user_id),
  constraint income_source_kind_transaction_match check (
    (source_kind = 'salary' and transaction_kind = 'salary_income')
    or (source_kind = 'freelance' and transaction_kind = 'freelance_income')
    or (source_kind in ('allowance', 'other') and transaction_kind = 'custom_income')
  )
);

create trigger trg_income_sources_updated_at
  before update on app_finance.income_sources
  for each row execute function app_private.set_updated_at();

create unique index idx_income_sources_active_name
  on app_finance.income_sources (user_id, source_kind, lower(name))
  where is_active;

create unique index idx_income_sources_one_active_salary
  on app_finance.income_sources (user_id)
  where source_kind = 'salary' and is_active;

create index idx_income_sources_user_active
  on app_finance.income_sources (user_id, is_active, payment_day, id);

create table app_finance.income_source_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  income_source_id uuid not null,
  destination_account_id uuid not null,
  percentage_basis_points integer not null
    check (percentage_basis_points between 1 and 10000),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint income_source_allocations_owner_unique unique (id, user_id),
  constraint income_allocation_source_owner_fk
    foreign key (income_source_id, user_id)
    references app_finance.income_sources (id, user_id) on delete cascade,
  constraint income_allocation_account_owner_fk
    foreign key (destination_account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint income_allocation_account_unique
    unique (income_source_id, destination_account_id)
);

create trigger trg_income_source_allocations_updated_at
  before update on app_finance.income_source_allocations
  for each row execute function app_private.set_updated_at();

create index idx_income_allocations_source_order
  on app_finance.income_source_allocations (income_source_id, sort_order, id);

create table app_finance.income_occurrences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  income_source_id uuid not null,
  scheduled_on date not null,
  expected_amount_minor bigint not null check (expected_amount_minor > 0),
  status app_finance.income_occurrence_status not null default 'pending',
  actual_amount_minor bigint check (actual_amount_minor > 0),
  received_on date,
  primary_transaction_id uuid,
  salary_period_id uuid,
  decision_at timestamptz,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint income_occurrences_owner_unique unique (id, user_id),
  constraint income_occurrence_source_owner_fk
    foreign key (income_source_id, user_id)
    references app_finance.income_sources (id, user_id) on delete cascade,
  constraint income_occurrence_schedule_unique
    unique (income_source_id, scheduled_on),
  constraint income_occurrence_salary_period_owner_fk
    foreign key (salary_period_id, user_id)
    references app_salary.salary_periods (id, user_id),
  constraint income_occurrence_state_fields check (
    (status = 'pending'
      and actual_amount_minor is null
      and received_on is null
      and primary_transaction_id is null
      and decision_at is null)
    or (status = 'skipped'
      and primary_transaction_id is null
      and decision_at is not null)
    or (status = 'accepted'
      and actual_amount_minor is not null
      and received_on is not null
      and primary_transaction_id is not null
      and decision_at is not null)
  )
);

create trigger trg_income_occurrences_updated_at
  before update on app_finance.income_occurrences
  for each row execute function app_private.set_updated_at();

create index idx_income_occurrences_pending
  on app_finance.income_occurrences (user_id, status, scheduled_on, id);

alter table app_finance.financial_transactions
  add column income_occurrence_id uuid;

alter table app_finance.financial_transactions
  add constraint tx_income_occurrence_owner_fk
  foreign key (income_occurrence_id, user_id)
  references app_finance.income_occurrences (id, user_id);

create index idx_tx_income_occurrence
  on app_finance.financial_transactions (income_occurrence_id, user_id)
  where income_occurrence_id is not null;

create unique index idx_tx_one_primary_income_per_occurrence
  on app_finance.financial_transactions (income_occurrence_id)
  where income_occurrence_id is not null and transaction_kind <> 'transfer';

alter table app_finance.income_occurrences
  add constraint income_occurrence_primary_tx_owner_fk
  foreign key (primary_transaction_id, user_id)
  references app_finance.financial_transactions (id, user_id);

-- ---------------------------------------------------------------------------
-- Validation triggers
-- ---------------------------------------------------------------------------
create or replace function app_private.validate_income_source()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account record;
  v_category record;
begin
  select currency_code, is_archived into v_account
  from app_finance.accounts
  where id = new.primary_account_id
    and user_id = new.user_id;
  if v_account is null then
    raise exception 'invalid_account: primary account not found';
  end if;
  if new.is_active and v_account.is_archived then
    raise exception 'invalid_account: primary account is archived';
  end if;
  if v_account.currency_code <> new.currency_code then
    raise exception 'currency_mismatch: income source and account must match';
  end if;

  if new.category_id is not null then
    select category_kind, is_archived into v_category
    from app_finance.transaction_categories
    where id = new.category_id
      and user_id = new.user_id;
    if v_category is null
      or v_category.category_kind is distinct from
        'income'::app_finance.category_kind then
      raise exception 'invalid_category: an income category is required';
    end if;
    if new.is_active and v_category.is_archived then
      raise exception 'invalid_category: income category is archived';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_validate_income_source
  before insert or update on app_finance.income_sources
  for each row execute function app_private.validate_income_source();

create or replace function app_private.validate_income_allocation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_source record;
  v_account record;
begin
  select primary_account_id, currency_code into v_source
  from app_finance.income_sources
  where id = new.income_source_id and user_id = new.user_id;
  if v_source is null then
    raise exception 'invalid_income_source';
  end if;
  if new.destination_account_id = v_source.primary_account_id then
    raise exception 'invalid_allocation: primary account receives the remainder';
  end if;

  select currency_code, is_archived into v_account
  from app_finance.accounts
  where id = new.destination_account_id and user_id = new.user_id;
  if v_account is null or v_account.is_archived then
    raise exception 'invalid_account: allocation account not found or archived';
  end if;
  if v_account.currency_code <> v_source.currency_code then
    raise exception 'currency_mismatch: allocation account must match source';
  end if;
  return new;
end;
$$;

create trigger trg_validate_income_allocation
  before insert or update on app_finance.income_source_allocations
  for each row execute function app_private.validate_income_allocation();

create or replace function app_private.enforce_income_allocation_total()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_source_id uuid := coalesce(new.income_source_id, old.income_source_id);
  v_total integer;
begin
  select coalesce(sum(percentage_basis_points), 0)::integer into v_total
  from app_finance.income_source_allocations
  where income_source_id = v_source_id;
  if v_total > 10000 then
    raise exception 'invalid_allocation: percentages exceed 100%%';
  end if;
  return null;
end;
$$;

create constraint trigger trg_enforce_income_allocation_total
  after insert or update or delete on app_finance.income_source_allocations
  deferrable initially deferred
  for each row execute function app_private.enforce_income_allocation_total();

create or replace function app_private.disable_salary_automation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.salary_enabled and not new.salary_enabled then
    update app_finance.income_sources
    set is_active = false
    where user_id = new.user_id and source_kind = 'salary' and is_active;
  end if;
  return new;
end;
$$;

create trigger trg_disable_salary_automation
  after update of salary_enabled on app_salary.salary_settings
  for each row execute function app_private.disable_salary_automation();

create or replace function app_private.enable_salary_automation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.source_kind = 'salary' and new.is_active then
    update app_salary.salary_settings
    set salary_enabled = true
    where user_id = new.user_id and not salary_enabled;
  end if;
  return new;
end;
$$;

create trigger trg_enable_salary_automation
  after insert or update of source_kind, is_active
  on app_finance.income_sources
  for each row execute function app_private.enable_salary_automation();

create or replace function app_private.sync_salary_automation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_source_id uuid;
  v_account_id uuid;
begin
  if not new.salary_enabled or new.base_salary_minor <= 0 then
    return new;
  end if;

  select id into v_source_id
  from app_finance.income_sources
  where user_id = new.user_id and source_kind = 'salary' and is_active;

  if v_source_id is not null then
    update app_finance.income_sources set
      expected_amount_minor = new.base_salary_minor,
      currency_code = new.currency_code,
      payment_day = new.payment_day
    where id = v_source_id;
    return new;
  end if;

  select id into v_account_id
  from app_finance.accounts
  where user_id = new.user_id
    and currency_code = new.currency_code
    and not is_archived
  order by is_default desc, created_at, id
  limit 1;

  if v_account_id is not null then
    insert into app_finance.income_sources (
      user_id, name, source_kind, transaction_kind, expected_amount_minor,
      currency_code, payment_day, start_date, prompt_days_before,
      primary_account_id
    ) values (
      new.user_id, 'Salary', 'salary', 'salary_income',
      new.base_salary_minor, new.currency_code, new.payment_day,
      date_trunc('month', current_date)::date, 7, v_account_id
    );
  end if;
  return new;
end;
$$;

create trigger trg_sync_salary_automation
  after insert or update of salary_enabled, base_salary_minor,
    currency_code, payment_day
  on app_salary.salary_settings
  for each row execute function app_private.sync_salary_automation();

-- Backfill a source for existing configured salary users. The no-op update
-- invokes the synchronization trigger after the new source tables exist.
update app_salary.salary_settings
set salary_enabled = salary_enabled
where salary_enabled and base_salary_minor > 0;

-- ---------------------------------------------------------------------------
-- Source CRUD and schedule materialization
-- ---------------------------------------------------------------------------
create or replace function app_finance.save_income_source(
  p_name text,
  p_source_kind app_finance.income_source_kind,
  p_expected_amount_minor bigint,
  p_currency_code text,
  p_payment_day smallint,
  p_start_date date,
  p_prompt_days_before smallint,
  p_primary_account_id uuid,
  p_category_id uuid,
  p_allocations jsonb default '[]'::jsonb,
  p_notes text default null,
  p_source_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source_id uuid;
  v_transaction_kind app_finance.transaction_kind;
  v_total integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'invalid_allocations: expected an array';
  end if;

  select coalesce(sum((item ->> 'percentage_basis_points')::integer), 0)::integer
  into v_total
  from jsonb_array_elements(p_allocations) item;
  if v_total > 10000 then
    raise exception 'invalid_allocation: percentages exceed 100%%';
  end if;

  v_transaction_kind := case p_source_kind
    when 'salary' then 'salary_income'::app_finance.transaction_kind
    when 'freelance' then 'freelance_income'::app_finance.transaction_kind
    else 'custom_income'::app_finance.transaction_kind
  end;

  if p_source_id is null then
    insert into app_finance.income_sources (
      user_id, name, source_kind, transaction_kind, expected_amount_minor,
      currency_code, payment_day, start_date, prompt_days_before,
      primary_account_id, category_id, notes
    ) values (
      v_user_id, p_name, p_source_kind, v_transaction_kind,
      p_expected_amount_minor, p_currency_code, p_payment_day, p_start_date,
      p_prompt_days_before, p_primary_account_id, p_category_id, p_notes
    ) returning id into v_source_id;
  else
    update app_finance.income_sources set
      name = p_name,
      source_kind = p_source_kind,
      transaction_kind = v_transaction_kind,
      expected_amount_minor = p_expected_amount_minor,
      currency_code = p_currency_code,
      payment_day = p_payment_day,
      start_date = p_start_date,
      prompt_days_before = p_prompt_days_before,
      primary_account_id = p_primary_account_id,
      category_id = p_category_id,
      notes = p_notes,
      is_active = true
    where id = p_source_id and user_id = v_user_id
    returning id into v_source_id;
    if v_source_id is null then raise exception 'not_found: income source'; end if;

    delete from app_finance.income_occurrences
    where income_source_id = v_source_id
      and user_id = v_user_id
      and status = 'pending'
      and scheduled_on >= current_date;
  end if;

  delete from app_finance.income_source_allocations
  where income_source_id = v_source_id and user_id = v_user_id;

  insert into app_finance.income_source_allocations (
    user_id, income_source_id, destination_account_id,
    percentage_basis_points, sort_order
  )
  select
    v_user_id,
    v_source_id,
    (item ->> 'destination_account_id')::uuid,
    (item ->> 'percentage_basis_points')::integer,
    ordinality::integer - 1
  from jsonb_array_elements(p_allocations) with ordinality as rows(item, ordinality);

  if p_source_kind = 'salary' then
    update app_salary.salary_settings
    set salary_enabled = true,
      base_salary_minor = p_expected_amount_minor,
      currency_code = p_currency_code,
      payment_day = p_payment_day
    where user_id = v_user_id;
  end if;

  return v_source_id;
end;
$$;

create or replace function app_finance.materialize_income_occurrences(
  p_through_date date
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source record;
  v_month date;
  v_scheduled date;
  v_inserted integer := 0;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_through_date > current_date + 62 then
    raise exception 'invalid_date: schedule lookahead is limited to 62 days';
  end if;

  for v_source in
    select * from app_finance.income_sources
    where user_id = v_user_id and is_active
  loop
    v_month := date_trunc('month', v_source.start_date)::date;
    while v_month <= date_trunc('month', p_through_date)::date loop
      v_scheduled := make_date(
        extract(year from v_month)::integer,
        extract(month from v_month)::integer,
        v_source.payment_day
      );
      if v_scheduled >= v_source.start_date and v_scheduled <= p_through_date then
        insert into app_finance.income_occurrences (
          user_id, income_source_id, scheduled_on, expected_amount_minor
        ) values (
          v_user_id, v_source.id, v_scheduled, v_source.expected_amount_minor
        ) on conflict (income_source_id, scheduled_on) do nothing;
        if found then v_inserted := v_inserted + 1; end if;
      end if;
      v_month := (v_month + interval '1 month')::date;
    end loop;
  end loop;
  return v_inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Explicit accept / skip decisions
-- ---------------------------------------------------------------------------
create or replace function app_finance.accept_income_occurrence(
  p_occurrence_id uuid,
  p_actual_amount_minor bigint,
  p_received_on date,
  p_notes text default null,
  p_salary_period_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_occurrence record;
  v_source record;
  v_period record;
  v_tx_id uuid;
  v_allocation record;
  v_transfer_amount bigint;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_actual_amount_minor <= 0 then raise exception 'invalid_amount'; end if;

  select * into v_occurrence
  from app_finance.income_occurrences
  where id = p_occurrence_id and user_id = v_user_id
  for update;
  if v_occurrence is null then raise exception 'not_found: income occurrence'; end if;
  if v_occurrence.status = 'accepted' then return v_occurrence.primary_transaction_id; end if;
  if v_occurrence.status <> 'pending' then raise exception 'already_decided'; end if;

  select * into v_source
  from app_finance.income_sources
  where id = v_occurrence.income_source_id
    and user_id = v_user_id
    and is_active;
  if v_source is null then raise exception 'invalid_income_source'; end if;

  if v_source.source_kind = 'salary' then
    if p_salary_period_id is null then
      raise exception 'salary_period_required';
    end if;
    select * into v_period
    from app_salary.salary_periods
    where id = p_salary_period_id and user_id = v_user_id
    for update;
    if v_period is null then raise exception 'not_found: salary period'; end if;
    if v_period.status = 'paid' then raise exception 'already_paid'; end if;
    if v_period.status <> 'finalized' then raise exception 'not_finalized'; end if;
  elsif p_salary_period_id is not null then
    raise exception 'invalid_salary_period';
  end if;

  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    destination_account_id, category_id, title, notes, salary_period_id,
    income_occurrence_id
  ) values (
    v_user_id, v_source.transaction_kind, p_received_on,
    p_actual_amount_minor, v_source.currency_code,
    v_source.primary_account_id, v_source.category_id, v_source.name, p_notes,
    p_salary_period_id, v_occurrence.id
  ) returning id into v_tx_id;

  for v_allocation in
    select * from app_finance.income_source_allocations
    where income_source_id = v_source.id and user_id = v_user_id
    order by sort_order, id
  loop
    v_transfer_amount := (p_actual_amount_minor *
      v_allocation.percentage_basis_points) / 10000;
    if v_transfer_amount > 0 then
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, destination_account_id, title, income_occurrence_id
      ) values (
        v_user_id, 'transfer', p_received_on, v_transfer_amount,
        v_source.currency_code, v_source.primary_account_id,
        v_allocation.destination_account_id,
        v_source.name || ' automatic allocation', v_occurrence.id
      );
    end if;
  end loop;

  if p_salary_period_id is not null then
    update app_salary.salary_periods set
      status = 'paid',
      actual_amount_minor = p_actual_amount_minor,
      received_date = p_received_on,
      destination_account_id = v_source.primary_account_id,
      paid_transaction_id = v_tx_id
    where id = p_salary_period_id;
  end if;

  update app_finance.income_occurrences set
    status = 'accepted',
    actual_amount_minor = p_actual_amount_minor,
    received_on = p_received_on,
    primary_transaction_id = v_tx_id,
    salary_period_id = p_salary_period_id,
    decision_at = now(),
    notes = p_notes
  where id = p_occurrence_id;

  return v_tx_id;
end;
$$;

create or replace function app_finance.skip_income_occurrence(
  p_occurrence_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update app_finance.income_occurrences set
    status = 'skipped', decision_at = now()
  where id = p_occurrence_id
    and user_id = (select auth.uid())
    and status = 'pending';
  if not found then raise exception 'not_found_or_already_decided'; end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- New onboarding contract; the old RPC remains callable by installed clients.
-- ---------------------------------------------------------------------------
create or replace function app_core.complete_onboarding_v2(
  p_display_name text,
  p_currency_code text,
  p_timezone text,
  p_locale text,
  p_week_starts_on smallint,
  p_weekend_days smallint[],
  p_salary_enabled boolean,
  p_base_salary_minor bigint,
  p_salary_period_start_day smallint,
  p_payment_day smallint,
  p_payment_month_offset smallint,
  p_standard_paid_days smallint,
  p_standard_minutes_per_day integer,
  p_day_rate_mode app_salary.rate_mode,
  p_manual_day_rate_minor bigint,
  p_hour_rate_mode app_salary.rate_mode,
  p_manual_hour_rate_minor bigint,
  p_extra_day_multiplier_pct integer,
  p_official_holiday_multiplier_pct integer,
  p_overtime_multiplier_pct integer,
  p_holiday_semantics app_salary.holiday_multiplier_semantics,
  p_account_name text,
  p_account_type app_finance.account_type,
  p_opening_balance_minor bigint,
  p_allow_negative_balance boolean,
  p_income_source_kind app_finance.income_source_kind default null,
  p_income_source_name text default null,
  p_expected_income_minor bigint default null,
  p_income_payment_day smallint default null,
  p_prompt_days_before smallint default 7
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_source_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select app_core.complete_onboarding(
    p_display_name, p_currency_code, p_timezone, p_locale,
    p_week_starts_on, p_weekend_days, p_base_salary_minor,
    p_salary_period_start_day, p_payment_day, p_payment_month_offset,
    p_standard_paid_days, p_standard_minutes_per_day, p_day_rate_mode,
    p_manual_day_rate_minor, p_hour_rate_mode, p_manual_hour_rate_minor,
    p_extra_day_multiplier_pct, p_official_holiday_multiplier_pct,
    p_overtime_multiplier_pct, p_holiday_semantics, p_account_name,
    p_account_type, p_opening_balance_minor, p_allow_negative_balance
  ) into v_account_id;

  update app_salary.salary_settings
  set salary_enabled = p_salary_enabled
  where user_id = v_user_id;

  if p_income_source_kind is not null then
    if p_income_source_name is null or p_expected_income_minor is null
      or p_income_payment_day is null then
      raise exception 'income_source_fields_required';
    end if;
    if p_income_source_kind = 'salary' then
      select id into v_source_id
      from app_finance.income_sources
      where user_id = v_user_id and source_kind = 'salary' and is_active;
    end if;
    perform app_finance.save_income_source(
      p_income_source_name,
      p_income_source_kind,
      p_expected_income_minor,
      p_currency_code,
      p_income_payment_day,
      current_date,
      p_prompt_days_before,
      v_account_id,
      null,
      '[]'::jsonb,
      null,
      v_source_id
    );
  end if;

  return v_account_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS, API grants, realtime, and product-data deletion
-- ---------------------------------------------------------------------------
alter table app_finance.income_sources enable row level security;
alter table app_finance.income_source_allocations enable row level security;
alter table app_finance.income_occurrences enable row level security;

create policy income_sources_select on app_finance.income_sources
  for select to authenticated using ((select auth.uid()) = user_id);
create policy income_sources_insert on app_finance.income_sources
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy income_sources_update on app_finance.income_sources
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy income_sources_delete on app_finance.income_sources
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy income_allocations_select on app_finance.income_source_allocations
  for select to authenticated using ((select auth.uid()) = user_id);
create policy income_allocations_insert on app_finance.income_source_allocations
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy income_allocations_update on app_finance.income_source_allocations
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy income_allocations_delete on app_finance.income_source_allocations
  for delete to authenticated using ((select auth.uid()) = user_id);

create policy income_occurrences_select on app_finance.income_occurrences
  for select to authenticated using ((select auth.uid()) = user_id);
create policy income_occurrences_insert on app_finance.income_occurrences
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy income_occurrences_update on app_finance.income_occurrences
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy income_occurrences_delete on app_finance.income_occurrences
  for delete to authenticated using ((select auth.uid()) = user_id);

grant select, insert, update, delete on
  app_finance.income_sources,
  app_finance.income_source_allocations,
  app_finance.income_occurrences
to authenticated, service_role;

grant usage on type
  app_finance.income_source_kind,
  app_finance.income_occurrence_status
to authenticated, service_role;

revoke execute on function app_finance.save_income_source(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid
) from public, anon;
revoke execute on function app_finance.materialize_income_occurrences(date)
  from public, anon;
revoke execute on function app_finance.accept_income_occurrence(
  uuid, bigint, date, text, uuid
) from public, anon;
revoke execute on function app_finance.skip_income_occurrence(uuid)
  from public, anon;
revoke execute on function app_core.complete_onboarding_v2(
  text, text, text, text, smallint, smallint[], boolean, bigint, smallint,
  smallint, smallint, smallint, integer, app_salary.rate_mode, bigint,
  app_salary.rate_mode, bigint, integer, integer, integer,
  app_salary.holiday_multiplier_semantics, text, app_finance.account_type,
  bigint, boolean, app_finance.income_source_kind, text, bigint, smallint,
  smallint
) from public, anon;

grant execute on function app_finance.save_income_source(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid
) to authenticated, service_role;
grant execute on function app_finance.materialize_income_occurrences(date)
  to authenticated, service_role;
grant execute on function app_finance.accept_income_occurrence(
  uuid, bigint, date, text, uuid
) to authenticated, service_role;
grant execute on function app_finance.skip_income_occurrence(uuid)
  to authenticated, service_role;
grant execute on function app_core.complete_onboarding_v2(
  text, text, text, text, smallint, smallint[], boolean, bigint, smallint,
  smallint, smallint, smallint, integer, app_salary.rate_mode, bigint,
  app_salary.rate_mode, bigint, integer, integer, integer,
  app_salary.holiday_multiplier_semantics, text, app_finance.account_type,
  bigint, boolean, app_finance.income_source_kind, text, bigint, smallint,
  smallint
) to authenticated, service_role;

alter publication supabase_realtime add table app_finance.income_sources;
alter publication supabase_realtime add table app_finance.income_occurrences;

create or replace function app_core.delete_finance_suit_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user_id is null then raise exception 'user_id_required'; end if;

  update app_salary.salary_periods set paid_transaction_id = null
    where user_id = p_user_id;
  update app_finance.income_occurrences set primary_transaction_id = null
    where user_id = p_user_id;
  update app_finance.financial_transactions set
    salary_period_id = null,
    income_occurrence_id = null
    where user_id = p_user_id;

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
end;
$$;

revoke all on function app_core.delete_finance_suit_data(uuid)
  from public, anon, authenticated;
grant execute on function app_core.delete_finance_suit_data(uuid)
  to service_role;

notify pgrst, 'reload schema';
