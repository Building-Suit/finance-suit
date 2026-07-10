-- Work Tracker initial schema.
-- Money: bigint minor units (piastres). Durations: integer minutes.
-- Multipliers: integer percent (150 = 1.5x). Day units: integer hundredths
-- (100 = full day, 50 = half day). Business dates: date. Audit: timestamptz.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.work_entry_type as enum (
  'regular', 'overtime', 'extra_day', 'holiday_worked'
);

create type public.rate_mode as enum ('derived', 'manual');

create type public.holiday_multiplier_semantics as enum (
  'additional_pay', 'total_including_base'
);

create type public.rounding_mode as enum ('half_up', 'half_even');

create type public.salary_period_status as enum ('open', 'finalized', 'paid');

create type public.adjustment_type as enum ('bonus', 'deduction');

create type public.account_type as enum (
  'current', 'savings', 'cash', 'bank', 'wallet',
  'emergency', 'vacation', 'custom'
);

create type public.category_kind as enum ('expense', 'allowance', 'income');

create type public.transaction_kind as enum (
  'expense', 'allowance_given', 'custom_income',
  'freelance_income', 'salary_income', 'transfer'
);

-- ---------------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create profile row when a user registers.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- user_preferences
-- ---------------------------------------------------------------------------
create table public.user_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  currency_code text not null default 'EGP' check (currency_code ~ '^[A-Z]{3}$'),
  timezone text not null default 'Africa/Cairo',
  locale text not null default 'en' check (locale in ('en', 'ar')),
  week_starts_on smallint not null default 6
    check (week_starts_on between 1 and 7),        -- ISO: 1=Mon .. 7=Sun
  weekend_days smallint[] not null default '{5,6}' -- Fri, Sat
    check (array_length(weekend_days, 1) between 1 and 3),
  default_history_days integer not null default 30
    check (default_history_days between 1 and 365),
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_user_preferences_updated_at
  before update on public.user_preferences
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- salary_settings (one active record per user)
-- ---------------------------------------------------------------------------
create table public.salary_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  base_salary_minor bigint not null check (base_salary_minor >= 0),
  currency_code text not null default 'EGP' check (currency_code ~ '^[A-Z]{3}$'),
  salary_period_start_day smallint not null default 1
    check (salary_period_start_day between 1 and 28),
  payment_day smallint not null default 1
    check (payment_day between 1 and 28),
  payment_month_offset smallint not null default 1
    check (payment_month_offset between 0 and 2),
  standard_paid_days_per_period smallint not null default 22
    check (standard_paid_days_per_period between 1 and 31),
  standard_minutes_per_day integer not null default 480
    check (standard_minutes_per_day between 60 and 1440),
  day_rate_mode public.rate_mode not null default 'derived',
  manual_day_rate_minor bigint check (manual_day_rate_minor >= 0),
  hour_rate_mode public.rate_mode not null default 'derived',
  manual_hour_rate_minor bigint check (manual_hour_rate_minor >= 0),
  extra_day_multiplier_pct integer not null default 100
    check (extra_day_multiplier_pct between 0 and 1000),
  official_holiday_multiplier_pct integer not null default 200
    check (official_holiday_multiplier_pct between 0 and 1000),
  overtime_multiplier_pct integer not null default 150
    check (overtime_multiplier_pct between 0 and 1000),
  official_holiday_multiplier_semantics public.holiday_multiplier_semantics
    not null default 'additional_pay',
  rounding_mode public.rounding_mode not null default 'half_up',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint manual_day_rate_required
    check (day_rate_mode <> 'manual' or manual_day_rate_minor is not null),
  constraint manual_hour_rate_required
    check (hour_rate_mode <> 'manual' or manual_hour_rate_minor is not null)
);

create trigger trg_salary_settings_updated_at
  before update on public.salary_settings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- salary_adjustments
-- ---------------------------------------------------------------------------
create table public.salary_adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  effective_date date not null,
  adjustment_type public.adjustment_type not null,
  amount_minor bigint not null check (amount_minor > 0),
  title text check (char_length(title) <= 120),
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_salary_adjustments_updated_at
  before update on public.salary_adjustments
  for each row execute function public.set_updated_at();

