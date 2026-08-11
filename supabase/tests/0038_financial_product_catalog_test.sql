begin;
create extension if not exists pgtap with schema extensions;

select plan(65);

select has_table('app_finance', 'catalog_configuration', 'catalog configuration exists');
select has_table('app_finance', 'financial_product_catalog', 'catalog products table exists');
select has_table('app_finance', 'financial_product_catalog_versions', 'catalog versions table exists');
select has_table('app_finance', 'financial_product_catalog_sources', 'catalog sources table exists');
select has_table('app_finance', 'catalog_research_queue', 'catalog queue table exists');
select has_table('app_finance', 'catalog_research_runs', 'catalog runs table exists');
select has_function('app_finance', 'get_catalog_research_contract', array[]::text[], 'contract RPC exists');
select has_function('app_finance', 'catalog_search', array['app_finance.account_type','text','text','text','text','text','text'], 'search RPC exists');
select has_function('app_finance', 'enqueue_catalog_research', array['app_finance.account_type','text','text','text','text','text','text','text','app_finance.catalog_queue_reason','integer'], 'enqueue RPC exists');
select has_function('app_finance', 'enqueue_due_catalog_research', array[]::text[], 'stale enqueue RPC exists');
select has_function('app_finance', 'get_catalog_research_work', array['integer'], 'lease RPC exists');
select has_function('app_finance', 'upsert_catalog_research_result', array['jsonb'], 'result RPC exists');
select has_function('app_finance', 'fail_catalog_research_work', array['uuid','text'], 'failure RPC exists');
select has_function('app_finance', 'record_catalog_automation_heartbeat', array['text'], 'heartbeat RPC exists');
select has_function('app_finance', 'catalog_status_summary', array[]::text[], 'summary RPC exists');

select ok(not has_table_privilege('anon', 'app_finance.financial_product_catalog', 'insert'), 'anon has no direct catalog insert');
select ok(not has_table_privilege('authenticated', 'app_finance.financial_product_catalog', 'insert'), 'authenticated has no direct catalog insert');
select ok(has_function_privilege('authenticated', 'app_finance.get_catalog_research_contract()', 'execute'), 'authenticated can read contract');
select ok(has_function_privilege('authenticated', 'app_finance.catalog_search(app_finance.account_type,text,text,text,text,text,text)', 'execute'), 'authenticated can search');
select ok(not has_function_privilege('authenticated', 'app_finance.get_catalog_research_work(integer)', 'execute'), 'authenticated cannot lease work');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-4000-8000-00000000ca01',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'catalog-user@test.local', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

