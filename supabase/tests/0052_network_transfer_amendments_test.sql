begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

-- ---------------------------------------------------------------------------
-- Users, accounts, connection
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000521',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'amend-sender@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Amend Sender"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000522',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'amend-receiver@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Amend Receiver"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000523',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'amend-third@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Amend Third"}', now(), now()
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-00000000b521',
   '00000000-0000-0000-0000-000000000521', 'Cash', 'cash', 'EGP', 100000),
  ('00000000-0000-0000-0000-00000000b522',
   '00000000-0000-0000-0000-000000000521', 'Spare', 'current', 'EGP', 50000),
  ('00000000-0000-0000-0000-00000000b523',
   '00000000-0000-0000-0000-000000000522', 'Wallet', 'wallet', 'EGP', 0);

insert into app_finance.network_connections (
  id, user_a_id, user_b_id, user_a_alias_for_b, user_b_alias_for_a
) values (
  '00000000-0000-0000-0000-00000000c521',
  '00000000-0000-0000-0000-000000000521',
  '00000000-0000-0000-0000-000000000522',
  'Receiver Alias', 'Sender Alias'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000521","role":"authenticated"}';

select lives_ok(
  $$select app_finance.create_network_transfer_request(
      '00000000-0000-0000-0000-00000000c521', '00000000-0000-0000-0000-00000000b521',
      30000, current_date, null, 'manual', null, 'amend:t1')$$,
  'sender creates a pending transfer'
);

-- ---------------------------------------------------------------------------
-- Authorization
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000523","role":"authenticated"}';

select throws_ok(
  $$select app_finance.cancel_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'))$$,
  'not_found: network transfer',
  'a third party cannot even see the transfer, let alone cancel it'
);

select throws_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 50000)$$,
  'not_found: network transfer',
  'a third party cannot amend the transfer'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000522","role":"authenticated"}';

select throws_ok(
  $$select app_finance.cancel_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'))$$,
  'not_authorized: only the sender can cancel',
  'the receiver cannot cancel the sender''s request'
);

select throws_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 50000)$$,
  'not_authorized: only the sender can change this transfer',
  'the receiver cannot amend the sender''s request'
);

-- ---------------------------------------------------------------------------
-- Amending
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000521","role":"authenticated"}';

select lives_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 40000)$$,
  'the sender amends the amount while it is pending'
);

select results_eq(
  $$select amount_minor, amendment_count, responded_at is null, status::text
    from app_finance.network_transfers where idempotency_key = 'amend:t1'$$,
  $$values (40000::bigint, 1, true, 'pending')$$,
  'the amendment lands, responded_at stays null, and the row stays pending'
);

select throws_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 0)$$,
  'invalid_amount: must be positive',
  'the amended amount must stay positive'
);

-- The product decision: a request may promise more than the account holds.
-- Acceptance is the only moment that checks real funds.
select lives_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 99999999)$$,
  'amending far above the balance succeeds: pending never checks funds'
);

select ok(
  (select available_balance_minor < 0 from app_finance.account_balances
   where account_id = '00000000-0000-0000-0000-00000000b521'),
  'the available balance is allowed to go negative'
);

select lives_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 40000)$$,
  'the sender amends back down'
);

select lives_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'),
      null, '00000000-0000-0000-0000-00000000b522')$$,
  'the sender moves the request to a different source account'
);

select results_eq(
  $$select pending_transfer_hold_minor from app_finance.account_balances
    where account_id in ('00000000-0000-0000-0000-00000000b521',
                         '00000000-0000-0000-0000-00000000b522')
    order by account_id$$,
  $$values (0::bigint), (40000::bigint)$$,
  'the hold follows the request to the new source account'
);

select results_eq(
  $$select amendment_count from app_finance.network_transfers
    where idempotency_key = 'amend:t1'$$,
  $$values (4)$$,
  'each material change counts once'
);

select lives_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 40000)$$,
  'a no-op amendment is accepted'
);

select results_eq(
  $$select amendment_count from app_finance.network_transfers
    where idempotency_key = 'amend:t1'$$,
  $$values (4)$$,
  'but a no-op amendment does not burn an amendment or notify anyone'
);

-- ---------------------------------------------------------------------------
-- The consent guard
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000522","role":"authenticated"}';

select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'),
      '00000000-0000-0000-0000-00000000b523', 30000)$$,
  'transfer_changed: the sender changed this request',
  'accepting the amount the receiver last saw fails once the sender changed it'
);

-- ---------------------------------------------------------------------------
-- Cancelling
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000521","role":"authenticated"}';

select lives_ok(
  $$select app_finance.cancel_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'))$$,
  'the sender withdraws the request'
);

select results_eq(
  $$select status::text, cancelled_at is not null, responded_at is null
    from app_finance.network_transfers where idempotency_key = 'amend:t1'$$,
  $$values ('cancelled', true, true)$$,
  'cancelling stamps cancelled_at and leaves responded_at untouched'
);

select results_eq(
  $$select count(*) from app_finance.financial_transactions
    where is_network_transfer$$,
  $$values (0::bigint)$$,
  'cancelling books nothing'
);

select results_eq(
  $$select reserved_minor from app_finance.account_balances
    where account_id = '00000000-0000-0000-0000-00000000b522'$$,
  $$values (0::bigint)$$,
  'cancelling releases the hold'
);

select lives_ok(
  $$select app_finance.cancel_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'))$$,
  'cancelling twice is idempotent'
);

select throws_ok(
  $$select app_finance.amend_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'), 10000)$$,
  'transfer_cancelled: you already cancelled this transfer',
  'a cancelled request can no longer be amended'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000522","role":"authenticated"}';

select throws_ok(
  $$select app_finance.accept_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'),
      '00000000-0000-0000-0000-00000000b523')$$,
  'transfer_cancelled: the sender cancelled this transfer',
  'a cancelled request cannot be accepted'
);

select throws_ok(
  $$select app_finance.reject_network_transfer(
      (select id from app_finance.network_transfers
       where idempotency_key = 'amend:t1'))$$,
  'transfer_cancelled: the sender cancelled this transfer',
  'a cancelled request cannot be rejected'
);

-- ---------------------------------------------------------------------------
-- No client write path was opened
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update app_finance.network_transfers set cancelled_at = now()$$,
  '42501', null,
  'the new state columns stay server-owned'
);

select * from finish();
rollback;
