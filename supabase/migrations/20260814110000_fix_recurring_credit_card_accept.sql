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
    v_tx_id := app_finance.charge_credit_card(
      p_account_id => v_rule.source_account_id,
      p_title => v_rule.name,
      p_category_id => v_rule.category_id,
      p_occurred_on => p_paid_on,
      p_amount_minor => p_actual_amount_minor,
      p_notes => p_notes,
      p_charge_id => null,
      p_is_foreign_currency => v_rule.is_foreign_currency
    );
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
