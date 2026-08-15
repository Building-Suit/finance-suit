-- Selectable payment allocation for credit facilities.
--
-- The Pay Credit Facility flow becomes an explicit checklist: the user picks
-- exactly which currently payable components (statement items and installment
-- dues) a repayment satisfies. That requires item-level statement allocation
-- state, which production only tracked at cycle level.
--
-- This migration:
--   1. adds app_finance.credit_card_statement_item_allocations — one row per
--      (payment, statement item), guarded like every other facility table;
--   2. backfills item-level rows for historical cycle allocations using the
--      same deterministic oldest-first order the legacy waterfall used
--      (marked allocation_origin = 'legacy_inferred'); cycles whose legacy
--      aggregate cannot be proven to map onto their items are left untouched
--      and their item state stays indeterminate rather than fabricated;
--   3. adds app_finance.credit_card_statement_item_statuses — the canonical
--      per-item paid/partially_paid/unpaid view;
--   4. extends credit_card_statement_summaries with minimum_paid_minor and
--      minimum_remaining_minor (qualifying payments are exactly the payments
--      already counted in total_paid_minor: allocations to this cycle's card
--      charges plus allocations to this cycle's installment dues — money
--      allocated to other cycles or future dues does not satisfy the minimum);
--   5. adds app_finance.facility_due_breakdown — the single authoritative DTO
--      for the Pay screen checklist and the persistent Due Breakdown;
--   6. adds app_finance.pay_credit_facility_v2 — typed allocations
--      ({type, id, amount_minor}) whose total must equal the payment amount;
--   7. adds app_finance.facility_payment_allocations — the persisted
--      "Applied to" detail for payment history;
--   8. teaches reverse_facility_payment and delete_finance_suit_data about
--      the new table.
--
-- Accounting invariants preserved:
--   * a facility repayment stays ONE liability-reducing transfer; allocation
--     rows never post a second financial effect and never touch balances;
--   * credit_card_statement_allocations (cycle level) remains the single
--     authoritative source for statement paid state in
--     credit_card_statement_summaries; v2 writes the cycle aggregate as the
--     exact per-cycle sum of the item rows it creates, so the two levels can
--     never diverge for new payments and are never added together;
--   * the backfill changes no balance, no payment amount, and no statement
--     total — it only adds detail rows underneath existing aggregates.

-- ---------------------------------------------------------------------------
-- 1. Item-level statement allocation table
-- ---------------------------------------------------------------------------

create table if not exists app_finance.credit_card_statement_item_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  payment_transaction_id uuid not null,
  statement_item_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  allocation_origin text not null default 'user_selected'
    check (allocation_origin in ('user_selected', 'legacy_inferred', 'system')),
  created_at timestamptz not null default now(),
  constraint statement_item_allocations_owner_unique unique (id, user_id),
  constraint statement_item_allocations_pair_unique
    unique (payment_transaction_id, statement_item_id),
  constraint statement_item_allocations_payment_owner_fk
    foreign key (payment_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade,
  constraint statement_item_allocations_item_owner_fk
    foreign key (statement_item_id, user_id)
    references app_finance.credit_card_statement_items (id, user_id)
    on delete cascade
);

create index if not exists idx_statement_item_allocations_item
  on app_finance.credit_card_statement_item_allocations
  (statement_item_id, user_id);
create index if not exists idx_statement_item_allocations_payment
  on app_finance.credit_card_statement_item_allocations
  (payment_transaction_id, user_id);

alter table app_finance.credit_card_statement_item_allocations
  enable row level security;
drop policy if exists credit_card_statement_item_allocations_select
  on app_finance.credit_card_statement_item_allocations;
create policy credit_card_statement_item_allocations_select
  on app_finance.credit_card_statement_item_allocations
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_item_allocations_insert
  on app_finance.credit_card_statement_item_allocations;
create policy credit_card_statement_item_allocations_insert
  on app_finance.credit_card_statement_item_allocations
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_statement_item_allocations_delete
  on app_finance.credit_card_statement_item_allocations;
create policy credit_card_statement_item_allocations_delete
  on app_finance.credit_card_statement_item_allocations
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Writes only happen through the facility payment/reversal RPCs.
drop trigger if exists trg_protect_statement_item_allocations
  on app_finance.credit_card_statement_item_allocations;
create trigger trg_protect_statement_item_allocations
  before insert or update or delete
  on app_finance.credit_card_statement_item_allocations
  for each row execute function app_private.protect_installment_rows();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'app_finance'
      and tablename = 'credit_card_statement_item_allocations'
  ) then
    execute 'alter publication supabase_realtime add table '
      'app_finance.credit_card_statement_item_allocations';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Historical backfill (legacy_inferred)
--
-- Legacy cycle allocations were produced by a deterministic oldest-first
-- waterfall, but which items inside the cycle a payment covered was never
-- stored. The only faithful reconstruction is to replay that same
-- deterministic order: items sorted by (occurred_on, transaction_id) — the
-- exact order rebuild_credit_card_statement_cycles uses — and payments sorted
-- by (occurred_on, created_at, id). Each payment's cycle amount then maps to
-- the interval intersection of the two cumulative sequences.
--
-- A cycle is only backfilled when its legacy allocation total fits inside its
-- item total (sum of allocations <= sum of items). Anything else cannot be
-- mapped truthfully; those cycles keep only their legacy aggregate and their
-- item state remains indeterminate (surfaced as 'statement_cycle' rows by
-- facility_payment_allocations rather than invented checkmarks).
--
-- The insert changes no balances and no aggregates: for every backfilled
-- (payment, cycle) pair, sum(new item rows) equals the legacy amount exactly.
-- ---------------------------------------------------------------------------

