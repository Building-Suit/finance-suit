begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.catalog_issuers'::regclass),
  'issuer RLS is enabled');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.catalog_canonical_products'::regclass),
  'canonical-product RLS is enabled');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.catalog_issuer_markets'::regclass),
  'issuer-market RLS is enabled');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.catalog_issuer_market_versions'::regclass),
  'issuer-market version RLS is enabled');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.catalog_issuer_market_sources'::regclass),
  'issuer-market source RLS is enabled');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.catalog_version_verifications'::regclass),
  'verification-history RLS is enabled');
select ok(not has_table_privilege('service_role',
  'app_finance.catalog_issuers', 'select'),
  'service role has no arbitrary catalog table reads');
select ok(not has_table_privilege('authenticated',
  'app_finance.catalog_canonical_products', 'select'),
  'authenticated users have no direct catalog table reads');
select ok(not has_function_privilege('authenticated',
  'app_finance.upsert_catalog_research_result(jsonb)', 'execute'),
  'ordinary users cannot write researched results');
select ok(has_function_privilege('service_role',
  'app_finance.upsert_catalog_research_result(jsonb)', 'execute'),
  'service role can use the sole result writer');
select ok(not has_function_privilege('anon',
  'app_finance.catalog_status_summary()', 'execute'),
  'anonymous callers cannot inspect curator operations');
select ok(has_function_privilege('service_role',
  'app_finance.catalog_status_summary()', 'execute'),
  'service role can inspect safe aggregate status');
select ok(not has_function_privilege('service_role',
  'app_finance.catalog_search(app_finance.account_type,text,text,text,text,text,text)',
  'execute'), 'curator access is limited to the approved RPC surface');
select ok((select p.prosecdef from pg_proc p
  where p.oid = 'app_finance.upsert_catalog_research_result(jsonb)'::regprocedure),
  'result writing uses a reviewed definer function');
select is((select p.proconfig[1] from pg_proc p
  where p.oid = 'app_finance.upsert_catalog_research_result(jsonb)'::regprocedure),
  'search_path=""', 'the result writer pins an empty search path');

select * from finish();
rollback;
