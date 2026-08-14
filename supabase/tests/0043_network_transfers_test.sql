begin;
create extension if not exists pgtap with schema extensions;

select plan(45);

-- ---------------------------------------------------------------------------
-- Users and accounts
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000000f4',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'transfer-sender@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Transfer Sender"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000f5',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'transfer-receiver@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Transfer Receiver"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000f6',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'transfer-third@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Transfer Third"}', now(), now()
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-00000000a401',
   '00000000-0000-0000-0000-0000000000f4', 'Cash', 'cash', 'EGP', 100000),
  ('00000000-0000-0000-0000-00000000a402',
   '00000000-0000-0000-0000-0000000000f4', 'Card', 'credit_card', 'EGP', 0),
  ('00000000-0000-0000-0000-00000000a403',
   '00000000-0000-0000-0000-0000000000f4', 'Poor', 'current', 'EGP', 1000),
  ('00000000-0000-0000-0000-00000000a404',
   '00000000-0000-0000-0000-0000000000f4', 'Doomed', 'current', 'EGP', 10000),
  ('00000000-0000-0000-0000-00000000a405',
   '00000000-0000-0000-0000-0000000000f5', 'Wallet', 'wallet', 'EGP', 0),
  ('00000000-0000-0000-0000-00000000a406',
   '00000000-0000-0000-0000-0000000000f5', 'Dollars', 'current', 'USD', 0),
  ('00000000-0000-0000-0000-00000000a407',
   '00000000-0000-0000-0000-0000000000f5', 'Closet', 'current', 'EGP', 0);

select has_table('app_finance', 'network_transfers',
  'network transfers table exists');

-- ---------------------------------------------------------------------------
-- Connect the two users
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f4","role":"authenticated"}';
select lives_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f5', 'Wife')$$,
  'sender adds the receiver'
);
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f5","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.status = 'pending' limit 1), 'Tarek')$$,
  'receiver accepts the request'
);

-- ---------------------------------------------------------------------------
-- Creation rules and the pending state
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f4","role":"authenticated"}';

select throws_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a402', 500, current_date,
      null, 'manual', null, 'test:card')$$,
  'invalid_account: network transfers move your own cash',
  'a credit card cannot fund a network transfer'
);

select lives_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a401', 30000, current_date,
      'rent share', 'manual', null, 'test:t1')$$,
  'creating a manual network transfer works'
);
select results_eq(
  $$select status::text, amount_minor, currency_code
    from app_finance.network_transfers where idempotency_key = 'test:t1'$$,
  $$values ('pending', 30000::bigint, 'EGP')$$,
  'the transfer starts pending with the source currency'
);
select lives_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a401', 30000, current_date,
      'rent share', 'manual', null, 'test:t1')$$,
  'retrying the same idempotency key does not fail'
);
select results_eq(
  $$select count(*)::integer from app_finance.network_transfers
    where idempotency_key = 'test:t1'$$,
  $$values (1)$$,
  'the retry reused the existing transfer'
);

select lives_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a401', 20000, current_date,
      null, 'manual', null, 'test:t2')$$,
  'a second transfer for the rejection path'
);
select lives_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a403', 5000, current_date,
      null, 'manual', null, 'test:t3')$$,
  'a pending transfer larger than the source balance is allowed'
);
select lives_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a404', 500, current_date,
      null, 'manual', null, 'test:t4')$$,
  'a transfer from the soon-archived account'
);
select lives_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a401', 700, current_date,
      null, 'manual', null, 'test:t5')$$,
  'a transfer that will outlive the connection'
);

update app_finance.accounts set is_archived = true
  where id = '00000000-0000-0000-0000-00000000a404';
select throws_ok(
  $$select app_finance.create_network_transfer_request(
      (select connection_id from app_finance.list_network_contacts()),
      '00000000-0000-0000-0000-00000000a404', 500, current_date,
      null, 'manual', null, 'test:archived')$$,
  'invalid_account: source not found or archived',
  'an archived account cannot fund a new transfer'
);

select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a401'$$,
  $$values (100000::bigint)$$,
  'pending transfers leave the sender balance untouched'
);
select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t1'),
      '00000000-0000-0000-0000-00000000a401')$$,
  'not_authorized: only the receiver can accept',
  'the sender cannot accept their own transfer'
);

set local role postgres;
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where is_network_transfer$$,
  $$values (0)$$,
  'no ledger rows exist while everything is pending'
);

-- ---------------------------------------------------------------------------
-- Third-user isolation
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f6","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.list_network_transfers()$$,
  $$values (0)$$,
  'a third user sees no transfers'
);
select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt limit 1),
      '00000000-0000-0000-0000-00000000a405')$$,
  'not_found: network transfer',
  'a third user cannot accept (rls hides the row)'
);

-- ---------------------------------------------------------------------------
-- Receiver decisions
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f5","role":"authenticated"}';

select results_eq(
  $$select direction, counterparty_alias,
      (my_account_id is null) as source_hidden
    from app_finance.list_network_transfers()
    where shared_note = 'rent share'$$,
  $$values ('received', 'Tarek', true)$$,
  'the receiver sees the alias and amount but never the sender account'
);
select throws_ok(
  $$select sender_source_account_id from app_finance.network_transfers$$,
  '42501', null,
  'the sender source account column is unreadable'
);
select throws_ok(
  $$update app_finance.network_transfers set amount_minor = 1$$,
  '42501', null,
  'clients cannot update transfers directly'
);