insert into app_finance.credit_card_statement_item_allocations (
  user_id, payment_transaction_id, statement_item_id, amount_minor,
  allocation_origin, created_at
)
select
  pay.user_id,
  pay.payment_transaction_id,
  item.statement_item_id,
  least(pay.pay_end, item.item_end)
    - greatest(pay.pay_start, item.item_start) as amount_minor,
  'legacy_inferred',
  pay.created_at
from (
  select sa.user_id, sa.payment_transaction_id, sa.cycle_id, sa.created_at,
    sum(sa.amount_minor) over w - sa.amount_minor as pay_start,
    sum(sa.amount_minor) over w as pay_end
  from app_finance.credit_card_statement_allocations sa
  join app_finance.financial_transactions t
    on t.id = sa.payment_transaction_id
  window w as (
    partition by sa.cycle_id
    order by t.occurred_on, t.created_at, t.id
    rows between unbounded preceding and current row
  )
) pay
join (
  select si.id as statement_item_id, si.cycle_id,
    sum(si.amount_minor) over w - si.amount_minor as item_start,
    sum(si.amount_minor) over w as item_end
  from app_finance.credit_card_statement_items si
  join app_finance.financial_transactions t on t.id = si.transaction_id
  window w as (
    partition by si.cycle_id
    order by t.occurred_on, si.transaction_id
    rows between unbounded preceding and current row
  )
) item
  on item.cycle_id = pay.cycle_id
  and least(pay.pay_end, item.item_end)
    > greatest(pay.pay_start, item.item_start)
where pay.cycle_id in (
  select sa.cycle_id
  from app_finance.credit_card_statement_allocations sa
  group by sa.cycle_id
  having sum(sa.amount_minor) <= coalesce((
    select sum(si.amount_minor)
    from app_finance.credit_card_statement_items si
    where si.cycle_id = sa.cycle_id
  ), 0)
)
and not exists (
  select 1 from app_finance.credit_card_statement_item_allocations existing
  where existing.payment_transaction_id = pay.payment_transaction_id
);

-- Backfill safety net: every inferred (payment, cycle) total must equal its
-- legacy aggregate exactly. Abort the migration otherwise.
do $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from app_finance.credit_card_statement_allocations sa
  join app_finance.credit_card_statement_items si
    on si.cycle_id = sa.cycle_id
  join app_finance.credit_card_statement_item_allocations ia
    on ia.statement_item_id = si.id
    and ia.payment_transaction_id = sa.payment_transaction_id
  group by sa.payment_transaction_id, sa.cycle_id, sa.amount_minor
  having sum(ia.amount_minor) <> sa.amount_minor
  limit 1;
  if v_bad is not null then
    raise exception
      'backfill_mismatch: inferred item allocations diverge from legacy totals';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Canonical per-item payment status view
-- ---------------------------------------------------------------------------

drop view if exists app_finance.facility_payment_allocations;
drop view if exists app_finance.credit_card_statement_item_statuses;
create view app_finance.credit_card_statement_item_statuses
with (security_invoker = on) as
  select
    si.id as statement_item_id,
    si.user_id,
    sc.account_id,
    si.cycle_id,
    sc.due_on as cycle_due_on,
    sc.cycle_close,
    si.transaction_id,
    si.amount_minor,
    coalesce(al.paid_minor, 0)::bigint as paid_minor,
    greatest(si.amount_minor - coalesce(al.paid_minor, 0), 0)::bigint
      as remaining_minor,
    case
      when coalesce(al.paid_minor, 0) >= si.amount_minor then 'paid'
      when coalesce(al.paid_minor, 0) > 0 then 'partially_paid'
      else 'unpaid'
    end as payment_status,
    case
      when fr.fee_type = 'purchase_interest' then 'purchase_interest'
      when fee.id is not null then 'fee_charge'
      when exists (
        select 1 from app_finance.installment_dues d
        where d.interest_transaction_id = t.id
      ) then 'installment_interest'
      else 'ordinary_expense'
    end as activity_kind,
    fr.fee_type,
    t.title,
    t.category_id,
    t.occurred_on,
    t.currency_code
  from app_finance.credit_card_statement_items si
  join app_finance.credit_card_statement_cycles sc on sc.id = si.cycle_id
  join app_finance.financial_transactions t on t.id = si.transaction_id
  left join app_finance.credit_card_fee_charges fee
    on fee.transaction_id = si.transaction_id
  left join app_finance.credit_card_fee_rules fr on fr.id = fee.rule_id
  left join lateral (
    select sum(ia.amount_minor)::bigint as paid_minor
    from app_finance.credit_card_statement_item_allocations ia
    where ia.statement_item_id = si.id
  ) al on true;

comment on view app_finance.credit_card_statement_item_statuses is
  'Canonical paid state per statement item, aggregated from item-level '
  'allocations. Clients must read this instead of reconstructing state from '
  'raw allocation rows. Legacy cycles that could not be backfilled report '
  'their items as unpaid here; cycle-level truth stays in '
  'credit_card_statement_summaries.';

-- ---------------------------------------------------------------------------
-- 4. Statement summaries gain minimum_paid / minimum_remaining
--
-- Column list, order, and types of the existing view are preserved;
-- minimum_paid_minor and minimum_remaining_minor are appended. The minimum
-- formula moves into the `md` lateral so both the legacy column and the new
-- remaining column use one expression.
-- ---------------------------------------------------------------------------

