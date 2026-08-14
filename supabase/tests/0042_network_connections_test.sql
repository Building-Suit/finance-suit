begin;
create extension if not exists pgtap with schema extensions;

select plan(34);

-- ---------------------------------------------------------------------------
-- Users: Tarek (requester), Mona (recipient), and an unrelated third user
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000000f1',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'network-tarek@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Tarek Abdelwahab"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000f2',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'network-mona@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Mona Ahmed"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000f3',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'network-third@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Third Wheel"}', now(), now()
);

select has_table('app_finance', 'network_add_requests',
  'network add requests table exists');
select has_table('app_finance', 'network_connections',
  'network connections table exists');
select results_eq(
  $$select count(*)::integer from pg_tables
    where schemaname like 'app\_%' escape '\'
      and rowsecurity = false$$,
  $$values (0)$$,
  'the new tables keep the no-RLS-less-table invariant'
);

-- ---------------------------------------------------------------------------
-- Search and request creation
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';

select results_eq(
  $$select display_name, email, relationship_state
    from app_finance.search_network_users('Mona Ah')$$,
  $$values ('Mona Ahmed', 'network-mona@test.local', 'none')$$,
  'name search returns identity and relationship state'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.search_network_users('Mo')$$,
  $$values (0)$$,
  'name search needs at least three characters'
);
select results_eq(
  $$select display_name
    from app_finance.search_network_users('NETWORK-MONA@test.local')$$,
  $$values ('Mona Ahmed')$$,
  'email search is an exact case-insensitive lookup'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.search_network_users('network-tarek@test.local')$$,
  $$values (0)$$,
  'search excludes the caller'
);

select throws_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f1', 'Me')$$,
  'invalid_target: you cannot add yourself',
  'self-add is rejected'
);
select throws_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f2', '   ')$$,
  'invalid_alias: choose a name between 1 and 80 characters',
  'a blank alias is rejected'
);
select lives_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f2', '  Wife  ')$$,
  'sending an add request with an alias works'
);
select throws_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f2', 'Wife again')$$,
  'request_already_pending: a request between you two is already waiting',
  'a duplicate pending request is blocked'
);
select results_eq(
  $$select relationship_state, request_direction
    from app_finance.search_network_users('Mona Ah')$$,
  $$values ('outgoing_pending', 'outgoing')$$,
  'search reflects the outgoing pending request'
);

-- ---------------------------------------------------------------------------
-- Recipient view and reverse-duplicate protection
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';

select throws_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f1', 'Tarek')$$,
  'request_already_pending: a request between you two is already waiting',
  'the reverse direction cannot open a second pending request'
);
select results_eq(
  $$select direction, other_display_name, other_email,
      coalesce(my_alias, '(hidden)')
    from app_finance.list_network_add_requests()$$,
  $$values ('incoming', 'Tarek Abdelwahab', 'network-tarek@test.local',
    '(hidden)')$$,
  'the recipient sees the requester real identity, never the private alias'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f3","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.network_add_requests$$,
  $$values (0)$$,
  'a third user cannot read the request'
);
select throws_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r limit 1), 'Spy')$$,
  'not_found: add request',
  'a third user has no request id to accept (rls hides it)'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select throws_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r limit 1), 'Nope')$$,
  'not_authorized: only the recipient can respond',
  'the requester cannot accept their own request'
);

-- ---------------------------------------------------------------------------
-- Acceptance builds the connection with directional aliases
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';

select lives_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.status = 'pending' limit 1), 'Tarek')$$,
  'the recipient accepts with their own alias'
);
select results_eq(
  $$select status::text from app_finance.network_add_requests$$,
  $$values ('accepted')$$,
  'the request is marked accepted'
);
select results_eq(
  $$select local_alias, real_display_name
    from app_finance.list_network_contacts()$$,
  $$values ('Tarek', 'Tarek Abdelwahab')$$,
  'the recipient sees their own alias for the requester'
);
select throws_ok(
  $$select user_a_alias_for_b from app_finance.network_connections$$,
  '42501', null,
  'alias columns are not readable directly'
);
select throws_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f1', 'Twice')$$,
  'already_connected: this person is already in your network',
  'a new request while connected is refused'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select results_eq(
  $$select local_alias, real_display_name
    from app_finance.list_network_contacts()$$,
  $$values ('Wife', 'Mona Ahmed')$$,
  'the requester sees their own trimmed alias for the recipient'
);
select results_eq(
  $$select relationship_state from app_finance.search_network_users('Mona Ah')$$,
  $$values ('connected')$$,
  'search reflects the connection'
);

-- ---------------------------------------------------------------------------
-- Rename touches only the caller''s own alias
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.rename_network_contact(
      (select connection_id from app_finance.list_network_contacts()),
      'Habibty')$$,
  'renaming my alias works'
);
select results_eq(
  $$select local_alias from app_finance.list_network_contacts()$$,
  $$values ('Habibty')$$,
  'my alias changed'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select results_eq(
  $$select local_alias from app_finance.list_network_contacts()$$,
  $$values ('Tarek')$$,
  'the other side alias is untouched by my rename'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f3","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer from app_finance.list_network_contacts()$$,
  $$values (0)$$,
  'a third user sees no connections'
);

-- ---------------------------------------------------------------------------
-- Removal keeps history and allows reconnecting
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select lives_ok(
  $$select app_finance.remove_network_connection(
      (select connection_id from app_finance.list_network_contacts()))$$,
  'either party can remove the connection'
);
select results_eq(
  $$select count(*)::integer from app_finance.list_network_contacts()$$,
  $$values (0)$$,
  'a removed connection leaves the contact list'
);
select results_eq(
  $$select count(*)::integer from app_finance.network_add_requests
    where status = 'accepted'$$,
  $$values (1)$$,
  'the accepted request history remains after removal'
);

-- A fresh request cycle after removal, this time rejected.
select lives_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f1', 'Tarek again')$$,
  'a new request can be sent after removal'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select lives_ok(
  $$select app_finance.reject_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.status = 'pending' limit 1))$$,
  'the recipient can reject'
);
select throws_ok(
  $$select app_finance.reject_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.status = 'rejected' limit 1))$$,
  'already_decided: this request was already handled',
  'a decided request cannot be rejected again'
);

select * from finish();
rollback;
