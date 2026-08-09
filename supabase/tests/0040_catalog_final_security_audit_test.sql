begin;
create extension if not exists pgtap with schema extensions;

select plan(34);

select ok(
  not has_function_privilege(
    'service_role',
    'app_private.enqueue_catalog_research_common(app_finance.account_type,text,text,text,text,text,text,text,app_finance.catalog_queue_reason,integer,uuid)',
    'execute'
  ),
  'service role cannot bypass the public catalog enqueue wrappers'
);
select ok(
  not has_function_privilege(
    'authenticated', 'app_private.catalog_json_nodes(jsonb)', 'execute'
  ),
  'authenticated cannot execute catalog private helpers'
);
select ok(
  not has_function_privilege(
    'anon', 'app_finance.catalog_status_summary()', 'execute'
  ),
  'anon cannot execute the operational summary'
);
select ok(
  not has_function_privilege(
    'authenticated', 'app_finance.upsert_catalog_research_result(jsonb)',
    'execute'
  ),
  'authenticated cannot execute the curator result writer'
);
select ok(
  has_function_privilege(
    'service_role', 'app_finance.upsert_catalog_research_result(jsonb)',
    'execute'
  ),
  'service role can execute the curator result writer'
);
select ok(
  not (select p.prosecdef from pg_catalog.pg_proc p
       where p.oid = 'app_finance.get_catalog_research_contract()'::regprocedure),
  'constant research contract RPC runs without definer privileges'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'app_finance.financial_product_catalog'::regclass),
  'catalog products have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'app_finance.financial_product_catalog_versions'::regclass),
  'catalog versions have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'app_finance.financial_product_catalog_sources'::regclass),
  'catalog sources have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'app_finance.catalog_research_queue'::regclass),
  'catalog queue has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'app_finance.catalog_research_runs'::regclass),
  'catalog runs have RLS enabled'
);

create temp table catalog_financial_state_before as
select
  (select count(*) from app_finance.accounts) accounts,
  (select count(*) from app_finance.financial_transactions) transactions,
  (select count(*) from app_finance.credit_card_statement_cycles) statements,
  (select count(*) from app_finance.installment_plans) installments;

select is(
  (select queue_status::text
   from app_finance.enqueue_catalog_research_automation(
     'credit_card', 'EG', 'Audit Bank', 'Secure Card', 'Gold', 'visa',
     'EGP', 'https://audit.example', 'initial_seed', 50
   )),
  'queued',
  'trusted automation queues public product identity'
);

set local role service_role;
create temp table catalog_audit_lease as
select * from app_finance.get_catalog_research_work(1);
select is(
  (select count(*)::integer from catalog_audit_lease), 1,
  'trusted curator leases audit work'
);

set local role postgres;
create or replace function pg_temp.audit_payload(
  p_queue_id uuid,
  p_due_day integer default 20
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'contractVersion', 'finance-card-catalog-v1',
    'queueItemId', q.id,
    'productIdentity', jsonb_build_object(
      'accountType', q.account_type,
      'countryCode', q.country_code,
      'issuerName', q.issuer_name,
      'officialWebsite', q.official_website,
      'productName', q.product_name,
      'tier', q.tier,
      'network', q.network,
      'currencyCode', q.currency_code
    ),
    'researchStatus', 'resolved',
    'research', jsonb_build_object(
      'product', jsonb_build_object(
        'issuerName', jsonb_build_object(
          'value', q.issuer_name, 'status', 'verified',
          'confidence', 'high', 'sourceIds', jsonb_build_array('official')
        ),
        'productName', jsonb_build_object(
          'value', q.product_name, 'status', 'verified',
          'confidence', 'high', 'sourceIds', jsonb_build_array('official')
        )
      ),
      'accountForm', jsonb_build_object(
        'creditLimitMinor', jsonb_build_object(
          'value', null, 'status', 'unknown',
          'confidence', null, 'sourceIds', '[]'::jsonb
        ),
        'defaultDueDay', jsonb_build_object(
          'value', p_due_day, 'status', 'verified',
          'confidence', 'medium', 'sourceIds', jsonb_build_array('official')
        )
      ),
      'rules', '[]'::jsonb,
      'installmentTenors', '[]'::jsonb,
      'sources', jsonb_build_array(jsonb_build_object(
        'id', 'official',
        'url', 'https://audit.example/secure-card',
        'title', 'Official tariff',
        'officialDomain', true,
        'publishedDate', null,
        'effectiveDate', '2026-08-01'
      )),
      'unresolvedRequiredFields', '[]'::jsonb,
      'conflicts', '[]'::jsonb,
      'unsupportedFindings', '[]'::jsonb
    )
  )
  from app_finance.catalog_research_queue q where q.id = p_queue_id;
$$;

select is(
  (select changed from app_finance.upsert_catalog_research_result(
    pg_temp.audit_payload((select queue_item_id from catalog_audit_lease))
  )),
  true,
  'validated public research creates the first immutable version'
);
select is(
  (select count(*)::integer
   from app_finance.financial_product_catalog_sources s
   join app_finance.financial_product_catalog_versions v on v.id = s.version_id
   join app_finance.financial_product_catalog p on p.id = v.product_id
   where p.issuer_name = 'Audit Bank'),
  1,
  'source provenance belongs to the exact created version'
);

