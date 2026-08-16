-- Ordinary BNPL purchases become first-class payable obligations.
--
-- A BNPL purchase already booked one expense and raised facility outstanding,
-- but unlike a credit-card charge (which becomes a statement item) or a
-- financed purchase (which becomes installment dues) it had no due entity.
-- Every surface therefore had to guess: Home summed raw BNPL expenses as if
-- all were unpaid and invented a due-today obligation, the facility summary
-- could not name a next due date, and the Pay screen could only offer the
-- anonymous facility balance. Paying one never marked anything paid.
--
-- This migration gives the ordinary purchase the same lifecycle the other two
-- already have:
--
--   financial_transaction -> bnpl_purchase_obligation -> allocations -> paid
--
-- The transaction stays the ledger truth; the obligation carries the due and
-- payment state, derived from allocation rows rather than mutable counters.
-- A plan-controlled purchase never gets an obligation, so a financed purchase
-- is never owed twice.

-- ---------------------------------------------------------------------------
-- 1. The generic BNPL due-date rule
--
-- Until provider-specific billing cycles exist, an ordinary BNPL purchase is
-- owed on the facility's configured default_due_day: the first occurrence of
-- that day strictly after the purchase date, clamped to the length of the
-- target month. One function owns this so no RPC re-derives the date.
-- ---------------------------------------------------------------------------

create or replace function app_finance.bnpl_purchase_due_on(
  p_due_day smallint,
  p_purchased_on date
)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_day integer := greatest(least(coalesce(p_due_day, 1), 31), 1);
  v_month_start date := date_trunc('month', p_purchased_on)::date;
  v_last_day integer;
  v_candidate date;
begin
  v_last_day := extract(
    day from (v_month_start + interval '1 month - 1 day')
  )::integer;
  v_candidate := v_month_start + (least(v_day, v_last_day) - 1);
  -- Strictly after: buying on the due day itself is billed next month.
  if v_candidate > p_purchased_on then
    return v_candidate;
  end if;
  v_month_start := (v_month_start + interval '1 month')::date;
  v_last_day := extract(
    day from (v_month_start + interval '1 month - 1 day')
  )::integer;
  return v_month_start + (least(v_day, v_last_day) - 1);
end;
$$;

comment on function app_finance.bnpl_purchase_due_on(smallint, date) is
  'Due date of an ordinary BNPL purchase: the first occurrence of the '
  'facility default_due_day strictly after the purchase date, clamped to the '
  'target month length (day 31 becomes Feb 28/29). Installment schedules and '
  'credit-card statement cycles are unaffected.';

revoke execute on function app_finance.bnpl_purchase_due_on(smallint, date)
  from public, anon;
grant execute on function app_finance.bnpl_purchase_due_on(smallint, date)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Obligation and allocation tables
-- ---------------------------------------------------------------------------

create table if not exists app_finance.bnpl_purchase_obligations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  transaction_id uuid not null,
  due_on date not null,
  created_at timestamptz not null default now(),
  constraint bnpl_obligations_owner_unique unique (id, user_id),
  -- One obligation per purchase: the ledger row is the identity.
  constraint bnpl_obligations_transaction_unique unique (transaction_id),
  constraint bnpl_obligations_account_owner_fk
    foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id) on delete cascade,
  constraint bnpl_obligations_tx_owner_fk
    foreign key (transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade
);

create index if not exists idx_bnpl_obligations_account
  on app_finance.bnpl_purchase_obligations (account_id, user_id, due_on);
create index if not exists idx_bnpl_obligations_transaction
  on app_finance.bnpl_purchase_obligations (transaction_id, user_id);

create table if not exists app_finance.bnpl_purchase_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  payment_transaction_id uuid not null,
  obligation_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint bnpl_allocations_owner_unique unique (id, user_id),
  constraint bnpl_allocations_pair_unique
    unique (payment_transaction_id, obligation_id),
  constraint bnpl_allocations_payment_owner_fk
    foreign key (payment_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade,
  constraint bnpl_allocations_obligation_owner_fk
    foreign key (obligation_id, user_id)
    references app_finance.bnpl_purchase_obligations (id, user_id)
    on delete cascade
);

create index if not exists idx_bnpl_allocations_obligation
  on app_finance.bnpl_purchase_payment_allocations (obligation_id, user_id);
create index if not exists idx_bnpl_allocations_payment
  on app_finance.bnpl_purchase_payment_allocations
  (payment_transaction_id, user_id);

alter table app_finance.bnpl_purchase_obligations enable row level security;
alter table app_finance.bnpl_purchase_payment_allocations
  enable row level security;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'bnpl_purchase_obligations', 'bnpl_purchase_payment_allocations'
  ] loop
    execute format(
      'drop policy if exists %1$s_select on app_finance.%1$I', v_table);
    execute format(
      'create policy %1$s_select on app_finance.%1$I for select '
      'to authenticated using ((select auth.uid()) = user_id)', v_table);
    execute format(
      'drop policy if exists %1$s_insert on app_finance.%1$I', v_table);
    execute format(
      'create policy %1$s_insert on app_finance.%1$I for insert '
      'to authenticated with check ((select auth.uid()) = user_id)', v_table);
    execute format(
      'drop policy if exists %1$s_delete on app_finance.%1$I', v_table);
    execute format(
      'create policy %1$s_delete on app_finance.%1$I for delete '
      'to authenticated using ((select auth.uid()) = user_id)', v_table);
  end loop;
end;
$$;

-- Writes happen only through the facility RPCs, like every other facility
-- table: the owner policies scope rows, the trigger keeps direct writes out.
drop trigger if exists trg_protect_bnpl_obligations
  on app_finance.bnpl_purchase_obligations;
create trigger trg_protect_bnpl_obligations
  before insert or update or delete on app_finance.bnpl_purchase_obligations
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_bnpl_allocations
  on app_finance.bnpl_purchase_payment_allocations;
create trigger trg_protect_bnpl_allocations
  before insert or update or delete
  on app_finance.bnpl_purchase_payment_allocations
  for each row execute function app_private.protect_installment_rows();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'bnpl_purchase_obligations', 'bnpl_purchase_payment_allocations'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'app_finance' and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table app_finance.%I',
        v_table);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Canonical paid/due state
-- ---------------------------------------------------------------------------