create index idx_salary_adjustments_user_date
  on public.salary_adjustments (user_id, effective_date desc, id desc);

-- ---------------------------------------------------------------------------
-- official_holidays
-- ---------------------------------------------------------------------------
create table public.official_holidays (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  holiday_date date not null,
  name text not null check (char_length(name) between 1 and 120),
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint official_holidays_owner_unique unique (id, user_id)
);

create trigger trg_official_holidays_updated_at
  before update on public.official_holidays
  for each row execute function public.set_updated_at();

create index idx_official_holidays_user_date
  on public.official_holidays (user_id, holiday_date desc);

-- ---------------------------------------------------------------------------
-- work_entries
-- ---------------------------------------------------------------------------
create table public.work_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  work_date date not null,
  entry_type public.work_entry_type not null,
  start_time time,
  end_time time,
  break_minutes integer not null default 0
    check (break_minutes >= 0 and break_minutes <= 1440),
  duration_minutes integer
    check (duration_minutes > 0 and duration_minutes <= 2880),
  day_units_hundredths integer
    check (day_units_hundredths > 0 and day_units_hundredths <= 200),
  multiplier_pct integer
    check (multiplier_pct between 0 and 1000),
  custom_rate_minor bigint check (custom_rate_minor >= 0),
  computed_amount_minor bigint check (computed_amount_minor >= 0),
  calc_snapshot jsonb,
  holiday_id uuid,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Ownership-aware FK: a work entry may only reference the same user's holiday.
  constraint work_entries_holiday_owner_fk
    foreign key (holiday_id, user_id)
    references public.official_holidays (id, user_id) on delete set null (holiday_id),
  -- Regular sessions and overtime need a duration; day-based types need units.
  constraint duration_required check (
    entry_type not in ('regular', 'overtime') or duration_minutes is not null
  ),
  constraint day_units_required check (
    entry_type not in ('extra_day') or day_units_hundredths is not null
  ),
  constraint holiday_needs_units_or_duration check (
    entry_type <> 'holiday_worked'
    or day_units_hundredths is not null
    or duration_minutes is not null
  )
);

create trigger trg_work_entries_updated_at
  before update on public.work_entries
  for each row execute function public.set_updated_at();

create index idx_work_entries_user_date
  on public.work_entries (user_id, work_date desc, id desc);
create index idx_work_entries_user_type_date
  on public.work_entries (user_id, entry_type, work_date desc);

-- ---------------------------------------------------------------------------
-- accounts
-- ---------------------------------------------------------------------------
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  account_type public.account_type not null default 'current',
  currency_code text not null default 'EGP' check (currency_code ~ '^[A-Z]{3}$'),
  opening_balance_minor bigint not null default 0,
  is_default boolean not null default false,
  allow_negative_balance boolean not null default false,
  is_archived boolean not null default false,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_owner_unique unique (id, user_id)
);

create trigger trg_accounts_updated_at
  before update on public.accounts
  for each row execute function public.set_updated_at();

-- Exactly one default among active accounts per user.
create unique index idx_accounts_one_default_per_user
  on public.accounts (user_id)
  where is_default and not is_archived;

-- Active account names unique per user.
create unique index idx_accounts_active_name_per_user
  on public.accounts (user_id, lower(name))
  where not is_archived;

create index idx_accounts_user
  on public.accounts (user_id, is_archived, created_at);

-- ---------------------------------------------------------------------------
-- transaction_categories
-- ---------------------------------------------------------------------------
create table public.transaction_categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  category_kind public.category_kind not null,
  icon text not null default 'category' check (char_length(icon) <= 60),
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transaction_categories_owner_unique unique (id, user_id)
);

create trigger trg_transaction_categories_updated_at
  before update on public.transaction_categories
  for each row execute function public.set_updated_at();

create unique index idx_categories_active_name_per_user_kind
  on public.transaction_categories (user_id, category_kind, lower(name))
  where not is_archived;

create index idx_categories_user_kind
  on public.transaction_categories (user_id, category_kind, is_archived);

