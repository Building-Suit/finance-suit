-- Ordinary expenses on liability accounts (credit cards and BNPL) and the
-- canonical, role-aware editor for them.
--
-- Until now an ordinary expense could only be *created* on a credit card
-- (charge_credit_card) and could never be edited: the generic editor writes
-- app_finance.financial_transactions directly and the
-- protect_facility_transactions guard rail rejects every client write that
-- touches a liability account. BNPL had no ordinary-expense path at all.
--
-- This migration adds three forward-only RPCs that own the whole lifecycle
-- of an ordinary (non-installment, non-fee, non-repayment) expense:
--
--   charge_liability_account   -- create one liability-backed expense
--   update_expense_transaction -- edit one expense across every account role
--   delete_ledger_transaction  -- delete one ordinary row of any account role
--
-- It also adds app_finance.facility_activity_items, the single server-side
-- classification of what each row in a facility's Related activity list
-- actually is, so the client never has to guess which editor to open.
--
-- The accounting model is unchanged. An expense is one row in
-- financial_transactions on its business date. On a liability account it
-- raises outstanding (opening + charges - repayments) exactly once. On a
-- credit card it also joins exactly one statement cycle through
-- credit_card_statement_items, which is what produces the payment
-- obligation; closing a cycle never books a second expense. BNPL keeps its
-- current product model: an ordinary BNPL expense raises outstanding and
-- never silently creates an installment plan, and BNPL obligations continue
-- to come from explicit installment plans.
--
-- Everything runs inside the single transaction of the RPC with the
-- transaction row and both affected accounts locked, so a cross-account
-- move can never leave partial state.

-- ---------------------------------------------------------------------------
-- Statement-cycle membership of one card charge
-- ---------------------------------------------------------------------------

-- Recomputes which statement cycle a charge belongs to. Removes any current
-- membership, then re-adds it when the account is a configured credit card.
-- BNPL and asset accounts simply end up with no statement item.
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
  v_cycle_id uuid;
begin
  delete from app_finance.credit_card_statement_items
    where transaction_id = p_transaction_id and user_id = p_user_id;

  select account_type into v_account
    from app_finance.accounts
    where id = p_account_id and user_id = p_user_id;
  if v_account is null or v_account.account_type <> 'credit_card' then
    return;
  end if;

  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = p_user_id;
  if v_settings is null or v_settings.statement_day is null then
    return;
  end if;

  select * into v_bounds from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
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
  'Recomputes the statement-cycle membership of one ordinary card charge.';

-- True when the statement cycle a charge currently sits in has already
-- received a payment allocation: settled history is corrected through the
-- payment reversal flow, never by mutating the charge in place.
create or replace function app_finance.charge_statement_is_settled(
  p_user_id uuid,
  p_transaction_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from app_finance.credit_card_statement_items i
    join app_finance.credit_card_statement_allocations al
      on al.cycle_id = i.cycle_id
    where i.transaction_id = p_transaction_id and i.user_id = p_user_id
  );
$$;

-- True when the cycle a charge would move into has already been paid into.
create or replace function app_finance.target_statement_is_settled(
  p_user_id uuid,
  p_account_id uuid,
  p_occurred_on date
)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_settings record;
  v_account record;
  v_bounds record;
