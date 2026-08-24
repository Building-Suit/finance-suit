-- Ordinary BNPL purchases are billed with the following month, and an
-- unpaid due always rides the next upcoming bill instead of going "late".
--
-- Two fixes to how a BNPL provider (ValU-style monthly billing) actually
-- collects:
--
--   1. Base rule. A purchase made in month M is collected on the facility's
--      due day of month M+1. The old rule ("first occurrence of the due day
--      strictly after the purchase date") billed a purchase made early in
--      the month inside that same month, which put freshly backfilled
--      obligations weeks in the past and surfaced them as overdue dues the
--      provider never actually asked for yet.
--
--   2. Roll-forward. When a bill day passes with an obligation still
--      unpaid, the provider adds it to the next month's bill. The canonical
--      read surface now exposes exactly that: the effective due date of an
--      unpaid obligation is never stuck in the past — it moves to the next
--      occurrence of the billing day, so Home, the due breakdowns, the
--      month carousel and the Pay screen all show it with the month it will
--      really be collected in. The stored due_on keeps the bill the
--      purchase was first placed on; paid history is untouched.
--
-- Existing obligations that no payment has ever been allocated to are
-- re-dated with the corrected base rule.

-- ---------------------------------------------------------------------------
-- 1. Base rule: billed with the following month
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
  v_month_start date :=
    (date_trunc('month', p_purchased_on) + interval '1 month')::date;
  v_last_day integer;
begin
  v_last_day := extract(
    day from (v_month_start + interval '1 month - 1 day')
  )::integer;
  return v_month_start + (least(v_day, v_last_day) - 1);
end;
$$;

comment on function app_finance.bnpl_purchase_due_on(smallint, date) is
  'Due date of an ordinary BNPL purchase: the facility default_due_day in '
  'the month after the purchase month (day 31 becomes Feb 28/29), matching '
  'monthly BNPL billing where month M purchases are collected with month '
  'M+1. Installment schedules and credit-card statement cycles are '
  'unaffected.';

-- ---------------------------------------------------------------------------
-- 2. The next upcoming bill date
-- ---------------------------------------------------------------------------

create or replace function app_finance.bnpl_next_bill_on(
  p_due_day smallint,
  p_on date
)
returns date
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_day integer := greatest(least(coalesce(p_due_day, 1), 31), 1);
  v_month_start date := date_trunc('month', p_on)::date;
  v_last_day integer;
  v_candidate date;
begin
  v_last_day := extract(
    day from (v_month_start + interval '1 month - 1 day')
  )::integer;
  v_candidate := v_month_start + (least(v_day, v_last_day) - 1);
  -- On the bill day itself the bill is today, not next month.
  if v_candidate >= p_on then
    return v_candidate;
  end if;
  v_month_start := (v_month_start + interval '1 month')::date;
  v_last_day := extract(
    day from (v_month_start + interval '1 month - 1 day')
  )::integer;
  return v_month_start + (least(v_day, v_last_day) - 1);
end;
$$;

comment on function app_finance.bnpl_next_bill_on(smallint, date) is
  'First occurrence of the facility billing day on or after the given '
  'date: the bill an unpaid BNPL obligation is collected with.';

revoke execute on function app_finance.bnpl_next_bill_on(smallint, date)
  from public, anon;
grant execute on function app_finance.bnpl_next_bill_on(smallint, date)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Canonical read surface: unpaid dues ride the next bill
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
    eff.due_on,
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
      when eff.due_on < current_date then 'overdue'
      when eff.due_on = current_date then 'due_today'
      when coalesce(al.paid_minor, 0) > 0 then 'partially_paid'
      else 'upcoming'
    end as due_status
  from app_finance.bnpl_purchase_obligations o
  join app_finance.financial_transactions t on t.id = o.transaction_id
  left join app_finance.credit_facility_settings s
    on s.account_id = o.account_id and s.user_id = o.user_id
  left join lateral (
    select sum(pa.amount_minor)::bigint as paid_minor
    from app_finance.bnpl_purchase_payment_allocations pa
    where pa.obligation_id = o.id
  ) al on true
  cross join lateral (
    -- The bill an unpaid amount is actually collected with: a missed bill
    -- day moves the remainder onto the next month's bill rather than
    -- leaving a permanently late due. Paid obligations keep their bill.
    select case
      when t.amount_minor - coalesce(al.paid_minor, 0) > 0
        and o.due_on < current_date
        and s.default_due_day is not null
      then app_finance.bnpl_next_bill_on(s.default_due_day, current_date)
      else o.due_on
    end as due_on
  ) eff;

comment on view app_finance.bnpl_purchase_obligation_statuses is
  'Canonical due and paid state of ordinary BNPL purchases. Amount comes '
  'from the linked ledger transaction and paid state from allocation rows. '
  'due_on is the bill the remaining amount is collected with: an unpaid '
  'obligation whose bill day passed rolls to the next billing day.';

grant select on app_finance.bnpl_purchase_obligation_statuses
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Re-date obligations no payment has touched with the corrected rule
-- ---------------------------------------------------------------------------

update app_finance.bnpl_purchase_obligations o
set due_on = app_finance.bnpl_purchase_due_on(s.default_due_day, t.occurred_on)
from app_finance.financial_transactions t,
  app_finance.credit_facility_settings s
where t.id = o.transaction_id
  and t.user_id = o.user_id
  and s.account_id = o.account_id
  and s.user_id = o.user_id
  and not exists (
    select 1 from app_finance.bnpl_purchase_payment_allocations pa
    where pa.obligation_id = o.id
  )
  and o.due_on is distinct from
    app_finance.bnpl_purchase_due_on(s.default_due_day, t.occurred_on);

notify pgrst, 'reload schema';
