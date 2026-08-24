begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000055',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'roll-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Roll Owner"}', now(), now()
);

-- ---------------------------------------------------------------------------
-- The next-bill rule
-- ---------------------------------------------------------------------------

select results_eq(
  $$select app_finance.bnpl_next_bill_on(5::smallint, date '2026-08-05')$$,
  $$values (date '2026-08-05')$$,
  'on the billing day the bill is today, not next month'
);
select results_eq(
  $$select app_finance.bnpl_next_bill_on(5::smallint, date '2026-08-06')$$,
  $$values (date '2026-09-05')$$,
  'after the billing day the next bill is next month'
);
select results_eq(
  $$select app_finance.bnpl_next_bill_on(31::smallint, date '2026-02-10')$$,
  $$values (date '2026-02-28')$$,
  'day 31 clamps to the end of February'
);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000055","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-000000055a01',
  '00000000-0000-0000-0000-000000000055', 'Roll Wallet', 'cash', 'EGP',
  100000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-000000055c01',
  '00000000-0000-0000-0000-000000000055', 'Roll Shopping', 'expense'
);

select app_finance.save_credit_facility(
  'Roll Card', 'credit_card', 'EGP', 2000000, 25::smallint,
  p_statement_day => 10::smallint);
select app_finance.save_credit_facility(
  'Roll Valu', 'bnpl', 'EGP', 2000000, 5::smallint);

-- ---------------------------------------------------------------------------
-- A card purchase books at any time and rolls onto the next open statement
-- ---------------------------------------------------------------------------

-- The March statement: one charge, closed on the 10th, paid in full.
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Roll Card'),
  'March Groceries', '00000000-0000-0000-0000-000000055c01',
  date '2026-03-05', 70000, null, '00000000-0000-0000-0000-000000055f01');
select results_eq(
  $$select c.cycle_close
    from app_finance.credit_card_statement_items si
    join app_finance.credit_card_statement_cycles c on c.id = si.cycle_id
    where si.transaction_id = '00000000-0000-0000-0000-000000055f01'$$,
  $$values (date '2026-03-10')$$,
  'a charge inside an unpaid cycle joins that cycle'
);
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Roll Card'),
  '00000000-0000-0000-0000-000000055a01', 70000, date '2026-03-12',
  null, null, '00000000-0000-0000-0000-000000055901');
select results_eq(
  $$select count(*)::integer
    from app_finance.credit_card_statement_allocations al
    join app_finance.credit_card_statement_cycles c on c.id = al.cycle_id
    where al.payment_transaction_id = '00000000-0000-0000-0000-000000055901'
      and c.cycle_close = date '2026-03-10'$$,
  $$values (1)$$,
  'the payment settled the March statement'
);

-- A late-logged purchase dated inside the paid statement is not refused: it
-- books and rides the next statement instead.
select lives_ok(
  $$select app_finance.charge_liability_account(
      (select id from app_finance.accounts where name = 'Roll Card'),
      'Old Bill', '00000000-0000-0000-0000-000000055c01',
      date '2026-03-06', 40000, null,
      '00000000-0000-0000-0000-000000055f02')$$,
  'a purchase dated inside a paid statement still books'
);
select results_eq(
  $$select c.cycle_close
    from app_finance.credit_card_statement_items si
    join app_finance.credit_card_statement_cycles c on c.id = si.cycle_id
    where si.transaction_id = '00000000-0000-0000-0000-000000055f02'$$,
  $$values (date '2026-04-10')$$,
  'the late-logged purchase joins the next open statement'
);

-- The recurring-charge path (charge_credit_card) rolls the same way.
select app_finance.charge_credit_card(
  (select id from app_finance.accounts where name = 'Roll Card'),
  'Subscription', '00000000-0000-0000-0000-000000055c01',
  date '2026-03-07', 50000, null, '00000000-0000-0000-0000-000000055f03');
select results_eq(
  $$select c.cycle_close
    from app_finance.credit_card_statement_items si
    join app_finance.credit_card_statement_cycles c on c.id = si.cycle_id
    where si.transaction_id = '00000000-0000-0000-0000-000000055f03'$$,
  $$values (date '2026-04-10')$$,
  'charge_credit_card also skips the paid statement'
);

-- Re-dating a rolled charge to another day of the paid cycle keeps rolling.
select lives_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-000000055f02',
      (select id from app_finance.accounts where name = 'Roll Card'),
      date '2026-03-08', 40000, '00000000-0000-0000-0000-000000055c01')$$,
  'an edit that targets a paid statement is not refused'
);
select results_eq(
  $$select c.cycle_close
    from app_finance.credit_card_statement_items si
    join app_finance.credit_card_statement_cycles c on c.id = si.cycle_id
    where si.transaction_id = '00000000-0000-0000-0000-000000055f02'$$,
  $$values (date '2026-04-10')$$,
  'the edited charge stays on the next open statement'
);

