begin;
create extension if not exists pgtap with schema extensions;

select plan(47);

-- ---------------------------------------------------------------------------
-- Users: Owner (Tarek), Responsible network user (Ahmed)
-- ---------------------------------------------------------------------------

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000000f1',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reimb-owner@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Tarek Reimb"}', now(), now()
), (
  '00000000-0000-0000-0000-0000000000f2',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'reimb-linked@test.local', '', now(),
  '{"provider":"email","providers":["email"]}',
  '{"display_name":"Ahmed Reimb"}', now(), now()
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';

insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000f101',
  '00000000-0000-0000-0000-0000000000f1', 'Owner Bank', 'current', 'EGP',
  5000000
);
insert into app_finance.transaction_categories (
  id, user_id, name, category_kind
) values (
  '00000000-0000-0000-0000-00000000f1c1',
  '00000000-0000-0000-0000-0000000000f1', 'Financed', 'expense'
);
select lives_ok(
  $$select app_finance.save_credit_facility(
      'Reimb Card', 'credit_card', 'EGP', 10000000, 5::smallint)$$,
  'owner creates a facility'
);

create temporary table reimb_ids (key text primary key, id uuid);
insert into reimb_ids values ('card',
  (select account_id from app_finance.credit_facility_settings
    where user_id = '00000000-0000-0000-0000-0000000000f1'));

-- Plan 1: 10 x EGP 1,000 (network-linked). Plan 2: 5 x EGP 2,000 (custom).
select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from reimb_ids where key = 'card'), 'Samsung TV',
      '00000000-0000-0000-0000-00000000f1c1', current_date - 40,
      1000000, 10, current_date - 10, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ff01')$$,
  'owner creates the network-linked plan'
);
select lives_ok(
  $$select app_finance.create_installment_plan(
      (select id from reimb_ids where key = 'card'), 'iPhone',
      '00000000-0000-0000-0000-00000000f1c1', current_date - 40,
      1000000, 5, current_date - 10, 0, null, null, null, null,
      '00000000-0000-0000-0000-00000000ff02')$$,
  'owner creates the custom-linked plan'
);

-- Ahmed's wallet.
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
insert into app_finance.accounts (
  id, user_id, name, account_type, currency_code, opening_balance_minor
) values (
  '00000000-0000-0000-0000-00000000f201',
  '00000000-0000-0000-0000-0000000000f2', 'Ahmed Wallet', 'wallet', 'EGP',
  2000000
);

-- Connect and link.
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select lives_ok(
  $$select app_finance.send_network_add_request(
      '00000000-0000-0000-0000-0000000000f2', 'Ahmed')$$,
  'owner adds Ahmed'
);
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_add_request(
      (select r.id from app_finance.network_add_requests r
        where r.recipient_user_id = '00000000-0000-0000-0000-0000000000f2'
          and r.status = 'pending'), 'Tarek')$$,
  'Ahmed accepts the connection'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
insert into reimb_ids values ('conn',
  (select connection_id from app_finance.list_network_contacts()));
select lives_ok(
  $$select app_finance.request_installment_responsibility(
      '00000000-0000-0000-0000-00000000ff01',
      (select id from reimb_ids where key = 'conn'), null)$$,
  'owner requests responsibility from Ahmed'
);
insert into reimb_ids values ('netlink',
  (select id from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ff01'));
select lives_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ff02', 'Mohamed', null)$$,
  'owner links the second plan to a custom person'
);
insert into reimb_ids values ('customlink',
  (select id from app_finance.installment_responsibility_links
    where plan_id = '00000000-0000-0000-0000-00000000ff02'));

-- Capture due ids while the owner's RLS context is active.
insert into reimb_ids values ('due1',
  (select d.id from app_finance.installment_dues d
    where d.plan_id = '00000000-0000-0000-0000-00000000ff01'
      and d.sequence_number = 1));
insert into reimb_ids values ('due2',
  (select d.id from app_finance.installment_dues d
    where d.plan_id = '00000000-0000-0000-0000-00000000ff01'
      and d.sequence_number = 2));

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_installment_responsibility(
      (select id from reimb_ids where key = 'netlink'))$$,
  'Ahmed accepts the responsibility'
);