-- ---------------------------------------------------------------------------
-- salary_periods
-- ---------------------------------------------------------------------------
create table public.salary_periods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  period_start date not null,
  period_end date not null,
  expected_payment_date date not null,
  status public.salary_period_status not null default 'open',
  snapshot jsonb,
  finalized_at timestamptz,
  actual_amount_minor bigint check (actual_amount_minor >= 0),
  received_date date,
  destination_account_id uuid,
  paid_transaction_id uuid,
  notes text check (char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint salary_periods_owner_unique unique (id, user_id),
  constraint salary_periods_unique_start unique (user_id, period_start),
  constraint salary_periods_valid_range check (period_end >= period_start),
  constraint salary_periods_destination_owner_fk
    foreign key (destination_account_id, user_id)
    references public.accounts (id, user_id),
  constraint finalized_has_snapshot check (
    status = 'open' or snapshot is not null
  ),
  constraint paid_has_payment_fields check (
    status <> 'paid'
    or (actual_amount_minor is not null
        and received_date is not null
        and destination_account_id is not null
        and paid_transaction_id is not null)
  )
);

create trigger trg_salary_periods_updated_at
  before update on public.salary_periods
  for each row execute function public.set_updated_at();

create index idx_salary_periods_user_start
  on public.salary_periods (user_id, period_start desc);

-- ---------------------------------------------------------------------------
-- financial_transactions
-- ---------------------------------------------------------------------------
create table public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  transaction_kind public.transaction_kind not null,
  occurred_on date not null,
  amount_minor bigint not null check (amount_minor > 0),
  currency_code text not null default 'EGP' check (currency_code ~ '^[A-Z]{3}$'),
  source_account_id uuid,
  destination_account_id uuid,
  category_id uuid,
  counterparty text check (char_length(counterparty) <= 120),
  title text check (char_length(title) <= 120),
  notes text check (char_length(notes) <= 1000),
  salary_period_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Ownership-aware references: no cross-user account/category linkage.
  constraint tx_source_owner_fk
    foreign key (source_account_id, user_id)
    references public.accounts (id, user_id),
  constraint tx_destination_owner_fk
    foreign key (destination_account_id, user_id)
    references public.accounts (id, user_id),
  constraint tx_category_owner_fk
    foreign key (category_id, user_id)
    references public.transaction_categories (id, user_id),
  constraint tx_salary_period_owner_fk
    foreign key (salary_period_id, user_id)
    references public.salary_periods (id, user_id),
  -- Direction rules per kind.
  constraint tx_direction_by_kind check (
    (transaction_kind in ('expense', 'allowance_given')
      and source_account_id is not null
      and destination_account_id is null)
    or
    (transaction_kind in ('custom_income', 'freelance_income', 'salary_income')
      and destination_account_id is not null
      and source_account_id is null)
    or
    (transaction_kind = 'transfer'
      and source_account_id is not null
      and destination_account_id is not null
      and source_account_id <> destination_account_id)
  ),
  constraint tx_salary_link_only_for_salary check (
    salary_period_id is null or transaction_kind = 'salary_income'
  )
);

create trigger trg_financial_transactions_updated_at
  before update on public.financial_transactions
  for each row execute function public.set_updated_at();

-- One salary transaction per salary period (idempotent payment).
create unique index idx_tx_one_salary_payment_per_period
  on public.financial_transactions (salary_period_id)
  where salary_period_id is not null;

create index idx_tx_user_date
  on public.financial_transactions (user_id, occurred_on desc, id desc);
create index idx_tx_user_kind_date
  on public.financial_transactions (user_id, transaction_kind, occurred_on desc);
create index idx_tx_user_source_date
  on public.financial_transactions (user_id, source_account_id, occurred_on desc)
  where source_account_id is not null;
create index idx_tx_user_destination_date
  on public.financial_transactions (user_id, destination_account_id, occurred_on desc)
  where destination_account_id is not null;
create index idx_tx_user_category_date
  on public.financial_transactions (user_id, category_id, occurred_on desc)
  where category_id is not null;

