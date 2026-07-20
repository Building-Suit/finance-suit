-- Legacy Held rows predate account linkage. Assign each unlinked row to its
-- owner's matching active default account so settlement can post a real
-- transaction. The RPC repeats this resolution for old clients that may still
-- create an unlinked row after this migration.

update app_finance.held_amounts held
set account_id = (
      select account.id
      from app_finance.accounts account
      where account.user_id = held.user_id
        and account.currency_code = held.currency_code
        and not account.is_archived
      order by account.is_default desc, account.created_at, account.id
      limit 1
    ),
    manages_transaction = true
where held.transaction_id is null
  and not held.manages_transaction
  and exists (
    select 1
    from app_finance.accounts account
    where account.user_id = held.user_id
      and account.currency_code = held.currency_code
      and not account.is_archived
  );

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
  v_kind app_finance.transaction_kind;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_held
    from app_finance.held_amounts
    where id = p_held_id and user_id = v_user_id
    for update;
  if v_held is null then
    raise exception 'not_found: held amount';
  end if;

  -- A non-managed row with no linked transaction is a legacy standalone Held
  -- amount, not a hold attached to an existing transaction. Convert it using
  -- the owner's matching active default (or oldest active) account.
  if not v_held.manages_transaction and v_held.transaction_id is null then
    select * into v_account
      from app_finance.accounts
      where user_id = v_user_id
        and currency_code = v_held.currency_code
        and not is_archived
      order by is_default desc, created_at, id
      limit 1;
    if v_account is null then
      raise exception 'invalid_account: no active matching account';
    end if;

    update app_finance.held_amounts
      set account_id = v_account.id,
          manages_transaction = true
      where id = p_held_id and user_id = v_user_id;
    v_held.account_id := v_account.id;
    v_held.manages_transaction := true;
  end if;

  -- A non-managed row with a transaction link is intentionally attached to
  -- an existing transaction and must never create a duplicate.
  if not v_held.manages_transaction then
    update app_finance.held_amounts
      set settled_on = p_settled_on
      where id = p_held_id and user_id = v_user_id;
    return;
  end if;

  if p_settled_on is null then
    if v_held.transaction_id is not null then
      delete from app_finance.financial_transactions
        where id = v_held.transaction_id and user_id = v_user_id;
    end if;
    update app_finance.held_amounts
      set settled_on = null, transaction_id = null
      where id = p_held_id and user_id = v_user_id;
    return;
  end if;

  select * into v_account
    from app_finance.accounts
    where id = v_held.account_id
      and user_id = v_user_id
      and not is_archived;
  if v_account is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if v_account.currency_code <> v_held.currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  v_kind := case v_held.direction
    when 'i_owe' then 'expense'::app_finance.transaction_kind
    when 'owed_to_me' then 'custom_income'::app_finance.transaction_kind
  end;

  if v_held.transaction_id is null then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, counterparty, title, notes
    ) values (
      v_user_id, v_kind, p_settled_on, v_held.amount_minor,
      v_held.currency_code,
      case when v_held.direction = 'i_owe' then v_held.account_id end,
      case when v_held.direction = 'owed_to_me' then v_held.account_id end,
      v_held.counterparty, v_held.title, v_held.notes
    ) returning id into v_transaction_id;
  else
    v_transaction_id := v_held.transaction_id;
    update app_finance.financial_transactions
      set occurred_on = p_settled_on
      where id = v_transaction_id and user_id = v_user_id;
  end if;

  update app_finance.held_amounts
    set settled_on = p_settled_on,
        transaction_id = v_transaction_id
    where id = p_held_id and user_id = v_user_id;
end;
$$;

notify pgrst, 'reload schema';
