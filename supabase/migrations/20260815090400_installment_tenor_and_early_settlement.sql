-- Tenor-specific installment rates and early settlement. A plan resolves
-- and snapshots its rate once at creation (exactly like every other
-- installment field), so a later change to the card's tenor table or
-- early-settlement rule never touches an existing plan's own numbers —
-- the same non-retroactive guarantee the rest of the rules engine gives.

-- ---------------------------------------------------------------------------
-- Tenor rate tiers (card-level defaults; a plan can still override at
-- creation via any of the existing manual pricing methods)
-- ---------------------------------------------------------------------------

create table if not exists app_finance.installment_tenor_rates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  from_months integer not null check (from_months >= 1),
  to_months integer not null check (to_months >= from_months),
  rate_basis_points integer not null check (rate_basis_points >= 0),
  interest_method app_finance.interest_method not null default 'flat',
  rate_period app_finance.interest_rate_period not null default 'monthly',
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenor_rates_owner_unique unique (id, user_id),
  constraint tenor_rates_account_owner_fk foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id) on delete cascade
);

drop trigger if exists trg_tenor_rates_updated_at
  on app_finance.installment_tenor_rates;
create trigger trg_tenor_rates_updated_at
  before update on app_finance.installment_tenor_rates
  for each row execute function app_private.set_updated_at();

create index if not exists idx_tenor_rates_account
  on app_finance.installment_tenor_rates (account_id, user_id, from_months);

alter table app_finance.installment_tenor_rates enable row level security;
drop policy if exists installment_tenor_rates_select
  on app_finance.installment_tenor_rates;
create policy installment_tenor_rates_select
  on app_finance.installment_tenor_rates
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists installment_tenor_rates_insert
  on app_finance.installment_tenor_rates;
create policy installment_tenor_rates_insert
  on app_finance.installment_tenor_rates
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists installment_tenor_rates_update
  on app_finance.installment_tenor_rates;
create policy installment_tenor_rates_update
  on app_finance.installment_tenor_rates
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists installment_tenor_rates_delete
  on app_finance.installment_tenor_rates;
create policy installment_tenor_rates_delete
  on app_finance.installment_tenor_rates
  for delete to authenticated using ((select auth.uid()) = user_id);

-- No overlapping month ranges for the same card (validate: from <= to is
-- already a column check; overlap is a cross-row invariant).
create or replace function app_private.enforce_no_overlapping_tenor_rates()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1 from app_finance.installment_tenor_rates t
    where t.account_id = new.account_id
      and t.id <> new.id
      and t.from_months <= new.to_months
      and t.to_months >= new.from_months
  ) then
    raise exception
      'overlapping_tenor: tenor ranges cannot overlap on the same card';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_no_overlapping_tenor_rates
  on app_finance.installment_tenor_rates;
create trigger trg_enforce_no_overlapping_tenor_rates
  before insert or update on app_finance.installment_tenor_rates
  for each row execute function
    app_private.enforce_no_overlapping_tenor_rates();

create or replace function app_finance.resolve_tenor_rate(
  p_account_id uuid,
  p_user_id uuid,
  p_months integer
)
returns table (
  rate_basis_points integer,
  interest_method app_finance.interest_method,
  rate_period app_finance.interest_rate_period
)
language sql
stable
set search_path = ''
as $$
  select t.rate_basis_points, t.interest_method, t.rate_period
    from app_finance.installment_tenor_rates t
    where t.account_id = p_account_id and t.user_id = p_user_id
      and p_months between t.from_months and t.to_months
    order by t.from_months
    limit 1;
$$;

revoke execute on function app_finance.resolve_tenor_rate(uuid, uuid, integer)
from public, anon;
grant execute on function app_finance.resolve_tenor_rate(uuid, uuid, integer)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- create_installment_plan learns 'card_tenor_default': resolve the tier
-- covering this tenor, then price it exactly like an explicit
-- interest_rate plan. Every other pricing method is untouched.
-- ---------------------------------------------------------------------------

