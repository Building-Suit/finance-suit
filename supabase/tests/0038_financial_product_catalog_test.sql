begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- Catalog v1's table/history foundation remains in place. Behavioral and
-- contract coverage moved to 0042_global_catalog_v2_test.sql.
select has_table('app_finance', 'financial_product_catalog',
  'country-market catalog table remains available');
select has_table('app_finance', 'financial_product_catalog_versions',
  'immutable product versions remain available');
select has_table('app_finance', 'financial_product_catalog_sources',
  'version source provenance remains available');
select has_table('app_finance', 'catalog_research_queue',
  'transactional research queue remains available');
select has_table('app_finance', 'catalog_issuers',
  'v2 normalized issuers are available');
select has_table('app_finance', 'catalog_canonical_products',
  'v2 canonical products are available');
select has_table('app_finance', 'catalog_issuer_markets',
  'v2 issuer markets are available');
select is(app_finance.get_catalog_research_contract() ->> 'contractVersion',
  'finance-card-catalog-v2', 'the active write contract is v2');
select is((select curator_batch_size from app_finance.catalog_configuration),
  25, 'curator batch default is 25');
select is((select curator_max_batch_size from app_finance.catalog_configuration),
  50, 'curator batch hard maximum is 50');

select * from finish();
rollback;
