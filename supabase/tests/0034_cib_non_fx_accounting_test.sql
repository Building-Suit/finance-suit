begin;
create extension if not exists pgtap with schema extensions;

select plan(41);

select has_function('app_finance', 'installment_amortization_schedule',
  'exact amortization schedule exists');
select results_eq(
  $$select count(*)::integer, sum(principal_minor)::bigint,
      sum(interest_minor)::bigint, sum(scheduled_payment_minor)::bigint,
      max(closing_principal_minor) filter (where sequence_number = 36)
    from app_finance.installment_amortization_schedule(
      1300000, 686734, 0, 36, 250, 'monthly', 'reducing')$$,
  $$values (36, 1300000::bigint, 686734::bigint, 1986734::bigint,
    0::bigint)$$,
  'Samsung schedule reconciles every contractual total and ends at zero');
select results_eq(
  $$select closing_principal_minor
    from app_finance.installment_amortization_schedule(
      1300000, 686734, 0, 36, 250, 'monthly', 'reducing')
    where sequence_number = 27$$,
  $$values (439888::bigint)$$,
  '27 paid Samsung periods leave deterministic calculated principal');
select results_eq(
  $$select scheduled_payment_minor
    from app_finance.installment_amortization_schedule(
      1300000, 686734, 0, 36, 250, 'monthly', 'reducing')
    where sequence_number = 1$$,
  $$values (55188::bigint)$$,
  'reducing monthly payment rounds to the bank schedule around EGP 551.87');
select results_eq(
  $$select cycle_start, cycle_close, due_on
    from app_finance.statement_bounds_for(31, 25, date '2026-07-14')$$,
  $$values (date '2026-07-01', date '2026-07-31', date '2026-08-25')$$,
  'end-of-month July closes July 31 and is due August 25');
select results_eq(
  $$select cycle_close, due_on
    from app_finance.statement_bounds_for(31, 25, date '2028-02-14')$$,
  $$values (date '2028-02-29', date '2028-03-25')$$,
  'end-of-month mode clamps correctly in leap-year February');
select results_eq(
  $$select cycle_close, due_on
    from app_finance.statement_bounds_for(31, 25, date '2026-02-14')$$,
  $$values (date '2026-02-28', date '2026-03-25')$$,
  'end-of-month mode clamps correctly in non-leap February');
select results_eq(
  $$select cycle_close, due_on
    from app_finance.statement_bounds_for(31, 25, date '2026-04-30')$$,
  $$values (date '2026-04-30', date '2026-05-25')$$,
  'end-of-month mode closes on April 30');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000081',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'cib-non-fx@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"CIB Non FX"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000081","role":"authenticated"}';

insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values
  ('00000000-0000-0000-0000-00000000c801',
   '00000000-0000-0000-0000-000000000081', 'Installments', 'expense'),
  ('00000000-0000-0000-0000-00000000c802',
   '00000000-0000-0000-0000-000000000081', 'Card purchases', 'expense'),
  ('00000000-0000-0000-0000-00000000c803',
   '00000000-0000-0000-0000-000000000081', 'Bank fees', 'expense'),
  ('00000000-0000-0000-0000-00000000c804',
   '00000000-0000-0000-0000-000000000081', 'Card interest', 'expense');

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000a801',
  '00000000-0000-0000-0000-000000000081',
  'Payment wallet', 'cash', 'EGP', 5000000
);

select lives_ok(
  $$select app_finance.save_credit_facility(
    p_name => 'CIB Gold Test', p_account_type => 'credit_card',
    p_currency_code => 'EGP', p_credit_limit_minor => 5000000,
    p_default_due_day => 25::smallint, p_statement_day => 25::smallint,
    p_last_four_digits => '6011',
    p_min_payment_method => 'percent',
    p_min_payment_basis_points => 500,
    p_installment_due_day => 25::smallint,
    p_min_payment_percentage_basis => 'revolving_noninstallment',
    p_min_payment_include_installment_dues => true,
    p_min_payment_include_bank_fees => true)$$,
  'card settings keep close, payment due, and installment day separate');

select lives_ok(
  $$select app_finance.create_installment_plan(
    p_account_id => (select id from app_finance.accounts
      where name = 'CIB Gold Test'),
    p_title => 'Samsung Monitor',
    p_category_id => '00000000-0000-0000-0000-00000000c801',
    p_purchased_on => date '2024-04-19',
    p_purchase_price_minor => 1300000,
    p_installment_count => 36, p_first_due_on => date '2024-05-25',
    p_pricing_method => 'interest_rate',
    p_interest_rate_basis_points => 250,
    p_interest_rate_period => 'monthly', p_interest_method => 'reducing',
    p_paid_installments => 27, p_import_as_of => date '2026-08-07',
    p_paid_through_on => date '2026-07-25')$$,
  'reducing historical import uses explicit as-of and paid count');
