-- A salary that arrives short must not keep routing the full extra-work pay
-- to savings. The money that never arrived is taken out of the extra-work
-- earnings first; only what the extra work cannot absorb is taken off the
-- base salary, and the rest of the automation (percentage splits, extra-work
-- routing) keeps running on what actually landed.
--
-- The held-back extra work is not lost: when the missing part arrives later
-- as a remainder occurrence, it carries the extra-work pay that was withheld,
-- so a partial payment plus its remainder end up exactly where one full
-- payment would have.

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
      -- counting whatever earlier acceptances of this payment already routed.
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
      v_extra_work_minor :=
        greatest(v_extra_work_minor - v_routed_extra_minor, 0);
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
-- The previous balance rolls over once per payment
-- ---------------------------------------------------------------------------

-- A remainder is late money for a payment that already swept the previous
-- balance into savings. Without this guard, accepting it would sweep the
-- account a second time and empty everything the salary just paid.
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
    source.rollover_destination_account_id,
    (occurrence.remainder_of_occurrence_id is not null) as is_remainder
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
  if coalesce(v_source.is_remainder, false) then
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

revoke execute on function app_private.rollover_previous_salary_balance()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
