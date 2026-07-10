-- Views, functions, and triggers built on the initial schema.
-- All views use security_invoker so RLS on base tables applies.
-- Functions derive identity from auth.uid(); none trust a caller-supplied user id.

-- ---------------------------------------------------------------------------
-- Signed per-account transaction flows (internal building block)
-- ---------------------------------------------------------------------------
create or replace view public.account_flows
with (security_invoker = on) as
  select
    t.user_id,
    t.source_account_id as account_id,
    t.id as transaction_id,
    t.transaction_kind,
    t.occurred_on,
    -t.amount_minor as signed_amount_minor
  from public.financial_transactions t
  where t.source_account_id is not null
  union all
  select
    t.user_id,
    t.destination_account_id,
    t.id,
    t.transaction_kind,
    t.occurred_on,
    t.amount_minor
  from public.financial_transactions t
  where t.destination_account_id is not null;

-- ---------------------------------------------------------------------------
-- Account balances
-- ---------------------------------------------------------------------------
create or replace view public.account_balances
with (security_invoker = on) as
  select
    a.id as account_id,
    a.user_id,
    a.name,
    a.account_type,
    a.currency_code,
    a.is_default,
    a.is_archived,
    a.allow_negative_balance,
    a.opening_balance_minor,
    (a.opening_balance_minor + coalesce(f.net, 0))::bigint as balance_minor,
    coalesce(f.total_in, 0)::bigint as total_incoming_minor,
    coalesce(f.total_out, 0)::bigint as total_outgoing_minor
  from public.accounts a
  left join (
    select
      account_id,
      sum(signed_amount_minor) as net,
      sum(signed_amount_minor) filter (where signed_amount_minor > 0) as total_in,
      -sum(signed_amount_minor) filter (where signed_amount_minor < 0) as total_out
    from public.account_flows
    group by account_id
  ) f on f.account_id = a.id;

-- ---------------------------------------------------------------------------
-- Negative balance enforcement
-- ---------------------------------------------------------------------------
create or replace function public.enforce_account_balance()
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
  select allow_negative_balance, is_archived, name
    into v_account
    from public.accounts
    where id = new.source_account_id;
  if v_account.is_archived then
    raise exception 'account_archived: cannot write to an archived account';
  end if;
  if v_account.allow_negative_balance then
    return new;
  end if;
  select balance_minor into v_balance
    from public.account_balances
    where account_id = new.source_account_id;
  if v_balance < 0 then
    raise exception 'insufficient_funds: % does not allow negative balance',
      v_account.name;
  end if;
  return new;
end;
$$;

create constraint trigger trg_enforce_account_balance
  after insert or update on public.financial_transactions
  deferrable initially immediate
  for each row execute function public.enforce_account_balance();

-- ---------------------------------------------------------------------------
-- Cash-flow summary for a date range
-- ---------------------------------------------------------------------------
create or replace function public.cash_flow_summary(p_start date, p_end date)
returns table (
  income_minor bigint,
  expenses_minor bigint,
  allowances_minor bigint,
  net_minor bigint
)
language sql
stable
set search_path = ''
as $$
  select
    coalesce(sum(amount_minor) filter (where transaction_kind in
      ('custom_income', 'freelance_income', 'salary_income')), 0),
    coalesce(sum(amount_minor) filter (where transaction_kind = 'expense'), 0),
    coalesce(sum(amount_minor) filter (where transaction_kind = 'allowance_given'), 0),
    coalesce(sum(amount_minor) filter (where transaction_kind in
      ('custom_income', 'freelance_income', 'salary_income')), 0)
    - coalesce(sum(amount_minor) filter (where transaction_kind = 'expense'), 0)
    - coalesce(sum(amount_minor) filter (where transaction_kind = 'allowance_given'), 0)
  from public.financial_transactions
  where user_id = (select auth.uid())
    and occurred_on between p_start and p_end
    and transaction_kind <> 'transfer';
$$;

