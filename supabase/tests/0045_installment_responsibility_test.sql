begin;
create extension if not exists pgtap with schema extensions;

select plan(55);

-- ---------------------------------------------------------------------------
-- Users: Owner A, Responsible B, Third C
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000000e1',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'resp-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Tarek Owner"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000e2',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'resp-linked@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Ahmed Linked"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000e3',
  '00000000-0000-0000-0000-0000000000e3',
  'authenticated', 'authenticated', 'resp-third@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Third Wheel"}', now(), now()
);

select has_table('app_finance', 'installment_responsibility_links',
  'responsibility links table exists');
select has_table('app_finance', 'installment_reimbursements',
  'reimbursements table exists');

-- Owner accounts, category, facility, and plans.
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000e101',
  '00000000-0000-0000-0000-0000000000e1', 'Owner Cash', 'cash', 'EGP', 5000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000e1c1',
  '00000000-0000-0000-0000-0000000000e1', 'Financed', 'expense'
);

select lives_ok(
  $$select app_finance.save_credit_facility(
      'Resp Gold Card', 'credit_card', 'EGP', 10000000, 5::smallint)$$,
  'owner creates a credit card facility'
);

create temporary table resp_ids (key text primary key, id uuid);
insert into resp_ids values ('card',
  (select account_id from app_finance.credit_facility_settings
    where user_id = '00000000-0000-0000-0000-0000000000e1'));

select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from resp_ids where key = 'card'), 'Samsung TV',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 40,
      1200000, 12, current_date - 10, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ee01')$$,
  'owner creates a 12 x EGP 1,000 plan'
);

-- ---------------------------------------------------------------------------
-- Custom link: active immediately, one live link per plan
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ee01', '  Dad  ', 'TV for dad')$$,
  'custom link is created'
);
select results_eq(
  $$select link_type::text, status::text, custom_name,
      responsibility_from_sequence
    from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee01'$$,
  $$values ('custom', 'accepted', 'Dad', 1)$$,
  'custom link is accepted immediately, trimmed, starting at sequence 1'
);
select throws_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ee01', 'Mona', null)$$,
  'already_linked: this installment already has a responsible person',
  'a plan can have only one live responsibility link'
);

-- Unlink preserves the row as history.
select lives_ok(
  $$select app_finance.remove_installment_responsibility(
      (select id from app_finance.installment_responsibility_links
        where plan_id = '00000000-0000-0000-0000-00000000ee01'))$$,
  'owner unlinks the custom person'
);
select results_eq(
  $$select count(*)::integer, count(removed_at)::integer
    from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee01'$$,
  $$values (1, 1)$$,
  'unlink soft-removes and preserves history'
);

-- ---------------------------------------------------------------------------
-- Network link needs an active accepted connection
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.request_installment_responsibility(
      '00000000-0000-0000-0000-00000000ee01', gen_random_uuid(), null)$$,
  'not_found: network connection',
  'an arbitrary connection id is rejected'
);

select lives_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000e2', 'Ahmed')$$,
  'owner sends an add request'
);
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.recipient_user_id = '00000000-0000-0000-0000-0000000000e2'
          and r.status = 'pending'), 'Tarek')$$,
  'the contact accepts the connection'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';
insert into resp_ids values ('conn',
  (select connection_id from app_finance.list_network_contacts()));

select lives_ok(
  $$select app_finance.request_installment_responsibility(
      '00000000-0000-0000-0000-00000000ee01',
      (select id from resp_ids where key = 'conn'), 'Please cover this')$$,
  'owner sends the installment link request'
);
insert into resp_ids values ('link1',
  (select id from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee01'
      and status = 'pending'));

select results_eq(
  $$select link_type::text, status::text,
      responsible_user_id, plan_revision_at_request
    from app_finance.installment_responsibility_links
    where id = (select id from resp_ids where key = 'link1')$$,
  $$values ('network', 'pending',
    '00000000-0000-0000-0000-0000000000e2'::uuid, 1)$$,
  'the network link is pending with the derived responsible user'
);

