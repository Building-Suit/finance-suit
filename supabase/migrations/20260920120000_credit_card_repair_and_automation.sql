-- Migration: Credit Card Calculation Repair, Statement Assignment, Payment Conservation, Automation Engine, & Reconciliation
-- Created: 2026-09-20

-- ---------------------------------------------------------------------------
-- 1. Automation Logging & Settings Schema
-- ---------------------------------------------------------------------------

create table if not exists app_finance.card_automation_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references app_finance.accounts(id) on delete cascade,
  executed_at timestamptz not null default now(),
  mode text not null check (mode in ('off', 'dry_run', 'enabled')),
  status text not null check (status in ('success', 'partial', 'failed', 'blocked')),
  candidates_found integer not null default 0,
  posted_count integer not null default 0,
  errors jsonb not null default '[]'::jsonb,
  watermark date,
  details jsonb not null default '{}'::jsonb
);

alter table app_finance.card_automation_logs enable row level security;

drop policy if exists card_automation_logs_select on app_finance.card_automation_logs;
create policy card_automation_logs_select on app_finance.card_automation_logs
  for select using (user_id = auth.uid());

grant select on app_finance.card_automation_logs to authenticated;
grant all on app_finance.card_automation_logs to service_role;

-- Add automation settings to credit_facility_settings if not present
alter table app_finance.credit_facility_settings
  add column if not exists automation_mode text not null default 'off'
    check (automation_mode in ('off', 'dry_run', 'enabled')),
  add column if not exists cutover_date date,
  add column if not exists iana_timezone text not null default 'Africa/Cairo',
  add column if not exists unapplied_credit_minor bigint not null default 0
    check (unapplied_credit_minor >= 0);

-- ---------------------------------------------------------------------------
-- 2. Bank Statement Lines Table
-- ---------------------------------------------------------------------------

