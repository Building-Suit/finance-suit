-- Partial income acceptance: when less money arrives than was owed (a
-- 44,000 salary paid as 40,000), the user accepts what actually landed and
-- the difference becomes a linked *remainder occurrence* — a pending item
-- that keeps showing until the money arrives (accept) or is written off
-- (skip). The earned figures never shrink: the salary period books the
-- received amount while the remainder tracks the shortfall explicitly, so
-- extra-work math stays truthful.

-- ---------------------------------------------------------------------------
-- Remainder link
-- ---------------------------------------------------------------------------

alter table app_finance.income_occurrences
  add column if not exists remainder_of_occurrence_id uuid
    references app_finance.income_occurrences (id) on delete cascade;

create index if not exists idx_income_occurrences_remainder
  on app_finance.income_occurrences (remainder_of_occurrence_id)
  where remainder_of_occurrence_id is not null;

-- Remainders share their parent's source and may land on any date, so the
-- one-per-day schedule key must only bind the materialized schedule rows.
alter table app_finance.income_occurrences
  drop constraint if exists income_occurrence_schedule_unique;
drop index if exists app_finance.income_occurrence_schedule_unique;
create unique index income_occurrence_schedule_unique
  on app_finance.income_occurrences (income_source_id, scheduled_on)
  where remainder_of_occurrence_id is null;

-- ---------------------------------------------------------------------------
-- Materialization targets only schedule rows
-- ---------------------------------------------------------------------------

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
      if v_scheduled >= v_source.start_date
        and v_scheduled <= p_through_date then
        insert into app_finance.income_occurrences (
          user_id, income_source_id, scheduled_on, expected_amount_minor
        ) values (
          v_user_id, v_source.id, v_scheduled, v_source.expected_amount_minor
        ) on conflict (income_source_id, scheduled_on)
          where remainder_of_occurrence_id is null
          do nothing;
        if found then v_inserted := v_inserted + 1; end if;
      end if;
      v_month := (v_month + interval '1 month')::date;
    end loop;
  end loop;
  return v_inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accept learns about remainders
-- ---------------------------------------------------------------------------

-- A remainder is late money that was already earned and split: its parent
-- acceptance ran the salary period, the allocations, and the extra-work
-- routing on the amount that arrived then. Accepting the remainder books
-- one plain income transaction into the primary account — no second
-- period, no second split pass.
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

  if v_occurrence.remainder_of_occurrence_id is not null then
    if p_salary_period_id is not null then
      raise exception 'invalid_salary_period';
    end if;

    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      destination_account_id, category_id, title, notes,
      income_occurrence_id
    ) values (
      v_user_id, v_source.transaction_kind, p_received_on,
      p_actual_amount_minor, v_source.currency_code,
      v_source.primary_account_id, v_source.category_id, v_source.name,
      p_notes, v_occurrence.id
    ) returning id into v_tx_id;

    update app_finance.income_occurrences set
      status = 'accepted',
      actual_amount_minor = p_actual_amount_minor,
      received_on = p_received_on,
      primary_transaction_id = v_tx_id,
      decision_at = now(),
      notes = p_notes
    where id = p_occurrence_id;

    return v_tx_id;
  end if;

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
      v_protected_extra_minor :=
        least(greatest(v_extra_work_minor, 0), p_actual_amount_minor);
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

-- ---------------------------------------------------------------------------
-- Partial acceptance
-- ---------------------------------------------------------------------------

-- Books the received part exactly like a normal acceptance (salary period,
-- splits, extra-work routing all run on what arrived), then spawns a
-- pending remainder for the difference so the shortfall stays visible
-- until it is received or explicitly skipped.
create or replace function app_finance.accept_income_occurrence_partial(
  p_occurrence_id uuid,
  p_received_amount_minor bigint,
  p_expected_total_minor bigint,
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
  v_tx_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_received_amount_minor is null or p_received_amount_minor <= 0 then
    raise exception 'invalid_amount';
  end if;
  if p_expected_total_minor is null
    or p_expected_total_minor <= p_received_amount_minor then
    raise exception
      'invalid_partial: the amount owed must exceed the amount received';
  end if;

  select * into v_occurrence
  from app_finance.income_occurrences
  where id = p_occurrence_id and user_id = v_user_id
  for update;
  if v_occurrence is null then
    raise exception 'not_found: income occurrence';
  end if;
  if v_occurrence.status <> 'pending' then
    raise exception 'already_decided';
  end if;

  v_tx_id := app_finance.accept_income_occurrence(
    p_occurrence_id, p_received_amount_minor, p_received_on, p_notes,
    p_salary_period_id
  );

  insert into app_finance.income_occurrences (
    user_id, income_source_id, scheduled_on, expected_amount_minor,
    remainder_of_occurrence_id
  ) values (
    v_user_id, v_occurrence.income_source_id, p_received_on,
    p_expected_total_minor - p_received_amount_minor, p_occurrence_id
  );

  return v_tx_id;
end;
$$;

revoke execute on function app_finance.accept_income_occurrence_partial(
  uuid, bigint, bigint, date, text, uuid
) from public, anon;
grant execute on function app_finance.accept_income_occurrence_partial(
  uuid, bigint, bigint, date, text, uuid
) to authenticated, service_role;

notify pgrst, 'reload schema';