-- ---------------------------------------------------------------------------
-- Finance time series (income/expense/allowance per bucket)
-- ---------------------------------------------------------------------------
create or replace function public.finance_series(
  p_start date,
  p_end date,
  p_bucket text default 'day'
)
returns table (
  bucket_start date,
  income_minor bigint,
  expenses_minor bigint,
  allowances_minor bigint,
  net_minor bigint
)
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_bucket not in ('day', 'week', 'month') then
    raise exception 'invalid_bucket: %', p_bucket;
  end if;
  return query
  select
    date_trunc(p_bucket, t.occurred_on)::date,
    coalesce(sum(t.amount_minor) filter (where t.transaction_kind in
      ('custom_income', 'freelance_income', 'salary_income')), 0)::bigint,
    coalesce(sum(t.amount_minor) filter (where t.transaction_kind = 'expense'), 0)::bigint,
    coalesce(sum(t.amount_minor) filter (where t.transaction_kind = 'allowance_given'), 0)::bigint,
    (coalesce(sum(t.amount_minor) filter (where t.transaction_kind in
      ('custom_income', 'freelance_income', 'salary_income')), 0)
    - coalesce(sum(t.amount_minor) filter (where t.transaction_kind = 'expense'), 0)
    - coalesce(sum(t.amount_minor) filter (where t.transaction_kind = 'allowance_given'), 0))::bigint
  from public.financial_transactions t
  where t.user_id = (select auth.uid())
    and t.occurred_on between p_start and p_end
    and t.transaction_kind <> 'transfer'
  group by 1
  order by 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- Amounts grouped by category (expenses / allowances / income breakdowns)
-- ---------------------------------------------------------------------------
create or replace function public.amounts_by_category(
  p_start date,
  p_end date,
  p_kind public.transaction_kind
)
returns table (
  category_id uuid,
  category_name text,
  category_icon text,
  total_minor bigint,
  tx_count bigint
)
language sql
stable
set search_path = ''
as $$
  select
    t.category_id,
    coalesce(c.name, 'Uncategorized'),
    coalesce(c.icon, 'category'),
    sum(t.amount_minor)::bigint,
    count(*)::bigint
  from public.financial_transactions t
  left join public.transaction_categories c on c.id = t.category_id
  where t.user_id = (select auth.uid())
    and t.occurred_on between p_start and p_end
    and t.transaction_kind = p_kind
  group by t.category_id, c.name, c.icon
  order by 4 desc;
$$;

-- ---------------------------------------------------------------------------
-- Account balance history (running daily balance, computed server-side)
-- ---------------------------------------------------------------------------
create or replace function public.account_balance_history(
  p_account_id uuid,
  p_start date,
  p_end date
)
returns table (day date, balance_minor bigint)
language sql
stable
set search_path = ''
as $$
  with account as (
    select id, opening_balance_minor
    from public.accounts
    where id = p_account_id and user_id = (select auth.uid())
  ),
  opening as (
    select
      a.opening_balance_minor + coalesce((
        select sum(f.signed_amount_minor)
        from public.account_flows f
        where f.account_id = a.id and f.occurred_on < p_start
      ), 0) as start_balance
    from account a
  ),
  daily as (
    select f.occurred_on as day, sum(f.signed_amount_minor) as delta
    from public.account_flows f
    join account a on a.id = f.account_id
    where f.occurred_on between p_start and p_end
    group by f.occurred_on
  ),
  series as (
    select generate_series(p_start, p_end, interval '1 day')::date as day
  )
  select
    s.day,
    ((select start_balance from opening)
      + coalesce(sum(d.delta) over (order by s.day), 0))::bigint as balance_minor
  from series s
  left join daily d on d.day = s.day
  where exists (select 1 from account);
$$;

-- ---------------------------------------------------------------------------
-- Work summary for a date range (salary-estimate input aggregation)
-- ---------------------------------------------------------------------------
create or replace function public.work_summary(p_start date, p_end date)
returns table (
  entry_type public.work_entry_type,
  entry_count bigint,
  total_minutes bigint,
  total_day_units_hundredths bigint,
  total_amount_minor bigint
)
language sql
stable
set search_path = ''
as $$
  select
    w.entry_type,
    count(*)::bigint,
    coalesce(sum(w.duration_minutes), 0)::bigint,
    coalesce(sum(w.day_units_hundredths), 0)::bigint,
    coalesce(sum(w.computed_amount_minor), 0)::bigint
  from public.work_entries w
  where w.user_id = (select auth.uid())
    and w.work_date between p_start and p_end
  group by w.entry_type;
$$;

-- ---------------------------------------------------------------------------
-- Working minutes grouped by week / month (reports)
-- ---------------------------------------------------------------------------
create or replace function public.work_minutes_series(
  p_start date,
  p_end date,
  p_bucket text default 'week'
)
returns table (bucket_start date, total_minutes bigint)
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_bucket not in ('day', 'week', 'month') then
    raise exception 'invalid_bucket: %', p_bucket;
  end if;
  return query
  select
    date_trunc(p_bucket, w.work_date)::date,
    coalesce(sum(w.duration_minutes), 0)::bigint
  from public.work_entries w
  where w.user_id = (select auth.uid())
    and w.work_date between p_start and p_end
    and w.duration_minutes is not null
  group by 1
  order by 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- Default categories seeder
