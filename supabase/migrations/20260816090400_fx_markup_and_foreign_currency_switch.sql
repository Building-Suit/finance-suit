-- A single flat foreign-exchange markup rate on the card itself, with a
-- plain per-charge switch — a deliberately simpler alternative to the
-- versioned fee-rules engine's `foreign_transaction` trigger (apply_when
-- conditions, min/max clamps, lookback) for the common case: one rate,
-- charged whenever the box is ticked, no rule to create first.
--
-- The two mechanisms are independent and can coexist: a card can still
-- configure a rule-based foreign-transaction fee for conditional or
-- clamped markups, while this flat rate covers the everyday case from the
-- card's own settings with no extra setup.

alter table app_finance.credit_facility_settings
  add column if not exists fx_markup_basis_points integer
  check (fx_markup_basis_points is null
    or fx_markup_basis_points between 1 and 10000);

comment on column app_finance.credit_facility_settings.fx_markup_basis_points is
  'Flat foreign-exchange markup rate, applied when a charge is flagged as '
  'foreign currency. Independent of the fee-rules engine''s '
  'foreign_transaction trigger; null means no flat markup is configured.';

-- ---------------------------------------------------------------------------
-- save_credit_facility gains the rate
-- ---------------------------------------------------------------------------

drop function if exists app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text
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
  p_color_hex text default null,
  p_fx_markup_basis_points integer default null
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
    color_hex, fx_markup_basis_points
  ) values (
    v_account_id, v_user_id, p_credit_limit_minor, p_statement_day,
    p_default_due_day, p_last_four_digits, coalesce(p_reminder_lead_days, 3),
    coalesce(p_facility_status, 'active'),
    coalesce(p_min_payment_method, 'full'),
    p_min_payment_fixed_minor, p_min_payment_basis_points, v_color,
    p_fx_markup_basis_points
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
    color_hex = excluded.color_hex,
    fx_markup_basis_points = excluded.fx_markup_basis_points;

  return v_account_id;
end;
$$;

comment on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text, integer
) is
  'Creates or updates a liability account together with its facility '
  'settings, including its flat foreign-exchange markup rate.';

revoke execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text, integer
) from public, anon;
grant execute on function app_finance.save_credit_facility(
  text, app_finance.account_type, text, bigint, smallint, smallint, text,
  smallint, text, uuid, app_finance.facility_status,
  app_finance.min_payment_method, bigint, integer, text, integer
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- charge_liability_account gains the switch: when flagged as foreign
-- currency on a credit card with a configured rate, a second expense for
-- the markup posts atomically alongside the purchase, into the same
-- statement cycle. Any other combination (BNPL, no rate configured, or the
-- switch left off) behaves exactly as before.
-- ---------------------------------------------------------------------------

drop function if exists app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid
);

create function app_finance.charge_liability_account(
  p_account_id uuid,
  p_title text,
  p_category_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_notes text default null,
  p_charge_id uuid default null,
  p_is_foreign_currency boolean default false
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account record;
  v_settings record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_markup_tx_id uuid;
  v_markup_minor bigint := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  -- Client-generated ids make a retried save idempotent.
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

  select a.id, a.currency_code, a.account_type into v_account
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id
    for update;
  if v_account is null
    or app_finance.account_role(v_account.account_type) <> 'liability' then
    raise exception
      'invalid_account: this flow requires a credit card or BNPL account';
  end if;
  perform app_finance.assert_liability_can_fund(v_user_id, p_account_id);

  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;

  if p_is_foreign_currency and v_account.account_type = 'credit_card'
    and coalesce(v_settings.fx_markup_basis_points, 0) > 0 then
    v_markup_minor := round(
      p_amount_minor::numeric * v_settings.fx_markup_basis_points / 10000
    )::bigint;
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + p_amount_minor + v_markup_minor
    > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  if app_finance.target_statement_is_settled(
    v_user_id, p_account_id, p_occurred_on
  ) then
    raise exception
      'statement_settled: that statement is already paid; use a correction';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    coalesce(p_charge_id, gen_random_uuid()), v_user_id, 'expense',
    p_occurred_on, p_amount_minor, v_account.currency_code, p_account_id,
    p_category_id, p_title, p_notes
  )
  returning id into v_tx_id;

  perform app_finance.relink_card_statement_item(
    v_user_id, v_tx_id, p_account_id, p_occurred_on, p_amount_minor
  );

  if v_markup_minor > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    ) values (
      v_user_id, 'expense', p_occurred_on, v_markup_minor,
      v_account.currency_code, p_account_id, p_category_id,
      'Foreign Exchange Markup'
    )
    returning id into v_markup_tx_id;

    perform app_finance.relink_card_statement_item(
      v_user_id, v_markup_tx_id, p_account_id, p_occurred_on, v_markup_minor
    );
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

comment on function app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid, boolean
) is
  'One ordinary credit-card or BNPL expense: a single liability-backed '
  'expense that raises outstanding once and joins the card statement '
  'cycle. When flagged foreign currency on a credit card with a '
  'configured fx_markup_basis_points, a second expense for the flat '
  'markup posts atomically alongside it.';

revoke execute on function app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid, boolean
) from public, anon;
grant execute on function app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid, boolean
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The rate travels with the facility summary
-- ---------------------------------------------------------------------------

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
    s.color_hex,
    s.fx_markup_basis_points
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