-- ---------------------------------------------------------------------------
-- Network reimbursement: pending moves nothing
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.create_installment_network_reimbursement(
      (select id from reimb_ids where key = 'netlink'),
      (select id from reimb_ids where key = 'due1'), 100000,
      '00000000-0000-0000-0000-00000000f201', null,
      '00000000-0000-0000-0000-00000000fa01')$$,
  'Ahmed sends a reimbursement for due #1'
);
select results_eq(
  $$select status::text, method::text, amount_minor, currency_code
    from app_finance.installment_reimbursements
    where id = '00000000-0000-0000-0000-00000000fa01'$$,
  $$values ('pending', 'network_transfer', 100000::bigint, 'EGP')$$,
  'the reimbursement starts pending with the canonical amount'
);
select results_eq(
  $$select nt.status::text, nt.origin_kind::text
    from app_finance.network_transfers nt
    where nt.origin_id = '00000000-0000-0000-0000-00000000fa01'$$,
  $$values ('pending', 'installment_reimbursement')$$,
  'a pending network transfer carries the reimbursement origin'
);
select results_eq(
  $$select b.balance_minor from app_finance.account_balances b
    where b.account_id = '00000000-0000-0000-0000-00000000f201'$$,
  $$values (2000000::bigint)$$,
  'pending reimbursement leaves the sender balance untouched'
);
select lives_ok(
  $$select app_finance.create_installment_network_reimbursement(
      (select id from reimb_ids where key = 'netlink'),
      (select id from reimb_ids where key = 'due1'), 100000,
      '00000000-0000-0000-0000-00000000f201', null,
      '00000000-0000-0000-0000-00000000fa01')$$,
  'resubmitting the same reimbursement id is idempotent'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_reimbursements
    where due_id = (select id from reimb_ids where key = 'due1')$$,
  $$values (1)$$,
  'the retry created no duplicate'
);
select throws_ok(
  $$select app_finance.create_installment_network_reimbursement(
      (select id from reimb_ids where key = 'netlink'),
      (select id from reimb_ids where key = 'due1'), 1,
      '00000000-0000-0000-0000-00000000f201', null)$$,
  'reimbursement_exceeds_due: amount is larger than the remaining responsibility',
  'the pending amount reserves the due: no over-collection'
);

-- ---------------------------------------------------------------------------
-- Owner accepts: money moves once, the card does not
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select lives_ok(
  $$select app_finance.accept_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.origin_id = '00000000-0000-0000-0000-00000000fa01'),
      '00000000-0000-0000-0000-00000000f101')$$,
  'owner accepts the reimbursement into their own bank account'
);
select results_eq(
  $$select status::text, (received_on is not null),
      owner_destination_account_id, (owner_transaction_id is not null)
    from app_finance.installment_reimbursements
    where id = '00000000-0000-0000-0000-00000000fa01'$$,
  $$values ('received', true,
    '00000000-0000-0000-0000-00000000f101'::uuid, true)$$,
  'acceptance settles the reimbursement server-side'
);
select results_eq(
  $$select b.balance_minor from app_finance.account_balances b
    where b.account_id = '00000000-0000-0000-0000-00000000f101'$$,
  $$values (5100000::bigint)$$,
  'the owner asset account rose exactly once'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from reimb_ids where key = 'card'))$$,
  $$values (2000000::bigint)$$,
  'the Credit Card liability is completely unchanged'
);
select results_eq(
  $$select count(*)::integer
    from app_finance.installment_payment_allocations
    where user_id = '00000000-0000-0000-0000-0000000000f1'$$,
  $$values (0)$$,
  'no installment payment allocation was written'
);
select results_eq(
  $$select s.remaining_minor from app_finance.installment_due_statuses s
    where s.id = (select id from reimb_ids where key = 'due1')$$,
  $$values (100000::bigint)$$,
  'the bank due is still unpaid: reimbursement is not facility repayment'
);
select results_eq(
  $$select count(*)::integer from app_finance.financial_transactions
    where user_id = '00000000-0000-0000-0000-0000000000f1'
      and transaction_kind in
        ('custom_income', 'freelance_income', 'salary_income')$$,
  $$values (0)$$,
  'the reimbursement is a transfer, never income'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select results_eq(
  $$select b.balance_minor from app_finance.account_balances b
    where b.account_id = '00000000-0000-0000-0000-00000000f201'$$,
  $$values (1900000::bigint)$$,
  'the sender paid exactly once'
);

-- ---------------------------------------------------------------------------
-- Rejection frees the reserved amount
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.create_installment_network_reimbursement(
      (select id from reimb_ids where key = 'netlink'),
      (select id from reimb_ids where key = 'due2'), 100000,
      '00000000-0000-0000-0000-00000000f201', null,
      '00000000-0000-0000-0000-00000000fa02')$$,
  'Ahmed sends a reimbursement for due #2'
);
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select lives_ok(
  $$select app_finance.reject_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.origin_id = '00000000-0000-0000-0000-00000000fa02'))$$,
  'owner rejects the second reimbursement'
);
select results_eq(
  $$select status::text from app_finance.installment_reimbursements
    where id = '00000000-0000-0000-0000-00000000fa02'$$,
  $$values ('rejected')$$,
  'the reimbursement is rejected with the transfer'
);
set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select results_eq(
  $$select b.balance_minor from app_finance.account_balances b
    where b.account_id = '00000000-0000-0000-0000-00000000f201'$$,
  $$values (1900000::bigint)$$,
  'rejection books nothing'
);
select lives_ok(
  $$select app_finance.create_installment_network_reimbursement(
      (select id from reimb_ids where key = 'netlink'),
      (select id from reimb_ids where key = 'due2'), 100000,
      '00000000-0000-0000-0000-00000000f201', null,
      '00000000-0000-0000-0000-00000000fa03')$$,
  'the full amount is available again after rejection'
);