-- ---------------------------------------------------------------------------
create or replace function public.seed_default_categories(p_user_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  insert into public.transaction_categories (user_id, name, category_kind, icon, sort_order)
  values
    (p_user_id, 'Food', 'expense', 'restaurant', 0),
    (p_user_id, 'Transportation', 'expense', 'directions_bus', 1),
    (p_user_id, 'Bills', 'expense', 'receipt_long', 2),
    (p_user_id, 'Shopping', 'expense', 'shopping_bag', 3),
    (p_user_id, 'Health', 'expense', 'medical_services', 4),
    (p_user_id, 'Education', 'expense', 'school', 5),
    (p_user_id, 'Entertainment', 'expense', 'movie', 6),
    (p_user_id, 'Rent', 'expense', 'home', 7),
    (p_user_id, 'Subscriptions', 'expense', 'subscriptions', 8),
    (p_user_id, 'Other', 'expense', 'category', 9),
    (p_user_id, 'Family', 'allowance', 'family_restroom', 0),
    (p_user_id, 'Children', 'allowance', 'child_care', 1),
    (p_user_id, 'Gift', 'allowance', 'card_giftcard', 2),
    (p_user_id, 'Charity', 'allowance', 'volunteer_activism', 3),
    (p_user_id, 'Support', 'allowance', 'handshake', 4),
    (p_user_id, 'Other', 'allowance', 'category', 5),
    (p_user_id, 'Freelance', 'income', 'work', 0),
    (p_user_id, 'Bonus', 'income', 'stars', 1),
    (p_user_id, 'Refund', 'income', 'undo', 2),
    (p_user_id, 'Sale', 'income', 'sell', 3),
    (p_user_id, 'Gift received', 'income', 'redeem', 4),
    (p_user_id, 'Other', 'income', 'category', 5)
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic onboarding completion
-- ---------------------------------------------------------------------------
create or replace function public.complete_onboarding(
  p_display_name text,
  p_currency_code text,
  p_timezone text,
  p_locale text,
  p_week_starts_on smallint,
  p_weekend_days smallint[],
  p_base_salary_minor bigint,
  p_salary_period_start_day smallint,
  p_payment_day smallint,
  p_payment_month_offset smallint,
  p_standard_paid_days smallint,
  p_standard_minutes_per_day integer,
  p_day_rate_mode public.rate_mode,
  p_manual_day_rate_minor bigint,
  p_hour_rate_mode public.rate_mode,
  p_manual_hour_rate_minor bigint,
  p_extra_day_multiplier_pct integer,
  p_official_holiday_multiplier_pct integer,
  p_overtime_multiplier_pct integer,
  p_holiday_semantics public.holiday_multiplier_semantics,
  p_account_name text,
  p_account_type public.account_type,
  p_opening_balance_minor bigint,
  p_allow_negative_balance boolean
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

  update public.profiles
    set display_name = p_display_name
    where id = v_user_id;
  if not found then
    insert into public.profiles (id, display_name)
    values (v_user_id, p_display_name);
  end if;

  insert into public.user_preferences (
    user_id, currency_code, timezone, locale,
    week_starts_on, weekend_days, onboarding_completed_at
  ) values (
    v_user_id, p_currency_code, p_timezone, p_locale,
    p_week_starts_on, p_weekend_days, now()
  )
  on conflict (user_id) do update set
    currency_code = excluded.currency_code,
    timezone = excluded.timezone,
    locale = excluded.locale,
    week_starts_on = excluded.week_starts_on,
    weekend_days = excluded.weekend_days,
    onboarding_completed_at = now();

  insert into public.salary_settings (
    user_id, base_salary_minor, currency_code,
    salary_period_start_day, payment_day, payment_month_offset,
    standard_paid_days_per_period, standard_minutes_per_day,
    day_rate_mode, manual_day_rate_minor,
    hour_rate_mode, manual_hour_rate_minor,
    extra_day_multiplier_pct, official_holiday_multiplier_pct,
    overtime_multiplier_pct, official_holiday_multiplier_semantics
  ) values (
    v_user_id, p_base_salary_minor, p_currency_code,
    p_salary_period_start_day, p_payment_day, p_payment_month_offset,
    p_standard_paid_days, p_standard_minutes_per_day,
    p_day_rate_mode, p_manual_day_rate_minor,
    p_hour_rate_mode, p_manual_hour_rate_minor,
    p_extra_day_multiplier_pct, p_official_holiday_multiplier_pct,
    p_overtime_multiplier_pct, p_holiday_semantics
  )
  on conflict (user_id) do update set
    base_salary_minor = excluded.base_salary_minor,
    currency_code = excluded.currency_code,
    salary_period_start_day = excluded.salary_period_start_day,
    payment_day = excluded.payment_day,
    payment_month_offset = excluded.payment_month_offset,
    standard_paid_days_per_period = excluded.standard_paid_days_per_period,
    standard_minutes_per_day = excluded.standard_minutes_per_day,
    day_rate_mode = excluded.day_rate_mode,
    manual_day_rate_minor = excluded.manual_day_rate_minor,
    hour_rate_mode = excluded.hour_rate_mode,
    manual_hour_rate_minor = excluded.manual_hour_rate_minor,
    extra_day_multiplier_pct = excluded.extra_day_multiplier_pct,
    official_holiday_multiplier_pct = excluded.official_holiday_multiplier_pct,
    overtime_multiplier_pct = excluded.overtime_multiplier_pct,
    official_holiday_multiplier_semantics = excluded.official_holiday_multiplier_semantics;

  -- First account becomes the default when no active account exists yet.
  insert into public.accounts (
    user_id, name, account_type, currency_code,
    opening_balance_minor, is_default, allow_negative_balance
  ) values (
    v_user_id, p_account_name, p_account_type, p_currency_code,
    p_opening_balance_minor,
    not exists (
      select 1 from public.accounts
      where user_id = v_user_id and not is_archived
    ),
    p_allow_negative_balance
  )
  returning id into v_account_id;

  perform public.seed_default_categories(v_user_id);

  return v_account_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic transfer between own accounts
-- ---------------------------------------------------------------------------
create or replace function public.create_transfer(
  p_source_account_id uuid,
  p_destination_account_id uuid,
  p_amount_minor bigint,
  p_occurred_on date,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_currency text;
  v_dest_currency text;
  v_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if p_source_account_id = p_destination_account_id then
    raise exception 'invalid_transfer: source equals destination';
  end if;

  select currency_code into v_currency
    from public.accounts
    where id = p_source_account_id and user_id = v_user_id and not is_archived;
  if v_currency is null then
    raise exception 'invalid_account: source not found or archived';
  end if;
  select currency_code into v_dest_currency
    from public.accounts
    where id = p_destination_account_id and user_id = v_user_id and not is_archived;
  if v_dest_currency is null then
    raise exception 'invalid_account: destination not found or archived';
  end if;
  if v_currency <> v_dest_currency then
    raise exception 'currency_mismatch: transfers require matching currencies';
  end if;

  insert into public.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, notes
  ) values (
    v_user_id, 'transfer', p_occurred_on, p_amount_minor, v_currency,
    p_source_account_id, p_destination_account_id, p_notes
  )
  returning id into v_tx_id;

  return v_tx_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomic salary payment recording (idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.record_salary_payment(
  p_period_id uuid,
  p_actual_amount_minor bigint,
  p_destination_account_id uuid,
  p_received_date date,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_period record;
  v_currency text;
  v_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_actual_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select * into v_period
    from public.salary_periods
    where id = p_period_id and user_id = v_user_id
    for update;
  if v_period is null then
    raise exception 'not_found: salary period';
  end if;
  if v_period.status = 'paid' then
    raise exception 'already_paid: salary period already has a payment';
  end if;
  if v_period.status <> 'finalized' then
    raise exception 'not_finalized: finalize the period before recording payment';
  end if;

  select currency_code into v_currency
    from public.accounts
    where id = p_destination_account_id and user_id = v_user_id and not is_archived;
  if v_currency is null then
    raise exception 'invalid_account: destination not found or archived';
  end if;

  insert into public.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    destination_account_id, salary_period_id, title, notes
  ) values (
    v_user_id, 'salary_income', p_received_date, p_actual_amount_minor,
    v_currency, p_destination_account_id, p_period_id, 'Salary', p_notes
  )
  returning id into v_tx_id;

  update public.salary_periods set
    status = 'paid',
    actual_amount_minor = p_actual_amount_minor,
    received_date = p_received_date,
    destination_account_id = p_destination_account_id,
    paid_transaction_id = v_tx_id
  where id = p_period_id;

  return v_tx_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Realtime publication for user-owned tables
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.financial_transactions;
alter publication supabase_realtime add table public.work_entries;
alter publication supabase_realtime add table public.accounts;
alter publication supabase_realtime add table public.salary_periods;
alter publication supabase_realtime add table public.salary_adjustments;
alter publication supabase_realtime add table public.official_holidays;
alter publication supabase_realtime add table public.transaction_categories;
