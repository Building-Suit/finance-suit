do $$
declare
  v_missing text[] := array[]::text[];
  v_without_rls integer;
begin
  if to_regclass('app_finance.held_amounts') is null then
    v_missing := array_append(v_missing, 'app_finance.held_amounts');
  end if;
  if to_regclass('app_reports.history_items') is null then
    v_missing := array_append(v_missing, 'app_reports.history_items');
  end if;
  if to_regclass('app_finance.income_sources') is null then
    v_missing := array_append(v_missing, 'app_finance.income_sources');
  end if;
  if to_regclass('app_finance.income_occurrences') is null then
    v_missing := array_append(v_missing, 'app_finance.income_occurrences');
  end if;
  if to_regclass('app_finance.income_source_allocations') is null then
    v_missing := array_append(v_missing, 'app_finance.income_source_allocations');
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'held_amounts'
      and column_name = 'transaction_kind'
  ) then
    v_missing := array_append(v_missing, 'held_amounts.transaction_kind');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'held_amounts'
      and column_name = 'category_id'
  ) then
    v_missing := array_append(v_missing, 'held_amounts.category_id');
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'held_transaction_kind_allowed'
      and conrelid = 'app_finance.held_amounts'::regclass
  ) then
    v_missing := array_append(v_missing, 'held_transaction_kind_allowed');
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'held_kind_matches_direction'
      and conrelid = 'app_finance.held_amounts'::regclass
  ) then
    v_missing := array_append(v_missing, 'held_kind_matches_direction');
  end if;

  if to_regprocedure(
    'app_finance.save_held_amount(app_finance.transaction_kind,bigint,text,text,date,text,text,uuid,uuid,uuid,uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'typed save_held_amount');
  end if;
  if to_regprocedure(
    'app_finance.save_held_amount(app_finance.held_amount_direction,bigint,text,text,date,text,text,uuid,uuid,uuid)'
  ) is not null then
    raise exception 'Legacy direction-based save_held_amount overload remains';
  end if;
  if to_regprocedure(
    'app_finance.set_held_amount_settled(uuid,date)'
  ) is null then
    v_missing := array_append(v_missing, 'set_held_amount_settled');
  end if;
  if to_regprocedure('app_finance.delete_held_amount(uuid)') is null then
    v_missing := array_append(v_missing, 'delete_held_amount');
  end if;

  if to_regclass('app_finance.credit_facility_settings') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_facility_settings');
  end if;
  if to_regclass('app_finance.installment_plans') is null then
    v_missing := array_append(v_missing, 'app_finance.installment_plans');
  end if;
  if to_regclass('app_finance.installment_dues') is null then
    v_missing := array_append(v_missing, 'app_finance.installment_dues');
  end if;
  if to_regclass('app_finance.installment_payment_allocations') is null then
    v_missing := array_append(
      v_missing, 'app_finance.installment_payment_allocations');
  end if;
  if to_regclass('app_finance.credit_facility_summaries') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_facility_summaries');
  end if;
  if to_regclass('app_finance.installment_due_statuses') is null then
    v_missing := array_append(
      v_missing, 'app_finance.installment_due_statuses');
  end if;
  if to_regclass('app_finance.installment_plan_revisions') is null then
    v_missing := array_append(
      v_missing, 'app_finance.installment_plan_revisions');
  end if;
  if to_regclass('app_finance.credit_card_statement_cycles') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_statement_cycles');
  end if;
  if to_regclass('app_finance.credit_card_statement_items') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_statement_items');
  end if;
  if to_regclass('app_finance.credit_card_statement_allocations') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_statement_allocations');
  end if;
  if to_regclass('app_finance.credit_card_statement_item_allocations')
      is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_statement_item_allocations');
  end if;
  if to_regclass('app_finance.credit_card_statement_item_statuses') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_statement_item_statuses');
  end if;
  if to_regclass('app_finance.facility_payment_allocations') is null then
    v_missing := array_append(
      v_missing, 'app_finance.facility_payment_allocations');
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_finance' and p.proname = 'pay_credit_facility_v2'
  ) then
    v_missing := array_append(
      v_missing, 'app_finance.pay_credit_facility_v2');
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_finance' and p.proname = 'facility_due_breakdown'
  ) then
    v_missing := array_append(
      v_missing, 'app_finance.facility_due_breakdown');
  end if;
  if to_regclass('app_finance.credit_card_fee_rules') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_fee_rules');
  end if;
  if to_regclass('app_finance.credit_card_fee_charges') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_fee_charges');
  end if;
  if to_regclass('app_finance.credit_card_statement_summaries') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_statement_summaries');
  end if;
  if to_regclass('app_core.push_devices') is null then
    v_missing := array_append(v_missing, 'app_core.push_devices');
  end if;
  if to_regclass('app_core.notification_preferences') is null then
    v_missing := array_append(
      v_missing, 'app_core.notification_preferences');
  end if;
  if to_regclass('app_core.notification_outbox') is null then
    v_missing := array_append(v_missing, 'app_core.notification_outbox');
  end if;

  if to_regprocedure(
    'app_finance.create_installment_plan(uuid,text,uuid,date,bigint,integer,date,bigint,uuid,bigint,bigint,text,uuid,app_finance.plan_pricing_method,bigint,integer,app_finance.interest_rate_period,app_finance.interest_method,bigint,bigint,date,integer,date,date,boolean,boolean,bigint,date,text)'
  ) is null then
    v_missing := array_append(v_missing, 'create_installment_plan');
  end if;
  if to_regprocedure(
    'app_finance.create_installment_plan(uuid,text,uuid,date,bigint,integer,date,bigint,uuid,bigint,bigint,text,uuid)'
  ) is not null then
    raise exception 'Legacy create_installment_plan overload remains';
  end if;
  if to_regprocedure(
    'app_finance.save_credit_facility(text,app_finance.account_type,text,bigint,smallint,smallint,text,smallint,text,uuid,app_finance.facility_status,app_finance.min_payment_method,bigint,integer,text,integer,smallint,smallint,app_finance.min_payment_percentage_basis,boolean,boolean,boolean,bigint)'
  ) is null then
    v_missing := array_append(v_missing, 'save_credit_facility');
  end if;
  if to_regprocedure(
    'app_finance.save_credit_facility(text,app_finance.account_type,text,bigint,smallint,smallint,text,smallint,text,uuid,app_finance.facility_status,app_finance.min_payment_method,bigint,integer,text)'
  ) is not null then
    raise exception 'Legacy fx-markup-less save_credit_facility overload remains';
  end if;
  if to_regprocedure(
    'app_finance.save_credit_facility(text,app_finance.account_type,text,bigint,smallint,smallint,text,smallint,text,uuid,app_finance.facility_status,app_finance.min_payment_method,bigint,integer)'
  ) is not null then
    raise exception 'Legacy colourless save_credit_facility overload remains';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'credit_facility_settings'
      and column_name = 'color_hex'
  ) then
    v_missing := array_append(v_missing, 'credit_facility_settings.color_hex');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'credit_facility_settings'
      and column_name = 'fx_markup_basis_points'
  ) then
    v_missing := array_append(
      v_missing, 'credit_facility_settings.fx_markup_basis_points');
  end if;
  if to_regprocedure(
    'app_finance.save_credit_facility(text,app_finance.account_type,text,bigint,bigint,smallint,smallint,text,smallint,text,uuid)'
  ) is not null then
    raise exception 'Legacy opening-owed save_credit_facility overload remains';
  end if;
  if to_regprocedure(
    'app_finance.update_installment_plan(uuid,text,uuid,date,bigint,integer,date,bigint,uuid,bigint,bigint,text,app_finance.plan_pricing_method,bigint,integer,app_finance.interest_rate_period,app_finance.interest_method,bigint,date,integer)'
  ) is null then
    v_missing := array_append(v_missing, 'update_installment_plan');
  end if;
  if to_regprocedure(
    'app_finance.restructure_installment_plan(uuid,bigint,integer,date,text,date)'
  ) is null then
    v_missing := array_append(v_missing, 'restructure_installment_plan');
  end if;
  if to_regprocedure(
    'app_finance.delete_credit_facility(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'delete_credit_facility');
  end if;
  if to_regprocedure(
    'app_finance.set_credit_facility_status(uuid,app_finance.facility_status)'
  ) is null then
    v_missing := array_append(v_missing, 'set_credit_facility_status');
  end if;
  if to_regprocedure(
    'app_finance.charge_credit_card(uuid,text,uuid,date,bigint,text,uuid,'
    'app_finance.card_transaction_subtype,boolean,boolean,bigint,text,numeric)'
  ) is null then
    v_missing := array_append(v_missing, 'charge_credit_card');
  end if;
  if to_regprocedure(
    'app_finance.charge_credit_card(uuid,text,uuid,date,bigint,text,uuid)'
  ) is not null then
    raise exception 'Legacy 7-arg charge_credit_card overload remains';
  end if;
  if to_regprocedure(
    'app_finance.save_credit_card_fee_rule(uuid,text,app_finance.card_fee_type,uuid,app_finance.card_rule_state,app_finance.card_rule_trigger,date,app_finance.card_rule_calculation_type,bigint,integer,app_finance.fee_percent_basis,bigint,bigint,integer,app_finance.fee_frequency,app_finance.foreign_apply_when,bigint,integer,text,integer,text,uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'save_credit_card_fee_rule');
  end if;
  if to_regprocedure(
    'app_finance.create_fee_rule_version(uuid,date,app_finance.card_rule_calculation_type,bigint,integer,app_finance.fee_percent_basis,bigint,bigint,integer,app_finance.fee_frequency,app_finance.foreign_apply_when,bigint,integer,text)'
  ) is null then
    v_missing := array_append(v_missing, 'create_fee_rule_version');
  end if;
  if to_regprocedure(
    'app_finance.cancel_fee_rule_version(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'cancel_fee_rule_version');
  end if;
  if to_regprocedure(
    'app_finance.apply_statement_penalty_fees(date)'
  ) is null then
    v_missing := array_append(v_missing, 'apply_statement_penalty_fees');
  end if;
  if to_regprocedure(
    'app_finance.reconcile_fee_charge(uuid,bigint,boolean,date,text)'
  ) is null then
    v_missing := array_append(v_missing, 'reconcile_fee_charge');
  end if;
  if to_regprocedure(
    'app_finance.highest_daily_balance_minor(uuid,date,integer)'
  ) is null then
    v_missing := array_append(v_missing, 'highest_daily_balance_minor');
  end if;
  if not exists (
    select 1 from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typnamespace = 'app_finance'::regnamespace
      and t.typname = 'foreign_apply_when'
      and e.enumlabel = 'foreign_merchant_home_currency'
  ) then
    v_missing := array_append(
      v_missing, 'foreign_apply_when.foreign_merchant_home_currency');
  end if;
  if not exists (
    select 1 from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typnamespace = 'app_finance'::regnamespace
      and t.typname = 'fee_percent_basis'
      and e.enumlabel = 'highest_daily_balance_lookback'
  ) then
    v_missing := array_append(
      v_missing, 'fee_percent_basis.highest_daily_balance_lookback');
  end if;
  if to_regprocedure('app_finance.apply_credit_card_fees(date)') is null then
    v_missing := array_append(v_missing, 'apply_credit_card_fees');
  end if;
  if to_regprocedure(
    'app_finance.charge_liability_account(uuid,text,uuid,date,bigint,text,uuid,boolean)'
  ) is null then
    v_missing := array_append(v_missing, 'charge_liability_account');
  end if;
  if to_regprocedure(
    'app_finance.charge_liability_account(uuid,text,uuid,date,bigint,text,uuid)'
  ) is not null then
    raise exception
      'Legacy fx-switch-less charge_liability_account overload remains';
  end if;
  if to_regprocedure(
    'app_finance.update_expense_transaction(uuid,uuid,date,bigint,uuid,text,text,text,boolean)'
  ) is null then
    v_missing := array_append(v_missing, 'update_expense_transaction');
  end if;
  if to_regprocedure(
    'app_finance.update_expense_transaction(uuid,uuid,date,bigint,uuid,text,text,text)'
  ) is not null then
    raise exception
      'Legacy fx-switch-less update_expense_transaction overload remains';
  end if;
  if to_regprocedure(
    'app_finance.delete_ledger_transaction(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'delete_ledger_transaction');
  end if;
  if to_regclass('app_finance.credit_card_fx_markup_charges') is null then
    v_missing := array_append(
      v_missing, 'app_finance.credit_card_fx_markup_charges');
  end if;
  if to_regclass('app_finance.facility_activity_items') is null then
    v_missing := array_append(
      v_missing, 'app_finance.facility_activity_items');
  end if;
  if to_regprocedure(
    'app_finance.pay_credit_facility(uuid,uuid,bigint,date,jsonb,text,uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'pay_credit_facility');
  end if;

  if to_regclass('app_finance.recurring_rules') is null then
    v_missing := array_append(v_missing, 'app_finance.recurring_rules');
  end if;
  if to_regclass('app_finance.recurring_occurrences') is null then
    v_missing := array_append(
      v_missing, 'app_finance.recurring_occurrences');
  end if;
  if to_regprocedure(
    'app_finance.save_recurring_rule(text,app_finance.recurring_rule_kind,bigint,app_finance.recurring_frequency,smallint,date,smallint,uuid,uuid,uuid,text,uuid,boolean,boolean)'
  ) is null then
    v_missing := array_append(v_missing, 'save_recurring_rule');
  end if;
  if to_regprocedure(
    'app_finance.save_recurring_rule(text,app_finance.recurring_rule_kind,bigint,app_finance.recurring_frequency,smallint,date,smallint,uuid,uuid,uuid,text,uuid,boolean)'
  ) is not null then
    raise exception
      'Ambiguous 13-parameter save_recurring_rule overload remains';
  end if;
  if to_regprocedure(
    'app_finance.materialize_recurring_occurrences(date)'
  ) is null then
    v_missing := array_append(
      v_missing, 'materialize_recurring_occurrences');
  end if;
  if to_regprocedure(
    'app_finance.accept_recurring_occurrence(uuid,bigint,date,text)'
  ) is null then
    v_missing := array_append(v_missing, 'accept_recurring_occurrence');
  end if;
  if to_regprocedure(
    'app_finance.skip_recurring_occurrence(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'skip_recurring_occurrence');
  end if;
  if to_regprocedure(
    'app_finance.snooze_recurring_occurrence(uuid,timestamptz)'
  ) is null then
    v_missing := array_append(v_missing, 'snooze_recurring_occurrence');
  end if;
  if to_regprocedure(
    'app_finance.delete_transaction_category(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'delete_transaction_category');
  end if;
  if to_regprocedure(
    'app_finance.accept_income_occurrence_partial(uuid,bigint,bigint,date,text,uuid)'
  ) is null then
    v_missing := array_append(
      v_missing, 'accept_income_occurrence_partial');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'income_occurrences'
      and column_name = 'remainder_of_occurrence_id'
  ) then
    v_missing := array_append(
      v_missing, 'income_occurrences.remainder_of_occurrence_id');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'accounts'
      and column_name = 'hide_from_home'
  ) then
    v_missing := array_append(v_missing, 'accounts.hide_from_home');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'account_balances'
      and column_name = 'hide_from_home'
  ) then
    v_missing := array_append(v_missing, 'account_balances.hide_from_home');
  end if;
  if to_regprocedure(
    'app_finance.reverse_facility_payment(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'reverse_facility_payment');
  end if;
  if to_regprocedure(
    'app_finance.cancel_installment_plan(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'cancel_installment_plan');
  end if;
  if to_regprocedure('app_reports.debt_summary(date,date)') is null then
    v_missing := array_append(v_missing, 'app_reports.debt_summary');
  end if;

  -- Finance Suit Network
  if to_regclass('app_finance.network_add_requests') is null then
    v_missing := array_append(v_missing, 'app_finance.network_add_requests');
  end if;
  if to_regclass('app_finance.network_connections') is null then
    v_missing := array_append(v_missing, 'app_finance.network_connections');
  end if;
  if to_regclass('app_finance.network_transfers') is null then
    v_missing := array_append(v_missing, 'app_finance.network_transfers');
  end if;
  if not exists (
    select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'network_add_request_status'
  ) then
    v_missing := array_append(v_missing, 'network_add_request_status enum');
  end if;
  if not exists (
    select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'network_transfer_status'
  ) then
    v_missing := array_append(v_missing, 'network_transfer_status enum');
  end if;
  if not exists (
    select 1 from pg_type
    where typnamespace = 'app_finance'::regnamespace
      and typname = 'network_transfer_origin'
  ) then
    v_missing := array_append(v_missing, 'network_transfer_origin enum');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'financial_transactions'
      and column_name = 'network_transfer_id'
  ) then
    v_missing := array_append(
      v_missing, 'financial_transactions.network_transfer_id');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'financial_transactions'
      and column_name = 'is_network_transfer'
  ) then
    v_missing := array_append(
      v_missing, 'financial_transactions.is_network_transfer');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'recurring_rules'
      and column_name = 'destination_network_connection_id'
  ) then
    v_missing := array_append(
      v_missing, 'recurring_rules.destination_network_connection_id');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'income_source_allocations'
      and column_name = 'destination_network_connection_id'
  ) then
    v_missing := array_append(
      v_missing, 'income_source_allocations.destination_network_connection_id');
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app_finance'
      and table_name = 'income_sources'
      and column_name = 'extra_work_destination_network_connection_id'
  ) then
    v_missing := array_append(
      v_missing,
      'income_sources.extra_work_destination_network_connection_id');
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'tx_direction_by_kind'
      and conrelid = 'app_finance.financial_transactions'::regclass
  ) then
    v_missing := array_append(v_missing, 'tx_direction_by_kind');
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'network_transfers_state_fields'
      and conrelid = 'app_finance.network_transfers'::regclass
  ) then
    v_missing := array_append(v_missing, 'network_transfers_state_fields');
  end if;
  if to_regprocedure('app_finance.search_network_users(text)') is null then
    v_missing := array_append(v_missing, 'search_network_users');
  end if;
  if to_regprocedure(
    'app_finance.send_network_add_request(uuid,text)'
  ) is null then
    v_missing := array_append(v_missing, 'send_network_add_request');
  end if;
  if to_regprocedure(
    'app_finance.accept_network_add_request(uuid,text)'
  ) is null then
    v_missing := array_append(v_missing, 'accept_network_add_request');
  end if;
  if to_regprocedure(
    'app_finance.reject_network_add_request(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'reject_network_add_request');
  end if;
  if to_regprocedure('app_finance.list_network_add_requests()') is null then
    v_missing := array_append(v_missing, 'list_network_add_requests');
  end if;
  if to_regprocedure('app_finance.list_network_contacts()') is null then
    v_missing := array_append(v_missing, 'list_network_contacts');
  end if;
  if to_regprocedure(
    'app_finance.rename_network_contact(uuid,text)'
  ) is null then
    v_missing := array_append(v_missing, 'rename_network_contact');
  end if;
  if to_regprocedure(
    'app_finance.remove_network_connection(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'remove_network_connection');
  end if;
  if to_regprocedure(
    'app_finance.create_network_transfer_request(uuid,uuid,bigint,date,text,app_finance.network_transfer_origin,uuid,text)'
  ) is null then
    v_missing := array_append(v_missing, 'create_network_transfer_request');
  end if;
  if to_regprocedure(
    'app_finance.accept_network_transfer(uuid,uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'accept_network_transfer');
  end if;
  if to_regprocedure(
    'app_finance.reject_network_transfer(uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'reject_network_transfer');
  end if;
  if to_regprocedure('app_finance.list_network_transfers()') is null then
    v_missing := array_append(v_missing, 'list_network_transfers');
  end if;
  if to_regprocedure(
    'app_finance.save_recurring_rule_v2(text,app_finance.recurring_rule_kind,bigint,app_finance.recurring_frequency,smallint,date,smallint,uuid,uuid,uuid,uuid,text,uuid,boolean,boolean)'
  ) is null then
    v_missing := array_append(v_missing, 'save_recurring_rule_v2');
  end if;
  if to_regprocedure(
    'app_finance.save_income_source_v5(text,app_finance.income_source_kind,bigint,text,smallint,date,smallint,uuid,uuid,jsonb,text,uuid,boolean,boolean,uuid,uuid,boolean,uuid)'
  ) is null then
    v_missing := array_append(v_missing, 'save_income_source_v5');
  end if;
  -- Network tables must not be broadly writable by clients.
  if has_table_privilege(
    'authenticated', 'app_finance.network_transfers', 'insert'
  ) then
    raise exception 'network_transfers must not be client-writable';
  end if;
  if has_table_privilege(
    'authenticated', 'app_finance.network_connections', 'update'
  ) then
    raise exception 'network_connections must not be client-writable';
  end if;

  if cardinality(v_missing) > 0 then
    raise exception 'Missing required Finance Suit objects: %',
      array_to_string(v_missing, ', ');
  end if;

  select count(*)::integer
    into v_without_rls
  from pg_tables
  where schemaname like 'app\_%' escape '\'
    and rowsecurity = false;

  if v_without_rls <> 0 then
    raise exception '% private app_* tables do not have RLS enabled',
      v_without_rls;
  end if;

  raise notice 'finance_suit_schema_verified: % RLS-protected app_* tables',
    (
      select count(*)
      from pg_tables
      where schemaname like 'app\_%' escape '\'
        and rowsecurity
    );
end;
$$;
