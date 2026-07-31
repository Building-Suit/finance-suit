-- Advanced ordered income split rules and editable income source types.

-- Keep direct inserts used by older clients/tests compatible. Settlement RPCs
-- still require an account when creating a settlement transaction.
alter table app_finance.held_amounts
  drop constraint if exists held_settlement_account_required;

do $$
begin
  if not exists (
    select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'income_allocation_method'
  ) then
    create type app_finance.income_allocation_method as enum ('percentage', 'fixed');
  end if;
  if not exists (
    select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'income_allocation_calculation_basis'
  ) then
    create type app_finance.income_allocation_calculation_basis as enum ('original', 'remaining');
  end if;
end $$;

alter table app_finance.income_source_allocations
  add column if not exists allocation_method app_finance.income_allocation_method
    not null default 'percentage',
  add column if not exists calculation_basis app_finance.income_allocation_calculation_basis
    not null default 'original',
  add column if not exists fixed_amount_minor bigint;

alter table app_finance.income_source_allocations
  alter column percentage_basis_points drop not null;

alter table app_finance.income_source_allocations
  drop constraint if exists income_source_allocations_percentage_basis_points_check,
  drop constraint if exists income_allocation_account_unique,
  drop constraint if exists income_allocation_shape;

alter table app_finance.income_source_allocations
  add constraint income_allocation_shape check (
    (
      allocation_method = 'percentage'
      and percentage_basis_points between 1 and 10000
      and fixed_amount_minor is null
    )
    or
    (
      allocation_method = 'fixed'
      and fixed_amount_minor > 0
      and percentage_basis_points is null
      and calculation_basis = 'original'
    )
  );

drop trigger if exists trg_enforce_income_allocation_total
  on app_finance.income_source_allocations;
drop function if exists app_private.enforce_income_allocation_total();

alter table app_finance.income_sources
  add column if not exists include_extra_work_in_percentage boolean
    not null default true,
  add column if not exists extra_work_destination_account_id uuid;

alter table app_finance.income_sources
  drop constraint if exists income_source_extra_work_account_owner_fk,
  add constraint income_source_extra_work_account_owner_fk
    foreign key (extra_work_destination_account_id, user_id)
    references app_finance.accounts (id, user_id);

create index if not exists idx_income_sources_extra_work_account
  on app_finance.income_sources (extra_work_destination_account_id, user_id)
  where extra_work_destination_account_id is not null;

alter table app_finance.financial_transactions
  add column if not exists income_allocation_id uuid,
  add column if not exists is_extra_work_routing boolean not null default false;

alter table app_finance.financial_transactions
  drop constraint if exists tx_income_allocation_owner_fk,
  add constraint tx_income_allocation_owner_fk
    foreign key (income_allocation_id, user_id)
    references app_finance.income_source_allocations (id, user_id);

create index if not exists idx_tx_income_allocation_owner_fk
  on app_finance.financial_transactions (income_allocation_id, user_id)
  where income_allocation_id is not null;

drop trigger if exists trg_prevent_income_source_kind_change
  on app_finance.income_sources;
drop function if exists app_private.prevent_income_source_kind_change();

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

create or replace function app_finance.set_held_amount_settled(
  p_held_id uuid,
  p_settled_on date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_held app_finance.held_amounts%rowtype;
  v_account app_finance.accounts%rowtype;
  v_transaction_id uuid;
  v_kind app_finance.transaction_kind;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_held
  from app_finance.held_amounts
  where id = p_held_id and user_id = v_user_id
  for update;
  if v_held is null then raise exception 'not_found: held amount'; end if;

  v_transaction_id := v_held.settlement_transaction_id;

  if p_settled_on is null then
    if v_transaction_id is not null then
      delete from app_finance.financial_transactions
      where id = v_transaction_id and user_id = v_user_id;
    end if;
    update app_finance.held_amounts
    set settled_on = null,
        settlement_transaction_id = null,
        transaction_id = linked_transaction_id,
        manages_transaction = linked_transaction_id is null
    where id = p_held_id and user_id = v_user_id;
    return;
  end if;

  if v_held.account_id is null then
    select * into v_account
    from app_finance.accounts
    where user_id = v_user_id
      and currency_code = v_held.currency_code
      and not is_archived
    order by is_default desc, created_at, id
    limit 1;
  else
    select * into v_account
    from app_finance.accounts
    where id = v_held.account_id and user_id = v_user_id and not is_archived;
  end if;
  if v_account is null then raise exception 'invalid_account: account not found or archived'; end if;
  if v_account.currency_code <> v_held.currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  v_kind := case v_held.direction
    when 'i_owe' then 'expense'::app_finance.transaction_kind
    when 'owed_to_me' then 'custom_income'::app_finance.transaction_kind
  end;

  if v_transaction_id is null then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, counterparty, title, notes
    ) values (
      v_user_id, v_kind, p_settled_on, v_held.amount_minor, v_held.currency_code,
      case when v_held.direction = 'i_owe' then v_account.id end,
      case when v_held.direction = 'owed_to_me' then v_account.id end,
      v_held.counterparty, v_held.title, v_held.notes
    ) returning id into v_transaction_id;
  else
    update app_finance.financial_transactions
    set transaction_kind = v_kind,
        occurred_on = p_settled_on,
        amount_minor = v_held.amount_minor,
        currency_code = v_held.currency_code,
        source_account_id = case when v_held.direction = 'i_owe' then v_account.id end,
        destination_account_id = case when v_held.direction = 'owed_to_me' then v_account.id end,
        counterparty = v_held.counterparty,
        title = v_held.title,
        notes = v_held.notes
    where id = v_transaction_id and user_id = v_user_id;
    if not found then raise exception 'not_found: settlement transaction'; end if;
  end if;

  update app_finance.held_amounts
  set settled_on = p_settled_on,
      settlement_transaction_id = v_transaction_id,
      transaction_id = v_transaction_id,
      account_id = v_account.id,
      manages_transaction = true
  where id = p_held_id and user_id = v_user_id;
