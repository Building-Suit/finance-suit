-- Calendar-month due breakdown and month-scoped prepayment.
--
-- `facility_due_breakdown(account, as_of)` answers "what is payable now": it
-- accumulates every closed unpaid statement and every due on or before the
-- as-of date, and only falls back to the next upcoming due date when nothing
-- is currently payable. That is the right contract for the Pay screen, but it
-- cannot describe one calendar month in isolation — asking it for next month
-- would sweep this month's unpaid dues in with it.
--
-- This migration adds:
--   1. app_finance.facility_month_due_breakdown(account, month_start) — the
--      dues that fall inside one calendar month, with the same component
--      shape the existing breakdown returns so clients reuse one model;
--   2. app_finance.pay_credit_facility_v3(...) — the same atomic repayment as
--      v2 but with an explicit target month, so a user can prepay next
--      month's dues while this month still has unpaid ones. v2 keeps its
--      exact contract and "currently payable" eligibility for existing
--      callers.
--
-- Month membership is defined by when the money is owed:
--   * installment due  -> installment_dues.due_on
--   * statement item   -> the due_on of the statement cycle it belongs to
--
-- Prepayment isolation: allocations are still per component, so paying a
-- next-month component only reduces that component's remaining amount. The
-- statement/installment paid state, the cycle compatibility aggregate, and
-- the ledger transfer all behave exactly as in v2 — nothing about the due
-- date changes because the money arrived early, and the due can never be
-- charged twice because its remaining amount is what gates any later payment.

-- ---------------------------------------------------------------------------
-- 1. Month-scoped due breakdown
-- ---------------------------------------------------------------------------