-- ---------------------------------------------------------------------------
-- Restructure protection and changed terms
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
select throws_ok(
  $$select app_finance.restructure_installment_plan(
      '00000000-0000-0000-0000-00000000ff01', 1050000, 7,
      (current_date + 20)::date, 'restructure')$$,
  'reimbursement_pending: resolve the pending reimbursement before changing this installment',
  'a pending reimbursement blocks the restructure'
);
select lives_ok(
  $$select app_finance.reject_network_transfer(
      (select nt.id from app_finance.network_transfers nt
        where nt.origin_id = '00000000-0000-0000-0000-00000000fa03'))$$,
  'owner clears the pending reimbursement'
);
select lives_ok(
  $$select app_finance.restructure_installment_plan(
      '00000000-0000-0000-0000-00000000ff01', 1050000, 7,
      (current_date + 20)::date, 'restructure')$$,
  'the restructure then succeeds'
);
select results_eq(
  $$select amount_minor, due_sequence_number, (due_id is null)
    from app_finance.installment_reimbursements
    where id = '00000000-0000-0000-0000-00000000fa01'$$,
  $$values (100000::bigint, 1, true)$$,
  'received history survives the restructure with its recorded sequence'
);

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}';
select throws_ok(
  $$select app_finance.create_installment_network_reimbursement(
      (select id from reimb_ids where key = 'netlink'),
      (select d.id from app_finance.installment_dues d
        where d.plan_id = '00000000-0000-0000-0000-00000000ff01'
        order by d.sequence_number limit 1), 100000,
      '00000000-0000-0000-0000-00000000f201', null)$$,
  'terms_changed: this installment changed after you accepted it',
  'materially changed terms block new reimbursements until re-consent'
);

-- ---------------------------------------------------------------------------
-- Custom reimbursement: protected one-sided inflow, partial then full
-- ---------------------------------------------------------------------------

set local request.jwt.claims to
  '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}';
insert into reimb_ids values ('cdue1',
  (select d.id from app_finance.installment_dues d
    where d.plan_id = '00000000-0000-0000-0000-00000000ff02'
      and d.sequence_number = 1));

select lives_ok(
  $$select app_finance.record_custom_installment_reimbursement(
      (select id from reimb_ids where key = 'customlink'),
      (select id from reimb_ids where key = 'cdue1'), 120000,
      current_date, '00000000-0000-0000-0000-00000000f101', 'cash from Mohamed',
      '00000000-0000-0000-0000-00000000fa04')$$,
  'owner records a partial custom reimbursement'
);
select results_eq(
  $$select t.transaction_kind::text, t.source_account_id,
      t.destination_account_id, t.is_reimbursement_inflow
    from app_finance.financial_transactions t
    where t.installment_reimbursement_id
      = '00000000-0000-0000-0000-00000000fa04'$$,
  $$values ('transfer', null::uuid,
    '00000000-0000-0000-0000-00000000f101'::uuid, true)$$,
  'the inflow is a protected one-sided transfer into the owner account'
);
select results_eq(
  $$select b.balance_minor from app_finance.account_balances b
    where b.account_id = '00000000-0000-0000-0000-00000000f101'$$,
  $$values (5220000::bigint)$$,
  'the owner asset rose by the recorded amount'
);
select results_eq(
  $$select app_finance.facility_outstanding_minor(
      (select id from reimb_ids where key = 'card'))$$,
  $$values (2050000::bigint)$$,
  'the facility owes only the restructure delta, never the reimbursements'
);

