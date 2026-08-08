-- Non-FX credit-card reconciliation foundations.
--
-- The ledger remains authoritative. Reducing-balance plans book principal
-- (and non-interest financed fees) when created/imported; contractual future
-- interest is retained in the schedule and materialized only when due. A
-- historical repayment can therefore be reclassified without changing the
-- current liability twice by pairing it with an explicit pre-tracking
-- obligation.

do $$
begin
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'min_payment_percentage_basis') then
    create type app_finance.min_payment_percentage_basis as enum
      ('statement_total', 'revolving_noninstallment');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_interest_rate_period') then
    create type app_finance.card_interest_rate_period as enum
      ('daily', 'monthly', 'annual');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_interest_accrual_method') then
    create type app_finance.card_interest_accrual_method as enum
      ('bank_posted_manual', 'statement_based', 'daily_accrual');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_interest_start') then
    create type app_finance.card_interest_start as enum
      ('purchase_date', 'statement_close', 'payment_due', 'grace_expiry');
  end if;
end
$$;

grant usage on type app_finance.min_payment_percentage_basis,
  app_finance.card_interest_rate_period,
  app_finance.card_interest_accrual_method,
  app_finance.card_interest_start to authenticated, service_role;

-- Billing and minimum-payment concepts are intentionally orthogonal.
alter table app_finance.credit_facility_settings
  drop constraint if exists credit_facility_settings_statement_day_check;
alter table app_finance.credit_facility_settings
  add constraint credit_facility_settings_statement_day_check
  check (statement_day between 1 and 31);
alter table app_finance.credit_facility_settings
  drop constraint if exists credit_facility_settings_default_due_day_check;
alter table app_finance.credit_facility_settings
  add constraint credit_facility_settings_default_due_day_check
  check (default_due_day between 1 and 31);

alter table app_finance.credit_facility_settings
  add column if not exists installment_due_day smallint,
  add column if not exists grace_period_days smallint not null default 0,
  add column if not exists min_payment_percentage_basis
    app_finance.min_payment_percentage_basis not null default 'statement_total',
  add column if not exists min_payment_include_installment_dues boolean
    not null default false,
  add column if not exists min_payment_include_bank_fees boolean
    not null default true,
  add column if not exists min_payment_include_overdue boolean
    not null default false,
  add column if not exists min_payment_fixed_floor_minor bigint;

alter table app_finance.credit_facility_settings
  drop constraint if exists credit_facility_settings_installment_due_day_check;
alter table app_finance.credit_facility_settings
  add constraint credit_facility_settings_installment_due_day_check
    check (installment_due_day is null or installment_due_day between 1 and 31),
  add constraint credit_facility_settings_grace_period_days_check
    check (grace_period_days between 0 and 90),
  add constraint credit_facility_settings_min_floor_check
    check (min_payment_fixed_floor_minor is null
      or min_payment_fixed_floor_minor >= 0);

comment on column app_finance.credit_facility_settings.statement_day is
  'Statement closing day. Day 31 means end of month and is clamped in short months.';
comment on column app_finance.credit_facility_settings.default_due_day is
  'Card payment due day in the month following statement close.';
comment on column app_finance.credit_facility_settings.installment_due_day is
  'Optional product default for installment posting/due dates; independent of statement close.';

-- Exact-money amortization components and explicit historical-import state.
alter table app_finance.installment_dues
  add column if not exists opening_principal_minor bigint,
  add column if not exists principal_minor bigint,
  add column if not exists interest_minor bigint,
  add column if not exists financing_fee_minor bigint,
  add column if not exists closing_principal_minor bigint,
  add column if not exists interest_transaction_id uuid;

alter table app_finance.installment_dues
  add constraint installment_dues_components_nonnegative check (
    opening_principal_minor is null or opening_principal_minor >= 0
  ),
  add constraint installment_dues_principal_nonnegative check (
    principal_minor is null or principal_minor >= 0
  ),
  add constraint installment_dues_interest_nonnegative check (
    interest_minor is null or interest_minor >= 0
  ),
  add constraint installment_dues_fee_nonnegative check (
    financing_fee_minor is null or financing_fee_minor >= 0
  ),
  add constraint installment_dues_closing_nonnegative check (
    closing_principal_minor is null or closing_principal_minor >= 0
  ),
  add constraint installment_dues_interest_tx_owner_fk
    foreign key (interest_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete set null (interest_transaction_id);

create unique index if not exists idx_installment_due_interest_tx
  on app_finance.installment_dues (interest_transaction_id)
  where interest_transaction_id is not null;

alter table app_finance.installment_plans
  add column if not exists import_as_of date,
  add column if not exists paid_through_on date,
  add column if not exists current_installment_posted boolean
    not null default false,
  add column if not exists bank_reported_principal_minor bigint,
  add column if not exists reconciliation_as_of date,
  add column if not exists reconciliation_paid_installments integer,
  add column if not exists reconciliation_notes text,
  add column if not exists needs_reconciliation boolean not null default false;

alter table app_finance.installment_plans
  add constraint installment_plans_bank_principal_positive check (
    bank_reported_principal_minor is null
      or bank_reported_principal_minor >= 0
  ),
  add constraint installment_plans_reconciled_count_range check (
    reconciliation_paid_installments is null
      or reconciliation_paid_installments between 0 and installment_count
  ),
  add constraint installment_plans_reconciliation_note_length check (
    reconciliation_notes is null or char_length(reconciliation_notes) <= 1000
  );

-- Effective-dated purchase-interest configuration lives on rule versions.
alter table app_finance.credit_card_fee_rule_versions
  add column if not exists interest_rate_period
    app_finance.card_interest_rate_period,
  add column if not exists interest_accrual_method
    app_finance.card_interest_accrual_method,
  add column if not exists interest_starts app_finance.card_interest_start,
  add column if not exists grace_period_days smallint,
  add column if not exists grace_applies boolean;

alter table app_finance.credit_card_fee_rule_versions
  add constraint fee_rule_versions_interest_grace_days check (
    grace_period_days is null or grace_period_days between 0 and 90
  );

alter table app_finance.credit_card_fee_charges
  add column if not exists reconciliation_key text;
create unique index if not exists idx_fee_charges_reconciliation_key
  on app_finance.credit_card_fee_charges (user_id, reconciliation_key)
  where reconciliation_key is not null;

-- Explicit pre-tracking liabilities paired with corrected historical
-- repayments. These rows are not expenses and never appear in reports.
create table if not exists app_finance.historical_facility_obligations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  settled_by_transaction_id uuid not null,
  occurred_on date not null,
  amount_minor bigint not null check (amount_minor > 0),
  repair_key text not null check (char_length(repair_key) between 1 and 160),
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  constraint historical_obligations_owner_unique unique (id, user_id),
  constraint historical_obligations_repair_unique unique (user_id, repair_key),
  constraint historical_obligations_payment_unique unique (settled_by_transaction_id),
  constraint historical_obligations_account_owner_fk
    foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id) on delete cascade,
  constraint historical_obligations_payment_owner_fk
    foreign key (settled_by_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
);

create index if not exists idx_historical_obligations_account
  on app_finance.historical_facility_obligations (account_id, user_id);

alter table app_finance.historical_facility_obligations enable row level security;
create policy historical_facility_obligations_select
  on app_finance.historical_facility_obligations
  for select to authenticated using ((select auth.uid()) = user_id);
create policy historical_facility_obligations_insert
  on app_finance.historical_facility_obligations
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy historical_facility_obligations_delete
  on app_finance.historical_facility_obligations
  for delete to authenticated using ((select auth.uid()) = user_id);

create or replace function app_private.protect_historical_facility_obligations()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app_finance.facility_internal', true), '') = 'on'
    or (select auth.uid()) is null then
    return coalesce(new, old);
  end if;
  raise exception 'historical_obligation_locked: use the facility repair flow';