create or replace view app_finance.bnpl_purchase_obligation_statuses
with (security_invoker = on) as
  select
    o.id as obligation_id,
    o.user_id,
    o.account_id,
    o.transaction_id,
    t.title,
    t.counterparty,
    t.category_id,
    t.occurred_on as purchased_on,
    o.due_on,
    t.amount_minor,
    t.currency_code,
    coalesce(al.paid_minor, 0)::bigint as paid_minor,
    greatest(t.amount_minor - coalesce(al.paid_minor, 0), 0)::bigint
      as remaining_minor,
    case
      when coalesce(al.paid_minor, 0) >= t.amount_minor then 'paid'
      when coalesce(al.paid_minor, 0) > 0 then 'partially_paid'
      else 'unpaid'
    end as payment_status,
    case
      when coalesce(al.paid_minor, 0) >= t.amount_minor then 'paid'
      when o.due_on < current_date then 'overdue'
      when o.due_on = current_date then 'due_today'
      when coalesce(al.paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as due_status
  from app_finance.bnpl_purchase_obligations o
  join app_finance.financial_transactions t on t.id = o.transaction_id
  left join lateral (
    select sum(pa.amount_minor)::bigint as paid_minor
    from app_finance.bnpl_purchase_payment_allocations pa
    where pa.obligation_id = o.id
  ) al on true;

comment on view app_finance.bnpl_purchase_obligation_statuses is
  'Canonical due and paid state of ordinary BNPL purchases. Amount comes from '
  'the linked ledger transaction and paid state from allocation rows, so no '
  'mutable totals can drift.';

grant select on app_finance.bnpl_purchase_obligation_statuses
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Lifecycle helper
--
-- Mirrors relink_card_statement_item: it is called from the same create/edit
-- paths, no-ops for anything that is not an ordinary BNPL purchase, and
-- refuses to move a purchase whose obligation already carries payments.
-- ---------------------------------------------------------------------------

create or replace function app_finance.relink_bnpl_purchase_obligation(
  p_user_id uuid,
  p_transaction_id uuid,
  p_account_id uuid,
  p_occurred_on date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_account record;
  v_settings record;
begin
  -- Settled history is never silently re-dated, re-sized or dropped.
  if exists (
    select 1
    from app_finance.bnpl_purchase_payment_allocations pa
    join app_finance.bnpl_purchase_obligations o on o.id = pa.obligation_id
    where o.transaction_id = p_transaction_id and o.user_id = p_user_id
  ) then
    raise exception
      'bnpl_purchase_settled: reverse its payment before changing this '
      'purchase';
  end if;
  delete from app_finance.bnpl_purchase_obligations
    where transaction_id = p_transaction_id and user_id = p_user_id;

  select a.account_type into v_account
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = p_user_id;
  if v_account is null or v_account.account_type <> 'bnpl' then
    return;
  end if;
  -- A financed purchase is owed through its installment dues instead.
  if exists (
    select 1 from app_finance.installment_plans p
    where p.user_id = p_user_id
      and (p.purchase_transaction_id = p_transaction_id
        or p.down_payment_transaction_id = p_transaction_id)
  ) then
    return;
  end if;
  select s.default_due_day into v_settings
  from app_finance.credit_facility_settings s
  where s.account_id = p_account_id and s.user_id = p_user_id;
  if v_settings is null then return; end if;

  insert into app_finance.bnpl_purchase_obligations (
    user_id, account_id, transaction_id, due_on
  ) values (
    p_user_id, p_account_id, p_transaction_id,
    app_finance.bnpl_purchase_due_on(v_settings.default_due_day, p_occurred_on)
  );
end;
$$;

revoke execute on function app_finance.relink_bnpl_purchase_obligation(
  uuid, uuid, uuid, date
) from public, anon;
grant execute on function app_finance.relink_bnpl_purchase_obligation(
  uuid, uuid, uuid, date
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Backfill existing ordinary BNPL purchases
--
-- Idempotent: the unique transaction_id plus the not-exists guard mean a
-- second run creates nothing. Historical facility payments are NOT mapped to
-- individual purchases — which purchase an old generic repayment settled
-- cannot be proven, so those obligations start unpaid and the facility-level
-- debt stays the truth. That difference is visible rather than invented: the
-- Pay screen still exposes the unallocated remainder as facility balance.
-- ---------------------------------------------------------------------------

insert into app_finance.bnpl_purchase_obligations (
  user_id, account_id, transaction_id, due_on
)
select
  t.user_id,
  t.source_account_id,
  t.id,
  app_finance.bnpl_purchase_due_on(s.default_due_day, t.occurred_on)
from app_finance.financial_transactions t
join app_finance.accounts a
  on a.id = t.source_account_id and a.user_id = t.user_id
join app_finance.credit_facility_settings s
  on s.account_id = a.id and s.user_id = t.user_id
where t.transaction_kind = 'expense'
  and a.account_type = 'bnpl'
  and not exists (
    select 1 from app_finance.installment_plans p
    where p.user_id = t.user_id
      and (p.purchase_transaction_id = t.id
        or p.down_payment_transaction_id = t.id)
  )
  and not exists (
    select 1 from app_finance.credit_card_fee_charges f
    where f.transaction_id = t.id
  )
  and not exists (
    select 1 from app_finance.bnpl_purchase_obligations o
    where o.transaction_id = t.id
  );

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 6. Payment detail: an ordinary BNPL purchase is an Applied-to row
-- ---------------------------------------------------------------------------

create or replace view app_finance.facility_payment_allocations
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
    ba.payment_transaction_id,
    ba.user_id,
    b.account_id,
    'bnpl_purchase',
    ba.obligation_id,
    coalesce(b.title, b.counterparty),
    null::text,
    'bnpl_purchase',
    null::integer,
    b.due_on,
    ba.amount_minor,
    b.currency_code,
    'user_selected',
    ba.created_at
  from app_finance.bnpl_purchase_payment_allocations ba
  join app_finance.bnpl_purchase_obligation_statuses b
    on b.obligation_id = ba.obligation_id
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

grant select on app_finance.facility_payment_allocations
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Facility summaries learn ordinary BNPL obligations
--
-- The installment lateral becomes a union of every non-statement payable
-- obligation, and next_due_amount_minor becomes the TOTAL owed on the
-- earliest unpaid date instead of whichever row sorted first — otherwise a
-- day carrying two purchases and an installment reported only one of them.
-- Credit-card statement semantics (the `c` lateral) are untouched.
-- ---------------------------------------------------------------------------

create or replace view app_finance.credit_facility_summaries
with (security_invoker = on) as
  select
    a.id as account_id, a.user_id, a.name, a.account_type, a.currency_code,
    a.is_archived, a.notes,
    a.opening_balance_minor as opening_owed_minor,
    s.credit_limit_minor, s.statement_day, s.default_due_day,
    s.last_four_digits, s.reminder_lead_days, s.facility_status,
    s.min_payment_method, s.min_payment_fixed_minor,
    s.min_payment_basis_points,
    o.outstanding_minor,
    greatest(s.credit_limit_minor - o.outstanding_minor, 0)::bigint
      as available_credit_minor,
    case when o.outstanding_minor <= 0 then 0 else round(
      o.outstanding_minor::numeric * 10000 / s.credit_limit_minor
    )::integer end as utilization_basis_points,
    (coalesce(d.due_now_minor, 0) + coalesce(c.due_now_minor, 0))::bigint
      as due_now_minor,
    (coalesce(d.overdue_minor, 0) + coalesce(c.overdue_minor, 0))::bigint
      as overdue_minor,
    least(d.next_due_on, c.next_due_on) as next_due_on,
    case when c.next_due_on is not null and (d.next_due_on is null
      or c.next_due_on <= d.next_due_on) then c.next_due_amount_minor
      else d.next_due_amount_minor end as next_due_amount_minor,
    coalesce(c.statement_remaining_minor, 0)::bigint
      as statement_remaining_minor,
    c.next_due_on as next_statement_due_on,
    coalesce(p.active_plan_count, 0)::integer as active_plan_count,
    (coalesce(d.upcoming_due_minor, 0)
      + coalesce(c.upcoming_due_minor, 0))::bigint as upcoming_due_minor,
    s.color_hex,
    s.installment_due_day, s.grace_period_days,
    s.min_payment_percentage_basis,
    s.min_payment_include_installment_dues,
    s.min_payment_include_bank_fees,
    s.min_payment_include_overdue,
    s.min_payment_fixed_floor_minor,
    s.fx_markup_basis_points
  from app_finance.accounts a
  join app_finance.credit_facility_settings s on s.account_id = a.id
  cross join lateral (
    select app_finance.facility_outstanding_minor(a.id) as outstanding_minor
  ) o
  left join lateral (
    select
      sum(due.remaining_minor) filter (where due.due_on <= current_date)
        as due_now_minor,
      sum(due.remaining_minor) filter (where due.due_on < current_date)
        as overdue_minor,
      min(due.due_on) as next_due_on,
      -- Everything owed on that earliest date, not merely its first row.
      sum(due.remaining_minor) filter (
        where due.due_on = (select min(x.due_on) from (
          select ds.due_on
          from app_finance.installment_due_statuses ds
          where ds.account_id = a.id and ds.plan_status = 'active'
            and ds.remaining_minor > 0
            and not (a.account_type = 'credit_card' and exists (
              select 1 from app_finance.credit_card_statement_cycles sc
              where sc.account_id = a.id and sc.due_on = ds.due_on))
          union all
          select b.due_on
          from app_finance.bnpl_purchase_obligation_statuses b
          where b.account_id = a.id and b.remaining_minor > 0
        ) x)
      )::bigint as next_due_amount_minor,
      sum(due.remaining_minor) filter (where due.due_on
        <= (current_date + interval '1 month')::date) as upcoming_due_minor
    from (
      select ds.due_on, ds.remaining_minor
      from app_finance.installment_due_statuses ds
      where ds.account_id = a.id and ds.plan_status = 'active'
        and ds.remaining_minor > 0
        and not (a.account_type = 'credit_card' and exists (
          select 1 from app_finance.credit_card_statement_cycles sc
          where sc.account_id = a.id and sc.due_on = ds.due_on
        ))
      union all
      -- Ordinary BNPL purchases are payable obligations in their own right.
      select b.due_on, b.remaining_minor
      from app_finance.bnpl_purchase_obligation_statuses b
      where b.account_id = a.id and b.remaining_minor > 0
    ) due
  ) d on true
  left join lateral (
    select
      sum(y.total_remaining_minor) filter (where y.due_on <= current_date
        and y.cycle_close < current_date) as due_now_minor,
      sum(y.total_remaining_minor) filter (where y.due_on < current_date)
        as overdue_minor,
      min(y.due_on) filter (where y.total_remaining_minor > 0) as next_due_on,
      (array_agg(y.total_remaining_minor order by y.due_on)
        filter (where y.total_remaining_minor > 0))[1] as next_due_amount_minor,
      sum(y.total_remaining_minor) as statement_remaining_minor,
      sum(y.total_remaining_minor) filter (where y.due_on
        <= (current_date + interval '1 month')::date) as upcoming_due_minor
    from app_finance.credit_card_statement_summaries y
    where y.account_id = a.id and y.total_remaining_minor > 0
  ) c on true
  left join lateral (
    select count(*) as active_plan_count
    from app_finance.installment_plans ip
    where ip.account_id = a.id and ip.status = 'active'
  ) p on true
  where app_finance.account_role(a.account_type) = 'liability';

grant select on app_finance.credit_facility_summaries
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8. Lifecycle, payment, and read surfaces learn the BNPL obligation
--
-- These are the current definitions with the BNPL paths added, so existing
-- credit-card and installment behavior carries over verbatim:
--   * charge_liability_account / update_expense_transaction relink the
--     obligation exactly where they relink a card statement item;
--   * delete_ledger_transaction refuses to drop a settled purchase;
--   * reverse_facility_payment releases BNPL allocations too;
--   * pay_credit_facility_v2/v3 accept the bnpl_purchase component — v2
--     keeps payable-now eligibility, v3 keeps month scoping;
--   * home_current_month_obligations drops the workaround that summed raw
--     BNPL expenses as unpaid and invented a due-today obligation;
--   * both due-breakdown DTOs expose bnpl_purchase components, and the
--     next-due group is the whole next bill rather than one row.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app_finance.charge_liability_account(p_account_id uuid, p_title text, p_category_id uuid, p_occurred_on date, p_amount_minor bigint, p_notes text DEFAULT NULL::text, p_charge_id uuid DEFAULT NULL::uuid, p_is_foreign_currency boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
  v_settings record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_markup_tx_id uuid;
  v_markup_minor bigint := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  -- Client-generated ids make a retried save idempotent.
  if p_charge_id is not null then
    select id into v_tx_id from app_finance.financial_transactions
      where id = p_charge_id and user_id = v_user_id;
    if v_tx_id is not null then
      return v_tx_id;
    end if;
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select a.id, a.currency_code, a.account_type into v_account
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id
    for update;
  if v_account is null
    or app_finance.account_role(v_account.account_type) <> 'liability' then
    raise exception
      'invalid_account: this flow requires a credit card or BNPL account';
  end if;
  perform app_finance.assert_liability_can_fund(v_user_id, p_account_id);

  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;

  if p_is_foreign_currency and v_account.account_type = 'credit_card'
    and coalesce(v_settings.fx_markup_basis_points, 0) > 0 then
    v_markup_minor := round(
      p_amount_minor::numeric * v_settings.fx_markup_basis_points / 10000
    )::bigint;
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + p_amount_minor + v_markup_minor
    > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  if app_finance.target_statement_is_settled(
    v_user_id, p_account_id, p_occurred_on
  ) then
    raise exception
      'statement_settled: that statement is already paid; use a correction';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    coalesce(p_charge_id, gen_random_uuid()), v_user_id, 'expense',
    p_occurred_on, p_amount_minor, v_account.currency_code, p_account_id,
    p_category_id, p_title, p_notes
  )
  returning id into v_tx_id;

  perform app_finance.relink_card_statement_item(
    v_user_id, v_tx_id, p_account_id, p_occurred_on, p_amount_minor
  );
  perform app_finance.relink_bnpl_purchase_obligation(
    v_user_id, v_tx_id, p_account_id, p_occurred_on
  );

  if v_markup_minor > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    ) values (
      v_user_id, 'expense', p_occurred_on, v_markup_minor,
      v_account.currency_code, p_account_id, p_category_id,
      'Foreign Exchange Markup'
    )
    returning id into v_markup_tx_id;

    perform app_finance.relink_card_statement_item(
      v_user_id, v_markup_tx_id, p_account_id, p_occurred_on, v_markup_minor
    );

    insert into app_finance.credit_card_fx_markup_charges (
      user_id, purchase_transaction_id, markup_transaction_id, basis_points
    ) values (
      v_user_id, v_tx_id, v_markup_tx_id, v_settings.fx_markup_basis_points
    );
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app_finance.update_expense_transaction(p_transaction_id uuid, p_account_id uuid, p_occurred_on date, p_amount_minor bigint, p_category_id uuid DEFAULT NULL::uuid, p_counterparty text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_is_foreign_currency boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_tx record;
  v_old_account_id uuid;
  v_new_account record;
  v_new_role text;
  v_settings record;
  v_outstanding bigint;
  v_is_income boolean;
  v_moved boolean;
  v_monetary_change boolean;
  v_existing_markup record;
  v_fx_rate integer;
  v_new_markup_minor bigint;
  v_old_markup_minor bigint;
  v_markup_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select * into v_tx
    from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id
    for update;
  if v_tx is null then
    raise exception 'not_found: transaction';
  end if;

  -- Transfers and salary payments have their own flows and are never
  -- reachable from the ordinary transaction editor.
  if v_tx.transaction_kind in ('transfer', 'salary_income') then
    raise exception
      'invalid_kind: this record is edited from its own flow';
  end if;

  -- System-owned records keep their specialized editors.
  if v_tx.facility_reversal_of_id is not null
    or exists (
      select 1 from app_finance.installment_payment_allocations pa
      where pa.payment_transaction_id = p_transaction_id
    )
    or exists (
      select 1 from app_finance.credit_card_statement_allocations al
      where al.payment_transaction_id = p_transaction_id
    ) then
    raise exception
      'facility_transaction_locked: correct this from the facility screen';
  end if;
  if exists (
    select 1 from app_finance.installment_plans p
    where p.purchase_transaction_id = p_transaction_id
      or p.down_payment_transaction_id = p_transaction_id
  ) then
    raise exception
      'plan_controlled: edit this purchase from its installment plan';
  end if;
  if exists (
    select 1 from app_finance.credit_card_fee_charges f
    where f.transaction_id = p_transaction_id
  ) then
    raise exception
      'fee_charge_locked: change the fee rule instead of the generated charge';
  end if;
  if exists (
    select 1 from app_finance.credit_card_fx_markup_charges m
    where m.markup_transaction_id = p_transaction_id
  ) then
    raise exception
      'fx_markup_locked: this charge follows its purchase; edit the purchase '
      'instead';
  end if;

  v_is_income := v_tx.transaction_kind in
    ('custom_income', 'freelance_income');
  v_old_account_id := coalesce(
    v_tx.source_account_id, v_tx.destination_account_id
  );

  -- Lock every account involved in a stable order so two concurrent moves
  -- between the same pair can never deadlock.
  perform 1 from app_finance.accounts
    where id in (v_old_account_id, p_account_id) and user_id = v_user_id
    order by id
    for update;

  select a.id, a.account_type, a.currency_code, a.is_archived
    into v_new_account
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id;
  if v_new_account is null then
    raise exception 'invalid_account: account not found';
  end if;
  v_new_role := app_finance.account_role(v_new_account.account_type);
  v_moved := v_old_account_id is distinct from p_account_id;
  v_monetary_change :=
    v_moved
    or v_tx.amount_minor <> p_amount_minor
    or v_tx.occurred_on <> p_occurred_on;

  if v_new_account.currency_code <> v_tx.currency_code then
    raise exception 'currency_mismatch: the account uses another currency';
  end if;

  -- Income never lands on a liability: a card refund or repayment is not
  -- ordinary income and has its own flow.
  if v_new_role = 'liability' and v_tx.transaction_kind <> 'expense' then
    raise exception
      'invalid_kind: only expenses can be charged to a credit facility';
  end if;

  -- A different destination must be eligible today. The account the record
  -- already sits on stays usable so archived or frozen history can still be
  -- corrected in place.
  if v_moved then
    if v_new_account.is_archived then
      raise exception 'account_archived: cannot write to an archived account';
    end if;
    if v_new_role = 'liability' then
      perform app_finance.assert_liability_can_fund(v_user_id, p_account_id);
    end if;
  end if;

  if p_category_id is not null and not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived
  ) then
    raise exception 'invalid_category: category not found';
  end if;
  if v_new_role = 'liability' and not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  -- Settled statement history is corrected, never mutated: neither the
  -- cycle the charge leaves nor the cycle it would join may already carry a
  -- payment. Renaming or recategorizing a settled charge stays allowed.
  if v_monetary_change then
    if app_finance.charge_statement_is_settled(v_user_id, p_transaction_id)
      or app_finance.target_statement_is_settled(
        v_user_id, p_account_id, p_occurred_on
      ) then
      raise exception
        'statement_settled: that statement is already paid; use a correction';
    end if;
  end if;

  -- Credit limits are validated against the outstanding amount the edit
  -- would actually produce, with the facility row locked above.
  if v_new_role = 'liability' then
    select * into v_settings
      from app_finance.credit_facility_settings
      where account_id = p_account_id and user_id = v_user_id;
    if v_settings is null then
      raise exception
        'facility_not_configured: set a credit limit before charging this account';
    end if;
    v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
    if not v_moved then
      v_outstanding := v_outstanding - v_tx.amount_minor;
    end if;
    if v_outstanding + p_amount_minor > v_settings.credit_limit_minor then
      raise exception 'insufficient_credit: purchase exceeds available credit';
    end if;
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  update app_finance.financial_transactions set
    occurred_on = p_occurred_on,
    amount_minor = p_amount_minor,
    source_account_id = case when v_is_income then null else p_account_id end,
    destination_account_id =
      case when v_is_income then p_account_id else null end,
    category_id = p_category_id,
    counterparty = p_counterparty,
    title = p_title,
    notes = p_notes
  where id = p_transaction_id and user_id = v_user_id;

  -- Rebuilds membership on the destination and drops the old linkage in the
  -- same statement, so no orphaned statement item can survive a move.
  perform app_finance.relink_card_statement_item(
    v_user_id, p_transaction_id, p_account_id, p_occurred_on, p_amount_minor
  );
  -- Recreates, moves, re-dates or drops the BNPL obligation to match the
  -- edited account and date, and refuses to touch a settled one.
  perform app_finance.relink_bnpl_purchase_obligation(
    v_user_id, p_transaction_id, p_account_id, p_occurred_on
  );

  -- The FX markup switch: evaluated fresh against where and what this
  -- transaction is now, never against what it used to be. An expense that
  -- moved off the card, or a card with no configured rate, always ends up
  -- with no markup regardless of the switch.
  select * into v_existing_markup
    from app_finance.credit_card_fx_markup_charges
    where purchase_transaction_id = p_transaction_id and user_id = v_user_id;

  -- Procedural if, not a case expression: v_settings is a bare `record`
  -- that is never assigned at all when v_new_role isn't 'liability' (e.g.
  -- asset-to-asset), and referencing an unassigned record's field fails to
  -- parse even inside a case branch that would never run — the tuple
  -- structure has to be known before any branch of a single expression can
  -- be evaluated. A separate if statement only compiles this branch when
  -- it is actually taken, by which point v_settings is guaranteed set.
  v_fx_rate := 0;
  if v_new_role = 'liability' and v_new_account.account_type = 'credit_card'
  then
    v_fx_rate := coalesce(v_settings.fx_markup_basis_points, 0);
  end if;
  v_new_markup_minor := 0;
  if p_is_foreign_currency and v_fx_rate > 0 then
    v_new_markup_minor :=
      round(p_amount_minor::numeric * v_fx_rate / 10000)::bigint;
  end if;

  if v_new_markup_minor > 0 then
    if v_existing_markup is not null then
      -- The purchase's own credit-limit check above sized only the
      -- purchase's change; a resized markup needs the same check the new
      -- one below gets, against the balance with the *old* markup amount
      -- still in it (the resize below hasn't happened yet).
      select amount_minor into v_old_markup_minor
        from app_finance.financial_transactions
        where id = v_existing_markup.markup_transaction_id
          and user_id = v_user_id;
      v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
      if v_outstanding - v_old_markup_minor + v_new_markup_minor
        > v_settings.credit_limit_minor
      then
        raise exception
          'insufficient_credit: purchase exceeds available credit';
      end if;
      update app_finance.financial_transactions set
        amount_minor = v_new_markup_minor,
        occurred_on = p_occurred_on,
        source_account_id = p_account_id,
        category_id = p_category_id
      where id = v_existing_markup.markup_transaction_id
        and user_id = v_user_id;
      perform app_finance.relink_card_statement_item(
        v_user_id, v_existing_markup.markup_transaction_id, p_account_id,
        p_occurred_on, v_new_markup_minor
      );
      update app_finance.credit_card_fx_markup_charges
        set basis_points = v_fx_rate
        where id = v_existing_markup.id and user_id = v_user_id;
    else
      -- The purchase's own credit-limit check above never accounted for a
      -- markup that didn't exist yet; check again with it included, against
      -- the balance the update above already produced.
      v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
      if v_outstanding + v_new_markup_minor > v_settings.credit_limit_minor
      then
        raise exception
          'insufficient_credit: purchase exceeds available credit';
      end if;
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, category_id, title
      ) values (
        v_user_id, 'expense', p_occurred_on, v_new_markup_minor,
        v_new_account.currency_code, p_account_id, p_category_id,
        'Foreign Exchange Markup'
      )
      returning id into v_markup_tx_id;
      perform app_finance.relink_card_statement_item(
        v_user_id, v_markup_tx_id, p_account_id, p_occurred_on,
        v_new_markup_minor
      );
      insert into app_finance.credit_card_fx_markup_charges (
        user_id, purchase_transaction_id, markup_transaction_id, basis_points
      ) values (
        v_user_id, p_transaction_id, v_markup_tx_id, v_fx_rate
      );
    end if;
  elsif v_existing_markup is not null then
    -- Switched off, or no longer eligible: the markup transaction's
    -- deletion cascades the link row away with it.
    delete from app_finance.financial_transactions
      where id = v_existing_markup.markup_transaction_id
        and user_id = v_user_id;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return p_transaction_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app_finance.delete_ledger_transaction(p_transaction_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_tx record;
  v_markup_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_tx
    from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id
    for update;
  if v_tx is null then
    raise exception 'not_found: transaction';
  end if;
  if v_tx.transaction_kind = 'salary_income' then
    raise exception 'invalid_kind: this record is edited from its own flow';
  end if;
  if v_tx.facility_reversal_of_id is not null
    or exists (
      select 1 from app_finance.installment_payment_allocations pa
      where pa.payment_transaction_id = p_transaction_id
    )
    or exists (
      select 1 from app_finance.credit_card_statement_allocations al
      where al.payment_transaction_id = p_transaction_id
    ) then
    raise exception
      'facility_transaction_locked: correct this from the facility screen';
  end if;
  if exists (
    select 1 from app_finance.installment_plans p
    where p.purchase_transaction_id = p_transaction_id
      or p.down_payment_transaction_id = p_transaction_id
  ) then
    raise exception
      'plan_controlled: edit this purchase from its installment plan';
  end if;
  if exists (
    select 1 from app_finance.credit_card_fee_charges f
    where f.transaction_id = p_transaction_id
  ) then
    raise exception
      'fee_charge_locked: change the fee rule instead of the generated charge';
  end if;
  if exists (
    select 1 from app_finance.credit_card_fx_markup_charges m
    where m.markup_transaction_id = p_transaction_id
  ) then
    raise exception
      'fx_markup_locked: this charge follows its purchase; edit the purchase '
      'instead';
  end if;
  if exists (
    select 1
    from app_finance.bnpl_purchase_payment_allocations pa
    join app_finance.bnpl_purchase_obligations o on o.id = pa.obligation_id
    where o.transaction_id = p_transaction_id and o.user_id = v_user_id
  ) then
    raise exception
      'bnpl_purchase_settled: reverse its payment before deleting this '
      'purchase';
  end if;
  if app_finance.charge_statement_is_settled(v_user_id, p_transaction_id) then
    raise exception
      'statement_settled: that statement is already paid; use a correction';
  end if;

  select markup_transaction_id into v_markup_tx_id
    from app_finance.credit_card_fx_markup_charges
    where purchase_transaction_id = p_transaction_id and user_id = v_user_id;

  perform 1 from app_finance.accounts
    where id in (v_tx.source_account_id, v_tx.destination_account_id)
      and user_id = v_user_id
    order by id
    for update;

  perform set_config('app_finance.facility_internal', 'on', true);
  if v_markup_tx_id is not null then
    delete from app_finance.financial_transactions
      where id = v_markup_tx_id and user_id = v_user_id;
  end if;
  delete from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id;
  perform set_config('app_finance.facility_internal', '', true);
end;
$function$;

CREATE OR REPLACE FUNCTION app_finance.reverse_facility_payment(p_transaction_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  delete from app_finance.bnpl_purchase_payment_allocations
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
$function$;

CREATE OR REPLACE FUNCTION app_core.delete_finance_suit_data(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  delete from app_finance.bnpl_purchase_payment_allocations
    where user_id = p_user_id;
  delete from app_finance.bnpl_purchase_obligations where user_id = p_user_id;
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
$function$;

CREATE OR REPLACE FUNCTION app_finance.pay_credit_facility_v2(p_account_id uuid, p_source_account_id uuid, p_amount_minor bigint, p_paid_on date, p_allocations jsonb, p_notes text DEFAULT NULL::text, p_payment_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  v_bnpl record;
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
        union all
        select jsonb_build_object('type', 'bnpl_purchase',
          'id', ba.obligation_id, 'amount_minor', ba.amount_minor)
        from app_finance.bnpl_purchase_payment_allocations ba
        where ba.payment_transaction_id = v_tx_id
          and ba.user_id = v_user_id
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
    select 1 from app_finance.bnpl_purchase_obligation_statuses b
    where b.user_id = v_user_id and b.account_id = p_account_id
      and b.remaining_minor > 0 and b.due_on <= p_paid_on
  ) or exists (
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
  -- The next payable date spans both ordinary purchases and installments,
  -- so "next due" is the real next bill rather than the next installment.
  select min(due_on) into v_next_due_on from (
    select s.due_on
    from app_finance.installment_due_statuses s
    where s.user_id = v_user_id and s.account_id = p_account_id
      and s.plan_status = 'active' and s.remaining_minor > 0
      and s.due_on > p_paid_on
    union all
    select b.due_on
    from app_finance.bnpl_purchase_obligation_statuses b
    where b.user_id = v_user_id and b.account_id = p_account_id
      and b.remaining_minor > 0 and b.due_on > p_paid_on
  ) upcoming;

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
      or v_type not in ('installment_due', 'statement_item',
        'bnpl_purchase', 'facility_balance') then
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
    elsif v_type = 'bnpl_purchase' then
      select b.obligation_id, b.remaining_minor, b.due_on into v_bnpl
      from app_finance.bnpl_purchase_obligation_statuses b
      where b.obligation_id = v_target_id
        and b.user_id = v_user_id and b.account_id = p_account_id;
      if v_bnpl is null then
        raise exception 'not_found: bnpl purchase';
      end if;
      if v_bnpl.remaining_minor <= 0 then
        raise exception 'allocation_target_paid: purchase settled';
      end if;
      if v_alloc_amount > v_bnpl.remaining_minor then
        raise exception 'allocation_exceeds_purchase';
      end if;
      if not (v_bnpl.due_on <= p_paid_on
        or (not v_has_current and v_bnpl.due_on = v_next_due_on)) then
        raise exception
          'allocation_not_payable: purchase is not currently payable';
      end if;
      insert into app_finance.bnpl_purchase_payment_allocations (
        user_id, payment_transaction_id, obligation_id, amount_minor
      ) values (v_user_id, v_tx_id, v_bnpl.obligation_id, v_alloc_amount);
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
$function$;

CREATE OR REPLACE FUNCTION app_finance.pay_credit_facility_v3(p_account_id uuid, p_source_account_id uuid, p_amount_minor bigint, p_paid_on date, p_month_start date, p_allocations jsonb, p_notes text DEFAULT NULL::text, p_payment_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  v_bnpl record;
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
        union all
        select jsonb_build_object('type', 'bnpl_purchase',
          'id', ba.obligation_id, 'amount_minor', ba.amount_minor)
        from app_finance.bnpl_purchase_payment_allocations ba
        where ba.payment_transaction_id = v_tx_id
          and ba.user_id = v_user_id
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
      or v_type not in
        ('installment_due', 'statement_item', 'bnpl_purchase') then
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
    elsif v_type = 'bnpl_purchase' then
      select b.obligation_id, b.remaining_minor, b.due_on into v_bnpl
      from app_finance.bnpl_purchase_obligation_statuses b
      where b.obligation_id = v_target_id
        and b.user_id = v_user_id and b.account_id = p_account_id;
      if v_bnpl is null then
        raise exception 'not_found: bnpl purchase';
      end if;
      if v_bnpl.remaining_minor <= 0 then
        raise exception 'allocation_target_paid: purchase settled';
      end if;
      if v_alloc_amount > v_bnpl.remaining_minor then
        raise exception 'allocation_exceeds_purchase';
      end if;
      if v_bnpl.due_on < v_month_start or v_bnpl.due_on > v_month_end then
        raise exception
          'allocation_out_of_period: component is not due in the paid month';
      end if;
      insert into app_finance.bnpl_purchase_payment_allocations (
        user_id, payment_transaction_id, obligation_id, amount_minor
      ) values (v_user_id, v_tx_id, v_bnpl.obligation_id, v_alloc_amount);
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
$function$;

CREATE OR REPLACE FUNCTION app_finance.home_current_month_obligations(p_today date DEFAULT CURRENT_DATE)
 RETURNS TABLE(obligation_id uuid, obligation_kind text, source_account_id uuid, source_name text, masked_identifier text, related_id uuid, due_on date, currency_code text, remaining_minor bigint, minimum_due_minor bigint, paid_minor bigint, obligation_status text, title text, sort_rank integer, details jsonb)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_month_start date := date_trunc('month', p_today)::date;
  v_month_end date := (date_trunc('month', p_today)
    + interval '1 month - 1 day')::date;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Materializing is idempotent and does not create ledger transactions. The
  -- Home surface needs every pending expense occurrence in this calendar
  -- month, not only the earliest item inside a rule's reminder window.
  perform app_finance.materialize_recurring_occurrences(v_month_end);

  return query
  with card_statements as (
    select
      y.id as obligation_id,
      'card_statement'::text as obligation_kind,
      y.account_id as source_account_id,
      a.name as source_name,
      s.last_four_digits as masked_identifier,
      y.id as related_id,
      y.due_on,
      y.currency_code,
      y.total_remaining_minor as remaining_minor,
      least(y.minimum_due_minor, y.total_remaining_minor)::bigint
        as minimum_due_minor,
      y.total_paid_minor as paid_minor,
      case
        when y.total_remaining_minor = 0 then 'paid'
        when y.due_on < p_today then 'overdue'
        when y.due_on = p_today then 'due_today'
        when y.total_paid_minor > 0 then 'partially_paid'
        else 'upcoming'
      end as obligation_status,
      a.name || ' — Statement due' as title,
      case when y.due_on < p_today then 0
        when y.due_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'cycle_start', y.cycle_start,
        'cycle_close', y.cycle_close,
        'statement_due_minor', y.total_statement_due_minor,
        'ordinary_charges_minor', y.ordinary_statement_charges_minor,
        'fee_charges_minor', y.fee_charges_minor,
        'installment_due_minor', y.installment_due_minor,
        'total_paid_minor', y.total_paid_minor,
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', si.id,
            'kind', case when fc.id is null then 'purchase' else 'fee' end,
            'title', coalesce(t.title, t.counterparty, fr.name, 'Charge'),
            'counterparty', t.counterparty,
            'occurred_on', t.occurred_on,
            'category', cat.name,
            'amount_minor', si.amount_minor,
            'paid_minor', coalesce(ia.paid_minor, 0),
            'remaining_minor',
              greatest(si.amount_minor - coalesce(ia.paid_minor, 0), 0),
            'payment_status', case
              when coalesce(ia.paid_minor, 0) >= si.amount_minor then 'paid'
              when coalesce(ia.paid_minor, 0) > 0 then 'partially_paid'
              else 'unpaid'
            end
          ) order by t.occurred_on, si.id)
          from app_finance.credit_card_statement_items si
          join app_finance.financial_transactions t on t.id = si.transaction_id
          left join app_finance.transaction_categories cat on cat.id = t.category_id
          left join app_finance.credit_card_fee_charges fc
            on fc.transaction_id = t.id
          left join app_finance.credit_card_fee_rules fr on fr.id = fc.rule_id
          left join lateral (
            select sum(x.amount_minor)::bigint as paid_minor
            from app_finance.credit_card_statement_item_allocations x
            where x.statement_item_id = si.id
          ) ia on true
          where si.cycle_id = y.id and si.user_id = v_user_id
        ), '[]'::jsonb),
        'installments', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', ds.id,
            'plan_id', ds.plan_id,
            'title', ds.plan_title,
            'sequence_number', ds.sequence_number,
            'installment_count', p.installment_count,
            'due_on', ds.due_on,
            'amount_minor', ds.amount_minor,
            'paid_minor', ds.paid_minor,
            'remaining_minor', ds.remaining_minor,
            'payment_status', case
              when ds.remaining_minor = 0 then 'paid'
              when ds.paid_minor > 0 then 'partially_paid'
              else 'unpaid'
            end
          ) order by ds.sequence_number)
          from app_finance.installment_due_statuses ds
          join app_finance.installment_plans p on p.id = ds.plan_id
          where ds.account_id = y.account_id
            and ds.due_on = y.due_on
            and ds.plan_status <> 'cancelled'
        ), '[]'::jsonb)
      ) as details
    from app_finance.credit_card_statement_summaries y
    join app_finance.accounts a on a.id = y.account_id
    join app_finance.credit_facility_settings s on s.account_id = y.account_id
    where y.user_id = v_user_id
      and (y.total_remaining_minor > 0
        or (y.total_paid_minor > 0 and y.due_on >= p_today))
      and y.due_on <= v_month_end
  ),
  -- Ordinary BNPL purchases now carry their own obligation and paid state,
  -- grouped per due date so Home shows one card per real bill.
  bnpl_purchases as (
    select
      (array_agg(b.obligation_id order by b.purchased_on, b.obligation_id))[1]
        as obligation_id,
      'bnpl_purchase'::text as obligation_kind,
      b.account_id as source_account_id,
      a.name as source_name,
      s.last_four_digits as masked_identifier,
      null::uuid as related_id,
      b.due_on,
      b.currency_code,
      sum(b.remaining_minor)::bigint as remaining_minor,
      sum(b.remaining_minor)::bigint as minimum_due_minor,
      sum(b.paid_minor)::bigint as paid_minor,
      case
        when b.due_on < p_today then 'overdue'
        when b.due_on = p_today then 'due_today'
        when sum(b.paid_minor) > 0 then 'partially_paid'
        else 'upcoming'
      end as obligation_status,
      a.name || ' — Purchases' as title,
      case when b.due_on < p_today then 0
        when b.due_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'items', coalesce(jsonb_agg(jsonb_build_object(
          'id', b.obligation_id,
          'kind', 'purchase',
          'title', coalesce(b.title, b.counterparty, 'Purchase'),
          'occurred_on', b.purchased_on,
          'due_on', b.due_on,
          'amount_minor', b.amount_minor,
          'paid_minor', b.paid_minor,
          'remaining_minor', b.remaining_minor,
          'payment_status', b.payment_status
        ) order by b.purchased_on, b.obligation_id), '[]'::jsonb),
        'installments', '[]'::jsonb
      ) as details
    from app_finance.bnpl_purchase_obligation_statuses b
    join app_finance.accounts a on a.id = b.account_id
    join app_finance.credit_facility_settings s on s.account_id = b.account_id
    where b.user_id = v_user_id
      and b.remaining_minor > 0
      and b.due_on <= v_month_end
    group by b.account_id, a.name, s.last_four_digits, b.due_on,
      b.currency_code
  ),
  bnpl_installments as (
    select
      ds.id as obligation_id,
      'installment_due'::text as obligation_kind,
      ds.account_id as source_account_id,
      a.name as source_name,
      s.last_four_digits as masked_identifier,
      ds.plan_id as related_id,
      ds.due_on,
      ds.currency_code,
      ds.remaining_minor,
      ds.remaining_minor as minimum_due_minor,
      ds.paid_minor,
      case
        when ds.remaining_minor = 0 then 'paid'
        when ds.due_on < p_today then 'overdue'
        when ds.due_on = p_today then 'due_today'
        when ds.paid_minor > 0 then 'partially_paid'
        else 'upcoming'
      end as obligation_status,
      a.name || ' — ' || ds.plan_title as title,
      case when ds.due_on < p_today then 0
        when ds.due_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'plan_title', p.title,
        'sequence_number', ds.sequence_number,
        'installment_count', p.installment_count,
        'purchase_date', p.purchased_on,
        'purchase_price_minor', p.purchase_price_minor,
        'financed_principal_minor', p.financed_principal_minor,
        'financing_fees_minor', p.financing_fees_minor,
        'plan_remaining_minor', ps.remaining_minor,
        'category', cat.name,
        'items', '[]'::jsonb,
        'installments', jsonb_build_array(jsonb_build_object(
          'id', ds.id,
          'title', ds.plan_title,
          'sequence_number', ds.sequence_number,
          'installment_count', p.installment_count,
          'due_on', ds.due_on,
          'amount_minor', ds.amount_minor,
          'paid_minor', ds.paid_minor,
          'remaining_minor', ds.remaining_minor,
          'payment_status', case
            when ds.remaining_minor = 0 then 'paid'
            when ds.paid_minor > 0 then 'partially_paid'
            else 'unpaid'
          end
        ))
      ) as details
    from app_finance.installment_due_statuses ds
    join app_finance.installment_plans p on p.id = ds.plan_id
    join app_finance.installment_plan_summaries ps on ps.id = p.id
    join app_finance.accounts a on a.id = ds.account_id
    join app_finance.credit_facility_settings s on s.account_id = ds.account_id
    left join app_finance.transaction_categories cat on cat.id = p.category_id
    where ds.user_id = v_user_id
      and a.account_type = 'bnpl'
      and ds.plan_status <> 'cancelled'
      and (ds.remaining_minor > 0
        or (ds.paid_minor > 0 and ds.due_on >= p_today))
      and ds.due_on <= v_month_end
  ),
  recurring_expenses as (
    select
      o.id as obligation_id,
      'recurring_expense'::text as obligation_kind,
      r.source_account_id,
      r.name as source_name,
      null::text as masked_identifier,
      r.id as related_id,
      o.scheduled_on as due_on,
      r.currency_code,
      o.expected_amount_minor as remaining_minor,
      o.expected_amount_minor as minimum_due_minor,
      0::bigint as paid_minor,
      case
        when o.scheduled_on < p_today then 'overdue'
        when o.scheduled_on = p_today then 'due_today'
        else 'upcoming'
      end as obligation_status,
      r.name || ' — Recurring payment' as title,
      case when o.scheduled_on < p_today then 0
        when o.scheduled_on = p_today then 1 else 2 end as sort_rank,
      jsonb_build_object(
        'frequency', r.frequency,
        'category', cat.name,
        'source_account_name', source.name,
        'snoozed_until', o.snoozed_until,
        'occurrence_status', o.status
      ) as details
    from app_finance.recurring_occurrences o
    join app_finance.recurring_rules r on r.id = o.rule_id
    join app_finance.accounts source on source.id = r.source_account_id
    left join app_finance.transaction_categories cat on cat.id = r.category_id
    where o.user_id = v_user_id
      and r.rule_kind = 'expense'
      -- A card-funded recurring rule is a future card charge, not a direct
      -- cash obligation. It becomes payable through its card statement.
      and source.account_type <> 'credit_card'
      and o.status = 'pending'
      and o.scheduled_on <= v_month_end
  )
  select * from card_statements
  union all select * from bnpl_installments
  union all select * from bnpl_purchases
  union all select * from recurring_expenses
  order by sort_rank, due_on, source_name, obligation_id;