-- Salary periods reference their payment transaction.
alter table public.salary_periods
  add constraint salary_periods_paid_tx_fk
  foreign key (paid_transaction_id) references public.financial_transactions (id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;
alter table public.salary_settings enable row level security;
alter table public.salary_adjustments enable row level security;
alter table public.official_holidays enable row level security;
alter table public.work_entries enable row level security;
alter table public.accounts enable row level security;
alter table public.transaction_categories enable row level security;
alter table public.salary_periods enable row level security;
alter table public.financial_transactions enable row level security;

-- profiles: id is the owner key.
create policy profiles_select on public.profiles
  for select using ((select auth.uid()) = id);
create policy profiles_insert on public.profiles
  for insert with check ((select auth.uid()) = id);
create policy profiles_update on public.profiles
  for update using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
create policy profiles_delete on public.profiles
  for delete using ((select auth.uid()) = id);

-- user_preferences
create policy user_preferences_select on public.user_preferences
  for select using ((select auth.uid()) = user_id);
create policy user_preferences_insert on public.user_preferences
  for insert with check ((select auth.uid()) = user_id);
create policy user_preferences_update on public.user_preferences
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy user_preferences_delete on public.user_preferences
  for delete using ((select auth.uid()) = user_id);

-- salary_settings
create policy salary_settings_select on public.salary_settings
  for select using ((select auth.uid()) = user_id);
create policy salary_settings_insert on public.salary_settings
  for insert with check ((select auth.uid()) = user_id);
create policy salary_settings_update on public.salary_settings
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy salary_settings_delete on public.salary_settings
  for delete using ((select auth.uid()) = user_id);

-- salary_adjustments
create policy salary_adjustments_select on public.salary_adjustments
  for select using ((select auth.uid()) = user_id);
create policy salary_adjustments_insert on public.salary_adjustments
  for insert with check ((select auth.uid()) = user_id);
create policy salary_adjustments_update on public.salary_adjustments
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy salary_adjustments_delete on public.salary_adjustments
  for delete using ((select auth.uid()) = user_id);

-- official_holidays
create policy official_holidays_select on public.official_holidays
  for select using ((select auth.uid()) = user_id);
create policy official_holidays_insert on public.official_holidays
  for insert with check ((select auth.uid()) = user_id);
create policy official_holidays_update on public.official_holidays
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy official_holidays_delete on public.official_holidays
  for delete using ((select auth.uid()) = user_id);

-- work_entries
create policy work_entries_select on public.work_entries
  for select using ((select auth.uid()) = user_id);
create policy work_entries_insert on public.work_entries
  for insert with check ((select auth.uid()) = user_id);
create policy work_entries_update on public.work_entries
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy work_entries_delete on public.work_entries
  for delete using ((select auth.uid()) = user_id);

-- accounts
create policy accounts_select on public.accounts
  for select using ((select auth.uid()) = user_id);
create policy accounts_insert on public.accounts
  for insert with check ((select auth.uid()) = user_id);
create policy accounts_update on public.accounts
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy accounts_delete on public.accounts
  for delete using ((select auth.uid()) = user_id);

-- transaction_categories
create policy transaction_categories_select on public.transaction_categories
  for select using ((select auth.uid()) = user_id);
create policy transaction_categories_insert on public.transaction_categories
  for insert with check ((select auth.uid()) = user_id);
create policy transaction_categories_update on public.transaction_categories
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy transaction_categories_delete on public.transaction_categories
  for delete using ((select auth.uid()) = user_id);

-- salary_periods
create policy salary_periods_select on public.salary_periods
  for select using ((select auth.uid()) = user_id);
create policy salary_periods_insert on public.salary_periods
  for insert with check ((select auth.uid()) = user_id);
create policy salary_periods_update on public.salary_periods
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy salary_periods_delete on public.salary_periods
  for delete using ((select auth.uid()) = user_id);

-- financial_transactions
create policy financial_transactions_select on public.financial_transactions
  for select using ((select auth.uid()) = user_id);
create policy financial_transactions_insert on public.financial_transactions
  for insert with check ((select auth.uid()) = user_id);
create policy financial_transactions_update on public.financial_transactions
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy financial_transactions_delete on public.financial_transactions
  for delete using ((select auth.uid()) = user_id);