select throws_ok(
  $$update app_finance.financial_product_catalog_sources
    set title = 'rewritten history'$$,
  'catalog version sources are immutable',
  'historical source provenance cannot be updated'
);
select throws_ok(
  $$delete from app_finance.financial_product_catalog_sources$$,
  'catalog version sources are immutable',
  'historical source provenance cannot be deleted'
);
select throws_ok(
  $$update app_finance.financial_product_catalog_versions
    set effective_until = current_date$$,
  'current catalog version end date cannot be changed',
  'current version validity cannot be rewritten outside supersession'
);

select throws_ok(
  $$select app_private.assert_catalog_public_payload(
    jsonb_set(
      (pg_temp.audit_payload(
        (select id from app_finance.catalog_research_queue
         where issuer_name = 'Audit Bank' limit 1)
      ) -> 'research'),
      '{conflicts}',
      '[{"field":"defaultDueDay","userValue":"18","officialValue":"20"}]'
    )
  )$$,
  'private or user-provided data is forbidden in the global catalog',
  'catalog rejects user-provided conflict values'
);
select throws_ok(
  $$select app_private.assert_catalog_public_payload(
    jsonb_set(
      (pg_temp.audit_payload(
        (select id from app_finance.catalog_research_queue
         where issuer_name = 'Audit Bank' limit 1)
      ) -> 'research'),
      '{unsupportedFindings}',
      '[{"description":"4111 1111 1111 1111","note":""}]'
    )
  )$$,
  'credential-like or card-number-like content is forbidden in the global catalog',
  'catalog rejects PAN-like content hidden under an otherwise valid field'
);
select throws_ok(
  $$select app_private.assert_catalog_public_payload(
    jsonb_set(
      (pg_temp.audit_payload(
        (select id from app_finance.catalog_research_queue
         where issuer_name = 'Audit Bank' limit 1)
      ) -> 'research'),
      '{accountForm,transactions}',
      '{"value":"public-looking","status":"probable","confidence":"low","sourceIds":[]}'
    )
  )$$,
  'unknown catalog value field',
  'catalog rejects fields outside the public product contract'
);
select throws_ok(
  $$select app_private.assert_catalog_public_payload(
    jsonb_set(
      (pg_temp.audit_payload(
        (select id from app_finance.catalog_research_queue
         where issuer_name = 'Audit Bank' limit 1)
      ) -> 'research'),
      '{accountForm,defaultDueDay,sourceIds}',
      '[]'
    )
  )$$,
  'verified catalog values require official source provenance',
  'verified values require exact official provenance'
);

set local role authenticated;
set local request.jwt.claims to
  '{"sub":"00000000-0000-4000-8000-00000000ca01","role":"authenticated"}';
select is(
  (select count(*)::integer from app_finance.catalog_search(
    'credit_card', 'EG', 'Audit Bank', 'Secure Card', 'Platinum', 'visa', 'EGP'
  )),
  0,
  'catalog does not guess when an optional product discriminator mismatches'
);
select is(
  (select count(*)::integer from app_finance.catalog_search(
    'credit_card', 'EG', 'Audit Bank', 'Secure Card', 'Gold', 'visa', 'EGP'
  )),
  1,
  'catalog returns an exact optional-discriminator match'
);

set local role postgres;
select throws_ok(
  $$select * from app_finance.record_catalog_automation_heartbeat(
    E'catalog-task\nBearer secret'
  )$$,
  'invalid task name',
  'heartbeat rejects arbitrary text and control characters'
);

select * from app_finance.enqueue_catalog_research_automation(
  'bnpl', 'EG', 'Retry Audit', 'Retry Plan', null, null, 'EGP',
  'https://retry.example', 'manual_review', 1000
);
set local role service_role;
create temp table catalog_retry_lease as
select * from app_finance.get_catalog_research_work(1);
select is(
  (select queue_status::text from app_finance.fail_catalog_research_work(
    (select queue_item_id from catalog_retry_lease),
    'Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature sk-secretsecretsecret 4111111111111111'
  )),
  'queued',
  'failed work remains retryable below max attempts'
);

set local role postgres;
select is(
  (select last_error from app_finance.catalog_research_queue
   where issuer_name = 'Retry Audit'),
  'catalog research failed',
  'worker failures persist only a fixed safe category'
);

select is(
  (select count(*) from app_finance.accounts),
  (select accounts from catalog_financial_state_before),
  'catalog paths cannot create or modify accounts'
);
select is(
  (select count(*) from app_finance.financial_transactions),
  (select transactions from catalog_financial_state_before),
  'catalog paths cannot create transactions or balances'
);
select is(
  (select count(*) from app_finance.credit_card_statement_cycles),
  (select statements from catalog_financial_state_before),
  'catalog paths cannot create statements'
);
select is(
  (select count(*) from app_finance.installment_plans),
  (select installments from catalog_financial_state_before),
  'catalog paths cannot create installments'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app_finance', 'app_private')
      and p.proname like '%catalog%'
      and pg_catalog.pg_get_functiondef(p.oid) ~* '\\mexecute\\M'
  ),
  'catalog functions contain no dynamic SQL execution'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'app_finance'
      and indexname = 'catalog_research_queue_product_id_idx'
  ),
  'catalog queue product foreign key is indexed'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app_finance', 'app_private')
      and p.proname like '%catalog%'
      and p.prosecdef
      and coalesce(array_to_string(p.proconfig, ','), '') !~ 'search_path='
  ),
  'all catalog SECURITY DEFINER functions have an explicit search path'
);

select * from finish();
rollback;
