alter table app_finance.recurring_rules
  add column if not exists is_foreign_currency boolean not null default false;

create or replace function app_finance.save_recurring_rule(
  p_name text,
  p_rule_kind app_finance.recurring_rule_kind,
  p_amount_minor bigint,
  p_frequency app_finance.recurring_frequency,
  p_payment_day smallint,
  p_start_date date,
  p_prompt_days_before smallint,
  p_source_account_id uuid,
  p_destination_account_id uuid default null,
  p_category_id uuid default null,
  p_notes text default null,
  p_rule_id uuid default null,
  p_is_active boolean default true,
  p_is_foreign_currency boolean default false
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_source record;
  v_rule_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  select a.id, a.currency_code, a.account_type into v_source
    from app_finance.accounts a
    where a.id = p_source_account_id and a.user_id = v_user_id
      and not a.is_archived;
  if v_source is null then
    raise exception 'invalid_account: account not found or archived';
  end if;
  if p_rule_kind = 'expense' then
    if app_finance.account_role(v_source.account_type) = 'liability'
      and v_source.account_type <> 'credit_card' then
      raise exception 'invalid_account: recurring expenses need cash or a credit card';
    end if;
    if not exists (
      select 1 from app_finance.transaction_categories c
      where c.id = p_category_id and c.user_id = v_user_id
        and not c.is_archived and c.category_kind = 'expense'
    ) then raise exception 'invalid_category: expense category required'; end if;
  else
    if app_finance.account_role(v_source.account_type) <> 'asset' then
      raise exception 'invalid_account: recurring transfers move your own cash';
    end if;
    if not exists (
      select 1 from app_finance.accounts d
      where d.id = p_destination_account_id and d.user_id = v_user_id
        and not d.is_archived and app_finance.account_role(d.account_type) = 'asset'
        and d.currency_code = v_source.currency_code
    ) then raise exception 'invalid_account: destination not found, archived, or mismatched'; end if;
  end if;
  if p_rule_id is not null then
    update app_finance.recurring_rules set
      name = p_name, rule_kind = p_rule_kind, amount_minor = p_amount_minor,
      currency_code = v_source.currency_code, frequency = p_frequency,
      payment_day = p_payment_day, start_date = p_start_date,
      prompt_days_before = coalesce(p_prompt_days_before, 3),
      source_account_id = p_source_account_id,
      destination_account_id = p_destination_account_id, category_id = p_category_id,
      is_active = coalesce(p_is_active, true), is_foreign_currency =
        (case when v_source.account_type = 'credit_card' and p_rule_kind = 'expense'
          then coalesce(p_is_foreign_currency, false) else false end), notes = p_notes
      where id = p_rule_id and user_id = v_user_id returning id into v_rule_id;
    if v_rule_id is not null then
      delete from app_finance.recurring_occurrences
        where rule_id = v_rule_id and user_id = v_user_id and status = 'pending';
    end if;
  end if;
  if v_rule_id is null then
    insert into app_finance.recurring_rules (
      id, user_id, name, rule_kind, amount_minor, currency_code, frequency,
      payment_day, start_date, prompt_days_before, source_account_id,
      destination_account_id, category_id, is_active, is_foreign_currency, notes
    ) values (
      coalesce(p_rule_id, gen_random_uuid()), v_user_id, p_name, p_rule_kind,
      p_amount_minor, v_source.currency_code, p_frequency, p_payment_day,
      p_start_date, coalesce(p_prompt_days_before, 3), p_source_account_id,
      p_destination_account_id, p_category_id, coalesce(p_is_active, true),
      (case when v_source.account_type = 'credit_card' and p_rule_kind = 'expense'
        then coalesce(p_is_foreign_currency, false) else false end), p_notes
    ) returning id into v_rule_id;
  end if;
  return v_rule_id;
end;
$$;

create or replace function app_finance.accept_recurring_occurrence(
  p_occurrence_id uuid,
  p_actual_amount_minor bigint,
  p_paid_on date,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_occurrence record;
  v_rule record;
  v_tx_id uuid;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_actual_amount_minor is null or p_actual_amount_minor <= 0 then
    raise exception 'invalid_amount: must be positive';
  end if;
  select o.* into v_occurrence from app_finance.recurring_occurrences o
    where o.id = p_occurrence_id and o.user_id = v_user_id for update;
  if v_occurrence is null then raise exception 'not_found: recurring occurrence'; end if;
  if v_occurrence.status = 'accepted' then return v_occurrence.transaction_id; end if;
  if v_occurrence.status <> 'pending' then raise exception 'already_decided: this entry was already handled'; end if;
  select r.* into v_rule from app_finance.recurring_rules r
    where r.id = v_occurrence.rule_id and r.user_id = v_user_id;
  if v_rule.rule_kind = 'transfer' then
    v_tx_id := app_finance.create_transfer(v_rule.source_account_id,
      v_rule.destination_account_id, p_actual_amount_minor, p_paid_on, p_notes);
  elsif exists (select 1 from app_finance.accounts a where a.id = v_rule.source_account_id
    and a.account_type = 'credit_card') then
    v_tx_id := app_finance.charge_credit_card(v_rule.source_account_id, v_rule.name,
      v_rule.category_id, p_paid_on, p_actual_amount_minor, p_notes, null,
      v_rule.is_foreign_currency);
  else
    insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, category_id, title, notes
    ) values (v_user_id, 'expense', p_paid_on, p_actual_amount_minor,
      v_rule.currency_code, v_rule.source_account_id, v_rule.category_id,
      v_rule.name, p_notes) returning id into v_tx_id;
  end if;
  update app_finance.recurring_occurrences set status = 'accepted',
    actual_amount_minor = p_actual_amount_minor, paid_on = p_paid_on,
    transaction_id = v_tx_id, decision_at = now(), notes = coalesce(p_notes, notes)
    where id = p_occurrence_id and user_id = v_user_id;
  return v_tx_id;
end;
$$;

notify pgrst, 'reload schema';