drop function if exists app_finance.create_installment_plan(
  uuid, text, uuid, date, bigint, integer, date, bigint, uuid, bigint,
  bigint, text, uuid, app_finance.plan_pricing_method, bigint, integer,
  app_finance.interest_rate_period, app_finance.interest_method, bigint,
  bigint, date, integer
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
  v_pricing app_finance.plan_pricing_method := p_pricing_method;
  v_rate_bp integer := p_interest_rate_basis_points;
  v_rate_period app_finance.interest_rate_period := p_interest_rate_period;
  v_interest_method app_finance.interest_method := p_interest_method;
  v_tenor record;
  v_financing record;
  v_outstanding bigint;
  v_plan_id uuid;
  v_purchase_tx_id uuid;
  v_down_tx_id uuid;
  v_upfront_tx_id uuid;
  v_base bigint;
  v_remainder bigint;
  v_seq integer;
  v_presettled_count integer;
  v_presettled_minor bigint;
  v_charge_minor bigint;
  v_origin app_finance.plan_origin;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_plan_id is not null then
    select id into v_plan_id
      from app_finance.installment_plans
      where id = p_plan_id and user_id = v_user_id;
    if v_plan_id is not null then
      return v_plan_id;
    end if;
  end if;

  if p_purchase_price_minor is null or p_purchase_price_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if coalesce(p_down_payment_minor, 0) < 0 then
    raise exception 'invalid_amount: down payment cannot be negative';
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
  if coalesce(p_paid_installments, 0) < 0
    or coalesce(p_paid_installments, 0) >= p_installment_count then
    raise exception
      'invalid_paid_count: paid installments must be fewer than the total';
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

  select credit_limit_minor, facility_status into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before financing purchases';
  end if;
  if v_settings.facility_status <> 'active' then
    raise exception 'facility_not_active: this account cannot fund new plans';
  end if;

  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  if v_pricing = 'card_tenor_default' then
    select * into v_tenor from app_finance.resolve_tenor_rate(
      p_account_id, v_user_id, p_installment_count
    );
    if not found then
      raise exception
        'no_tenor_rate: no rate is configured for % months', p_installment_count;
    end if;
    v_pricing := 'interest_rate';
    v_rate_bp := v_tenor.rate_basis_points;
    v_rate_period := v_tenor.rate_period;
    v_interest_method := v_tenor.interest_method;
  end if;

  select * into v_financing from app_finance.resolve_plan_financing(
    v_pricing, p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
    p_installment_count, p_financing_fees_minor, p_total_payable_minor,
    p_monthly_payment_minor, v_rate_bp, v_rate_period, v_interest_method,
    coalesce(p_financed_fees_minor, 0)
  );

  if coalesce(p_down_payment_minor, 0) > 0 then
    if p_down_payment_account_id is null then
      raise exception
        'invalid_account: a down payment needs a funding account';
    end if;
    select a.id, a.currency_code, a.account_type into v_down_account
      from app_finance.accounts a
      where a.id = p_down_payment_account_id and a.user_id = v_user_id
        and not a.is_archived;
    if v_down_account is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
    if app_finance.account_role(v_down_account.account_type) <> 'asset' then
      raise exception
        'invalid_account: down payments come from an asset account';
    end if;
    if v_down_account.currency_code <> v_facility.currency_code then
      raise exception
        'currency_mismatch: down payment account must match the facility';
    end if;
  end if;

  v_presettled_count := coalesce(p_paid_installments, 0);
  v_origin := case when v_presettled_count > 0
    then 'historical_import' else 'app' end;

  v_base := v_financing.total_minor / p_installment_count;
  v_remainder := v_financing.total_minor % p_installment_count;
  v_presettled_minor := 0;
  for v_seq in 1..v_presettled_count loop
    v_presettled_minor := v_presettled_minor
      + v_base + case when v_seq <= v_remainder then 1 else 0 end;
  end loop;
  v_charge_minor := v_financing.total_minor - v_presettled_minor;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + v_charge_minor > v_settings.credit_limit_minor then
    raise exception
      'insufficient_credit: purchase exceeds available credit';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    v_user_id, 'expense', p_purchased_on, v_charge_minor,
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
      v_user_id, 'expense', coalesce(p_down_paid_on, p_purchased_on),
      p_upfront_fees_minor, v_facility.currency_code,
      coalesce(p_down_payment_account_id, p_account_id), p_category_id,
      p_title, p_notes
    )
    returning id into v_upfront_tx_id;
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
    p_first_due_on,
    p_installment_count, p_purchase_price_minor,
    coalesce(p_down_payment_minor, 0),
    p_purchase_price_minor - coalesce(p_down_payment_minor, 0),
    v_financing.fees_minor, v_financing.interest_minor,
    v_financing.total_minor, v_facility.currency_code, p_notes, v_pricing,
    v_rate_bp, v_rate_period, v_interest_method, v_origin
  )
  returning id into v_plan_id;

  for v_seq in 1..p_installment_count loop
    insert into app_finance.installment_dues (
      user_id, plan_id, sequence_number, due_on, amount_minor, is_presettled
    ) values (
      v_user_id, v_plan_id, v_seq,
      (p_first_due_on + make_interval(months => v_seq - 1))::date,
      v_base + case when v_seq <= v_remainder then 1 else 0 end,
      v_seq <= v_presettled_count
    );
  end loop;

  perform set_config('app_finance.facility_internal', '', true);

  return v_plan_id;
end;
$$;

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

-- ---------------------------------------------------------------------------
-- Early settlement: pay off a plan's remaining dues in one action and
-- book the settlement fee (if any) exactly once. Never re-appears through
-- future dues because there are no future dues left after this.
-- ---------------------------------------------------------------------------