end;
$$;

create or replace function app_finance.save_income_source_v3(
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
  p_source_id uuid default null,
  p_is_active boolean default true,
  p_include_extra_work_in_percentage boolean default true,
  p_extra_work_destination_account_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source_id uuid;
  v_old_kind app_finance.income_source_kind;
  v_transaction_kind app_finance.transaction_kind;
  v_account record;
  v_extra_account record;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'invalid_allocations: expected an array';
  end if;
  if p_expected_amount_minor <= 0 then raise exception 'invalid_amount'; end if;

  select currency_code, is_archived into v_account
  from app_finance.accounts
  where id = p_primary_account_id and user_id = v_user_id;
  if v_account is null or v_account.is_archived then
    raise exception 'invalid_account: primary account not found or archived';
  end if;
  if v_account.currency_code <> p_currency_code then
    raise exception 'currency_mismatch: primary account must match source';
  end if;

  if p_extra_work_destination_account_id is not null then
    select currency_code, is_archived into v_extra_account
    from app_finance.accounts
    where id = p_extra_work_destination_account_id and user_id = v_user_id;
    if v_extra_account is null or v_extra_account.is_archived then
      raise exception 'invalid_account: extra work account not found or archived';
    end if;
    if v_extra_account.currency_code <> p_currency_code then
      raise exception 'currency_mismatch: extra work account must match source';
    end if;
    if p_extra_work_destination_account_id = p_primary_account_id then
      raise exception 'invalid_allocation: primary account receives the remainder';
    end if;
  end if;

  v_transaction_kind := case p_source_kind
    when 'salary' then 'salary_income'::app_finance.transaction_kind
    when 'freelance' then 'freelance_income'::app_finance.transaction_kind
    else 'custom_income'::app_finance.transaction_kind
  end;

  if p_source_kind = 'salary' and p_is_active and exists (
    select 1 from app_finance.income_sources
    where user_id = v_user_id
      and source_kind = 'salary'
      and is_active
      and id is distinct from p_source_id
  ) then
    raise exception 'salary_source_conflict';
  end if;

  if p_source_id is null then
    insert into app_finance.income_sources (
      user_id, name, source_kind, transaction_kind, expected_amount_minor,
      currency_code, payment_day, start_date, prompt_days_before,
      primary_account_id, category_id, is_active, notes,
      include_extra_work_in_percentage, extra_work_destination_account_id
    ) values (
      v_user_id, p_name, p_source_kind, v_transaction_kind,
      p_expected_amount_minor, p_currency_code, p_payment_day, p_start_date,
      p_prompt_days_before, p_primary_account_id,
      case when p_source_kind = 'salary' then null else p_category_id end,
      p_is_active, p_notes, coalesce(p_include_extra_work_in_percentage, true),
      case
        when p_source_kind = 'salary' and not coalesce(p_include_extra_work_in_percentage, true)
          then p_extra_work_destination_account_id
        else null
      end
    ) returning id into v_source_id;
  else
    select source_kind into v_old_kind
    from app_finance.income_sources
    where id = p_source_id and user_id = v_user_id
    for update;
    if v_old_kind is null then raise exception 'not_found: income source'; end if;

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
      category_id = case when p_source_kind = 'salary' then null else p_category_id end,
      notes = p_notes,
      is_active = p_is_active,
      include_extra_work_in_percentage = coalesce(p_include_extra_work_in_percentage, true),
      extra_work_destination_account_id = case
        when p_source_kind = 'salary' and not coalesce(p_include_extra_work_in_percentage, true)
          then p_extra_work_destination_account_id
        else null
      end
    where id = p_source_id and user_id = v_user_id
    returning id into v_source_id;

    if v_old_kind is distinct from p_source_kind then
      delete from app_finance.income_occurrences
      where income_source_id = v_source_id
        and user_id = v_user_id
        and status = 'pending';
    else
      delete from app_finance.income_occurrences
      where income_source_id = v_source_id
        and user_id = v_user_id
        and status = 'pending'
        and scheduled_on >= current_date;
    end if;
  end if;

  delete from app_finance.income_source_allocations
  where income_source_id = v_source_id and user_id = v_user_id;

  insert into app_finance.income_source_allocations (
    user_id, income_source_id, destination_account_id, allocation_method,
    calculation_basis, percentage_basis_points, fixed_amount_minor, sort_order
  )
  with parsed as (
    select
      item,
      ordinality::integer as ordinality,
      coalesce(item ->> 'allocation_method', 'percentage') as method_text
    from jsonb_array_elements(p_allocations) with ordinality as rows(item, ordinality)
  ),
  numbered as (
    select
      item,
      ordinality,
      method_text,
      count(*) filter (where method_text = 'percentage')
        over (order by ordinality) as percentage_ordinal
    from parsed
  )
  select
    v_user_id,
    v_source_id,
    (item ->> 'destination_account_id')::uuid,
    method_text::app_finance.income_allocation_method,
    case
      when method_text = 'fixed'
          or (method_text = 'percentage' and percentage_ordinal = 1)
        then 'original'::app_finance.income_allocation_calculation_basis
      else coalesce(item ->> 'calculation_basis', 'original')::app_finance.income_allocation_calculation_basis
    end,
    case
      when method_text = 'percentage'
        then (item ->> 'percentage_basis_points')::integer
      else null
    end,
    case
      when method_text = 'fixed'
        then (item ->> 'fixed_amount_minor')::bigint
      else null
    end,
    ordinality::integer - 1
  from numbered;

  if p_source_kind = 'salary' then
    update app_salary.salary_settings
    set salary_enabled = p_is_active,
      base_salary_minor = p_expected_amount_minor,
      currency_code = p_currency_code,
      payment_day = p_payment_day
    where user_id = v_user_id;
  elsif v_old_kind = 'salary' and not exists (
    select 1 from app_finance.income_sources
    where user_id = v_user_id and source_kind = 'salary' and is_active
  ) then
    update app_salary.salary_settings
    set salary_enabled = false
    where user_id = v_user_id;
  end if;

  return v_source_id;
end;
$$;

create or replace function app_finance.save_income_source_v2(
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
  p_source_id uuid default null,
  p_is_active boolean default true
)
returns uuid
language sql
set search_path = ''
as $$
  select app_finance.save_income_source_v3(
    p_name, p_source_kind, p_expected_amount_minor, p_currency_code,
    p_payment_day, p_start_date, p_prompt_days_before, p_primary_account_id,
    p_category_id, p_allocations, p_notes, p_source_id, p_is_active,
    true, null
  );
$$;

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
  v_extra_work_minor bigint := 0;
  v_protected_extra_minor bigint := 0;
  v_original_basis bigint;
  v_remaining_basis bigint;
  v_percentage_index integer := 0;
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

    v_extra_work_minor :=
      coalesce((v_period.snapshot ->> 'extra_day_amount_minor')::bigint, 0) +
      coalesce((v_period.snapshot ->> 'overtime_amount_minor')::bigint, 0) +
      coalesce((v_period.snapshot ->> 'holiday_amount_minor')::bigint, 0);
    if not v_source.include_extra_work_in_percentage then
      v_protected_extra_minor := least(greatest(v_extra_work_minor, 0), p_actual_amount_minor);
    end if;
  elsif p_salary_period_id is not null then
    raise exception 'invalid_salary_period';
  end if;

  v_original_basis := p_actual_amount_minor - v_protected_extra_minor;
  v_remaining_basis := v_original_basis;

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
    if v_allocation.allocation_method = 'percentage' then
      v_percentage_index := v_percentage_index + 1;
      if v_percentage_index = 1 or v_allocation.calculation_basis = 'original' then
        v_transfer_amount :=
          (v_original_basis * v_allocation.percentage_basis_points) / 10000;
      else
        v_transfer_amount :=
          (v_remaining_basis * v_allocation.percentage_basis_points) / 10000;
      end if;
    else
      v_transfer_amount := v_allocation.fixed_amount_minor;
    end if;

    if v_transfer_amount > v_remaining_basis then
      raise exception 'allocation_exceeds_available_income';
    end if;
    v_remaining_basis := v_remaining_basis - v_transfer_amount;

    if v_transfer_amount > 0 then
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, destination_account_id, title,
        income_occurrence_id, income_allocation_id
      ) values (
        v_user_id, 'transfer', p_received_on, v_transfer_amount,
        v_source.currency_code, v_source.primary_account_id,
        v_allocation.destination_account_id,
        v_source.name || ' automatic allocation', v_occurrence.id,
        v_allocation.id
      );
    end if;
  end loop;

  if v_protected_extra_minor > 0
      and v_source.extra_work_destination_account_id is not null then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, title, income_occurrence_id,
      is_extra_work_routing
    ) values (
      v_user_id, 'transfer', p_received_on, v_protected_extra_minor,
      v_source.currency_code, v_source.primary_account_id,
      v_source.extra_work_destination_account_id,
      v_source.name || ' extra work allocation', v_occurrence.id, true
    );
  end if;

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

revoke execute on function app_finance.save_income_source_v3(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean, boolean, uuid
) from public, anon;
grant execute on function app_finance.save_income_source_v3(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean, boolean, uuid
) to authenticated, service_role;

notify pgrst, 'reload schema';