-- Paid history itself stays immutable: a charge already sitting on a paid
-- statement is still corrected through the reversal flow, never in place.
select throws_ok(
  $$select app_finance.update_expense_transaction(
      '00000000-0000-0000-0000-000000055f01',
      (select id from app_finance.accounts where name = 'Roll Card'),
      date '2026-03-05', 99000, '00000000-0000-0000-0000-000000055c01')$$,
  'P0001', null, 'a charge inside a paid statement still cannot be re-priced'
);

-- With April paid too, a new backdated charge rolls past both cycles.
select app_finance.pay_credit_facility(
  (select id from app_finance.accounts where name = 'Roll Card'),
  '00000000-0000-0000-0000-000000055a01', 30000, date '2026-04-12',
  null, null, '00000000-0000-0000-0000-000000055902');
select results_eq(
  $$select count(*)::integer
    from app_finance.credit_card_statement_allocations al
    join app_finance.credit_card_statement_cycles c on c.id = al.cycle_id
    where al.payment_transaction_id = '00000000-0000-0000-0000-000000055902'
      and c.cycle_close = date '2026-04-10'$$,
  $$values (1)$$,
  'the second payment settled into the April statement'
);
select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Roll Card'),
  'Very Old Bill', '00000000-0000-0000-0000-000000055c01',
  date '2026-03-09', 20000, null, '00000000-0000-0000-0000-000000055f04');
select results_eq(
  $$select c.cycle_close
    from app_finance.credit_card_statement_items si
    join app_finance.credit_card_statement_cycles c on c.id = si.cycle_id
    where si.transaction_id = '00000000-0000-0000-0000-000000055f04'$$,
  $$values (date '2026-05-10')$$,
  'a backdated charge rolls past every paid statement to the open one'
);

-- ---------------------------------------------------------------------------
-- An unpaid BNPL purchase rides the next bill instead of going late
-- ---------------------------------------------------------------------------

select app_finance.charge_liability_account(
  (select id from app_finance.accounts where name = 'Roll Valu'),
  'Old Valu Purchase', '00000000-0000-0000-0000-000000055c01',
  date '2026-03-02', 60000, null, '00000000-0000-0000-0000-000000055f05');
select results_eq(
  $$select due_on from app_finance.bnpl_purchase_obligations
    where transaction_id = '00000000-0000-0000-0000-000000055f05'$$,
  $$values (date '2026-04-05')$$,
  'the stored bill is the due day of the month after the purchase'
);
select results_eq(
  $$select due_on from app_finance.bnpl_purchase_obligation_statuses
    where transaction_id = '00000000-0000-0000-0000-000000055f05'$$,
  $$values (app_finance.bnpl_next_bill_on(5::smallint, current_date))$$,
  'an unpaid obligation whose bill passed rides the next upcoming bill'
);
select results_eq(
  $$select due_status
    from app_finance.bnpl_purchase_obligation_statuses
    where transaction_id = '00000000-0000-0000-0000-000000055f05'
      and due_status in ('due_today', 'upcoming')$$,
  $$select due_status
    from app_finance.bnpl_purchase_obligation_statuses
    where transaction_id = '00000000-0000-0000-0000-000000055f05'$$,
  'a missed bill is never reported as overdue, it moved to the next bill'
);

select lives_ok(
  $$select app_finance.pay_credit_facility_v2(
      (select id from app_finance.accounts where name = 'Roll Valu'),
      '00000000-0000-0000-0000-000000055a01',
      60000, current_date,
      jsonb_build_array(jsonb_build_object('type', 'bnpl_purchase',
        'id', (select obligation_id
          from app_finance.bnpl_purchase_obligation_statuses
          where transaction_id = '00000000-0000-0000-0000-000000055f05'),
        'amount_minor', 60000)),
      null, '00000000-0000-0000-0000-000000055903')$$,
  'the rolled obligation is payable on its next bill'
);
select results_eq(
  $$select due_on, due_status
    from app_finance.bnpl_purchase_obligation_statuses
    where transaction_id = '00000000-0000-0000-0000-000000055f05'$$,
  $$values (date '2026-04-05', 'paid'::text)$$,
  'a paid obligation keeps the bill it was settled against'
);

select * from finish();
rollback;
