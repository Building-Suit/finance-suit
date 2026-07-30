-- Preserve category-tree integrity and allow income automations to be saved
-- without unexpectedly re-enabling a paused source.

create or replace function app_private.validate_category_archive_state()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent_archived boolean;
begin
  if new.parent_category_id is null then
    if new.is_archived and not old.is_archived and exists (
      select 1
      from app_finance.transaction_categories child
      where child.user_id = new.user_id
        and child.parent_category_id = new.id
        and not child.is_archived
    ) then
      raise exception 'active_subcategories_exist: archive subcategories first';
    end if;
    return new;
  end if;

  if not new.is_archived then
    select parent.is_archived into v_parent_archived
    from app_finance.transaction_categories parent
    where parent.id = new.parent_category_id
      and parent.user_id = new.user_id;

    if coalesce(v_parent_archived, true) then
      raise exception 'parent_category_archived: restore the parent first';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_validate_category_archive_state
  before insert or update of parent_category_id, is_archived
  on app_finance.transaction_categories
  for each row execute function app_private.validate_category_archive_state();

-- Salary settings mean "the user has a salary"; pausing its automation must
-- not make the synchronization trigger create a second active source.
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
  where user_id = new.user_id and source_kind = 'salary'
  order by is_active desc, created_at, id
  limit 1;

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
      primary_account_id, category_id, is_active, notes
    ) values (
      v_user_id, p_name, p_source_kind, v_transaction_kind,
      p_expected_amount_minor, p_currency_code, p_payment_day, p_start_date,
      p_prompt_days_before, p_primary_account_id, p_category_id,
      p_is_active, p_notes
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
      is_active = p_is_active
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

revoke execute on function app_finance.save_income_source_v2(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean
) from public, anon;
grant execute on function app_finance.save_income_source_v2(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean
) to authenticated, service_role;

notify pgrst, 'reload schema';
