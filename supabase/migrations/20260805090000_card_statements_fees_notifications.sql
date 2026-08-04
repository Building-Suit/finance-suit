-- Credit-card lifecycle, statement cycles, fee rules, richer installment
-- pricing, running-plan import, plan revisions, and push-notification
-- infrastructure. Liability accounting stays unchanged: purchases are one
-- expense on their business date, statement and installment dues are
-- obligations rather than transactions, and repayments are transfers.
-- "Opening amount owed" disappears from all create/edit flows; legacy values
-- already stored in accounts.opening_balance_minor keep counting toward the
-- outstanding debt so no existing balance silently changes.

-- ---------------------------------------------------------------------------
-- New enums (fresh types, so same-transaction use is safe)
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'facility_status') then
    create type app_finance.facility_status as enum
      ('active', 'frozen', 'closed');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'plan_pricing_method') then
    create type app_finance.plan_pricing_method as enum
      ('manual_fees', 'monthly_amount', 'total_payable', 'interest_rate');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'interest_rate_period') then
    create type app_finance.interest_rate_period as enum
      ('monthly', 'annual');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'interest_method') then
    create type app_finance.interest_method as enum ('flat', 'reducing');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'plan_origin') then
    create type app_finance.plan_origin as enum ('app', 'historical_import');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'min_payment_method') then
    create type app_finance.min_payment_method as enum
      ('full', 'fixed', 'percent', 'greater_of');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'card_fee_type') then
    create type app_finance.card_fee_type as enum
      ('annual_membership', 'insurance', 'administration', 'stamp_tax',
       'foreign_transaction', 'cash_advance', 'late_payment', 'over_limit',
       'installment_conversion', 'other');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'fee_frequency') then
    create type app_finance.fee_frequency as enum
      ('once', 'monthly', 'quarterly', 'annually');
  end if;
  if not exists (select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'fee_percent_basis') then
    create type app_finance.fee_percent_basis as enum
      ('statement_balance', 'outstanding_balance', 'credit_limit');
  end if;
end $$;

grant usage on type app_finance.facility_status to authenticated, service_role;
grant usage on type app_finance.plan_pricing_method
to authenticated, service_role;
grant usage on type app_finance.interest_rate_period
to authenticated, service_role;
grant usage on type app_finance.interest_method to authenticated, service_role;
grant usage on type app_finance.plan_origin to authenticated, service_role;
grant usage on type app_finance.min_payment_method
to authenticated, service_role;
grant usage on type app_finance.card_fee_type to authenticated, service_role;
grant usage on type app_finance.fee_frequency to authenticated, service_role;
grant usage on type app_finance.fee_percent_basis
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Facility lifecycle and card billing settings
-- ---------------------------------------------------------------------------

alter table app_finance.credit_facility_settings
  add column if not exists facility_status app_finance.facility_status
    not null default 'active',
  add column if not exists min_payment_method app_finance.min_payment_method
    not null default 'full',
  add column if not exists min_payment_fixed_minor bigint
    check (min_payment_fixed_minor is null or min_payment_fixed_minor > 0),
  add column if not exists min_payment_basis_points integer
    check (min_payment_basis_points is null
      or min_payment_basis_points between 1 and 10000);

comment on column app_finance.credit_facility_settings.statement_day is
  'Credit-card statement CLOSING day of month (clamped in short months). '
  'The payment for a closed cycle falls due on the next default_due_day.';

-- ---------------------------------------------------------------------------
-- Installment plan pricing, origin, and revisions
-- ---------------------------------------------------------------------------

alter table app_finance.installment_plans
  add column if not exists pricing_method app_finance.plan_pricing_method
    not null default 'manual_fees',
  add column if not exists interest_rate_basis_points integer not null
    default 0,
  add column if not exists interest_rate_period
    app_finance.interest_rate_period not null default 'monthly',
  add column if not exists interest_method app_finance.interest_method
    not null default 'flat',
  add column if not exists interest_minor bigint not null default 0
    check (interest_minor >= 0),
  add column if not exists origin app_finance.plan_origin
    not null default 'app',
  add column if not exists revision integer not null default 1
    check (revision >= 1);

alter table app_finance.installment_plans
  drop constraint if exists installment_plans_rate_range;
alter table app_finance.installment_plans
  add constraint installment_plans_rate_range
  check (interest_rate_basis_points between 0 and 100000);
alter table app_finance.installment_plans
  drop constraint if exists installment_plans_interest_within_fees;
alter table app_finance.installment_plans
  add constraint installment_plans_interest_within_fees
  check (interest_minor <= financing_fees_minor);

-- Dues paid before Finance Suit tracking began (imported running plans).
alter table app_finance.installment_dues
  add column if not exists is_presettled boolean not null default false;

create table if not exists app_finance.installment_plan_revisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid not null,
  revision integer not null check (revision >= 1),
  change_summary text not null check (char_length(change_summary) <= 1000),
  previous_total_payable_minor bigint not null,
  new_total_payable_minor bigint not null,
  created_at timestamptz not null default now(),
  constraint plan_revisions_owner_unique unique (id, user_id),
  constraint plan_revisions_unique unique (plan_id, revision),
  constraint plan_revisions_plan_owner_fk foreign key (plan_id, user_id)
    references app_finance.installment_plans (id, user_id) on delete cascade
);

create index if not exists idx_plan_revisions_plan
  on app_finance.installment_plan_revisions (plan_id, user_id);

alter table app_finance.installment_plan_revisions enable row level security;
drop policy if exists installment_plan_revisions_select
  on app_finance.installment_plan_revisions;
create policy installment_plan_revisions_select
  on app_finance.installment_plan_revisions
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists installment_plan_revisions_insert
  on app_finance.installment_plan_revisions;
create policy installment_plan_revisions_insert
  on app_finance.installment_plan_revisions
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists installment_plan_revisions_delete
  on app_finance.installment_plan_revisions;
create policy installment_plan_revisions_delete
  on app_finance.installment_plan_revisions
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Credit-card statement cycles
-- ---------------------------------------------------------------------------

create table if not exists app_finance.credit_card_statement_cycles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  cycle_start date not null,
  cycle_close date not null,
  due_on date not null,
  created_at timestamptz not null default now(),
  constraint statement_cycles_owner_unique unique (id, user_id),
  constraint statement_cycles_close_unique unique (account_id, cycle_close),
  constraint statement_cycles_dates check (
    cycle_start <= cycle_close and cycle_close <= due_on
  ),
  constraint statement_cycles_account_owner_fk
    foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id) on delete cascade
);

create index if not exists idx_statement_cycles_account
  on app_finance.credit_card_statement_cycles
  (account_id, user_id, cycle_close);