create or replace view app_finance.credit_card_statement_summaries
with (security_invoker = on) as
  select
    c.id, c.user_id, c.account_id, a.currency_code,
    c.cycle_start, c.cycle_close, c.due_on,
    coalesce(i.card_charges_minor, 0)::bigint as charges_minor,
    (coalesce(pa.statement_paid_minor, 0)
      + coalesce(di.installment_paid_minor, 0))::bigint as paid_minor,
    greatest(coalesce(i.card_charges_minor, 0)
      - coalesce(pa.statement_paid_minor, 0), 0)::bigint as remaining_minor,
    md.minimum_due_minor,
    case
      when coalesce(i.card_charges_minor, 0) = 0 then 'paid'
      when coalesce(pa.statement_paid_minor, 0)
          + coalesce(di.installment_paid_minor, 0)
        >= coalesce(i.card_charges_minor, 0) then 'paid'
      when current_date <= c.cycle_close then 'open'
      when c.due_on < current_date then 'overdue'
      when c.due_on = current_date then 'due_today'
      when coalesce(pa.statement_paid_minor, 0)
          + coalesce(di.installment_paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as cycle_status,
    coalesce(i.ordinary_statement_charges_minor, 0)::bigint
      as ordinary_statement_charges_minor,
    coalesce(i.fee_charges_minor, 0)::bigint as fee_charges_minor,
    coalesce(di.installment_due_minor, 0)::bigint as installment_due_minor,
    (coalesce(i.ordinary_statement_charges_minor, 0)
      + case when s.min_payment_include_bank_fees
        then coalesce(i.fee_charges_minor, 0) else 0 end)::bigint
      as revolving_base_minor,
    (coalesce(i.card_charges_minor, 0)
      + coalesce(di.installment_due_minor, 0))::bigint
      as total_statement_due_minor,
    coalesce(i.card_charges_minor, 0)::bigint as card_charges_minor,
    coalesce(pa.statement_paid_minor, 0)::bigint as card_charges_paid_minor,
    coalesce(di.installment_paid_minor, 0)::bigint
      as installment_paid_minor,
    (coalesce(pa.statement_paid_minor, 0)
      + coalesce(di.installment_paid_minor, 0))::bigint as total_paid_minor,
    greatest(coalesce(i.card_charges_minor, 0)
      + coalesce(di.installment_due_minor, 0)
      - coalesce(pa.statement_paid_minor, 0)
      - coalesce(di.installment_paid_minor, 0), 0)::bigint
      as total_remaining_minor,
    case
      when coalesce(i.card_charges_minor, 0)
          + coalesce(di.installment_due_minor, 0) = 0 then 'paid'
      when coalesce(pa.statement_paid_minor, 0)
          + coalesce(di.installment_paid_minor, 0)
        >= coalesce(i.card_charges_minor, 0)
          + coalesce(di.installment_due_minor, 0) then 'paid'
      when current_date <= c.cycle_close then 'open'
      when c.due_on < current_date then 'overdue'
      when c.due_on = current_date then 'due_today'
      when coalesce(pa.statement_paid_minor, 0)
          + coalesce(di.installment_paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as obligation_status,
    least(md.minimum_due_minor,
      coalesce(pa.statement_paid_minor, 0)
        + coalesce(di.installment_paid_minor, 0))::bigint
      as minimum_paid_minor,
    least(
      greatest(md.minimum_due_minor
        - coalesce(pa.statement_paid_minor, 0)
        - coalesce(di.installment_paid_minor, 0), 0),
      greatest(coalesce(i.card_charges_minor, 0)
        + coalesce(di.installment_due_minor, 0)
        - coalesce(pa.statement_paid_minor, 0)
        - coalesce(di.installment_paid_minor, 0), 0)
    )::bigint as minimum_remaining_minor
  from app_finance.credit_card_statement_cycles c
  join app_finance.accounts a on a.id = c.account_id
  join app_finance.credit_facility_settings s on s.account_id = c.account_id
  left join lateral (
    select
      sum(si.amount_minor)::bigint as card_charges_minor,
      (sum(si.amount_minor) filter (where fc.id is null))::bigint
        as ordinary_statement_charges_minor,
      (sum(si.amount_minor) filter (where fc.id is not null))::bigint
        as fee_charges_minor
    from app_finance.credit_card_statement_items si
    left join app_finance.credit_card_fee_charges fc
      on fc.transaction_id = si.transaction_id
    where si.cycle_id = c.id
  ) i on true
  left join lateral (
    select sum(x.amount_minor)::bigint as statement_paid_minor
    from app_finance.credit_card_statement_allocations x
    where x.cycle_id = c.id
  ) pa on true
  left join lateral (
    select
      sum(ds.amount_minor)::bigint as installment_due_minor,
      sum(ds.paid_minor)::bigint as installment_paid_minor
    from app_finance.installment_due_statuses ds
    where ds.account_id = c.account_id and ds.due_on = c.due_on
      and ds.plan_status <> 'cancelled'
  ) di on true
  cross join lateral (
    select (case
      when s.min_payment_percentage_basis = 'revolving_noninstallment' then
        coalesce(i.ordinary_statement_charges_minor, 0)
          + case when s.min_payment_include_bank_fees
            then coalesce(i.fee_charges_minor, 0) else 0 end
      else coalesce(i.card_charges_minor, 0)
    end * coalesce(s.min_payment_basis_points, 0) / 10000)::bigint
      as percentage_minor
  ) mp
  left join lateral (
    select (
      coalesce(sum(greatest(coalesce(oi.card_charges_minor, 0)
        - coalesce(op.statement_paid_minor, 0), 0)), 0)
      + coalesce((select sum(ds.remaining_minor)
        from app_finance.installment_due_statuses ds
        where ds.account_id = c.account_id and ds.due_on < c.due_on
          and ds.plan_status = 'active'), 0)
    )::bigint as overdue_minor
    from app_finance.credit_card_statement_cycles oc
    left join lateral (
      select sum(si.amount_minor)::bigint as card_charges_minor
      from app_finance.credit_card_statement_items si
      where si.cycle_id = oc.id
    ) oi on true
    left join lateral (
      select sum(x.amount_minor)::bigint as statement_paid_minor
      from app_finance.credit_card_statement_allocations x
      where x.cycle_id = oc.id
    ) op on true
    where oc.account_id = c.account_id and oc.due_on < c.due_on
      and oc.due_on < current_date
  ) od on true
  cross join lateral (
    select least(
      greatest(
        case
          when s.min_payment_method = 'fixed' then
            coalesce(s.min_payment_fixed_minor, 0)
          when s.min_payment_method = 'percent' then
            mp.percentage_minor
              + case when s.min_payment_include_installment_dues
                then coalesce(di.installment_due_minor, 0) else 0 end
          when s.min_payment_method = 'greater_of' then
            greatest(coalesce(s.min_payment_fixed_minor, 0),
              mp.percentage_minor)
              + case when s.min_payment_include_installment_dues
                then coalesce(di.installment_due_minor, 0) else 0 end
          else coalesce(i.card_charges_minor, 0)
            + case when s.min_payment_include_installment_dues
              then coalesce(di.installment_due_minor, 0) else 0 end
        end,
        coalesce(s.min_payment_fixed_floor_minor, 0)
      ) + case when s.min_payment_include_overdue
        then coalesce(od.overdue_minor, 0) else 0 end,
      coalesce(i.card_charges_minor, 0) + coalesce(di.installment_due_minor, 0)
        + case when s.min_payment_include_overdue
          then coalesce(od.overdue_minor, 0) else 0 end
    )::bigint as minimum_due_minor
  ) md;

comment on column app_finance.credit_card_statement_summaries.charges_minor is
  'Compatibility field containing card statement items only. Use '
  'card_charges_minor or total_statement_due_minor for explicit semantics.';
comment on column
  app_finance.credit_card_statement_summaries.minimum_paid_minor is
  'Portion of the configured minimum already satisfied. Qualifying payments '
  'are exactly the ones in total_paid_minor: allocations to this cycle''s '
  'card charges plus this cycle''s installment dues. Allocations parked on '
  'other cycles or future dues never satisfy this cycle''s minimum.';
comment on column
  app_finance.credit_card_statement_summaries.minimum_remaining_minor is
  'max(minimum_due_minor - qualifying payments, 0), additionally capped at '
  'total_remaining_minor so a nearly settled statement never asks for more '
  'than what is left.';

-- ---------------------------------------------------------------------------
-- 5. Due Breakdown DTO
--
-- One authoritative payload for the Pay screen checklist and the persistent
-- Due Breakdown. Scope rules:
--   * credit cards: every closed unpaid statement (cycle_close < as-of and
--     total_remaining > 0) — the exact set pay_credit_facility considers
--     payable — plus a settled statement whose due date has not passed yet,
--     so a freshly paid due stays visible with its checkmarks;
--   * installment dues: dues on those statements' due dates (paid ones stay
--     visible), plus any other unpaid due on or before the as-of date;
--   * when nothing is currently payable, the earliest upcoming unpaid due
--     date is exposed with scope 'next_due' so the Next-installment preset
--     keeps working — future dues beyond that never appear;
--   * BNPL: installment dues only, same scoping, no statement items and no
--     minimum payment (none is modelled for BNPL).
-- Unbilled/open-cycle balance is reported as additional_balance_minor and
-- never disguised as due components.
-- ---------------------------------------------------------------------------

create or replace function app_finance.facility_due_breakdown(
  p_account_id uuid,
  p_as_of date default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
  v_as_of date := coalesce(p_as_of, current_date);
  v_outstanding bigint;
  v_cycles jsonb;
  v_components jsonb;
  v_cycle_due_dates date[];
  v_next_due_on date;
  v_minimum_due bigint;
  v_minimum_remaining bigint;
  v_include_overdue boolean;
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

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);

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
    array_agg(distinct y.due_on)
  into v_cycles, v_cycle_due_dates
  from app_finance.credit_card_statement_summaries y
  where y.user_id = v_user_id and y.account_id = p_account_id
    and y.cycle_close < v_as_of
    and (y.total_remaining_minor > 0
      or (y.due_on >= v_as_of and y.total_statement_due_minor > 0));

  select s.min_payment_include_overdue into v_include_overdue
  from app_finance.credit_facility_settings s
  where s.account_id = p_account_id and s.user_id = v_user_id;

  -- Minimum across eligible statements. With include_overdue the newest
  -- statement's minimum already contains every older remainder, so summing
  -- would double count; take the newest one instead.
  if v_account.account_type = 'credit_card' then
    if coalesce(v_include_overdue, false) then
      select y.minimum_due_minor, y.minimum_remaining_minor
      into v_minimum_due, v_minimum_remaining
      from app_finance.credit_card_statement_summaries y
      where y.user_id = v_user_id and y.account_id = p_account_id
        and y.cycle_close < v_as_of
        and (y.total_remaining_minor > 0
          or (y.due_on >= v_as_of and y.total_statement_due_minor > 0))
      order by y.due_on desc, y.cycle_close desc
      limit 1;
    else
      select sum(y.minimum_due_minor)::bigint,
        sum(y.minimum_remaining_minor)::bigint
      into v_minimum_due, v_minimum_remaining
      from app_finance.credit_card_statement_summaries y
      where y.user_id = v_user_id and y.account_id = p_account_id
        and y.cycle_close < v_as_of
        and (y.total_remaining_minor > 0
          or (y.due_on >= v_as_of and y.total_statement_due_minor > 0));
    end if;
  end if;

  with due_components as (
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
      s.amount_minor,
      s.paid_minor,
      s.remaining_minor,
      case
        when s.remaining_minor = 0 then 'paid'
        when s.paid_minor > 0 then 'partially_paid'
        else 'unpaid'
      end as payment_status,
      case when s.due_on <= v_as_of
          or s.due_on = any(coalesce(v_cycle_due_dates, array[]::date[]))
        then 'current' else 'next_due' end as scope,
      s.due_on as sort_on
    from app_finance.installment_due_statuses s
    join app_finance.installment_plans p on p.id = s.plan_id
    where s.user_id = v_user_id and s.account_id = p_account_id
      and s.plan_status = 'active'
      and not s.is_presettled
      and (
        (s.remaining_minor > 0 and s.due_on <= v_as_of)
        or s.due_on = any(coalesce(v_cycle_due_dates, array[]::date[]))
      )
  ),
  next_due as (
    select min(s.due_on) as due_on
    from app_finance.installment_due_statuses s
    where s.user_id = v_user_id and s.account_id = p_account_id
      and s.plan_status = 'active' and s.remaining_minor > 0
      and s.due_on > v_as_of
      and not exists (select 1 from due_components)
  ),
  next_due_components as (
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
      s.amount_minor,
      s.paid_minor,
      s.remaining_minor,
      case
        when s.remaining_minor = 0 then 'paid'
        when s.paid_minor > 0 then 'partially_paid'
        else 'unpaid'
      end as payment_status,
      'next_due' as scope,
      s.due_on as sort_on
    from app_finance.installment_due_statuses s
    join app_finance.installment_plans p on p.id = s.plan_id
    join next_due n on n.due_on = s.due_on
    where s.user_id = v_user_id and s.account_id = p_account_id
      and s.plan_status = 'active' and s.remaining_minor > 0
  ),
  item_components as (
    select
      'statement_item' as component_type,
      st.statement_item_id as component_id,
      null::uuid as plan_id,
      st.cycle_id,
      st.transaction_id,
      st.title,
      st.activity_kind,
      st.fee_type::text,
      null::integer as sequence_number,
      null::integer as installment_count,
      st.occurred_on as component_on,
      st.amount_minor,
      st.paid_minor,
      st.remaining_minor,
      st.payment_status,
      'current' as scope,
      st.cycle_due_on as sort_on
    from app_finance.credit_card_statement_item_statuses st
    where st.user_id = v_user_id and st.account_id = p_account_id
      and st.cycle_id in (
        select (c ->> 'cycle_id')::uuid
        from jsonb_array_elements(coalesce(v_cycles, '[]'::jsonb)) c
      )
  ),
  all_components as (
    select * from due_components
    union all
    select * from next_due_components
    union all
    select * from item_components
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
      'amount_minor', amount_minor,
      'paid_minor', paid_minor,
      'remaining_minor', remaining_minor,
      'payment_status', payment_status,
      'scope', scope
    ) order by
      case when scope = 'current' then 0 else 1 end,
      case when component_type = 'installment_due' then 0 else 1 end,
      case when activity_kind in
        ('fee_charge', 'purchase_interest', 'installment_interest')
        then 0 else 1 end,
      sort_on, component_on, component_id), '[]'::jsonb),
    coalesce(sum(amount_minor) filter (where scope = 'current'), 0)::bigint,
    coalesce(sum(paid_minor) filter (where scope = 'current'), 0)::bigint,
    coalesce(sum(remaining_minor) filter (where scope = 'current'), 0)::bigint
  into v_components, v_total_due, v_paid, v_remaining
  from all_components;

  return jsonb_build_object(
    'account_id', p_account_id,
    'account_type', v_account.account_type,
    'currency_code', v_account.currency_code,
    'as_of', v_as_of,
    'outstanding_minor', v_outstanding,
    'total_due_minor', v_total_due,
    'paid_minor', v_paid,
    'remaining_minor', v_remaining,
    'additional_balance_minor', greatest(v_outstanding - v_remaining
      - coalesce((
        select sum((c ->> 'remaining_minor')::bigint)
        from jsonb_array_elements(v_components) c
        where c ->> 'scope' = 'next_due'
      ), 0), 0),
    'minimum_due_minor', v_minimum_due,
    'minimum_remaining_minor', v_minimum_remaining,
    'cycles', coalesce(v_cycles, '[]'::jsonb),
    'components', v_components
  );