create or replace function app_finance.facility_month_due_breakdown(
  p_account_id uuid,
  p_month_start date default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
  v_month_start date := date_trunc(
    'month', coalesce(p_month_start, current_date)
  )::date;
  v_month_end date;
  v_cycles jsonb;
  v_components jsonb;
  v_minimum_due bigint;
  v_minimum_remaining bigint;
  v_total_due bigint;
  v_paid bigint;
  v_remaining bigint;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  select a.id, a.account_type, a.currency_code into v_account
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id
    and app_finance.account_role(a.account_type) = 'liability';
  if v_account is null then
    raise exception 'invalid_account: liability account required';
  end if;
  v_month_end := (v_month_start + interval '1 month - 1 day')::date;

  -- Statement cycles whose payment falls due inside the month.
  select coalesce(jsonb_agg(jsonb_build_object(
      'cycle_id', y.id,
      'cycle_start', y.cycle_start,
      'cycle_close', y.cycle_close,
      'due_on', y.due_on,
      'total_statement_due_minor', y.total_statement_due_minor,
      'total_paid_minor', y.total_paid_minor,
      'total_remaining_minor', y.total_remaining_minor,
      'minimum_due_minor', y.minimum_due_minor,
      'minimum_remaining_minor', y.minimum_remaining_minor,
      'obligation_status', y.obligation_status
    ) order by y.due_on, y.cycle_close), '[]'::jsonb),
    sum(y.minimum_due_minor)::bigint,
    sum(y.minimum_remaining_minor)::bigint
  into v_cycles, v_minimum_due, v_minimum_remaining
  from app_finance.credit_card_statement_summaries y
  where y.user_id = v_user_id and y.account_id = p_account_id
    and y.due_on between v_month_start and v_month_end;

  with statement_components as (
    select
      'statement_item' as component_type,
      st.statement_item_id as component_id,
      null::uuid as plan_id,
      st.cycle_id,
      st.transaction_id,
      st.title,
      st.activity_kind,
      st.fee_type::text as fee_type,
      null::integer as sequence_number,
      null::integer as installment_count,
      st.occurred_on as component_on,
      st.cycle_due_on as due_on,
      st.amount_minor,
      st.paid_minor,
      st.remaining_minor,
      st.payment_status
    from app_finance.credit_card_statement_item_statuses st
    where st.user_id = v_user_id and st.account_id = p_account_id
      and st.cycle_due_on between v_month_start and v_month_end
  ),
  installment_components as (
    select
      'installment_due' as component_type,
      s.id as component_id,
      s.plan_id,
      null::uuid as cycle_id,
      null::uuid as transaction_id,
      s.plan_title as title,
      'installment_due' as activity_kind,
      null::text as fee_type,
      s.sequence_number,
      p.installment_count,
      s.due_on as component_on,
      s.due_on,
      s.amount_minor,
      s.paid_minor,
      s.remaining_minor,
      case
        when s.remaining_minor = 0 then 'paid'
        when s.paid_minor > 0 then 'partially_paid'
        else 'unpaid'
      end as payment_status
    from app_finance.installment_due_statuses s
    join app_finance.installment_plans p on p.id = s.plan_id
    where s.user_id = v_user_id and s.account_id = p_account_id
      and s.plan_status <> 'cancelled'
      and not s.is_presettled
      and s.due_on between v_month_start and v_month_end
  ),
  all_components as (
    select * from installment_components
    union all
    select * from statement_components
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'component_type', component_type,
      'component_id', component_id,
      'plan_id', plan_id,
      'cycle_id', cycle_id,
      'transaction_id', transaction_id,
      'title', title,
      'activity_kind', activity_kind,
      'fee_type', fee_type,
      'sequence_number', sequence_number,
      'installment_count', installment_count,
      'occurred_on', component_on,
      'due_on', due_on,
      'amount_minor', amount_minor,
      'paid_minor', paid_minor,
      'remaining_minor', remaining_minor,
      'payment_status', payment_status,
      'scope', 'current'
    ) order by
      case when component_type = 'installment_due' then 0 else 1 end,
      case when activity_kind in
        ('fee_charge', 'purchase_interest', 'installment_interest')
        then 0 else 1 end,
      due_on, component_on, component_id), '[]'::jsonb),
    coalesce(sum(amount_minor), 0)::bigint,
    coalesce(sum(paid_minor), 0)::bigint,
    coalesce(sum(remaining_minor), 0)::bigint
  into v_components, v_total_due, v_paid, v_remaining
  from all_components;

  return jsonb_build_object(
    'account_id', p_account_id,
    'account_type', v_account.account_type,
    'currency_code', v_account.currency_code,
    'as_of', v_month_start,
    'month_start', v_month_start,
    'month_end', v_month_end,
    'outstanding_minor', app_finance.facility_outstanding_minor(p_account_id),
    'total_due_minor', v_total_due,
    'paid_minor', v_paid,
    'remaining_minor', v_remaining,
    -- A calendar month never carries the unbilled facility balance: that is
    -- not owed in this period, so the month card must not offer it.
    'additional_balance_minor', 0,
    'minimum_due_minor', case when v_account.account_type = 'credit_card'
      then v_minimum_due else null end,
    'minimum_remaining_minor', case when v_account.account_type = 'credit_card'
      then v_minimum_remaining else null end,
    'cycles', coalesce(v_cycles, '[]'::jsonb),
    'components', v_components
  );
end;
$$;

comment on function app_finance.facility_month_due_breakdown(uuid, date) is
  'Dues falling inside one calendar month (installment dues by due_on, '
  'statement items by their cycle due_on). Unlike facility_due_breakdown '
  'this never accumulates earlier periods, so it can describe next month in '
  'isolation for prepayment.';

revoke execute on function
  app_finance.facility_month_due_breakdown(uuid, date) from public, anon;
grant execute on function
  app_finance.facility_month_due_breakdown(uuid, date)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Month-scoped payment
-- ---------------------------------------------------------------------------

