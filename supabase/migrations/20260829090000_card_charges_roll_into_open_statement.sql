-- Card purchases are bookable at any time: a charge whose business date
-- falls inside a statement cycle that has already received a payment rolls
-- forward onto the next unpaid statement instead of being rejected.
--
-- Until now every create/edit path guarded with target_statement_is_settled
-- and raised `statement_settled` the moment the date-derived cycle carried
-- any payment allocation. That guard was too coarse: paying a statement
-- (fully, partially, or early) froze the whole cycle, so an ordinary "log
-- this old bill" save was refused with "that statement is already paid".
-- Real card behavior is the opposite — money that arrives after the payment
-- simply appears on the next statement.
--
-- The paid history itself stays immutable: a settled cycle never gains or
-- loses items (its remaining amount can only move through the payment
-- reversal flow), because new charges now skip past settled cycles instead
-- of joining them. Editing or deleting a charge that already sits on a
-- settled cycle keeps raising `statement_settled`
-- (charge_statement_is_settled) — that really is a correction.
--
-- target_statement_is_settled keeps its definition for older clients but no
-- server path raises from it anymore.

-- ---------------------------------------------------------------------------
-- 1. Statement bounds that skip settled cycles
-- ---------------------------------------------------------------------------

create or replace function app_finance.open_statement_bounds_for(
  p_user_id uuid,
  p_account_id uuid,
  p_statement_day integer,
  p_due_day integer,
  p_occurred_on date
)
returns table (cycle_start date, cycle_close date, due_on date)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_bounds record;
  v_guard integer := 0;
begin
  select * into v_bounds from app_finance.statement_bounds_for(
    p_statement_day, p_due_day, p_occurred_on
  );
  -- A cycle that has received any payment is settled history: roll the
  -- charge into the following cycle until one without a payment is found.
  -- Each step advances at least a month, so the loop ends at the first
  -- cycle the user has not paid into (usually the very next one).
  while exists (
    select 1
    from app_finance.credit_card_statement_cycles c
    join app_finance.credit_card_statement_allocations al on al.cycle_id = c.id
    where c.account_id = p_account_id
      and c.user_id = p_user_id
      and c.cycle_close = v_bounds.cycle_close
  ) loop
    v_guard := v_guard + 1;
    if v_guard > 600 then
      raise exception
        'statement_roll_overflow: no open statement cycle within 50 years';
    end if;
    select * into v_bounds from app_finance.statement_bounds_for(
      p_statement_day, p_due_day, (v_bounds.cycle_close + 1)::date
    );
  end loop;
  return query select v_bounds.cycle_start, v_bounds.cycle_close,
    v_bounds.due_on;
end;
$$;

comment on function app_finance.open_statement_bounds_for(
  uuid, uuid, integer, integer, date
) is
  'Statement bounds for a new card charge: the cycle covering the business '
  'date, rolled forward past every cycle that already carries a payment '
  'allocation, so paid statements never change and the charge lands on the '
  'next unpaid one.';