-- Server-built snapshot: sanitized consent evidence.
select ok(
  (select request_snapshot ? 'terms_fingerprint'
      and request_snapshot ? 'remaining_total_minor'
      and request_snapshot ->> 'title' = 'Samsung TV'
      and (request_snapshot ->> 'remaining_count')::int = 12
    from app_finance.installment_responsibility_links
    where id = (select id from resp_ids where key = 'link1')),
  'the snapshot carries the fingerprint and full remaining terms'
);
select ok(
  (select not (request_snapshot ? 'notes')
      and not (request_snapshot ? 'credit_limit_minor')
      and not (request_snapshot ? 'available_credit_minor')
      and not (request_snapshot ? 'last_four_digits')
    from app_finance.installment_responsibility_links
    where id = (select id from resp_ids where key = 'link1')),
  'the snapshot never contains notes, limits, or card digits'
);

-- A pending link books nothing.
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from resp_ids where key = 'card'))$$,
  $$values (1200000::bigint)$$,
  'the facility outstanding is untouched by the pending link'
);

-- ---------------------------------------------------------------------------
-- Consent: only the responsible user decides
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from resp_ids where key = 'link1'))$$,
  'not_authorized: only the responsible person can respond',
  'the owner cannot accept on behalf of the contact'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}';
select throws_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from resp_ids where key = 'link1'))$$,
  'not_found: installment link request',
  'a third user cannot even see the request'
);
select throws_ok(
  $$select app_finance.get_shared_installment_link_details(
      (select id from resp_ids where key = 'link1'))$$,
  'not_found: installment link',
  'a third user cannot read the shared details'
);

-- The responsible user reviews the sanitized details before accepting.
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';
select ok(
  (select d -> 'link' ->> 'viewer_role' = 'responsible'
      and d -> 'link' ->> 'counterparty_name' = 'Tarek'
      and jsonb_array_length(d -> 'schedule') = 12
      and (d -> 'current' ->> 'terms_changed')::boolean = false
      and not (d -> 'current' ? 'credit_limit_minor')
    from app_finance.get_shared_installment_link_details(
      (select id from resp_ids where key = 'link1')) d),
  'the recipient sees the full sanitized schedule under their own alias'
);
select results_eq(
  $$select count(*)::integer from app_finance.list_my_linked_installments()$$,
  $$values (1)$$,
  'the request appears in the recipient''s linked list'
);

select lives_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from resp_ids where key = 'link1'))$$,
  'the responsible user accepts'
);
select lives_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from resp_ids where key = 'link1'))$$,
  'double accept is idempotent'
);
select results_eq(
  $$select status::text, (accepted_at is not null)
    from app_finance.installment_responsibility_links
    where id = (select id from resp_ids where key = 'link1')$$,
  $$values ('accepted', true)$$,
  'the link is accepted exactly once'
);
select throws_ok(
  $$select app_finance.reject_installment_responsibility(
      (select id from resp_ids where key = 'link1'))$$,
  'already_decided: this request was already handled',
  'reject after accept is refused'
);

-- Acceptance moved no money anywhere.
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from resp_ids where key = 'card'))$$,
  $$values (1200000::bigint)$$,
  'acceptance leaves the facility liability unchanged'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where user_id = '00000000-0000-0000-0000-0000000000e2'$$,
  $$values (0)$$,
  'acceptance creates no transaction for the responsible user'
);

-- ---------------------------------------------------------------------------
-- Stale terms cannot be accepted
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from resp_ids where key = 'card'), 'Fridge',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 40,
      600000, 6, current_date - 10, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ee02')$$,
  'owner creates a second plan'
);
select lives_ok(
  $$select app_finance.request_installment_responsibility(
      '00000000-0000-0000-0000-00000000ee02',
      (select id from resp_ids where key = 'conn'), null)$$,
  'owner requests responsibility for the second plan'
);
insert into resp_ids values ('link2',
  (select id from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee02'));

select lives_ok(
  $$select app_finance.restructure_installment_plan(
      '00000000-0000-0000-0000-00000000ee02', 660000, 4,
      (current_date + 20)::date, 'bank restructure')$$,
  'owner restructures the plan after sending the request'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';
select throws_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from resp_ids where key = 'link2'))$$,
  'terms_changed: this installment changed after the request was sent',
  'materially changed terms cannot be silently accepted'
);
select ok(
  (select (d -> 'current' ->> 'terms_changed')::boolean
    from app_finance.get_shared_installment_link_details(
      (select id from resp_ids where key = 'link2')) d),
  'the shared details flag the changed terms'
);
select lives_ok(
  $$select app_finance.reject_installment_responsibility(
      (select id from resp_ids where key = 'link2'))$$,
  'the recipient can still reject the stale request'
);

-- ---------------------------------------------------------------------------
-- Responsibility starts at the first unpaid due
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}';