select results_eq(
  $$select remaining_principal_minor, remaining_scheduled_payments_minor,
      remaining_future_interest_minor
    from app_finance.installment_plan_summaries
    where title = 'Samsung Monitor'$$,
  $$values (439888::bigint, 496683::bigint, 56795::bigint)$$,
  'principal, scheduled payments, and future interest stay distinct');
select results_eq(
  $$select import_as_of, paid_through_on, financed_principal_minor,
      interest_rate_basis_points, installment_count
    from app_finance.installment_plan_summaries
    where title = 'Samsung Monitor'$$,
  $$values (date '2026-08-07', date '2026-07-25', 1300000::bigint,
    250, 36)$$,
  'historical import preserves explicit dates and original contractual terms');
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where destination_account_id = (select id from app_finance.accounts
      where name = 'CIB Gold Test') and transaction_kind = 'transfer'$$,
  $$values (0)$$,
  'historical paid installments do not fabricate cash repayments');
select results_eq(
  $$select outstanding_minor from app_finance.credit_facility_summaries
    where name = 'CIB Gold Test'$$,
  $$values (439888::bigint)$$,
  'future reducing interest does not consume available credit');
select lives_ok(
  $$select app_finance.reconcile_historical_installment_plan(
    (select id from app_finance.installment_plans
      where title = 'Samsung Monitor'), 27, date '2026-08-07', 439869,
    true, 'Reconciled to CIB snapshot dated 2026-08-07')$$,
  'Samsung calculated principal can be explicitly reconciled to bank actual');
select results_eq(
  $$select remaining_principal_minor, bank_reported_principal_minor
    from app_finance.installment_plan_summaries
    where title = 'Samsung Monitor'$$,
  $$values (439869::bigint, 439869::bigint)$$,
  'bank override is visible without changing contractual terms');

select throws_ok(
  $$select app_finance.create_installment_plan(
    p_account_id => (select id from app_finance.accounts
      where name = 'CIB Gold Test'), p_title => 'Future paid invalid',
    p_category_id => '00000000-0000-0000-0000-00000000c801',
    p_purchased_on => date '2026-03-17', p_purchase_price_minor => 1889900,
    p_installment_count => 18, p_first_due_on => date '2026-04-25',
    p_paid_installments => 5, p_import_as_of => date '2026-08-07')$$,
  'P0001', null, 'future installment cannot be silently presettled');
select lives_ok(
  $$select app_finance.create_installment_plan(
    p_account_id => (select id from app_finance.accounts
      where name = 'CIB Gold Test'), p_title => 'El Araby Makram Ebid',
    p_category_id => '00000000-0000-0000-0000-00000000c801',
    p_purchased_on => date '2026-03-17', p_purchase_price_minor => 1889900,
    p_installment_count => 18, p_first_due_on => date '2026-04-25',
    p_paid_installments => 4, p_import_as_of => date '2026-08-07',
    p_current_installment_posted => true,
    p_bank_reported_principal_minor => 1469924,
    p_reconciliation_as_of => date '2026-08-07')$$,
  'El Araby imports four paid installments and one current posted installment');
select results_eq(
  $$select remaining_principal_minor, paid_installments,
      current_posted_installments, future_installments,
      total_unpaid_installments
    from app_finance.installment_plan_summaries
    where title = 'El Araby Makram Ebid'$$,
  $$values (1469924::bigint, 4, 1, 13, 14)$$,
  'El Araby matches bank principal and explicit paid/current/future counts');
select results_eq(
  $$select is_presettled from app_finance.installment_dues d
    join app_finance.installment_plans p on p.id = d.plan_id
    where p.title = 'El Araby Makram Ebid' and d.due_on = date '2026-08-25'$$,
  $$values (false)$$,
  'August 25 is not marked as a historical payment on August 7');

select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  'July non-installment charges',
  '00000000-0000-0000-0000-00000000c802', date '2026-07-15',
  257376, null, null
);
select lives_ok(
  $$select app_finance.save_credit_facility(
    p_name => 'CIB Gold Test', p_account_type => 'credit_card',
    p_currency_code => 'EGP', p_credit_limit_minor => 5000000,
    p_default_due_day => 25::smallint, p_statement_day => 31::smallint,
    p_last_four_digits => '6011',
    p_account_id => (select id from app_finance.accounts
      where name = 'CIB Gold Test'),
    p_min_payment_method => 'percent', p_min_payment_basis_points => 500,
    p_installment_due_day => 25::smallint,
    p_min_payment_percentage_basis => 'revolving_noninstallment',
    p_min_payment_include_installment_dues => true,
    p_min_payment_include_bank_fees => true)$$,
  'changing close day rebuilds mutable statement history atomically');