-- One card charge belongs to exactly one statement cycle.
create table if not exists app_finance.credit_card_statement_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  cycle_id uuid not null,
  transaction_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint statement_items_owner_unique unique (id, user_id),
  constraint statement_items_transaction_unique unique (transaction_id),
  constraint statement_items_cycle_owner_fk foreign key (cycle_id, user_id)
    references app_finance.credit_card_statement_cycles (id, user_id)
    on delete cascade,
  constraint statement_items_tx_owner_fk foreign key (transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade
);

create index if not exists idx_statement_items_cycle
  on app_finance.credit_card_statement_items (cycle_id, user_id);

create table if not exists app_finance.credit_card_statement_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  payment_transaction_id uuid not null,
  cycle_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint statement_allocations_owner_unique unique (id, user_id),
  constraint statement_allocations_pair_unique
    unique (payment_transaction_id, cycle_id),
  constraint statement_allocations_payment_owner_fk
    foreign key (payment_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade,
  constraint statement_allocations_cycle_owner_fk
    foreign key (cycle_id, user_id)
    references app_finance.credit_card_statement_cycles (id, user_id)
    on delete cascade
);

create index if not exists idx_statement_allocations_cycle
  on app_finance.credit_card_statement_allocations (cycle_id, user_id);
create index if not exists idx_statement_allocations_payment
  on app_finance.credit_card_statement_allocations
  (payment_transaction_id, user_id);

-- ---------------------------------------------------------------------------
-- Card fee rules and generated fee charges
-- ---------------------------------------------------------------------------

create table if not exists app_finance.credit_card_fee_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  name text not null check (char_length(name) between 1 and 80),
  fee_type app_finance.card_fee_type not null,
  fixed_amount_minor bigint
    check (fixed_amount_minor is null or fixed_amount_minor > 0),
  percent_basis_points integer
    check (percent_basis_points is null
      or percent_basis_points between 1 and 100000),
  percent_basis app_finance.fee_percent_basis,
  frequency app_finance.fee_frequency not null default 'annually',
  starts_on date not null,
  next_charge_on date,
  category_id uuid not null,
  is_active boolean not null default true,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fee_rules_owner_unique unique (id, user_id),
  constraint fee_rules_account_owner_fk foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id) on delete cascade,
  constraint fee_rules_category_owner_fk foreign key (category_id, user_id)
    references app_finance.transaction_categories (id, user_id),
  constraint fee_rules_amount_shape check (
    (fixed_amount_minor is not null
      and percent_basis_points is null and percent_basis is null)
    or (fixed_amount_minor is null
      and percent_basis_points is not null and percent_basis is not null)
  )
);

drop trigger if exists trg_fee_rules_updated_at
  on app_finance.credit_card_fee_rules;
create trigger trg_fee_rules_updated_at
  before update on app_finance.credit_card_fee_rules
  for each row execute function app_private.set_updated_at();

create index if not exists idx_fee_rules_account
  on app_finance.credit_card_fee_rules (account_id, user_id, is_active);
create index if not exists idx_fee_rules_category_owner_fk
  on app_finance.credit_card_fee_rules (category_id, user_id);

alter table app_finance.credit_card_fee_rules enable row level security;
drop policy if exists credit_card_fee_rules_select
  on app_finance.credit_card_fee_rules;
create policy credit_card_fee_rules_select
  on app_finance.credit_card_fee_rules
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_rules_insert
  on app_finance.credit_card_fee_rules;
create policy credit_card_fee_rules_insert
  on app_finance.credit_card_fee_rules
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_rules_update
  on app_finance.credit_card_fee_rules;
create policy credit_card_fee_rules_update
  on app_finance.credit_card_fee_rules
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_rules_delete
  on app_finance.credit_card_fee_rules;
create policy credit_card_fee_rules_delete
  on app_finance.credit_card_fee_rules
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Fee charges generated from a rule; the expense transaction is the ledger
-- truth and the (rule, charged_on) pair keeps cron retries idempotent.
create table if not exists app_finance.credit_card_fee_charges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  rule_id uuid not null,
  transaction_id uuid not null,
  charged_on date not null,
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now(),
  constraint fee_charges_owner_unique unique (id, user_id),
  constraint fee_charges_once_per_date unique (rule_id, charged_on),
  constraint fee_charges_rule_owner_fk foreign key (rule_id, user_id)
    references app_finance.credit_card_fee_rules (id, user_id)
    on delete cascade,
  constraint fee_charges_tx_owner_fk foreign key (transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade
);

create index if not exists idx_fee_charges_rule
  on app_finance.credit_card_fee_charges (rule_id, user_id);
create index if not exists idx_fee_charges_tx
  on app_finance.credit_card_fee_charges (transaction_id, user_id);

alter table app_finance.credit_card_fee_charges enable row level security;
drop policy if exists credit_card_fee_charges_select
  on app_finance.credit_card_fee_charges;
create policy credit_card_fee_charges_select
  on app_finance.credit_card_fee_charges
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_charges_insert
  on app_finance.credit_card_fee_charges;
create policy credit_card_fee_charges_insert
  on app_finance.credit_card_fee_charges
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists credit_card_fee_charges_delete
  on app_finance.credit_card_fee_charges;
create policy credit_card_fee_charges_delete
  on app_finance.credit_card_fee_charges
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Push devices, notification preferences, and delivery outbox
-- ---------------------------------------------------------------------------

create table if not exists app_core.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  fcm_token text not null check (char_length(fcm_token) between 8 and 4096),
  platform text not null check (platform in ('android', 'ios', 'web')),
  app_version text check (char_length(app_version) <= 40),
  locale text check (char_length(locale) <= 20),
  timezone text not null default 'Africa/Cairo'
    check (char_length(timezone) <= 64),
  is_enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_devices_owner_unique unique (id, user_id),
  constraint push_devices_token_unique unique (user_id, fcm_token)
);

drop trigger if exists trg_push_devices_updated_at on app_core.push_devices;
create trigger trg_push_devices_updated_at
  before update on app_core.push_devices
  for each row execute function app_private.set_updated_at();

create index if not exists idx_push_devices_user
  on app_core.push_devices (user_id, is_enabled);

alter table app_core.push_devices enable row level security;
drop policy if exists push_devices_select on app_core.push_devices;
create policy push_devices_select on app_core.push_devices
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists push_devices_insert on app_core.push_devices;
create policy push_devices_insert on app_core.push_devices
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists push_devices_update on app_core.push_devices;
create policy push_devices_update on app_core.push_devices
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists push_devices_delete on app_core.push_devices;
create policy push_devices_delete on app_core.push_devices
  for delete to authenticated using ((select auth.uid()) = user_id);

create table if not exists app_core.notification_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  due_reminders_enabled boolean not null default true,
  show_amounts boolean not null default false,
  overdue_reminders_enabled boolean not null default true,
  payment_confirmations_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_notification_preferences_updated_at
  on app_core.notification_preferences;