end;
$function$;

CREATE OR REPLACE FUNCTION app_finance.facility_due_breakdown(p_account_id uuid, p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
  bnpl_components as (
    select
      'bnpl_purchase' as component_type,
      b.obligation_id as component_id,
      null::uuid as plan_id,
      null::uuid as cycle_id,
      b.transaction_id,
      coalesce(b.title, b.counterparty) as title,
      'bnpl_purchase' as activity_kind,
      null::text as fee_type,
      null::integer as sequence_number,
      null::integer as installment_count,
      b.purchased_on as component_on,
      b.amount_minor,
      b.paid_minor,
      b.remaining_minor,
      b.payment_status,
      'current' as scope,
      b.due_on as sort_on
    from app_finance.bnpl_purchase_obligation_statuses b
    where b.user_id = v_user_id and b.account_id = p_account_id
      and b.remaining_minor > 0 and b.due_on <= v_as_of
  ),
  next_due as (
    select min(due_on) as due_on from (
      select s.due_on
      from app_finance.installment_due_statuses s
      where s.user_id = v_user_id and s.account_id = p_account_id
        and s.plan_status = 'active' and s.remaining_minor > 0
        and s.due_on > v_as_of
      union all
      select b.due_on
      from app_finance.bnpl_purchase_obligation_statuses b
      where b.user_id = v_user_id and b.account_id = p_account_id
        and b.remaining_minor > 0 and b.due_on > v_as_of
    ) upcoming
    where not exists (select 1 from due_components)
      and not exists (select 1 from bnpl_components)
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
  bnpl_next_components as (
    select
      'bnpl_purchase' as component_type,
      b.obligation_id as component_id,
      null::uuid as plan_id,
      null::uuid as cycle_id,
      b.transaction_id,
      coalesce(b.title, b.counterparty) as title,
      'bnpl_purchase' as activity_kind,
      null::text as fee_type,
      null::integer as sequence_number,
      null::integer as installment_count,
      b.purchased_on as component_on,
      b.amount_minor,
      b.paid_minor,
      b.remaining_minor,
      b.payment_status,
      'next_due' as scope,
      b.due_on as sort_on
    from app_finance.bnpl_purchase_obligation_statuses b
    join next_due n on n.due_on = b.due_on
    where b.user_id = v_user_id and b.account_id = p_account_id
      and b.remaining_minor > 0
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
    select * from bnpl_components
    union all
    select * from bnpl_next_components
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
      'due_on', sort_on,
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
$function$;

CREATE OR REPLACE FUNCTION app_finance.facility_month_due_breakdown(p_account_id uuid, p_month_start date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
  bnpl_components as (
    select
      'bnpl_purchase' as component_type,
      b.obligation_id as component_id,
      null::uuid as plan_id,
      null::uuid as cycle_id,
      b.transaction_id,
      coalesce(b.title, b.counterparty) as title,
      'bnpl_purchase' as activity_kind,
      null::text as fee_type,
      null::integer as sequence_number,
      null::integer as installment_count,
      b.purchased_on as component_on,
      b.due_on,
      b.amount_minor,
      b.paid_minor,
      b.remaining_minor,
      b.payment_status
    from app_finance.bnpl_purchase_obligation_statuses b
    where b.user_id = v_user_id and b.account_id = p_account_id
      and b.due_on between v_month_start and v_month_end
  ),
  all_components as (
    select * from installment_components
    union all
    select * from bnpl_components
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
$function$;


-- ---------------------------------------------------------------------------
-- 9. Activity classification knows a settled ordinary BNPL purchase
--
-- An ordinary purchase stays editable through the canonical transaction
-- editor until money is applied to it. Once an allocation exists the server
-- refuses the edit (bnpl_purchase_settled), so the capability the client
-- reads must say so too rather than offering an action that cannot succeed.
-- Only the is_settled expression changes; every other column is the current
-- definition verbatim.
-- ---------------------------------------------------------------------------
create or replace view app_finance.facility_activity_items
with (security_invoker = on) as
SELECT t.id AS transaction_id,
    t.user_id,
    a.id AS account_id,
    t.transaction_kind,
    t.occurred_on,
    t.amount_minor,
    t.currency_code,
    t.category_id,
    t.title,
    t.notes,
    t.counterparty,
    t.sort_at,
    COALESCE(purchase.id, down.id) AS plan_id,
        CASE
            WHEN t.facility_reversal_of_id IS NOT NULL THEN 'repayment_reversal'::text
            WHEN purchase.id IS NOT NULL THEN 'installment_purchase'::text
            WHEN down.id IS NOT NULL THEN 'installment_down_payment'::text
            WHEN fr.fee_type = 'purchase_interest'::app_finance.card_fee_type THEN 'purchase_interest'::text
            WHEN fee.transaction_id IS NOT NULL THEN 'fee_charge'::text
            WHEN t.transaction_kind = 'transfer'::app_finance.transaction_kind AND t.destination_account_id = a.id THEN 'facility_repayment'::text
            WHEN t.transaction_kind = 'transfer'::app_finance.transaction_kind THEN 'repayment_reversal'::text
            WHEN t.transaction_kind = 'expense'::app_finance.transaction_kind AND (EXISTS ( SELECT 1
               FROM app_finance.installment_dues d
              WHERE d.interest_transaction_id = t.id)) THEN 'installment_interest'::text
            WHEN t.transaction_kind = 'expense'::app_finance.transaction_kind THEN 'ordinary_expense'::text
            ELSE 'other'::text
        END AS activity_kind,
    (EXISTS ( SELECT 1
           FROM app_finance.credit_card_statement_items i
             JOIN app_finance.credit_card_statement_allocations al ON al.cycle_id = i.cycle_id
          WHERE i.transaction_id = t.id)
     OR EXISTS ( SELECT 1
           FROM app_finance.bnpl_purchase_obligations o
             JOIN app_finance.bnpl_purchase_payment_allocations ba ON ba.obligation_id = o.id
          WHERE o.transaction_id = t.id)) AS is_settled,
    fr.fee_type
   FROM app_finance.financial_transactions t
     JOIN app_finance.accounts a ON (a.id = t.source_account_id OR a.id = t.destination_account_id) AND a.user_id = t.user_id
     LEFT JOIN app_finance.installment_plans purchase ON purchase.purchase_transaction_id = t.id
     LEFT JOIN app_finance.installment_plans down ON down.down_payment_transaction_id = t.id
     LEFT JOIN app_finance.credit_card_fee_charges fee ON fee.transaction_id = t.id
     LEFT JOIN app_finance.credit_card_fee_rules fr ON fr.id = fee.rule_id
  WHERE app_finance.account_role(a.account_type) = 'liability'::text;

notify pgrst, 'reload schema';
