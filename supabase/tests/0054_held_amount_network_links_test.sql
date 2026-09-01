begin;
create extension if not exists pgtap with schema extensions;

select plan(21);

-- ---------------------------------------------------------------------------
-- Users, accounts, connection
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000541',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'hold-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Hold Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000542',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'hold-peer@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Hold Peer"}', now(), now()
), (
  '00000000-0000-0000-0000-000000000543',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'hold-third@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Hold Third"}', now(), now()
);

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values
  ('00000000-0000-0000-0000-00000000b541',
   '00000000-0000-0000-0000-000000000541', 'Cash', 'cash', 'EGP', 100000),
  ('00000000-0000-0000-0000-00000000b542',
   '00000000-0000-0000-0000-000000000542', 'Wallet', 'wallet', 'EGP', 50000);

insert into app_finance.network_connections (
  id, user_a_id, user_b_id, user_a_alias_for_b, user_b_alias_for_a
) values (
  '00000000-0000-0000-0000-00000000c541',
  '00000000-0000-0000-0000-000000000541',
  '00000000-0000-0000-0000-000000000542',
  'My Name For Peer', 'My Name For Owner'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000541","role":"authenticated"}';

-- ---------------------------------------------------------------------------
-- Recording a network-linked hold
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.save_held_amount(
      'expense', 25000, 'EGP', 'ignored free text', current_date, 'private title',
      'private notes', '00000000-0000-0000-0000-00000000b541', null, null, null,
      '00000000-0000-0000-0000-00000000c541', 'the shared note')$$,
  'the owner records a hold against a network contact'
);

select results_eq(
  $$select counterparty, counterparty_user_id, shared_note
    from app_finance.held_amounts where network_connection_id is not null$$,
  $$values ('My Name For Peer',
            '00000000-0000-0000-0000-000000000542'::uuid, 'the shared note')$$,
  'the label comes from the connection, not from client-supplied text'
);

-- Remembered while the owner can still see it: RLS hides the row from every
-- other role, so a later subselect would silently yield NULL and turn the
-- authorization assertions below into no-ops.
create temporary table held_fixture as
  select id from app_finance.held_amounts where network_connection_id is not null;

select throws_ok(
  $$select app_finance.save_held_amount(
      'expense', 100, 'EGP', 'x', current_date, null, null,
      '00000000-0000-0000-0000-00000000b541', null, null, null,
      '00000000-0000-0000-0000-00000000c999', null)$$,
  'network_destination_unavailable: this contact was removed from your network',
  'a hold cannot name a connection the caller is not part of'
);

-- ---------------------------------------------------------------------------
-- What the counterparty sees, and what they do not
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000542","role":"authenticated"}';

select results_eq(
  $$select counterparty_alias, owner_direction::text, amount_minor,
      shared_note, connection_active
    from app_finance.list_holds_against_me()$$,
  $$values ('My Name For Owner', 'i_owe', 25000::bigint,
            'the shared note', true)$$,
  'the counterparty sees the hold under their own private alias for the owner'
);

select is_empty(
  $$select 1 from app_finance.held_amounts$$,
  'the counterparty still cannot read the held_amounts table'
);

select is_empty(
  $$select 1 from app_finance.accounts
    where user_id = '00000000-0000-0000-0000-000000000541'$$,
  'nor the owner''s accounts'
);

select is_empty(
  $$select 1 from app_finance.account_balances
    where user_id = '00000000-0000-0000-0000-000000000541'$$,
  'nor the owner''s balances'
);

select is_empty(
  $$select 1 from app_finance.financial_transactions
    where user_id = '00000000-0000-0000-0000-000000000541'$$,
  'nor the owner''s transactions'
);

-- The exposure is the OUT parameter list and nothing else, so assert on it
-- directly rather than on whatever a sample row happens to contain.
select is_empty(
  $$select unnest(p.proargnames) as col
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_finance' and p.proname = 'list_holds_against_me'
    intersect
    select unnest(array['notes', 'title', 'account_id', 'category_id',
      'user_id', 'transaction_id', 'linked_transaction_id',
      'settlement_transaction_id', 'manages_transaction'])$$,
  'the projection leaks no private column of the owner''s hold'
);

select results_eq(
  $$select coalesce(sum(reserved_minor), 0)::bigint,
      coalesce(sum(held_incoming_minor), 0)::bigint
    from app_finance.account_balances$$,
  $$values (0::bigint, 0::bigint)$$,
  'a hold against you never moves your own totals'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000543","role":"authenticated"}';

select is_empty(
  $$select 1 from app_finance.list_holds_against_me()$$,
  'an unconnected third party sees nothing'
);

-- ---------------------------------------------------------------------------
-- The notify helper's two load-bearing guards
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000542","role":"authenticated"}';

select throws_ok(
  $$select app_private.notify_held_amount_counterparty(
      (select id from held_fixture), 'held_amount.updated')$$,
  'not_authorized: not your held amount',
  'the helper refuses to speak for someone else''s hold'
);

-- Read as the recipient: app_core.notifications is RLS-scoped to its owner.
select results_eq(
  $$select count(*) from app_core.notifications
    where user_id = '00000000-0000-0000-0000-000000000542'
      and event_key = 'held_amount.recorded_against_you'$$,
  $$values (1::bigint)$$,
  'recording the hold notified the counterparty exactly once'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000541","role":"authenticated"}';

select throws_ok(
  $$select app_private.notify_held_amount_counterparty(
      (select id from held_fixture), 'system.developer_test')$$,
  'invalid_event: system.developer_test',
  'the helper refuses to mint an arbitrary catalogued notification'
);

select lives_ok(
  $$select app_finance.save_held_amount(
      'expense', 30000, 'EGP', 'x', current_date, 'private title',
      'private notes', '00000000-0000-0000-0000-00000000b541', null, null,
      (select id from held_fixture),
      '00000000-0000-0000-0000-00000000c541', 'the shared note')$$,
  'the owner changes the amount'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000542","role":"authenticated"}';

select results_eq(
  $$select count(*) from app_core.notifications
    where user_id = '00000000-0000-0000-0000-000000000542'
      and event_key = 'held_amount.updated'$$,
  $$values (1::bigint)$$,
  'and the change notifies the counterparty too'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000541","role":"authenticated"}';

-- ---------------------------------------------------------------------------
-- Alias upkeep and revocation
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.rename_network_contact(
      '00000000-0000-0000-0000-00000000c541', 'Renamed Peer')$$,
  'the owner renames the contact'
);

select results_eq(
  $$select counterparty from app_finance.held_amounts
    where network_connection_id is not null$$,
  $$values ('Renamed Peer')$$,
  'the snapshot on the hold follows the rename'
);

select lives_ok(
  $$select app_finance.remove_network_connection(
      '00000000-0000-0000-0000-00000000c541')$$,
  'the owner removes the connection'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000542","role":"authenticated"}';

select is_empty(
  $$select 1 from app_finance.list_holds_against_me()$$,
  'removing the connection revokes the counterparty''s view of the hold'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-000000000541","role":"authenticated"}';

select results_eq(
  $$select count(*), max(counterparty) from app_finance.held_amounts
    where network_connection_id is not null$$,
  $$values (1::bigint, 'Renamed Peer')$$,
  'while the owner keeps the hold and its label'
);

select * from finish();
rollback;