create trigger trg_notification_preferences_updated_at
  before update on app_core.notification_preferences
  for each row execute function app_private.set_updated_at();

alter table app_core.notification_preferences enable row level security;
drop policy if exists notification_preferences_select
  on app_core.notification_preferences;
create policy notification_preferences_select
  on app_core.notification_preferences
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists notification_preferences_insert
  on app_core.notification_preferences;
create policy notification_preferences_insert
  on app_core.notification_preferences
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists notification_preferences_update
  on app_core.notification_preferences;
create policy notification_preferences_update
  on app_core.notification_preferences
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists notification_preferences_delete
  on app_core.notification_preferences;
create policy notification_preferences_delete
  on app_core.notification_preferences
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Written only by the trusted sender (service role); clients may read their
-- own delivery history but never insert or edit rows.
create table if not exists app_core.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id uuid not null references app_core.push_devices (id)
    on delete cascade,
  obligation_type text not null check (
    obligation_type in
      ('installment_due', 'statement_due', 'payment', 'plan', 'general')
  ),
  obligation_id uuid not null,
  reminder_kind text not null check (
    reminder_kind in
      ('lead', 'due_tomorrow', 'due_today', 'overdue', 'payment_success',
       'plan_completed', 'near_limit')
  ),
  scheduled_local_date date not null,
  sent_at timestamptz,
  error text,
  created_at timestamptz not null default now(),
  constraint notification_outbox_idempotent unique
    (user_id, device_id, obligation_type, obligation_id, reminder_kind,
     scheduled_local_date)
);

create index if not exists idx_notification_outbox_user
  on app_core.notification_outbox (user_id, created_at);

alter table app_core.notification_outbox enable row level security;
drop policy if exists notification_outbox_select
  on app_core.notification_outbox;
create policy notification_outbox_select on app_core.notification_outbox
  for select to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Lifecycle guard rails: archiving no longer requires a settled card
-- ---------------------------------------------------------------------------

-- Archiving hides a facility from pickers but never hides unpaid debt: dues
-- and outstanding amounts stay visible on Home, Money, and Reports, and
-- payments remain possible until the balance reaches zero.
create or replace function app_private.enforce_liability_account_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_role text := app_finance.account_role(new.account_type);
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
  end if;

  return new;
end;
$$;

-- Statement, fee, and revision rows follow the same rule as installment
-- rows: only the facility RPCs (transaction-local flag) or service-role
-- sessions may write them.
drop trigger if exists trg_protect_statement_cycles
  on app_finance.credit_card_statement_cycles;
create trigger trg_protect_statement_cycles
  before insert or update or delete
  on app_finance.credit_card_statement_cycles
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_statement_items
  on app_finance.credit_card_statement_items;
create trigger trg_protect_statement_items
  before insert or update or delete
  on app_finance.credit_card_statement_items
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_statement_allocations
  on app_finance.credit_card_statement_allocations;
create trigger trg_protect_statement_allocations
  before insert or update or delete
  on app_finance.credit_card_statement_allocations
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_fee_charges
  on app_finance.credit_card_fee_charges;
create trigger trg_protect_fee_charges
  before insert or update or delete
  on app_finance.credit_card_fee_charges
  for each row execute function app_private.protect_installment_rows();

drop trigger if exists trg_protect_plan_revisions
  on app_finance.installment_plan_revisions;
create trigger trg_protect_plan_revisions
  before insert or update or delete
  on app_finance.installment_plan_revisions
  for each row execute function app_private.protect_installment_rows();

-- ---------------------------------------------------------------------------
-- Statement cycle helpers
-- ---------------------------------------------------------------------------

create or replace function app_finance.clamp_day_of_month(
  p_year integer,
  p_month integer,
  p_day integer
)
returns date
language sql
immutable
set search_path = ''
as $$
  select make_date(
    p_year,
    p_month,
    least(
      p_day,
      extract(day from (
        make_date(p_year, p_month, 1) + interval '1 month - 1 day'
      ))::integer
    )
  );
$$;

-- The statement cycle containing a business date: a charge on or before the
-- clamped closing day belongs to the cycle closing that day; later charges
-- roll into the next month's cycle. The due date is the next default due
-- day strictly after the close.
create or replace function app_finance.statement_bounds_for(
  p_closing_day integer,
  p_due_day integer,
  p_on date
)
returns table (cycle_start date, cycle_close date, due_on date)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_close date;
  v_prev_close date;
  v_due date;
begin
  v_close := app_finance.clamp_day_of_month(
    extract(year from p_on)::integer,
    extract(month from p_on)::integer,
    p_closing_day
  );
  if v_close < p_on then
    v_close := app_finance.clamp_day_of_month(
      extract(year from (p_on + interval '1 month'))::integer,
      extract(month from (p_on + interval '1 month'))::integer,
      p_closing_day
    );
  end if;
  v_prev_close := app_finance.clamp_day_of_month(
    extract(year from (v_close - interval '1 month'))::integer,
    extract(month from (v_close - interval '1 month'))::integer,
    p_closing_day
  );
  v_due := app_finance.clamp_day_of_month(
    extract(year from v_close)::integer,
    extract(month from v_close)::integer,
    p_due_day
  );
  if v_due <= v_close then
    v_due := app_finance.clamp_day_of_month(
      extract(year from (v_close + interval '1 month'))::integer,
      extract(month from (v_close + interval '1 month'))::integer,
      p_due_day
    );
  end if;
  return query select v_prev_close + 1, v_close, v_due;
end;
$$;

-- ---------------------------------------------------------------------------
-- Derived views
-- ---------------------------------------------------------------------------

-- The redefinitions add columns in the middle of the existing views, which
-- CREATE OR REPLACE VIEW cannot do (42P16). Drop the old views first,
-- dependents before dependencies; every one is recreated below in the same
-- transaction, so nothing can observe the gap.
drop view if exists app_finance.credit_facility_summaries;
drop view if exists app_finance.installment_plan_summaries;
drop view if exists app_finance.installment_due_statuses;

