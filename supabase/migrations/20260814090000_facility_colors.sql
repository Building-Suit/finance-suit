-- User-chosen colour for a credit card or BNPL facility.
--
-- A wallet holds physical cards the user recognizes by colour before they
-- read the name, so the app lets each facility carry that colour and paints
-- its Home tile, its Money row, and its detail header with it. The colour is
-- presentation only: no balance, statement, due, or report figure depends on
-- it, and a facility without one keeps the default brand surface exactly as
-- before.
--
-- Stored as an uppercase `#RRGGBB` string rather than an integer so the value
-- is readable in the database and portable across clients. Contrast for
-- foreground text is derived on the client from the colour's luminance.

alter table app_finance.credit_facility_settings
  add column if not exists color_hex text;

alter table app_finance.credit_facility_settings
  drop constraint if exists credit_facility_settings_color_hex_format;
alter table app_finance.credit_facility_settings
  add constraint credit_facility_settings_color_hex_format
  check (color_hex is null or color_hex ~ '^#[0-9A-F]{6}$');

comment on column app_finance.credit_facility_settings.color_hex is
  'Optional #RRGGBB colour matching the user''s physical card; display only.';

-- ---------------------------------------------------------------------------
-- save_credit_facility gains the colour
-- ---------------------------------------------------------------------------

-- The previous signature is dropped rather than overloaded: two candidates
-- differing only by a defaulted argument make the PostgREST call ambiguous.
drop function if exists app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer
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
  p_color_hex text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_color text := nullif(upper(trim(coalesce(p_color_hex, ''))), '');
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if app_finance.account_role(p_account_type) <> 'liability' then
    raise exception
      'invalid_account: facility settings require a credit card or BNPL account';
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
    min_payment_method, min_payment_fixed_minor, min_payment_basis_points,
    color_hex
  ) values (
    v_account_id, v_user_id, p_credit_limit_minor, p_statement_day,
    p_default_due_day, p_last_four_digits, coalesce(p_reminder_lead_days, 3),
    coalesce(p_facility_status, 'active'),
    coalesce(p_min_payment_method, 'full'),
    p_min_payment_fixed_minor, p_min_payment_basis_points, v_color
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
    min_payment_basis_points = excluded.min_payment_basis_points,
    color_hex = excluded.color_hex;

  return v_account_id;
end;
$$;

comment on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text
) is
  'Creates or updates a liability account together with its facility '
  'settings, including its display colour.';

revoke execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text
) from public, anon;
grant execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The colour travels with the facility summary
-- ---------------------------------------------------------------------------

-- Appended at the end of the select list, which CREATE OR REPLACE VIEW
-- allows; every other column keeps its position and meaning.
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
      + coalesce(cycles.upcoming_due_minor, 0))::bigint as upcoming_due_minor,
    s.color_hex
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

notify pgrst, 'reload schema';
