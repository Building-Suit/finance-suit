-- Credit facilities: credit cards and BNPL / finance-company accounts are
-- liabilities, not cash. A financed purchase is recognized as an expense once
-- on the purchase date; the monthly installment rows are scheduled dues, not
-- transactions. Repayments are transfers from an asset account into the
-- facility and reduce both sides equally, so income and expense reports never
-- count a repayment twice. Outstanding debt is stored positively:
-- outstanding = opening amount owed + charges - repayments.

-- ---------------------------------------------------------------------------
-- Account role: the single SQL source of truth for asset vs liability
-- ---------------------------------------------------------------------------

create or replace function app_finance.account_role(
  p_account_type app_finance.account_type
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_account_type in ('credit_card', 'bnpl') then 'liability'
    else 'asset'
  end;
$$;

comment on function app_finance.account_role(app_finance.account_type) is
  'Single source of truth mapping an account type to asset or liability.';

-- Positive outstanding debt for one liability account. The sign convention is
-- the mirror of asset balances: charges (outgoing flows) increase what is
-- owed, repayments (incoming flows) reduce it.
create or replace function app_finance.facility_outstanding_minor(
  p_account_id uuid
)
returns bigint
language sql
stable
set search_path = ''
as $$
  select a.opening_balance_minor - coalesce((
    select sum(
      case when t.destination_account_id = a.id
        then t.amount_minor
        else -t.amount_minor
      end
    )
    from app_finance.financial_transactions t
    where t.source_account_id = a.id or t.destination_account_id = a.id
  ), 0)
  from app_finance.accounts a
  where a.id = p_account_id;
$$;

-- ---------------------------------------------------------------------------
-- Installment plan status enum
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'installment_plan_status'
  ) then
    create type app_finance.installment_plan_status as enum (
      'active',
      'completed',
      'cancelled'
    );
  end if;
end $$;

grant usage on type app_finance.installment_plan_status
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Facility payment reversal audit link on financial transactions
-- ---------------------------------------------------------------------------

alter table app_finance.financial_transactions
  add column if not exists facility_reversal_of_id uuid;

alter table app_finance.financial_transactions
  drop constraint if exists tx_facility_reversal_owner_fk;
alter table app_finance.financial_transactions
  add constraint tx_facility_reversal_owner_fk
  foreign key (facility_reversal_of_id, user_id)
  references app_finance.financial_transactions (id, user_id)
  on delete set null (facility_reversal_of_id);

-- One reversal per facility payment keeps retries idempotent.
create unique index if not exists idx_tx_one_facility_reversal
  on app_finance.financial_transactions (facility_reversal_of_id)
  where facility_reversal_of_id is not null;

-- ---------------------------------------------------------------------------
-- Credit facility settings (one-to-one with a liability account)
-- ---------------------------------------------------------------------------

create table if not exists app_finance.credit_facility_settings (
  account_id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  credit_limit_minor bigint not null check (credit_limit_minor > 0),
  -- Informational statement day; prefill support only, credit cards only.
  statement_day smallint check (statement_day between 1 and 28),
  default_due_day smallint not null check (default_due_day between 1 and 28),
  last_four_digits text check (last_four_digits ~ '^[0-9]{4}$'),
  reminder_lead_days smallint not null default 3
    check (reminder_lead_days between 0 and 31),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credit_facility_settings_owner_unique unique (account_id, user_id),
  constraint credit_facility_settings_account_owner_fk
    foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id) on delete cascade
);

drop trigger if exists trg_credit_facility_settings_updated_at
  on app_finance.credit_facility_settings;
create trigger trg_credit_facility_settings_updated_at
  before update on app_finance.credit_facility_settings
  for each row execute function app_private.set_updated_at();

create index if not exists idx_credit_facility_settings_user
  on app_finance.credit_facility_settings (user_id);

alter table app_finance.credit_facility_settings enable row level security;

drop policy if exists credit_facility_settings_select
  on app_finance.credit_facility_settings;
create policy credit_facility_settings_select
  on app_finance.credit_facility_settings
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_facility_settings_insert
  on app_finance.credit_facility_settings;
create policy credit_facility_settings_insert
  on app_finance.credit_facility_settings
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_facility_settings_update
  on app_finance.credit_facility_settings;
create policy credit_facility_settings_update
  on app_finance.credit_facility_settings
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists credit_facility_settings_delete
  on app_finance.credit_facility_settings;
create policy credit_facility_settings_delete
  on app_finance.credit_facility_settings
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Installment plans
-- ---------------------------------------------------------------------------