-- Imported plans mark their pre-tracking dues as presettled: those dues are
-- fully paid without any current-period cash transfer.
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
    d.is_presettled,
    (coalesce(alloc.paid_minor, 0)
      + case when d.is_presettled then d.amount_minor else 0 end)::bigint
      as paid_minor,
    greatest(
      d.amount_minor - coalesce(alloc.paid_minor, 0)
        - case when d.is_presettled then d.amount_minor else 0 end,
      0
    )::bigint as remaining_minor,
    case
      when p.status = 'cancelled' then 'cancelled'
      when d.is_presettled
        or coalesce(alloc.paid_minor, 0) >= d.amount_minor then 'paid'
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
    p.interest_minor,
    p.total_payable_minor,
    p.currency_code,
    p.status,
    p.pricing_method,
    p.interest_rate_basis_points,
    p.interest_rate_period,
    p.interest_method,
    p.origin,
    p.revision,
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
    select s.plan_id, sum(s.paid_minor) as paid_minor
    from app_finance.installment_due_statuses s
    group by s.plan_id
  ) paid on paid.plan_id = p.id
  left join lateral (
    select s.due_on as next_due_on, s.remaining_minor as next_due_amount_minor
    from app_finance.installment_due_statuses s
    where s.plan_id = p.id and s.remaining_minor > 0
    order by s.due_on, s.sequence_number
    limit 1
  ) unpaid on true;

-- Statement cycles with charges, fees, credits, payments, and derived
-- status. Closing a cycle never books a transaction; these are obligations.
create or replace view app_finance.credit_card_statement_summaries
with (security_invoker = on) as
  select
    c.id,
    c.user_id,
    c.account_id,
    a.currency_code,
    c.cycle_start,
    c.cycle_close,
    c.due_on,
    coalesce(items.charges_minor, 0)::bigint as charges_minor,
    coalesce(paid.paid_minor, 0)::bigint as paid_minor,
    greatest(
      coalesce(items.charges_minor, 0) - coalesce(paid.paid_minor, 0), 0
    )::bigint as remaining_minor,
    case
      when s.min_payment_method = 'fixed' then
        least(coalesce(s.min_payment_fixed_minor, 0),
          coalesce(items.charges_minor, 0))
      when s.min_payment_method = 'percent' then
        (coalesce(items.charges_minor, 0)
          * coalesce(s.min_payment_basis_points, 0) / 10000)
      when s.min_payment_method = 'greater_of' then
        least(
          greatest(
            coalesce(s.min_payment_fixed_minor, 0),
            coalesce(items.charges_minor, 0)
              * coalesce(s.min_payment_basis_points, 0) / 10000
          ),
          coalesce(items.charges_minor, 0)
        )
      else coalesce(items.charges_minor, 0)
    end::bigint as minimum_due_minor,
    case
      when coalesce(items.charges_minor, 0) = 0 then 'paid'
      when coalesce(paid.paid_minor, 0) >= coalesce(items.charges_minor, 0)
        then 'paid'
      when current_date <= c.cycle_close then 'open'
      when c.due_on < current_date then 'overdue'
      when c.due_on = current_date then 'due_today'
      when coalesce(paid.paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as cycle_status
  from app_finance.credit_card_statement_cycles c
  join app_finance.accounts a on a.id = c.account_id
  join app_finance.credit_facility_settings s on s.account_id = c.account_id
  left join (
    select cycle_id, sum(amount_minor) as charges_minor
    from app_finance.credit_card_statement_items
    group by cycle_id
  ) items on items.cycle_id = c.id
  left join (
    select cycle_id, sum(amount_minor) as paid_minor
    from app_finance.credit_card_statement_allocations
    group by cycle_id
  ) paid on paid.cycle_id = c.id;

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
    s.facility_status,
    s.min_payment_method,
    s.min_payment_fixed_minor,
    s.min_payment_basis_points,
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
    (coalesce(dues.due_now_minor, 0)
      + coalesce(cycles.due_now_minor, 0))::bigint as due_now_minor,
    (coalesce(dues.overdue_minor, 0)
      + coalesce(cycles.overdue_minor, 0))::bigint as overdue_minor,
    least(dues.next_due_on, cycles.next_due_on) as next_due_on,
    case
      when cycles.next_due_on is not null
        and (dues.next_due_on is null
          or cycles.next_due_on <= dues.next_due_on)
        then cycles.next_due_amount_minor
      else dues.next_due_amount_minor
    end as next_due_amount_minor,
    coalesce(cycles.statement_remaining_minor, 0)::bigint
      as statement_remaining_minor,
    cycles.next_due_on as next_statement_due_on,
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
    select
      sum(y.remaining_minor)
        filter (where y.due_on <= current_date
          and y.cycle_close < current_date) as due_now_minor,
      sum(y.remaining_minor)
        filter (where y.due_on < current_date) as overdue_minor,
      min(y.due_on) filter (where y.remaining_minor > 0) as next_due_on,
      (array_agg(y.remaining_minor order by y.due_on)
        filter (where y.remaining_minor > 0))[1] as next_due_amount_minor,
      sum(y.remaining_minor) as statement_remaining_minor
    from app_finance.credit_card_statement_summaries y
    where y.account_id = a.id and y.remaining_minor > 0
  ) cycles on true
  left join lateral (
    select count(*) as active_plan_count
    from app_finance.installment_plans p
    where p.account_id = a.id and p.status = 'active'
  ) plans on true
  where app_finance.account_role(a.account_type) = 'liability';

-- ---------------------------------------------------------------------------
-- Facility RPCs: save (no opening debt), lifecycle, delete, charge, fees
-- ---------------------------------------------------------------------------

drop function if exists app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, bigint, smallint, smallint,
  text, smallint, text, uuid
);

-- New liability accounts always start with zero opening debt; editing never
-- touches opening_balance_minor, so legacy imported debt stays intact.
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
  p_min_payment_basis_points integer default null
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

  if p_account_id is null then
    insert into app_finance.accounts (
      user_id, name, account_type, currency_code, opening_balance_minor,
      is_default, allow_negative_balance, notes
    ) values (
      v_user_id, p_name, p_account_type, p_currency_code, 0,
      false, false, p_notes
    )
    returning id into v_account_id;
  else
    update app_finance.accounts
      set name = p_name,
        account_type = p_account_type,
        notes = p_notes
      where id = p_account_id and user_id = v_user_id and not is_archived
      returning id into v_account_id;
    if v_account_id is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
  end if;

  insert into app_finance.credit_facility_settings (
    account_id, user_id, credit_limit_minor, statement_day, default_due_day,
    last_four_digits, reminder_lead_days, facility_status,
    min_payment_method, min_payment_fixed_minor, min_payment_basis_points
  ) values (
    v_account_id, v_user_id, p_credit_limit_minor, p_statement_day,
    p_default_due_day, p_last_four_digits, coalesce(p_reminder_lead_days, 3),
    coalesce(p_facility_status, 'active'),
    coalesce(p_min_payment_method, 'full'),
    p_min_payment_fixed_minor, p_min_payment_basis_points
  )
  on conflict (account_id) do update set
    credit_limit_minor = excluded.credit_limit_minor,
    statement_day = excluded.statement_day,
    default_due_day = excluded.default_due_day,
    last_four_digits = excluded.last_four_digits,
    reminder_lead_days = excluded.reminder_lead_days,
    facility_status = excluded.facility_status,
    min_payment_method = excluded.min_payment_method,
    min_payment_fixed_minor = excluded.min_payment_fixed_minor,
    min_payment_basis_points = excluded.min_payment_basis_points;

  return v_account_id;