select results_eq(
  $$select cycle_start, cycle_close, due_on
    from app_finance.credit_card_statement_summaries
    where account_id = (select id from app_finance.accounts
      where name = 'CIB Gold Test')$$,
  $$values (date '2026-07-01', date '2026-07-31', date '2026-08-25')$$,
  'July charge is relinked into the corrected month-end cycle');
select results_eq(
  $$select ordinary_statement_charges_minor, installment_due_minor,
      total_statement_due_minor
    from app_finance.credit_card_statement_summaries
    where cycle_close = date '2026-07-31'$$,
  $$values (257376::bigint, 160181::bigint, 417557::bigint)$$,
  'statement total includes dues without creating duplicate expenses');
select results_eq(
  $$select revolving_base_minor, minimum_due_minor
    from app_finance.credit_card_statement_summaries
    where cycle_close = date '2026-07-31'$$,
  $$values (257376::bigint, 173049::bigint)$$,
  'minimum is 5 percent of revolving base plus both installment dues');
select results_eq(
  $$select app_finance.rebuild_credit_card_statement_cycles(
    (select id from app_finance.accounts where name = 'CIB Gold Test'))$$,
  $$values (1)$$,
  'cycle relinking is safe to retry without duplicate items');

select lives_ok(
  $$select app_finance.create_installment_plan(
    p_account_id => (select id from app_finance.accounts
      where name = 'CIB Gold Test'), p_title => 'Explicit early prepayment',
    p_category_id => '00000000-0000-0000-0000-00000000c801',
    p_purchased_on => date '2026-03-17', p_purchase_price_minor => 1889900,
    p_installment_count => 18, p_first_due_on => date '2026-04-25',
    p_paid_installments => 5, p_import_as_of => date '2026-08-07',
    p_allow_future_presettlement => true)$$,
  'future installment requires and accepts an explicit prepayment path');
select results_eq(
  $$select is_presettled from app_finance.installment_dues d
    join app_finance.installment_plans p on p.id = d.plan_id
    where p.title = 'Explicit early prepayment'
      and d.due_on = date '2026-08-25'$$,
  $$values (true)$$,
  'explicit early-prepayment confirmation is retained on the future due');

select app_finance.save_credit_card_fee_rule(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  'Stamp Duty', 'stamp_tax', '00000000-0000-0000-0000-00000000c803',
  'configured', 'schedule', date '2026-07-01', 'percentage', null, 5,
  'highest_statement_due_lookback', null, null, 3, 'quarterly', null,
  null, null, null, 100, null, null
);
select lives_ok(
  $$select app_finance.record_actual_card_charge(
    (select id from app_finance.accounts where name = 'CIB Gold Test'),
    (select id from app_finance.credit_card_fee_rules where name = 'Stamp Duty'),
    date '2026-07-01', 1312, 'test:stamp:2026-07-01',
    'Actual from CIB activity')$$,
  'historical stamp duty records the bank-confirmed actual');
select app_finance.record_actual_card_charge(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  (select id from app_finance.credit_card_fee_rules where name = 'Stamp Duty'),
  date '2026-07-01', 1312, 'test:stamp:2026-07-01', 'retry'
);
select results_eq(
  $$select count(*)::integer, max(actual_amount_minor)::bigint
    from app_finance.credit_card_fee_charges
    where reconciliation_key = 'test:stamp:2026-07-01'$$,
  $$values (1, 1312::bigint)$$,
  'actual stamp reconciliation is idempotent');
select results_eq(
  $$select next_charge_on from app_finance.credit_card_fee_rules
    where name = 'Stamp Duty'$$,
  $$values (date '2026-10-01')$$,
  'confirmed quarterly stamp occurrence advances the next schedule once');

select app_finance.configure_purchase_interest_rule(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  '00000000-0000-0000-0000-00000000c804', 'unknown', date '2026-08-01',
  null, 'monthly', 'bank_posted_manual', 'grace_expiry', null, true,
  'Future formula remains unknown; record bank actuals'
);
select results_eq(
  $$select fee_type::text, trigger_kind::text, state::text
    from app_finance.credit_card_fee_rules
    where name = 'Purchase / revolving interest'$$,
  $$values ('purchase_interest'::text, 'statement_interest'::text,
    'unknown'::text)$$,
  'purchase interest has dedicated semantic rule and trigger types');
