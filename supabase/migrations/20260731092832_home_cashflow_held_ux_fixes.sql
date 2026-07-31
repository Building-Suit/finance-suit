-- Home dashboard, cash-flow, income snooze, and linked held settlement fixes.

alter table app_finance.income_occurrences
  add column if not exists snoozed_until timestamptz;

alter table app_finance.income_occurrences
  drop constraint if exists income_occurrence_state_fields;

alter table app_finance.income_occurrences
  add constraint income_occurrence_state_fields check (
    (status = 'pending'
      and actual_amount_minor is null
      and received_on is null
      and primary_transaction_id is null
      and decision_at is null)
    or (status = 'skipped'
      and primary_transaction_id is null
      and decision_at is not null)
    or (status = 'accepted'
      and actual_amount_minor is not null
      and received_on is not null
      and primary_transaction_id is not null
      and decision_at is not null)
  );

create index if not exists idx_income_occurrences_actionable
  on app_finance.income_occurrences (user_id, status, snoozed_until, scheduled_on, id);

create or replace function app_finance.snooze_income_occurrence(
  p_occurrence_id uuid,
  p_snoozed_until timestamptz
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_occurrence app_finance.income_occurrences%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_snoozed_until is null
    or p_snoozed_until <= now()
    or p_snoozed_until > now() + interval '7 days' then
    raise exception 'invalid_snooze_until';
  end if;

  select * into v_occurrence
  from app_finance.income_occurrences
  where id = p_occurrence_id and user_id = v_user_id
  for update;
  if v_occurrence is null then
    raise exception 'not_found: income occurrence';
  end if;
  if v_occurrence.status <> 'pending' then
    raise exception 'already_decided';
  end if;

  update app_finance.income_occurrences
    set snoozed_until = p_snoozed_until
    where id = p_occurrence_id and user_id = v_user_id;
end;
$$;

revoke execute on function app_finance.snooze_income_occurrence(uuid, timestamptz)
from public;
grant execute on function app_finance.snooze_income_occurrence(uuid, timestamptz)
to authenticated, service_role;

create or replace function app_reports.cash_flow_summary_v2(
  p_start date,
  p_end date
)
returns table (
  currency_code text,
  starting_balance_minor bigint,
  income_minor bigint,
  expenses_minor bigint,
  allowances_minor bigint,
  net_minor bigint,
  ending_balance_minor bigint
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_start > p_end then
    raise exception 'invalid_range: start must be on or before end';
  end if;

  return query
  with currencies as (
    select distinct a.currency_code
    from app_finance.accounts a
    where a.user_id = v_user_id and not a.is_archived
    union
    select distinct t.currency_code
    from app_finance.financial_transactions t
    where t.user_id = v_user_id
      and t.occurred_on <= p_end
  ),
  opening as (
    select a.currency_code, sum(a.opening_balance_minor)::bigint as amount
    from app_finance.accounts a
    where a.user_id = v_user_id and not a.is_archived
    group by a.currency_code
  ),
  before_flows as (
    select
      t.currency_code,
      sum(case
        when t.transaction_kind in ('custom_income', 'freelance_income', 'salary_income')
          then t.amount_minor
        when t.transaction_kind in ('expense', 'allowance_given')
          then -t.amount_minor
        else 0
      end)::bigint as amount
    from app_finance.financial_transactions t
    join app_finance.accounts a
      on a.user_id = t.user_id
     and a.id = coalesce(t.source_account_id, t.destination_account_id)
     and not a.is_archived
    where t.user_id = v_user_id
      and t.occurred_on < p_start
      and t.transaction_kind <> 'transfer'
    group by t.currency_code
  ),
  ranged as (
    select
      t.currency_code,
      coalesce(sum(t.amount_minor) filter (where t.transaction_kind in
        ('custom_income', 'freelance_income', 'salary_income')), 0)::bigint as income_minor,
      coalesce(sum(t.amount_minor) filter (where t.transaction_kind = 'expense'), 0)::bigint as expenses_minor,
      coalesce(sum(t.amount_minor) filter (where t.transaction_kind = 'allowance_given'), 0)::bigint as allowances_minor
    from app_finance.financial_transactions t
    join app_finance.accounts a
      on a.user_id = t.user_id
     and a.id = coalesce(t.source_account_id, t.destination_account_id)
     and not a.is_archived
    where t.user_id = v_user_id
      and t.occurred_on between p_start and p_end
      and t.transaction_kind <> 'transfer'
    group by t.currency_code
  )
  select
    c.currency_code,
    (coalesce(o.amount, 0) + coalesce(b.amount, 0))::bigint as starting_balance_minor,
    coalesce(r.income_minor, 0)::bigint,
    coalesce(r.expenses_minor, 0)::bigint,
    coalesce(r.allowances_minor, 0)::bigint,
    (coalesce(r.income_minor, 0) - coalesce(r.expenses_minor, 0) - coalesce(r.allowances_minor, 0))::bigint as net_minor,
    (coalesce(o.amount, 0) + coalesce(b.amount, 0)
      + coalesce(r.income_minor, 0) - coalesce(r.expenses_minor, 0)
      - coalesce(r.allowances_minor, 0))::bigint as ending_balance_minor
  from currencies c
  left join opening o using (currency_code)
  left join before_flows b using (currency_code)
  left join ranged r using (currency_code)
  order by c.currency_code;
end;
$$;

revoke execute on function app_reports.cash_flow_summary_v2(date, date)
from public;
grant execute on function app_reports.cash_flow_summary_v2(date, date)
to authenticated, service_role;

alter table app_finance.held_amounts
  add column if not exists linked_transaction_id uuid,
  add column if not exists settlement_transaction_id uuid;

alter table app_finance.held_amounts
  drop constraint if exists held_amounts_linked_transaction_owner_fk;
alter table app_finance.held_amounts
  add constraint held_amounts_linked_transaction_owner_fk
  foreign key (linked_transaction_id, user_id)
  references app_finance.financial_transactions (id, user_id)
  on delete set null (linked_transaction_id);

alter table app_finance.held_amounts
  drop constraint if exists held_amounts_settlement_transaction_owner_fk;
alter table app_finance.held_amounts
  add constraint held_amounts_settlement_transaction_owner_fk
  foreign key (settlement_transaction_id, user_id)
  references app_finance.financial_transactions (id, user_id)
  on delete set null (settlement_transaction_id);

create index if not exists idx_held_amounts_linked_transaction
  on app_finance.held_amounts (linked_transaction_id, user_id)
  where linked_transaction_id is not null;
create unique index if not exists idx_held_amounts_one_settlement_transaction
  on app_finance.held_amounts (settlement_transaction_id)
  where settlement_transaction_id is not null;

update app_finance.held_amounts held
set linked_transaction_id = transaction_id
where transaction_id is not null
  and not manages_transaction
  and linked_transaction_id is null;

update app_finance.held_amounts held
set settlement_transaction_id = transaction_id
where transaction_id is not null
  and manages_transaction
  and settled_on is not null
  and settlement_transaction_id is null;

update app_finance.held_amounts held
set account_id = coalesce(held.account_id, tx.source_account_id, tx.destination_account_id)
from app_finance.financial_transactions tx
where held.linked_transaction_id = tx.id
  and held.user_id = tx.user_id
  and held.account_id is null;

alter table app_finance.held_amounts
  drop constraint if exists held_managed_account_required;
alter table app_finance.held_amounts
  add constraint held_settlement_account_required check (account_id is not null);

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
  v_held_id uuid;
  v_linked_transaction_id uuid := p_transaction_id;
  v_settlement_transaction_id uuid;
  v_kind app_finance.transaction_kind;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor <= 0 then raise exception 'invalid_amount: amount must be positive'; end if;

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
    v_kind := case p_direction
      when 'i_owe' then 'expense'::app_finance.transaction_kind
      when 'owed_to_me' then 'custom_income'::app_finance.transaction_kind
    end;
    if v_settlement_transaction_id is null then
      insert into app_finance.financial_transactions (
        user_id, transaction_kind, occurred_on, amount_minor, currency_code,
        source_account_id, destination_account_id, counterparty, title, notes
      ) values (
        v_user_id, v_kind, v_held.settled_on, p_amount_minor, p_currency_code,
        case when p_direction = 'i_owe' then p_account_id end,
        case when p_direction = 'owed_to_me' then p_account_id end,
        p_counterparty, p_title, p_notes
      ) returning id into v_settlement_transaction_id;
    else
      update app_finance.financial_transactions
      set transaction_kind = v_kind,
          occurred_on = v_held.settled_on,
          amount_minor = p_amount_minor,
          currency_code = p_currency_code,
          source_account_id = case when p_direction = 'i_owe' then p_account_id end,
          destination_account_id = case when p_direction = 'owed_to_me' then p_account_id end,
          category_id = null,
          counterparty = p_counterparty,
          title = p_title,
          notes = p_notes
      where id = v_settlement_transaction_id and user_id = v_user_id;
      if not found then raise exception 'not_found: settlement transaction'; end if;
    end if;
  end if;

  if p_held_id is null then
    insert into app_finance.held_amounts (
      user_id, direction, amount_minor, currency_code, counterparty, held_on,
      transaction_id, linked_transaction_id, settlement_transaction_id,
      account_id, manages_transaction, title, notes
    ) values (
      v_user_id, p_direction, p_amount_minor, p_currency_code, p_counterparty, p_held_on,
      v_linked_transaction_id, v_linked_transaction_id, null,
      p_account_id, true, p_title, p_notes
    ) returning id into v_held_id;
  else
    update app_finance.held_amounts
    set direction = p_direction,
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
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_held
  from app_finance.held_amounts
  where id = p_held_id and user_id = v_user_id
  for update;
  if v_held is null then raise exception 'not_found: held amount'; end if;

  v_transaction_id := coalesce(v_held.settlement_transaction_id, case when v_held.manages_transaction then v_held.transaction_id end);

  if p_settled_on is null then
    if v_transaction_id is not null then
      delete from app_finance.financial_transactions
      where id = v_transaction_id and user_id = v_user_id;
    end if;
    update app_finance.held_amounts
    set settled_on = null,
        settlement_transaction_id = null,
        transaction_id = linked_transaction_id
    where id = p_held_id and user_id = v_user_id;
    return;
  end if;

  select * into v_account
  from app_finance.accounts
  where id = v_held.account_id and user_id = v_user_id and not is_archived;
  if v_account is null then raise exception 'invalid_account: account not found or archived'; end if;
  if v_account.currency_code <> v_held.currency_code then
    raise exception 'currency_mismatch: held amount and account must match';
  end if;

  v_kind := case v_held.direction
    when 'i_owe' then 'expense'::app_finance.transaction_kind
    when 'owed_to_me' then 'custom_income'::app_finance.transaction_kind
  end;

  if v_transaction_id is null then
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, destination_account_id, counterparty, title, notes
    ) values (
      v_user_id, v_kind, p_settled_on, v_held.amount_minor, v_held.currency_code,
      case when v_held.direction = 'i_owe' then v_held.account_id end,
      case when v_held.direction = 'owed_to_me' then v_held.account_id end,
      v_held.counterparty, v_held.title, v_held.notes
    ) returning id into v_transaction_id;
  else
    update app_finance.financial_transactions
    set occurred_on = p_settled_on
    where id = v_transaction_id and user_id = v_user_id;
  end if;

  update app_finance.held_amounts
  set settled_on = p_settled_on,
      settlement_transaction_id = v_transaction_id,
      transaction_id = v_transaction_id,
      manages_transaction = true
  where id = p_held_id and user_id = v_user_id;
end;
$$;

create or replace function app_finance.delete_held_amount(p_held_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_settlement_transaction_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select coalesce(settlement_transaction_id, case when manages_transaction then transaction_id end)
  into v_settlement_transaction_id
  from app_finance.held_amounts
  where id = p_held_id and user_id = v_user_id
  for update;
  if not found then raise exception 'not_found: held amount'; end if;

  delete from app_finance.held_amounts
  where id = p_held_id and user_id = v_user_id;

  if v_settlement_transaction_id is not null then
    delete from app_finance.financial_transactions
    where id = v_settlement_transaction_id and user_id = v_user_id;
  end if;
end;
$$;

grant execute on function app_finance.save_held_amount(
  app_finance.held_amount_direction, bigint, text, text, date, text, text, uuid, uuid, uuid
) to authenticated, service_role;
grant execute on function app_finance.set_held_amount_settled(uuid, date)
to authenticated, service_role;
grant execute on function app_finance.delete_held_amount(uuid)
to authenticated, service_role;

notify pgrst, 'reload schema';