end;
$$;

-- Hard delete only for a pristine facility with no financial history at
-- all; anything else must archive so history stays intact.
create function app_finance.delete_credit_facility(p_account_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  select a.id, a.account_type into v_account
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id
    for update;
  if v_account is null
    or app_finance.account_role(v_account.account_type) <> 'liability' then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if exists (
    select 1 from app_finance.financial_transactions t
    where t.source_account_id = p_account_id
      or t.destination_account_id = p_account_id
  ) or exists (
    select 1 from app_finance.installment_plans p where p.account_id = p_account_id
  ) or exists (
    select 1 from app_finance.credit_card_statement_cycles c
    where c.account_id = p_account_id
  ) or exists (
    select 1 from app_finance.credit_card_fee_charges f
    join app_finance.credit_card_fee_rules r on r.id = f.rule_id
    where r.account_id = p_account_id
  ) then
    raise exception
      'facility_has_history: archive the card instead of deleting it';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  delete from app_finance.accounts
    where id = p_account_id and user_id = v_user_id;
  perform set_config('app_finance.facility_internal', '', true);
end;
$$;

create function app_finance.set_credit_facility_status(
  p_account_id uuid,
  p_status app_finance.facility_status
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_updated uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  update app_finance.credit_facility_settings
    set facility_status = p_status
    where account_id = p_account_id and user_id = v_user_id
    returning account_id into v_updated;
  if v_updated is null then
    raise exception 'not_found: credit facility';
  end if;
end;
$$;

-- One ordinary card purchase: a single expense from the card assigned to
-- its statement cycle. Never reduces cash and never books a second row
-- when the statement later closes or falls due.
create function app_finance.charge_credit_card(
  p_account_id uuid,
  p_title text,
  p_category_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_notes text default null,
  p_charge_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_card record;
  v_settings record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_cycle_id uuid;
  v_bounds record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
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

  select a.id, a.currency_code, a.account_type into v_card
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
    for update;
  if v_card is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if v_card.account_type <> 'credit_card' then
    raise exception
      'invalid_account: ordinary card charges require a credit card';
  end if;
  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before financing purchases';
  end if;
  if v_settings.facility_status <> 'active' then
    raise exception
      'facility_not_active: this card cannot fund new purchases';
  end if;
  if v_settings.statement_day is null then
    raise exception
      'card_not_configured: set a statement closing day first';
  end if;
  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + p_amount_minor > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  select * into v_bounds from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
  );

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    coalesce(p_charge_id, gen_random_uuid()), v_user_id, 'expense',
    p_occurred_on, p_amount_minor, v_card.currency_code, p_account_id,
    p_category_id, p_title, p_notes
  )
  returning id into v_tx_id;

  insert into app_finance.credit_card_statement_cycles (
    user_id, account_id, cycle_start, cycle_close, due_on
  ) values (
    v_user_id, p_account_id, v_bounds.cycle_start, v_bounds.cycle_close,
    v_bounds.due_on
  )
  on conflict (account_id, cycle_close) do nothing;

  select id into v_cycle_id
    from app_finance.credit_card_statement_cycles
    where account_id = p_account_id and cycle_close = v_bounds.cycle_close;

  insert into app_finance.credit_card_statement_items (
    user_id, cycle_id, transaction_id, amount_minor
  ) values (v_user_id, v_cycle_id, v_tx_id, p_amount_minor);

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

-- Generates due card fees (annual, insurance, ...) exactly once per rule
-- and charge date; safe to re-run from cron or the client.
create function app_finance.apply_credit_card_fees(
  p_through date default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_through date := coalesce(p_through, current_date);
  v_rule record;
  v_amount bigint;
  v_tx_id uuid;
  v_cycle_id uuid;
  v_bounds record;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  for v_rule in
    select r.*, a.currency_code, s.statement_day, s.default_due_day,
        s.facility_status, s.credit_limit_minor
    from app_finance.credit_card_fee_rules r
    join app_finance.accounts a on a.id = r.account_id
    join app_finance.credit_facility_settings s on s.account_id = r.account_id
    where r.user_id = v_user_id
      and r.is_active
      and not a.is_archived
      and s.facility_status = 'active'
      and coalesce(r.next_charge_on, r.starts_on) <= v_through
    order by r.created_at
  loop
    if v_rule.fixed_amount_minor is not null then
      v_amount := v_rule.fixed_amount_minor;
    else
      v_amount := case v_rule.percent_basis
        when 'credit_limit' then
          round(v_rule.credit_limit_minor::numeric
            * v_rule.percent_basis_points / 10000)::bigint
        when 'outstanding_balance' then
          round(app_finance.facility_outstanding_minor(
            v_rule.account_id
          )::numeric * v_rule.percent_basis_points / 10000)::bigint
        else
          round(coalesce((
            select y.remaining_minor
            from app_finance.credit_card_statement_summaries y
            where y.account_id = v_rule.account_id
            order by y.cycle_close desc limit 1
          ), 0)::numeric * v_rule.percent_basis_points / 10000)::bigint
      end;
    end if;
    if v_amount <= 0 then
      -- Nothing to charge on a zero basis; move the schedule forward.
      update app_finance.credit_card_fee_rules
        set next_charge_on = case frequency
            when 'once' then null
            when 'monthly' then
              (coalesce(next_charge_on, starts_on)
                + make_interval(months => 1))::date
            when 'quarterly' then
              (coalesce(next_charge_on, starts_on)
                + make_interval(months => 3))::date
            else (coalesce(next_charge_on, starts_on)
                + make_interval(years => 1))::date
          end,
          is_active = (frequency <> 'once')
        where id = v_rule.id;
      continue;
    end if;

    perform set_config('app_finance.facility_internal', 'on', true);
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    ) values (
      v_user_id, 'expense', coalesce(v_rule.next_charge_on, v_rule.starts_on),
      v_amount, v_rule.currency_code, v_rule.account_id, v_rule.category_id,
      v_rule.name
    )
    returning id into v_tx_id;

    begin
      insert into app_finance.credit_card_fee_charges (
        user_id, rule_id, transaction_id, charged_on, amount_minor
      ) values (
        v_user_id, v_rule.id, v_tx_id,
        coalesce(v_rule.next_charge_on, v_rule.starts_on), v_amount
      );
    exception when unique_violation then
      -- Another run already charged this date; drop the duplicate expense.
      delete from app_finance.financial_transactions where id = v_tx_id;
      perform set_config('app_finance.facility_internal', '', true);
      continue;
    end;

    if v_rule.statement_day is not null then
      select * into v_bounds from app_finance.statement_bounds_for(
        v_rule.statement_day, v_rule.default_due_day,
        coalesce(v_rule.next_charge_on, v_rule.starts_on)
      );
      insert into app_finance.credit_card_statement_cycles (
        user_id, account_id, cycle_start, cycle_close, due_on
      ) values (
        v_user_id, v_rule.account_id, v_bounds.cycle_start,
        v_bounds.cycle_close, v_bounds.due_on
      )
      on conflict (account_id, cycle_close) do nothing;
      select id into v_cycle_id
        from app_finance.credit_card_statement_cycles
        where account_id = v_rule.account_id
          and cycle_close = v_bounds.cycle_close;
      insert into app_finance.credit_card_statement_items (
        user_id, cycle_id, transaction_id, amount_minor
      ) values (v_user_id, v_cycle_id, v_tx_id, v_amount);
    end if;

    update app_finance.credit_card_fee_rules
      set next_charge_on = case frequency
          when 'once' then null
          when 'monthly' then
            (coalesce(next_charge_on, starts_on)
              + make_interval(months => 1))::date
          when 'quarterly' then
            (coalesce(next_charge_on, starts_on)
              + make_interval(months => 3))::date
          else (coalesce(next_charge_on, starts_on)
              + make_interval(years => 1))::date
        end,
        is_active = (frequency <> 'once')
      where id = v_rule.id;

    perform set_config('app_finance.facility_internal', '', true);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Installment pricing engine
-- ---------------------------------------------------------------------------

-- Resolves interest and total cost for one plan in integer minor units.
-- Reducing-balance uses the standard annuity payment; every rounding step
-- is deterministic half-up so previews and storage always agree.
create or replace function app_finance.resolve_plan_financing(
  p_pricing_method app_finance.plan_pricing_method,
  p_principal_minor bigint,
  p_count integer,
  p_manual_fees_minor bigint,
  p_total_payable_minor bigint,
  p_monthly_payment_minor bigint,
  p_rate_basis_points integer,
  p_rate_period app_finance.interest_rate_period,
  p_interest_method app_finance.interest_method,
  p_financed_fees_minor bigint
)
returns table (interest_minor bigint, fees_minor bigint, total_minor bigint)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_interest bigint := 0;
  v_rate numeric;
  v_pmt numeric;
begin
  if p_financed_fees_minor < 0 then
    raise exception 'invalid_amount: financing fees cannot be negative';
  end if;
  case p_pricing_method
    when 'manual_fees' then
      v_interest := 0;
      interest_minor := 0;
      fees_minor := coalesce(p_manual_fees_minor, 0) + p_financed_fees_minor;
      if fees_minor < 0 then
        raise exception 'invalid_amount: financing fees cannot be negative';
      end if;
      total_minor := p_principal_minor + fees_minor;
      if p_total_payable_minor is not null
        and p_total_payable_minor <> total_minor then
        raise exception 'invalid_financing: fees and total payable disagree';
      end if;
    when 'total_payable' then
      if p_total_payable_minor is null
        or p_total_payable_minor < p_principal_minor then
        raise exception
          'invalid_financing: total payable is below the financed principal';
      end if;
      total_minor := p_total_payable_minor;
      fees_minor := total_minor - p_principal_minor;
      interest_minor := fees_minor - p_financed_fees_minor;
      if interest_minor < 0 then
        raise exception 'invalid_financing: fees and total payable disagree';
      end if;
    when 'monthly_amount' then
      if p_monthly_payment_minor is null or p_monthly_payment_minor <= 0 then
        raise exception 'invalid_amount: must be positive';
      end if;
      if p_monthly_payment_minor * p_count < p_principal_minor then
        raise exception
          'invalid_financing: total payable is below the financed principal';
      end if;
      interest_minor := p_monthly_payment_minor * p_count
        - p_principal_minor;
      fees_minor := interest_minor + p_financed_fees_minor;
      total_minor := p_principal_minor + fees_minor;
    else -- interest_rate
      v_rate := p_rate_basis_points::numeric / 10000;
      if p_rate_period = 'annual' then
        v_rate := v_rate / 12;
      end if;
      if v_rate <= 0 then
        v_interest := 0;
      elsif p_interest_method = 'flat' then
        v_interest := round(p_principal_minor * v_rate * p_count)::bigint;
      else
        v_pmt := p_principal_minor * v_rate
          / (1 - power(1 + v_rate, -p_count));
        v_interest := round(v_pmt * p_count - p_principal_minor)::bigint;
      end if;
      interest_minor := greatest(v_interest, 0);
      fees_minor := interest_minor + p_financed_fees_minor;
      total_minor := p_principal_minor + fees_minor;
  end case;
  return next;
end;
$$;

drop function if exists app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid
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
  p_paid_installments integer default 0
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
  v_financing record;
  v_outstanding bigint;
  v_plan_id uuid;
  v_purchase_tx_id uuid;
  v_down_tx_id uuid;
  v_base bigint;
  v_remainder bigint;
  v_seq integer;
  v_due_amount bigint;
  v_presettled bigint := 0;
  v_charge bigint;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_plan_id is not null then
    select id into v_plan_id from app_finance.installment_plans
      where id = p_plan_id and user_id = v_user_id;
    if v_plan_id is not null then
      return v_plan_id;
    end if;
  end if;
  if p_purchase_price_minor is null or p_purchase_price_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if coalesce(p_down_payment_minor, 0) < 0
    or coalesce(p_upfront_fees_minor, 0) < 0 then
    raise exception 'invalid_amount: must be positive';
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
  if p_paid_installments < 0
    or p_paid_installments >= p_installment_count then
    raise exception
      'invalid_paid_installments: already-paid count must stay below the total';
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
      'invalid_account: installment purchases require a credit card or BNPL account';
  end if;
  select * into v_settings from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before financing purchases';
  end if;
  if v_settings.facility_status <> 'active' then
    raise exception
      'facility_not_active: this card cannot fund new purchases';
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
    raise exception 'invalid_amount: the financed principal must stay positive';
  end if;

  select * into v_financing from app_finance.resolve_plan_financing(
    p_pricing_method, v_financed, p_installment_count,
    p_financing_fees_minor, p_total_payable_minor, p_monthly_payment_minor,
    coalesce(p_interest_rate_basis_points, 0), p_interest_rate_period,
    p_interest_method, coalesce(p_financed_fees_minor, 0)
  );

  if coalesce(p_down_payment_minor, 0) > 0
    or coalesce(p_upfront_fees_minor, 0) > 0 then
    if p_down_payment_account_id is null then
      raise exception 'invalid_account: a down payment needs a funding account';
    end if;
    select a.id, a.currency_code, a.account_type into v_down_account
      from app_finance.accounts a
      where a.id = p_down_payment_account_id and a.user_id = v_user_id
        and not a.is_archived;
    if v_down_account is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
    if app_finance.account_role(v_down_account.account_type) <> 'asset' then
      raise exception 'invalid_account: down payments come from an asset account';
    end if;
    if v_down_account.currency_code <> v_facility.currency_code then
      raise exception
        'currency_mismatch: down payment account must match the facility';
    end if;
  end if;

  -- Deterministic split first, so the imported (presettled) portion and the
  -- booked charge are exact.
  v_base := v_financing.total_minor / p_installment_count;
  v_remainder := v_financing.total_minor % p_installment_count;
  for v_seq in 1..p_paid_installments loop
    v_presettled := v_presettled + v_base
      + case when v_seq <= v_remainder then 1 else 0 end;
  end loop;
  v_charge := v_financing.total_minor - v_presettled;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + v_charge > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  -- The recognized expense is the amount still owed through the facility.
  -- For an imported running plan the pre-tracking installments are history:
  -- they never become current-period expenses or transfers.
  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    v_user_id, 'expense', p_purchased_on, v_charge,
    v_facility.currency_code, p_account_id, p_category_id, p_title, p_notes
  )
  returning id into v_purchase_tx_id;

  if coalesce(p_down_payment_minor, 0) > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', coalesce(p_down_paid_on, p_purchased_on),
      p_down_payment_minor, v_facility.currency_code,
      p_down_payment_account_id, p_category_id, p_title, p_notes
    )
    returning id into v_down_tx_id;
  end if;

  if coalesce(p_upfront_fees_minor, 0) > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', p_purchased_on, p_upfront_fees_minor,
      v_facility.currency_code, p_down_payment_account_id, p_category_id,
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
    interest_method, origin
  ) values (
    coalesce(p_plan_id, gen_random_uuid()), v_user_id, p_account_id,
    v_purchase_tx_id, v_down_tx_id, p_title, p_category_id, p_purchased_on,
    p_first_due_on, p_installment_count, p_purchase_price_minor,
    coalesce(p_down_payment_minor, 0), v_financed, v_financing.fees_minor,
    v_financing.interest_minor, v_financing.total_minor,
    v_facility.currency_code, p_notes,
    p_pricing_method, coalesce(p_interest_rate_basis_points, 0),
    p_interest_rate_period, p_interest_method,
    case when p_paid_installments > 0
      then 'historical_import'::app_finance.plan_origin
      else 'app'::app_finance.plan_origin end
  )
  returning id into v_plan_id;

  for v_seq in 1..p_installment_count loop
    v_due_amount := v_base
      + case when v_seq <= v_remainder then 1 else 0 end;
    insert into app_finance.installment_dues (
      user_id, plan_id, sequence_number, due_on, amount_minor, is_presettled
    ) values (
      v_user_id, v_plan_id, v_seq,
      (p_first_due_on + make_interval(months => v_seq - 1))::date,
      v_due_amount, v_seq <= p_paid_installments
    );
  end loop;

  perform set_config('app_finance.facility_internal', '', true);
  return v_plan_id;