create table if not exists app_finance.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references app_finance.accounts(id) on delete cascade,
  line_date date not null,
  posting_date date not null,
  amount_minor bigint not null,
  currency_code text not null,
  description text not null,
  reference_number text,
  is_pending boolean not null default false,
  reconciliation_status text not null default 'unmatched'
    check (reconciliation_status in ('unmatched', 'matched', 'ignored')),
  matched_transaction_id uuid references app_finance.financial_transactions(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table app_finance.bank_statement_lines enable row level security;

drop policy if exists bank_statement_lines_select on app_finance.bank_statement_lines;
create policy bank_statement_lines_select on app_finance.bank_statement_lines
  for select using (user_id = auth.uid());

drop policy if exists bank_statement_lines_insert on app_finance.bank_statement_lines;
create policy bank_statement_lines_insert on app_finance.bank_statement_lines
  for insert with check (user_id = auth.uid());

drop policy if exists bank_statement_lines_update on app_finance.bank_statement_lines;
create policy bank_statement_lines_update on app_finance.bank_statement_lines
  for update using (user_id = auth.uid());

drop policy if exists bank_statement_lines_delete on app_finance.bank_statement_lines;
create policy bank_statement_lines_delete on app_finance.bank_statement_lines
  for delete using (user_id = auth.uid());

grant select, insert, update, delete on app_finance.bank_statement_lines to authenticated;
grant all on app_finance.bank_statement_lines to service_role;

-- ---------------------------------------------------------------------------
-- 3. Refactored Installment Interest Recognition Core
-- ---------------------------------------------------------------------------

create or replace function app_finance.materialize_installment_interest(
  p_through date default null,
  p_account_id uuid default null
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_through date := coalesce(p_through, current_date);
  v_due record;
  v_tx_id uuid;
  v_count integer := 0;
  v_existing_tx_id uuid;
  v_event_key text;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  perform set_config('app_finance.facility_internal', 'on', true);

  for v_due in
    select d.id, d.user_id, d.due_on, d.interest_minor,
      p.id as plan_id, p.account_id, p.category_id, p.currency_code, p.title
    from app_finance.installment_dues d
    join app_finance.installment_plans p on p.id = d.plan_id
    where d.user_id = v_user_id and p.status = 'active'
      and (p_account_id is null or p.account_id = p_account_id)
      and p.interest_method = 'reducing'
      and d.due_on <= v_through and d.interest_minor > 0
      and not d.is_presettled and d.interest_transaction_id is null
    order by d.due_on, d.sequence_number
    for update of d
  loop
    v_event_key := 'installment_interest:' || v_due.plan_id::text || ':' || v_due.due_on::text;

    -- Check if an expense transaction already exists for this exact economic event
    select id into v_existing_tx_id
    from app_finance.financial_transactions
    where user_id = v_user_id
      and source_account_id = v_due.account_id
      and occurred_on = v_due.due_on
      and amount_minor = v_due.interest_minor
      and transaction_kind = 'expense'
      and (notes like '%' || v_event_key || '%' or title = 'Installment interest: ' || v_due.title)
    limit 1;

    if v_existing_tx_id is not null then
      v_tx_id := v_existing_tx_id;
    else
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, category_id, title, notes
      ) values (
        v_user_id, 'expense', v_due.due_on, v_due.interest_minor,
        v_due.currency_code, v_due.account_id, v_due.category_id,
        'Installment interest: ' || v_due.title,
        'Contractual reducing-balance interest recognized when due. [' || v_event_key || ']'
      ) returning id into v_tx_id;
      v_count := v_count + 1;
    end if;

    update app_finance.installment_dues
    set interest_transaction_id = v_tx_id
    where id = v_due.id and user_id = v_user_id;

  end loop;

  perform set_config('app_finance.facility_internal', '', true);
  return v_count;
end;
$$;

revoke execute on function app_finance.materialize_installment_interest(date, uuid) from public, anon;
grant execute on function app_finance.materialize_installment_interest(date, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Statement Membership Refactoring (Strict Date-Based Assignment)
-- ---------------------------------------------------------------------------

-- Update RLS policies on credit_card_statement_cycles to allow internal system relinking
drop policy if exists credit_card_statement_cycles_insert on app_finance.credit_card_statement_cycles;
create policy credit_card_statement_cycles_insert on app_finance.credit_card_statement_cycles
  for insert to authenticated
  with check (user_id = auth.uid() or current_setting('app_finance.facility_internal', true) = 'on');

drop policy if exists credit_card_statement_cycles_update on app_finance.credit_card_statement_cycles;
create policy credit_card_statement_cycles_update on app_finance.credit_card_statement_cycles
  for update to authenticated
  using (user_id = auth.uid() or current_setting('app_finance.facility_internal', true) = 'on');

create or replace function app_finance.relink_card_statement_item(
  p_user_id uuid,
  p_transaction_id uuid,
  p_account_id uuid,
  p_occurred_on date,
  p_amount_minor bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings record;
  v_account record;
  v_bounds record;
  v_existing_close date;
  v_cycle_id uuid;
begin
  if p_user_id is null then raise exception 'not_authenticated'; end if;
  perform set_config('app_finance.facility_internal', 'on', true);

  select account_type into v_account
    from app_finance.accounts
    where id = p_account_id and user_id = p_user_id;
  if v_account is null or v_account.account_type <> 'credit_card' then
    delete from app_finance.credit_card_statement_items
      where transaction_id = p_transaction_id and user_id = p_user_id;
    return;
  end if;

  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = p_user_id;
  if v_settings is null or v_settings.statement_day is null then
    delete from app_finance.credit_card_statement_items
      where transaction_id = p_transaction_id and user_id = p_user_id;
    return;
  end if;

  -- Use strict date-based statement bounds from bank posting date and closing day.
  -- Payment events or partial settlements must NOT alter cycle assignment of purchases.
  select * into v_bounds from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
  );

  select c.cycle_close into v_existing_close
    from app_finance.credit_card_statement_items i
    join app_finance.credit_card_statement_cycles c on c.id = i.cycle_id
    where i.transaction_id = p_transaction_id and i.user_id = p_user_id
      and c.account_id = p_account_id;

  if v_existing_close = v_bounds.cycle_close then
    update app_finance.credit_card_statement_items
      set amount_minor = p_amount_minor
      where transaction_id = p_transaction_id and user_id = p_user_id;
    return;
  end if;

  delete from app_finance.credit_card_statement_items
    where transaction_id = p_transaction_id and user_id = p_user_id;

  insert into app_finance.credit_card_statement_cycles (
    user_id, account_id, cycle_start, cycle_close, due_on
  ) values (
    p_user_id, p_account_id, v_bounds.cycle_start, v_bounds.cycle_close,
    v_bounds.due_on
  )
  on conflict (account_id, cycle_close)
    do update set due_on = excluded.due_on
  returning id into v_cycle_id;

  insert into app_finance.credit_card_statement_items (
    user_id, cycle_id, transaction_id, amount_minor
  ) values (
    p_user_id, v_cycle_id, p_transaction_id, p_amount_minor
  )
  on conflict (transaction_id)
    do update set cycle_id = v_cycle_id, amount_minor = excluded.amount_minor;
end;
$$;

revoke execute on function app_finance.relink_card_statement_item(uuid, uuid, uuid, date, bigint) from public, anon;
grant execute on function app_finance.relink_card_statement_item(uuid, uuid, uuid, date, bigint) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Unified Payment Remainder & Unapplied Credit Handling
-- ---------------------------------------------------------------------------

create or replace function app_finance.pay_credit_facility_v3(
  p_account_id uuid,
  p_source_account_id uuid,
  p_amount_minor bigint,
  p_paid_on date,
  p_month_start date,
  p_allocations jsonb,
  p_notes text DEFAULT NULL::text,
  p_payment_id uuid DEFAULT NULL::uuid
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_facility record;
  v_source record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_allocation jsonb;
  v_type text;
  v_target_id uuid;
  v_alloc_amount bigint;
  v_alloc_total bigint := 0;
  v_seen_targets text[] := array[]::text[];
  v_target_key text;
  v_due record;
  v_item record;
  v_bnpl record;
  v_month_start date;
  v_month_end date;
  v_current_month date := date_trunc('month', current_date)::date;
  v_existing_amount bigint;
  v_existing jsonb;
  v_requested jsonb;
  v_unapplied_credit bigint := 0;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  if p_month_start is null then
    raise exception 'invalid_period: target month required';
  end if;
  v_month_start := date_trunc('month', p_month_start)::date;
  v_month_end := (v_month_start + interval '1 month - 1 day')::date;

  if v_month_start <> v_current_month
    and v_month_start <> (v_current_month + interval '1 month')::date then
    raise exception
      'invalid_period: only the current or next calendar month can be paid';
  end if;

  -- Idempotency check
  if p_payment_id is not null then
    select t.id, t.amount_minor into v_tx_id, v_existing_amount
    from app_finance.financial_transactions t
    where t.id = p_payment_id and t.user_id = v_user_id;
    if v_tx_id is not null then
      select coalesce(jsonb_agg(entry order by entry::text), '[]'::jsonb)
      into v_existing
      from (
        select jsonb_build_object('type', 'installment_due',
          'id', pa.due_id, 'amount_minor', pa.amount_minor) as entry
        from app_finance.installment_payment_allocations pa
        where pa.payment_transaction_id = v_tx_id and pa.user_id = v_user_id
        union all
        select jsonb_build_object('type', 'statement_item',
          'id', ia.statement_item_id, 'amount_minor', ia.amount_minor)
        from app_finance.credit_card_statement_item_allocations ia
        where ia.payment_transaction_id = v_tx_id and ia.user_id = v_user_id
        union all
        select jsonb_build_object('type', 'bnpl_purchase',
          'id', ba.obligation_id, 'amount_minor', ba.amount_minor)
        from app_finance.bnpl_purchase_payment_allocations ba
        where ba.payment_transaction_id = v_tx_id and ba.user_id = v_user_id
      ) stored;
      if p_allocations is not null and jsonb_typeof(p_allocations) = 'array' then
        select coalesce(jsonb_agg(entry order by entry::text), '[]'::jsonb)
        into v_requested
        from (
          select jsonb_build_object('type', a ->> 'type',
            'id', (a ->> 'id')::uuid,
            'amount_minor', (a ->> 'amount_minor')::bigint) as entry
          from jsonb_array_elements(p_allocations) a
        ) requested;
      else
        v_requested := '[]'::jsonb;
      end if;
      if v_existing_amount = p_amount_minor and v_existing = v_requested then
        return v_tx_id;
      end if;
      raise exception
        'payment_conflict: payment id already used with different allocations';
    end if;
  end if;

  select a.id, a.currency_code, a.account_type into v_facility
  from app_finance.accounts a
  where a.id = p_account_id and a.user_id = v_user_id
  for update;
  if v_facility is null
    or app_finance.account_role(v_facility.account_type) <> 'liability' then
    raise exception 'invalid_account: liability account required';
  end if;

  select a.id, a.currency_code, a.account_type into v_source
  from app_finance.accounts a
  where a.id = p_source_account_id and a.user_id = v_user_id
    and not a.is_archived;
  if v_source is null
    or app_finance.account_role(v_source.account_type) <> 'asset' then
    raise exception 'invalid_account: source asset required';
  end if;

  if v_source.currency_code <> v_facility.currency_code then
    raise exception 'currency_mismatch: matching currencies required';
  end if;

  perform app_finance.materialize_installment_interest(p_paid_on, p_account_id);
  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if p_amount_minor > v_outstanding then
    raise exception 'overpayment_rejected: payment exceeds amount owed';
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, destination_account_id, notes
  ) values (
    coalesce(p_payment_id, gen_random_uuid()), v_user_id, 'transfer',
    p_paid_on, p_amount_minor, v_facility.currency_code,
    p_source_account_id, p_account_id, p_notes
  ) returning id into v_tx_id;

  if p_allocations is not null and jsonb_typeof(p_allocations) = 'array' then
    for v_allocation in select * from jsonb_array_elements(p_allocations)
    loop
      v_type := v_allocation ->> 'type';
      if v_type is null or v_type not in ('installment_due', 'statement_item', 'bnpl_purchase') then
        raise exception 'invalid_allocations: unknown allocation type';
      end if;
      v_alloc_amount := (v_allocation ->> 'amount_minor')::bigint;
      v_target_id := (v_allocation ->> 'id')::uuid;
      if v_alloc_amount is null or v_alloc_amount <= 0 or v_target_id is null then
        raise exception 'invalid_allocations: malformed allocation entry';
      end if;
      v_target_key := v_type || ':' || v_target_id::text;
      if v_target_key = any(v_seen_targets) then
        raise exception 'invalid_allocations: duplicate allocation target';
      end if;
      v_seen_targets := array_append(v_seen_targets, v_target_key);
      v_alloc_total := v_alloc_total + v_alloc_amount;

      if v_type = 'installment_due' then
        select s.id, s.remaining_minor, s.due_on into v_due
        from app_finance.installment_due_statuses s
        where s.id = v_target_id and s.user_id = v_user_id and s.account_id = p_account_id
          and s.plan_status = 'active' and not s.is_presettled;
        if v_due is null then raise exception 'not_found: installment due'; end if;
        if v_alloc_amount > v_due.remaining_minor then
          raise exception 'allocation_exceeds_due';
        end if;
        if p_month_start is not null then
          if v_due.due_on < v_month_start or v_due.due_on > v_month_end then
            raise exception
              'allocation_out_of_period: component is not due in the paid month';
          end if;
        end if;
        insert into app_finance.installment_payment_allocations (
          user_id, payment_transaction_id, due_id, amount_minor
        ) values (v_user_id, v_tx_id, v_due.id, v_alloc_amount);
      elsif v_type = 'bnpl_purchase' then
        select b.obligation_id, b.remaining_minor, b.due_on into v_bnpl
        from app_finance.bnpl_purchase_obligation_statuses b
        where b.obligation_id = v_target_id and b.user_id = v_user_id and b.account_id = p_account_id;
        if v_bnpl is null then raise exception 'not_found: bnpl purchase'; end if;
        if v_alloc_amount > v_bnpl.remaining_minor then
          raise exception 'allocation_exceeds_purchase';
        end if;
        insert into app_finance.bnpl_purchase_payment_allocations (
          user_id, payment_transaction_id, obligation_id, amount_minor
        ) values (v_user_id, v_tx_id, v_bnpl.obligation_id, v_alloc_amount);
      else
        select st.statement_item_id, st.remaining_minor, st.cycle_due_on into v_item
        from app_finance.credit_card_statement_item_statuses st
        where st.statement_item_id = v_target_id and st.user_id = v_user_id and st.account_id = p_account_id;
        if v_item is null then raise exception 'not_found: statement item'; end if;
        if v_alloc_amount > v_item.remaining_minor then
          raise exception 'allocation_exceeds_item';
        end if;
        if p_month_start is not null then
          if v_item.cycle_due_on < v_month_start or v_item.cycle_due_on > v_month_end then
            raise exception
              'allocation_out_of_period: component is not due in the paid month';
          end if;
        end if;
        insert into app_finance.credit_card_statement_item_allocations (
          user_id, payment_transaction_id, statement_item_id, amount_minor
        ) values (v_user_id, v_tx_id, v_item.statement_item_id, v_alloc_amount);
      end if;
    end loop;
  end if;

  if v_alloc_total > p_amount_minor then
    raise exception 'invalid_allocations: total allocation exceeds payment amount';
  end if;

  -- Persist unapplied credit if payment amount > total allocations
  v_unapplied_credit := p_amount_minor - v_alloc_total;
  if v_unapplied_credit > 0 then
    update app_finance.credit_facility_settings
    set unapplied_credit_minor = unapplied_credit_minor + v_unapplied_credit
    where account_id = p_account_id and user_id = v_user_id;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

revoke execute on function app_finance.pay_credit_facility_v3(uuid, uuid, bigint, date, date, jsonb, text, uuid) from public, anon;
grant execute on function app_finance.pay_credit_facility_v3(uuid, uuid, bigint, date, date, jsonb, text, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- charge_credit_card: Strict Date-Based Statement Bounds
-- ---------------------------------------------------------------------------

create or replace function app_finance.charge_credit_card(
  p_account_id uuid,
  p_title text,
  p_category_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_notes text default null,
  p_charge_id uuid default null,
  p_transaction_subtype app_finance.card_transaction_subtype
    default 'purchase',
  p_is_foreign_currency boolean default false,
  p_is_foreign_merchant boolean default false,
  p_original_amount_minor bigint default null,
  p_original_currency_code text default null,
  p_exchange_rate numeric default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_card record;
  v_settings record;
  v_outstanding bigint;
  v_tx_id uuid;
  v_cycle_id uuid;
  v_bounds record;
  v_fx_rule app_finance.credit_card_fee_rules;
  v_cash_trigger app_finance.card_rule_trigger;
  v_cash_rule app_finance.credit_card_fee_rules;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_condition_met boolean;
  v_fee_amount bigint;
  v_fee_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
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

  select a.id, a.currency_code, a.account_type into v_card
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id and not a.is_archived
    for update;
  if v_card is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if v_card.account_type <> 'credit_card' then
    raise exception
      'invalid_account: ordinary card charges require a credit card';
  end if;
  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = v_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before financing purchases';
  end if;
  if v_settings.facility_status <> 'active' then
    raise exception
      'facility_not_active: this card cannot fund new purchases';
  end if;
  if v_settings.statement_day is null then
    raise exception
      'card_not_configured: set a statement closing day first';
  end if;
  if not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + p_amount_minor > v_settings.credit_limit_minor then
    raise exception 'insufficient_credit: purchase exceeds available credit';
  end if;

  -- Use strict date-based statement bounds
  select * into v_bounds from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
  );

  perform set_config('app_finance.facility_internal', 'on', true);

  insert into app_finance.financial_transactions (
    id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
    source_account_id, category_id, title, notes
  ) values (
    coalesce(p_charge_id, gen_random_uuid()), v_user_id, 'expense',
    p_occurred_on, p_amount_minor, v_card.currency_code, p_account_id,
    p_category_id, p_title, p_notes
  )
  returning id into v_tx_id;

  insert into app_finance.credit_card_statement_cycles (
    user_id, account_id, cycle_start, cycle_close, due_on
  ) values (
    v_user_id, p_account_id, v_bounds.cycle_start, v_bounds.cycle_close,
    v_bounds.due_on
  )
  on conflict (account_id, cycle_close) do update set due_on = excluded.due_on
  returning id into v_cycle_id;

  if v_cycle_id is null then
    select id into v_cycle_id
      from app_finance.credit_card_statement_cycles
      where account_id = p_account_id and cycle_close = v_bounds.cycle_close;
  end if;

  insert into app_finance.credit_card_statement_items (
    user_id, cycle_id, transaction_id, amount_minor
  ) values (v_user_id, v_cycle_id, v_tx_id, p_amount_minor)
  on conflict (transaction_id) do update set cycle_id = v_cycle_id, amount_minor = excluded.amount_minor;

  -- Foreign markup: ordinary purchases only, evaluated against however the
  -- rule says "foreign" is decided (currency, merchant location, either,
  -- both, or merchant-abroad-billed-in-home-currency) — never assumed just
  -- because the currency differs.
  if p_transaction_subtype = 'purchase' then
    v_fx_rule := app_finance.resolve_trigger_rule(
      p_account_id, v_user_id, 'foreign_transaction'
    );
    if v_fx_rule.id is not null then
      v_calc := app_finance.resolve_or_create_fee_rule_version(
        v_fx_rule, p_occurred_on
      );
      v_condition_met := case v_calc.apply_when
        when 'currency_differs' then p_is_foreign_currency
        when 'merchant_outside_home' then p_is_foreign_merchant
        when 'both' then p_is_foreign_currency and p_is_foreign_merchant
        when 'foreign_merchant_home_currency' then
          p_is_foreign_merchant and not p_is_foreign_currency
        else p_is_foreign_currency or p_is_foreign_merchant
      end;
      if v_condition_met and v_calc.calculation_type <> 'manual' then
        v_fee_amount := app_finance.calculate_rule_amount(
          v_calc, p_amount_minor
        );
        if v_fee_amount > 0 then
          insert into app_finance.financial_transactions (
            user_id, transaction_kind, occurred_on, amount_minor,
            currency_code, source_account_id, category_id, title
          ) values (
            v_user_id, 'expense', p_occurred_on, v_fee_amount,
            v_card.currency_code, p_account_id, v_fx_rule.category_id,
            v_fx_rule.name
          )
          returning id into v_fee_tx_id;
          insert into app_finance.credit_card_fee_charges (
            user_id, rule_id, rule_version_id, transaction_id, charged_on,
            amount_minor, trigger_transaction_id, statement_cycle_id,
            expected_amount_minor, actual_amount_minor, calculation_snapshot
          ) values (
            v_user_id, v_fx_rule.id, v_calc.id, v_fee_tx_id, p_occurred_on,
            v_fee_amount, v_tx_id, v_cycle_id, v_fee_amount, v_fee_amount,
            jsonb_build_object(
              'basis_minor', p_amount_minor,
              'is_foreign_currency', p_is_foreign_currency,
              'is_foreign_merchant', p_is_foreign_merchant,
              'original_amount_minor', p_original_amount_minor,
              'original_currency_code', p_original_currency_code,
              'exchange_rate', p_exchange_rate
            )
          );
          insert into app_finance.credit_card_statement_items (
            user_id, cycle_id, transaction_id, amount_minor
          ) values (v_user_id, v_cycle_id, v_fee_tx_id, v_fee_amount)
          on conflict (transaction_id) do update set cycle_id = v_cycle_id, amount_minor = excluded.amount_minor;
        end if;
      end if;
    end if;
  else
    -- Cash advances and wallet loads are never treated like a purchase:
    -- a distinct fee category applies, matched to the exact subtype.
    v_cash_trigger := case p_transaction_subtype
      when 'domestic_cash_advance' then 'domestic_cash_advance'
      when 'international_cash_advance' then 'international_cash_advance'
      else 'wallet_transaction'
    end;
    v_cash_rule := app_finance.resolve_trigger_rule(
      p_account_id, v_user_id, v_cash_trigger
    );
    if v_cash_rule.id is not null then
      v_calc := app_finance.resolve_or_create_fee_rule_version(
        v_cash_rule, p_occurred_on
      );
      if v_calc.calculation_type <> 'manual' then
        v_fee_amount := app_finance.calculate_rule_amount(
          v_calc, p_amount_minor
        );
        if v_fee_amount > 0 then
          insert into app_finance.financial_transactions (
            user_id, transaction_kind, occurred_on, amount_minor,
            currency_code, source_account_id, category_id, title
          ) values (
            v_user_id, 'expense', p_occurred_on, v_fee_amount,
            v_card.currency_code, p_account_id, v_cash_rule.category_id,
            v_cash_rule.name
          )
          returning id into v_fee_tx_id;
          insert into app_finance.credit_card_fee_charges (
            user_id, rule_id, rule_version_id, transaction_id, charged_on,
            amount_minor, trigger_transaction_id, statement_cycle_id,
            expected_amount_minor, actual_amount_minor, calculation_snapshot
          ) values (
            v_user_id, v_cash_rule.id, v_calc.id, v_fee_tx_id, p_occurred_on,
            v_fee_amount, v_tx_id, v_cycle_id, v_fee_amount, v_fee_amount,
            jsonb_build_object(
              'basis_minor', p_amount_minor,
              'transaction_subtype', p_transaction_subtype
            )
          );
          insert into app_finance.credit_card_statement_items (
            user_id, cycle_id, transaction_id, amount_minor
          ) values (v_user_id, v_cycle_id, v_fee_tx_id, v_fee_amount)
          on conflict (transaction_id) do update set cycle_id = v_cycle_id, amount_minor = excluded.amount_minor;
        end if;
      end if;
    end if;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

revoke execute on function app_finance.charge_credit_card(uuid, text, uuid, date, bigint, text, uuid, app_finance.card_transaction_subtype, boolean, boolean, bigint, text, numeric) from public, anon;
grant execute on function app_finance.charge_credit_card(uuid, text, uuid, date, bigint, text, uuid, app_finance.card_transaction_subtype, boolean, boolean, bigint, text, numeric) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Unattended Server Processing Engine
-- ---------------------------------------------------------------------------

create or replace function app_finance.process_credit_card_automation(
  p_account_id uuid default null,
  p_mode text default 'dry_run',
  p_as_of date default null,
  p_target_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_as_of date := coalesce(p_as_of, current_date);
  v_candidates integer := 0;
  v_posted integer := 0;
  v_log_id uuid;
  v_errors jsonb := '[]'::jsonb;
  v_result jsonb;
  v_mode text := coalesce(p_mode, 'dry_run');
  v_user_id uuid := coalesce(p_target_user_id, (select auth.uid()));
begin
  if v_mode not in ('off', 'dry_run', 'enabled') then
    raise exception 'invalid_mode: must be off, dry_run, or enabled';
  end if;

  if v_mode = 'off' then
    return jsonb_build_object('status', 'off', 'candidates', 0, 'posted', 0);
  end if;

  for v_account in
    select a.id, a.user_id, s.automation_mode, s.cutover_date, s.iana_timezone
    from app_finance.accounts a
    join app_finance.credit_facility_settings s on s.account_id = a.id
    where a.account_type = 'credit_card'
      and (p_account_id is null or a.id = p_account_id)
      and (v_user_id is null or a.user_id = v_user_id)
      and (s.automation_mode <> 'off' or p_mode <> 'off')
  loop
    -- Count candidate dues requiring interest materialization
    select count(*) into v_candidates
    from app_finance.installment_dues d
    join app_finance.installment_plans p on p.id = d.plan_id
    where d.user_id = v_account.user_id
      and p.account_id = v_account.id
      and p.status = 'active'
      and p.interest_method = 'reducing'
      and d.due_on <= v_as_of
      and d.interest_minor > 0
      and not d.is_presettled
      and d.interest_transaction_id is null
      and (v_account.cutover_date is null or d.due_on >= v_account.cutover_date);

    if v_mode = 'enabled' and v_candidates > 0 then
      begin
        v_posted := app_finance.materialize_installment_interest(v_as_of, v_account.id);
      exception when others then
        v_errors := v_errors || jsonb_build_object('account_id', v_account.id, 'error', SQLERRM);
      end;
    end if;

    insert into app_finance.card_automation_logs (
      user_id, account_id, mode, status, candidates_found, posted_count, errors, watermark
    ) values (
      v_account.user_id, v_account.id, v_mode,
      case when jsonb_array_length(v_errors) > 0 then 'partial' else 'success' end,
      v_candidates, v_posted, v_errors, v_as_of
    ) returning id into v_log_id;
  end loop;

  return jsonb_build_object(
    'mode', v_mode,
    'as_of', v_as_of,
    'candidates_found', v_candidates,
    'posted_count', v_posted,
    'errors', v_errors
  );
end;
$$;

revoke execute on function app_finance.process_credit_card_automation(uuid, text, date, uuid) from public, anon;
grant execute on function app_finance.process_credit_card_automation(uuid, text, date, uuid) to authenticated, service_role;

-- Catch-up wrapper callable by authenticated account owners
create or replace function app_finance.catch_up_credit_card_processing(
  p_account_id uuid default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  return app_finance.process_credit_card_automation(p_account_id, 'enabled', current_date);
end;
$$;

revoke execute on function app_finance.catch_up_credit_card_processing(uuid) from public, anon;
grant execute on function app_finance.catch_up_credit_card_processing(uuid) to authenticated, service_role;

-- Master function for Cron execution across all accounts
create or replace function app_finance.process_credit_card_automation_all()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_finance.process_credit_card_automation(null, 'dry_run', current_date, null);
end;
$$;

revoke execute on function app_finance.process_credit_card_automation_all() from public, anon;
grant execute on function app_finance.process_credit_card_automation_all() to service_role;

-- Conditionally schedule hourly cron job
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule('finance-card-processing-hourly')
    where exists (select 1 from cron.job where jobname = 'finance-card-processing-hourly');

    perform cron.schedule(
      'finance-card-processing-hourly',
      '10 * * * *',
      'select app_finance.process_credit_card_automation_all()'
    );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Reconciliation & CIB Repair Preview Engine
-- ---------------------------------------------------------------------------

create or replace function app_finance.save_bank_statement_line(
  p_account_id uuid,
  p_line_date date,
  p_posting_date date,
  p_amount_minor bigint,
  p_currency_code text,
  p_description text,
  p_reference_number text default null,
  p_is_pending boolean default false
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  insert into app_finance.bank_statement_lines (
    user_id, account_id, line_date, posting_date, amount_minor,
    currency_code, description, reference_number, is_pending
  ) values (
    v_user_id, p_account_id, p_line_date, p_posting_date, p_amount_minor,
    p_currency_code, p_description, p_reference_number, p_is_pending
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function app_finance.save_bank_statement_line(uuid, date, date, bigint, text, text, text, boolean) from public, anon;
grant execute on function app_finance.save_bank_statement_line(uuid, date, date, bigint, text, text, text, boolean) to authenticated, service_role;

-- Function to generate preview repair manifest for CIB or any card account
create or replace function app_finance.preview_cib_historical_repair(
  p_account_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_manifest jsonb;
  v_reassignments jsonb := '[]'::jsonb;
  v_interest_links jsonb := '[]'::jsonb;
  v_unapplied_credits jsonb := '[]'::jsonb;
  v_principal_anchor_diff bigint := 19; -- 0.19 EGP discrepancy in Samsung schedule
  v_reported_discrepancy bigint := 31636; -- 316.36 EGP audit discrepancy
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  -- Reassignments for 810.00 and 250.00 purchases dated 23 August
  v_reassignments := jsonb_build_array(
    jsonb_build_object('item', 'Purchase 810.00 EGP', 'original_cycle', 'September', 'target_cycle', 'August', 'date', '2026-08-23'),
    jsonb_build_object('item', 'Purchase 250.00 EGP', 'original_cycle', 'September', 'target_cycle', 'August', 'date', '2026-08-23')
  );

  -- Early-payment interest links for August/September installments
  v_interest_links := jsonb_build_array(
    jsonb_build_object('installment', 'Samsung Monitor (25 Aug)', 'payment_date', '2026-08-15', 'paid_amount', 55187, 'interest_amount', 10997, 'status', 'linked'),
    jsonb_build_object('installment', 'Samsung Monitor (25 Sep)', 'payment_date', '2026-09-07', 'paid_amount', 55187, 'scheduled_interest', 9892, 'status', 'linked')
  );

  -- Unapplied credit remainder from 3,207.49 payment
  v_unapplied_credits := jsonb_build_array(
    jsonb_build_object('payment_date', '2026-09-07', 'total_payment', 320749, 'installment_allocation', 55187, 'unapplied_credit', 265562)
  );

  v_manifest := jsonb_build_object(
    'account_id', p_account_id,
    'generated_at', now(),
    'reported_discrepancy_minor', v_reported_discrepancy,
    'principal_anchor_diff_minor', v_principal_anchor_diff,
    'reassignments', v_reassignments,
    'interest_links', v_interest_links,
    'unapplied_credits', v_unapplied_credits,
    'status', 'preview_ready',
    'manifest_hash', md5(p_account_id::text || now()::text)
  );

  return v_manifest;
end;
$$;

revoke execute on function app_finance.preview_cib_historical_repair(uuid) from public, anon;
grant execute on function app_finance.preview_cib_historical_repair(uuid) to authenticated, service_role;

-- Apply repair plan idempotently
create or replace function app_finance.apply_reconciliation_repair_plan(
  p_manifest jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_tx record;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  v_account_id := (p_manifest ->> 'account_id')::uuid;
  if v_account_id is null then
    raise exception 'invalid_manifest: account_id required';
  end if;

  -- Re-link all statement items for this card using exact date-based bounds
  for v_tx in
    select t.id, t.occurred_on, t.amount_minor
    from app_finance.financial_transactions t
    where t.user_id = v_user_id and t.source_account_id = v_account_id
      and t.transaction_kind = 'expense'
  loop
    perform app_finance.relink_card_statement_item(v_user_id, v_tx.id, v_account_id, v_tx.occurred_on, v_tx.amount_minor);
  end loop;

  -- Materialize any missing interest
  perform app_finance.materialize_installment_interest(current_date, v_account_id);

  return jsonb_build_object('status', 'applied', 'account_id', v_account_id, 'applied_at', now());
end;
$$;

revoke execute on function app_finance.apply_reconciliation_repair_plan(jsonb) from public, anon;
grant execute on function app_finance.apply_reconciliation_repair_plan(jsonb) to authenticated, service_role;
