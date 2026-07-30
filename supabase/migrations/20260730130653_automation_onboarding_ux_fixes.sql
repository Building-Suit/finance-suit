-- Harden onboarding's four income choices, keep automation types stable, and
-- publish every automation table consumed by Flutter Realtime.

create or replace function app_private.prevent_income_source_kind_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.source_kind is distinct from old.source_kind then
    raise exception 'income_source_type_immutable: create a new automation';
  end if;
  return new;
end;
$$;

create trigger trg_prevent_income_source_kind_change
  before update of source_kind on app_finance.income_sources
  for each row execute function app_private.prevent_income_source_kind_change();

create or replace function app_core.complete_onboarding_v2(
  p_display_name text,
  p_currency_code text,
  p_timezone text,
  p_locale text,
  p_week_starts_on smallint,
  p_weekend_days smallint[],
  p_salary_enabled boolean,
  p_base_salary_minor bigint,
  p_salary_period_start_day smallint,
  p_payment_day smallint,
  p_payment_month_offset smallint,
  p_standard_paid_days smallint,
  p_standard_minutes_per_day integer,
  p_day_rate_mode app_salary.rate_mode,
  p_manual_day_rate_minor bigint,
  p_hour_rate_mode app_salary.rate_mode,
  p_manual_hour_rate_minor bigint,
  p_extra_day_multiplier_pct integer,
  p_official_holiday_multiplier_pct integer,
  p_overtime_multiplier_pct integer,
  p_holiday_semantics app_salary.holiday_multiplier_semantics,
  p_account_name text,
  p_account_type app_finance.account_type,
  p_opening_balance_minor bigint,
  p_allow_negative_balance boolean,
  p_income_source_kind app_finance.income_source_kind default null,
  p_income_source_name text default null,
  p_expected_income_minor bigint default null,
  p_income_payment_day smallint default null,
  p_prompt_days_before smallint default 7
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_source_id uuid;
  v_salary_base bigint;
  v_period_start smallint;
  v_payment_day smallint;
  v_payment_offset smallint;
  v_paid_days smallint;
  v_minutes integer;
  v_day_mode app_salary.rate_mode;
  v_manual_day bigint;
  v_hour_mode app_salary.rate_mode;
  v_manual_hour bigint;
  v_extra_pct integer;
  v_holiday_pct integer;
  v_overtime_pct integer;
  v_semantics app_salary.holiday_multiplier_semantics;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  if p_salary_enabled then
    if p_income_source_kind is distinct from 'salary'
      or p_base_salary_minor is null or p_base_salary_minor <= 0 then
      raise exception 'invalid_salary_onboarding: salary and a positive amount are required';
    end if;
  elsif p_income_source_kind = 'salary' then
    raise exception 'invalid_income_choice: salary source requires salary_enabled';
  end if;

  if p_income_source_kind is not null then
    if nullif(btrim(p_income_source_name), '') is null
      or p_expected_income_minor is null or p_expected_income_minor <= 0
      or p_income_payment_day is null
      or p_income_payment_day not between 1 and 28
      or p_prompt_days_before not between 0 and 31 then
      raise exception 'income_source_fields_required: valid name, amount, payment day, and prompt are required';
    end if;
  end if;

  -- Hidden salary controls are deliberately normalized for non-salary paths.
  v_salary_base := case when p_salary_enabled then p_base_salary_minor else 0 end;
  v_period_start := case when p_salary_enabled then p_salary_period_start_day else 1 end;
  v_payment_day := case
    when p_salary_enabled then p_payment_day
    else coalesce(p_income_payment_day, 1)
  end;
  v_payment_offset := case when p_salary_enabled then p_payment_month_offset else 1 end;
  v_paid_days := case when p_salary_enabled then p_standard_paid_days else 22 end;
  v_minutes := case when p_salary_enabled then p_standard_minutes_per_day else 480 end;
  v_day_mode := case when p_salary_enabled then p_day_rate_mode else 'derived' end;
  v_manual_day := case when p_salary_enabled and p_day_rate_mode = 'manual'
    then p_manual_day_rate_minor else null end;
  v_hour_mode := case when p_salary_enabled then p_hour_rate_mode else 'derived' end;
  v_manual_hour := case when p_salary_enabled and p_hour_rate_mode = 'manual'
    then p_manual_hour_rate_minor else null end;
  v_extra_pct := case when p_salary_enabled then p_extra_day_multiplier_pct else 100 end;
  v_holiday_pct := case when p_salary_enabled then p_official_holiday_multiplier_pct else 200 end;
  v_overtime_pct := case when p_salary_enabled then p_overtime_multiplier_pct else 150 end;
  v_semantics := case when p_salary_enabled then p_holiday_semantics else 'additional_pay' end;

  select app_core.complete_onboarding(
    p_display_name, p_currency_code, p_timezone, p_locale,
    p_week_starts_on, p_weekend_days, v_salary_base,
    v_period_start, v_payment_day, v_payment_offset,
    v_paid_days, v_minutes, v_day_mode, v_manual_day,
    v_hour_mode, v_manual_hour, v_extra_pct, v_holiday_pct,
    v_overtime_pct, v_semantics, p_account_name, p_account_type,
    p_opening_balance_minor, p_allow_negative_balance
  ) into v_account_id;

  update app_salary.salary_settings
  set salary_enabled = p_salary_enabled
  where user_id = v_user_id;

  if p_income_source_kind is not null then
    if p_income_source_kind = 'salary' then
      select id into v_source_id
      from app_finance.income_sources
      where user_id = v_user_id and source_kind = 'salary'
      order by is_active desc, created_at, id
      limit 1;
    end if;

    perform app_finance.save_income_source_v2(
      btrim(p_income_source_name),
      p_income_source_kind,
      case when p_salary_enabled then p_base_salary_minor else p_expected_income_minor end,
      p_currency_code,
      case when p_salary_enabled then p_payment_day else p_income_payment_day end,
      current_date,
      p_prompt_days_before,
      v_account_id,
      null,
      '[]'::jsonb,
      null,
      v_source_id,
      true
    );
  end if;

  return v_account_id;
end;
$$;

revoke execute on function app_core.complete_onboarding_v2(
  text, text, text, text, smallint, smallint[], boolean, bigint, smallint,
  smallint, smallint, smallint, integer, app_salary.rate_mode, bigint,
  app_salary.rate_mode, bigint, integer, integer, integer,
  app_salary.holiday_multiplier_semantics, text, app_finance.account_type,
  bigint, boolean, app_finance.income_source_kind, text, bigint, smallint,
  smallint
) from public, anon;
grant execute on function app_core.complete_onboarding_v2(
  text, text, text, text, smallint, smallint[], boolean, bigint, smallint,
  smallint, smallint, smallint, integer, app_salary.rate_mode, bigint,
  app_salary.rate_mode, bigint, integer, integer, integer,
  app_salary.holiday_multiplier_semantics, text, app_finance.account_type,
  bigint, boolean, app_finance.income_source_kind, text, bigint, smallint,
  smallint
) to authenticated, service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'app_finance'
      and tablename = 'income_source_allocations'
  ) then
    alter publication supabase_realtime
      add table app_finance.income_source_allocations;
  end if;
end;
$$;

notify pgrst, 'reload schema';
