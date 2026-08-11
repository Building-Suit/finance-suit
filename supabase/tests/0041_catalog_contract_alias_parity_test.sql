begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

select has_table('app_finance','financial_product_catalog_aliases','trusted alias table exists');
select has_function('app_finance','resolve_catalog_research_alias',array['uuid','uuid'],'alias RPC exists');
select ok((select relrowsecurity from pg_class where oid='app_finance.financial_product_catalog_aliases'::regclass),'alias RLS is enabled');
select ok(not has_table_privilege('anon','app_finance.financial_product_catalog_aliases','insert'),'anon cannot write aliases');
select ok(not has_table_privilege('authenticated','app_finance.financial_product_catalog_aliases','insert'),'authenticated cannot write aliases');
select ok(not has_function_privilege('anon','app_finance.resolve_catalog_research_alias(uuid,uuid)','execute'),'anon cannot resolve aliases');
select ok(not has_function_privilege('authenticated','app_finance.resolve_catalog_research_alias(uuid,uuid)','execute'),'authenticated cannot resolve aliases');
select ok(has_function_privilege('service_role','app_finance.resolve_catalog_research_alias(uuid,uuid)','execute'),'service role can resolve aliases');
create temp table alias_financial_state_before as select count(*) accounts from app_finance.accounts;

create or replace function pg_temp.unknown_wrapper() returns jsonb language sql immutable as
$$select '{"value":null,"status":"unknown","confidence":null,"sourceIds":[]}'::jsonb$$;
create or replace function pg_temp.contract_research(p_issuer text default 'Canonical Bank',p_product text default 'World Card')
returns jsonb language sql stable as $$
with c as(select app_finance.get_catalog_research_contract() j),
p as(select jsonb_object_agg(f,pg_temp.unknown_wrapper()) o from c,jsonb_array_elements_text(c.j#>'{productValueFields,required}') f),
a as(select jsonb_object_agg(f,pg_temp.unknown_wrapper()) o from c,jsonb_array_elements_text(c.j#>'{accountFormValueFields,required}') f)
select jsonb_build_object(
 'product',jsonb_set(jsonb_set(p.o,'{issuerName}',jsonb_build_object('value',p_issuer,'status','verified','confidence','high','sourceIds',jsonb_build_array('official'))),'{productName}',jsonb_build_object('value',p_product,'status','verified','confidence','high','sourceIds',jsonb_build_array('official'))),
 'accountForm',a.o,'rules','[]'::jsonb,'installmentTenors','[]'::jsonb,
 'sources',jsonb_build_array(jsonb_build_object('id','official','url','https://canonical.example/card','title','Official card','officialDomain',true,'publishedDate',null,'effectiveDate',null)),
 'unresolvedRequiredFields','[]'::jsonb,'conflicts','[]'::jsonb,'unsupportedFindings','[]'::jsonb)
from p,a;
$$;

select is((app_finance.get_catalog_research_contract()->'productValueFields'->'required')::text,
 '["issuerName", "productName", "tier", "network", "currencyCode"]','contract exposes exact product fields');
select is((app_finance.get_catalog_research_contract()->'accountFormValueFields'->'required')::text,
 '["suggestedName", "creditLimitMinor", "defaultDueDay", "statementDay", "minPaymentMethod", "minPaymentFixedMinor", "minPaymentBasisPoints"]','contract exposes exact account-form fields');
select lives_ok($$select app_private.assert_catalog_public_payload(pg_temp.contract_research())$$,'contract-built complete payload passes validator');
select lives_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{accountForm,suggestedName}',pg_temp.unknown_wrapper()))$$,'accountForm suggestedName is accepted');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{product,suggestedName}',pg_temp.unknown_wrapper()))$$,'unknown catalog value field','product suggestedName is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{product,extra}',pg_temp.unknown_wrapper()))$$,'unknown catalog value field','undeclared product field is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{accountForm,extra}',pg_temp.unknown_wrapper()))$$,'unknown catalog value field','undeclared account-form field is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{product}',(pg_temp.contract_research()->'product')-'tier'))$$,'required catalog values are missing','missing product field is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{accountForm}',(pg_temp.contract_research()->'accountForm')-'statementDay'))$$,'required catalog values are missing','missing account-form field is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{accountForm,statementDay}','{"value":null,"status":"unknown","confidence":null,"sourceIds":[],"extra":1}'))$$,'malformed researched value: statementDay','malformed unknown wrapper is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{accountForm,creditLimitMinor,value}','500000'))$$,'personal credit limit is forbidden in the global catalog','personal credit limit is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{product,tier}',jsonb_build_object('value','Gold','status','probable','confidence','medium','sourceIds',jsonb_build_array('missing'))))$$,'research field references an unknown source identifier','unknown source is rejected');
select throws_ok($$select app_private.assert_catalog_public_payload(jsonb_set(pg_temp.contract_research(),'{product,tier}',jsonb_build_object('value','Gold','status','verified','confidence','high','sourceIds','[]'::jsonb)))$$,'verified catalog values require official source provenance','verified without official source is rejected');