create or replace function app_finance.settle_installment_plan_early(
  p_plan_id uuid,
  p_source_account_id uuid,
  p_paid_on date,
  p_notes text default null,
  p_payment_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_plan record;
  v_source record;
  v_remaining_minor bigint;
  v_paid_minor bigint;
  v_remaining_principal bigint;
  v_rule app_finance.credit_card_fee_rules;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_basis bigint;
  v_fee bigint := 0;
  v_fee_tx_id uuid;
  v_tx_id uuid;
  v_due record;
  v_left bigint;
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

  select p.id, p.account_id, p.status, p.financed_principal_minor,
      p.total_payable_minor, p.purchase_transaction_id, a.currency_code
    into v_plan
    from app_finance.installment_plans p
    join app_finance.accounts a on a.id = p.account_id
    where p.id = p_plan_id and p.user_id = v_user_id
    for update of p;
  if v_plan is null then
    raise exception 'not_found: installment plan';
  end if;
  if v_plan.status <> 'active' then
    raise exception 'plan_not_active: only an active plan can be settled';
  end if;

  select coalesce(sum(s.remaining_minor), 0), coalesce(sum(s.paid_minor), 0)
    into v_remaining_minor, v_paid_minor
    from app_finance.installment_due_statuses s
    where s.plan_id = p_plan_id;
  if v_remaining_minor <= 0 then
    raise exception 'already_settled: this plan has nothing left to pay';
  end if;

  v_remaining_principal := greatest(
    v_plan.financed_principal_minor - round(
      v_paid_minor::numeric * v_plan.financed_principal_minor
        / v_plan.total_payable_minor
    )::bigint,
    0
  );

  select a.id, a.currency_code, a.account_type into v_source
    from app_finance.accounts a
    where a.id = p_source_account_id and a.user_id = v_user_id
      and not a.is_archived;
  if v_source is null then
    raise exception 'invalid_account: source not found or archived';
  end if;
  if app_finance.account_role(v_source.account_type) <> 'asset' then
    raise exception
      'invalid_account: early settlement is paid from an asset account';
  end if;
  if v_source.currency_code <> v_plan.currency_code then
    raise exception 'currency_mismatch: transfers require matching currencies';
  end if;

  v_rule := app_finance.resolve_trigger_rule(
    v_plan.account_id, v_user_id, 'early_settlement'
  );
  if v_rule.id is not null then
    v_calc := app_finance.resolve_or_create_fee_rule_version(
      v_rule, p_paid_on
    );
    if v_calc.calculation_type <> 'manual' then
      v_basis := case v_calc.percent_basis
        when 'remaining_principal' then v_remaining_principal
        else v_remaining_minor
      end;
      v_fee := app_finance.calculate_rule_amount(v_calc, v_basis);
    end if;
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  if v_fee > 0 then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title
    ) values (
      v_user_id, 'expense', p_paid_on, v_fee, v_plan.currency_code,
      v_plan.account_id, v_rule.category_id, v_rule.name
    )
    returning id into v_fee_tx_id;

    insert into app_finance.credit_card_fee_charges (
      user_id, rule_id, rule_version_id, transaction_id, charged_on,
      amount_minor, trigger_transaction_id, expected_amount_minor,
      actual_amount_minor, calculation_snapshot
    ) values (
      v_user_id, v_rule.id, v_calc.id, v_fee_tx_id, p_paid_on, v_fee,
      v_plan.purchase_transaction_id, v_fee, v_fee,
      jsonb_build_object(
        'basis_minor', v_basis, 'remaining_principal_minor',
        v_remaining_principal, 'remaining_outstanding_minor',
        v_remaining_minor
      )
    );
  end if;

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, notes
  ) values (
    coalesce(p_payment_id, gen_random_uuid()), v_user_id, 'transfer',
    p_paid_on, v_remaining_minor + v_fee, v_plan.currency_code,
    p_source_account_id, v_plan.account_id, p_notes
  )
  returning id into v_tx_id;

  v_left := v_remaining_minor;
  for v_due in
    select s.id, s.remaining_minor
    from app_finance.installment_due_statuses s
    where s.plan_id = p_plan_id and s.remaining_minor > 0
    order by s.due_on, s.sequence_number
  loop
    exit when v_left <= 0;
    v_take := least(v_left, v_due.remaining_minor);
    insert into app_finance.installment_payment_allocations (
      user_id, payment_transaction_id, due_id, amount_minor
    ) values (v_user_id, v_tx_id, v_due.id, v_take);
    v_left := v_left - v_take;
  end loop;

  update app_finance.installment_plans
    set status = 'completed'
    where id = p_plan_id and user_id = v_user_id;

  perform set_config('app_finance.facility_internal', '', true);

  return v_tx_id;
end;
$$;

revoke execute on function app_finance.settle_installment_plan_early(
  uuid, uuid, date, text, uuid
) from public, anon;
grant execute on function app_finance.settle_installment_plan_early(
  uuid, uuid, date, text, uuid
) to authenticated, service_role;

notify pgrst, 'reload schema';