end;
$$;

create trigger trg_protect_historical_facility_obligations
  before insert or update or delete
  on app_finance.historical_facility_obligations
  for each row execute function
    app_private.protect_historical_facility_obligations();

create or replace function app_finance.facility_outstanding_minor(
  p_account_id uuid
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select a.opening_balance_minor
    + coalesce((
      select sum(o.amount_minor)
      from app_finance.historical_facility_obligations o
      where o.account_id = a.id
    ), 0)
    - coalesce((
      select sum(case when t.destination_account_id = a.id
        then t.amount_minor else -t.amount_minor end)
      from app_finance.financial_transactions t
      where t.source_account_id = a.id or t.destination_account_id = a.id
    ), 0)
  from app_finance.accounts a
  where a.id = p_account_id;
$$;

comment on function app_finance.facility_outstanding_minor(uuid) is
  'Positive current debt: opening/imported obligations plus ledger charges minus repayments.';

-- One deterministic minor-unit schedule. The final period absorbs only the
-- rounding residue needed to make principal, interest, fees, and payments
-- reconcile exactly to their contractual totals.
create or replace function app_finance.installment_amortization_schedule(
  p_principal_minor bigint,
  p_interest_minor bigint,
  p_financing_fee_minor bigint,
  p_count integer,
  p_rate_basis_points integer,
  p_rate_period app_finance.interest_rate_period,
  p_interest_method app_finance.interest_method
)
returns table (
  sequence_number integer,
  opening_principal_minor bigint,
  interest_minor bigint,
  principal_minor bigint,
  financing_fee_minor bigint,
  scheduled_payment_minor bigint,
  closing_principal_minor bigint
)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_opening bigint := p_principal_minor;
  v_principal_used bigint := 0;
  v_interest_used bigint := 0;
  v_fee_used bigint := 0;
  v_total bigint;
  v_payment bigint;
  v_interest bigint;
  v_principal bigint;
  v_fee bigint;
  v_rate numeric;
begin
  if p_principal_minor <= 0 or p_count < 1 or p_count > 120
    or p_interest_minor < 0 or p_financing_fee_minor < 0 then
    raise exception 'invalid_amortization_inputs';
  end if;
  v_total := p_principal_minor + p_interest_minor + p_financing_fee_minor;
  v_rate := p_rate_basis_points::numeric / 10000;
  if p_rate_period = 'annual' then
    v_rate := v_rate / 12;
  end if;

  for v_seq in 1..p_count loop
    if p_interest_method = 'reducing' then
      v_payment := v_total / p_count
        + case when v_seq <= v_total % p_count then 1 else 0 end;
      v_fee := p_financing_fee_minor / p_count
        + case when v_seq <= p_financing_fee_minor % p_count then 1 else 0 end;
      if v_seq < p_count then
        v_interest := least(
          round(v_opening * v_rate)::bigint,
          p_interest_minor - v_interest_used
        );
        v_principal := v_payment - v_fee - v_interest;
        if v_principal <= 0 or v_principal > v_opening then
          raise exception 'invalid_amortization_payment';
        end if;
      else
        v_principal := v_opening;
        v_interest := p_interest_minor - v_interest_used;
        v_fee := p_financing_fee_minor - v_fee_used;
        v_payment := v_principal + v_interest + v_fee;
      end if;
    else
      v_principal := p_principal_minor / p_count
        + case when v_seq <= p_principal_minor % p_count then 1 else 0 end;
      v_interest := p_interest_minor / p_count
        + case when v_seq <= p_interest_minor % p_count then 1 else 0 end;
      v_fee := p_financing_fee_minor / p_count
        + case when v_seq <= p_financing_fee_minor % p_count then 1 else 0 end;
      v_payment := v_principal + v_interest + v_fee;
    end if;

    sequence_number := v_seq;
    opening_principal_minor := v_opening;
    interest_minor := v_interest;
    principal_minor := v_principal;
    financing_fee_minor := v_fee;
    scheduled_payment_minor := v_payment;
    closing_principal_minor := v_opening - v_principal;
    return next;

    v_opening := v_opening - v_principal;
    v_principal_used := v_principal_used + v_principal;
    v_interest_used := v_interest_used + v_interest;
    v_fee_used := v_fee_used + v_fee;
  end loop;

  if v_opening <> 0 or v_principal_used <> p_principal_minor
    or v_interest_used <> p_interest_minor
    or v_fee_used <> p_financing_fee_minor then
    raise exception 'amortization_did_not_reconcile';
  end if;
end;
$$;

revoke execute on function app_finance.installment_amortization_schedule(
  bigint, bigint, bigint, integer, integer,
  app_finance.interest_rate_period, app_finance.interest_method
) from public, anon;
grant execute on function app_finance.installment_amortization_schedule(
  bigint, bigint, bigint, integer, integer,
  app_finance.interest_rate_period, app_finance.interest_method
) to authenticated, service_role;

-- Existing plans have complete contractual fields, so schedule components can
-- be backfilled without changing any ledger amount or presettled state.
update app_finance.installment_dues d
set opening_principal_minor = x.opening_principal_minor,
  principal_minor = x.principal_minor,
  interest_minor = x.interest_minor,
  financing_fee_minor = x.financing_fee_minor,
  closing_principal_minor = x.closing_principal_minor,
  amount_minor = x.scheduled_payment_minor
from app_finance.installment_plans p
cross join lateral app_finance.installment_amortization_schedule(
  p.financed_principal_minor,
  p.interest_minor,
  p.financing_fees_minor - p.interest_minor,
  p.installment_count,
  p.interest_rate_basis_points,
  p.interest_rate_period,
  p.interest_method
) x
where d.plan_id = p.id and d.sequence_number = x.sequence_number;

-- Keep every future write component-complete, including the existing
-- restructure RPC which replaces only the unpaid tail of a schedule. Any
-- restructured amount above remaining principal is an explicit financing
-- fee; it is never silently relabeled as principal or future interest.
create or replace function app_private.populate_installment_due_components()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_financed_principal bigint;
  v_principal_used bigint;
begin
  if new.opening_principal_minor is not null
    and new.principal_minor is not null
    and new.interest_minor is not null
    and new.financing_fee_minor is not null
    and new.closing_principal_minor is not null then
    return new;
  end if;

  select p.financed_principal_minor into v_financed_principal
  from app_finance.installment_plans p
  where p.id = new.plan_id and p.user_id = new.user_id;
  if v_financed_principal is null then
    raise exception 'invalid_plan: installment plan not found';
  end if;

  select coalesce(sum(d.principal_minor), 0)::bigint into v_principal_used
  from app_finance.installment_dues d
  where d.plan_id = new.plan_id and d.user_id = new.user_id;

  new.opening_principal_minor := greatest(
    v_financed_principal - v_principal_used, 0
  );
  new.principal_minor := least(
    new.amount_minor, new.opening_principal_minor
  );
  new.interest_minor := 0;
  new.financing_fee_minor := new.amount_minor - new.principal_minor;
  new.closing_principal_minor :=
    new.opening_principal_minor - new.principal_minor;
  return new;
end;
$$;

drop trigger if exists trg_populate_installment_due_components
  on app_finance.installment_dues;
create trigger trg_populate_installment_due_components
before insert on app_finance.installment_dues
for each row execute function app_private.populate_installment_due_components();

alter table app_finance.installment_dues
  alter column opening_principal_minor set not null,
  alter column principal_minor set not null,
  alter column interest_minor set not null,
  alter column financing_fee_minor set not null,
  alter column closing_principal_minor set not null;

drop view if exists app_finance.credit_facility_summaries;
drop view if exists app_finance.installment_plan_summaries;
drop view if exists app_finance.installment_due_statuses;

create view app_finance.installment_due_statuses
with (security_invoker = on) as
  select
    d.id,
    d.user_id,
    d.plan_id,
    p.account_id,
    d.sequence_number,
    d.due_on,
    d.amount_minor,
    p.currency_code,
    p.title as plan_title,
    p.status as plan_status,
    d.is_presettled,
    d.opening_principal_minor,
    d.principal_minor,
    d.interest_minor,
    d.financing_fee_minor,
    d.closing_principal_minor,
    d.interest_transaction_id,
    (coalesce(alloc.paid_minor, 0)
      + case when d.is_presettled then d.amount_minor else 0 end)::bigint
      as paid_minor,
    greatest(d.amount_minor - coalesce(alloc.paid_minor, 0)
      - case when d.is_presettled then d.amount_minor else 0 end, 0)::bigint
      as remaining_minor,
    case
      when d.is_presettled then d.principal_minor
      else least(d.principal_minor,
        greatest(coalesce(alloc.paid_minor, 0)
          - d.interest_minor - d.financing_fee_minor, 0))
    end::bigint as paid_principal_minor,
    case
      when p.status = 'cancelled' then 'cancelled'
      when d.is_presettled or coalesce(alloc.paid_minor, 0) >= d.amount_minor
        then 'paid'
      when d.due_on < current_date then 'overdue'
      when d.due_on = current_date then 'due_today'
      when coalesce(alloc.paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as due_status
  from app_finance.installment_dues d
  join app_finance.installment_plans p on p.id = d.plan_id
  left join (
    select due_id, sum(amount_minor)::bigint as paid_minor
    from app_finance.installment_payment_allocations
    group by due_id
  ) alloc on alloc.due_id = d.id;

create view app_finance.installment_plan_summaries
with (security_invoker = on) as
  select
    p.id, p.user_id, p.account_id, p.title, p.category_id, p.purchased_on,
    p.first_due_on, p.installment_count, p.purchase_price_minor,
    p.down_payment_minor, p.financed_principal_minor,
    p.financing_fees_minor, p.interest_minor, p.total_payable_minor,
    p.currency_code, p.status, p.pricing_method,
    p.interest_rate_basis_points, p.interest_rate_period,
    p.interest_method, p.origin, p.revision, p.notes,
    p.purchase_transaction_id, p.down_payment_transaction_id, p.created_at,
    coalesce(t.paid_minor, 0)::bigint as paid_minor,
    case when p.interest_method = 'reducing'
      then greatest(coalesce(r.remaining_principal_minor, 0)
        + coalesce(t.remaining_financing_fee_minor, 0)
        + coalesce(t.accrued_interest_remaining_minor, 0), 0)
      else coalesce(t.remaining_scheduled_payments_minor, 0)
    end::bigint as remaining_minor,
    n.next_due_on,
    n.next_due_amount_minor,
    coalesce(r.remaining_principal_minor, 0)::bigint
      as remaining_principal_minor,
    coalesce(t.remaining_scheduled_payments_minor, 0)::bigint
      as remaining_scheduled_payments_minor,
    coalesce(t.remaining_future_interest_minor, 0)::bigint
      as remaining_future_interest_minor,
    coalesce(t.accrued_interest_remaining_minor, 0)::bigint
      as accrued_interest_remaining_minor,
    coalesce(t.remaining_financing_fee_minor, 0)::bigint
      as remaining_financing_fee_minor,
    coalesce(t.paid_installments, 0)::integer as paid_installments,
    case when p.current_installment_posted
      and coalesce(t.total_unpaid_installments, 0) > 0 then 1 else 0 end::integer
      as current_posted_installments,
    greatest(coalesce(t.total_unpaid_installments, 0)
      - case when p.current_installment_posted then 1 else 0 end, 0)::integer
      as future_installments,
    coalesce(t.total_unpaid_installments, 0)::integer
      as total_unpaid_installments,
    p.import_as_of, p.paid_through_on, p.current_installment_posted,
    p.bank_reported_principal_minor, p.reconciliation_as_of,
    p.reconciliation_paid_installments, p.reconciliation_notes,
    p.needs_reconciliation
  from app_finance.installment_plans p
  left join lateral (
    select
      sum(s.paid_minor)::bigint as paid_minor,
      sum(s.remaining_minor)::bigint as remaining_scheduled_payments_minor,
      sum(s.financing_fee_minor - least(s.financing_fee_minor,
        greatest(s.paid_minor - s.interest_minor, 0)))::bigint
        as remaining_financing_fee_minor,
      (sum(case when s.interest_transaction_id is null
        then s.interest_minor else 0 end)
        filter (where s.remaining_minor > 0))::bigint
        as remaining_future_interest_minor,
      sum(case when s.interest_transaction_id is not null
        then least(s.interest_minor, s.remaining_minor) else 0 end)::bigint
        as accrued_interest_remaining_minor,
      count(*) filter (where s.remaining_minor = 0)::integer
        as paid_installments,
      count(*) filter (where s.remaining_minor > 0)::integer
        as total_unpaid_installments
    from app_finance.installment_due_statuses s
    where s.plan_id = p.id
  ) t on true
  left join lateral (
    select greatest(
      case when p.bank_reported_principal_minor is not null then
        p.bank_reported_principal_minor - coalesce(sum(
          case when s.sequence_number
              > coalesce(p.reconciliation_paid_installments, 0)
            then s.paid_principal_minor else 0 end
        ), 0)
      else sum(s.principal_minor - s.paid_principal_minor) end,
      0
    )::bigint as remaining_principal_minor
    from app_finance.installment_due_statuses s
    where s.plan_id = p.id
  ) r on true
  left join lateral (
    select s.due_on as next_due_on,
      s.remaining_minor as next_due_amount_minor
    from app_finance.installment_due_statuses s
    where s.plan_id = p.id and s.remaining_minor > 0
    order by s.due_on, s.sequence_number limit 1
  ) n on true;

comment on column app_finance.installment_plan_summaries.remaining_minor is
  'Compatibility field: current accrued obligation for reducing plans; remaining scheduled cash payments for other plans. Prefer explicit component columns.';

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
    least(
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
    )::bigint as minimum_due_minor,
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
    end as obligation_status
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
  ) od on true;

comment on column app_finance.credit_card_statement_summaries.charges_minor is
  'Compatibility field containing card statement items only. Use card_charges_minor or total_statement_due_minor for explicit semantics.';
comment on column app_finance.credit_card_statement_summaries.remaining_minor is
  'Compatibility field for unpaid card statement items. Use total_remaining_minor for the combined card and installment obligation.';

create view app_finance.credit_facility_summaries
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
      sum(ds.remaining_minor) filter (where ds.due_on <= current_date)
        as due_now_minor,
      sum(ds.remaining_minor) filter (where ds.due_on < current_date)
        as overdue_minor,
      min(ds.due_on) filter (where ds.remaining_minor > 0) as next_due_on,
      (array_agg(ds.remaining_minor order by ds.due_on, ds.sequence_number)
        filter (where ds.remaining_minor > 0))[1] as next_due_amount_minor,
      sum(ds.remaining_minor) filter (where ds.due_on
        <= (current_date + interval '1 month')::date) as upcoming_due_minor
    from app_finance.installment_due_statuses ds
    where ds.account_id = a.id and ds.plan_status = 'active'
      and ds.remaining_minor > 0
      and not (a.account_type = 'credit_card' and exists (
        select 1 from app_finance.credit_card_statement_cycles sc
        where sc.account_id = a.id and sc.due_on = ds.due_on
      ))
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

-- Relink only mutable statement history. A cycle with any payment allocation
-- is settled history and is never rewritten by a settings edit.
create or replace function app_finance.rebuild_credit_card_statement_cycles(
  p_account_id uuid,
  p_from_on date default null,
  p_through_on date default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
  v_item record;
  v_count integer := 0;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  select a.id, a.account_type into v_account
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id
  for update;
  if v_account is null or v_account.account_type <> 'credit_card' then
    raise exception 'invalid_account: configured credit card required';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  for v_item in
    select si.transaction_id, t.occurred_on, t.amount_minor
    from app_finance.credit_card_statement_items si
    join app_finance.credit_card_statement_cycles sc on sc.id = si.cycle_id
    join app_finance.financial_transactions t on t.id = si.transaction_id
    where sc.account_id = p_account_id and si.user_id = v_user_id
      and (p_from_on is null or t.occurred_on >= p_from_on)
      and (p_through_on is null or t.occurred_on <= p_through_on)
      and not exists (
        select 1 from app_finance.credit_card_statement_allocations sa
        where sa.cycle_id = sc.id
      )
    order by t.occurred_on, si.transaction_id
  loop
    perform app_finance.relink_card_statement_item(
      v_user_id, v_item.transaction_id, p_account_id,
      v_item.occurred_on, v_item.amount_minor
    );
    update app_finance.credit_card_fee_charges fc
    set statement_cycle_id = si.cycle_id
    from app_finance.credit_card_statement_items si
    where fc.transaction_id = v_item.transaction_id
      and fc.user_id = v_user_id
      and si.transaction_id = v_item.transaction_id;
    v_count := v_count + 1;
  end loop;

  delete from app_finance.credit_card_statement_cycles sc
  where sc.account_id = p_account_id and sc.user_id = v_user_id
    and not exists (select 1 from app_finance.credit_card_statement_items si
      where si.cycle_id = sc.id)
    and not exists (select 1 from app_finance.credit_card_statement_allocations sa
      where sa.cycle_id = sc.id);

  perform set_config('app_finance.facility_internal', '', true);
  return v_count;
end;
$$;

revoke execute on function app_finance.rebuild_credit_card_statement_cycles(
  uuid, date, date
) from public, anon;
grant execute on function app_finance.rebuild_credit_card_statement_cycles(
  uuid, date, date
) to authenticated, service_role;

drop function if exists app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text, integer
);

create function app_finance.save_credit_facility(
  p_name text,
  p_account_type app_finance.account_type,
  p_currency_code text,
  p_credit_limit_minor bigint,
  p_default_due_day smallint,
  p_statement_day smallint default null,
  p_last_four_digits text default null,
  p_reminder_lead_days smallint default 3,
  p_notes text default null,
  p_account_id uuid default null,
  p_facility_status app_finance.facility_status default 'active',
  p_min_payment_method app_finance.min_payment_method default 'full',
  p_min_payment_fixed_minor bigint default null,
  p_min_payment_basis_points integer default null,
  p_color_hex text default null,
  p_fx_markup_basis_points integer default null,
  p_installment_due_day smallint default null,
  p_grace_period_days smallint default 0,
  p_min_payment_percentage_basis
    app_finance.min_payment_percentage_basis default 'statement_total',
  p_min_payment_include_installment_dues boolean default false,
  p_min_payment_include_bank_fees boolean default true,
  p_min_payment_include_overdue boolean default false,
  p_min_payment_fixed_floor_minor bigint default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_color text := nullif(upper(trim(coalesce(p_color_hex, ''))), '');
  v_old_statement_day smallint;
  v_old_due_day smallint;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if app_finance.account_role(p_account_type) <> 'liability' then
    raise exception 'invalid_account: facility settings require a liability account';
  end if;
  if v_color is not null and v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'invalid_color: use a #RRGGBB value';
  end if;

  if p_account_id is null then
    insert into app_finance.accounts (
      user_id, name, account_type, currency_code, opening_balance_minor,
      is_default, allow_negative_balance, notes
    ) values (
      v_user_id, p_name, p_account_type, p_currency_code, 0,
      false, false, p_notes
    ) returning id into v_account_id;
  else
    select statement_day, default_due_day
      into v_old_statement_day, v_old_due_day
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
    update app_finance.accounts set name = p_name,
      account_type = p_account_type, notes = p_notes
    where id = p_account_id and user_id = v_user_id and not is_archived
    returning id into v_account_id;
    if v_account_id is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
  end if;

  insert into app_finance.credit_facility_settings (
    account_id, user_id, credit_limit_minor, statement_day, default_due_day,
    last_four_digits, reminder_lead_days, facility_status,
    min_payment_method, min_payment_fixed_minor, min_payment_basis_points,
    color_hex, installment_due_day, grace_period_days,
    min_payment_percentage_basis, min_payment_include_installment_dues,
    min_payment_include_bank_fees, min_payment_include_overdue,
    min_payment_fixed_floor_minor, fx_markup_basis_points
  ) values (
    v_account_id, v_user_id, p_credit_limit_minor, p_statement_day,
    p_default_due_day, p_last_four_digits, coalesce(p_reminder_lead_days, 3),
    coalesce(p_facility_status, 'active'),
    coalesce(p_min_payment_method, 'full'), p_min_payment_fixed_minor,
    p_min_payment_basis_points, v_color, p_installment_due_day,
    coalesce(p_grace_period_days, 0),
    coalesce(p_min_payment_percentage_basis, 'statement_total'),
    coalesce(p_min_payment_include_installment_dues, false),
    coalesce(p_min_payment_include_bank_fees, true),
    coalesce(p_min_payment_include_overdue, false),
    p_min_payment_fixed_floor_minor, p_fx_markup_basis_points
  ) on conflict (account_id) do update set
    credit_limit_minor = excluded.credit_limit_minor,
    statement_day = excluded.statement_day,
    default_due_day = excluded.default_due_day,
    last_four_digits = excluded.last_four_digits,
    reminder_lead_days = excluded.reminder_lead_days,
    facility_status = excluded.facility_status,
    min_payment_method = excluded.min_payment_method,
    min_payment_fixed_minor = excluded.min_payment_fixed_minor,
    min_payment_basis_points = excluded.min_payment_basis_points,
    color_hex = excluded.color_hex,
    installment_due_day = excluded.installment_due_day,
    grace_period_days = excluded.grace_period_days,
    min_payment_percentage_basis = excluded.min_payment_percentage_basis,
    min_payment_include_installment_dues =
      excluded.min_payment_include_installment_dues,
    min_payment_include_bank_fees = excluded.min_payment_include_bank_fees,
    min_payment_include_overdue = excluded.min_payment_include_overdue,
    min_payment_fixed_floor_minor = excluded.min_payment_fixed_floor_minor,
    fx_markup_basis_points = excluded.fx_markup_basis_points;

  if p_account_id is not null and p_account_type = 'credit_card'
    and (v_old_statement_day is distinct from p_statement_day
      or v_old_due_day is distinct from p_default_due_day) then
    perform app_finance.rebuild_credit_card_statement_cycles(v_account_id);
  end if;
  return v_account_id;
end;
$$;

revoke execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text, integer, smallint, smallint,
  app_finance.min_payment_percentage_basis, boolean, boolean, boolean, bigint
) from public, anon;
grant execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text, integer, smallint, smallint,
  app_finance.min_payment_percentage_basis, boolean, boolean, boolean, bigint
) to authenticated, service_role;

