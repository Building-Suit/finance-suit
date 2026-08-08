-- The flat FX markup (20260816090400) could only be created alongside a
-- brand-new purchase. This closes the loop: editing an existing expense can
-- now flip the "in foreign currency?" switch on or off, creating or
-- removing the markup transaction to match — and, symmetrically, deleting
-- the purchase always takes its markup with it, and the markup transaction
-- itself is never independently editable, exactly like a rule-generated fee.
--
-- This needs a durable link between a purchase and its markup, which
-- 20260816090400 never recorded — `charge_liability_account` just inserted
-- a second bare expense with no way back to the purchase it followed.

-- ---------------------------------------------------------------------------
-- The link: one row per (purchase, markup) pair, rate snapshotted at
-- creation so a later change to the card's rate never rewrites history.
-- ---------------------------------------------------------------------------

create table if not exists app_finance.credit_card_fx_markup_charges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  purchase_transaction_id uuid not null,
  markup_transaction_id uuid not null,
  basis_points integer not null check (basis_points > 0),
  created_at timestamptz not null default now(),
  constraint fx_markup_charges_owner_unique unique (id, user_id),
  constraint fx_markup_charges_purchase_unique unique (purchase_transaction_id),
  constraint fx_markup_charges_markup_unique unique (markup_transaction_id),
  constraint fx_markup_charges_purchase_owner_fk
    foreign key (purchase_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade,
  constraint fx_markup_charges_markup_owner_fk
    foreign key (markup_transaction_id, user_id)
    references app_finance.financial_transactions (id, user_id)
    on delete cascade
);

create index if not exists idx_fx_markup_charges_purchase
  on app_finance.credit_card_fx_markup_charges (purchase_transaction_id, user_id);

comment on table app_finance.credit_card_fx_markup_charges is
  'Links one flat-rate FX markup expense to the purchase that generated '
  'it. Independent of credit_card_fee_charges, which only tracks the '
  'versioned rules engine''s own generated charges.';

alter table app_finance.credit_card_fx_markup_charges enable row level security;
drop policy if exists fx_markup_charges_select
  on app_finance.credit_card_fx_markup_charges;
create policy fx_markup_charges_select
  on app_finance.credit_card_fx_markup_charges
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists fx_markup_charges_insert
  on app_finance.credit_card_fx_markup_charges;
create policy fx_markup_charges_insert
  on app_finance.credit_card_fx_markup_charges
  for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists fx_markup_charges_update
  on app_finance.credit_card_fx_markup_charges;
create policy fx_markup_charges_update
  on app_finance.credit_card_fx_markup_charges
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
drop policy if exists fx_markup_charges_delete
  on app_finance.credit_card_fx_markup_charges;
create policy fx_markup_charges_delete
  on app_finance.credit_card_fx_markup_charges
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- charge_liability_account records the link when it creates a markup.
-- Same signature, same behavior otherwise — see 20260816090400 for the
-- unchanged parts of this function.
-- ---------------------------------------------------------------------------

create or replace function app_finance.charge_liability_account(
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

    insert into app_finance.credit_card_fx_markup_charges (
      user_id, purchase_transaction_id, markup_transaction_id, basis_points
    ) values (
      v_user_id, v_tx_id, v_markup_tx_id, v_settings.fx_markup_basis_points
    );
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return v_tx_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_expense_transaction learns the switch: create, resync, or remove
-- the markup to match the edit, evaluated fresh against the destination
-- account and current amount every time — never assumed from what was
-- there before.
-- ---------------------------------------------------------------------------

drop function if exists app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text
);

create function app_finance.update_expense_transaction(
  p_transaction_id uuid,
  p_account_id uuid,
  p_occurred_on date,
  p_amount_minor bigint,
  p_category_id uuid default null,
  p_counterparty text default null,
  p_title text default null,
  p_notes text default null,
  p_is_foreign_currency boolean default false
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
$$;

comment on function app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text, boolean
) is
  'Canonical role-aware editor for one ordinary transaction: moves it '
  'between asset and liability accounts atomically, rebuilds the '
  'statement linkage, and creates, resyncs, or removes its flat FX '
  'markup to match the current switch, account, and amount.';

revoke execute on function app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text, boolean
) from public, anon;
grant execute on function app_finance.update_expense_transaction(
  uuid, uuid, date, bigint, uuid, text, text, text, boolean
) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- delete_ledger_transaction takes the markup with its purchase, and never
-- lets the markup transaction be deleted on its own.
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
  v_markup_tx_id uuid;
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
  if exists (
    select 1 from app_finance.credit_card_fx_markup_charges m
    where m.markup_transaction_id = p_transaction_id
  ) then
    raise exception
      'fx_markup_locked: this charge follows its purchase; edit the purchase '
      'instead';
  end if;
  if app_finance.charge_statement_is_settled(v_user_id, p_transaction_id) then
    raise exception
      'statement_settled: that statement is already paid; use a correction';
  end if;

  select markup_transaction_id into v_markup_tx_id
    from app_finance.credit_card_fx_markup_charges
    where purchase_transaction_id = p_transaction_id and user_id = v_user_id;

  perform 1 from app_finance.accounts
    where id in (v_tx.source_account_id, v_tx.destination_account_id)
      and user_id = v_user_id
    order by id
    for update;

  perform set_config('app_finance.facility_internal', 'on', true);
  if v_markup_tx_id is not null then
    delete from app_finance.financial_transactions
      where id = v_markup_tx_id and user_id = v_user_id;
  end if;
  delete from app_finance.financial_transactions
    where id = p_transaction_id and user_id = v_user_id;
  perform set_config('app_finance.facility_internal', '', true);
end;
$$;

comment on function app_finance.delete_ledger_transaction(uuid) is
  'Deletes one ordinary transaction on an asset or liability account and '
  'removes its statement linkage and any FX markup that followed it; '
  'system-owned records stay protected.';

notify pgrst, 'reload schema';
