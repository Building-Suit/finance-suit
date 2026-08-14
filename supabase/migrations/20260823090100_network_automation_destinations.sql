-- Network contacts as automation destinations: recurring transfer rules,
-- income allocation splits, and protected extra-work routing may now target a
-- network connection instead of an own account.
--
-- The accounting boundary is unchanged: an automation that targets a network
-- contact never posts a ledger row by itself. Approving the occurrence
-- creates a pending network transfer (zero balance impact on both sides) and
-- money moves only when the receiver accepts it. Deterministic idempotency
-- keys make automation retries reuse the same transfer instead of creating
-- duplicates. Existing local rules and allocations keep their exact shape and
-- behavior. Balance rollover keeps its own-savings semantics and does not
-- route to network contacts.

-- ---------------------------------------------------------------------------
-- Recurring transfer rules
-- ---------------------------------------------------------------------------

alter table app_finance.recurring_rules
  add column if not exists destination_network_connection_id uuid;

alter table app_finance.recurring_rules
  drop constraint if exists recurring_rules_network_connection_fk,
  add constraint recurring_rules_network_connection_fk
    foreign key (destination_network_connection_id)
    references app_finance.network_connections (id)
    on delete set null;

create index if not exists idx_recurring_rules_network_connection
  on app_finance.recurring_rules (destination_network_connection_id)
  where destination_network_connection_id is not null;

-- A transfer rule targets at most one destination. Write paths require
-- exactly one; the weaker CHECK tolerates the both-null state a connection
-- deletion cascade leaves behind, which the acceptance path surfaces as
-- "network destination is no longer available" instead of rerouting.
alter table app_finance.recurring_rules
  drop constraint if exists recurring_rules_kind_shape,
  add constraint recurring_rules_kind_shape check (
    (rule_kind = 'expense'
      and category_id is not null
      and destination_account_id is null
      and destination_network_connection_id is null)
    or (rule_kind = 'transfer'
      and category_id is null
      and num_nonnulls(destination_account_id,
        destination_network_connection_id) <= 1
      and (destination_account_id is null
        or destination_account_id <> source_account_id))
  );

-- ---------------------------------------------------------------------------
-- Income allocations and extra-work routing
-- ---------------------------------------------------------------------------

alter table app_finance.income_source_allocations
  add column if not exists destination_network_connection_id uuid;

alter table app_finance.income_source_allocations
  alter column destination_account_id drop not null;

alter table app_finance.income_source_allocations
  drop constraint if exists income_allocation_network_connection_fk,
  add constraint income_allocation_network_connection_fk
    foreign key (destination_network_connection_id)
    references app_finance.network_connections (id)
    on delete set null;

alter table app_finance.income_source_allocations
  drop constraint if exists income_allocation_destination_shape,
  add constraint income_allocation_destination_shape check (
    num_nonnulls(destination_account_id,
      destination_network_connection_id) <= 1
  );

create index if not exists idx_income_allocations_network_connection
  on app_finance.income_source_allocations (destination_network_connection_id)
  where destination_network_connection_id is not null;

alter table app_finance.income_sources
  add column if not exists extra_work_destination_network_connection_id uuid;

alter table app_finance.income_sources
  drop constraint if exists income_source_extra_work_network_fk,
  add constraint income_source_extra_work_network_fk
    foreign key (extra_work_destination_network_connection_id)
    references app_finance.network_connections (id)
    on delete set null,
  drop constraint if exists income_source_extra_work_destination_shape,
  add constraint income_source_extra_work_destination_shape check (
    num_nonnulls(extra_work_destination_account_id,
      extra_work_destination_network_connection_id) <= 1
  );

create index if not exists idx_income_sources_extra_work_network
  on app_finance.income_sources (extra_work_destination_network_connection_id)
  where extra_work_destination_network_connection_id is not null;

-- Allocations must name exactly one destination when written; the both-null
-- state is reachable only through the connection-deletion cascade (a
-- referential UPDATE also runs this trigger, so it must pass).
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

  if new.destination_account_id is not null
      and new.destination_network_connection_id is not null then
    raise exception 'invalid_allocation: choose one destination';
  end if;

  if new.destination_network_connection_id is not null then
    if not exists (
      select 1 from app_finance.network_connections c
      where c.id = new.destination_network_connection_id
        and new.user_id in (c.user_a_id, c.user_b_id)
        and c.removed_at is null
    ) then
      raise exception 'not_found: network connection';
    end if;
    return new;
  end if;

  if new.destination_account_id is null then
    if tg_op = 'UPDATE' then
      return new;
    end if;
    raise exception 'invalid_allocation: destination required';
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

