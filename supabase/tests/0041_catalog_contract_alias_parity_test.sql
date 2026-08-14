begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- Aliases remain readable migration history, but they are not part of the
-- approved v2 scheduled-curator surface.
select has_table('app_finance', 'financial_product_catalog_aliases',
  'legacy alias history remains available');
select ok((select relrowsecurity from pg_class
  where oid = 'app_finance.financial_product_catalog_aliases'::regclass),
  'legacy aliases keep RLS enabled');
select ok(not has_table_privilege('authenticated',
  'app_finance.financial_product_catalog_aliases', 'insert'),
  'ordinary users cannot write aliases directly');
select ok(not has_table_privilege('service_role',
  'app_finance.financial_product_catalog_aliases', 'insert'),
  'the curator cannot write aliases directly');
select ok(not has_function_privilege('service_role',
  'app_finance.resolve_catalog_research_alias(uuid,uuid)', 'execute'),
  'manual alias resolution is outside the scheduled v2 surface');
select ok(not has_function_privilege('authenticated',
  'app_finance.resolve_catalog_research_alias(uuid,uuid)', 'execute'),
  'ordinary users cannot resolve aliases');
select ok(has_function_privilege('authenticated',
  'app_finance.catalog_browse(app_finance.account_type,text,text)', 'execute'),
  'authenticated app users can browse the published catalog');
select ok(has_function_privilege('authenticated',
  'app_finance.catalog_search(app_finance.account_type,text,text,text,text,text,text)',
  'execute'), 'legacy exact search remains available during app migration');
select ok(app_finance.get_catalog_research_contract()
  #> '{productIdentity,required}' @> '["issuerName","productName"]'::jsonb,
  'v2 keeps issuer and product identity explicit');
select ok(app_finance.get_catalog_research_contract()
  #> '{researchPayload,requiredSections}' @> '["sources","conflicts"]'::jsonb,
  'v2 keeps provenance and conflicts explicit');

select * from finish();
rollback;
