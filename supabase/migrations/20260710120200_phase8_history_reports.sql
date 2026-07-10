-- Phase 8: dashboard, unified history, and report aggregates.
-- Views use security_invoker so base-table RLS remains authoritative.

create or replace view app_reports.history_items
with (security_invoker = on) as
  select
    t.id,
    t.user_id,
    'transaction'::text as record_group,
    t.transaction_kind::text as record_type,
    t.occurred_on as record_date,
    t.created_at,
    t.amount_minor,
    abs(t.amount_minor) as amount_abs_minor,
    t.currency_code,
    t.source_account_id,
    t.destination_account_id,
    t.category_id,
    t.counterparty,
    t.salary_period_id,
    coalesce(t.title, initcap(replace(t.transaction_kind::text, '_', ' '))) as title,
    t.notes
  from app_finance.financial_transactions t
  union all
  select
    w.id,
    w.user_id,
    'work'::text as record_group,
    w.entry_type::text as record_type,
    w.work_date as record_date,
    w.created_at,
    w.computed_amount_minor as amount_minor,
    abs(w.computed_amount_minor) as amount_abs_minor,
    ss.currency_code,
    null::uuid as source_account_id,
    null::uuid as destination_account_id,
    null::uuid as category_id,
    null::text as counterparty,
    null::uuid as salary_period_id,
    initcap(replace(w.entry_type::text, '_', ' ')) as title,
    w.notes
  from app_work.work_entries w
  left join app_salary.salary_settings ss on ss.user_id = w.user_id
  union all
  select
    a.id,
    a.user_id,
    'salary_adjustment'::text as record_group,
    a.adjustment_type::text as record_type,
    a.effective_date as record_date,
    a.created_at,
    case
      when a.adjustment_type = 'deduction' then -a.amount_minor
      else a.amount_minor
    end as amount_minor,
    a.amount_minor as amount_abs_minor,
    ss.currency_code,
    null::uuid as source_account_id,
    null::uuid as destination_account_id,
    null::uuid as category_id,
    null::text as counterparty,
    null::uuid as salary_period_id,
    coalesce(a.title, initcap(a.adjustment_type::text)) as title,
    a.notes
  from app_salary.salary_adjustments a
  left join app_salary.salary_settings ss on ss.user_id = a.user_id;

create or replace function app_reports.salary_comparison_report(
  p_start date,
  p_end date
)
returns table (
  period_id uuid,
  period_start date,
  period_end date,
  expected_payment_date date,
  status app_salary.salary_period_status,
  estimated_minor bigint,
  actual_amount_minor bigint,
  difference_minor bigint,
  currency_code text
)
language sql
stable
set search_path = ''
as $$
  select
    sp.id,
    sp.period_start,
    sp.period_end,
    sp.expected_payment_date,
    sp.status,
    (sp.snapshot ->> 'total_minor')::bigint as estimated_minor,
    sp.actual_amount_minor,
    case
      when sp.actual_amount_minor is null then null
      else sp.actual_amount_minor - (sp.snapshot ->> 'total_minor')::bigint
    end as difference_minor,
    coalesce(sp.snapshot ->> 'currency_code', ss.currency_code, 'EGP') as currency_code
  from app_salary.salary_periods sp
  left join app_salary.salary_settings ss on ss.user_id = sp.user_id
  where sp.user_id = (select auth.uid())
    and sp.snapshot is not null
    and sp.period_start <= p_end
    and sp.period_end >= p_start
  order by sp.period_start;
$$;

create or replace function app_reports.salary_period_work_report(
  p_start date,
  p_end date
)
returns table (
  period_id uuid,
  period_start date,
  period_end date,
  overtime_minutes bigint,
  overtime_amount_minor bigint,
  extra_day_units_hundredths bigint,
  extra_day_amount_minor bigint,
  holiday_count bigint,
  holiday_amount_minor bigint,
  currency_code text
)
language sql
stable
set search_path = ''
as $$
  select
    sp.id,
    sp.period_start,
    sp.period_end,
    coalesce(sum(w.duration_minutes) filter (where w.entry_type = 'overtime'), 0)::bigint,
    coalesce(sum(w.computed_amount_minor) filter (where w.entry_type = 'overtime'), 0)::bigint,
    coalesce(sum(w.day_units_hundredths) filter (where w.entry_type = 'extra_day'), 0)::bigint,
    coalesce(sum(w.computed_amount_minor) filter (where w.entry_type = 'extra_day'), 0)::bigint,
    coalesce(count(w.id) filter (where w.entry_type = 'holiday_worked'), 0)::bigint,
    coalesce(sum(w.computed_amount_minor) filter (where w.entry_type = 'holiday_worked'), 0)::bigint,
    coalesce(sp.snapshot ->> 'currency_code', ss.currency_code, 'EGP') as currency_code
  from app_salary.salary_periods sp
  left join app_salary.salary_settings ss on ss.user_id = sp.user_id
  left join app_work.work_entries w
    on w.user_id = sp.user_id
   and w.work_date between sp.period_start and sp.period_end
  where sp.user_id = (select auth.uid())
    and sp.period_start <= p_end
    and sp.period_end >= p_start
  group by sp.id, sp.period_start, sp.period_end, sp.snapshot, ss.currency_code
  order by sp.period_start;
$$;

create or replace function app_reports.income_amounts_by_category(
  p_start date,
  p_end date
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
    coalesce(c.name, initcap(replace(t.transaction_kind::text, '_', ' '))) as category_name,
    coalesce(c.icon, 'payments') as category_icon,
    sum(t.amount_minor)::bigint as total_minor,
    count(*)::bigint as tx_count
  from app_finance.financial_transactions t
  left join app_finance.transaction_categories c on c.id = t.category_id
  where t.user_id = (select auth.uid())
    and t.occurred_on between p_start and p_end
    and t.transaction_kind in ('custom_income', 'freelance_income', 'salary_income')
  group by t.category_id, c.name, c.icon, t.transaction_kind
  order by 4 desc;
$$;
