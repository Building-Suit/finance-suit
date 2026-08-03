-- Held amounts become fully typed deferred transactions.
--
-- A held amount is exactly a transaction (expense, allowance, or income)
-- that will be booked later: the user now picks the transaction kind and
-- an optional category when creating the hold, and settling books the real
-- transaction on the chosen settlement date with that kind and category.
-- Direction stays as a derived column (outgoing kinds = i_owe, incoming
-- kinds = owed_to_me) so existing consumers keep working.

alter table app_finance.held_amounts
  add column if not exists transaction_kind app_finance.transaction_kind,
  add column if not exists category_id uuid;

update app_finance.held_amounts
set transaction_kind = case direction
  when 'i_owe' then 'expense'::app_finance.transaction_kind
  else 'custom_income'::app_finance.transaction_kind
end
where transaction_kind is null;

alter table app_finance.held_amounts
  alter column transaction_kind set not null;

alter table app_finance.held_amounts
  add constraint held_transaction_kind_allowed check (
    transaction_kind in (
      'expense', 'allowance_given', 'custom_income', 'freelance_income'
    )
  );

alter table app_finance.held_amounts
  add constraint held_kind_matches_direction check (
    (transaction_kind in ('expense', 'allowance_given'))
      = (direction = 'i_owe')
  );

alter table app_finance.held_amounts
  add constraint held_amounts_category_fk
    foreign key (category_id, user_id)
    references app_finance.transaction_categories (id, user_id)
    on delete set null;

create index if not exists idx_held_amounts_category
  on app_finance.held_amounts (category_id)
  where category_id is not null;

-- Replace save_held_amount: the caller provides the transaction kind and
-- category; direction is derived. The old direction-based overload goes
-- away with its grant.
drop function if exists app_finance.save_held_amount(
  app_finance.held_amount_direction, bigint, text, text, date, text, text,
  uuid, uuid, uuid
);

create function app_finance.save_held_amount(
  p_transaction_kind app_finance.transaction_kind,
  p_amount_minor bigint,
  p_currency_code text,
  p_counterparty text,
  p_held_on date,
  p_title text default null,
  p_notes text default null,
  p_account_id uuid default null,
  p_category_id uuid default null,
  p_transaction_id uuid default null,
  p_held_id uuid default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_held app_finance.held_amounts%rowtype;
  v_account app_finance.accounts%rowtype;
  v_held_id uuid;
  v_linked_transaction_id uuid := p_transaction_id;
  v_settlement_transaction_id uuid;
  v_direction app_finance.held_amount_direction;
  v_outgoing boolean;
  v_category_kind app_finance.category_kind;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor <= 0 then raise exception 'invalid_amount: amount must be positive'; end if;
  if p_transaction_kind not in ('expense', 'allowance_given', 'custom_income', 'freelance_income') then
    raise exception 'invalid_kind: held amounts support expense, allowance, and income kinds';
  end if;

  v_outgoing := p_transaction_kind in ('expense', 'allowance_given');
  v_direction := case when v_outgoing
    then 'i_owe'::app_finance.held_amount_direction
    else 'owed_to_me'::app_finance.held_amount_direction
  end;

  if p_category_id is not null then
    select category_kind into v_category_kind
    from app_finance.transaction_categories
    where id = p_category_id and user_id = v_user_id and not is_archived;
    if v_category_kind is null then
      raise exception 'not_found: category';
    end if;
    if v_category_kind <> case p_transaction_kind
      when 'expense' then 'expense'::app_finance.category_kind
      when 'allowance_given' then 'allowance'::app_finance.category_kind
      else 'income'::app_finance.category_kind
    end then
      raise exception 'invalid_category: category kind does not match transaction kind';
    end if;
  end if;

  if p_held_id is not null then
    select * into v_held
    from app_finance.held_amounts
    where id = p_held_id and user_id = v_user_id
    for update;
    if v_held is null then raise exception 'not_found: held amount'; end if;
    v_linked_transaction_id := coalesce(v_held.linked_transaction_id, case when not v_held.manages_transaction then v_held.transaction_id end);
    v_settlement_transaction_id := coalesce(v_held.settlement_transaction_id, case when v_held.manages_transaction then v_held.transaction_id end);
  end if;

  select * into v_account
  from app_finance.accounts
  where id = p_account_id and user_id = v_user_id and not is_archived;
  if v_account is null then raise exception 'invalid_account: account not found or archived'; end if;
  if v_account.currency_code <> p_currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  if v_linked_transaction_id is not null then
    perform 1 from app_finance.financial_transactions
    where id = v_linked_transaction_id and user_id = v_user_id;
    if not found then raise exception 'not_found: linked transaction'; end if;
  end if;

  if p_held_id is not null and v_held.settled_on is not null then
    if v_settlement_transaction_id is null then
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, destination_account_id, category_id,
        counterparty, title, notes
      ) values (
        v_user_id, p_transaction_kind, v_held.settled_on, p_amount_minor, p_currency_code,
        case when v_outgoing then p_account_id end,
        case when not v_outgoing then p_account_id end,
        p_category_id, p_counterparty, p_title, p_notes
      ) returning id into v_settlement_transaction_id;
    else
      update app_finance.financial_transactions
      set transaction_kind = p_transaction_kind,
          occurred_on = v_held.settled_on,
          amount_minor = p_amount_minor,
          currency_code = p_currency_code,
          source_account_id = case when v_outgoing then p_account_id end,
          destination_account_id = case when not v_outgoing then p_account_id end,
          category_id = p_category_id,
          counterparty = p_counterparty,
          title = p_title,
          notes = p_notes
      where id = v_settlement_transaction_id and user_id = v_user_id;
      if not found then raise exception 'not_found: settlement transaction'; end if;
    end if;
  end if;

  if p_held_id is null then
    insert into app_finance.held_amounts (
      user_id, direction, transaction_kind, category_id,
      amount_minor, currency_code, counterparty, held_on,
      transaction_id, linked_transaction_id, settlement_transaction_id,
      account_id, manages_transaction, title, notes
    ) values (
      v_user_id, v_direction, p_transaction_kind, p_category_id,
      p_amount_minor, p_currency_code, p_counterparty, p_held_on,
      v_linked_transaction_id, v_linked_transaction_id, null,
      p_account_id, true, p_title, p_notes
    ) returning id into v_held_id;
  else
    update app_finance.held_amounts
    set direction = v_direction,
        transaction_kind = p_transaction_kind,
        category_id = p_category_id,
        amount_minor = p_amount_minor,
        currency_code = p_currency_code,
        counterparty = p_counterparty,
        held_on = p_held_on,
        transaction_id = coalesce(v_settlement_transaction_id, v_linked_transaction_id),
        linked_transaction_id = v_linked_transaction_id,
        settlement_transaction_id = v_settlement_transaction_id,
        account_id = p_account_id,
        manages_transaction = true,
        title = p_title,
        notes = p_notes
    where id = p_held_id and user_id = v_user_id
    returning id into v_held_id;
  end if;

  return v_held_id;