set local role anon;
select throws_ok(
  $$insert into app_finance.financial_product_catalog
    (account_type,country_code,issuer_name,product_name,identity_key)
    values ('credit_card','EG','Unsafe','Unsafe','unsafe')$$,
  '42501', null, 'anon direct write is denied'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000ca01","role":"authenticated"}';
select throws_ok(
  $$insert into app_finance.financial_product_catalog
    (account_type,country_code,issuer_name,product_name,identity_key)
    values ('credit_card','EG','Unsafe','Unsafe','unsafe')$$,
  '42501', null, 'authenticated direct write is denied'
);

select is(
  (select queue_status::text from app_finance.enqueue_catalog_research(
    'credit_card','eg','  CIB  ','Gold',null,'visa','egp',
    'https://www.cibeg.com','user_requested',10)),
  'queued', 'authenticated public identity can be queued'
);
select is(
  (select count(*)::integer from app_finance.enqueue_catalog_research(
    'credit_card','EG','cib',' gold ',null,'visa','EGP',
    'https://www.cibeg.com','user_requested',10)),
  1, 'equivalent outstanding work is returned once'
);

set local role postgres;
select is(
  (select count(*)::integer from app_finance.catalog_research_queue
   where issuer_name = 'CIB' and status in ('queued','leased')),
  1, 'case and whitespace insensitive queue deduplication works'
);

set local role service_role;
create temp table catalog_first_lease as
  select * from app_finance.get_catalog_research_work(1);
select is((select count(*)::integer from catalog_first_lease), 1, 'one curator leases the work item');
select is((select count(*)::integer from app_finance.get_catalog_research_work(1)), 0, 'a second lease cannot claim the same item');

set local role postgres;
insert into app_finance.catalog_research_queue (
  account_type,country_code,issuer_name,product_name,identity_key,work_key,
  reason,priority
)
select 'bnpl','EG','Batch Issuer ' || g,'Batch Product ' || g,'pending','pending',
  'initial_seed',-100 from generate_series(1,7) g;

set local role service_role;
select is((select count(*)::integer from app_finance.get_catalog_research_work(999)), 5, 'lease limit is clamped to configured batch size');

set local role postgres;
update app_finance.catalog_research_queue
set lease_expires_at = now() - interval '1 minute', priority = 800
where id = (select id from app_finance.catalog_research_queue
            where issuer_name like 'Batch Issuer %' and status = 'leased' limit 1);
set local role service_role;
select is((select count(*)::integer from app_finance.get_catalog_research_work(1)), 1, 'expired leases become eligible again');

set local role postgres;
create or replace function pg_temp.catalog_payload(
  p_queue_id uuid,
  p_due_day integer default 25
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'contractVersion','finance-card-catalog-v1',
    'queueItemId',q.id,
    'productIdentity',jsonb_build_object(
      'accountType',q.account_type,'countryCode',q.country_code,
      'issuerName',q.issuer_name,'officialWebsite',q.official_website,
      'productName',q.product_name,'tier',q.tier,'network',q.network,
      'currencyCode',q.currency_code
    ),
    'researchStatus','resolved',
    'research',jsonb_build_object(
      'product',jsonb_build_object(
        'issuerName',jsonb_build_object('value',q.issuer_name,'status','verified','confidence','high','sourceIds',jsonb_build_array('official')),
        'productName',jsonb_build_object('value',q.product_name,'status','verified','confidence','high','sourceIds',jsonb_build_array('official')),
        'tier',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'network',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'currencyCode',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb)
      ),
      'accountForm',jsonb_build_object(
        'suggestedName',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'creditLimitMinor',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'defaultDueDay',jsonb_build_object('value',p_due_day,'status','verified','confidence','high','sourceIds',jsonb_build_array('official')),
        'statementDay',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'minPaymentMethod',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'minPaymentFixedMinor',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb),
        'minPaymentBasisPoints',jsonb_build_object('value',null,'status','unknown','confidence',null,'sourceIds','[]'::jsonb)
      ),
      'rules','[]'::jsonb,
      'installmentTenors','[]'::jsonb,
      'sources',jsonb_build_array(jsonb_build_object(
        'id','official','url','https://issuer.example/products/current',
        'title','Official product tariff','officialDomain',true,
        'publishedDate',null,'effectiveDate','2026-08-01'
      )),
      'unresolvedRequiredFields','[]'::jsonb,
      'conflicts','[]'::jsonb,
      'unsupportedFindings','[]'::jsonb
    )
  )
  from app_finance.catalog_research_queue q where q.id = p_queue_id;
$$;

select is(
  (select changed from app_finance.upsert_catalog_research_result(
    pg_temp.catalog_payload((select queue_item_id from catalog_first_lease)))),
  true, 'first resolved research creates a version'
);
select is((select count(*)::integer from app_finance.financial_product_catalog_versions where product_id =
  (select id from app_finance.financial_product_catalog where issuer_name = 'CIB')), 1, 'first research creates exactly one version');
select is((select count(*)::integer from app_finance.financial_product_catalog_sources), 1, 'source provenance is persisted');

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000ca01","role":"authenticated"}';
select is((select count(*)::integer from app_finance.catalog_search('credit_card','EG','cib','gold',null,'visa','EGP')), 1, 'authenticated catalog search returns a match');
select is((select is_fresh from app_finance.catalog_search('credit_card','EG','cib','gold',null,'visa','EGP')), true, 'newly verified catalog result is fresh');

