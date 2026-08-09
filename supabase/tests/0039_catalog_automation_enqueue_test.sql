begin;
create extension if not exists pgtap with schema extensions;

select plan(21);

select has_function(
  'app_finance',
  'enqueue_catalog_research_automation',
  array[
    'app_finance.account_type','text','text','text','text','text','text','text',
    'app_finance.catalog_queue_reason','integer'
  ],
  'catalog automation enqueue RPC exists'
);

select ok(
  has_function_privilege(
    'authenticated',
    'app_finance.enqueue_catalog_research(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer)',
    'execute'
  ),
  'authenticated retains access to the user enqueue RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'app_finance.enqueue_catalog_research_automation(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer)',
    'execute'
  ),
  'anon has no execute privilege on automation enqueue'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'app_finance.enqueue_catalog_research_automation(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer)',
    'execute'
  ),
  'ordinary authenticated has no execute privilege on automation enqueue'
);
select ok(
  has_function_privilege(
    'service_role',
    'app_finance.enqueue_catalog_research_automation(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer)',
    'execute'
  ),
  'service role can execute automation enqueue'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-4000-8000-00000000cb01',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalog-enqueue-user@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

create temp table catalog_account_count_before as
select count(*)::bigint account_count from app_finance.accounts;

select throws_ok(
  $$select * from app_finance.enqueue_catalog_research(
    'credit_card','EG','No JWT Bank','No JWT Card')$$,
  '28000', 'authentication required',
  'user enqueue still rejects a caller without auth.uid()'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000cb01","role":"authenticated"}';

select is(
  (select queue_status::text from app_finance.enqueue_catalog_research(
    'credit_card','eg','User Bank','User Card',null,'visa','egp',
    'https://user-bank.example','user_requested',25)),
  'queued',
  'ordinary authenticated user can use the user enqueue RPC'
);

set local role postgres;
select is(
  (select requested_by from app_finance.catalog_research_queue
   where issuer_name = 'User Bank'),
  '00000000-0000-4000-8000-00000000cb01'::uuid,
  'user enqueue records auth.uid() in requested_by'
);

set local role anon;
select throws_ok(
  $$select * from app_finance.enqueue_catalog_research_automation(
    'credit_card','EG','Anon Bank','Anon Card')$$,
  '42501', null,
  'anon cannot execute automation enqueue'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000cb01","role":"authenticated"}';
select throws_ok(
  $$select * from app_finance.enqueue_catalog_research_automation(
    'credit_card','EG','Authenticated Bank','Authenticated Card')$$,
  '42501', null,
  'ordinary authenticated cannot execute automation enqueue'
);

set local role postgres;
select is(
  (select queue_status::text from app_finance.enqueue_catalog_research_automation(
    'credit_card','eg',' Automation Bank ','Seed Card',null,'VISA','egp',
    'https://automation-bank.example','initial_seed',5000)),
  'queued',
  'database owner can enqueue initial_seed work without JWT claims'
);

set local role service_role;
select is(
  (select queue_status::text from app_finance.enqueue_catalog_research_automation(
    'bnpl','EG','Source Provider','Source Plan',null,null,'EGP',
    'https://source-provider.example','source_changed',30)),
  'queued',
  'service role can enqueue source_changed work without JWT claims'
);

set local role postgres;
select is(
  (select queue_item_id from app_finance.enqueue_catalog_research_automation(
    'credit_card','EG','automation   bank',' seed card ',null,'visa','EGP',
    'https://automation-bank.example','initial_seed',0)),
  (select id from app_finance.catalog_research_queue
   where issuer_name = 'Automation Bank' and status = 'queued'),
  'automation enqueue deduplicates normalized equivalent queued work'
);

select throws_ok(
  $$select * from app_finance.enqueue_catalog_research_automation(
    'credit_card','EGY','Bad Country','Card')$$,
  'invalid public product identity',
  'automation enqueue rejects malformed country code'
);
select throws_ok(
  $$select * from app_finance.enqueue_catalog_research_automation(
    'credit_card','EG','Bad Currency','Card',null,'visa','EGPT')$$,
  'invalid public product identity',
  'automation enqueue rejects malformed currency code'
);
select throws_ok(
  $$select * from app_finance.enqueue_catalog_research_automation(
    'credit_card','EG','Bad Network','Card',null,'amex','EGP')$$,
  'invalid public product identity',
  'automation enqueue rejects invalid network'
);
select throws_ok(
  $$select * from app_finance.enqueue_catalog_research_automation(
    'credit_card','EG','Bad Website','Card',null,'visa','EGP','ftp://bank.example')$$,
  'invalid public product identity',
  'automation enqueue rejects non-http official website'
);

select is(
  (select requested_by from app_finance.catalog_research_queue
   where issuer_name = 'Automation Bank'),
  null::uuid,
  'automation enqueue stores requested_by as null'
);
select is(
  (select priority from app_finance.catalog_research_queue
   where issuer_name = 'Automation Bank'),
  1000,
  'automation enqueue clamps priority safely'
);
select is(
  (select country_code || '|' || network || '|' || currency_code
   from app_finance.catalog_research_queue where issuer_name = 'Automation Bank'),
  'EG|visa|EGP',
  'automation enqueue uses canonical country, network, and currency normalization'
);
select is(
  (select count(*)::bigint from app_finance.accounts),
  (select account_count from catalog_account_count_before),
  'neither enqueue path creates or updates a financial account'
);

select * from finish();
rollback;