drop function if exists app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  bigint, date, integer
);

create function app_finance.create_installment_plan(
  p_account_id uuid,
  p_title text,
  p_category_id uuid,
  p_purchased_on date,
  p_purchase_price_minor bigint,
  p_installment_count integer,
  p_first_due_on date,
  p_down_payment_minor bigint default 0,
  p_down_payment_account_id uuid default null,
  p_financing_fees_minor bigint default null,
  p_total_payable_minor bigint default null,
  p_notes text default null,
  p_plan_id uuid default null,
  p_pricing_method app_finance.plan_pricing_method default 'manual_fees',
  p_monthly_payment_minor bigint default null,
  p_interest_rate_basis_points integer default 0,
  p_interest_rate_period app_finance.interest_rate_period default 'monthly',
  p_interest_method app_finance.interest_method default 'flat',
  p_financed_fees_minor bigint default 0,
  p_upfront_fees_minor bigint default 0,
  p_down_paid_on date default null,
  p_paid_installments integer default 0,
  p_import_as_of date default null,
  p_paid_through_on date default null,
  p_current_installment_posted boolean default false,
  p_allow_future_presettlement boolean default false,
  p_bank_reported_principal_minor bigint default null,
  p_reconciliation_as_of date default null,
  p_reconciliation_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_facility record;
  v_settings record;
  v_down_account record;
  v_pricing app_finance.plan_pricing_method := p_pricing_method;
  v_rate_bp integer := p_interest_rate_basis_points;
  v_rate_period app_finance.interest_rate_period := p_interest_rate_period;
  v_interest_method app_finance.interest_method := p_interest_method;
  v_tenor record;
  v_financing record;
  v_plan_id uuid;
  v_purchase_tx_id uuid;
  v_down_tx_id uuid;
  v_outstanding bigint;
  v_charge_minor bigint;
  v_paid_count integer := coalesce(p_paid_installments, 0);
  v_derived_paid_count integer;
  v_origin app_finance.plan_origin;
  v_as_of date;
  v_non_interest_fees bigint;
  v_schedule record;
  v_reconciled_opening bigint;
  v_reconciled_component bigint;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_plan_id is not null then
    select id into v_plan_id from app_finance.installment_plans
    where id = p_plan_id and user_id = v_user_id;
    if v_plan_id is not null then return v_plan_id; end if;
  end if;
  if p_purchase_price_minor is null or p_purchase_price_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if coalesce(p_down_payment_minor, 0) < 0
    or coalesce(p_down_payment_minor, 0) >= p_purchase_price_minor then
    raise exception 'invalid_amount: down payment must be below purchase price';
  end if;
  if p_installment_count is null or p_installment_count not between 1 and 120 then
    raise exception 'invalid_installments: choose between 1 and 120 installments';
  end if;
  if p_first_due_on < p_purchased_on then
    raise exception 'invalid_date: first due date cannot precede purchase';
  end if;
  if v_paid_count < 0 or v_paid_count >= p_installment_count then
    raise exception 'invalid_paid_count: paid installments must be fewer than total';
  end if;
  if p_bank_reported_principal_minor is not null
    and p_bank_reported_principal_minor < 0 then
    raise exception 'invalid_amount: bank outstanding cannot be negative';
  end if;

  select a.id, a.currency_code, a.account_type into v_facility
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
  for update;
  if v_facility is null
    or app_finance.account_role(v_facility.account_type) <> 'liability' then
    raise exception 'invalid_account: liability account required';
  end if;
  select credit_limit_minor, facility_status into v_settings
  from app_finance.credit_facility_settings
  where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null or v_settings.facility_status <> 'active' then
    raise exception 'facility_not_active: configure an active facility first';
  end if;
  if not exists (select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense') then
    raise exception 'invalid_category: expense category required';
  end if;

  if v_pricing = 'card_tenor_default' then
    select * into v_tenor from app_finance.resolve_tenor_rate(
      p_account_id, v_user_id, p_installment_count
    );
    if not found then raise exception 'no_tenor_rate: no rate for tenor'; end if;
    v_pricing := 'interest_rate';
    v_rate_bp := v_tenor.rate_basis_points;
    v_rate_period := v_tenor.rate_period;
    v_interest_method := v_tenor.interest_method;
  end if;

  select * into v_financing from app_finance.resolve_plan_financing(
    v_pricing, p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
    p_installment_count, p_financing_fees_minor, p_total_payable_minor,
    p_monthly_payment_minor, v_rate_bp, v_rate_period, v_interest_method,
    coalesce(p_financed_fees_minor, 0)
  );
  v_non_interest_fees := v_financing.fees_minor - v_financing.interest_minor;

  v_origin := (case when p_import_as_of is not null
      or p_paid_through_on is not null or v_paid_count > 0
      or p_bank_reported_principal_minor is not null
    then 'historical_import' else 'app' end)::app_finance.plan_origin;
  v_as_of := case when v_origin = 'historical_import'
    then coalesce(p_import_as_of, p_reconciliation_as_of, current_date)
    else null end;

  if p_paid_through_on is not null then
    select count(*)::integer into v_derived_paid_count
    from generate_series(1, p_installment_count) g(sequence_number)
    where (p_first_due_on
      + make_interval(months => g.sequence_number - 1))::date
      <= p_paid_through_on;
    if v_paid_count > 0 and v_paid_count <> v_derived_paid_count then
      raise exception 'paid_state_mismatch: count and paid-through date disagree';
    end if;
    v_paid_count := v_derived_paid_count;
  end if;
  if v_paid_count >= p_installment_count then
    raise exception 'invalid_paid_count: imported plan must have an unpaid installment';
  end if;
  if v_paid_count > 0 and not coalesce(p_allow_future_presettlement, false)
    and (p_first_due_on + make_interval(months => v_paid_count - 1))::date
      > v_as_of then
    raise exception 'future_presettlement_requires_confirmation';
  end if;
  if coalesce(p_current_installment_posted, false)
    and v_origin <> 'historical_import' then
    raise exception 'current_posted_requires_historical_import';
  end if;

  if coalesce(p_down_payment_minor, 0) > 0 then
    select a.id, a.currency_code, a.account_type into v_down_account
    from app_finance.accounts a
    where a.id = p_down_payment_account_id and a.user_id = v_user_id
      and not a.is_archived;
    if v_down_account is null
      or app_finance.account_role(v_down_account.account_type) <> 'asset'
      or v_down_account.currency_code <> v_facility.currency_code then
      raise exception 'invalid_account: matching asset required for down payment';
    end if;
  end if;

  select sum(case
    when x.sequence_number <= v_paid_count then 0
    when v_interest_method = 'reducing'
      then x.principal_minor + x.financing_fee_minor
    else x.scheduled_payment_minor end)::bigint
  into v_charge_minor
  from app_finance.installment_amortization_schedule(
    p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
    v_financing.interest_minor, v_non_interest_fees, p_installment_count,
    v_rate_bp, v_rate_period, v_interest_method
  ) x;

  if p_bank_reported_principal_minor is not null then
    select p_bank_reported_principal_minor
      + coalesce(sum(case when x.sequence_number > v_paid_count
        then x.financing_fee_minor
          + case when v_interest_method = 'reducing' then 0
            else x.interest_minor end
        else 0 end), 0)::bigint
    into v_charge_minor
    from app_finance.installment_amortization_schedule(
      p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
      v_financing.interest_minor, v_non_interest_fees, p_installment_count,
      v_rate_bp, v_rate_period, v_interest_method
    ) x;
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + v_charge_minor > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    v_user_id, 'expense', p_purchased_on, v_charge_minor,
    v_facility.currency_code, p_account_id, p_category_id, p_title, p_notes
  ) returning id into v_purchase_tx_id;

  if coalesce(p_down_payment_minor, 0) > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', coalesce(p_down_paid_on, p_purchased_on),
      p_down_payment_minor, v_facility.currency_code,
      p_down_payment_account_id, p_category_id, p_title, p_notes
    ) returning id into v_down_tx_id;
  end if;
  if coalesce(p_upfront_fees_minor, 0) > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', coalesce(p_down_paid_on, p_purchased_on),
      p_upfront_fees_minor, v_facility.currency_code,
      coalesce(p_down_payment_account_id, p_account_id), p_category_id,
      p_title, p_notes
    );
  end if;

  insert into app_finance.installment_plans (
    id, user_id, account_id, purchase_transaction_id,
    down_payment_transaction_id, title, category_id, purchased_on,
    first_due_on, installment_count, purchase_price_minor,
    down_payment_minor, financed_principal_minor, financing_fees_minor,
    interest_minor, total_payable_minor, currency_code, notes,
    pricing_method, interest_rate_basis_points, interest_rate_period,
    interest_method, origin, import_as_of, paid_through_on,
    current_installment_posted, bank_reported_principal_minor,
    reconciliation_as_of, reconciliation_paid_installments,
    reconciliation_notes
  ) values (
    coalesce(p_plan_id, gen_random_uuid()), v_user_id, p_account_id,
    v_purchase_tx_id, v_down_tx_id, p_title, p_category_id, p_purchased_on,
    p_first_due_on, p_installment_count, p_purchase_price_minor,
    coalesce(p_down_payment_minor, 0),
    p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
    v_financing.fees_minor, v_financing.interest_minor,
    v_financing.total_minor, v_facility.currency_code, p_notes, v_pricing,
    v_rate_bp, v_rate_period, v_interest_method, v_origin, v_as_of,
    coalesce(p_paid_through_on, case when v_paid_count > 0 then
      (p_first_due_on + make_interval(months => v_paid_count - 1))::date end),
    coalesce(p_current_installment_posted, false),
    p_bank_reported_principal_minor,
    coalesce(p_reconciliation_as_of,
      case when p_bank_reported_principal_minor is not null then v_as_of end),
    case when p_bank_reported_principal_minor is not null
      then v_paid_count else null end,
    p_reconciliation_notes
  ) returning id into v_plan_id;

  v_reconciled_opening :=
    p_purchase_price_minor - coalesce(p_down_payment_minor, 0);
  for v_schedule in select *
    from app_finance.installment_amortization_schedule(
      p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
      v_financing.interest_minor, v_non_interest_fees, p_installment_count,
      v_rate_bp, v_rate_period, v_interest_method
    )
  loop
    -- A bank-reconciled 0% import may expose a rounded monthly amount and an
    -- exact current principal. Keep legacy schedules unchanged by default;
    -- only this explicit reconciliation path moves residue to final dues.
    if p_bank_reported_principal_minor is not null
      and v_interest_method <> 'reducing'
      and v_financing.interest_minor = 0 and v_non_interest_fees = 0 then
      v_reconciled_component :=
        (p_purchase_price_minor - coalesce(p_down_payment_minor, 0))
          / p_installment_count
        + case when v_schedule.sequence_number > p_installment_count
            - ((p_purchase_price_minor - coalesce(p_down_payment_minor, 0))
              % p_installment_count)
          then 1 else 0 end;
      v_schedule.opening_principal_minor := v_reconciled_opening;
      v_schedule.principal_minor := v_reconciled_component;
      v_schedule.scheduled_payment_minor := v_reconciled_component;
      v_schedule.closing_principal_minor :=
        v_reconciled_opening - v_reconciled_component;
      v_reconciled_opening := v_schedule.closing_principal_minor;
    end if;
    insert into app_finance.installment_dues (
      user_id, plan_id, sequence_number, due_on, amount_minor, is_presettled,
      opening_principal_minor, principal_minor, interest_minor,
      financing_fee_minor, closing_principal_minor
    ) values (
      v_user_id, v_plan_id, v_schedule.sequence_number,
      (p_first_due_on
        + make_interval(months => v_schedule.sequence_number - 1))::date,
      v_schedule.scheduled_payment_minor,
      v_schedule.sequence_number <= v_paid_count,
      v_schedule.opening_principal_minor, v_schedule.principal_minor,
      v_schedule.interest_minor, v_schedule.financing_fee_minor,
      v_schedule.closing_principal_minor
    );
  end loop;
  perform set_config('app_finance.facility_internal', '', true);
  return v_plan_id;