set local role postgres;
insert into app_finance.catalog_research_queue (
  product_id,account_type,country_code,issuer_name,official_website,product_name,
  tier,network,currency_code,identity_key,work_key,reason,priority
)
select id,account_type,country_code,issuer_name,official_website,product_name,
  tier,network,currency_code,identity_key,'pending','manual_review',900
from app_finance.financial_product_catalog where issuer_name = 'CIB';
select is((select count(*)::integer from app_finance.get_catalog_research_work(1)), 1, 'unchanged research work is leased');
select is(
  (select changed from app_finance.upsert_catalog_research_result(pg_temp.catalog_payload(
    (select id from app_finance.catalog_research_queue where product_id =
      (select id from app_finance.financial_product_catalog where issuer_name = 'CIB')
      and status = 'leased' order by created_at desc limit 1)))),
  false, 'materially unchanged research does not create a version'
);
select is((select count(*)::integer from app_finance.financial_product_catalog_versions where product_id =
  (select id from app_finance.financial_product_catalog where issuer_name = 'CIB')), 1, 'unchanged check leaves one version');

insert into app_finance.catalog_research_queue (
  product_id,account_type,country_code,issuer_name,official_website,product_name,
  tier,network,currency_code,identity_key,work_key,reason,priority
)
select id,account_type,country_code,issuer_name,official_website,product_name,
  tier,network,currency_code,identity_key,'pending','source_changed',900
from app_finance.financial_product_catalog where issuer_name = 'CIB';
select is((select count(*)::integer from app_finance.get_catalog_research_work(1)), 1, 'changed research work is leased');
select is(
  (select changed from app_finance.upsert_catalog_research_result(pg_temp.catalog_payload(
    (select id from app_finance.catalog_research_queue where product_id =
      (select id from app_finance.financial_product_catalog where issuer_name = 'CIB')
      and status = 'leased' order by created_at desc limit 1), 26))),
  true, 'materially changed research creates a version'
);
select is((select count(*)::integer from app_finance.financial_product_catalog_versions where product_id =
  (select id from app_finance.financial_product_catalog where issuer_name = 'CIB')), 2, 'changed research creates exactly one additional version');
select is((select research_payload #>> '{accountForm,defaultDueDay,value}' from app_finance.financial_product_catalog_versions
  where product_id = (select id from app_finance.financial_product_catalog where issuer_name = 'CIB') and version_number = 1), '25', 'prior version payload remains intact');
select ok((select superseded_at is not null from app_finance.financial_product_catalog_versions
  where product_id = (select id from app_finance.financial_product_catalog where issuer_name = 'CIB') and version_number = 1), 'prior version is marked superseded');

insert into app_finance.catalog_research_queue (
  account_type,country_code,issuer_name,product_name,network,currency_code,
  identity_key,work_key,reason,priority
) values ('credit_card','EG','Validation Bank','Safe Card','visa','EGP','pending','pending','manual_review',950);
select is((select count(*)::integer from app_finance.get_catalog_research_work(1)), 1, 'validation work is leased');

select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{contractVersion}','"wrong-v1"'))$$,
  'unsupported catalog research contract version', 'wrong contract version is rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')) - 'research')$$,
  'productIdentity and research objects are required', 'malformed contract payload is rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,accountForm,defaultDueDay,status}','"user_provided"'))$$,
  'user_provided field status is forbidden in the global catalog', 'user_provided status is rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,accountForm,creditLimitMinor,value}','500000'))$$,
  'personal credit limit is forbidden in the global catalog', 'personal credit limits are rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,product,pan}','"4111111111111111"'))$$,
  'forbidden private field in catalog payload: pan', 'PAN fields are rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,product,cvv}','"123"'))$$,
  'forbidden private field in catalog payload: cvv', 'CVV fields are rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,product,pin}','"1234"'))$$,
  'forbidden private field in catalog payload: pin', 'PIN fields are rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,product,otp}','"123456"'))$$,
  'forbidden private field in catalog payload: otp', 'OTP fields are rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,accountForm,defaultDueDay,sourceIds}','["missing-source"]'))$$,
  'research field references an unknown source identifier', 'unknown source references are rejected'
);
select throws_ok(
  $$select * from app_finance.upsert_catalog_research_result(
    jsonb_set(pg_temp.catalog_payload((select id from app_finance.catalog_research_queue where issuer_name='Validation Bank')),
      '{research,rules}', '[{"feeType":"invented_fee","calculationType":"fixed","frequency":"once","fixedAmountMinor":10,"percentBasis":null,"status":"verified","confidence":"high","sourceIds":["official"]}]'))$$,
  'unknown fee rule enum value', 'unknown catalog enum values are rejected'
);