end;
$$;

-- Full atomic edit while no payment exists: rebuilds the booked expense,
-- the optional down payment, and the entire schedule.
create function app_finance.update_installment_plan(
  p_plan_id uuid,
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
  p_pricing_method app_finance.plan_pricing_method default 'manual_fees',
  p_monthly_payment_minor bigint default null,
  p_interest_rate_basis_points integer default 0,
  p_interest_rate_period app_finance.interest_rate_period default 'monthly',
  p_interest_method app_finance.interest_method default 'flat',
  p_financed_fees_minor bigint default 0,
  p_down_paid_on date default null,
  p_paid_installments integer default 0
)
returns uuid
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
  select p.* into v_plan from app_finance.installment_plans p
    where p.id = p_plan_id and p.user_id = v_user_id
    for update;
  if v_plan is null then
    raise exception 'not_found: installment plan';
  end if;
  if v_plan.status <> 'active' then
    raise exception 'plan_locked: only active plans can be edited';
  end if;
  if exists (
    select 1 from app_finance.installment_payment_allocations pa
    join app_finance.installment_dues d on d.id = pa.due_id
    where d.plan_id = p_plan_id
  ) then
    raise exception
      'plan_has_payments: restructure the remaining installments instead';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);
  update app_finance.installment_plans
    set status = 'cancelled'
    where id = p_plan_id and user_id = v_user_id;
  delete from app_finance.financial_transactions
    where user_id = v_user_id
      and id in (
        v_plan.purchase_transaction_id, v_plan.down_payment_transaction_id
      );
  delete from app_finance.installment_dues
    where plan_id = p_plan_id and user_id = v_user_id;
  delete from app_finance.installment_plans
    where id = p_plan_id and user_id = v_user_id;
  perform set_config('app_finance.facility_internal', '', true);

  -- Recreate under the same id so links and the client stay stable.
  return app_finance.create_installment_plan(
    v_plan.account_id, p_title, p_category_id, p_purchased_on,
    p_purchase_price_minor, p_installment_count, p_first_due_on,
    p_down_payment_minor, p_down_payment_account_id,
    p_financing_fees_minor, p_total_payable_minor, p_notes, p_plan_id,
    p_pricing_method, p_monthly_payment_minor,
    p_interest_rate_basis_points, p_interest_rate_period, p_interest_method,
    p_financed_fees_minor, 0, p_down_paid_on, p_paid_installments
  );