end;
$$;

revoke execute on function app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  bigint, date, integer, date, date, boolean, boolean, bigint, date, text
) from public, anon;
grant execute on function app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  bigint, date, integer, date, date, boolean, boolean, bigint, date, text
) to authenticated, service_role;

create or replace function app_finance.materialize_installment_interest(
  p_through date default null,
  p_account_id uuid default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_through date := coalesce(p_through, current_date);
  v_due record;
  v_tx_id uuid;
  v_count integer := 0;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  perform set_config('app_finance.facility_internal', 'on', true);
  for v_due in
    select d.id, d.user_id, d.due_on, d.interest_minor,
      p.account_id, p.category_id, p.currency_code, p.title
    from app_finance.installment_dues d
    join app_finance.installment_plans p on p.id = d.plan_id
    where d.user_id = v_user_id and p.status = 'active'
      and (p_account_id is null or p.account_id = p_account_id)
      and p.interest_method = 'reducing'
      and d.due_on <= v_through and d.interest_minor > 0
      and not d.is_presettled and d.interest_transaction_id is null
      and not exists (select 1
        from app_finance.installment_payment_allocations pa
        where pa.due_id = d.id)
    order by d.due_on, d.sequence_number
    for update of d
  loop
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', v_due.due_on, v_due.interest_minor,
      v_due.currency_code, v_due.account_id, v_due.category_id,
      'Installment interest: ' || v_due.title,
      'Contractual reducing-balance interest recognized when due.'
    ) returning id into v_tx_id;
    update app_finance.installment_dues
    set interest_transaction_id = v_tx_id
    where id = v_due.id and user_id = v_user_id;
    v_count := v_count + 1;
  end loop;
  perform set_config('app_finance.facility_internal', '', true);
  return v_count;
