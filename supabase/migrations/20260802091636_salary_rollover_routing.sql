-- Salary balance rollover routing and persisted automation controls.

alter table app_finance.income_sources
  add column if not exists rollover_balance_enabled boolean
    not null default false,
  add column if not exists rollover_destination_account_id uuid;

alter table app_finance.income_sources
  drop constraint if exists income_source_rollover_account_owner_fk,
  drop constraint if exists income_source_rollover_shape,
  add constraint income_source_rollover_account_owner_fk
    foreign key (rollover_destination_account_id, user_id)
    references app_finance.accounts (id, user_id),
  add constraint income_source_rollover_shape check (
    (
      not rollover_balance_enabled
      and rollover_destination_account_id is null
    )
    or
    (
      rollover_balance_enabled
      and source_kind = 'salary'
      and rollover_destination_account_id is not null
      and rollover_destination_account_id <> primary_account_id
    )
  );

create index if not exists idx_income_sources_rollover_account
  on app_finance.income_sources (rollover_destination_account_id, user_id)
  where rollover_destination_account_id is not null;

alter table app_finance.financial_transactions
  add column if not exists is_balance_rollover boolean not null default false;

alter table app_finance.financial_transactions
  drop constraint if exists tx_income_allocation_owner_fk,
  add constraint tx_income_allocation_owner_fk
    foreign key (income_allocation_id, user_id)
    references app_finance.income_source_allocations (id, user_id)
    on delete set null (income_allocation_id);

create unique index if not exists idx_tx_one_balance_rollover_per_occurrence
  on app_finance.financial_transactions (income_occurrence_id)
  where is_balance_rollover;

create or replace function app_private.rollover_previous_salary_balance()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_source record;
  v_destination record;
  v_rollover_minor bigint;
begin
  if new.transaction_kind <> 'salary_income'
      or new.income_occurrence_id is null then
    return new;
  end if;

  select
    source.id,
    source.name,
    source.primary_account_id,
    source.currency_code,
    source.rollover_balance_enabled,
    source.rollover_destination_account_id
  into v_source
  from app_finance.income_occurrences occurrence
  join app_finance.income_sources source
    on source.id = occurrence.income_source_id
   and source.user_id = occurrence.user_id
  where occurrence.id = new.income_occurrence_id
    and occurrence.user_id = new.user_id;

  if v_source is null or not v_source.rollover_balance_enabled then
    return new;
  end if;

  select account.currency_code, account.is_archived, account.account_type
  into v_destination
  from app_finance.accounts account
  where account.id = v_source.rollover_destination_account_id
    and account.user_id = new.user_id;

  if v_destination is null or v_destination.is_archived then
    raise exception 'invalid_account: rollover account not found or archived';
  end if;
  if v_destination.currency_code <> v_source.currency_code then
    raise exception 'currency_mismatch: rollover account must match salary';
  end if;
  if v_destination.account_type <> 'savings' then
    raise exception 'invalid_account: rollover destination must be savings';
  end if;

  select greatest(coalesce(balance.balance_minor, 0), 0)
  into v_rollover_minor
  from app_finance.account_balances balance
  where balance.account_id = v_source.primary_account_id
    and balance.user_id = new.user_id;

  if coalesce(v_rollover_minor, 0) > 0 then
    insert into app_finance.financial_transactions (
      user_id,
      transaction_kind,
      occurred_on,
      amount_minor,
      currency_code,
      source_account_id,
      destination_account_id,
      title,
      income_occurrence_id,
      is_balance_rollover
    ) values (
      new.user_id,
      'transfer',
      new.occurred_on,
      v_rollover_minor,
      v_source.currency_code,
      v_source.primary_account_id,
      v_source.rollover_destination_account_id,
      v_source.name || ' previous balance rollover',
      new.income_occurrence_id,
      true
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_rollover_previous_salary_balance
  on app_finance.financial_transactions;
create trigger trg_rollover_previous_salary_balance
  before insert on app_finance.financial_transactions
  for each row execute function app_private.rollover_previous_salary_balance();

revoke execute on function app_private.rollover_previous_salary_balance()
  from public, anon, authenticated;

create or replace function app_finance.save_income_source_v4(
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
  p_extra_work_destination_account_id uuid default null,
  p_rollover_balance_enabled boolean default false,
  p_rollover_destination_account_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_source_id uuid;
  v_rollover_account record;
begin
  if p_source_kind = 'salary'
      and coalesce(p_rollover_balance_enabled, false) then
    if p_rollover_destination_account_id is null then
      raise exception 'invalid_account: rollover destination is required';
    end if;
    if p_rollover_destination_account_id = p_primary_account_id then
      raise exception 'invalid_allocation: rollover account must differ from primary';
    end if;

    select account.currency_code, account.is_archived, account.account_type
    into v_rollover_account
    from app_finance.accounts account
    where account.id = p_rollover_destination_account_id
      and account.user_id = (select auth.uid());

    if v_rollover_account is null or v_rollover_account.is_archived then
      raise exception 'invalid_account: rollover account not found or archived';
    end if;
    if v_rollover_account.currency_code <> p_currency_code then
      raise exception 'currency_mismatch: rollover account must match source';
    end if;
    if v_rollover_account.account_type <> 'savings' then
      raise exception 'invalid_account: rollover destination must be savings';
    end if;
  end if;

  v_source_id := app_finance.save_income_source_v3(
    p_name => p_name,
    p_source_kind => p_source_kind,
    p_expected_amount_minor => p_expected_amount_minor,
    p_currency_code => p_currency_code,
    p_payment_day => p_payment_day,
    p_start_date => p_start_date,
    p_prompt_days_before => p_prompt_days_before,
    p_primary_account_id => p_primary_account_id,
    p_category_id => p_category_id,
    p_allocations => p_allocations,
    p_notes => p_notes,
    p_source_id => p_source_id,
    p_is_active => p_is_active,
    p_include_extra_work_in_percentage =>
      p_include_extra_work_in_percentage,
    p_extra_work_destination_account_id =>
      p_extra_work_destination_account_id
  );

  if p_source_kind = 'salary'
      and coalesce(p_rollover_balance_enabled, false) then
    update app_finance.income_sources
    set rollover_balance_enabled = true,
        rollover_destination_account_id = p_rollover_destination_account_id
    where id = v_source_id and user_id = (select auth.uid());
  else
    update app_finance.income_sources
    set rollover_balance_enabled = false,
        rollover_destination_account_id = null
    where id = v_source_id and user_id = (select auth.uid());
  end if;

  return v_source_id;
end;
$$;

revoke execute on function app_finance.save_income_source_v4(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean, boolean, uuid,
  boolean, uuid
) from public, anon;
grant execute on function app_finance.save_income_source_v4(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean, boolean, uuid,
  boolean, uuid
) to authenticated, service_role;

notify pgrst, 'reload schema';