begin
  select account_type into v_account
    from app_finance.accounts
    where id = p_account_id and user_id = p_user_id;
  if v_account is null or v_account.account_type <> 'credit_card' then
    return false;
  end if;
  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = p_user_id;
  if v_settings is null or v_settings.statement_day is null then
    return false;
  end if;
  select * into v_bounds from app_finance.statement_bounds_for(
    v_settings.statement_day, v_settings.default_due_day, p_occurred_on
  );
  return exists (
    select 1
    from app_finance.credit_card_statement_cycles c
    join app_finance.credit_card_statement_allocations al on al.cycle_id = c.id
    where c.account_id = p_account_id and c.cycle_close = v_bounds.cycle_close
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared eligibility check for a liability account funding an expense
-- ---------------------------------------------------------------------------

-- Raises the coded error the client renders when the account cannot take a
-- new ordinary charge. Callers hold the account row lock already.
create or replace function app_finance.assert_liability_can_fund(
  p_user_id uuid,
  p_account_id uuid
)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_account record;
  v_settings record;
begin
  select account_type, is_archived into v_account
    from app_finance.accounts
    where id = p_account_id and user_id = p_user_id;
  if v_account is null then
    raise exception 'invalid_account: account not found';
  end if;
  if v_account.is_archived then
    raise exception 'account_archived: cannot write to an archived account';
  end if;
  select * into v_settings
    from app_finance.credit_facility_settings
    where account_id = p_account_id and user_id = p_user_id;
  if v_settings is null then
    raise exception
      'facility_not_configured: set a credit limit before charging this account';
  end if;
  if v_settings.facility_status <> 'active' then
    raise exception
      'facility_not_active: this facility cannot fund new purchases';
  end if;
  if v_account.account_type = 'credit_card'
    and v_settings.statement_day is null then
    raise exception 'card_not_configured: set a statement closing day first';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Create one ordinary liability-backed expense (credit card or BNPL)
-- ---------------------------------------------------------------------------

-- The generalization of charge_credit_card: one expense on the purchase
-- date that raises the facility's outstanding amount exactly once. A credit
-- card charge also joins its statement cycle; a BNPL charge does not create
-- an installment plan and never will implicitly.
create or replace function app_finance.charge_liability_account(
  p_account_id uuid,
  p_title text,
  p_category_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_notes text default null,
  p_charge_id uuid default null
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
  v_outstanding := app_finance.facility_outstanding_minor(p_account_id);
  if v_outstanding + p_amount_minor > v_settings.credit_limit_minor then
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

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

comment on function app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid
) is
  'One ordinary credit-card or BNPL expense: a single liability-backed '
  'expense that raises outstanding once and joins the card statement cycle.';

-- ---------------------------------------------------------------------------
-- The canonical role-aware expense editor
-- ---------------------------------------------------------------------------

-- Edits one ordinary transaction and moves it between accounts of any role
-- atomically. Supported transitions and their effects:
--
--   asset  -> asset       old balance effect reversed, new one applied
--   asset  -> liability   balance effect removed, destination outstanding up,
--                         card statement linkage created
--   liability -> asset    charge and statement linkage removed, old
--                         outstanding down, balance effect applied
--   liability -> liability  linkage rebuilt on the destination facility
--   same account          only the monetary delta and the cycle membership
--                         are re-evaluated
--
-- The expense row is preserved throughout: exactly one expense exists before
-- and after, so reports and history never double count.
create or replace function app_finance.update_expense_transaction(
  p_transaction_id uuid,
  p_account_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_category_id uuid default null,
  p_counterparty text default null,
  p_title text default null,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
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

  -- Settled statement history is corrected, never mutated: neither the
  -- cycle the charge leaves nor the cycle it would join may already carry a
  -- payment. Renaming or recategorizing a settled charge stays allowed.
  if v_monetary_change then
    if app_finance.charge_statement_is_settled(v_user_id, p_transaction_id)
      or app_finance.target_statement_is_settled(
        v_user_id, p_account_id, p_occurred_on
      ) then
      raise exception
        'statement_settled: that statement is already paid; use a correction';
    end if;
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

  perform set_config('app_finance.facility_internal', '', true);
  return p_transaction_id;
end;
$$;

comment on function app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text
) is
  'Canonical role-aware editor for one ordinary transaction: moves it '
  'between asset and liability accounts atomically and rebuilds the '
  'statement linkage without ever duplicating the expense.';

-- ---------------------------------------------------------------------------
-- Delete one ordinary transaction of any account role
-- ---------------------------------------------------------------------------

create or replace function app_finance.delete_ledger_transaction(
  p_transaction_id uuid
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_tx record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_tx
    from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id
    for update;
  if v_tx is null then
    raise exception 'not_found: transaction';
  end if;
  if v_tx.transaction_kind = 'salary_income' then
    raise exception 'invalid_kind: this record is edited from its own flow';
  end if;
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
  if app_finance.charge_statement_is_settled(v_user_id, p_transaction_id) then
    raise exception
      'statement_settled: that statement is already paid; use a correction';
  end if;

  perform 1 from app_finance.accounts
    where id in (v_tx.source_account_id, v_tx.destination_account_id)
      and user_id = v_user_id
    order by id
    for update;

  perform set_config('app_finance.facility_internal', 'on', true);
  delete from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id;
  perform set_config('app_finance.facility_internal', '', true);
end;
$$;

comment on function app_finance.delete_ledger_transaction(uuid) is
  'Deletes one ordinary transaction on an asset or liability account and '
  'removes its statement linkage; system-owned records stay protected.';

-- ---------------------------------------------------------------------------
-- Related activity: one server-side classification per ledger row
-- ---------------------------------------------------------------------------

-- Every transaction touching a liability account, labelled with what it
-- really is. The Related activity list routes each row to its own editor
-- from `activity_kind` alone, so the capability decision lives here instead
-- of being re-derived in widgets.
create or replace view app_finance.facility_activity_items
with (security_invoker = on) as
  select
    t.id as transaction_id,
    t.user_id,
    a.id as account_id,
    t.transaction_kind,
    t.occurred_on,
    t.amount_minor,
    t.currency_code,
    t.category_id,
    t.title,
    t.notes,
    t.counterparty,
    t.sort_at,
    coalesce(purchase.id, down.id) as plan_id,
    case
      when t.facility_reversal_of_id is not null then 'repayment_reversal'
      when purchase.id is not null then 'installment_purchase'
      when down.id is not null then 'installment_down_payment'
      when fee.transaction_id is not null then 'fee_charge'
      when t.transaction_kind = 'transfer'
        and t.destination_account_id = a.id then 'facility_repayment'
      when t.transaction_kind = 'transfer' then 'repayment_reversal'
      when t.transaction_kind = 'expense' then 'ordinary_expense'
      else 'other'
    end as activity_kind,
    exists (
      select 1
      from app_finance.credit_card_statement_items i
      join app_finance.credit_card_statement_allocations al
        on al.cycle_id = i.cycle_id
      where i.transaction_id = t.id
    ) as is_settled
  from app_finance.financial_transactions t
  join app_finance.accounts a
    on a.id in (t.source_account_id, t.destination_account_id)
      and a.user_id = t.user_id
  left join app_finance.installment_plans purchase
    on purchase.purchase_transaction_id = t.id
  left join app_finance.installment_plans down
    on down.down_payment_transaction_id = t.id
  left join app_finance.credit_card_fee_charges fee
    on fee.transaction_id = t.id
  where app_finance.account_role(a.account_type) = 'liability';

comment on view app_finance.facility_activity_items is
  'Ledger rows of every credit facility, classified so the client can open '
  'the correct editor for each kind of activity.';

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

revoke execute on function app_finance.relink_card_statement_item(
  uuid, uuid, uuid, date, bigint
) from public, anon;
grant execute on function app_finance.relink_card_statement_item(
  uuid, uuid, uuid, date, bigint
) to authenticated, service_role;

revoke execute on function app_finance.charge_statement_is_settled(uuid, uuid)
from public, anon;
grant execute on function app_finance.charge_statement_is_settled(uuid, uuid)
to authenticated, service_role;

revoke execute on function app_finance.target_statement_is_settled(
  uuid, uuid, date
) from public, anon;
grant execute on function app_finance.target_statement_is_settled(
  uuid, uuid, date
) to authenticated, service_role;

revoke execute on function app_finance.assert_liability_can_fund(uuid, uuid)
from public, anon;
grant execute on function app_finance.assert_liability_can_fund(uuid, uuid)
to authenticated, service_role;

revoke execute on function app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid
) from public, anon;
grant execute on function app_finance.charge_liability_account(
  uuid, text, uuid, date, bigint, text, uuid
) to authenticated, service_role;

revoke execute on function app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text
) from public, anon;
grant execute on function app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text
) to authenticated, service_role;

revoke execute on function app_finance.delete_ledger_transaction(uuid)
from public, anon;
grant execute on function app_finance.delete_ledger_transaction(uuid)
to authenticated, service_role;

notify pgrst, 'reload schema';
