-- Expected-versus-actual reconciliation. Finance Suit's calculation is an
-- estimate; the bank statement is authoritative. Reconciling one charge
-- never silently changes the rule that generated it — a future rate
-- change is always an explicit, separate choice.
--
-- Scope: this RPC reconciles a charge whose actual amount differs from
-- (or matches) what Finance Suit predicted — the "confirmed"/"adjusted"
-- half of the reconciliation_status lifecycle described in the product
-- spec. A bank fully waiving or reversing a charge, or a charge that
-- never posts at all ("missing"), needs its own transaction-deletion and
-- reversal handling and is intentionally left out of this pass; the
-- amount_minor > 0 guard on financial_transactions means "waived" can't
-- be represented by simply zeroing this charge's ledger row.

-- credit_card_statement_items shipped with select/insert/delete RLS
-- policies only (20260806090000); reconciliation is the first thing that
-- needs to correct a statement item's amount in place rather than
-- deleting and reinserting it. Direct write access is still RPC-only via
-- the existing protect_installment_rows trigger.
drop policy if exists credit_card_statement_items_update
  on app_finance.credit_card_statement_items;
create policy credit_card_statement_items_update
  on app_finance.credit_card_statement_items
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function app_finance.reconcile_fee_charge(
  p_charge_id uuid,
  p_actual_amount_minor bigint,
  p_update_rule_going_forward boolean default false,
  p_new_version_effective_from date default null,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_charge record;
  v_calc app_finance.credit_card_fee_rule_versions;
  v_status app_finance.charge_reconciliation_status;
  v_effective_from date;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;
  if p_actual_amount_minor is null or p_actual_amount_minor <= 0 then
    raise exception
      'invalid_amount: reconciled charges must stay positive; use the '
      'facility screen to reverse a fully waived charge instead';
  end if;

  select c.id, c.rule_id, c.rule_version_id, c.transaction_id,
      c.expected_amount_minor
    into v_charge
    from app_finance.credit_card_fee_charges c
    where c.id = p_charge_id and c.user_id = v_user_id
    for update;
  if v_charge is null then
    raise exception 'not_found: generated charge';
  end if;

  v_status := case
    when p_actual_amount_minor = v_charge.expected_amount_minor
      then 'confirmed'
    else 'adjusted'
  end;

  perform set_config('app_finance.facility_internal', 'on', true);

  update app_finance.credit_card_fee_charges
    set actual_amount_minor = p_actual_amount_minor,
      amount_minor = p_actual_amount_minor,
      reconciliation_status = v_status,
      reconciled_at = now(),
      reconciliation_notes = p_notes
    where id = p_charge_id and user_id = v_user_id;

  update app_finance.financial_transactions
    set amount_minor = p_actual_amount_minor
    where id = v_charge.transaction_id and user_id = v_user_id;

  update app_finance.credit_card_statement_items
    set amount_minor = p_actual_amount_minor
    where transaction_id = v_charge.transaction_id and user_id = v_user_id;

  if p_update_rule_going_forward then
    select * into v_calc from app_finance.credit_card_fee_rule_versions
      where id = v_charge.rule_version_id and user_id = v_user_id;
    if v_calc.calculation_type <> 'fixed' then
      raise exception
        'unsupported_rule_edit: reconcile a fixed-amount rule this way, '
        'or open the rule to change a percentage rate directly';
    end if;

    v_effective_from := coalesce(p_new_version_effective_from, current_date);
    perform app_finance.create_fee_rule_version(
      v_charge.rule_id, v_effective_from, 'fixed', p_actual_amount_minor,
      null, null, v_calc.minimum_minor, v_calc.maximum_minor,
      v_calc.lookback_cycles, v_calc.frequency, v_calc.apply_when,
      v_calc.tolerance_minor, v_calc.tolerance_basis_points, p_notes
    );
  end if;

  perform set_config('app_finance.facility_internal', '', true);
  return p_charge_id;
end;
$$;

revoke execute on function app_finance.reconcile_fee_charge(
  uuid, bigint, boolean, date, text
) from public, anon;
grant execute on function app_finance.reconcile_fee_charge(
  uuid, bigint, boolean, date, text
) to authenticated, service_role;

notify pgrst, 'reload schema';