insert into app_finance.financial_product_catalog(account_type,country_code,issuer_name,product_name,tier,network,currency_code,identity_key,status,last_checked_at,last_changed_at)
values('credit_card','EG','Commercial International Bank (CIB)','Gold Credit Card',null,null,null,'pending','active',now(),now()) returning id as product_id \gset
insert into app_finance.financial_product_catalog_versions(product_id,version_number,contract_version,research_status,research_payload,content_hash,verified_at)
values(:'product_id',1,'finance-card-catalog-v1','resolved',pg_temp.contract_research('Commercial International Bank (CIB)','Gold Credit Card'),repeat('a',64),now());
select is((select count(*)::integer from app_finance.financial_product_catalog_versions where product_id=:'product_id'),1,'canonical version exists before alias resolution');

select * from app_finance.enqueue_catalog_research_automation('credit_card','EG','CIB','Gold',null,null,null,null,'manual_review',900) \gset
set local role service_role;
select * from app_finance.get_catalog_research_work(1);
select is((select queue_status::text from app_finance.resolve_catalog_research_alias(:'queue_item_id',:'product_id')),'completed','trusted alias resolution succeeds');
select is((select queue_status::text from app_finance.resolve_catalog_research_alias(:'queue_item_id',:'product_id')),'completed','repeat alias resolution is idempotent');
set local role postgres;
select is((select status::text from app_finance.catalog_research_queue where id=:'queue_item_id'),'completed','alias queue item completes');
select is((select count(*)::integer from app_finance.financial_product_catalog_versions where product_id=:'product_id'),1,'alias creates no catalog version');
select is((select count(*) from app_finance.accounts),(select accounts from alias_financial_state_before),'alias creates no financial account');
select is((select issuer_name from app_finance.catalog_search('credit_card','EG','CIB','Gold',null,null,null)),'Commercial International Bank (CIB)','exact alias search returns canonical product');
select cmp_ok((select match_quality from app_finance.catalog_search('credit_card','EG','CIB','Gold',null,null,null)),'>=',80,'exact alias has confident score');
select is((select count(*)::integer from app_finance.catalog_search('credit_card','EG','Commercial International Bank (CIB)','Gold Credit Card',null,null,null)),1,'canonical search still works');
select is((select count(*)::integer from app_finance.catalog_search('credit_card','EG','CIB','Unrelated Platinum',null,null,null)),0,'similar unrelated card does not false-match');

insert into app_finance.catalog_research_queue(account_type,country_code,issuer_name,product_name,identity_key,work_key,reason,status,leased_at,lease_expires_at)
values('bnpl','EG','CIB','Gold BNPL','pending','pending','manual_review','leased',now(),now()+interval '10 minutes') returning id as mismatch_type_id \gset
insert into app_finance.catalog_research_queue(account_type,country_code,issuer_name,product_name,identity_key,work_key,reason,status,leased_at,lease_expires_at)
values('credit_card','US','CIB','Gold US','pending','pending','manual_review','leased',now(),now()+interval '10 minutes') returning id as mismatch_country_id \gset
select throws_ok(format('select * from app_finance.resolve_catalog_research_alias(%L,%L)', :'mismatch_type_id', :'product_id'),'alias account type does not match canonical product','account-type mismatch is rejected');
select throws_ok(format('select * from app_finance.resolve_catalog_research_alias(%L,%L)', :'mismatch_country_id', :'product_id'),'alias country does not match canonical product','country mismatch is rejected');
insert into app_finance.financial_product_catalog(account_type,country_code,issuer_name,product_name,identity_key,status)
values('credit_card','EG','Inactive Bank','Inactive Card','pending','retired') returning id as inactive_id \gset
insert into app_finance.catalog_research_queue(account_type,country_code,issuer_name,product_name,identity_key,work_key,reason,status,leased_at,lease_expires_at)
values('credit_card','EG','Old','Retired','pending','pending','manual_review','leased',now(),now()+interval '10 minutes') returning id as inactive_queue_id \gset
select throws_ok(format('select * from app_finance.resolve_catalog_research_alias(%L,%L)', :'inactive_queue_id', :'inactive_id'),'canonical catalog product must be active','inactive canonical product is rejected');
insert into app_finance.financial_product_catalog(account_type,country_code,issuer_name,product_name,identity_key,status)
values('credit_card','EG','Other Bank','Other Card','pending','active') returning id as other_id \gset
select throws_ok(format('insert into app_finance.financial_product_catalog_aliases(product_id,account_type,country_code,issuer_alias,product_alias,normalized_issuer_alias,normalized_product_alias) values(%L,''credit_card'',''EG'',''CIB'',''Gold'',''pending'',''pending'')', :'other_id'),'23505',null,'same alias cannot map to two products');
select is((select research_payload->'product' ? 'tier' from app_finance.financial_product_catalog_versions where product_id=:'product_id'),true,'existing catalog row remains readable');

select * from finish();
rollback;