update app_finance.financial_product_catalog set last_checked_at = now() - interval '31 days'
where issuer_name = 'CIB';
select is((select queued_count from app_finance.enqueue_due_catalog_research()), 1, 'stale active products are queued for refresh');
update app_finance.financial_product_catalog set status = 'retired' where issuer_name = 'CIB';
set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000ca01","role":"authenticated"}';
select is((select count(*)::integer from app_finance.catalog_search('credit_card','EG','CIB','Gold',null,'visa','EGP')), 0, 'retired products are not automatic matches');

set local role postgres;
insert into app_finance.catalog_research_queue (
  account_type,country_code,issuer_name,product_name,identity_key,work_key,
  reason,priority
) values ('bnpl','EG','Retry Provider','Retry Plan','pending','pending','manual_review',1000);
select is((select count(*)::integer from app_finance.get_catalog_research_work(1)), 1, 'failure test work is leased');
select is((select queue_status::text from app_finance.fail_catalog_research_work(
  (select id from app_finance.catalog_research_queue where issuer_name='Retry Provider'),
  'provider timeout 4111111111111111 CVV: 123')), 'queued', 'failed work is retried below max attempts');
select ok((select last_error not like '%411111%123%' and last_error not like '%CVV: 123%'
  from app_finance.catalog_research_queue where issuer_name='Retry Provider'),
  'failure errors redact obvious PAN and CVV data');
update app_finance.catalog_research_queue set available_at=now() where issuer_name='Retry Provider';
select * from app_finance.get_catalog_research_work(1);
select * from app_finance.fail_catalog_research_work(
  (select id from app_finance.catalog_research_queue where issuer_name='Retry Provider'), 'provider timeout');
update app_finance.catalog_research_queue set available_at=now() where issuer_name='Retry Provider';
select * from app_finance.get_catalog_research_work(1);
select is((select queue_status::text from app_finance.fail_catalog_research_work(
  (select id from app_finance.catalog_research_queue where issuer_name='Retry Provider'),
  'provider timeout')), 'failed', 'work permanently fails at configured max attempts');

create temp table catalog_counts_before as select
  (select count(*) from app_finance.financial_product_catalog) products,
  (select count(*) from app_finance.accounts) accounts,
  (select count(*) from app_finance.catalog_research_runs) runs;
select ok((select run_id is not null from app_finance.record_catalog_automation_heartbeat('catalog-heartbeat')), 'heartbeat returns a run ID');
select is((select count(*) from app_finance.catalog_research_runs),
  (select runs + 1 from catalog_counts_before), 'heartbeat writes exactly one run audit row');
select is((select count(*) from app_finance.financial_product_catalog),
  (select products from catalog_counts_before), 'heartbeat touches no catalog product data');
select is((select count(*) from app_finance.accounts),
  (select accounts from catalog_counts_before), 'catalog APIs do not create or update financial accounts');
select is(app_finance.catalog_status_summary() ->> 'contractVersion',
  'finance-card-catalog-v1', 'status summary publishes current contract version');

select throws_ok(
  $$update app_finance.financial_product_catalog_versions set research_payload='{}'::jsonb
    where version_number=1$$,
  'catalog version payloads are immutable', 'historical version payloads cannot be updated'
);

select * from finish();
rollback;