end;
$$;

-- Restructure the unpaid remainder of a partially paid plan. Paid and
-- imported-paid dues stay immutable; extra recognized cost books an
-- explicit adjustment expense on the adjustment date.
create function app_finance.restructure_installment_plan(
  p_plan_id uuid,
  p_remaining_total_minor bigint,
  p_remaining_count integer,
  p_next_due_on date,
  p_change_note text default null,
  p_adjusted_on date default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_plan record;
  v_paid bigint;
  v_new_total bigint;
  v_delta bigint;
  v_base bigint;
  v_remainder bigint;
  v_seq integer;
  v_start_seq integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_remaining_total_minor is null or p_remaining_total_minor <= 0
    or p_remaining_count is null or p_remaining_count < 1
    or p_remaining_count > 120 then
    raise exception
      'invalid_installments: choose between 1 and 120 installments';
  end if;
  select p.* into v_plan from app_finance.installment_plans p
    where p.id = p_plan_id and p.user_id = v_user_id
    for update;
  if v_plan is null then
    raise exception 'not_found: installment plan';
  end if;
  if v_plan.status <> 'active' then
    raise exception 'plan_locked: only active plans can be edited';
  end if;
  if exists (
    select 1 from app_finance.installment_due_statuses s
    where s.plan_id = p_plan_id and s.paid_minor > 0 and s.remaining_minor > 0
  ) then
    raise exception
      'plan_partially_paid_due: settle the partially paid installment first';
  end if;

  select coalesce(sum(s.paid_minor), 0) into v_paid
    from app_finance.installment_due_statuses s
    where s.plan_id = p_plan_id;
  v_new_total := v_paid + p_remaining_total_minor;
  v_delta := v_new_total - v_plan.total_payable_minor;
  if v_delta < 0 then
    raise exception
      'invalid_financing: the restructured total cannot fall below the recognized cost';
  end if;

  select coalesce(max(s.sequence_number), 0) into v_start_seq
    from app_finance.installment_due_statuses s
    where s.plan_id = p_plan_id and s.remaining_minor = 0;

  perform set_config('app_finance.facility_internal', 'on', true);

  delete from app_finance.installment_dues d
    where d.plan_id = p_plan_id and d.user_id = v_user_id
      and not d.is_presettled
      and not exists (
        select 1 from app_finance.installment_payment_allocations pa
        where pa.due_id = d.id
      );

  v_base := p_remaining_total_minor / p_remaining_count;
  v_remainder := p_remaining_total_minor % p_remaining_count;
  for v_seq in 1..p_remaining_count loop
    insert into app_finance.installment_dues (
      user_id, plan_id, sequence_number, due_on, amount_minor
    ) values (
      v_user_id, p_plan_id, v_start_seq + v_seq,
      (p_next_due_on + make_interval(months => v_seq - 1))::date,
      v_base + case when v_seq <= v_remainder then 1 else 0 end
    );
  end loop;

  if v_delta > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (
      v_user_id, 'expense', coalesce(p_adjusted_on, current_date), v_delta,
      v_plan.currency_code, v_plan.account_id, v_plan.category_id,
      v_plan.title, p_change_note
    );
  end if;

  update app_finance.installment_plans
    set total_payable_minor = v_new_total,
      financing_fees_minor = v_new_total - financed_principal_minor,
      installment_count = v_start_seq + p_remaining_count,
      revision = revision + 1
    where id = p_plan_id and user_id = v_user_id;

  insert into app_finance.installment_plan_revisions (
    user_id, plan_id, revision, change_summary,
    previous_total_payable_minor, new_total_payable_minor
  ) values (
    v_user_id, p_plan_id, v_plan.revision + 1,
    coalesce(p_change_note, 'restructured remaining installments'),
    v_plan.total_payable_minor, v_new_total
  );

  perform set_config('app_finance.facility_internal', '', true);
  return p_plan_id;
end;
$$;

-- Payments now settle statement dues and installment dues together:
-- everything overdue first, then by due date, statements before
-- installments on the same day.
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
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_payment_id is not null then
    select id into v_tx_id from app_finance.financial_transactions
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
    where a.id = p_account_id and a.user_id = v_user_id
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
    raise exception 'overpayment_rejected: payment exceeds the amount owed';
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
    for v_obligation in
      select 'statement' as kind, y.id, y.remaining_minor, y.due_on
      from app_finance.credit_card_statement_summaries y
      where y.user_id = v_user_id and y.account_id = p_account_id
        and y.remaining_minor > 0 and y.cycle_close < current_date
      union all
      select 'installment' as kind, s.id, s.remaining_minor, s.due_on
      from app_finance.installment_due_statuses s
      where s.user_id = v_user_id and s.account_id = p_account_id
        and s.plan_status = 'active' and s.remaining_minor > 0
      order by due_on, kind desc, id
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

  update app_finance.installment_plans p
    set status = 'completed'
    where p.user_id = v_user_id
      and p.account_id = p_account_id
      and p.status = 'active'
      and not exists (
        select 1 from app_finance.installment_due_statuses s
        where s.plan_id = p.id and s.remaining_minor > 0
      );

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

-- Reversals also release statement allocations.
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
-- Account deletion cascade learns the statement, fee, revision, and
-- notification tables
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

  delete from app_core.notification_outbox where user_id = p_user_id;
  delete from app_core.push_devices where user_id = p_user_id;
  delete from app_core.notification_preferences where user_id = p_user_id;

  delete from app_finance.installment_payment_allocations
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

revoke execute on function app_finance.clamp_day_of_month(
  integer, integer, integer
) from public, anon;
grant execute on function app_finance.clamp_day_of_month(
  integer, integer, integer
) to authenticated, service_role;

revoke execute on function app_finance.statement_bounds_for(
  integer, integer, date
) from public, anon;
grant execute on function app_finance.statement_bounds_for(
  integer, integer, date
) to authenticated, service_role;

revoke execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer
) from public, anon;
grant execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer
) to authenticated, service_role;