revoke execute on function app_finance.open_statement_bounds_for(
  uuid, uuid, integer, integer, date
) from public, anon;
grant execute on function app_finance.open_statement_bounds_for(
  uuid, uuid, integer, integer, date
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Statement membership rolls past settled cycles
-- ---------------------------------------------------------------------------

create or replace function app_finance.relink_card_statement_item(
  p_user_id uuid,
  p_transaction_id uuid,
  p_account_id uuid,
  p_occurred_on date,
  p_amount_minor bigint
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_settings record;
  v_account record;
  v_bounds record;
  v_base record;
  v_existing_close date;
  v_cycle_id uuid;
begin
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

  -- A charge that already sits on the statement its date bills to keeps that
  -- membership even if the statement was paid meanwhile: it was legitimately
  -- billed there, and a non-monetary edit (rename, recategorize) must never
  -- silently move history. Only a charge newly landing on a cycle skips
  -- settled ones.
  select * into v_base from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
  );
  select c.cycle_close into v_existing_close
    from app_finance.credit_card_statement_items i
    join app_finance.credit_card_statement_cycles c on c.id = i.cycle_id
    where i.transaction_id = p_transaction_id and i.user_id = p_user_id
      and c.account_id = p_account_id;
  if v_existing_close = v_base.cycle_close then
    update app_finance.credit_card_statement_items
      set amount_minor = p_amount_minor
      where transaction_id = p_transaction_id and user_id = p_user_id;
    return;
  end if;

  delete from app_finance.credit_card_statement_items
    where transaction_id = p_transaction_id and user_id = p_user_id;

  select * into v_bounds from app_finance.open_statement_bounds_for(
    p_user_id, p_account_id, v_settings.statement_day,
    v_settings.default_due_day, p_occurred_on
  );

  insert into app_finance.credit_card_statement_cycles (
    user_id, account_id, cycle_start, cycle_close, due_on
  ) values (
    p_user_id, p_account_id, v_bounds.cycle_start, v_bounds.cycle_close,
    v_bounds.due_on
  )
  on conflict (account_id, cycle_close) do nothing;

  select id into v_cycle_id
    from app_finance.credit_card_statement_cycles
    where account_id = p_account_id and cycle_close = v_bounds.cycle_close;

  insert into app_finance.credit_card_statement_items (
    user_id, cycle_id, transaction_id, amount_minor
  ) values (p_user_id, v_cycle_id, p_transaction_id, p_amount_minor);
end;
$$;

comment on function app_finance.relink_card_statement_item(
  uuid, uuid, uuid, date, bigint
) is
  'Recomputes the statement-cycle membership of one ordinary card charge, '
  'rolling forward past cycles that already received a payment.';

-- ---------------------------------------------------------------------------
-- 3. Creating a liability expense never refuses a paid statement
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app_finance.charge_liability_account(p_account_id uuid, p_title text, p_category_id uuid, p_occurred_on date, p_amount_minor bigint, p_notes text DEFAULT NULL::text, p_charge_id uuid DEFAULT NULL::uuid, p_is_foreign_currency boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

  -- A purchase is bookable at any time. When the cycle covering its date is
  -- already paid, relink_card_statement_item rolls it onto the next unpaid
  -- statement instead of refusing the save.

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
  perform app_finance.relink_bnpl_purchase_obligation(
    v_user_id, v_tx_id, p_account_id, p_occurred_on
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

    insert into app_finance.credit_card_fx_markup_charges (
      user_id, purchase_transaction_id, markup_transaction_id, basis_points
    ) values (
      v_user_id, v_tx_id, v_markup_tx_id, v_settings.fx_markup_basis_points
    );
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Editing an expense: only the cycle the charge already sits on is frozen
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app_finance.update_expense_transaction(p_transaction_id uuid, p_account_id uuid, p_occurred_on date, p_amount_minor bigint, p_category_id uuid DEFAULT NULL::uuid, p_counterparty text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_is_foreign_currency boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := (select auth.uid());
  v_tx record;
  v_old_account_id uuid;
  v_new_account record;
  v_new_role text;
  v_settings record;
  v_outstanding bigint;
  v_is_income boolean;
  v_moved boolean;
  v_monetary_change boolean;
  v_existing_markup record;
  v_fx_rate integer;
  v_new_markup_minor bigint;
  v_old_markup_minor bigint;
  v_markup_tx_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;

  select * into v_tx
    from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id
    for update;
  if v_tx is null then
    raise exception 'not_found: transaction';
  end if;

  -- Transfers and salary payments have their own flows and are never
  -- reachable from the ordinary transaction editor.
  if v_tx.transaction_kind in ('transfer', 'salary_income') then
    raise exception
      'invalid_kind: this record is edited from its own flow';
  end if;

  -- System-owned records keep their specialized editors.
  if v_tx.facility_reversal_of_id is not null
    or exists (
      select 1 from app_finance.installment_payment_allocations pa
      where pa.payment_transaction_id = p_transaction_id
    )
    or exists (
      select 1 from app_finance.credit_card_statement_allocations al
      where al.payment_transaction_id = p_transaction_id
    ) then
    raise exception
      'facility_transaction_locked: correct this from the facility screen';
  end if;
  if exists (
    select 1 from app_finance.installment_plans p
    where p.purchase_transaction_id = p_transaction_id
      or p.down_payment_transaction_id = p_transaction_id
  ) then
    raise exception
      'plan_controlled: edit this purchase from its installment plan';
  end if;
  if exists (
    select 1 from app_finance.credit_card_fee_charges f
    where f.transaction_id = p_transaction_id
  ) then
    raise exception
      'fee_charge_locked: change the fee rule instead of the generated charge';
  end if;
  if exists (
    select 1 from app_finance.credit_card_fx_markup_charges m
    where m.markup_transaction_id = p_transaction_id
  ) then
    raise exception
      'fx_markup_locked: this charge follows its purchase; edit the purchase '
      'instead';
  end if;

  v_is_income := v_tx.transaction_kind in
    ('custom_income', 'freelance_income');
  v_old_account_id := coalesce(
    v_tx.source_account_id, v_tx.destination_account_id
  );

  -- Lock every account involved in a stable order so two concurrent moves
  -- between the same pair can never deadlock.
  perform 1 from app_finance.accounts
    where id in (v_old_account_id, p_account_id) and user_id = v_user_id
    order by id
    for update;

  select a.id, a.account_type, a.currency_code, a.is_archived
    into v_new_account
    from app_finance.accounts a
    where a.id = p_account_id and a.user_id = v_user_id;
  if v_new_account is null then
    raise exception 'invalid_account: account not found';
  end if;
  v_new_role := app_finance.account_role(v_new_account.account_type);
  v_moved := v_old_account_id is distinct from p_account_id;
  v_monetary_change :=
    v_moved
    or v_tx.amount_minor <> p_amount_minor
    or v_tx.occurred_on <> p_occurred_on;

  if v_new_account.currency_code <> v_tx.currency_code then
    raise exception 'currency_mismatch: the account uses another currency';
  end if;

  -- Income never lands on a liability: a card refund or repayment is not
  -- ordinary income and has its own flow.
  if v_new_role = 'liability' and v_tx.transaction_kind <> 'expense' then
    raise exception
      'invalid_kind: only expenses can be charged to a credit facility';
  end if;

  -- A different destination must be eligible today. The account the record
  -- already sits on stays usable so archived or frozen history can still be
  -- corrected in place.
  if v_moved then
    if v_new_account.is_archived then
      raise exception 'account_archived: cannot write to an archived account';
    end if;
    if v_new_role = 'liability' then
      perform app_finance.assert_liability_can_fund(v_user_id, p_account_id);
    end if;
  end if;

  if p_category_id is not null and not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived
  ) then
    raise exception 'invalid_category: category not found';
  end if;
  if v_new_role = 'liability' and not exists (
    select 1 from app_finance.transaction_categories c
    where c.id = p_category_id and c.user_id = v_user_id
      and not c.is_archived and c.category_kind = 'expense'
  ) then
    raise exception 'invalid_category: expense category required';
  end if;

  -- Settled statement history is corrected, never mutated: a charge that
  -- already sits on a paid cycle keeps its statement, so its edit is still
  -- refused. Moving a charge into a paid cycle is no longer refused —
  -- relink_card_statement_item rolls it onto the next unpaid statement.
  -- Renaming or recategorizing a settled charge stays allowed.
  if v_monetary_change
    and app_finance.charge_statement_is_settled(v_user_id, p_transaction_id)
  then
    raise exception
      'statement_settled: that statement is already paid; use a correction';
  end if;

  -- Credit limits are validated against the outstanding amount the edit
  -- would actually produce, with the facility row locked above.
  if v_new_role = 'liability' then
    select * into v_settings
      from app_finance.credit_facility_settings
      where account_id = p_account_id and user_id = v_user_id;
    if v_settings is null then
      raise exception
        'facility_not_configured: set a credit limit before charging this account';
    end if;
    v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
    if not v_moved then
      v_outstanding := v_outstanding - v_tx.amount_minor;
    end if;
    if v_outstanding + p_amount_minor > v_settings.credit_limit_minor then
      raise exception 'insufficient_credit: purchase exceeds available credit';
    end if;
  end if;

  perform set_config('app_finance.facility_internal', 'on', true);

  update app_finance.financial_transactions set
    occurred_on = p_occurred_on,
    amount_minor = p_amount_minor,
    source_account_id = case when v_is_income then null else p_account_id end,
    destination_account_id =
      case when v_is_income then p_account_id else null end,
    category_id = p_category_id,
    counterparty = p_counterparty,
    title = p_title,
    notes = p_notes
  where id = p_transaction_id and user_id = v_user_id;

  -- Rebuilds membership on the destination and drops the old linkage in the
  -- same statement, so no orphaned statement item can survive a move.
  perform app_finance.relink_card_statement_item(
    v_user_id, p_transaction_id, p_account_id, p_occurred_on, p_amount_minor
  );
  -- Recreates, moves, re-dates or drops the BNPL obligation to match the
  -- edited account and date, and refuses to touch a settled one.
  perform app_finance.relink_bnpl_purchase_obligation(
    v_user_id, p_transaction_id, p_account_id, p_occurred_on
  );

  -- The FX markup switch: evaluated fresh against where and what this
  -- transaction is now, never against what it used to be. An expense that
  -- moved off the card, or a card with no configured rate, always ends up
  -- with no markup regardless of the switch.
  select * into v_existing_markup
    from app_finance.credit_card_fx_markup_charges
    where purchase_transaction_id = p_transaction_id and user_id = v_user_id;

  -- Procedural if, not a case expression: v_settings is a bare `record`
  -- that is never assigned at all when v_new_role isn't 'liability' (e.g.
  -- asset-to-asset), and referencing an unassigned record's field fails to
  -- parse even inside a case branch that would never run — the tuple
  -- structure has to be known before any branch of a single expression can
  -- be evaluated. A separate if statement only compiles this branch when
  -- it is actually taken, by which point v_settings is guaranteed set.
  v_fx_rate := 0;
  if v_new_role = 'liability' and v_new_account.account_type = 'credit_card'
  then
    v_fx_rate := coalesce(v_settings.fx_markup_basis_points, 0);
  end if;
  v_new_markup_minor := 0;
  if p_is_foreign_currency and v_fx_rate > 0 then
    v_new_markup_minor :=
      round(p_amount_minor::numeric * v_fx_rate / 10000)::bigint;
  end if;

  if v_new_markup_minor > 0 then
    if v_existing_markup is not null then
      -- The purchase's own credit-limit check above sized only the
      -- purchase's change; a resized markup needs the same check the new
      -- one below gets, against the balance with the *old* markup amount
      -- still in it (the resize below hasn't happened yet).
      select amount_minor into v_old_markup_minor
        from app_finance.financial_transactions
        where id = v_existing_markup.markup_transaction_id
          and user_id = v_user_id;
      v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
      if v_outstanding - v_old_markup_minor + v_new_markup_minor
        > v_settings.credit_limit_minor
      then
        raise exception
          'insufficient_credit: purchase exceeds available credit';
      end if;
      update app_finance.financial_transactions set
        amount_minor = v_new_markup_minor,
        occurred_on = p_occurred_on,
        source_account_id = p_account_id,
        category_id = p_category_id
      where id = v_existing_markup.markup_transaction_id
        and user_id = v_user_id;
      perform app_finance.relink_card_statement_item(
        v_user_id, v_existing_markup.markup_transaction_id, p_account_id,
        p_occurred_on, v_new_markup_minor
      );
      update app_finance.credit_card_fx_markup_charges
        set basis_points = v_fx_rate
        where id = v_existing_markup.id and user_id = v_user_id;
    else
      -- The purchase's own credit-limit check above never accounted for a
      -- markup that didn't exist yet; check again with it included, against
      -- the balance the update above already produced.
      v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
      if v_outstanding + v_new_markup_minor > v_settings.credit_limit_minor
      then
        raise exception
          'insufficient_credit: purchase exceeds available credit';
      end if;
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, category_id, title
      ) values (
        v_user_id, 'expense', p_occurred_on, v_new_markup_minor,
        v_new_account.currency_code, p_account_id, p_category_id,
        'Foreign Exchange Markup'
      )
      returning id into v_markup_tx_id;
      perform app_finance.relink_card_statement_item(
        v_user_id, v_markup_tx_id, p_account_id, p_occurred_on,
        v_new_markup_minor
      );
      insert into app_finance.credit_card_fx_markup_charges (
        user_id, purchase_transaction_id, markup_transaction_id, basis_points
      ) values (
        v_user_id, p_transaction_id, v_markup_tx_id, v_fx_rate
      );
    end if;
  elsif v_existing_markup is not null then
    -- Switched off, or no longer eligible: the markup transaction's
    -- deletion cascades the link row away with it.
    delete from app_finance.financial_transactions
      where id = v_existing_markup.markup_transaction_id
        and user_id = v_user_id;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return p_transaction_id;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. charge_credit_card (recurring card charges) books past paid cycles too
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

  -- Bounds skip cycles that already received a payment, so a charge booked
  -- after its statement was paid lands on the next statement instead of
  -- mutating settled history. Generated fees follow into the same cycle.
  select * into v_bounds from app_finance.open_statement_bounds_for(
    v_user_id, p_account_id, v_settings.statement_day,
    v_settings.default_due_day, p_occurred_on
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
  on conflict (account_id, cycle_close) do nothing;

  select id into v_cycle_id
    from app_finance.credit_card_statement_cycles
    where account_id = p_account_id and cycle_close = v_bounds.cycle_close;

  insert into app_finance.credit_card_statement_items (
    user_id, cycle_id, transaction_id, amount_minor
  ) values (v_user_id, v_cycle_id, v_tx_id, p_amount_minor);

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
          ) values (v_user_id, v_cycle_id, v_fee_tx_id, v_fee_amount);
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
          ) values (v_user_id, v_cycle_id, v_fee_tx_id, v_fee_amount);
        end if;
      end if;
    end if;
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

notify pgrst, 'reload schema';