select throws_ok(
  $$select app_finance.record_custom_installment_reimbursement(
      (select id from reimb_ids where key = 'customlink'),
      (select id from reimb_ids where key = 'cdue1'), 90000,
      current_date, '00000000-0000-0000-0000-00000000f101', null)$$,
  'reimbursement_exceeds_due: amount is larger than the remaining responsibility',
  'overpaying a due is rejected'
);
select lives_ok(
  $$select app_finance.record_custom_installment_reimbursement(
      (select id from reimb_ids where key = 'customlink'),
      (select id from reimb_ids where key = 'cdue1'), 80000,
      current_date, '00000000-0000-0000-0000-00000000f101', null,
      '00000000-0000-0000-0000-00000000fa05')$$,
  'the exact remainder completes the due'
);

-- Generic editing cannot touch reimbursement ledger rows.
select throws_ok(
  $$update app_finance.financial_transactions
    set notes = 'edited'
    where installment_reimbursement_id
      = '00000000-0000-0000-0000-00000000fa04'$$,
  'reimbursement_transaction_locked: recorded reimbursements cannot be edited directly',
  'recorded reimbursement rows are read-only for generic edits'
);
select throws_ok(
  $$delete from app_finance.financial_transactions
    where installment_reimbursement_id
      = '00000000-0000-0000-0000-00000000fa04'$$,
  'reimbursement_transaction_locked: recorded reimbursements cannot be edited directly',
  'recorded reimbursement rows cannot be deleted directly'
);
select throws_ok(
  $$insert into app_finance.financial_transactions (
      user_id, transaction_kind, occurred_on, amount_minor, currency_code,
      destination_account_id, is_reimbursement_inflow
    ) values (
      '00000000-0000-0000-0000-0000000000f1', 'transfer', current_date,
      100, 'EGP', '00000000-0000-0000-0000-00000000f101', true)$$,
  'reimbursement_transaction_locked: reimbursements are recorded from the installment screen',
  'clients cannot forge one-sided reimbursement inflows'
);

-- ---------------------------------------------------------------------------
-- Reassignment: history stays, the same due is never collected twice
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select app_finance.remove_installment_responsibility(
      (select id from reimb_ids where key = 'customlink'))$$,
  'owner unlinks Mohamed'
);
select results_eq(
  $$select count(*)::integer from app_finance.installment_reimbursements
    where responsibility_link_id
      = (select id from reimb_ids where key = 'customlink')$$,
  $$values (2)$$,
  'Mohamed''s reimbursement history remains attributed to him'
);
select lives_ok(
  $$select app_finance.link_installment_to_custom_person(
      '00000000-0000-0000-0000-00000000ff02', 'Mona', null)$$,
  'owner links Mona instead'
);
select throws_ok(
  $$select app_finance.record_custom_installment_reimbursement(
      (select id from app_finance.installment_responsibility_links
        where plan_id = '00000000-0000-0000-0000-00000000ff02'
          and removed_at is null),
      (select id from reimb_ids where key = 'cdue1'), 1,
      current_date, '00000000-0000-0000-0000-00000000f101', null)$$,
  'reimbursement_exceeds_due: amount is larger than the remaining responsibility',
  'a due already covered by Mohamed cannot be collected again from Mona'
);
select lives_ok(
  $$select app_finance.record_custom_installment_reimbursement(
      (select id from app_finance.installment_responsibility_links
        where plan_id = '00000000-0000-0000-0000-00000000ff02'
          and removed_at is null),
      (select d.id from app_finance.installment_dues d
        where d.plan_id = '00000000-0000-0000-0000-00000000ff02'
          and d.sequence_number = 2), 200000,
      current_date, '00000000-0000-0000-0000-00000000f101', null)$$,
  'Mona covers the next due normally'
);

select * from finish();
rollback;