revoke execute on function app_finance.delete_credit_facility(uuid)
from public, anon;
grant execute on function app_finance.delete_credit_facility(uuid)
to authenticated, service_role;

revoke execute on function app_finance.set_credit_facility_status(
  uuid, app_finance.facility_status
) from public, anon;
grant execute on function app_finance.set_credit_facility_status(
  uuid, app_finance.facility_status
) to authenticated, service_role;

revoke execute on function app_finance.charge_credit_card(
  uuid, text, uuid, date, bigint, text, uuid
) from public, anon;
grant execute on function app_finance.charge_credit_card(
  uuid, text, uuid, date, bigint, text, uuid
) to authenticated, service_role;

revoke execute on function app_finance.apply_credit_card_fees(date)
from public, anon;
grant execute on function app_finance.apply_credit_card_fees(date)
to authenticated, service_role;

revoke execute on function app_finance.resolve_plan_financing(
  app_finance.plan_pricing_method, bigint, integer, bigint, bigint, bigint,
  integer, app_finance.interest_rate_period, app_finance.interest_method,
  bigint
) from public, anon;
grant execute on function app_finance.resolve_plan_financing(
  app_finance.plan_pricing_method, bigint, integer, bigint, bigint, bigint,
  integer, app_finance.interest_rate_period, app_finance.interest_method,
  bigint
) to authenticated, service_role;

revoke execute on function app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  bigint, date, integer
) from public, anon;
grant execute on function app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  bigint, date, integer
) to authenticated, service_role;

revoke execute on function app_finance.update_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  date, integer
) from public, anon;
grant execute on function app_finance.update_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  date, integer
) to authenticated, service_role;

revoke execute on function app_finance.restructure_installment_plan(
  uuid, bigint, integer, date, text, date
) from public, anon;
grant execute on function app_finance.restructure_installment_plan(
  uuid, bigint, integer, date, text, date
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

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'installment_plan_revisions',
    'credit_card_statement_cycles',
    'credit_card_statement_items',
    'credit_card_statement_allocations',
    'credit_card_fee_rules',
    'credit_card_fee_charges'
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