create or replace function app_finance.pay_credit_facility_v3(
  p_account_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_paid_on date,
  p_month_start date,
  p_allocations jsonb,
  p_notes text default null,
  p_payment_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_facility record;
  v_source record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_allocation jsonb;
  v_type text;
  v_target_id uuid;
  v_alloc_amount bigint;
  v_alloc_total bigint := 0;
  v_seen_targets text[] := array[]::text[];
  v_target_key text;
  v_due record;
  v_item record;
  v_month_start date;
  v_month_end date;
  v_current_month date := date_trunc('month', current_date)::date;
  v_existing_amount bigint;
  v_existing jsonb;
  v_requested jsonb;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if p_month_start is null then
    raise exception 'invalid_period: target month required';
  end if;
  v_month_start := date_trunc('month', p_month_start)::date;
  v_month_end := (v_month_start + interval '1 month - 1 day')::date;
  -- Only this month and next month are payable. Anything further out is not
  -- exposed by the product and must not become payable through the API.
  if v_month_start <> v_current_month
    and v_month_start <> (v_current_month + interval '1 month')::date then
    raise exception
      'invalid_period: only the current or next calendar month can be paid';
  end if;
  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array'
    or jsonb_array_length(p_allocations) = 0 then
    raise exception 'invalid_allocations: expected a non-empty array';
  end if;

  -- Idempotency: an identical retry returns the stored payment; the same id
  -- with a different amount or allocation intent is a typed conflict.
  if p_payment_id is not null then
    select t.id, t.amount_minor into v_tx_id, v_existing_amount
    from app_finance.financial_transactions t
    where t.id = p_payment_id and t.user_id = v_user_id;
    if v_tx_id is not null then
      select coalesce(jsonb_agg(entry order by entry::text), '[]'::jsonb)
      into v_existing
      from (
        select jsonb_build_object('type', 'installment_due',
          'id', pa.due_id, 'amount_minor', pa.amount_minor) as entry
        from app_finance.installment_payment_allocations pa
        where pa.payment_transaction_id = v_tx_id
          and pa.user_id = v_user_id
        union all
        select jsonb_build_object('type', 'statement_item',
          'id', ia.statement_item_id, 'amount_minor', ia.amount_minor)
        from app_finance.credit_card_statement_item_allocations ia
        where ia.payment_transaction_id = v_tx_id
          and ia.user_id = v_user_id
      ) stored;
      select coalesce(jsonb_agg(entry order by entry::text), '[]'::jsonb)
      into v_requested
      from (
        select jsonb_build_object('type', a ->> 'type',
          'id', (a ->> 'id')::uuid,
          'amount_minor', (a ->> 'amount_minor')::bigint) as entry
        from jsonb_array_elements(p_allocations) a
      ) requested;
      if v_existing_amount = p_amount_minor and v_existing = v_requested then
        return v_tx_id;
      end if;
      raise exception
        'payment_conflict: payment id already used with different allocations';
    end if;
  end if;

  select a.id, a.currency_code, a.account_type into v_facility
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id
  for update;
  if v_facility is null
    or app_finance.account_role(v_facility.account_type) <> 'liability' then
    raise exception 'invalid_account: liability account required';
  end if;
  select a.id, a.currency_code, a.account_type into v_source
  from app_finance.accounts a
  where a.id = p_source_account_id and a.user_id = v_user_id
    and not a.is_archived;
  if v_source is null
    or app_finance.account_role(v_source.account_type) <> 'asset' then
    raise exception 'invalid_account: source asset required';
  end if;
  if v_source.currency_code <> v_facility.currency_code then
    raise exception 'currency_mismatch: matching currencies required';
  end if;

  -- Interest is materialized up to the payment date only: prepaying a future
  -- due must not recognize its interest in the ledger early.
  perform app_finance.materialize_installment_interest(p_paid_on, p_account_id);
  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if p_amount_minor > v_outstanding then
    raise exception 'overpayment_rejected: payment exceeds amount owed';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, notes
  ) values (
    coalesce(p_payment_id, gen_random_uuid()), v_user_id, 'transfer',
    p_paid_on, p_amount_minor, v_facility.currency_code,
    p_source_account_id, p_account_id, p_notes
  ) returning id into v_tx_id;

  for v_allocation in select * from jsonb_array_elements(p_allocations)
  loop
    v_type := v_allocation ->> 'type';
    if v_type is null
      or v_type not in ('installment_due', 'statement_item') then
      raise exception 'invalid_allocations: unknown allocation type';
    end if;
    begin
      v_alloc_amount := (v_allocation ->> 'amount_minor')::bigint;
      v_target_id := (v_allocation ->> 'id')::uuid;
    exception when others then
      raise exception 'invalid_allocations: malformed allocation entry';
    end;
    if v_alloc_amount is null or v_alloc_amount <= 0 then
      raise exception 'invalid_allocations: amounts must be positive';
    end if;
    if v_target_id is null then
      raise exception 'invalid_allocations: allocation target required';
    end if;
    v_target_key := v_type || ':' || v_target_id::text;
    if v_target_key = any(v_seen_targets) then
      raise exception 'invalid_allocations: duplicate allocation target';
    end if;
    v_seen_targets := array_append(v_seen_targets, v_target_key);
    v_alloc_total := v_alloc_total + v_alloc_amount;

    if v_type = 'installment_due' then
      select s.id, s.remaining_minor, s.due_on into v_due
      from app_finance.installment_due_statuses s
      where s.id = v_target_id
        and s.user_id = v_user_id and s.account_id = p_account_id
        and s.plan_status = 'active'
        and not s.is_presettled;
      if v_due is null then raise exception 'not_found: installment due'; end if;
      if v_due.remaining_minor <= 0 then
        raise exception 'allocation_target_paid: installment due settled';
      end if;
      if v_alloc_amount > v_due.remaining_minor then
        raise exception 'allocation_exceeds_due';
      end if;
      if v_due.due_on < v_month_start or v_due.due_on > v_month_end then
        raise exception
          'allocation_out_of_period: component is not due in the paid month';
      end if;
      insert into app_finance.installment_payment_allocations (
        user_id, payment_transaction_id, due_id, amount_minor
      ) values (v_user_id, v_tx_id, v_due.id, v_alloc_amount);
    else
      select st.statement_item_id, st.remaining_minor, st.cycle_due_on
        into v_item
      from app_finance.credit_card_statement_item_statuses st
      where st.statement_item_id = v_target_id
        and st.user_id = v_user_id and st.account_id = p_account_id;
      if v_item is null then raise exception 'not_found: statement item'; end if;
      if v_item.remaining_minor <= 0 then
        raise exception 'allocation_target_paid: statement item settled';
      end if;
      if v_alloc_amount > v_item.remaining_minor then
        raise exception 'allocation_exceeds_item';
      end if;
      if v_item.cycle_due_on < v_month_start
        or v_item.cycle_due_on > v_month_end then
        raise exception
          'allocation_out_of_period: component is not due in the paid month';
      end if;
      insert into app_finance.credit_card_statement_item_allocations (
        user_id, payment_transaction_id, statement_item_id, amount_minor
      ) values (v_user_id, v_tx_id, v_item.statement_item_id, v_alloc_amount);
    end if;
  end loop;

  if v_alloc_total <> p_amount_minor then
    raise exception
      'allocation_total_mismatch: allocations must equal the payment amount';
  end if;

  -- Cycle-level compatibility aggregates: exactly the per-cycle sums of the
  -- item rows written above, so legacy statement consumers keep working.
  insert into app_finance.credit_card_statement_allocations (
    user_id, payment_transaction_id, cycle_id, amount_minor
  )
  select v_user_id, v_tx_id, si.cycle_id, sum(ia.amount_minor)::bigint
  from app_finance.credit_card_statement_item_allocations ia
  join app_finance.credit_card_statement_items si
    on si.id = ia.statement_item_id
  where ia.payment_transaction_id = v_tx_id and ia.user_id = v_user_id
  group by si.cycle_id;

  update app_finance.installment_plans p set status = 'completed'
  where p.user_id = v_user_id and p.account_id = p_account_id
    and p.status = 'active' and not exists (
      select 1 from app_finance.installment_due_statuses s
      where s.plan_id = p.id and s.remaining_minor > 0
    );
  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

comment on function app_finance.pay_credit_facility_v3(
  uuid, uuid, bigint, date, date, jsonb, text, uuid
) is
  'Month-scoped facility repayment. Identical to pay_credit_facility_v2 in '
  'ledger effect, allocation persistence, locking and idempotency, but every '
  'component must be due inside the explicit target month, which must be the '
  'current or next calendar month. Lets a user prepay next month while this '
  'month is still unpaid, without making arbitrary future dues payable.';

revoke execute on function app_finance.pay_credit_facility_v3(
  uuid, uuid, bigint, date, date, jsonb, text, uuid
) from public, anon;
grant execute on function app_finance.pay_credit_facility_v3(
  uuid, uuid, bigint, date, date, jsonb, text, uuid
) to authenticated, service_role;

notify pgrst, 'reload schema';