select lives_ok(
  $$select app_finance.reject_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.status = 'pending' and nt.amount_minor = 20000))$$,
  'the receiver rejects the second transfer'
);
select throws_ok(
  $$select app_finance.reject_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.status = 'rejected'))$$,
  'already_decided: this transfer was already handled',
  'a rejected transfer cannot be rejected again'
);
select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.status = 'rejected'),
      '00000000-0000-0000-0000-00000000a405')$$,
  'already_decided: this transfer was already handled',
  'a rejected transfer cannot be accepted (accept/reject race: one wins)'
);

select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t1'),
      '00000000-0000-0000-0000-00000000a406')$$,
  'currency_mismatch: pick an account in the transfer currency',
  'the receive account must match the transfer currency'
);

update app_finance.accounts set is_archived = true
  where id = '00000000-0000-0000-0000-00000000a407';
select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t1'),
      '00000000-0000-0000-0000-00000000a407')$$,
  'invalid_account: destination not found or archived',
  'an archived receive account is refused'
);

select lives_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t1'),
      '00000000-0000-0000-0000-00000000a405')$$,
  'the receiver accepts into their own wallet'
);
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a405'$$,
  $$values (30000::bigint)$$,
  'the receiver account increased exactly once'
);
select lives_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t1'),
      '00000000-0000-0000-0000-00000000a405')$$,
  'a double accept is idempotent'
);
select results_eq(
  $$select income_minor, expenses_minor
    from app_reports.cash_flow_summary(current_date - 7, current_date + 1)$$,
  $$values (0::bigint, 0::bigint)$$,
  'the accepted network transfer is neither income nor expense'
);

select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t3'),
      '00000000-0000-0000-0000-00000000a405')$$,
  'transfer_unavailable: this transfer can no longer be accepted',
  'a transfer the sender can no longer fund fails with a generic message'
);
select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t4'),
      '00000000-0000-0000-0000-00000000a405')$$,
  'transfer_unavailable: this transfer can no longer be accepted',
  'an archived sender source fails with the same generic message'
);

set local role postgres;
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where network_transfer_id = (select nt.id
      from app_finance.network_transfers nt
      where nt.idempotency_key = 'test:t1')$$,
  $$values (2)$$,
  'acceptance booked exactly two linked ledger rows'
);
select results_eq(
  $$select
      (source_account_id is not null and destination_account_id is null)
    from app_finance.financial_transactions
    where network_transfer_id is not null
    order by (user_id = '00000000-0000-0000-0000-0000000000f4') desc$$,
  $$values (true), (false)$$,
  'the sender row is source-only and the receiver row destination-only'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where is_network_transfer$$,
  $$values (2)$$,
  'the double accept created no extra rows'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f4","role":"authenticated"}';
select results_eq(
  $$select balance_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000a401'$$,
  $$values (70000::bigint)$$,
  'the sender account decreased exactly once (t5 still pending)'
);

-- ---------------------------------------------------------------------------
-- Cross-user RLS stays strict after connecting (hard acceptance criterion)
-- ---------------------------------------------------------------------------

select results_eq(
  $$select count(*)::integer from app_finance.accounts
    where user_id = '00000000-0000-0000-0000-0000000000f5'$$,
  $$values (0)$$,
  'the sender cannot read the receiver accounts'
);
select results_eq(
  $$select count(*)::integer from app_finance.account_balances
    where user_id = '00000000-0000-0000-0000-0000000000f5'$$,
  $$values (0)$$,
  'the sender cannot read the receiver balances'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where user_id = '00000000-0000-0000-0000-0000000000f5'$$,
  $$values (0)$$,
  'the sender cannot read the receiver transactions'
);
select results_eq(
  $$select count(*)::integer from app_salary.salary_settings
    where user_id = '00000000-0000-0000-0000-0000000000f5'$$,
  $$values (0)$$,
  'the sender cannot read the receiver salary settings'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f5","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.accounts
    where user_id = '00000000-0000-0000-0000-0000000000f4'$$,
  $$values (0)$$,
  'the receiver cannot read the sender accounts either'
);

-- ---------------------------------------------------------------------------
-- Removed connection: pending transfers stay but cannot be accepted
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.remove_network_connection(
      (select connection_id from app_finance.list_network_contacts()))$$,
  'the receiver removes the connection'
);
select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t5'),
      '00000000-0000-0000-0000-00000000a405')$$,
  'network_destination_unavailable: this transfer can no longer be accepted',
  'a pending transfer on a removed connection cannot be accepted'
);
select lives_ok(
  $$select app_finance.reject_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.idempotency_key = 'test:t5'))$$,
  'the receiver may still reject it'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f4","role":"authenticated"}';
select throws_ok(
  $$select app_finance.create_network_transfer_request(
      (select c.id from app_finance.network_connections c limit 1),
      '00000000-0000-0000-0000-00000000a401', 100, current_date,
      null, 'manual', null, 'test:t6')$$,
  'network_destination_unavailable: this contact was removed from your network',
  'no new transfers after removal'
);

select * from finish();
rollback;