create table if not exists app_finance.installment_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  -- The financed purchase expense (principal + fees) booked from the
  -- facility. Nulled only when a never-paid plan is cancelled.
  purchase_transaction_id uuid,
  down_payment_transaction_id uuid,
  title text not null check (char_length(title) between 1 and 120),
  category_id uuid not null,
  purchased_on date not null,
  first_due_on date not null,
  installment_count integer not null
    check (installment_count between 1 and 120),
  purchase_price_minor bigint not null check (purchase_price_minor > 0),
  down_payment_minor bigint not null default 0
    check (down_payment_minor >= 0),
  financed_principal_minor bigint not null
    check (financed_principal_minor > 0),
  financing_fees_minor bigint not null default 0
    check (financing_fees_minor >= 0),
  total_payable_minor bigint not null check (total_payable_minor > 0),
  currency_code text not null default 'EGP'
    check (currency_code ~ '^[A-Z]{3}$'),
  status app_finance.installment_plan_status not null default 'active',
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint installment_plans_owner_unique unique (id, user_id),
  constraint installment_plans_account_owner_fk
    foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id),
  constraint installment_plans_category_owner_fk
    foreign key (category_id, user_id)
    references app_finance.transaction_categories (id, user_id),
  constraint installment_plans_purchase_tx_owner_fk
    foreign key (purchase_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete set null (purchase_transaction_id),
  constraint installment_plans_down_tx_owner_fk
    foreign key (down_payment_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete set null (down_payment_transaction_id),
  constraint installment_plans_down_within_price
    check (down_payment_minor <= purchase_price_minor),
  constraint installment_plans_principal_math
    check (
      financed_principal_minor = purchase_price_minor - down_payment_minor
    ),
  constraint installment_plans_total_math
    check (
      total_payable_minor = financed_principal_minor + financing_fees_minor
    ),
  constraint installment_plans_due_after_purchase
    check (first_due_on >= purchased_on),
  -- Active and completed plans stay linked to their booked purchase.
  constraint installment_plans_purchase_link_required
    check (status = 'cancelled' or purchase_transaction_id is not null)
);

drop trigger if exists trg_installment_plans_updated_at
  on app_finance.installment_plans;
create trigger trg_installment_plans_updated_at
  before update on app_finance.installment_plans
  for each row execute function app_private.set_updated_at();

create index if not exists idx_installment_plans_user_account
  on app_finance.installment_plans (user_id, account_id, status, created_at);
create index if not exists idx_installment_plans_category_owner_fk
  on app_finance.installment_plans (category_id, user_id);
create index if not exists idx_installment_plans_purchase_tx
  on app_finance.installment_plans (purchase_transaction_id, user_id)
  where purchase_transaction_id is not null;
create index if not exists idx_installment_plans_down_tx
  on app_finance.installment_plans (down_payment_transaction_id, user_id)
  where down_payment_transaction_id is not null;

alter table app_finance.installment_plans enable row level security;

drop policy if exists installment_plans_select on app_finance.installment_plans;
create policy installment_plans_select on app_finance.installment_plans
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists installment_plans_insert on app_finance.installment_plans;
create policy installment_plans_insert on app_finance.installment_plans
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists installment_plans_update on app_finance.installment_plans;
create policy installment_plans_update on app_finance.installment_plans
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists installment_plans_delete on app_finance.installment_plans;
create policy installment_plans_delete on app_finance.installment_plans
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Installment dues (schedule rows, never transactions)
-- ---------------------------------------------------------------------------

create table if not exists app_finance.installment_dues (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null,
  sequence_number integer not null check (sequence_number >= 1),
  due_on date not null,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint installment_dues_owner_unique unique (id, user_id),
  constraint installment_dues_sequence_unique unique (plan_id, sequence_number),
  constraint installment_dues_plan_owner_fk
    foreign key (plan_id, user_id)
    references app_finance.installment_plans (id, user_id) on delete cascade
);

create index if not exists idx_installment_dues_user_due_on
  on app_finance.installment_dues (user_id, due_on, sequence_number);
create index if not exists idx_installment_dues_plan_owner_fk
  on app_finance.installment_dues (plan_id, user_id);

alter table app_finance.installment_dues enable row level security;

drop policy if exists installment_dues_select on app_finance.installment_dues;
create policy installment_dues_select on app_finance.installment_dues
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists installment_dues_insert on app_finance.installment_dues;
create policy installment_dues_insert on app_finance.installment_dues
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists installment_dues_update on app_finance.installment_dues;
create policy installment_dues_update on app_finance.installment_dues
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists installment_dues_delete on app_finance.installment_dues;
create policy installment_dues_delete on app_finance.installment_dues
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Payment allocations (the transfer transaction stays the source of truth)
-- ---------------------------------------------------------------------------

create table if not exists app_finance.installment_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  payment_transaction_id uuid not null,
  due_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint installment_payment_allocations_owner_unique unique (id, user_id),
  constraint installment_payment_allocations_pair_unique
    unique (payment_transaction_id, due_id),
  constraint installment_allocations_payment_owner_fk
    foreign key (payment_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade,
  constraint installment_allocations_due_owner_fk
    foreign key (due_id, user_id)
    references app_finance.installment_dues (id, user_id) on delete cascade
);

create index if not exists idx_installment_allocations_due
  on app_finance.installment_payment_allocations (due_id, user_id);
create index if not exists idx_installment_allocations_payment
  on app_finance.installment_payment_allocations
  (payment_transaction_id, user_id);

alter table app_finance.installment_payment_allocations
  enable row level security;

drop policy if exists installment_payment_allocations_select
  on app_finance.installment_payment_allocations;
create policy installment_payment_allocations_select
  on app_finance.installment_payment_allocations
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists installment_payment_allocations_insert
  on app_finance.installment_payment_allocations;
create policy installment_payment_allocations_insert
  on app_finance.installment_payment_allocations
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists installment_payment_allocations_update
  on app_finance.installment_payment_allocations;
create policy installment_payment_allocations_update
  on app_finance.installment_payment_allocations
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists installment_payment_allocations_delete
  on app_finance.installment_payment_allocations;
create policy installment_payment_allocations_delete
  on app_finance.installment_payment_allocations
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Liability guard rails on accounts
-- ---------------------------------------------------------------------------

create or replace function app_private.enforce_liability_account_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_role text := app_finance.account_role(new.account_type);
  v_outstanding bigint;
begin
  if v_role = 'liability' then
    if new.is_default then
      raise exception
        'invalid_account: liability accounts cannot be the default account';
    end if;
    if new.allow_negative_balance then
      raise exception
        'invalid_account: liability accounts cannot allow negative balances';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    -- Historical flows keep their meaning: an account may only switch
    -- between asset and liability roles while it is completely unused.
    if app_finance.account_role(old.account_type) <> v_role then
      if exists (
        select 1 from app_finance.financial_transactions t
        where t.source_account_id = old.id
          or t.destination_account_id = old.id
      ) or exists (
        select 1 from app_finance.credit_facility_settings s
        where s.account_id = old.id
      ) or exists (
        select 1 from app_finance.installment_plans p
        where p.account_id = old.id
      ) then
        raise exception
          'account_role_locked: create a new account for a different role';
      end if;
    end if;

    if v_role = 'liability' and new.is_archived and not old.is_archived then
      v_outstanding := app_finance.facility_outstanding_minor(old.id);
      if v_outstanding <> 0
        or exists (
          select 1
          from app_finance.installment_plans p
          where p.account_id = old.id and p.status = 'active'
        ) then
        raise exception
          'facility_archive_blocked: money is still owed on this facility';
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_liability_account_rules
  on app_finance.accounts;
create trigger trg_enforce_liability_account_rules
  before insert or update on app_finance.accounts
  for each row execute function app_private.enforce_liability_account_rules();

-- ---------------------------------------------------------------------------
-- Facility settings guard rails
-- ---------------------------------------------------------------------------

create or replace function app_private.enforce_credit_facility_settings()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account record;
  v_outstanding bigint;
begin
  select account_type, is_archived into v_account
    from app_finance.accounts
    where id = new.account_id;
  if v_account is null
    or app_finance.account_role(v_account.account_type) <> 'liability' then
    raise exception
      'invalid_account: facility settings require a credit card or BNPL account';
  end if;
  if v_account.account_type <> 'credit_card'
    and (new.statement_day is not null or new.last_four_digits is not null) then
    raise exception
      'invalid_facility: statement day and last four digits are credit-card only';
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(new.account_id);
  if new.credit_limit_minor < v_outstanding then
    raise exception
      'credit_limit_below_outstanding: raise the limit to at least the amount owed';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_credit_facility_settings
  on app_finance.credit_facility_settings;
create trigger trg_enforce_credit_facility_settings
  before insert or update on app_finance.credit_facility_settings
  for each row execute function app_private.enforce_credit_facility_settings();

-- ---------------------------------------------------------------------------
-- Protect facility ledger rows from the generic editors
-- ---------------------------------------------------------------------------

-- The facility RPCs mark themselves with a transaction-local flag; ordinary
-- client writes never carry it. Service-role and admin sessions (no JWT
-- subject) stay unrestricted so account deletion and support tooling work.
-- The check is inlined in each trigger because clients hold no privileges
-- on the app_private schema, and trigger bodies run as the invoking role.
create or replace function app_private.protect_facility_transactions()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_row app_finance.financial_transactions;
begin
  if coalesce(current_setting('app_finance.facility_internal', true), '')
      = 'on'
    or (select auth.uid()) is null then
    return coalesce(new, old);
  end if;

  v_row := coalesce(new, old);
  if exists (
    select 1 from app_finance.accounts a
    where a.id in (v_row.source_account_id, v_row.destination_account_id)
      and app_finance.account_role(a.account_type) = 'liability'
  ) then
    raise exception
      'invalid_account: credit facility accounts accept only installment purchases and facility payments';
  end if;

  if tg_op <> 'INSERT' then
    if old.facility_reversal_of_id is not null
      or exists (
        select 1 from app_finance.installment_plans p
        where p.purchase_transaction_id = old.id
          or p.down_payment_transaction_id = old.id
      )
      or exists (
        select 1 from app_finance.installment_payment_allocations pa
        where pa.payment_transaction_id = old.id
      ) then
      raise exception
        'facility_transaction_locked: manage installment records from the facility screen';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_protect_facility_transactions
  on app_finance.financial_transactions;
create trigger trg_protect_facility_transactions
  before insert or update or delete on app_finance.financial_transactions
  for each row execute function app_private.protect_facility_transactions();

-- Plans, dues, and allocations change only through the facility RPCs, except
-- plan title/notes which stay editable in place.
create or replace function app_private.protect_installment_rows()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app_finance.facility_internal', true), '')
      = 'on'
    or (select auth.uid()) is null then
    return coalesce(new, old);
  end if;

  if tg_table_name = 'installment_plans' and tg_op = 'UPDATE' then
    if new.id = old.id
      and new.user_id = old.user_id
      and new.account_id = old.account_id
      and new.purchase_transaction_id is not distinct from
        old.purchase_transaction_id
      and new.down_payment_transaction_id is not distinct from
        old.down_payment_transaction_id
      and new.category_id = old.category_id
      and new.purchased_on = old.purchased_on
      and new.first_due_on = old.first_due_on
      and new.installment_count = old.installment_count
      and new.purchase_price_minor = old.purchase_price_minor
      and new.down_payment_minor = old.down_payment_minor
      and new.financed_principal_minor = old.financed_principal_minor
      and new.financing_fees_minor = old.financing_fees_minor
      and new.total_payable_minor = old.total_payable_minor
      and new.currency_code = old.currency_code
      and new.status = old.status then
      return new;
    end if;
    raise exception
      'plan_locked: only the title and notes of an installment plan can be edited';
  end if;

  raise exception
    'facility_rows_locked: use the installment purchase and payment flows';
end;
$$;

drop trigger if exists trg_protect_installment_plans
  on app_finance.installment_plans;
create trigger trg_protect_installment_plans
  before insert or update or delete on app_finance.installment_plans
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_installment_dues
  on app_finance.installment_dues;
create trigger trg_protect_installment_dues
  before insert or update or delete on app_finance.installment_dues
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_installment_allocations
  on app_finance.installment_payment_allocations;
create trigger trg_protect_installment_allocations
  before insert or update or delete
  on app_finance.installment_payment_allocations
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_credit_facility_settings_delete
  on app_finance.credit_facility_settings;
create or replace function app_private.protect_facility_settings_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(current_setting('app_finance.facility_internal', true), '')
      = 'on'
    or (select auth.uid()) is null then
    return old;
  end if;
  raise exception
    'facility_rows_locked: facility settings are removed with their account';
end;
$$;
create trigger trg_protect_credit_facility_settings_delete
  before delete on app_finance.credit_facility_settings
  for each row execute function app_private.protect_facility_settings_delete();

-- ---------------------------------------------------------------------------
-- Overdraft enforcement learns about liabilities
-- ---------------------------------------------------------------------------

-- Liability accounts legitimately hold a negative asset-style balance (debt),
-- so the insufficient-funds rule only applies to asset accounts. Facility
-- charges are limit-checked inside the installment RPCs under a row lock.
create or replace function app_private.enforce_account_balance()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account record;
  v_balance bigint;
begin
  if new.source_account_id is null then
    return new;
  end if;
  select allow_negative_balance, is_archived, name, account_type
    into v_account
    from app_finance.accounts
    where id = new.source_account_id;
  if v_account.is_archived then
    raise exception 'account_archived: cannot write to an archived account';
  end if;
  if app_finance.account_role(v_account.account_type) = 'liability' then
    return new;
  end if;
  if v_account.allow_negative_balance then
    return new;
  end if;
  select balance_minor into v_balance
    from app_finance.account_balances
    where account_id = new.source_account_id;
  if v_balance < 0 then
    raise exception 'insufficient_funds: % does not allow negative balance',
      v_account.name;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Derived views (security_invoker so base-table RLS applies)
-- ---------------------------------------------------------------------------

create or replace view app_finance.installment_due_statuses
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
    coalesce(alloc.paid_minor, 0)::bigint as paid_minor,
    (d.amount_minor - coalesce(alloc.paid_minor, 0))::bigint
      as remaining_minor,
    case
      when p.status = 'cancelled' then 'cancelled'
      when coalesce(alloc.paid_minor, 0) >= d.amount_minor then 'paid'
      when d.due_on < current_date then 'overdue'
      when d.due_on = current_date then 'due_today'
      when coalesce(alloc.paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as due_status
  from app_finance.installment_dues d
  join app_finance.installment_plans p on p.id = d.plan_id
  left join (
    select due_id, sum(amount_minor) as paid_minor
    from app_finance.installment_payment_allocations
    group by due_id
  ) alloc on alloc.due_id = d.id;

create or replace view app_finance.installment_plan_summaries
with (security_invoker = on) as
  select
    p.id,
    p.user_id,
    p.account_id,
    p.title,
    p.category_id,
    p.purchased_on,
    p.first_due_on,
    p.installment_count,
    p.purchase_price_minor,
    p.down_payment_minor,
    p.financed_principal_minor,
    p.financing_fees_minor,
    p.total_payable_minor,
    p.currency_code,
    p.status,
    p.notes,
    p.purchase_transaction_id,
    p.down_payment_transaction_id,
    p.created_at,
    coalesce(paid.paid_minor, 0)::bigint as paid_minor,
    (p.total_payable_minor - coalesce(paid.paid_minor, 0))::bigint
      as remaining_minor,
    unpaid.next_due_on,
    unpaid.next_due_amount_minor
  from app_finance.installment_plans p
  left join (
    select d.plan_id, sum(pa.amount_minor) as paid_minor
    from app_finance.installment_dues d
    join app_finance.installment_payment_allocations pa on pa.due_id = d.id
    group by d.plan_id
  ) paid on paid.plan_id = p.id
  left join lateral (
    select s.due_on as next_due_on, s.remaining_minor as next_due_amount_minor
    from app_finance.installment_due_statuses s
    where s.plan_id = p.id and s.remaining_minor > 0
    order by s.due_on, s.sequence_number
    limit 1
  ) unpaid on true;

create or replace view app_finance.credit_facility_summaries
with (security_invoker = on) as
  select
    a.id as account_id,
    a.user_id,
    a.name,
    a.account_type,
    a.currency_code,
    a.is_archived,
    a.notes,
    a.opening_balance_minor as opening_owed_minor,
    s.credit_limit_minor,
    s.statement_day,
    s.default_due_day,
    s.last_four_digits,
    s.reminder_lead_days,
    outstanding.outstanding_minor,
    greatest(s.credit_limit_minor - outstanding.outstanding_minor, 0)::bigint
      as available_credit_minor,
    case
      when outstanding.outstanding_minor <= 0 then 0
      else round(
        (outstanding.outstanding_minor::numeric * 10000)
          / s.credit_limit_minor
      )::integer
    end as utilization_basis_points,
    coalesce(dues.due_now_minor, 0)::bigint as due_now_minor,
    coalesce(dues.overdue_minor, 0)::bigint as overdue_minor,
    dues.next_due_on,
    dues.next_due_amount_minor,
    coalesce(plans.active_plan_count, 0)::integer as active_plan_count
  from app_finance.accounts a
  join app_finance.credit_facility_settings s on s.account_id = a.id
  cross join lateral (
    select app_finance.facility_outstanding_minor(a.id) as outstanding_minor
  ) outstanding
  left join lateral (
    select
      sum(d.remaining_minor)
        filter (where d.due_on <= current_date) as due_now_minor,
      sum(d.remaining_minor)
        filter (where d.due_on < current_date) as overdue_minor,
      min(d.due_on) filter (where d.remaining_minor > 0) as next_due_on,
      (array_agg(d.remaining_minor order by d.due_on, d.sequence_number)
        filter (where d.remaining_minor > 0))[1] as next_due_amount_minor
    from app_finance.installment_due_statuses d
    where d.account_id = a.id
      and d.plan_status = 'active'
      and d.remaining_minor > 0
  ) dues on true
  left join lateral (
    select count(*) as active_plan_count
    from app_finance.installment_plans p
    where p.account_id = a.id and p.status = 'active'
  ) plans on true
  where app_finance.account_role(a.account_type) = 'liability';

-- ---------------------------------------------------------------------------
-- Atomic facility upsert (account + settings)
-- ---------------------------------------------------------------------------

create function app_finance.save_credit_facility(
  p_name text,
  p_account_type app_finance.account_type,
  p_currency_code text,
  p_opening_owed_minor bigint,
  p_credit_limit_minor bigint,
  p_default_due_day smallint,
  p_statement_day smallint default null,
  p_last_four_digits text default null,
  p_reminder_lead_days smallint default 3,
  p_notes text default null,
  p_account_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if app_finance.account_role(p_account_type) <> 'liability' then
    raise exception
      'invalid_account: facility settings require a credit card or BNPL account';
  end if;
  if p_opening_owed_minor < 0 then
    raise exception 'invalid_amount: opening amount owed cannot be negative';
  end if;

  if p_account_id is null then
    insert into app_finance.accounts (
      user_id, name, account_type, currency_code, opening_balance_minor,
      is_default, allow_negative_balance, notes
    ) values (
      v_user_id, p_name, p_account_type, p_currency_code,
      p_opening_owed_minor, false, false, p_notes
    )
    returning id into v_account_id;
  else
    update app_finance.accounts
      set name = p_name,
        account_type = p_account_type,
        opening_balance_minor = p_opening_owed_minor,
        notes = p_notes
      where id = p_account_id and user_id = v_user_id and not is_archived
      returning id into v_account_id;
    if v_account_id is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
  end if;

  insert into app_finance.credit_facility_settings (
    account_id, user_id, credit_limit_minor, statement_day, default_due_day,
    last_four_digits, reminder_lead_days
  ) values (
    v_account_id, v_user_id, p_credit_limit_minor, p_statement_day,
    p_default_due_day, p_last_four_digits, coalesce(p_reminder_lead_days, 3)
  )
  on conflict (account_id) do update set
    credit_limit_minor = excluded.credit_limit_minor,
    statement_day = excluded.statement_day,
    default_due_day = excluded.default_due_day,
    last_four_digits = excluded.last_four_digits,
    reminder_lead_days = excluded.reminder_lead_days;

  return v_account_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic installment purchase
-- ---------------------------------------------------------------------------

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
  p_plan_id uuid default null
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
  v_financed bigint;
  v_fees bigint;
  v_total bigint;
  v_outstanding bigint;
  v_plan_id uuid;
  v_purchase_tx_id uuid;
  v_down_tx_id uuid;
  v_base bigint;
  v_remainder bigint;
  v_seq integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Retry-safe: a client resubmitting the same plan id gets the same plan.
  if p_plan_id is not null then
    select id into v_plan_id
      from app_finance.installment_plans
      where id = p_plan_id and user_id = v_user_id;
    if v_plan_id is not null then
      return v_plan_id;
    end if;
  end if;

  if p_purchase_price_minor is null or p_purchase_price_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if coalesce(p_down_payment_minor, 0) < 0 then
    raise exception 'invalid_amount: down payment cannot be negative';
  end if;
  if p_installment_count is null
    or p_installment_count < 1 or p_installment_count > 120 then
    raise exception
      'invalid_installments: choose between 1 and 120 installments';
  end if;
  if p_first_due_on < p_purchased_on then
    raise exception
      'invalid_date: the first due date cannot precede the purchase date';
  end if;

  -- Locking the facility row serializes concurrent purchases and payments so
  -- two requests can never both spend the same remaining credit.
  select a.id, a.currency_code, a.account_type into v_facility
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
    for update;
  if v_facility is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if app_finance.account_role(v_facility.account_type) <> 'liability' then
    raise exception
      'invalid_account: installment purchases require a credit card or BNPL account';
  end if;

  select credit_limit_minor into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before financing purchases';
  end if;

  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  v_financed := p_purchase_price_minor - coalesce(p_down_payment_minor, 0);
  if v_financed <= 0 then
    raise exception
      'invalid_amount: the financed principal must stay positive';
  end if;

  if p_financing_fees_minor is null and p_total_payable_minor is null then
    v_fees := 0;
    v_total := v_financed;
  elsif p_financing_fees_minor is not null
    and p_total_payable_minor is not null then
    if p_total_payable_minor <> v_financed + p_financing_fees_minor then
      raise exception
        'invalid_financing: fees and total payable disagree';
    end if;
    v_fees := p_financing_fees_minor;
    v_total := p_total_payable_minor;
  elsif p_financing_fees_minor is not null then
    if p_financing_fees_minor < 0 then
      raise exception 'invalid_amount: financing fees cannot be negative';
    end if;
    v_fees := p_financing_fees_minor;
    v_total := v_financed + v_fees;
  else
    if p_total_payable_minor < v_financed then
      raise exception
        'invalid_financing: total payable is below the financed principal';
    end if;
    v_fees := p_total_payable_minor - v_financed;
    v_total := p_total_payable_minor;
  end if;

  if coalesce(p_down_payment_minor, 0) > 0 then
    if p_down_payment_account_id is null then
      raise exception
        'invalid_account: a down payment needs a funding account';
    end if;
    select a.id, a.currency_code, a.account_type into v_down_account
      from app_finance.accounts a
      where a.id = p_down_payment_account_id and a.user_id = v_user_id
        and not a.is_archived;
    if v_down_account is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
    if app_finance.account_role(v_down_account.account_type) <> 'asset' then
      raise exception
        'invalid_account: down payments come from an asset account';
    end if;
    if v_down_account.currency_code <> v_facility.currency_code then
      raise exception
        'currency_mismatch: down payment account must match the facility';
    end if;
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + v_total > v_settings.credit_limit_minor then
    raise exception
      'insufficient_credit: purchase exceeds available credit';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  -- One reportable expense for the financed principal plus fees, dated on
  -- the purchase business date. Monthly dues are schedule rows only.
  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    v_user_id, 'expense', p_purchased_on, v_total,
    v_facility.currency_code, p_account_id, p_category_id, p_title, p_notes
  )
  returning id into v_purchase_tx_id;

  if coalesce(p_down_payment_minor, 0) > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', p_purchased_on, p_down_payment_minor,
      v_facility.currency_code, p_down_payment_account_id, p_category_id,
      p_title, p_notes
    )
    returning id into v_down_tx_id;
  end if;

  insert into app_finance.installment_plans (
    id, user_id, account_id, purchase_transaction_id,
    down_payment_transaction_id, title, category_id, purchased_on,
    first_due_on, installment_count, purchase_price_minor,
    down_payment_minor, financed_principal_minor, financing_fees_minor,
    total_payable_minor, currency_code, notes
  ) values (
    coalesce(p_plan_id, gen_random_uuid()), v_user_id, p_account_id,
    v_purchase_tx_id, v_down_tx_id, p_title, p_category_id, p_purchased_on,
    p_first_due_on, p_installment_count, p_purchase_price_minor,
    coalesce(p_down_payment_minor, 0), v_financed, v_fees, v_total,
    v_facility.currency_code, p_notes
  )
  returning id into v_plan_id;

  -- Deterministic equal split in integer minor units: the first
  -- (total mod count) installments carry one extra minor unit, so the
  -- schedule always sums to the exact total payable.
  v_base := v_total / p_installment_count;
  v_remainder := v_total % p_installment_count;
  for v_seq in 1..p_installment_count loop
    insert into app_finance.installment_dues (
      user_id, plan_id, sequence_number, due_on, amount_minor
    ) values (
      v_user_id, v_plan_id, v_seq,
      -- Calendar months from the first due date; PostgreSQL clamps to the
      -- last valid day of shorter months (Jan 31 -> Feb 28/29 -> Mar 31).
      (p_first_due_on + make_interval(months => v_seq - 1))::date,
      v_base + case when v_seq <= v_remainder then 1 else 0 end
    );
  end loop;

  return v_plan_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic facility payment with due allocation
-- ---------------------------------------------------------------------------

create function app_finance.pay_credit_facility(
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
  v_allocation jsonb;
  v_alloc_amount bigint;
  v_alloc_total bigint := 0;
  v_take bigint;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  -- Retry-safe: resubmitting the same payment id returns the same transfer.
  if p_payment_id is not null then
    select id into v_tx_id
      from app_finance.financial_transactions
      where id = p_payment_id and user_id = v_user_id;
    if v_tx_id is not null then
      return v_tx_id;
    end if;
  end if;

  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select a.id, a.currency_code, a.account_type into v_facility
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
    for update;
  if v_facility is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if app_finance.account_role(v_facility.account_type) <> 'liability' then
    raise exception
      'invalid_account: facility payments go to a credit card or BNPL account';
  end if;

  select a.id, a.currency_code, a.account_type into v_source
    from app_finance.accounts a
    where a.id = p_source_account_id and a.user_id = v_user_id
      and not a.is_archived;
  if v_source is null then
    raise exception 'invalid_account: source not found or archived';
  end if;
  if app_finance.account_role(v_source.account_type) <> 'asset' then
    raise exception
      'invalid_account: facility payments come from an asset account';
  end if;
  if v_source.currency_code <> v_facility.currency_code then
    raise exception 'currency_mismatch: transfers require matching currencies';
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if p_amount_minor > v_outstanding then
    raise exception
      'overpayment_rejected: payment exceeds the amount owed';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, notes
  ) values (
    coalesce(p_payment_id, gen_random_uuid()), v_user_id, 'transfer',
    p_paid_on, p_amount_minor, v_facility.currency_code,
    p_source_account_id, p_account_id, p_notes
  )
  returning id into v_tx_id;

  v_left := p_amount_minor;

  if p_allocations is not null then
    if jsonb_typeof(p_allocations) <> 'array' then
      raise exception 'invalid_allocations: expected an array';
    end if;
    for v_allocation in select * from jsonb_array_elements(p_allocations)
    loop
      v_alloc_amount := (v_allocation ->> 'amount_minor')::bigint;
      if v_alloc_amount is null or v_alloc_amount <= 0 then
        raise exception 'invalid_amount: must be positive';
      end if;
      select s.id, s.remaining_minor into v_due
        from app_finance.installment_due_statuses s
        where s.id = (v_allocation ->> 'due_id')::uuid
          and s.user_id = v_user_id
          and s.account_id = p_account_id
          and s.plan_status = 'active';
      if v_due is null then
        raise exception 'not_found: installment due';
      end if;
      if v_alloc_amount > v_due.remaining_minor then
        raise exception
          'allocation_exceeds_due: allocation is larger than the remaining due';
      end if;
      v_alloc_total := v_alloc_total + v_alloc_amount;
      if v_alloc_total > p_amount_minor then
        raise exception
          'allocation_exceeds_payment: allocations are larger than the payment';
      end if;
      insert into app_finance.installment_payment_allocations (
        user_id, payment_transaction_id, due_id, amount_minor
      ) values (v_user_id, v_tx_id, v_due.id, v_alloc_amount);
    end loop;
  else
    -- Auto-allocation: overdue first, then due today, then upcoming —
    -- which is exactly ascending due date, oldest sequence first.
    for v_due in
      select s.id, s.remaining_minor
      from app_finance.installment_due_statuses s
      where s.user_id = v_user_id
        and s.account_id = p_account_id
        and s.plan_status = 'active'
        and s.remaining_minor > 0
      order by s.due_on, s.sequence_number, s.id
    loop
      exit when v_left <= 0;
      v_take := least(v_left, v_due.remaining_minor);
      insert into app_finance.installment_payment_allocations (
        user_id, payment_transaction_id, due_id, amount_minor
      ) values (v_user_id, v_tx_id, v_due.id, v_take);
      v_left := v_left - v_take;
    end loop;
  end if;

  -- A plan completes only when every due is fully covered.
  update app_finance.installment_plans p
    set status = 'completed'
    where p.user_id = v_user_id
      and p.account_id = p_account_id
      and p.status = 'active'
      and not exists (
        select 1 from app_finance.installment_due_statuses s
        where s.plan_id = p.id and s.remaining_minor > 0
      );

  return v_tx_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reverse a facility payment
-- ---------------------------------------------------------------------------

create function app_finance.reverse_facility_payment(
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

  -- The opposite transfer on the original business date keeps every ranged
  -- report neutral and preserves the full audit trail of both movements.
  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, facility_reversal_of_id
  ) values (
    v_user_id, 'transfer', v_payment.occurred_on, v_payment.amount_minor,
    v_payment.currency_code, v_payment.destination_account_id,
    v_payment.source_account_id, p_transaction_id
  )
  returning id into v_reversal_id;

  -- Reopen plans whose dues are unpaid again.
  update app_finance.installment_plans p
    set status = 'active'
    where p.user_id = v_user_id
      and p.status = 'completed'
      and exists (
        select 1 from app_finance.installment_due_statuses s
        where s.plan_id = p.id and s.remaining_minor > 0
      );

  return v_reversal_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cancel a plan that has no payments yet
-- ---------------------------------------------------------------------------

create function app_finance.cancel_installment_plan(
  p_plan_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_plan record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select p.id, p.purchase_transaction_id, p.down_payment_transaction_id
    into v_plan
    from app_finance.installment_plans p
    where p.id = p_plan_id and p.user_id = v_user_id
    for update;
  if v_plan is null then
    raise exception 'not_found: installment plan';
  end if;
  if exists (
    select 1
    from app_finance.installment_payment_allocations pa
    join app_finance.installment_dues d on d.id = pa.due_id
    where d.plan_id = p_plan_id
  ) then
    raise exception
      'plan_has_payments: reverse the payments before cancelling';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  update app_finance.installment_plans
    set status = 'cancelled'
    where id = p_plan_id and user_id = v_user_id;

  -- Cancelling before any repayment removes the generated purchase records,
  -- matching how held-amount settlements manage their booked transactions.
  delete from app_finance.financial_transactions
    where user_id = v_user_id
      and id in (
        v_plan.purchase_transaction_id, v_plan.down_payment_transaction_id
      );
end;
$$;

-- ---------------------------------------------------------------------------
-- Debt reporting: repayments and upcoming commitments
-- ---------------------------------------------------------------------------

create function app_reports.debt_summary(
  p_start date,
  p_end date
)
returns table (
  currency_code text,
  repayments_minor bigint,
  upcoming_dues_minor bigint,
  overdue_minor bigint,
  outstanding_minor bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_start > p_end then
    raise exception 'invalid_range: start must be on or before end';
  end if;

  return query
  with facilities as (
    select f.account_id, f.currency_code, f.outstanding_minor,
        f.overdue_minor
    from app_finance.credit_facility_summaries f
    where f.user_id = v_user_id and not f.is_archived
  ),
  repayments as (
    select t.currency_code, sum(t.amount_minor) as repayments_minor
    from app_finance.financial_transactions t
    join facilities f on f.account_id = t.destination_account_id
    where t.user_id = v_user_id
      and t.transaction_kind = 'transfer'
      and t.occurred_on between p_start and p_end
      and t.facility_reversal_of_id is null
    group by t.currency_code
  ),
  reversals as (
    select t.currency_code, sum(t.amount_minor) as reversed_minor
    from app_finance.financial_transactions t
    join facilities f on f.account_id = t.source_account_id
    where t.user_id = v_user_id
      and t.transaction_kind = 'transfer'
      and t.occurred_on between p_start and p_end
      and t.facility_reversal_of_id is not null
    group by t.currency_code
  ),
  upcoming as (
    select s.currency_code, sum(s.remaining_minor) as upcoming_dues_minor
    from app_finance.installment_due_statuses s
    join facilities f on f.account_id = s.account_id
    where s.user_id = v_user_id
      and s.plan_status = 'active'
      and s.remaining_minor > 0
      and s.due_on between p_start and p_end
    group by s.currency_code
  ),
  totals as (
    select f.currency_code,
        sum(f.outstanding_minor) as outstanding_minor,
        sum(f.overdue_minor) as overdue_minor
    from facilities f
    group by f.currency_code
  )
  select
    totals.currency_code,
    (coalesce(repayments.repayments_minor, 0)
      - coalesce(reversals.reversed_minor, 0))::bigint,
    coalesce(upcoming.upcoming_dues_minor, 0)::bigint,
    coalesce(totals.overdue_minor, 0)::bigint,
    coalesce(totals.outstanding_minor, 0)::bigint
  from totals
  left join repayments on repayments.currency_code = totals.currency_code
  left join reversals on reversals.currency_code = totals.currency_code
  left join upcoming on upcoming.currency_code = totals.currency_code
  order by totals.currency_code;
end;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion cascade learns the facility tables
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

  update app_salary.salary_periods
    set paid_transaction_id = null
    where user_id = p_user_id;
  update app_finance.income_occurrences
    set primary_transaction_id = null
    where user_id = p_user_id;
  update app_finance.financial_transactions
    set salary_period_id = null, income_occurrence_id = null
    where user_id = p_user_id;

  delete from app_finance.installment_payment_allocations
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
end;
$$;

comment on function app_core.delete_finance_suit_data(uuid) is
  'Deletes Finance Suit product data only; preserves shared Auth and public legacy data.';

revoke all on function app_core.delete_finance_suit_data(uuid) from public;
revoke all on function app_core.delete_finance_suit_data(uuid) from anon;
revoke all on function app_core.delete_finance_suit_data(uuid) from authenticated;
grant execute on function app_core.delete_finance_suit_data(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- Function grants
-- ---------------------------------------------------------------------------

revoke execute on function app_finance.account_role(app_finance.account_type)
from public, anon;
grant execute on function app_finance.account_role(app_finance.account_type)
to authenticated, service_role;

revoke execute on function app_finance.facility_outstanding_minor(uuid)
from public, anon;
grant execute on function app_finance.facility_outstanding_minor(uuid)
to authenticated, service_role;

revoke execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, bigint, smallint, smallint,
  text, smallint, text, uuid
) from public, anon;
grant execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, bigint, smallint, smallint,
  text, smallint, text, uuid
) to authenticated, service_role;

revoke execute on function app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid
) from public, anon;
grant execute on function app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid
) to authenticated, service_role;

revoke execute on function app_finance.pay_credit_facility(
  uuid, uuid, bigint, date, jsonb, text, uuid
) from public, anon;
grant execute on function app_finance.pay_credit_facility(
  uuid, uuid, bigint, date, jsonb, text, uuid
) to authenticated, service_role;

revoke execute on function app_finance.reverse_facility_payment(uuid)
from public, anon;
grant execute on function app_finance.reverse_facility_payment(uuid)
to authenticated, service_role;

revoke execute on function app_finance.cancel_installment_plan(uuid)
from public, anon;
grant execute on function app_finance.cancel_installment_plan(uuid)
to authenticated, service_role;

revoke execute on function app_reports.debt_summary(date, date)
from public, anon;
grant execute on function app_reports.debt_summary(date, date)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'credit_facility_settings',
    'installment_plans',
    'installment_dues',
    'installment_payment_allocations'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'app_finance'
        and tablename = v_table
    ) then
      execute format(
        'alter publication supabase_realtime add table app_finance.%I',
        v_table
      );
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