-- ---------------------------------------------------------------------------
-- Save recurring rule (v2 adds the network destination)
-- ---------------------------------------------------------------------------

-- The existing save_recurring_rule overloads stay untouched for released
-- clients; new clients call the v2 entry point.
create or replace function app_finance.save_recurring_rule_v2(
  p_name text,
  p_rule_kind app_finance.recurring_rule_kind,
  p_amount_minor bigint,
  p_frequency app_finance.recurring_frequency,
  p_payment_day smallint,
  p_start_date date,
  p_prompt_days_before smallint,
  p_source_account_id uuid,
  p_destination_account_id uuid default null,
  p_destination_network_connection_id uuid default null,
  p_category_id uuid default null,
  p_notes text default null,
  p_rule_id uuid default null,
  p_is_active boolean default true,
  p_is_foreign_currency boolean default false
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
  if v_user_id is null then raise exception 'not_authenticated'; end if;
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
    if p_destination_network_connection_id is not null then
      raise exception
        'invalid_destination: network contacts receive transfers only';
    end if;
    if app_finance.account_role(v_source.account_type) = 'liability'
      and v_source.account_type <> 'credit_card' then
      raise exception 'invalid_account: recurring expenses need cash or a credit card';
    end if;
    if not exists (
      select 1 from app_finance.transaction_categories c
      where c.id = p_category_id and c.user_id = v_user_id
        and not c.is_archived and c.category_kind = 'expense'
    ) then raise exception 'invalid_category: expense category required'; end if;
  else
    if app_finance.account_role(v_source.account_type) <> 'asset' then
      raise exception 'invalid_account: recurring transfers move your own cash';
    end if;
    if p_destination_account_id is not null
        and p_destination_network_connection_id is not null then
      raise exception 'invalid_destination: choose one destination';
    end if;
    if p_destination_network_connection_id is not null then
      if not exists (
        select 1 from app_finance.network_connections c
        where c.id = p_destination_network_connection_id
          and v_user_id in (c.user_a_id, c.user_b_id)
          and c.removed_at is null
      ) then
        raise exception 'not_found: network connection';
      end if;
    elsif not exists (
      select 1 from app_finance.accounts d
      where d.id = p_destination_account_id and d.user_id = v_user_id
        and not d.is_archived and app_finance.account_role(d.account_type) = 'asset'
        and d.currency_code = v_source.currency_code
    ) then raise exception 'invalid_account: destination not found, archived, or mismatched'; end if;
  end if;
  if p_rule_id is not null then
    update app_finance.recurring_rules set
      name = p_name, rule_kind = p_rule_kind, amount_minor = p_amount_minor,
      currency_code = v_source.currency_code, frequency = p_frequency,
      payment_day = p_payment_day, start_date = p_start_date,
      prompt_days_before = coalesce(p_prompt_days_before, 3),
      source_account_id = p_source_account_id,
      destination_account_id = p_destination_account_id,
      destination_network_connection_id = p_destination_network_connection_id,
      category_id = p_category_id,
      is_active = coalesce(p_is_active, true), is_foreign_currency =
        (case when v_source.account_type = 'credit_card' and p_rule_kind = 'expense'
          then coalesce(p_is_foreign_currency, false) else false end), notes = p_notes
      where id = p_rule_id and user_id = v_user_id returning id into v_rule_id;
    if v_rule_id is not null then
      delete from app_finance.recurring_occurrences
        where rule_id = v_rule_id and user_id = v_user_id and status = 'pending';
    end if;
  end if;
  if v_rule_id is null then
    insert into app_finance.recurring_rules (
      id, user_id, name, rule_kind, amount_minor, currency_code, frequency,
      payment_day, start_date, prompt_days_before, source_account_id,
      destination_account_id, destination_network_connection_id, category_id,
      is_active, is_foreign_currency, notes
    ) values (
      coalesce(p_rule_id, gen_random_uuid()), v_user_id, p_name, p_rule_kind,
      p_amount_minor, v_source.currency_code, p_frequency, p_payment_day,
      p_start_date, coalesce(p_prompt_days_before, 3), p_source_account_id,
      p_destination_account_id, p_destination_network_connection_id,
      p_category_id, coalesce(p_is_active, true),
      (case when v_source.account_type = 'credit_card' and p_rule_kind = 'expense'
        then coalesce(p_is_foreign_currency, false) else false end), p_notes
    ) returning id into v_rule_id;
  end if;
  return v_rule_id;
end;
$$;

revoke execute on function app_finance.save_recurring_rule_v2(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, uuid, text, uuid, boolean, boolean
) from public, anon;
grant execute on function app_finance.save_recurring_rule_v2(
  text, app_finance.recurring_rule_kind, bigint,
  app_finance.recurring_frequency, smallint, date, smallint, uuid, uuid,
  uuid, uuid, text, uuid, boolean, boolean
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Accept recurring occurrence: network destinations create pending transfers
-- ---------------------------------------------------------------------------

-- Approving a recurring occurrence that targets a network contact creates the
-- pending network transfer once (idempotency key recurring:<occurrence_id>)
-- and books nothing: the receiver still accepts or rejects. Local rules keep
-- booking through create_transfer exactly as before.
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
  v_network_transfer_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_actual_amount_minor is null or p_actual_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  select o.* into v_occurrence from app_finance.recurring_occurrences o
    where o.id = p_occurrence_id and o.user_id = v_user_id for update;
  if v_occurrence is null then raise exception 'not_found: recurring occurrence'; end if;
  if v_occurrence.status = 'accepted' then
    return coalesce(v_occurrence.transaction_id, (
      select nt.id from app_finance.network_transfers nt
      where nt.sender_user_id = v_user_id
        and nt.origin_kind = 'recurring_rule'
        and nt.origin_id = v_occurrence.id
      limit 1
    ));
  end if;
  if v_occurrence.status <> 'pending' then raise exception 'already_decided: this entry was already handled'; end if;
  select r.* into v_rule from app_finance.recurring_rules r
    where r.id = v_occurrence.rule_id and r.user_id = v_user_id;
  if v_rule.rule_kind = 'transfer' then
    if v_rule.destination_network_connection_id is not null then
      v_network_transfer_id := app_private.create_network_transfer(
        v_user_id, v_rule.destination_network_connection_id,
        v_rule.source_account_id, p_actual_amount_minor, p_paid_on,
        p_notes, 'recurring_rule', v_occurrence.id,
        'recurring:' || v_occurrence.id::text
      );
    elsif v_rule.destination_account_id is null then
      raise exception
        'network_destination_unavailable: edit this automation';
    else
      v_tx_id := app_finance.create_transfer(v_rule.source_account_id,
        v_rule.destination_account_id, p_actual_amount_minor, p_paid_on, p_notes);
    end if;
  elsif exists (select 1 from app_finance.accounts a where a.id = v_rule.source_account_id
    and a.account_type = 'credit_card') then
    v_tx_id := app_finance.charge_credit_card(
      p_account_id => v_rule.source_account_id,
      p_title => v_rule.name,
      p_category_id => v_rule.category_id,
      p_occurred_on => p_paid_on,
      p_amount_minor => p_actual_amount_minor,
      p_notes => p_notes,
      p_charge_id => null,
      p_is_foreign_currency => v_rule.is_foreign_currency
    );
  else
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (v_user_id, 'expense', p_paid_on, p_actual_amount_minor,
      v_rule.currency_code, v_rule.source_account_id, v_rule.category_id,
      v_rule.name, p_notes) returning id into v_tx_id;
  end if;
  update app_finance.recurring_occurrences set status = 'accepted',
    actual_amount_minor = p_actual_amount_minor, paid_on = p_paid_on,
    transaction_id = v_tx_id, decision_at = now(), notes = coalesce(p_notes, notes)
    where id = p_occurrence_id and user_id = v_user_id;
  return coalesce(v_tx_id, v_network_transfer_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Save income source: allocations may target a network connection
-- ---------------------------------------------------------------------------

-- Same signature as before: allocation items in p_allocations may now carry
-- destination_network_connection_id instead of destination_account_id.
-- Released clients that never send the key are unaffected.
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
    user_id, income_source_id, destination_account_id,
    destination_network_connection_id, allocation_method,
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
    (item ->> 'destination_network_connection_id')::uuid,
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

-- v5 adds the network extra-work destination on top of v4's rollover
-- controls. Released clients on v4 and earlier keep working unchanged.
create or replace function app_finance.save_income_source_v5(
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
  p_extra_work_destination_network_connection_id uuid default null,
  p_rollover_balance_enabled boolean default false,
  p_rollover_destination_account_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  if p_extra_work_destination_account_id is not null
      and p_extra_work_destination_network_connection_id is not null then
    raise exception 'invalid_destination: choose one destination';
  end if;
  if p_extra_work_destination_network_connection_id is not null
    and not exists (
      select 1 from app_finance.network_connections c
      where c.id = p_extra_work_destination_network_connection_id
        and v_user_id in (c.user_a_id, c.user_b_id)
        and c.removed_at is null
    ) then
    raise exception 'not_found: network connection';
  end if;

  v_source_id := app_finance.save_income_source_v4(
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
      p_extra_work_destination_account_id,
    p_rollover_balance_enabled => p_rollover_balance_enabled,
    p_rollover_destination_account_id => p_rollover_destination_account_id
  );

  update app_finance.income_sources
  set extra_work_destination_network_connection_id = case
      when p_source_kind = 'salary'
        and not coalesce(p_include_extra_work_in_percentage, true)
        then p_extra_work_destination_network_connection_id
      else null
    end
  where id = v_source_id and user_id = v_user_id;

  return v_source_id;
end;
$$;

revoke execute on function app_finance.save_income_source_v5(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean, boolean, uuid, uuid,
  boolean, uuid
) from public, anon;
grant execute on function app_finance.save_income_source_v5(
  text, app_finance.income_source_kind, bigint, text, smallint, date,
  smallint, uuid, uuid, jsonb, text, uuid, boolean, boolean, uuid, uuid,
  boolean, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Accept income occurrence: network splits create pending transfers
-- ---------------------------------------------------------------------------

-- Income still posts exactly once to the primary account. A network split
-- consumes its share of the allocation basis but books nothing: it creates a
-- pending network transfer (idempotency key
-- income:<occurrence_id>:<allocation_id>) and the sender's balance moves only
-- when the receiver accepts. Extra-work pay routed to a network contact
-- follows the same rule (key extra-work:<occurrence_id>), and the remainder
-- chain counts network-routed extra work (pending or accepted) so late money
-- does not route it twice.
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
  v_snapshot jsonb;
  v_is_remainder boolean;
  v_root_id uuid;
  v_root_period_id uuid;
  v_tx_id uuid;
  v_allocation record;
  v_transfer_amount bigint;
  v_extra_work_minor bigint := 0;
  v_routed_extra_minor bigint := 0;
  v_routed_extra_network_minor bigint := 0;
  v_expected_total_minor bigint := 0;
  v_shortfall_minor bigint := 0;
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
  if v_occurrence is null then
    raise exception 'not_found: income occurrence';
  end if;
  if v_occurrence.status = 'accepted' then
    return v_occurrence.primary_transaction_id;
  end if;
  if v_occurrence.status <> 'pending' then raise exception 'already_decided'; end if;

  select * into v_source
  from app_finance.income_sources
  where id = v_occurrence.income_source_id
    and user_id = v_user_id
    and is_active;
  if v_source is null then raise exception 'invalid_income_source'; end if;

  v_is_remainder := v_occurrence.remainder_of_occurrence_id is not null;

  if v_is_remainder then
    -- The salary period belongs to the payment as a whole and was already
    -- settled by the acceptance this remainder came from.
    if p_salary_period_id is not null then
      raise exception 'invalid_salary_period';
    end if;
    select root.id, root.salary_period_id
      into v_root_id, v_root_period_id
    from app_finance.income_occurrences root
    where root.user_id = v_user_id
      and root.id = (
        with recursive chain (id, parent_id) as (
          select o.id, o.remainder_of_occurrence_id
          from app_finance.income_occurrences o
          where o.id = v_occurrence.id
          union all
          select parent.id, parent.remainder_of_occurrence_id
          from app_finance.income_occurrences parent
          join chain c on parent.id = c.parent_id
        )
        select c.id from chain c where c.parent_id is null
      );
    if v_root_period_id is not null then
      select sp.snapshot into v_snapshot
      from app_salary.salary_periods sp
      where sp.id = v_root_period_id and sp.user_id = v_user_id;
    end if;
  elsif v_source.source_kind = 'salary' then
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
    v_snapshot := v_period.snapshot;
  elsif p_salary_period_id is not null then
    raise exception 'invalid_salary_period';
  end if;

  if v_snapshot is not null then
    v_extra_work_minor :=
      coalesce((v_snapshot ->> 'extra_day_amount_minor')::bigint, 0) +
      coalesce((v_snapshot ->> 'overtime_amount_minor')::bigint, 0) +
      coalesce((v_snapshot ->> 'holiday_amount_minor')::bigint, 0);

    if v_is_remainder then
      -- Late money first replaces the extra-work pay that the shortfall ate,
      -- counting whatever earlier acceptances of this payment already routed
      -- to an own account or to a network contact (pending counts too: the
      -- request is out even before the receiver accepts it).
      select coalesce(sum(t.amount_minor), 0) into v_routed_extra_minor
      from app_finance.financial_transactions t
      where t.user_id = v_user_id
        and t.is_extra_work_routing
        and t.income_occurrence_id in (
          with recursive chain (id) as (
            select v_root_id::uuid
            union all
            select child.id
            from app_finance.income_occurrences child
            join chain c on child.remainder_of_occurrence_id = c.id
          )
          select c.id from chain c
        );
      select coalesce(sum(nt.amount_minor), 0)
        into v_routed_extra_network_minor
      from app_finance.network_transfers nt
      where nt.sender_user_id = v_user_id
        and nt.origin_kind = 'extra_work_allocation'
        and nt.status in ('pending', 'accepted')
        and nt.origin_id in (
          with recursive chain (id) as (
            select v_root_id::uuid
            union all
            select child.id
            from app_finance.income_occurrences child
            join chain c on child.remainder_of_occurrence_id = c.id
          )
          select c.id from chain c
        );
      v_extra_work_minor := greatest(
        v_extra_work_minor - v_routed_extra_minor
          - v_routed_extra_network_minor,
        0);
    else
      v_expected_total_minor := coalesce(
        (v_snapshot ->> 'total_minor')::bigint,
        coalesce((v_snapshot ->> 'base_salary_minor')::bigint, 0)
          + v_extra_work_minor
          + coalesce((v_snapshot ->> 'bonuses_minor')::bigint, 0)
          - coalesce((v_snapshot ->> 'deductions_minor')::bigint, 0)
      );
      -- Money that never arrived comes out of the extra-work pay first.
      v_shortfall_minor :=
        greatest(v_expected_total_minor - p_actual_amount_minor, 0);
      v_extra_work_minor :=
        greatest(v_extra_work_minor - v_shortfall_minor, 0);
    end if;

    if not v_source.include_extra_work_in_percentage then
      v_protected_extra_minor :=
        least(greatest(v_extra_work_minor, 0), p_actual_amount_minor);
    end if;
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
    -- Fixed splits are once per payment: the acceptance this remainder came
    -- from already booked them, so late money only re-applies percentages.
    if v_is_remainder and v_allocation.allocation_method <> 'percentage' then
      continue;
    end if;

    if v_allocation.allocation_method = 'percentage' then
      v_percentage_index := v_percentage_index + 1;
      if v_percentage_index = 1
        or v_allocation.calculation_basis = 'original' then
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
      if v_allocation.destination_network_connection_id is not null then
        perform app_private.create_network_transfer(
          v_user_id, v_allocation.destination_network_connection_id,
          v_source.primary_account_id, v_transfer_amount, p_received_on,
          v_source.name || ' automatic allocation',
          'income_allocation', v_occurrence.id,
          'income:' || v_occurrence.id::text
            || ':' || v_allocation.id::text
        );
      elsif v_allocation.destination_account_id is not null then
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
      else
        raise exception
          'network_destination_unavailable: edit this automation';
      end if;
    end if;
  end loop;

  if v_protected_extra_minor > 0 then
    if v_source.extra_work_destination_network_connection_id is not null then
      perform app_private.create_network_transfer(
        v_user_id, v_source.extra_work_destination_network_connection_id,
        v_source.primary_account_id, v_protected_extra_minor, p_received_on,
        v_source.name || ' extra work allocation',
        'extra_work_allocation', v_occurrence.id,
        'extra-work:' || v_occurrence.id::text
      );
    elsif v_source.extra_work_destination_account_id is not null then
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

notify pgrst, 'reload schema';
