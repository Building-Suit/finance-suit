-- Phase 9: realtime coverage and local performance support.

alter publication supabase_realtime add table app_salary.salary_settings;

create or replace function app_private.seed_performance_sample(
  p_months integer default 18,
  p_transactions_per_month integer default 120,
  p_work_entries_per_month integer default 35
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_category_id uuid;
  v_start date;
  i integer;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_months < 1 or p_months > 60 then
    raise exception 'invalid_months';
  end if;
  if p_transactions_per_month < 0 or p_transactions_per_month > 1000 then
    raise exception 'invalid_transaction_count';
  end if;
  if p_work_entries_per_month < 0 or p_work_entries_per_month > 250 then
    raise exception 'invalid_work_count';
  end if;

  select id into v_account_id
  from app_finance.accounts
  where user_id = v_user_id and not is_archived
  order by is_default desc, created_at
  limit 1;
  if v_account_id is null then
    raise exception 'missing_account';
  end if;

  select id into v_category_id
  from app_finance.transaction_categories
  where user_id = v_user_id and category_kind = 'expense' and not is_archived
  order by sort_order, name
  limit 1;

  v_start := date_trunc('month', current_date)::date - ((p_months - 1) || ' months')::interval;

  insert into app_finance.financial_transactions (
    user_id,
    transaction_kind,
    occurred_on,
    amount_minor,
    currency_code,
    destination_account_id,
    title
  )
  values (
    v_user_id,
    'custom_income',
    v_start,
    greatest((p_months * p_transactions_per_month * 20000)::bigint, 1000000),
    'EGP',
    v_account_id,
    'Performance sample funding'
  );

  for i in 0..(p_months * p_transactions_per_month - 1) loop
    insert into app_finance.financial_transactions (
      user_id,
      transaction_kind,
      occurred_on,
      amount_minor,
      currency_code,
      source_account_id,
      destination_account_id,
      category_id,
      title
    )
    values (
      v_user_id,
      case
        when i % 17 = 0 then 'custom_income'::app_finance.transaction_kind
        when i % 11 = 0 then 'allowance_given'::app_finance.transaction_kind
        else 'expense'::app_finance.transaction_kind
      end,
      v_start + (i % (p_months * 28)),
      (5000 + (i % 70) * 100)::bigint,
      'EGP',
      case when i % 17 = 0 then null else v_account_id end,
      case when i % 17 = 0 then v_account_id else null end,
      case when i % 17 = 0 then null else v_category_id end,
      'Performance sample'
    );
  end loop;

  for i in 0..(p_months * p_work_entries_per_month - 1) loop
    insert into app_work.work_entries (
      user_id,
      work_date,
      entry_type,
      duration_minutes,
      day_units_hundredths,
      break_minutes,
      computed_amount_minor,
      calc_snapshot,
      notes
    )
    values (
      v_user_id,
      v_start + (i % (p_months * 28)),
      case
        when i % 13 = 0 then 'holiday_worked'::app_work.work_entry_type
        when i % 5 = 0 then 'extra_day'::app_work.work_entry_type
        else 'overtime'::app_work.work_entry_type
      end,
      case when i % 5 = 0 then null else 120 + (i % 5) * 30 end,
      case when i % 5 = 0 then 100 else null end,
      0,
      (10000 + (i % 20) * 500)::bigint,
      '{"source":"seed_performance_sample"}'::jsonb,
      'Performance sample'
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- API schema privileges
-- ---------------------------------------------------------------------------
grant usage on schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
to authenticated, service_role;

grant select, insert, update, delete on all tables in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
to authenticated, service_role;

grant usage, select on all sequences in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
to authenticated, service_role;

grant usage on all types in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
to authenticated, service_role;

revoke execute on all functions in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
from public, anon;

grant execute on all functions in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
to authenticated, service_role;

revoke all on schema app_private from anon, authenticated;
revoke execute on all functions in schema app_private from public, anon, authenticated;
grant usage on schema app_private to service_role;
grant execute on all functions in schema app_private to service_role;

alter default privileges in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
grant select, insert, update, delete on tables to authenticated, service_role;

alter default privileges in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
grant usage, select on sequences to authenticated, service_role;

alter default privileges in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
grant usage on types to authenticated, service_role;

alter default privileges in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
revoke execute on functions from public, anon;

alter default privileges in schema
  app_core,
  app_finance,
  app_work,
  app_salary,
  app_reports
grant execute on functions to authenticated, service_role;

alter default privileges in schema app_private
revoke execute on functions from public, anon, authenticated;

notify pgrst, 'reload schema';