end;
$$;

grant execute on function app_finance.save_held_amount(
  app_finance.transaction_kind, bigint, text, text, date, text, text,
  uuid, uuid, uuid, uuid
) to authenticated, service_role;

-- Settling books the stored kind and category on the settlement date.
create or replace function app_finance.set_held_amount_settled(
  p_held_id uuid,
  p_settled_on date
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_held app_finance.held_amounts%rowtype;
  v_account app_finance.accounts%rowtype;
  v_transaction_id uuid;
  v_outgoing boolean;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_held
  from app_finance.held_amounts
  where id = p_held_id and user_id = v_user_id
  for update;
  if v_held is null then raise exception 'not_found: held amount'; end if;

  v_transaction_id := v_held.settlement_transaction_id;

  if p_settled_on is null then
    if v_transaction_id is not null then
      delete from app_finance.financial_transactions
      where id = v_transaction_id and user_id = v_user_id;
    end if;
    update app_finance.held_amounts
    set settled_on = null,
        settlement_transaction_id = null,
        transaction_id = linked_transaction_id,
        manages_transaction = linked_transaction_id is null
    where id = p_held_id and user_id = v_user_id;
    return;
  end if;

  if v_held.account_id is null then
    select * into v_account
    from app_finance.accounts
    where user_id = v_user_id
      and currency_code = v_held.currency_code
      and not is_archived
    order by is_default desc, created_at, id
    limit 1;
  else
    select * into v_account
    from app_finance.accounts
    where id = v_held.account_id and user_id = v_user_id and not is_archived;
  end if;
  if v_account is null then raise exception 'invalid_account: account not found or archived'; end if;
  if v_account.currency_code <> v_held.currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  v_outgoing := v_held.transaction_kind in ('expense', 'allowance_given');

  if v_transaction_id is null then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, category_id,
      counterparty, title, notes
    ) values (
      v_user_id, v_held.transaction_kind, p_settled_on, v_held.amount_minor, v_held.currency_code,
      case when v_outgoing then v_account.id end,
      case when not v_outgoing then v_account.id end,
      v_held.category_id, v_held.counterparty, v_held.title, v_held.notes
    ) returning id into v_transaction_id;
  else
    update app_finance.financial_transactions
    set transaction_kind = v_held.transaction_kind,
        occurred_on = p_settled_on,
        amount_minor = v_held.amount_minor,
        currency_code = v_held.currency_code,
        source_account_id = case when v_outgoing then v_account.id end,
        destination_account_id = case when not v_outgoing then v_account.id end,
        category_id = v_held.category_id,
        counterparty = v_held.counterparty,
        title = v_held.title,
        notes = v_held.notes
    where id = v_transaction_id and user_id = v_user_id;
    if not found then raise exception 'not_found: settlement transaction'; end if;
  end if;

  update app_finance.held_amounts
  set settled_on = p_settled_on,
      settlement_transaction_id = v_transaction_id,
      transaction_id = v_transaction_id,
      account_id = v_account.id,
      manages_transaction = true
  where id = p_held_id and user_id = v_user_id;
end;
$$;

-- Deleting a held amount must only ever remove the settlement transaction
-- it created, never a linked origin transaction.
create or replace function app_finance.delete_held_amount(p_held_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_settlement_transaction_id uuid;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  delete from app_finance.held_amounts
    where id = p_held_id and user_id = v_user_id
    returning settlement_transaction_id
    into v_settlement_transaction_id;
  if not found then
    raise exception 'not_found: held amount';
  end if;

  if v_settlement_transaction_id is not null then
    delete from app_finance.financial_transactions
      where id = v_settlement_transaction_id and user_id = v_user_id;
  end if;
end;
$$;
