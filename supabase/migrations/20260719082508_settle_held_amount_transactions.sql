-- Held amounts affect account balances only when they are settled. Correct
-- the earlier eager-posting behavior while preserving already-settled rows.

alter table app_finance.held_amounts
  drop constraint held_managed_transaction_complete;

-- Restore balances for active holds created by the previous implementation.
-- The ownership-aware FK clears held_amounts.transaction_id automatically.
delete from app_finance.financial_transactions tx
using app_finance.held_amounts held
where held.transaction_id = tx.id
  and held.user_id = tx.user_id
  and held.manages_transaction
  and held.settled_on is null;

alter table app_finance.held_amounts
  add constraint held_managed_account_required check (
    not manages_transaction or account_id is not null
  );

create or replace function app_finance.save_held_amount(
  p_direction app_finance.held_amount_direction,
  p_amount_minor bigint,
  p_currency_code text,
  p_counterparty text,
  p_held_on date,
  p_title text default null,
  p_notes text default null,
  p_account_id uuid default null,
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
  v_transaction_id uuid := p_transaction_id;
  v_manages_transaction boolean := false;
  v_held_id uuid;
  v_kind app_finance.transaction_kind;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_amount_minor <= 0 then
    raise exception 'invalid_amount: amount must be positive';
  end if;

  if p_held_id is not null then
    select * into v_held
      from app_finance.held_amounts
      where id = p_held_id and user_id = v_user_id
      for update;
    if v_held is null then
      raise exception 'not_found: held amount';
    end if;
    v_manages_transaction := v_held.manages_transaction;
    v_transaction_id := v_held.transaction_id;
    if v_manages_transaction then
      p_account_id := coalesce(p_account_id, v_held.account_id);
    end if;
  elsif p_transaction_id is null then
    v_manages_transaction := true;
  end if;

  if v_manages_transaction then
    select * into v_account
      from app_finance.accounts
      where id = p_account_id
        and user_id = v_user_id
        and not is_archived;
    if v_account is null then
      raise exception 'invalid_account: account not found or archived';
    end if;
    if v_account.currency_code <> p_currency_code then
      raise exception 'currency_mismatch: held amount and account must match';
    end if;

    -- A settled managed hold already has an actual transaction. Keep edits to
    -- the held record and that transaction synchronized. Active holds do not
    -- create transactions and therefore cannot affect balances.
    if p_held_id is not null and v_held.settled_on is not null then
      v_kind := case p_direction
        when 'i_owe' then 'expense'::app_finance.transaction_kind
        when 'owed_to_me' then 'custom_income'::app_finance.transaction_kind
      end;

      if v_transaction_id is null then
        insert into app_finance.financial_transactions (
          user_id, transaction_kind, occurred_on, amount_minor, currency_code,
          source_account_id, destination_account_id, counterparty, title, notes
        ) values (
          v_user_id, v_kind, v_held.settled_on, p_amount_minor,
          p_currency_code,
          case when p_direction = 'i_owe' then p_account_id end,
          case when p_direction = 'owed_to_me' then p_account_id end,
          p_counterparty, p_title, p_notes
        ) returning id into v_transaction_id;
      else
        update app_finance.financial_transactions
          set transaction_kind = v_kind,
              occurred_on = v_held.settled_on,
              amount_minor = p_amount_minor,
              currency_code = p_currency_code,
              source_account_id = case
                when p_direction = 'i_owe' then p_account_id
              end,
              destination_account_id = case
                when p_direction = 'owed_to_me' then p_account_id
              end,
              category_id = null,
              counterparty = p_counterparty,
              title = p_title,
              notes = p_notes
          where id = v_transaction_id and user_id = v_user_id;
        if not found then
          raise exception 'not_found: managed transaction';
        end if;
      end if;
    end if;
  end if;

  if p_held_id is null then
    insert into app_finance.held_amounts (
      user_id, direction, amount_minor, currency_code, counterparty,
      held_on, transaction_id, account_id, manages_transaction, title, notes
    ) values (
      v_user_id, p_direction, p_amount_minor, p_currency_code, p_counterparty,
      p_held_on, v_transaction_id, p_account_id, v_manages_transaction,
      p_title, p_notes
    ) returning id into v_held_id;
  else
    update app_finance.held_amounts
      set direction = p_direction,
          amount_minor = p_amount_minor,
          currency_code = p_currency_code,
          counterparty = p_counterparty,
          held_on = p_held_on,
          transaction_id = v_transaction_id,
          account_id = case
            when v_manages_transaction then p_account_id
            else v_held.account_id
          end,
          title = p_title,
          notes = p_notes
      where id = p_held_id and user_id = v_user_id
      returning id into v_held_id;
  end if;

  return v_held_id;
end;
$$;

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

grant execute on function app_finance.set_held_amount_settled(uuid, date)
to authenticated, service_role;

notify pgrst, 'reload schema';
