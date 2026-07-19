-- Make standalone held amounts real account transactions. The RPC keeps the
-- held record and its generated transaction in one database transaction.

alter table app_finance.held_amounts
  add column account_id uuid,
  add column manages_transaction boolean not null default false,
  add constraint held_amounts_account_owner_fk
    foreign key (account_id, user_id)
    references app_finance.accounts (id, user_id),
  add constraint held_managed_transaction_complete check (
    not manages_transaction
    or (account_id is not null and transaction_id is not null)
  );

create index idx_held_amounts_account_owner_fk
  on app_finance.held_amounts (account_id, user_id)
  where account_id is not null;

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

    v_kind := case p_direction
      when 'i_owe' then 'expense'::app_finance.transaction_kind
      when 'owed_to_me' then 'custom_income'::app_finance.transaction_kind
    end;

    if v_transaction_id is null then
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, destination_account_id, counterparty, title, notes
      ) values (
        v_user_id, v_kind, p_held_on, p_amount_minor, p_currency_code,
        case when p_direction = 'i_owe' then p_account_id end,
        case when p_direction = 'owed_to_me' then p_account_id end,
        p_counterparty, p_title, p_notes
      ) returning id into v_transaction_id;
    else
      update app_finance.financial_transactions
        set transaction_kind = v_kind,
            occurred_on = p_held_on,
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

create or replace function app_finance.delete_held_amount(p_held_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_transaction_id uuid;
  v_manages_transaction boolean;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  delete from app_finance.held_amounts
    where id = p_held_id and user_id = v_user_id
    returning transaction_id, manages_transaction
    into v_transaction_id, v_manages_transaction;
  if not found then
    raise exception 'not_found: held amount';
  end if;

  if v_manages_transaction then
    delete from app_finance.financial_transactions
      where id = v_transaction_id and user_id = v_user_id;
  end if;
end;
$$;

grant execute on function app_finance.save_held_amount(
  app_finance.held_amount_direction, bigint, text, text, date,
  text, text, uuid, uuid, uuid
) to authenticated, service_role;
grant execute on function app_finance.delete_held_amount(uuid)
to authenticated, service_role;

notify pgrst, 'reload schema';
