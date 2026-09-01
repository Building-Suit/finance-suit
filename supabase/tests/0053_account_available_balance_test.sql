begin;
create extension if not exists pgtap with schema extensions;

select plan(19);

-- ---------------------------------------------------------------------------
-- Users, accounts, connection
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000531',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'avail-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Avail Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000532',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'avail-peer@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Avail Peer"}', now(), now()
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-00000000b531',
   '00000000-0000-0000-0000-000000000531', 'Cash', 'cash', 'EGP', 100000),
  ('00000000-0000-0000-0000-00000000b532',
   '00000000-0000-0000-0000-000000000532', 'Wallet', 'wallet', 'EGP', 0);

insert into app_finance.network_connections (
  id, user_a_id, user_b_id, user_a_alias_for_b, user_b_alias_for_a
) values (
  '00000000-0000-0000-0000-00000000c531',
  '00000000-0000-0000-0000-000000000531',
  '00000000-0000-0000-0000-000000000532',
  'Peer Alias', 'Owner Alias'
);

select has_view('app_finance', 'account_hold_totals',
  'the owner-context hold totals view exists');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000531","role":"authenticated"}';

select lives_ok(
  $$select app_finance.create_network_transfer_request(
      '00000000-0000-0000-0000-00000000c531', '00000000-0000-0000-0000-00000000b531',
      30000, current_date, null, 'manual', null, 'avail:t1')$$,
  'a pending outgoing transfer exists'
);

-- ---------------------------------------------------------------------------
-- The regression that matters most
-- ---------------------------------------------------------------------------

-- app_finance.network_transfers withholds sender_source_account_id from
-- `authenticated`. app_private.enforce_account_balance is SECURITY INVOKER and
-- reads this view on every transaction insert, so if the pending-hold
-- aggregate ever moves into the security_invoker view it raises 42501 here and
-- every financial write in the app stops working.
select lives_ok(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b531'$$,
  'an authenticated caller can still read balance_minor with a pending transfer'
);

select lives_ok(
  $$select * from app_finance.account_balances$$,
  'and can read every new column'
);

select lives_ok(
  $$insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, title
    ) values (
      '00000000-0000-0000-0000-000000000531', 'expense', current_date, 1000,
      'EGP', '00000000-0000-0000-0000-00000000b531', 'probe')$$,
  'and can still insert a transaction through enforce_account_balance'
);

select throws_ok(
  $$select sender_source_account_id from app_finance.network_transfers$$,
  '42501', null,
  'the column the view needs is still unreadable by the client'
);

-- ---------------------------------------------------------------------------
-- The arithmetic
-- ---------------------------------------------------------------------------

select results_eq(
  $$select balance_minor, pending_transfer_hold_minor, reserved_minor,
      available_balance_minor
    from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b531'$$,
  $$values (99000::bigint, 30000::bigint, 30000::bigint, 69000::bigint)$$,
  'a pending transfer reserves without touching the balance'
);

select lives_ok(
  $$select app_finance.save_held_amount(
      'expense', 20000, 'EGP', 'Someone', current_date, null, null,
      '00000000-0000-0000-0000-00000000b531')$$,
  'an unsettled i_owe hold is recorded'
);

select results_eq(
  $$select held_outgoing_minor, reserved_minor, available_balance_minor
    from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b531'$$,
  $$values (20000::bigint, 50000::bigint, 49000::bigint)$$,
  'an i_owe hold reduces what is available'
);

select lives_ok(
  $$select app_finance.save_held_amount(
      'custom_income', 90000, 'EGP', 'Someone', current_date, null, null,
      '00000000-0000-0000-0000-00000000b531')$$,
  'an unsettled owed_to_me hold is recorded'
);

select results_eq(
  $$select held_incoming_minor, reserved_minor, available_balance_minor
    from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b531'$$,
  $$values (90000::bigint, 50000::bigint, 49000::bigint)$$,
  'money owed to the user is reported but never raises the available balance'
);

select lives_ok(
  $$select app_finance.set_held_amount_settled(
      (select id from app_finance.held_amounts
       where direction = 'i_owe' and settled_on is null), current_date)$$,
  'settling the i_owe hold books it'
);

select results_eq(
  $$select balance_minor, held_outgoing_minor, available_balance_minor
    from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b531'$$,
  $$values (79000::bigint, 0::bigint, 49000::bigint)$$,
  'settling moves the figure from the hold into the balance, available unchanged'
);

-- ---------------------------------------------------------------------------
-- Negative available is legal
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'avail:t1'), 9999999)$$,
  'the sender may promise more than the account holds'
);

select ok(
  (select available_balance_minor < 0 from app_finance.account_balances
   where account_id = '00000000-0000-0000-0000-00000000b531'),
  'available goes negative'
);

select lives_ok(
  $$insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      source_account_id, title
    ) values (
      '00000000-0000-0000-0000-000000000531', 'expense', current_date, 1000,
      'EGP', '00000000-0000-0000-0000-00000000b531', 'still spendable')$$,
  'and spending still works: the guard is balance_minor, not available'
);

-- ---------------------------------------------------------------------------
-- Isolation
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000532","role":"authenticated"}';

select is_empty(
  $$select 1 from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b531'$$,
  'the peer sees nothing of the sender''s account'
);

select results_eq(
  $$select coalesce(sum(reserved_minor), 0)::bigint
    from app_finance.account_balances$$,
  $$values (0::bigint)$$,
  'a pending incoming transfer reserves nothing on the receiver''s side'
);

select is_empty(
  $$select 1 from app_finance.account_hold_totals
    where user_id = '00000000-0000-0000-0000-000000000531'$$,
  'and the hold totals view is scoped to the caller'
);

select * from finish();
rollback;
