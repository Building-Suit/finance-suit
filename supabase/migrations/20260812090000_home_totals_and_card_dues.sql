-- Home-tab accuracy pass.
--
-- 1. Hidden accounts leave the Home cash-flow numbers as well as the balance
--    list: a new cash_flow_summary_v3 takes an exclude-hidden flag so Home
--    can ask for "only what I chose to see" while Reports keeps counting
--    everything.
-- 2. Credit facilities expose what is coming due over the next month, summed
--    across every unpaid installment and statement instead of only the
--    earliest one, so a card can show a single honest figure.
-- 3. Open salary periods that were created under an older payment offset get
--    their expected payment date recomputed from current settings — a
--    finalized or paid period keeps its history untouched.

-- ---------------------------------------------------------------------------
-- 1. Cash flow that can skip hidden accounts
-- ---------------------------------------------------------------------------

create or replace function app_reports.cash_flow_summary_v3(
  p_start date,
  p_end date,
  p_exclude_hidden boolean default false
)
returns table (
  currency_code text,
  starting_balance_minor bigint,
  income_minor bigint,
  expenses_minor bigint,
  allowances_minor bigint,
  net_minor bigint,
  ending_balance_minor bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_skip boolean := coalesce(p_exclude_hidden, false);
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_start > p_end then
    raise exception 'invalid_range: start must be on or before end';
  end if;

  return query
  with visible as (
    select a.*
    from app_finance.accounts a
    where a.user_id = v_user_id
      and not a.is_archived
      and (not v_skip or not a.hide_from_home)
  ),
  currencies as (
    select distinct v.currency_code from visible v
    union
    select distinct t.currency_code
    from app_finance.financial_transactions t
    join visible v
      on v.id = coalesce(t.source_account_id, t.destination_account_id)
    where t.user_id = v_user_id
      and t.occurred_on <= p_end
  ),
  opening as (
    select v.currency_code, sum(v.opening_balance_minor)::bigint as amount
    from visible v
    group by v.currency_code
  ),
  before_flows as (
    select
      t.currency_code,
      sum(case
        when t.transaction_kind in
          ('custom_income', 'freelance_income', 'salary_income')
          then t.amount_minor
        when t.transaction_kind in ('expense', 'allowance_given')
          then -t.amount_minor
        else 0
      end)::bigint as amount
    from app_finance.financial_transactions t
    join visible v
      on v.id = coalesce(t.source_account_id, t.destination_account_id)
    where t.user_id = v_user_id
      and t.occurred_on < p_start
      and t.transaction_kind <> 'transfer'
    group by t.currency_code
  ),
  ranged as (
    select
      t.currency_code,
      coalesce(sum(t.amount_minor) filter (where t.transaction_kind in
        ('custom_income', 'freelance_income', 'salary_income')), 0)::bigint
        as income_minor,
      coalesce(sum(t.amount_minor)
        filter (where t.transaction_kind = 'expense'), 0)::bigint
        as expenses_minor,
      coalesce(sum(t.amount_minor)
        filter (where t.transaction_kind = 'allowance_given'), 0)::bigint
        as allowances_minor
    from app_finance.financial_transactions t
    join visible v
      on v.id = coalesce(t.source_account_id, t.destination_account_id)
    where t.user_id = v_user_id
      and t.occurred_on between p_start and p_end
      and t.transaction_kind <> 'transfer'
    group by t.currency_code
  )
  select
    c.currency_code,
    (coalesce(o.amount, 0) + coalesce(b.amount, 0))::bigint
      as starting_balance_minor,
    coalesce(r.income_minor, 0)::bigint,
    coalesce(r.expenses_minor, 0)::bigint,
    coalesce(r.allowances_minor, 0)::bigint,
    (coalesce(r.income_minor, 0) - coalesce(r.expenses_minor, 0)
      - coalesce(r.allowances_minor, 0))::bigint as net_minor,
    (coalesce(o.amount, 0) + coalesce(b.amount, 0)
      + coalesce(r.income_minor, 0) - coalesce(r.expenses_minor, 0)
      - coalesce(r.allowances_minor, 0))::bigint as ending_balance_minor
  from currencies c
  left join opening o using (currency_code)
  left join before_flows b using (currency_code)
  left join ranged r using (currency_code)
  order by c.currency_code;
end;
$$;

revoke execute on function app_reports.cash_flow_summary_v3(date, date, boolean)
from public, anon;
grant execute on function app_reports.cash_flow_summary_v3(date, date, boolean)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Everything a facility owes over the next month
-- ---------------------------------------------------------------------------

-- Appending a column keeps every existing reader valid; the earlier columns
-- stay in place because CREATE OR REPLACE VIEW cannot reorder them.
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
    coalesce(plans.active_plan_count, 0)::integer as active_plan_count,
    -- Everything still unpaid that falls due between today and one month
    -- out, installments and statements together: what the card actually
    -- asks for next, not just its earliest single due.
    (coalesce(dues.upcoming_due_minor, 0)
      + coalesce(cycles.upcoming_due_minor, 0))::bigint as upcoming_due_minor
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
        filter (where d.remaining_minor > 0))[1] as next_due_amount_minor,
      sum(d.remaining_minor) filter (
        where d.due_on <= (current_date + interval '1 month')::date
      ) as upcoming_due_minor
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
      sum(y.remaining_minor) as statement_remaining_minor,
      sum(y.remaining_minor) filter (
        where y.due_on <= (current_date + interval '1 month')::date
      ) as upcoming_due_minor
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
-- 3. Open salary periods follow the current payment offset
-- ---------------------------------------------------------------------------

-- A period's expected payment date is derived from settings, not entered by
-- hand. Changing the payment offset used to leave already-materialized open
-- periods pointing at the old date, so a period earning through August still
-- claimed it would be paid on 5 August instead of 5 September.
update app_salary.salary_periods p
set expected_payment_date =
  (date_trunc('month', p.period_start)
    + make_interval(months => s.payment_month_offset))::date
  + (s.payment_day - 1)
from app_salary.salary_settings s
where s.user_id = p.user_id
  and p.status = 'open'
  and p.expected_payment_date <>
    (date_trunc('month', p.period_start)
      + make_interval(months => s.payment_month_offset))::date
    + (s.payment_day - 1);

notify pgrst, 'reload schema';
