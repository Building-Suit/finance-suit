begin;

-- Establish the target identity before using the same authenticated RPC path
-- as the application. Cardinality checks prevent a broad repair.
do $$
declare
  v_user_id uuid;
  v_count integer;
begin
  select count(*), min(id::text)::uuid into v_count, v_user_id
  from public.profiles
  where lower(email) = lower('tarekian99@gmail.com');

  if v_count <> 1 then
    raise exception 'repair_target_user_count: expected 1, found %', v_count;
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

set local role authenticated;

do $$
declare
  v_user_id uuid := (select auth.uid());
  v_account_id uuid;
  v_samsung_id uuid;
  v_el_araby_id uuid;
  v_bank_category_id uuid;
  v_interest_category_id uuid;
  v_tax_category_id uuid;
  v_stamp_rule_id uuid;
  v_interest_rule_id uuid;
  v_payment_id uuid;
  v_count integer;
  v_outstanding bigint;
  v_settings app_finance.credit_facility_settings;
  v_account app_finance.accounts;
  v_rule app_finance.credit_card_fee_rules;
  v_version app_finance.credit_card_fee_rule_versions;
begin
  select count(*), min(a.id::text)::uuid into v_count, v_account_id
  from app_finance.accounts a
  where a.user_id = v_user_id
    and a.name = 'CIB Gold Card'
    and a.account_type = 'credit_card'
    and a.currency_code = 'EGP'
    and not a.is_archived;
  if v_count <> 1 then
    raise exception 'repair_target_card_count: expected 1, found %', v_count;
  end if;

  select * into strict v_account from app_finance.accounts
  where id = v_account_id and user_id = v_user_id;
  select * into strict v_settings from app_finance.credit_facility_settings
  where account_id = v_account_id and user_id = v_user_id;

  if v_settings.credit_limit_minor <> 2580000
    or v_settings.last_four_digits <> '6011' then
    raise exception 'unexpected_card_fixture';
  end if;

  v_outstanding := app_finance.facility_outstanding_minor(v_account_id);
  if v_outstanding not in (2366234, 2426727) then
    raise exception 'unexpected_before_outstanding: %', v_outstanding;
  end if;

  select count(*), min(id::text)::uuid into v_count, v_samsung_id
  from app_finance.installment_plans
  where user_id = v_user_id and account_id = v_account_id
    and title = 'Samsung Monitor' and origin = 'historical_import';
  if v_count <> 1 then
    raise exception 'samsung_plan_count: expected 1, found %', v_count;
  end if;

  select count(*), min(id::text)::uuid into v_count, v_el_araby_id
  from app_finance.installment_plans
  where user_id = v_user_id and account_id = v_account_id
    and title = 'Al Araby Makram Ebid' and origin = 'historical_import';
  if v_count <> 1 then
    raise exception 'el_araby_plan_count: expected 1, found %', v_count;
  end if;

  perform app_finance.reconcile_historical_installment_plan(
    v_samsung_id, 27, date '2026-08-07', 439869, true,
    'Reconciled to CIB installment snapshot dated 2026-08-07'
  );
  perform app_finance.reconcile_historical_installment_plan(
    v_el_araby_id, 4, date '2026-08-07', 1469924, true,
    'Reconciled to CIB installment snapshot dated 2026-08-07; '
      || '2026-08-25 is posted, not paid'
  );

  perform app_finance.save_credit_facility(
    p_name => v_account.name,
    p_account_type => v_account.account_type,
    p_currency_code => v_account.currency_code,
    p_credit_limit_minor => v_settings.credit_limit_minor,
    p_default_due_day => 25::smallint,
    p_statement_day => 31::smallint,
    p_last_four_digits => v_settings.last_four_digits,
    p_reminder_lead_days => v_settings.reminder_lead_days,
    p_notes => v_account.notes,
    p_account_id => v_account_id,
    p_facility_status => v_settings.facility_status,
    p_min_payment_method => 'percent',
    p_min_payment_fixed_minor => null,
    p_min_payment_basis_points => 500,
    p_color_hex => v_settings.color_hex,
    p_fx_markup_basis_points => v_settings.fx_markup_basis_points,
    p_installment_due_day => 25::smallint,
    p_grace_period_days => 0::smallint,
    p_min_payment_percentage_basis => 'revolving_noninstallment',
    p_min_payment_include_installment_dues => true,
    p_min_payment_include_bank_fees => true,
    p_min_payment_include_overdue => false,
    p_min_payment_fixed_floor_minor => null
  );

  select count(*), min(id::text)::uuid into v_count, v_bank_category_id
  from app_finance.transaction_categories
  where user_id = v_user_id and category_kind = 'expense'
    and lower(name) = lower('Bank') and not is_archived;
  if v_count <> 1 then
    raise exception 'bank_category_count: expected 1, found %', v_count;
  end if;

  select count(*), min(id::text)::uuid into v_count, v_interest_category_id
  from app_finance.transaction_categories
  where user_id = v_user_id and category_kind = 'expense'
    and lower(name) = lower('Card Interest') and not is_archived;
  if v_count = 0 then
    insert into app_finance.transaction_categories (
      user_id, name, category_kind, parent_category_id, icon, sort_order
    ) values (
      v_user_id, 'Card Interest', 'expense', v_bank_category_id,
      'percent', 10
    ) returning id into v_interest_category_id;
  elsif v_count <> 1 then
    raise exception 'interest_category_count: expected at most 1, found %', v_count;
  end if;

  select count(*), min(id::text)::uuid into v_count, v_tax_category_id
  from app_finance.transaction_categories
  where user_id = v_user_id and category_kind = 'expense'
    and lower(name) = lower('Taxes & Government Charges') and not is_archived;
  if v_count = 0 then
    insert into app_finance.transaction_categories (
      user_id, name, category_kind, parent_category_id, icon, sort_order
    ) values (
      v_user_id, 'Taxes & Government Charges', 'expense', v_bank_category_id,
      'receipt_long', 20
    ) returning id into v_tax_category_id;
  elsif v_count <> 1 then
    raise exception 'tax_category_count: expected at most 1, found %', v_count;
  end if;

  select count(*), min(id::text)::uuid into v_count, v_stamp_rule_id
  from app_finance.credit_card_fee_rules
  where user_id = v_user_id and account_id = v_account_id
    and fee_type = 'stamp_tax';
  if v_count = 0 then
    v_stamp_rule_id := app_finance.save_credit_card_fee_rule(
      p_account_id => v_account_id,
      p_name => 'Quarterly stamp duty',
      p_fee_type => 'stamp_tax',
      p_category_id => v_tax_category_id,
      p_state => 'configured',
      p_trigger_kind => 'schedule',
      p_starts_on => date '2026-07-01',
      p_calculation_type => 'percentage',
      p_percent_basis_points => 5,
      p_percent_basis => 'highest_statement_due_lookback',
      p_lookback_cycles => 3,
      p_frequency => 'quarterly',
      p_notes => 'CIB Gold: 0.05% of highest statement due in prior 3 cycles'
    );
  elsif v_count <> 1 then
    raise exception 'stamp_rule_count: expected at most 1, found %', v_count;
  else
    select * into strict v_rule from app_finance.credit_card_fee_rules
    where id = v_stamp_rule_id;
    select * into strict v_version from app_finance.credit_card_fee_rule_versions
    where rule_id = v_stamp_rule_id order by effective_from desc limit 1;
    if v_rule.state <> 'configured' or v_rule.trigger_kind <> 'schedule'
      or v_version.calculation_type <> 'percentage'
      or v_version.percent_basis_points <> 5
      or v_version.percent_basis <> 'highest_statement_due_lookback'
      or v_version.lookback_cycles <> 3
      or v_version.frequency <> 'quarterly' then
      raise exception 'unexpected_existing_stamp_rule';
    end if;
  end if;

  select count(*), min(id::text)::uuid into v_count, v_interest_rule_id
  from app_finance.credit_card_fee_rules
  where user_id = v_user_id and account_id = v_account_id
    and fee_type = 'purchase_interest';
  if v_count = 0 then
    v_interest_rule_id := app_finance.configure_purchase_interest_rule(
      p_account_id => v_account_id,
      p_category_id => v_interest_category_id,
      p_state => 'unknown',
      p_effective_from => date '2026-08-01',
      p_rate_basis_points => null,
      p_rate_period => 'monthly',
      p_accrual_method => 'bank_posted_manual',
      p_interest_starts => 'grace_expiry',
      p_grace_period_days => null,
      p_grace_applies => true,
      p_notes => 'Historical actual is bank-authoritative; future rate unknown'
    );
  elsif v_count <> 1 then
    raise exception 'purchase_interest_rule_count: expected at most 1, found %',
      v_count;
  end if;

  perform app_finance.record_actual_card_charge(
    v_account_id, v_stamp_rule_id, date '2026-07-01', 1312,
    'cib-gold-non-fx:stamp:2026-07-01',
    'Confirmed from CIB activity; historical actual is authoritative'
  );
  perform app_finance.record_actual_card_charge(
    v_account_id, v_interest_rule_id, date '2026-08-01', 10996,
    'cib-gold-non-fx:purchase-interest:2026-08-01',
    'Confirmed from CIB activity; historical actual is authoritative'
  );

  select count(*), min(t.id::text)::uuid into v_count, v_payment_id
  from app_finance.financial_transactions t
  where t.user_id = v_user_id
    and t.occurred_on = date '2026-07-14'
    and t.amount_minor = 412507
    and t.currency_code = 'EGP'
    and t.title = 'CIB Credit Card'
    and t.source_account_id is not null
    and (
      (t.transaction_kind = 'expense' and t.destination_account_id is null)
      or (t.transaction_kind = 'transfer'
        and t.destination_account_id = v_account_id)
    );
  if v_count <> 1 then
    raise exception 'historical_payment_count: expected 1, found %', v_count;
  end if;
  perform app_finance.correct_historical_facility_payment(
    v_payment_id, v_account_id, 412507,
    'cib-gold-non-fx:payment:2026-07-14:412507',
    'Corrected from expense to historical CIB Gold repayment; matching '
      || 'historical obligation preserves current liability'
  );

  v_outstanding := app_finance.facility_outstanding_minor(v_account_id);
  if v_outstanding <> 2426727 then
    raise exception 'unexpected_after_outstanding: expected 2426727, found %',
      v_outstanding;
  end if;
end;
$$;

commit;