end;
$$;

revoke execute on function app_finance.materialize_installment_interest(
  date, uuid
) from public, anon;
grant execute on function app_finance.materialize_installment_interest(
  date, uuid
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

create or replace function app_finance.reconcile_historical_installment_plan(
  p_plan_id uuid,
  p_paid_installments integer,
  p_as_of date,
  p_bank_reported_principal_minor bigint,
  p_current_installment_posted boolean default false,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_plan app_finance.installment_plans;
  v_last_paid_due date;
  v_charge_minor bigint;
  v_outstanding_after bigint;
  v_limit bigint;
  v_due record;
  v_opening bigint;
  v_component bigint;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_as_of is null or p_bank_reported_principal_minor is null
    or p_bank_reported_principal_minor < 0 then
    raise exception 'invalid_reconciliation: as-of date and bank principal required';
  end if;
  select * into v_plan from app_finance.installment_plans
  where id = p_plan_id and user_id = v_user_id
  for update;
  if v_plan.id is null or v_plan.origin <> 'historical_import' then
    raise exception 'not_found: historical installment plan';
  end if;
  if p_paid_installments < 0
    or p_paid_installments >= v_plan.installment_count then
    raise exception 'invalid_paid_count';
  end if;
  if exists (select 1 from app_finance.installment_payment_allocations pa
    join app_finance.installment_dues d on d.id = pa.due_id
    where d.plan_id = p_plan_id) then
    raise exception 'plan_has_tracked_payments: reverse allocations before reconciling';
  end if;
  select due_on into v_last_paid_due from app_finance.installment_dues
  where plan_id = p_plan_id and sequence_number = p_paid_installments;
  if p_paid_installments > 0 and v_last_paid_due > p_as_of then
    raise exception 'future_presettlement_requires_confirmation';
  end if;

  select p_bank_reported_principal_minor
    + coalesce(sum(case when d.sequence_number > p_paid_installments
      then d.financing_fee_minor
        + case when v_plan.interest_method = 'reducing'
          then 0 else d.interest_minor end
      else 0 end), 0)::bigint
  into v_charge_minor
  from app_finance.installment_dues d where d.plan_id = p_plan_id;

  select credit_limit_minor into v_limit
  from app_finance.credit_facility_settings
  where account_id = v_plan.account_id and user_id = v_user_id;
  select app_finance.facility_outstanding_minor(v_plan.account_id)
      - t.amount_minor + v_charge_minor
    into v_outstanding_after
  from app_finance.financial_transactions t
  where t.id = v_plan.purchase_transaction_id and t.user_id = v_user_id;
  if v_outstanding_after > v_limit then
    raise exception 'insufficient_credit: reconciliation exceeds limit';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  if v_plan.interest_method <> 'reducing' and v_plan.interest_minor = 0
    and v_plan.financing_fees_minor = 0 then
    v_opening := v_plan.financed_principal_minor;
    for v_due in select id, sequence_number
      from app_finance.installment_dues where plan_id = p_plan_id
      order by sequence_number
    loop
      v_component := v_plan.financed_principal_minor / v_plan.installment_count
        + case when v_due.sequence_number > v_plan.installment_count
            - (v_plan.financed_principal_minor % v_plan.installment_count)
          then 1 else 0 end;
      update app_finance.installment_dues
      set amount_minor = v_component,
        opening_principal_minor = v_opening,
        principal_minor = v_component,
        closing_principal_minor = v_opening - v_component
      where id = v_due.id and user_id = v_user_id;
      v_opening := v_opening - v_component;
    end loop;
  end if;
  update app_finance.installment_dues
  set is_presettled = sequence_number <= p_paid_installments
  where plan_id = p_plan_id and user_id = v_user_id;
  update app_finance.financial_transactions
  set amount_minor = v_charge_minor,
    notes = concat_ws(E'\n', nullif(notes, ''), p_notes)
  where id = v_plan.purchase_transaction_id and user_id = v_user_id;
  update app_finance.installment_plans
  set import_as_of = p_as_of,
    paid_through_on = case when p_paid_installments > 0
      then v_last_paid_due else null end,
    current_installment_posted = coalesce(p_current_installment_posted, false),
    bank_reported_principal_minor = p_bank_reported_principal_minor,
    reconciliation_as_of = p_as_of,
    reconciliation_paid_installments = p_paid_installments,
    reconciliation_notes = p_notes,
    needs_reconciliation = false
  where id = p_plan_id and user_id = v_user_id;
  perform set_config('app_finance.facility_internal', '', true);
  return p_plan_id;
end;
$$;

revoke execute on function app_finance.reconcile_historical_installment_plan(
  uuid, integer, date, bigint, boolean, text
) from public, anon;
grant execute on function app_finance.reconcile_historical_installment_plan(
  uuid, integer, date, bigint, boolean, text
) to authenticated, service_role;

create or replace function app_finance.configure_purchase_interest_rule(
  p_account_id uuid,
  p_category_id uuid,
  p_state app_finance.card_rule_state,
  p_effective_from date,
  p_rate_basis_points integer default null,
  p_rate_period app_finance.card_interest_rate_period default 'monthly',
  p_accrual_method app_finance.card_interest_accrual_method
    default 'bank_posted_manual',
  p_interest_starts app_finance.card_interest_start default 'grace_expiry',
  p_grace_period_days smallint default null,
  p_grace_applies boolean default true,
  p_notes text default null,
  p_rule_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_rule_id uuid;
  v_latest app_finance.credit_card_fee_rule_versions;
  v_number integer;
  v_calc app_finance.card_rule_calculation_type;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id
      and a.account_type = 'credit_card' and not a.is_archived) then
    raise exception 'invalid_account: credit card required';
  end if;
  if not exists (select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and c.category_kind = 'expense' and not c.is_archived) then
    raise exception 'invalid_category: expense category required';
  end if;
  if p_state = 'configured'
    and (p_rate_basis_points is null or p_rate_basis_points <= 0) then
    raise exception 'invalid_rule: configured interest requires a rate';
  end if;
  v_calc := (case when p_rate_basis_points is null
    then 'manual' else 'percentage' end)
    ::app_finance.card_rule_calculation_type;

  perform set_config('app_finance.facility_internal', 'on', true);
  if p_rule_id is null then
    insert into app_finance.credit_card_fee_rules (
      user_id, account_id, name, fee_type, category_id, frequency,
      starts_on, next_charge_on, state, trigger_kind, is_active, notes,
      percent_basis_points, percent_basis
    ) values (
      v_user_id, p_account_id, 'Purchase / revolving interest',
      'purchase_interest', p_category_id, 'monthly', p_effective_from, null,
      p_state, 'statement_interest', p_state = 'configured', p_notes,
      p_rate_basis_points,
      case when p_rate_basis_points is null then null
        else 'statement_balance'::app_finance.fee_percent_basis end
    ) returning id into v_rule_id;
    v_number := 1;
  else
    select * into v_latest from app_finance.credit_card_fee_rule_versions
    where rule_id = p_rule_id and user_id = v_user_id
    order by effective_from desc limit 1 for update;
    if v_latest.id is null or p_effective_from <= v_latest.effective_from then
      raise exception 'invalid_date: version must start after current version';
    end if;
    update app_finance.credit_card_fee_rule_versions
    set effective_until = p_effective_from where id = v_latest.id;
    update app_finance.credit_card_fee_rules
    set category_id = p_category_id, state = p_state,
      is_active = p_state = 'configured', notes = p_notes,
      percent_basis_points = p_rate_basis_points,
      percent_basis = case when p_rate_basis_points is null then null
        else 'statement_balance'::app_finance.fee_percent_basis end
    where id = p_rule_id and account_id = p_account_id
      and user_id = v_user_id
    returning id into v_rule_id;
    if v_rule_id is null then raise exception 'not_found: interest rule'; end if;
    v_number := v_latest.version_number + 1;
  end if;

  insert into app_finance.credit_card_fee_rule_versions (
    user_id, rule_id, version_number, effective_from, calculation_type,
    percent_basis_points, percent_basis, frequency, notes,
    interest_rate_period, interest_accrual_method, interest_starts,
    grace_period_days, grace_applies
  ) values (
    v_user_id, v_rule_id, v_number, p_effective_from, v_calc,
    p_rate_basis_points,
    case when p_rate_basis_points is null then null
      else 'statement_balance'::app_finance.fee_percent_basis end,
    'monthly', p_notes, p_rate_period, p_accrual_method, p_interest_starts,
    p_grace_period_days, p_grace_applies
  );
  perform set_config('app_finance.facility_internal', '', true);
  return v_rule_id;
end;
$$;

revoke execute on function app_finance.configure_purchase_interest_rule(
  uuid, uuid, app_finance.card_rule_state, date, integer,
  app_finance.card_interest_rate_period,
  app_finance.card_interest_accrual_method, app_finance.card_interest_start,
  smallint, boolean, text, uuid
) from public, anon;
grant execute on function app_finance.configure_purchase_interest_rule(
  uuid, uuid, app_finance.card_rule_state, date, integer,
  app_finance.card_interest_rate_period,
  app_finance.card_interest_accrual_method, app_finance.card_interest_start,
  smallint, boolean, text, uuid
) to authenticated, service_role;

create or replace function app_finance.record_actual_card_charge(
  p_account_id uuid,
  p_rule_id uuid,
  p_charged_on date,
  p_actual_amount_minor bigint,
  p_reconciliation_key text,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_rule app_finance.credit_card_fee_rules;
  v_version app_finance.credit_card_fee_rule_versions;
  v_account record;
  v_charge_id uuid;
  v_tx_id uuid;
  v_cycle_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_actual_amount_minor is null or p_actual_amount_minor <= 0 then
    raise exception 'invalid_amount: actual charge must be positive';
  end if;
  if nullif(trim(p_reconciliation_key), '') is null then
    raise exception 'reconciliation_key_required';
  end if;
  select id into v_charge_id from app_finance.credit_card_fee_charges
  where user_id = v_user_id and reconciliation_key = p_reconciliation_key;
  if v_charge_id is not null then return v_charge_id; end if;

  select * into v_rule from app_finance.credit_card_fee_rules
  where id = p_rule_id and account_id = p_account_id and user_id = v_user_id
  for update;
  if v_rule.id is null then raise exception 'not_found: card rule'; end if;
  select a.currency_code, a.account_type into v_account
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
  for update;
  if v_account.account_type <> 'credit_card' then
    raise exception 'invalid_account: credit card required';
  end if;
  select * into v_version from app_finance.credit_card_fee_rule_versions
  where rule_id = p_rule_id and user_id = v_user_id
    and effective_from <= p_charged_on
    and (effective_until is null or effective_until > p_charged_on)
  order by effective_from desc limit 1;
  if v_version.id is null then
    raise exception 'not_found: rule version for posting date';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    v_user_id, 'expense', p_charged_on, p_actual_amount_minor,
    v_account.currency_code, p_account_id, v_rule.category_id,
    v_rule.name, p_notes
  ) returning id into v_tx_id;
  perform app_finance.relink_card_statement_item(
    v_user_id, v_tx_id, p_account_id, p_charged_on, p_actual_amount_minor
  );
  select cycle_id into v_cycle_id
  from app_finance.credit_card_statement_items
  where transaction_id = v_tx_id and user_id = v_user_id;
  insert into app_finance.credit_card_fee_charges (
    user_id, rule_id, rule_version_id, transaction_id, statement_cycle_id,
    charged_on, amount_minor, expected_amount_minor, actual_amount_minor,
    reconciliation_status, calculation_snapshot, reconciled_at,
    reconciliation_notes, reconciliation_key
  ) values (
    v_user_id, p_rule_id, v_version.id, v_tx_id, v_cycle_id,
    p_charged_on, p_actual_amount_minor, p_actual_amount_minor,
    p_actual_amount_minor, 'confirmed',
    jsonb_build_object('source', 'bank_statement_actual',
      'posting_date', p_charged_on, 'rule_version', v_version.version_number),
    now(), p_notes, trim(p_reconciliation_key)
  ) returning id into v_charge_id;
  if v_rule.trigger_kind = 'schedule'
    and coalesce(v_rule.next_charge_on, v_rule.starts_on) <= p_charged_on then
    update app_finance.credit_card_fee_rules
    set next_charge_on = case v_version.frequency
        when 'once' then null
        when 'monthly' then (p_charged_on + interval '1 month')::date
        when 'quarterly' then (p_charged_on + interval '3 months')::date
        else (p_charged_on + interval '1 year')::date
      end,
      is_active = case when v_version.frequency = 'once'
        then false else is_active end
    where id = v_rule.id and user_id = v_user_id;
  end if;
  perform set_config('app_finance.facility_internal', '', true);
  return v_charge_id;
end;
$$;

revoke execute on function app_finance.record_actual_card_charge(
  uuid, uuid, date, bigint, text, text
) from public, anon;
grant execute on function app_finance.record_actual_card_charge(
  uuid, uuid, date, bigint, text, text
) to authenticated, service_role;

create or replace function app_finance.correct_historical_facility_payment(
  p_transaction_id uuid,
  p_account_id uuid,
  p_expected_amount_minor bigint,
  p_repair_key text,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_tx app_finance.financial_transactions;
  v_account record;
  v_existing uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  select settled_by_transaction_id into v_existing
  from app_finance.historical_facility_obligations
  where user_id = v_user_id and repair_key = p_repair_key;
  if v_existing is not null then return v_existing; end if;
  select * into v_tx from app_finance.financial_transactions
  where id = p_transaction_id and user_id = v_user_id
  for update;
  if v_tx.id is null or v_tx.transaction_kind <> 'expense'
    or v_tx.source_account_id is null or v_tx.destination_account_id is not null
    or v_tx.amount_minor <> p_expected_amount_minor then
    raise exception 'unexpected_payment_before_state';
  end if;
  if not exists (select 1 from app_finance.accounts a
    where a.id = v_tx.source_account_id and a.user_id = v_user_id
      and app_finance.account_role(a.account_type) = 'asset') then
    raise exception 'invalid_payment_source';
  end if;
  select a.id, a.currency_code, a.account_type into v_account
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id
  for update;
  if v_account is null
    or app_finance.account_role(v_account.account_type) <> 'liability'
    or v_account.currency_code <> v_tx.currency_code then
    raise exception 'invalid_payment_destination';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  delete from app_finance.credit_card_statement_items
  where transaction_id = p_transaction_id and user_id = v_user_id;
  update app_finance.financial_transactions
  set transaction_kind = 'transfer', destination_account_id = p_account_id,
    category_id = null,
    title = coalesce(nullif(title, ''), 'Credit Card repayment'),
    notes = concat_ws(E'\n', nullif(notes, ''), p_notes)
  where id = p_transaction_id and user_id = v_user_id;
  insert into app_finance.historical_facility_obligations (
    user_id, account_id, settled_by_transaction_id, occurred_on,
    amount_minor, repair_key, notes
  ) values (
    v_user_id, p_account_id, p_transaction_id, v_tx.occurred_on,
    v_tx.amount_minor, p_repair_key, p_notes
  );
  perform set_config('app_finance.facility_internal', '', true);
  return p_transaction_id;
end;
$$;

revoke execute on function app_finance.correct_historical_facility_payment(
  uuid, uuid, bigint, text, text
) from public, anon;
grant execute on function app_finance.correct_historical_facility_payment(
  uuid, uuid, bigint, text, text
) to authenticated, service_role;

create or replace function app_finance.highest_statement_due_minor(
  p_account_id uuid,
  p_before date,
  p_lookback_cycles integer
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(max(y.total_statement_due_minor), 0)::bigint
  from (
    select total_statement_due_minor
    from app_finance.credit_card_statement_summaries
    where account_id = p_account_id and cycle_close < p_before
    order by cycle_close desc
    limit greatest(coalesce(p_lookback_cycles, 3), 1)
  ) y;
$$;

create or replace view app_finance.facility_activity_items
with (security_invoker = on) as
  select
    t.id as transaction_id, t.user_id, a.id as account_id,
    t.transaction_kind, t.occurred_on, t.amount_minor, t.currency_code,
    t.category_id, t.title, t.notes, t.counterparty, t.sort_at,
    coalesce(purchase.id, down.id) as plan_id,
    case
      when t.facility_reversal_of_id is not null then 'repayment_reversal'
      when purchase.id is not null then 'installment_purchase'
      when down.id is not null then 'installment_down_payment'
      when fr.fee_type = 'purchase_interest' then 'purchase_interest'
      when fee.transaction_id is not null then 'fee_charge'
      when t.transaction_kind = 'transfer'
        and t.destination_account_id = a.id then 'facility_repayment'
      when t.transaction_kind = 'transfer' then 'repayment_reversal'
      when t.transaction_kind = 'expense'
        and exists (select 1 from app_finance.installment_dues d
          where d.interest_transaction_id = t.id) then 'installment_interest'
      when t.transaction_kind = 'expense' then 'ordinary_expense'
      else 'other'
    end as activity_kind,
    exists (
      select 1 from app_finance.credit_card_statement_items i
      join app_finance.credit_card_statement_allocations al
        on al.cycle_id = i.cycle_id
      where i.transaction_id = t.id
    ) as is_settled,
    fr.fee_type
  from app_finance.financial_transactions t
  join app_finance.accounts a
    on a.id in (t.source_account_id, t.destination_account_id)
      and a.user_id = t.user_id
  left join app_finance.installment_plans purchase
    on purchase.purchase_transaction_id = t.id
  left join app_finance.installment_plans down
    on down.down_payment_transaction_id = t.id
  left join app_finance.credit_card_fee_charges fee
    on fee.transaction_id = t.id
  left join app_finance.credit_card_fee_rules fr on fr.id = fee.rule_id
  where app_finance.account_role(a.account_type) = 'liability';

grant select on app_finance.historical_facility_obligations
  to authenticated, service_role;
grant select on app_finance.installment_due_statuses,
  app_finance.installment_plan_summaries,
  app_finance.credit_card_statement_summaries,
  app_finance.credit_facility_summaries,
  app_finance.facility_activity_items to authenticated, service_role;

notify pgrst, 'reload schema';