end;
$$;

revoke execute on function app_finance.facility_due_breakdown(uuid, date)
  from public, anon;
grant execute on function app_finance.facility_due_breakdown(uuid, date)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5b. Legacy waterfall keeps item detail in sync
--
-- Old clients keep calling pay_credit_facility, whose automatic waterfall
-- writes cycle-level statement allocations. So that item-level state stays
-- truthful for those payments too, the waterfall now also records the item
-- split it implies — the same deterministic oldest-first order, marked
-- allocation_origin = 'system'. The cycle aggregate remains exactly the sum
-- of the item rows whenever the cycle's item state is determinate; on a
-- legacy cycle that could not be backfilled the helper allocates at most
-- each item's remaining and leaves the rest at cycle level only.
-- ---------------------------------------------------------------------------

create or replace function app_private.allocate_statement_items_for_cycle(
  p_user_id uuid,
  p_payment_transaction_id uuid,
  p_cycle_id uuid,
  p_amount_minor bigint,
  p_origin text default 'system'
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_left bigint := p_amount_minor;
  v_item record;
  v_take bigint;
begin
  for v_item in
    select st.statement_item_id, st.remaining_minor
    from app_finance.credit_card_statement_item_statuses st
    where st.cycle_id = p_cycle_id and st.user_id = p_user_id
      and st.remaining_minor > 0
    order by st.occurred_on, st.transaction_id
  loop
    exit when v_left <= 0;
    v_take := least(v_left, v_item.remaining_minor);
    insert into app_finance.credit_card_statement_item_allocations (
      user_id, payment_transaction_id, statement_item_id, amount_minor,
      allocation_origin
    ) values (
      p_user_id, p_payment_transaction_id, v_item.statement_item_id,
      v_take, p_origin
    );
    v_left := v_left - v_take;
  end loop;
end;
$$;

-- Callable by the invoker-security payment RPCs; a direct client call is
-- still inert because the protect trigger rejects writes outside them.
revoke execute on function app_private.allocate_statement_items_for_cycle(
  uuid, uuid, uuid, bigint, text
) from public, anon;
grant execute on function app_private.allocate_statement_items_for_cycle(
  uuid, uuid, uuid, bigint, text
) to authenticated, service_role;

create or replace function app_finance.pay_credit_facility(
  p_account_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_paid_on date,
  p_allocations jsonb default null,
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
  v_left bigint;
  v_due record;
  v_obligation record;
  v_allocation jsonb;
  v_alloc_amount bigint;
  v_alloc_total bigint := 0;
  v_take bigint;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_payment_id is not null then
    select id into v_tx_id from app_finance.financial_transactions
    where id = p_payment_id and user_id = v_user_id;
    if v_tx_id is not null then return v_tx_id; end if;
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
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
  v_left := p_amount_minor;

  if p_allocations is not null then
    if jsonb_typeof(p_allocations) <> 'array' then
      raise exception 'invalid_allocations: expected an array';
    end if;
    for v_allocation in select * from jsonb_array_elements(p_allocations)
    loop
      v_alloc_amount := (v_allocation ->> 'amount_minor')::bigint;
      select s.id, s.remaining_minor into v_due
      from app_finance.installment_due_statuses s
      where s.id = (v_allocation ->> 'due_id')::uuid
        and s.user_id = v_user_id and s.account_id = p_account_id
        and s.plan_status = 'active';
      if v_due is null then raise exception 'not_found: installment due'; end if;
      if v_alloc_amount <= 0 or v_alloc_amount > v_due.remaining_minor then
        raise exception 'allocation_exceeds_due';
      end if;
      v_alloc_total := v_alloc_total + v_alloc_amount;
      if v_alloc_total > p_amount_minor then
        raise exception 'allocation_exceeds_payment';
      end if;
      insert into app_finance.installment_payment_allocations (
        user_id, payment_transaction_id, due_id, amount_minor
      ) values (v_user_id, v_tx_id, v_due.id, v_alloc_amount);
    end loop;
  else
    for v_obligation in
      select 'statement'::text as kind, y.id,
        greatest(y.card_charges_minor - y.card_charges_paid_minor, 0)::bigint
          as remaining_minor,
        y.due_on, 0 as kind_order
      from app_finance.credit_card_statement_summaries y
      where y.user_id = v_user_id and y.account_id = p_account_id
        and y.card_charges_minor > y.card_charges_paid_minor
        and y.cycle_close < p_paid_on
      union all
      select 'installment', s.id, s.remaining_minor, s.due_on, 1
      from app_finance.installment_due_statuses s
      where s.user_id = v_user_id and s.account_id = p_account_id
        and s.plan_status = 'active' and s.remaining_minor > 0
      order by due_on, kind_order, id
    loop
      exit when v_left <= 0;
      v_take := least(v_left, v_obligation.remaining_minor);
      if v_obligation.kind = 'statement' then
        insert into app_finance.credit_card_statement_allocations (
          user_id, payment_transaction_id, cycle_id, amount_minor
        ) values (v_user_id, v_tx_id, v_obligation.id, v_take);
        perform app_private.allocate_statement_items_for_cycle(
          v_user_id, v_tx_id, v_obligation.id, v_take
        );
      else
        insert into app_finance.installment_payment_allocations (
          user_id, payment_transaction_id, due_id, amount_minor
        ) values (v_user_id, v_tx_id, v_obligation.id, v_take);
      end if;
      v_left := v_left - v_take;
    end loop;
  end if;

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

-- ---------------------------------------------------------------------------
-- 6. Typed v2 payment RPC
--
-- p_allocations is a mandatory JSON array of
--   {"type": "installment_due" | "statement_item" | "facility_balance",
--    "id": uuid, "amount_minor": bigint}
-- whose amounts must total exactly p_amount_minor. Targets must be currently
-- payable (same scope facility_due_breakdown exposes). 'facility_balance'
-- (at most one, id = the facility account) explicitly labels money paid
-- against non-current-due outstanding balance; it is derivable as
-- payment - sum(item/due rows), so no row is stored for it.
--
-- The facility account row lock is the serialization point for every
-- allocation write on a facility, so two concurrent payments cannot
-- overpay a component: the second waits, then revalidates against remaining
-- amounts that already include the first payment's allocations.
-- ---------------------------------------------------------------------------

create or replace function app_finance.pay_credit_facility_v2(
  p_account_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_paid_on date,
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
  v_balance_entries integer := 0;
  v_seen_targets text[] := array[]::text[];
  v_target_key text;
  v_due record;
  v_item record;
  v_next_due_on date;
  v_cycle_due_dates date[];
  v_has_current boolean;
  v_existing_amount bigint;
  v_existing jsonb;
  v_requested jsonb;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
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
        where a ->> 'type' <> 'facility_balance'
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

  perform app_finance.materialize_installment_interest(p_paid_on, p_account_id);
  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if p_amount_minor > v_outstanding then
    raise exception 'overpayment_rejected: payment exceeds amount owed';
  end if;

  -- Due dates of currently payable statements (same rule as the waterfall
  -- and facility_due_breakdown: closed before the payment date).
  select array_agg(distinct y.due_on) into v_cycle_due_dates
  from app_finance.credit_card_statement_summaries y
  where y.user_id = v_user_id and y.account_id = p_account_id
    and y.cycle_close < p_paid_on;
  v_has_current := exists (
    select 1 from app_finance.installment_due_statuses s
    where s.user_id = v_user_id and s.account_id = p_account_id
      and s.plan_status = 'active' and s.remaining_minor > 0
      and (s.due_on <= p_paid_on
        or s.due_on = any(coalesce(v_cycle_due_dates, array[]::date[])))
  ) or exists (
    select 1 from app_finance.credit_card_statement_summaries y
    where y.user_id = v_user_id and y.account_id = p_account_id
      and y.cycle_close < p_paid_on and y.total_remaining_minor > 0
  );
  select min(s.due_on) into v_next_due_on
  from app_finance.installment_due_statuses s
  where s.user_id = v_user_id and s.account_id = p_account_id
    and s.plan_status = 'active' and s.remaining_minor > 0
    and s.due_on > p_paid_on;

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
      or v_type not in
        ('installment_due', 'statement_item', 'facility_balance') then
      raise exception 'invalid_allocations: unknown allocation type';
    end if;
    begin
      v_alloc_amount := (v_allocation ->> 'amount_minor')::bigint;
      v_target_id := case when v_type = 'facility_balance'
        then p_account_id else (v_allocation ->> 'id')::uuid end;
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
        and s.plan_status = 'active';
      if v_due is null then raise exception 'not_found: installment due'; end if;
      if v_due.remaining_minor <= 0 then
        raise exception 'allocation_target_paid: installment due settled';
      end if;
      if v_alloc_amount > v_due.remaining_minor then
        raise exception 'allocation_exceeds_due';
      end if;
      -- Current dues, dues on a payable statement, or the single next
      -- upcoming due date when nothing is currently payable. Anything
      -- further in the future is early settlement, not this flow.
      if not (v_due.due_on <= p_paid_on
        or v_due.due_on = any(coalesce(v_cycle_due_dates, array[]::date[]))
        or (not v_has_current and v_due.due_on = v_next_due_on)) then
        raise exception
          'allocation_not_payable: installment due is not currently payable';
      end if;
      insert into app_finance.installment_payment_allocations (
        user_id, payment_transaction_id, due_id, amount_minor
      ) values (v_user_id, v_tx_id, v_due.id, v_alloc_amount);
    elsif v_type = 'statement_item' then
      select st.statement_item_id, st.remaining_minor into v_item
      from app_finance.credit_card_statement_item_statuses st
      where st.statement_item_id = v_target_id
        and st.user_id = v_user_id and st.account_id = p_account_id
        and st.cycle_close < p_paid_on;
      if v_item is null then raise exception 'not_found: statement item'; end if;
      if v_item.remaining_minor <= 0 then
        raise exception 'allocation_target_paid: statement item settled';
      end if;
      if v_alloc_amount > v_item.remaining_minor then
        raise exception 'allocation_exceeds_item';
      end if;
      insert into app_finance.credit_card_statement_item_allocations (
        user_id, payment_transaction_id, statement_item_id, amount_minor
      ) values (v_user_id, v_tx_id, v_item.statement_item_id, v_alloc_amount);
    else
      v_balance_entries := v_balance_entries + 1;
      if v_balance_entries > 1 then
        raise exception
          'invalid_allocations: multiple facility balance entries';
      end if;
    end if;
  end loop;

  if v_alloc_total <> p_amount_minor then
    raise exception
      'allocation_total_mismatch: allocations must equal the payment amount';
  end if;

  -- Cycle-level compatibility aggregates: exactly the per-cycle sums of the
  -- item rows written above, so legacy statement consumers keep working and
  -- the two levels can never diverge.
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

revoke execute on function app_finance.pay_credit_facility_v2(
  uuid, uuid, bigint, date, jsonb, text, uuid
) from public, anon;
grant execute on function app_finance.pay_credit_facility_v2(
  uuid, uuid, bigint, date, jsonb, text, uuid
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Persisted "Applied to" detail for payment history
--
-- Item-level rows where they exist; a payment's legacy cycle aggregate is
-- surfaced as one 'statement_cycle' row only when that payment has no item
-- rows (an unmapped legacy payment) — never both, so amounts always total
-- the payment's allocated amount exactly once.
-- ---------------------------------------------------------------------------

drop view if exists app_finance.facility_payment_allocations;
create view app_finance.facility_payment_allocations
with (security_invoker = on) as
  select
    pa.payment_transaction_id,
    pa.user_id,
    s.account_id,
    'installment_due' as component_type,
    pa.due_id as component_id,
    s.plan_title as title,
    null::text as fee_type,
    'installment_due' as activity_kind,
    s.sequence_number,
    s.due_on as detail_on,
    pa.amount_minor,
    s.currency_code,
    'user_selected' as allocation_origin,
    pa.created_at
  from app_finance.installment_payment_allocations pa
  join app_finance.installment_due_statuses s on s.id = pa.due_id
  union all
  select
    ia.payment_transaction_id,
    ia.user_id,
    st.account_id,
    'statement_item',
    ia.statement_item_id,
    st.title,
    st.fee_type::text,
    st.activity_kind,
    null::integer,
    st.occurred_on,
    ia.amount_minor,
    st.currency_code,
    ia.allocation_origin,
    ia.created_at
  from app_finance.credit_card_statement_item_allocations ia
  join app_finance.credit_card_statement_item_statuses st
    on st.statement_item_id = ia.statement_item_id
  union all
  select
    sa.payment_transaction_id,
    sa.user_id,
    sc.account_id,
    'statement_cycle',
    sa.cycle_id,
    null::text,
    null::text,
    'statement_cycle',
    null::integer,
    sc.due_on,
    sa.amount_minor,
    a.currency_code,
    'legacy_inferred',
    sa.created_at
  from app_finance.credit_card_statement_allocations sa
  join app_finance.credit_card_statement_cycles sc on sc.id = sa.cycle_id
  join app_finance.accounts a on a.id = sc.account_id
  where not exists (
    select 1
    from app_finance.credit_card_statement_item_allocations ia
    join app_finance.credit_card_statement_items si
      on si.id = ia.statement_item_id
    where ia.payment_transaction_id = sa.payment_transaction_id
      and si.cycle_id = sa.cycle_id
  );

grant select on app_finance.credit_card_statement_item_statuses,
  app_finance.facility_payment_allocations to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. Reversal also removes item-level allocations
-- ---------------------------------------------------------------------------

create or replace function app_finance.reverse_facility_payment(
  p_transaction_id uuid
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_payment record;
  v_reversal_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  select t.id, t.amount_minor, t.currency_code, t.occurred_on,
      t.source_account_id, t.destination_account_id
    into v_payment
    from app_finance.financial_transactions t
    join app_finance.accounts a on a.id = t.destination_account_id
    where t.id = p_transaction_id and t.user_id = v_user_id
      and t.transaction_kind = 'transfer'
      and app_finance.account_role(a.account_type) = 'liability'
    for update of t;
  if v_payment is null then
    raise exception 'not_found: facility payment';
  end if;
  if exists (
    select 1 from app_finance.financial_transactions r
    where r.facility_reversal_of_id = p_transaction_id
  ) then
    raise exception 'already_reversed: this payment has a reversal';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  delete from app_finance.installment_payment_allocations
    where payment_transaction_id = p_transaction_id and user_id = v_user_id;
  delete from app_finance.credit_card_statement_item_allocations
    where payment_transaction_id = p_transaction_id and user_id = v_user_id;
  delete from app_finance.credit_card_statement_allocations
    where payment_transaction_id = p_transaction_id and user_id = v_user_id;

  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, facility_reversal_of_id
  ) values (
    v_user_id, 'transfer', v_payment.occurred_on, v_payment.amount_minor,
    v_payment.currency_code, v_payment.destination_account_id,
    v_payment.source_account_id, p_transaction_id
  )
  returning id into v_reversal_id;

  update app_finance.installment_plans p
    set status = 'active'
    where p.user_id = v_user_id
      and p.status = 'completed'
      and exists (
        select 1 from app_finance.installment_due_statuses s
        where s.plan_id = p.id and s.remaining_minor > 0
      );

  perform set_config('app_finance.facility_internal', '', true);
  return v_reversal_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Account deletion learns the new table
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
  perform set_config('app_finance.network_internal', 'on', true);
  perform set_config('app_finance.responsibility_internal', 'on', true);

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

  update app_finance.installment_responsibility_links
    set removed_at = now()
    where responsible_user_id = p_user_id and removed_at is null;

  delete from app_finance.installment_reimbursements
    where user_id = p_user_id;
  delete from app_finance.installment_responsibility_links
    where user_id = p_user_id;

  delete from app_finance.network_transfers
    where status = 'pending'
      and (sender_user_id = p_user_id or receiver_user_id = p_user_id);
  delete from app_finance.network_connections
    where user_a_id = p_user_id or user_b_id = p_user_id;
  delete from app_finance.network_add_requests
    where requester_user_id = p_user_id or recipient_user_id = p_user_id;

  delete from app_finance.recurring_occurrences where user_id = p_user_id;
  delete from app_finance.recurring_rules where user_id = p_user_id;
  delete from app_finance.installment_payment_allocations
    where user_id = p_user_id;
  delete from app_finance.credit_card_statement_item_allocations
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
  perform set_config('app_finance.network_internal', '', true);
  perform set_config('app_finance.responsibility_internal', '', true);
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

notify pgrst, 'reload schema';