select app_finance.record_actual_card_charge(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  (select id from app_finance.credit_card_fee_rules
    where name = 'Purchase / revolving interest'),
  date '2026-08-01', 10996, 'test:interest:2026-08-01',
  'Actual CIB Month.Interest posted 2026-08-01'
);
select results_eq(
  $$select c.actual_amount_minor, s.cycle_start, s.cycle_close
    from app_finance.credit_card_fee_charges c
    join app_finance.credit_card_statement_cycles s
      on s.id = c.statement_cycle_id
    where c.reconciliation_key = 'test:interest:2026-08-01'$$,
  $$values (10996::bigint, date '2026-08-01', date '2026-08-31')$$,
  'August 1 interest actual belongs to the August cycle, not July');
select app_finance.record_actual_card_charge(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  (select id from app_finance.credit_card_fee_rules
    where name = 'Purchase / revolving interest'),
  date '2026-08-01', 10996, 'test:interest:2026-08-01', 'retry'
);
select results_eq(
  $$select count(*)::integer from app_finance.credit_card_fee_charges
    where reconciliation_key = 'test:interest:2026-08-01'$$,
  $$values (1)$$,
  'bank-posted interest actual is idempotent and never double-expensed');
select app_finance.configure_purchase_interest_rule(
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  '00000000-0000-0000-0000-00000000c804', 'configured', date '2026-09-01',
  399, 'monthly', 'bank_posted_manual', 'grace_expiry', 0::smallint, true,
  'Later tariff version',
  (select id from app_finance.credit_card_fee_rules
    where name = 'Purchase / revolving interest')
);
select results_eq(
  $$select version_number, effective_from, effective_until
    from app_finance.credit_card_fee_rule_versions v
    join app_finance.credit_card_fee_rules r on r.id = v.rule_id
    where r.name = 'Purchase / revolving interest'
    order by version_number$$,
  $$values (1, date '2026-08-01', date '2026-09-01'),
      (2, date '2026-09-01', null::date)$$,
  'purchase-interest tariff changes preserve effective-dated history');

insert into app_finance.financial_transactions (
  id, user_id, transaction_kind, occurred_on, amount_minor, currency_code,
  source_account_id, category_id, title
) values (
  '00000000-0000-0000-0000-00000000f801',
  '00000000-0000-0000-0000-000000000081', 'expense', date '2026-07-14',
  412507, 'EGP', '00000000-0000-0000-0000-00000000a801',
  '00000000-0000-0000-0000-00000000c803', 'CIB Credit Card'
);
create temporary table before_payment_outstanding as
select outstanding_minor from app_finance.credit_facility_summaries
where name = 'CIB Gold Test';
select lives_ok(
  $$select app_finance.correct_historical_facility_payment(
    '00000000-0000-0000-0000-00000000f801',
    (select id from app_finance.accounts where name = 'CIB Gold Test'),
    412507, 'test:historical-payment:2026-07-14',
    'Reclassified from expense using matching pre-tracking obligation')$$,
  'historical payment is reclassified through the guarded repair flow');
select results_eq(
  $$select f.outstanding_minor
    from app_finance.credit_facility_summaries f
    where f.name = 'CIB Gold Test'$$,
  $$select outstanding_minor from before_payment_outstanding$$,
  'matching historical obligation prevents a second current-liability reduction');
select results_eq(
  $$select record_type::text from app_reports.history_items
    where id = '00000000-0000-0000-0000-00000000f801'$$,
  $$values ('transfer'::text)$$,
  'corrected payment is excluded from expense history classification');
select results_eq(
  $$select count(*)::integer from app_reports.history_items
    where id = '00000000-0000-0000-0000-00000000f801'
      and record_type = 'expense'$$,
  $$values (0)$$,
  'the repayment no longer contributes an ordinary expense row');
select results_eq(
  $$select activity_kind::text from app_finance.facility_activity_items
    where transaction_id = '00000000-0000-0000-0000-00000000f801'$$,
  $$values ('facility_repayment'::text)$$,
  'Related activity classifies the correction as a facility repayment');
select results_eq(
  $$select count(*)::integer from app_finance.historical_facility_obligations
    where repair_key = 'test:historical-payment:2026-07-14'$$,
  $$values (1)$$,
  'historical correction keeps exactly one auditable matching obligation');
select app_finance.correct_historical_facility_payment(
  '00000000-0000-0000-0000-00000000f801',
  (select id from app_finance.accounts where name = 'CIB Gold Test'),
  412507, 'test:historical-payment:2026-07-14', 'retry'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where id = '00000000-0000-0000-0000-00000000f801'
      and transaction_kind = 'transfer'$$,
  $$values (1)$$,
  'historical repayment correction is idempotent and keeps one asset outflow');

select * from finish();
rollback;