select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from resp_ids where key = 'card'), 'Ongoing Laptop',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 100,
      900000, 9, current_date - 70, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ee03')$$,
  'owner creates an ongoing plan'
);
select lives_ok(
  $$select app_finance.pay_credit_facility(
      (select id from resp_ids where key = 'card'),
      '00000000-0000-0000-0000-00000000e101', 200000, current_date,
      (select jsonb_agg(jsonb_build_object(
          'due_id', d.id, 'amount_minor', d.amount_minor))
        from app_finance.installment_dues d
        where d.plan_id = '00000000-0000-0000-0000-00000000ee03'
          and d.sequence_number <= 2))$$,
  'owner pays the first two installments to the bank'
);
select lives_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ee03', 'Mona', null)$$,
  'owner links the ongoing plan'
);
select results_eq(
  $$select responsibility_from_sequence
    from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee03'$$,
  $$values (3)$$,
  'the ongoing link starts at the first unpaid due, not at 1'
);

-- Imported plans: presettled history is never assigned.
select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from resp_ids where key = 'card'), 'Imported Phone',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 200,
      800000, 8, current_date - 170, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ee04', 'manual_fees', null, 0,
      'monthly', 'flat', 0, 0, null, 2)$$,
  'owner imports a plan with two paid installments'
);
select lives_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ee04', 'Cousin', null)$$,
  'owner links the imported plan'
);
select results_eq(
  $$select responsibility_from_sequence
    from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee04'$$,
  $$values (3)$$,
  'presettled dues stay outside the responsibility'
);

-- Cancelled plans cannot be linked.
select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from resp_ids where key = 'card'), 'Doomed Chair',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 10,
      100000, 2, current_date, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ee05')$$,
  'owner creates a plan to cancel'
);
select lives_ok(
  $$select app_finance.cancel_installment_plan(
      '00000000-0000-0000-0000-00000000ee05')$$,
  'owner cancels it'
);
select throws_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ee05', 'Nobody', null)$$,
  'plan_not_linkable: only an active installment plan can be linked',
  'a cancelled plan cannot be linked'
);

-- A plan that carries responsibility history cannot be rewritten in place.
select throws_ok(
  $$select app_finance.update_installment_plan(
      '00000000-0000-0000-0000-00000000ee01', 'Samsung TV 2',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 40,
      1200000, 10, current_date - 10)$$,
  'plan_linked: this plan has responsibility history and cannot be rewritten',
  'the delete-and-recreate edit path refuses linked plans'
);

-- ---------------------------------------------------------------------------
-- Removed connection blocks pending acceptance
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from resp_ids where key = 'card'), 'Late Link',
      '00000000-0000-0000-0000-00000000e1c1', current_date - 10,
      200000, 2, current_date, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ee06')$$,
  'owner creates one more plan'
);
select lives_ok(
  $$select app_finance.request_installment_responsibility(
      '00000000-0000-0000-0000-00000000ee06',
      (select id from resp_ids where key = 'conn'), null)$$,
  'owner sends a request on the new plan'
);
insert into resp_ids values ('link3',
  (select id from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ee06'));
select lives_ok(
  $$select app_finance.remove_network_connection(
      (select id from resp_ids where key = 'conn'))$$,
  'owner removes the network connection'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}';
select throws_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from resp_ids where key = 'link3'))$$,
  'network_destination_unavailable: this request can no longer be accepted',
  'a removed connection blocks acceptance'
);
select results_eq(
  $$select count(*)::integer from app_finance.list_my_linked_installments()$$,
  $$values (0)$$,
  'removed connections drop the shared surface for the linked user'
);

-- ---------------------------------------------------------------------------
-- RLS isolation
-- ---------------------------------------------------------------------------

select results_eq(
  $$select count(*)::integer from app_finance.installment_plans$$,
  $$values (0)$$,
  'the responsible user cannot read the owner''s plans'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_dues$$,
  $$values (0)$$,
  'the responsible user cannot read the owner''s dues'
);
select results_eq(
  $$select count(*)::integer from app_finance.accounts
    where user_id = '00000000-0000-0000-0000-0000000000e1'$$,
  $$values (0)$$,
  'the responsible user cannot read the owner''s accounts'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.installment_responsibility_links$$,
  $$values (3)$$,
  'the responsible user sees only links naming them'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}';
select results_eq(
  $$select count(*)::integer
    from app_finance.installment_responsibility_links$$,
  $$values (0)$$,
  'a third user sees no responsibility links at all'
);

select * from finish();
rollback;
